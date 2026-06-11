--!strict
-- Per-account inbox API for the Mail system: the single clean surface for reading, sending, claiming,
-- and deleting mail, plus the sanitised list the mailbox UI renders. Mirrors Inventory.luau -- the
-- server-only join of profile data to ItemConfig/Monetization, with the raw config never crossing to
-- the client (only resolved display fields do).
--
-- DELIVERY:
--   * Personal  -- Mail.sendToPlayer(player, spec): appended straight to the online player's profile.
--   * Broadcast -- Mail.broadcast(spec): posted to the shared MailBroadcast store, then materialized
--                  into every online player's inbox here (offline / future joiners pick it up via
--                  Mail.syncBroadcasts at load + MailServer's re-sync loop).
--
-- REWARD ROUTING at claim time (all-or-nothing, see Mail.claim):
--   Item  -> the ACTIVE slot (Inventory.add, respects maxAmount)   "whatever slot they claim on"
--   Spins -> account-wide Shared.Spins
--   Pass  -> Monetization.grantPass (persistent, idempotent)
--
-- spec = { from, subject, body, rewards, expiresInDays? } (expiry defaults to 7 days). rewards is a
-- list of { kind = "Item"|"Spins"|"Pass", itemId?/passKey?, amount? }.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Inventory = require(ServerStorage.Modules.Inventory)
local ItemConfig = require(ServerStorage.Modules.ItemConfig)
local MailBroadcast = require(ServerStorage.Modules.MailBroadcast)
local Manager = require(ServerStorage.Modules.Manager)
local Monetization = require(ServerStorage.Modules.Monetization)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Template = require(ServerStorage.Modules.TemplateData)

local DAY_SECONDS = 86400
local DEFAULT_EXPIRY_DAYS = 7
-- Placeholder icon for non-item rewards (Spins/Pass); swap in real assets later, like ItemConfig's images.
local PLACEHOLDER_IMAGE = "rbxassetid://0"

local Mail = {}

export type Spec = {
	from: string?,
	subject: string?,
	body: string?,
	rewards: { Template.MailReward }?,
	expiresInDays: number?,
}

-- A reward resolved for the client: enough to render an inventory-style cell. Raw config never crosses.
export type ClientReward = {
	kind: string,
	image: string,
	displayName: string,
	rarity: string?, -- Items only (drives the rarity border); nil for Spins/Pass
	count: number,
	label: string,
}

export type ClientMail = {
	id: string,
	from: string,
	subject: string,
	body: string,
	sentAt: number,
	expiresAt: number,
	read: boolean,
	claimed: boolean,
	rewards: { ClientReward },
}

-- The account-wide inbox array, or nil if the profile isn't loaded.
local function mailsArray(player: Player): { Template.MailEntry }?
	local profile = Manager.getProfile(player)
	if not profile then
		return nil
	end
	if typeof(profile.Data.Mail) ~= "table" then
		profile.Data.Mail = {}
	end
	return profile.Data.Mail
end

local function findById(arr: { Template.MailEntry }, id: string): Template.MailEntry?
	for _, m in arr do
		if m.id == id then
			return m
		end
	end
	return nil
end

-- Drop expired (or malformed) entries in place.
local function prune(arr: { Template.MailEntry }, now: number)
	for i = #arr, 1, -1 do
		local m = arr[i]
		if typeof(m) ~= "table" or typeof(m.expiresAt) ~= "number" or m.expiresAt <= now then
			table.remove(arr, i)
		end
	end
end

-- Independent copy of a rewards list so the same table is never aliased across profiles (broadcasts) or
-- mutated by a caller after sending.
local function copyRewards(rewards: { Template.MailReward }?): { Template.MailReward }
	local out: { Template.MailReward } = {}
	if typeof(rewards) == "table" then
		for _, r in rewards do
			if typeof(r) == "table" then
				table.insert(out, { kind = r.kind, itemId = r.itemId, passKey = r.passKey, amount = r.amount })
			end
		end
	end
	return out
end

local function rewardAmount(r: Template.MailReward): number
	return if typeof(r.amount) == "number" and r.amount > 0 then math.floor(r.amount) else 1
end

local function resolveReward(r: Template.MailReward): ClientReward
	local amount = rewardAmount(r)
	if r.kind == "Item" and typeof(r.itemId) == "string" then
		local def = ItemConfig.get(r.itemId)
		if def then
			return {
				kind = "Item",
				image = def.image,
				displayName = def.displayName,
				rarity = def.rarity :: string,
				count = amount,
				label = def.displayName,
			}
		end
		return {
			kind = "Item",
			image = PLACEHOLDER_IMAGE,
			displayName = r.itemId,
			rarity = "Common",
			count = amount,
			label = r.itemId,
		}
	elseif r.kind == "Spins" then
		return {
			kind = "Spins",
			image = PLACEHOLDER_IMAGE,
			displayName = "Race Spins",
			count = amount,
			label = "Race Spins",
		}
	elseif r.kind == "Pass" and typeof(r.passKey) == "string" then
		local name = Monetization.getPassName(r.passKey) or r.passKey
		return { kind = "Pass", image = PLACEHOLDER_IMAGE, displayName = name, count = 1, label = name }
	end
	return {
		kind = tostring(r.kind),
		image = PLACEHOLDER_IMAGE,
		displayName = "Reward",
		count = amount,
		label = "Reward",
	}
end

-- The player's full mailbox view (newest first), with rewards resolved for display. Prunes expired mail
-- as a side effect (cheap cleanup -- the inbox should never show dead mail).
function Mail.list(player: Player): { ClientMail }
	local arr = mailsArray(player)
	if not arr then
		return {}
	end
	prune(arr, os.time())
	local out: { ClientMail } = {}
	for _, m in arr do
		local rewards: { ClientReward } = {}
		for _, r in m.rewards do
			table.insert(rewards, resolveReward(r))
		end
		table.insert(out, {
			id = m.id,
			from = m.from,
			subject = m.subject,
			body = m.body,
			sentAt = m.sentAt,
			expiresAt = m.expiresAt,
			read = m.read == true,
			claimed = m.claimed == true,
			rewards = rewards,
		})
	end
	table.sort(out, function(a, b)
		return a.sentAt > b.sentAt
	end)
	return out
end

-- Push the fresh list to the player (drives the live mailbox + the unread badge). Fired after every
-- mutation; the client derives the unread count from the list.
local function push(player: Player)
	Remotes.MailChanged:FireClient(player, Mail.list(player))
end

local function expiryFrom(now: number, expiresInDays: number?): number
	local days = if typeof(expiresInDays) == "number" and expiresInDays > 0 then expiresInDays else DEFAULT_EXPIRY_DAYS
	return now + math.floor(days * DAY_SECONDS)
end

-- Append a personal mail to the player's inbox (no push). Returns the new entry, or nil if no profile.
function Mail.add(player: Player, spec: Spec): Template.MailEntry?
	local arr = mailsArray(player)
	if not arr then
		return nil
	end
	local now = os.time()
	local entry: Template.MailEntry = {
		id = HttpService:GenerateGUID(false),
		from = tostring(spec.from or "System"),
		subject = tostring(spec.subject or "Mail"),
		body = tostring(spec.body or ""),
		sentAt = now,
		expiresAt = expiryFrom(now, spec.expiresInDays),
		rewards = copyRewards(spec.rewards),
		read = false,
		claimed = false,
	}
	table.insert(arr, entry)
	return entry
end

-- Deliver a personal mail to an online player (append + push). The main entry point for codes,
-- world-boss drops, and any per-player reward.
function Mail.sendToPlayer(player: Player, spec: Spec): Template.MailEntry?
	local entry = Mail.add(player, spec)
	if entry then
		push(player)
	end
	return entry
end

-- Materialize active broadcasts the player hasn't seen yet into their inbox (deduped via
-- Shared.SeenBroadcasts so a broadcast lands once per account, survives deletion, and never re-appears).
-- Returns how many were newly added.
function Mail.syncBroadcasts(player: Player): number
	local profile = Manager.getProfile(player)
	if not profile then
		return 0
	end
	local shared = profile.Data.Shared
	if typeof(shared.SeenBroadcasts) ~= "table" then
		shared.SeenBroadcasts = {}
	end
	local seen = shared.SeenBroadcasts
	local arr = mailsArray(player)
	if not arr then
		return 0
	end
	local added = 0
	for _, b in MailBroadcast.activeBroadcasts() do
		if not seen[b.id] then
			seen[b.id] = true
			table.insert(arr, {
				id = HttpService:GenerateGUID(false),
				broadcastId = b.id,
				from = b.from,
				subject = b.subject,
				body = b.body,
				sentAt = b.sentAt,
				expiresAt = b.expiresAt,
				rewards = copyRewards(b.rewards),
				read = false,
				claimed = false,
			})
			added += 1
		end
	end
	if added > 0 then
		push(player)
	end
	return added
end

-- Post a broadcast to the shared store, then materialize it into every online player's inbox on this
-- server immediately (other servers / offline / future joiners pick it up via syncBroadcasts). Returns
-- (broadcastId, nil) or (nil, err).
function Mail.broadcast(spec: Spec): (string?, string?)
	local id, err = MailBroadcast.post(spec)
	if not id then
		return nil, err
	end
	for _, player in Players:GetPlayers() do
		if Manager.getProfile(player) then
			Mail.syncBroadcasts(player)
		end
	end
	return id, nil
end

function Mail.markRead(player: Player, id: string): boolean
	local arr = mailsArray(player)
	if not arr then
		return false
	end
	local entry = findById(arr, id)
	if not entry or entry.read then
		return false
	end
	entry.read = true
	push(player)
	return true
end

function Mail.delete(player: Player, id: string): boolean
	local arr = mailsArray(player)
	if not arr then
		return false
	end
	for i, m in arr do
		if m.id == id then
			table.remove(arr, i)
			push(player)
			return true
		end
	end
	return false
end

-- Claim every reward on a mail, all-or-nothing. Items go to the ACTIVE slot (rejected up front if any
-- won't fit, so a half-claim can't happen); Spins -> Shared; Pass -> grantPass. The mail stays in the
-- inbox marked claimed (re-readable) until deleted or expired. Returns (ok, reason?).
function Mail.claim(player: Player, id: string): (boolean, string?)
	local arr = mailsArray(player)
	if not arr then
		return false, "Profile not loaded"
	end
	prune(arr, os.time())
	local entry = findById(arr, id)
	if not entry then
		return false, "Mail not found or expired"
	end
	if entry.claimed then
		return false, "Already claimed"
	end

	-- Partition rewards by routing.
	local itemRewards: { { itemId: string, amount: number } } = {}
	local spinTotal = 0
	local passKeys: { string } = {}
	for _, r in entry.rewards do
		local amount = rewardAmount(r)
		if r.kind == "Item" and typeof(r.itemId) == "string" then
			table.insert(itemRewards, { itemId = r.itemId, amount = amount })
		elseif r.kind == "Spins" then
			spinTotal += amount
		elseif r.kind == "Pass" and typeof(r.passKey) == "string" then
			table.insert(passKeys, r.passKey)
		end
	end

	-- Item rewards need an active slot with room. Pre-check against maxAmount, summing duplicate ids.
	if #itemRewards > 0 then
		if not Manager.getActiveSlot(player) then
			return false, "No active character slot to receive items"
		end
		local projected: { [string]: number } = {}
		for _, ir in itemRewards do
			local def = ItemConfig.get(ir.itemId)
			if not def then
				return false, "Unknown item reward"
			end
			local already = projected[ir.itemId] or Inventory.count(player, ir.itemId)
			local after = already + ir.amount
			if after > def.maxAmount then
				return false, `Not enough room on this slot for {def.displayName} -- make space or switch slots`
			end
			projected[ir.itemId] = after
		end
	end

	-- Feasible: grant everything (no yields between the check and the item/spin grants -> atomic).
	for _, ir in itemRewards do
		Inventory.add(player, ir.itemId, ir.amount)
	end
	if spinTotal > 0 then
		local shared = Manager.getShared(player)
		if shared then
			shared.Spins += spinTotal
		end
	end
	for _, key in passKeys do
		Monetization.grantPass(player, key) -- idempotent: a no-op if already owned
	end

	entry.claimed = true
	if #itemRewards > 0 then
		Remotes.InventoryChanged:FireClient(player, Inventory.list(player))
	end
	push(player)
	return true, nil
end

return Mail
