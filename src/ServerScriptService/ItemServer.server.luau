-- Server entry for the Items system (per-slot inventory), mirroring SkillServer. Serves the bag UI
-- the sanitised inventory list (Inventory.list), handles a use request (UseItem -> ItemState.use),
-- and pokes the client with the fresh list (InventoryChanged) after any change. Item balance/config
-- from ItemConfig never leaves the server; only the curated list (counts + display + description
-- string) crosses.
--
-- TEST GRANT: on spawn, in Studio or for an Admin, the active slot is topped up with example items so
-- the system is testable end-to-end. Inventory.add clamps to each item's maxAmount, so this just
-- refills to the cap each spawn -- no stacking. Live, non-admin players get nothing here; real
-- acquisition (shops / drops / codes) should call Inventory.add later.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Describe = require(ReplicatedStorage.Modules.Describe)
local Inventory = require(ServerStorage.Modules.Inventory)
local ItemState = require(ServerStorage.Modules.ItemState)
local Manager = require(ServerStorage.Modules.Manager)
local PassiveConfig = require(ServerStorage.Modules.PassiveConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local function isTester(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	local shared = Manager.getShared(player)
	return shared ~= nil and shared.Admin == true
end

local function pushInventory(player: Player)
	Remotes.InventoryChanged:FireClient(player, Inventory.list(player))
end

local function seedTestItems(player: Player)
	if not isTester(player) then
		return
	end
	if not Manager.getActiveSlot(player) then
		return -- profile not loaded yet; a later spawn will catch it
	end
	-- add() clamps to maxAmount, so these refill to the cap each spawn (idempotent, never stacks).
	Inventory.add(player, "SenzuBean", 5)
	Inventory.add(player, "SenzuBean75OT", 10)
	Inventory.add(player, "DragonRadar", 1)
	pushInventory(player)
end

Remotes.GetInventory.OnServerInvoke = function(player: Player)
	return Inventory.list(player)
end

-- Passives for the inventory's Skills tab: the active slot's race-applicable (+ universal) traits,
-- read-only, each with the finished description string. Presence is race-based -- no unlock tracking.
Remotes.GetPassives.OnServerInvoke = function(player: Player)
	local slot = Manager.getActiveSlot(player)
	local race = if slot then slot.Race else "Any"
	local out = {}
	for _, entry in PassiveConfig.forRace(race) do
		local def = entry.def
		table.insert(out, {
			id = entry.id,
			displayName = def.displayName,
			type = def.type,
			description = Describe.format({
				type = def.type,
				note = def.description.note,
				summary = def.description.summary,
				effects = def.description.effects or {},
			}),
		})
	end
	return out
end

Remotes.UseItem.OnServerEvent:Connect(function(player: Player, itemId: any)
	if type(itemId) ~= "string" then
		return
	end
	ItemState.use(player, itemId)
	-- Always resync the bag from the server after a use attempt (the consume happens up front, so the
	-- list already reflects the new count), keeping the client authoritative.
	pushInventory(player)
end)

local function bindPlayer(player: Player)
	if player.Character then
		task.defer(seedTestItems, player)
	end
	player.CharacterAdded:Connect(function()
		task.defer(seedTestItems, player)
	end)
end

Players.PlayerAdded:Connect(bindPlayer)
for _, player in Players:GetPlayers() do
	bindPlayer(player)
end
