-- Server entry for the Form/Technique loadout (keys 6-0), mirroring SkillServer. On spawn it fills
-- the active slot's FormLoadout with the race's ability line if it's empty (preserving today's
-- default bar), and it serves the inventory's loadout view + equip writes. Form *casting* stays in
-- CombatServer (the "Transform" action -> FormState.toggleByIndex, which now reads FormLoadout).
-- Balance numbers from FormConfig never leave the server; the catalogue here is sanitised.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local FormState = require(ServerStorage.Modules.FormState)
local Manager = require(ServerStorage.Modules.Manager)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

Remotes.GetFormLoadout.OnServerInvoke = function(player: Player)
	local character = player.Character
	if not character then
		return { catalogue = {}, loadout = { "", "", "", "", "" } }
	end
	return FormState.getLoadoutView(character)
end

Remotes.SetFormLoadout.OnServerEvent:Connect(function(player: Player, index: any, formId: any)
	if type(index) ~= "number" or index % 1 ~= 0 then
		return
	end
	if type(formId) ~= "string" then
		return
	end
	if FormState.setLoadout(player, index, formId) then
		-- Poke the client (ActionBar + inventory) to re-pull the rearranged row.
		Remotes.FormLoadoutChanged:FireClient(player)
	end
end)

-- Reconcile the 6-0 loadout with the slot's race on spawn (prunes stale forms after a reroll, fills
-- the default race line when none remain; otherwise leaves the player's arrangement alone).
local function bindCharacter(player: Player)
	task.defer(function()
		local slot = Manager.getActiveSlot(player)
		if slot then
			FormState.reconcileLoadout(slot, slot.Race)
		end
	end)
end

local function bindPlayer(player: Player)
	if player.Character then
		bindCharacter(player)
	end
	player.CharacterAdded:Connect(function()
		bindCharacter(player)
	end)
end

Players.PlayerAdded:Connect(bindPlayer)
for _, player in Players:GetPlayers() do
	bindPlayer(player)
end
