--!strict
-- AFK system, server half (client half: StarterPlayerScripts/AntiIdleController). Owns the spawn
-- ForceField:
--
--   * Every character gets a fresh ForceField the moment it spawns -- spawn protection in the combat
--     worlds, and a standing safe-zone shield in the Main Menu.
--   * In the combat worlds the client pings Remotes.PlayerActive on the player's first input and we
--     drop the shield (so protection ends the instant they start playing).
--   * In the Main Menu -- a GUI lobby where interacting with menus must not strip protection -- we
--     ignore that ping and keep the shield up. An AFK player gives no input anywhere, so the shield
--     persists, which (with the client herding them to the Main Menu) keeps them safe while idle.
--
-- The shield is a real server-side ForceField on purpose: Damage.apply lands hits through
-- Humanoid:TakeDamage, which a ForceField blocks -- but only the SERVER's copy of it counts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Teleport = require(ServerStorage.Modules.Teleport)

local SHIELD_NAME = "AFKShield"
-- True when THIS place is the Main Menu lobby; there the spawn shield is never dropped by input.
local IS_MAIN_MENU = game.PlaceId == Teleport.getPlaceId("MainMenu")

local function grantShield(character: Model)
	if character:FindFirstChild(SHIELD_NAME) then
		return
	end
	local shield = Instance.new("ForceField")
	shield.Name = SHIELD_NAME
	shield.Visible = true
	shield.Parent = character
end

local function dropShield(character: Model)
	local shield = character:FindFirstChild(SHIELD_NAME)
	if shield then
		shield:Destroy()
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(grantShield)
	if player.Character then
		grantShield(player.Character)
	end
end

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerAdded:Connect(onPlayerAdded)

-- Player's first input in a combat world -> drop their spawn shield. Ignored in the Main Menu lobby,
-- where interacting with the menu UI must not strip protection.
Remotes.PlayerActive.OnServerEvent:Connect(function(player: Player)
	if IS_MAIN_MENU then
		return
	end
	local character = player.Character
	if character then
		dropShield(character)
	end
end)
