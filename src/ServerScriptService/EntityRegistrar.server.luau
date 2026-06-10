--!strict
-- Tags every player's character as a "Player" and parks it in the Workspace.Players folder on
-- each spawn. Shadows/NPCs register themselves at their own spawn sites (see ShadowSpawner);
-- this script owns the player side and creates the shared folders at boot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CollisionGroups = require(ServerStorage.Modules.CollisionGroups)
local Entities = require(ReplicatedStorage.Modules.Entities)

-- Create Players/NPCs/Shadows up-front so nothing ever references a missing folder.
Entities.ensureFolders()

local function onCharacter(character: Model): ()
	Entities.register(character, "Player")
	-- Own collision group so a shadow can pass through players (see CollisionGroups / ShadowSpawner).
	CollisionGroups.assign(character, CollisionGroups.Player)
end

local function onPlayerAdded(player: Player): ()
	-- Catch a character that already exists (script loaded after the player spawned).
	local existing = player.Character
	if existing then
		onCharacter(existing)
	end
	player.CharacterAdded:Connect(onCharacter)
end

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
