--!strict
-- Central monetization registry + purchase engine. This is the single place that HOLDS the info for
-- every Developer Product and Game Pass in the game and handles buying them -- nothing else (no UI).
--
-- Game-pass ownership is stored PERSISTENTLY in profile.Data.Shared.Passes (a { [key]: true } map),
-- not just read live from Roblox. Making ownership data we control is what lets players GIFT passes to
-- one another. Perk effects are read elsewhere via Monetization.ownsPass (e.g. the Race Roller checks
-- "InfiniteSpins") -- never from MarketplaceService.
--
-- GIFTING (paid model): a player buys a "Gift X" Developer Product, having chosen a recipient; the
-- linked pass is delivered to that recipient (this server, another server, or offline) via a persisted
-- ProfileStore message. The recipient is captured by startGift just before the prompt; ProcessReceipt
-- reads it back and delivers. Dev Product grants are de-duplicated with Shared.PurchaseIds so a receipt
-- is never granted twice.
--
-- ADD AN ITEM: drop an entry in PRODUCTS, PASSES or GIFTS below with its Creator-Dashboard id. A
-- product needs a grant(); a pass just needs the id; a gift links a gift-product id to a pass key.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Manager = require(ServerStorage.Modules.Manager)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Template = require(ServerStorage.Modules.TemplateData)

local LOG = "[Monetization]"
-- Roblox only re-delivers recent receipts, so a small rolling log is plenty for de-duping.
local PURCHASE_LOG_CAP = 100
-- A receipt can arrive while the buyer's profile is still loading; wait this long before asking Roblox
-- to re-deliver later (returning NotProcessedYet).
local PROFILE_WAIT_TIMEOUT = 30
local GIFT_MESSAGE = "GiftPass"

type Profile = Manager.ActiveProfile

-- The fields of MarketplaceService receiptInfo this module reads (it carries more; these are enough).
export type ReceiptInfo = {
	PlayerId: number,
	ProductId: number,
	PurchaseId: string,
	CurrencySpent: number,
}

export type ProductDef = {
	id: number,
	name: string?,
	desc: string?,
	-- Award the product by mutating profile.Data. Runs inside ProcessReceipt and persists atomically
	-- with the purchase log, so keep it to data mutations (currency, unlocks, slot fields).
	grant: (player: Player, profile: Profile, receiptInfo: ReceiptInfo) -> (),
}

export type PassDef = {
	id: number,
	name: string?,
	desc: string?,
	-- Optional side effect run the first time the pass is owned/gifted (the flag itself is the perk;
	-- most passes need nothing here -- the Race Roller etc. just check ownsPass).
	onGranted: ((player: Player, profile: Profile) -> ())?,
}

export type GiftDef = {
	id: number, -- the "Gift X" Developer Product id (the buyer pays this, per gift)
	passKey: string, -- which PASSES entry it grants to the recipient
	name: string?,
	desc: string?,
}

-- ============================================================================================
-- REGISTRY -- the info this module holds. Real ids from the Creator Dashboard.
-- ============================================================================================

local PRODUCTS: { [string]: ProductDef } = {
	RaceSpins25 = {
		id = 3539525749,
		name = "25 Race Spins",
		desc = "Adds 25 Spins to your account.",
		grant = function(_player, profile, _receiptInfo)
			profile.Data.Shared.Spins += 25
		end,
	},
	SlotPurchase = {
		id = 3415213163,
		name = "Character Slot",
		desc = "Adds another character slot to your account (up to 5 buyable).",
		grant = function(_player, profile, _receiptInfo)
			-- Always grants (a receipt is never wasted). PurchasedSlots only tracks BUYS so the Slots panel
			-- can stop offering the Buy button at 5; TOTAL slots are intentionally uncapped, since free/race
			-- slots granted elsewhere (Manager.addSlot) can push the count higher. The new slot keeps
			-- Race = "NA" and auto-rolls free the first time it's the active slot on a build (first Play).
			profile.Data.Shared.PurchasedSlots += 1
			table.insert(profile.Data.Slots, Template.newSlot())
		end,
	},
}

local PASSES: { [string]: PassDef } = {
	InfiniteSpins = {
		id = 1721811833,
		name = "Infinite Spins",
		desc = "Roll races without spending Spins.",
	},
	AutoRoller = {
		id = 1722345108,
		name = "AutoRoller",
		desc = "Automatically rolls races for you.",
	},
	InstantSpins = {
		id = 1511074306,
		name = "Instant Spins",
		desc = "Skip the roll animation.",
	},
}

-- Paid gift products: buying one grants the linked pass to a chosen RECIPIENT (not the buyer). Create a
-- "Gift X" Developer Product per pass on the dashboard and paste its id here. Until then each is inert.
local GIFTS: { [string]: GiftDef } = {
	GiftInfiniteSpins = { id = 3603821478, passKey = "InfiniteSpins", name = "Gift: Infinite Spins" },
	GiftAutoRoller = { id = 3603821676, passKey = "AutoRoller", name = "Gift: AutoRoller" },
	GiftInstantSpins = { id = 3603821732, passKey = "InstantSpins", name = "Gift: Instant Spins" },
}

-- ============================================================================================
-- ENGINE
-- ============================================================================================

local Monetization = {}

local inited = false
-- id -> def lookups, built once at init (skipping unconfigured id == 0 entries).
local PRODUCTS_BY_ID: { [number]: ProductDef } = {}
local PASSES_BY_ID: { [number]: { key: string, def: PassDef } } = {}
local GIFTS_BY_ID: { [number]: GiftDef } = {}
-- Buyer userId -> { [giftProductId]: recipientUserId }. Captured at startGift, read back at receipt.
-- In-memory: a server restart between prompt and receipt loses it and the gift falls back to the buyer
-- (so no Robux is wasted, just delivered to the wrong person in that rare window).
local pendingGifts: { [number]: { [number]: number } } = {}

-- True if `player` owns the pass `key` -- bought OR gifted (read from persistent Shared.Passes).
function Monetization.ownsPass(player: Player, key: string): boolean
	local profile = Manager.getProfile(player)
	if not profile then
		return false
	end
	local passes = profile.Data.Shared.Passes
	return passes ~= nil and passes[key] == true
end

-- Sets the persistent ownership flag for `key` on `player`. The shared building block behind real
-- purchases, gift delivery and the join-sync. Returns true only if it was newly granted.
function Monetization.grantPass(player: Player, key: string): boolean
	local def = PASSES[key]
	if not def then
		return false
	end
	local profile = Manager.getProfile(player)
	if not profile then
		return false
	end
	local passes = profile.Data.Shared.Passes
	if not passes then
		passes = {}
		profile.Data.Shared.Passes = passes
	end
	if passes[key] then
		return false
	end
	passes[key] = true
	local hook = def.onGranted
	if hook then
		local ok, err = pcall(function()
			hook(player, profile)
		end)
		if not ok then
			warn(`{LOG} onGranted '{key}' failed for {player.Name}: {err}`)
		end
	end
	return true
end

-- Begin a paid gift: record the recipient for the matching gift product, then prompt the buyer to pay.
-- Fired from a recipient-picker via Remotes.RequestGift. Returns ok + a short reason on failure.
function Monetization.startGift(buyer: Player, recipientUserId: number, passKey: string): (boolean, string?)
	if recipientUserId == buyer.UserId then
		return false, "cannot gift to yourself"
	end
	local gift: GiftDef? = nil
	for _, def in GIFTS do
		if def.passKey == passKey then
			gift = def
			break
		end
	end
	if not gift or gift.id <= 0 then
		return false, "gift not available"
	end
	local byBuyer = pendingGifts[buyer.UserId]
	if not byBuyer then
		byBuyer = {}
		pendingGifts[buyer.UserId] = byBuyer
	end
	byBuyer[gift.id] = recipientUserId
	MarketplaceService:PromptProductPurchase(buyer, gift.id)
	return true
end

-- Server-side purchase prompts (there's no in-game shop UI; call these from wherever a buy is
-- triggered, or prompt client-side with the id). No-op for unknown / unconfigured keys.
function Monetization.promptProduct(player: Player, key: string)
	local def = PRODUCTS[key]
	if def and def.id > 0 then
		MarketplaceService:PromptProductPurchase(player, def.id)
	end
end

function Monetization.promptPass(player: Player, key: string)
	local def = PASSES[key]
	if def and def.id > 0 then
		MarketplaceService:PromptGamePassPurchase(player, def.id)
	end
end

function Monetization.prompt(player: Player, key: string)
	if PRODUCTS[key] then
		Monetization.promptProduct(player, key)
	elseif PASSES[key] then
		Monetization.promptPass(player, key)
	end
end

-- The Dev Product id behind a registry key (nil if unknown, 0 if unconfigured). Lets a UI hand the id
-- to the client so it can prompt the purchase itself, without re-hard-coding the id outside this module.
function Monetization.getProductId(key: string): number?
	local def = PRODUCTS[key]
	return if def then def.id else nil
end

-- Display name for a pass key (nil if unknown). Used by the Mail system to label Pass rewards without
-- re-hard-coding pass names outside this module.
function Monetization.getPassName(key: string): string?
	local def = PASSES[key]
	return if def then def.name else nil
end

-- Per-join setup: register the gift-message receiver and fold real Roblox game-pass ownership into the
-- persistent Shared.Passes map. Run before the character builds so a pass perk is known on first spawn.
-- Yields on the ownership web calls.
function Monetization.onProfileLoaded(player: Player)
	local profile = Manager.getProfile(player)
	if not profile then
		return
	end

	-- Receive gifted passes (delivered via ProfileStore messages): live if the gift arrives now, or
	-- replayed at load if it arrived while offline. GiftPass is the only message type, so we ack all.
	(profile :: any):MessageHandler(function(message, processed)
		if type(message) == "table" and message.Type == GIFT_MESSAGE and type(message.PassKey) == "string" then
			Monetization.grantPass(player, message.PassKey)
		end
		processed()
	end)

	for key, def in PASSES do
		if def.id <= 0 then
			continue
		end
		if Monetization.ownsPass(player, key) then
			continue -- already recorded (bought or gifted) -- no need to re-ask Roblox
		end
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.id)
		end)
		if ok then
			if owns then
				Monetization.grantPass(player, key)
			end
		else
			warn(`{LOG} UserOwnsGamePassAsync('{key}') failed for {player.Name}: {owns}`)
		end
	end
end

-- Blocks until the buyer's profile is active, or the timeout elapses / they leave (-> nil, retry later).
local function waitForProfile(player: Player): Profile?
	local elapsed = 0
	while player.Parent == Players do
		local profile = Manager.getProfile(player)
		if profile and profile:IsActive() then
			return profile
		end
		if elapsed >= PROFILE_WAIT_TIMEOUT then
			return nil
		end
		task.wait(0.5)
		elapsed += 0.5
	end
	return nil
end

-- Records a purchaseId on the buyer's rolling log and force-saves. Caller has already applied the award.
local function logAndSave(profile: Profile, log: { string }, purchaseId: string)
	while #log >= PURCHASE_LOG_CAP do
		table.remove(log, 1)
	end
	table.insert(log, purchaseId)
	profile:Save()
end

-- Gift product receipt: deliver the linked pass to the buyer's chosen recipient (idempotent on the
-- buyer's PurchaseIds). The buyer's profile holds the purchase log; the recipient receives via message.
local function processGiftReceipt(receiptInfo: ReceiptInfo, gift: GiftDef): Enum.ProductPurchaseDecision
	local buyer = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not buyer then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local buyerProfile = waitForProfile(buyer)
	if not buyerProfile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local log = buyerProfile.Data.Shared.PurchaseIds
	local purchaseId = tostring(receiptInfo.PurchaseId)
	if table.find(log, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local byBuyer = pendingGifts[buyer.UserId]
	local recipientUserId = if byBuyer then byBuyer[receiptInfo.ProductId] else nil

	if recipientUserId then
		-- Deliver to the recipient's profile wherever they are (this/another server, or offline) via a
		-- persisted message; their MessageHandler sets the pass flag. Idempotent: re-delivery just sets
		-- an already-true flag.
		local ok, delivered = pcall(function()
			return (Manager.PlayerStore :: any):MessageAsync(tostring(recipientUserId), {
				Type = GIFT_MESSAGE,
				PassKey = gift.passKey,
			})
		end)
		if not ok or not delivered then
			warn(`{LOG} gift delivery of '{gift.passKey}' to {recipientUserId} failed; will retry`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if byBuyer then
			byBuyer[receiptInfo.ProductId] = nil
		end
	else
		-- No recipient on record (bought from the store page, or intent lost on restart): grant to the
		-- buyer so the Robux isn't wasted.
		warn(`{LOG} gift '{gift.passKey}' bought by {buyer.Name} with no recipient; granting to buyer`)
		Monetization.grantPass(buyer, gift.passKey)
	end

	logAndSave(buyerProfile, log, purchaseId)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- The ONE ProcessReceipt callback for the whole game. Routes gift products separately; otherwise grants
-- the buyer. Idempotent via Shared.PurchaseIds.
local function processReceipt(receiptInfo: ReceiptInfo): Enum.ProductPurchaseDecision
	local gift = GIFTS_BY_ID[receiptInfo.ProductId]
	if gift then
		return processGiftReceipt(receiptInfo, gift)
	end

	local def = PRODUCTS_BY_ID[receiptInfo.ProductId]
	if not def then
		-- Sold a product with no handler yet: don't consume it -- retry so a later patch can grant it.
		warn(`{LOG} no handler for ProductId {receiptInfo.ProductId}; will retry. Add it to PRODUCTS.`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- Buyer isn't in this server; Roblox re-delivers on one where they are.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local profile = waitForProfile(player)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local log = profile.Data.Shared.PurchaseIds
	local purchaseId = tostring(receiptInfo.PurchaseId)
	if table.find(log, purchaseId) then
		-- Already granted on an earlier (un-acked) delivery -- safe to confirm without re-granting.
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- Grant and log together so they persist atomically. If the Save fails, NEITHER the award nor the
	-- id were written, so the re-delivery re-grants cleanly: no double-grant, no lost grant.
	local ok, err = pcall(function()
		def.grant(player, profile, receiptInfo)
		logAndSave(profile, log, purchaseId)
	end)
	if not ok then
		warn(`{LOG} grant for ProductId {def.id} failed for {player.Name}: {err}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Wires the global callbacks once, at server start. Safe to call repeatedly; only the first takes hold.
function Monetization.init()
	if inited then
		return
	end
	inited = true

	for key, def in PRODUCTS do
		if def.id > 0 then
			if PRODUCTS_BY_ID[def.id] then
				warn(`{LOG} duplicate ProductId {def.id} ('{key}')`)
			end
			PRODUCTS_BY_ID[def.id] = def
		else
			warn(`{LOG} product '{key}' has no id set -- not purchasable yet`)
		end
	end
	for key, def in PASSES do
		if def.id > 0 then
			if PASSES_BY_ID[def.id] then
				warn(`{LOG} duplicate GamePass id {def.id} ('{key}')`)
			end
			PASSES_BY_ID[def.id] = { key = key, def = def }
		else
			warn(`{LOG} pass '{key}' has no id set -- not purchasable yet`)
		end
	end
	for key, def in GIFTS do
		if def.id > 0 then
			if GIFTS_BY_ID[def.id] then
				warn(`{LOG} duplicate gift ProductId {def.id} ('{key}')`)
			end
			GIFTS_BY_ID[def.id] = def
		else
			warn(`{LOG} gift '{key}' has no id set -- gifting '{def.passKey}' is disabled until you create it`)
		end
	end

	-- Roblox enforces a single ProcessReceipt per game; cast past the strict signature check.
	(MarketplaceService :: any).ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		if not wasPurchased then
			return
		end
		local entry = PASSES_BY_ID[gamePassId]
		if not entry then
			return
		end
		-- Record the purchase as a persistent flag (mirrors a gift), then force-save it.
		if Monetization.grantPass(player, entry.key) then
			local profile = Manager.getProfile(player)
			if profile then
				profile:Save()
			end
		end
	end)

	-- Recipient-picker entry point: client sends (recipientUserId, passKey); server prompts the buyer.
	Remotes.RequestGift.OnServerEvent:Connect(function(player, recipientUserId, passKey)
		if type(recipientUserId) == "number" and type(passKey) == "string" then
			Monetization.startGift(player, recipientUserId, passKey)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		pendingGifts[player.UserId] = nil
	end)
end

return Monetization
