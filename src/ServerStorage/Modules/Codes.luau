--!strict
-- Redeem-code catalogue + redemption. Server-authoritative: the catalogue lives here and NEVER reaches
-- the client; redemption is one-time per account (Shared.RedeemedCodes); codes are matched
-- case-insensitively with whitespace stripped. Codes NEVER expire -- retire one with active = false so
-- already-redeemed players keep what they got. To add a code, add a row to CODES (key = normalised
-- UPPERCASE, no spaces). Rewards reuse the Mail reward shape (see TemplateData.MailReward).
--
-- DELIVERY (mirrors the Mail system's claim routing, but split by WHEN it lands):
--   * Spins / Pass -- account-wide, granted INSTANTLY on redeem (Shared.Spins += / Monetization.grantPass).
--   * Item         -- sent to the player's mailbox (Mail.sendToPlayer) to claim on whichever slot they
--                     like, exactly like any other mail. The delivery mail uses a long expiry
--                     (CODE_MAIL_EXPIRY_DAYS) so a never-expiring code's reward can't quietly rot.
--
-- REQUIREMENTS (all must pass; each failure returns a player-facing message):
--   races          -- the ACTIVE slot's Race must be one of these. Race-gated codes are SETTINGS-ONLY:
--                     redeeming from the Main Menu box is rejected (you redeem a race code in-game, on the
--                     character it's for -- see the `source` arg). The race check itself is authoritative
--                     against the active slot's Race, so the source flag is only a UX router, not a gate.
--   userIds        -- player.UserId must be listed (a code targeted at one specific player).
--   minBattlePower -- the active slot's BattlePower must be >= this (example of an extensible numeric gate).
--   custom         -- arbitrary predicate (player) -> (ok, message?) for anything the fixed gates can't express.

local ServerStorage = game:GetService("ServerStorage")

local Mail = require(ServerStorage.Modules.Mail)
local Manager = require(ServerStorage.Modules.Manager)
local Monetization = require(ServerStorage.Modules.Monetization)
local Template = require(ServerStorage.Modules.TemplateData)

-- Item-reward mail lingers far longer than ordinary mail: a code never expires, so its delivered reward
-- shouldn't disappear if the player doesn't open their mailbox right away.
local CODE_MAIL_EXPIRY_DAYS = 60
local DEFAULT_FROM = "Project Kaioshin"
local DEFAULT_SUBJECT = "Code Reward"

export type Requirements = {
	races: { string }?,
	userIds: { number }?,
	minBattlePower: number?,
	custom: ((player: Player) -> (boolean, string?))?,
}

type Code = {
	active: boolean,
	rewards: { Template.MailReward },
	requirements: Requirements?,
	-- Optional presentation for the item-delivery mail (falls back to the DEFAULT_* above).
	from: string?,
	subject: string?,
	body: string?,
}

-- Keys MUST be the normalised (UPPERCASE, no spaces) form -- redeem() normalises input the same way.
local CODES: { [string]: Code } = {
	WELCOME = {
		active = true,
		rewards = { { kind = "Spins", amount = 10 } },
	},
	RELEASE = {
		active = true,
		rewards = {
			{ kind = "Spins", amount = 25 },
			{ kind = "Item", itemId = "HerculeStatueGold", amount = 1 },
		},
	},
	-- Race-gated example: only redeemable from the in-game Settings box, only by a Saiyan active slot.
	SAIYANPRIDE = {
		active = true,
		rewards = { { kind = "Item", itemId = "HerculeStatueSilver", amount = 1 } },
		requirements = { races = { "Saiyan", "LegendarySuperSaiyan" } },
		subject = "Saiyan Pride",
	},
	-- Targeted example: only the listed user id(s) can redeem it (still one-time, still mail-delivered).
	-- Fill in the real id and flip active = true to use it.
	-- DEVGIFT = {
	-- 	active = true,
	-- 	rewards = { { kind = "Spins", amount = 100 } },
	-- 	requirements = { userIds = { 0 } },
	-- },
}

local Codes = {}

local function normalize(code: string): string
	return (code:gsub("%s+", "")):upper()
end

local function rewardAmount(r: Template.MailReward): number
	return if typeof(r.amount) == "number" and r.amount > 0 then math.floor(r.amount) else 1
end

-- Evaluate a code's requirements. `source` ("Settings" | "MainMenu") lets race-gated codes be
-- restricted to the in-game Settings box. Returns (true) when there are no requirements or all pass,
-- else (false, playerFacingMessage).
local function checkRequirements(player: Player, req: Requirements?, source: string): (boolean, string?)
	if not req then
		return true, nil
	end

	if req.races and #req.races > 0 then
		if source ~= "Settings" then
			return false, "Redeem this code in-game from Settings"
		end
		local slot = Manager.getActiveSlot(player)
		local race = if slot then slot.Race else nil
		local matched = false
		for _, r in req.races do
			if race == r then
				matched = true
				break
			end
		end
		if not matched then
			return false, "This code is for a different race"
		end
	end

	if req.userIds and #req.userIds > 0 then
		local matched = false
		for _, id in req.userIds do
			if player.UserId == id then
				matched = true
				break
			end
		end
		if not matched then
			return false, "This code isn't available on your account"
		end
	end

	if typeof(req.minBattlePower) == "number" then
		local slot = Manager.getActiveSlot(player)
		local bp = if slot then slot.BattlePower else 0
		if bp < req.minBattlePower then
			return false, "Your Battle Power is too low for this code"
		end
	end

	if req.custom then
		local ok, message = req.custom(player)
		if not ok then
			return false, message or "You can't redeem this code"
		end
	end

	return true, nil
end

-- Redeem a code for `player`. `source` is "Settings" (in-game box) or "MainMenu"; anything else is
-- treated as "MainMenu". Returns (ok, playerFacingMessage). On success the message summarises what was
-- granted instantly and whether items were mailed.
function Codes.redeem(player: Player, raw: any, source: any): (boolean, string)
	if typeof(raw) ~= "string" then
		return false, "Invalid code"
	end
	local code = normalize(raw)
	if code == "" then
		return false, "Enter a code"
	end

	local entry = CODES[code]
	if not entry or not entry.active then
		return false, "Invalid code"
	end

	local shared = Manager.getShared(player)
	if not shared then
		return false, "Still loading..."
	end
	if typeof(shared.RedeemedCodes) ~= "table" then
		shared.RedeemedCodes = {}
	end
	if shared.RedeemedCodes[code] then
		return false, "You've already redeemed this code"
	end

	local src = if source == "Settings" then "Settings" else "MainMenu"
	local ok, why = checkRequirements(player, entry.requirements, src)
	if not ok then
		return false, why or "You can't redeem this code"
	end

	-- Passed. Mark redeemed FIRST so a second request can't double-grant (none of the grants below
	-- yield, so the mark and the grants are effectively atomic).
	shared.RedeemedCodes[code] = true

	-- Partition rewards: account-wide (instant) vs items (mailed).
	local spinTotal = 0
	local passKeys: { string } = {}
	local itemRewards: { Template.MailReward } = {}
	for _, r in entry.rewards do
		local amount = rewardAmount(r)
		if r.kind == "Spins" then
			spinTotal += amount
		elseif r.kind == "Pass" and typeof(r.passKey) == "string" then
			table.insert(passKeys, r.passKey)
		elseif r.kind == "Item" and typeof(r.itemId) == "string" then
			table.insert(itemRewards, { kind = "Item", itemId = r.itemId, amount = amount })
		end
	end

	-- Instant: account-wide rewards land immediately.
	if spinTotal > 0 then
		shared.Spins += spinTotal
	end
	for _, key in passKeys do
		Monetization.grantPass(player, key) -- idempotent: a no-op if already owned
	end

	-- Items go to the mailbox, claimed on whichever slot the player chooses (room-checked at claim time).
	if #itemRewards > 0 then
		Mail.sendToPlayer(player, {
			from = entry.from or DEFAULT_FROM,
			subject = entry.subject or DEFAULT_SUBJECT,
			body = entry.body
				or `Thanks for redeeming "{code}"! Claim the rewards below -- items land on whichever character slot is active when you claim.`,
			rewards = itemRewards,
			expiresInDays = CODE_MAIL_EXPIRY_DAYS,
		})
	end

	-- Summarise what happened for the redeem toast.
	local parts: { string } = {}
	if spinTotal > 0 then
		table.insert(parts, `+{spinTotal} Spins`)
	end
	for _, key in passKeys do
		table.insert(parts, Monetization.getPassName(key) or "Game Pass")
	end
	if #itemRewards > 0 then
		table.insert(parts, "Items sent to your mailbox")
	end
	local summary = if #parts > 0 then table.concat(parts, ", ") else "Reward granted"
	return true, `Redeemed! {summary}.`
end

return Codes
