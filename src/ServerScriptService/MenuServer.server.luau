-- Server entry for the Main Menu UI (StarterPlayerScripts/MainMenuController): the Play button and the
-- Slots panel. Everything is re-validated here -- the client only ever sends a slot index (SelectSlot)
-- or nothing at all. Play reads the ACTIVE slot's stored Planet server-side and routes it through
-- Teleport (which runs every access gate + the safe-zone guard), so the client never names a place --
-- matching how the rest of travel works.
--
-- Also publishes this place's world NAME to ReplicatedStorage ("CurrentWorld") so a Main-Menu-only UI
-- can gate itself on the world without the client ever seeing the server-side place-id table.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Manager = require(ServerStorage.Modules.Manager)
local Monetization = require(ServerStorage.Modules.Monetization)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Teleport = require(ServerStorage.Modules.Teleport)

-- Players start with 1 free slot. Up to MAX_BUYABLE_SLOTS more are purchasable via the Slot dev product
-- (Monetization "SlotPurchase"); the panel hides the Buy button once that many have been bought. There's
-- no cap on TOTAL slots -- free/race slots granted elsewhere (Manager.addSlot) can push the count higher.
local MAX_BUYABLE_SLOTS = 5
local SLOT_PRODUCT_KEY = "SlotPurchase"

-- Publish which world this place is, by name (e.g. "MainMenu", "Earth"). Unknown places (not in the
-- Teleport table) publish "Unknown". Read client-side as ReplicatedStorage:GetAttribute("CurrentWorld").
ReplicatedStorage:SetAttribute("CurrentWorld", Teleport.getCurrentDestination() or "Unknown")

-- The slot roster the panel renders: one entry per slot with the three columns it shows (slot number,
-- race, Battle Power) plus its home planet and the active index, then the buyable-slot economy the panel
-- needs to drive its Buy button (slots already bought, the buyable cap, and the Slot product id the
-- client prompts). nil while the profile is still loading.
local function buildSlots(player: Player)
	local profile = Manager.getProfile(player)
	if not profile then
		return nil
	end
	local data = profile.Data
	local slots = {}
	for i, slot in data.Slots do
		table.insert(slots, {
			index = i,
			race = slot.Race,
			battlePower = slot.BattlePower,
			planet = slot.Planet,
		})
	end
	return {
		activeSlot = data.ActiveSlot,
		slots = slots,
		purchasedSlots = data.Shared.PurchasedSlots,
		maxBuyable = MAX_BUYABLE_SLOTS,
		slotProductId = Monetization.getProductId(SLOT_PRODUCT_KEY) or 0,
	}
end

Remotes.GetSlots.OnServerInvoke = function(player: Player)
	return buildSlots(player)
end

Remotes.SelectSlot.OnServerInvoke = function(player: Player, index: any)
	if typeof(index) ~= "number" then
		return { ok = false, error = "bad_slot" }
	end
	-- switchSlot bounds-checks the index against the player's real slot count.
	if not Manager.switchSlot(player, index) then
		return { ok = false, error = "bad_slot" }
	end
	return { ok = true, state = buildSlots(player) }
end

Remotes.RequestPlay.OnServerInvoke = function(player: Player)
	local slot = Manager.getActiveSlot(player)
	if not slot then
		return { ok = false, reason = "Still loading..." }
	end
	-- The slot stores a destination NAME; fall back to Earth if it's missing or no longer a real place.
	local planet = slot.Planet
	if typeof(planet) ~= "string" or not Teleport.isDestination(planet) then
		planet = "Earth"
	end
	local ok, reason = Teleport.teleportPlayer(player, planet)
	if not ok then
		return { ok = false, reason = reason or "You can't travel there" }
	end
	return { ok = true, planet = planet }
end
