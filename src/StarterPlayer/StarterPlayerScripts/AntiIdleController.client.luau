--!strict
-- AFK handling, client half (server half: ServerScriptService/AntiIdleServer). Two jobs:
--
--   1. Idle herd. After IDLE_LIMIT seconds with no input we ask the server to send the player to the
--      Main Menu (Remotes.RequestTeleport "MainMenu"); it re-fires every CHECK_INTERVAL while they
--      stay idle. Teleporting to the Main Menu while already there just reloads the place, so this
--      doubles as a session refresh that dodges Roblox's ~20-minute idle disconnect -- the player is
--      both kept in the lobby AND kept connected while AFK.
--
--   2. Spawn-shield drop. The server puts a ForceField on the character at every spawn. The moment
--      this player gives ANY input we ping Remotes.PlayerActive so the server drops it. No input ->
--      the shield stays, so an AFK player herded to the lobby remains protected. (The server keeps
--      the shield up regardless in the Main Menu, since that's a GUI lobby where interacting with the
--      menus must not strip protection -- see AntiIdleServer.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Modules.Remotes)

local IDLE_LIMIT = 960 -- seconds without input before the player is herded to the Main Menu
local CHECK_INTERVAL = 30 -- how often the idle check runs

local player = Players.LocalPlayer

local lastInput = os.clock()
local shieldUp = false -- true from spawn until this player's first input (a server ForceField is on us)

local function markActive()
	lastInput = os.clock()
	-- First input after a spawn: tell the server to drop the spawn shield. Guarded so we ping once per
	-- spawn rather than on every key press / mouse move.
	if shieldUp then
		shieldUp = false
		Remotes.PlayerActive:FireServer()
	end
end

UserInputService.InputBegan:Connect(markActive)
UserInputService.InputChanged:Connect(markActive)
UserInputService.InputEnded:Connect(markActive)

-- Every spawn re-arms the shield (the server attaches a fresh ForceField) and resets the idle clock,
-- so a just-teleported-in player isn't immediately herded again.
local function onCharacterAdded()
	shieldUp = true
	lastInput = os.clock()
end
player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded()
end

task.spawn(function()
	while true do
		task.wait(CHECK_INTERVAL)
		if os.clock() - lastInput >= IDLE_LIMIT then
			Remotes.RequestTeleport:FireServer("MainMenu")
		end
	end
end)
