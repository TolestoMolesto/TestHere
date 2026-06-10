--!strict
-- Client-facing entry to the Teleport module. A player fires RequestTeleport with a destination NAME
-- (never a place id); we re-validate the name and let Teleport run every access gate before moving
-- them. On rejection we fire TeleportDenied back with a player-facing reason. Server code (portals,
-- NPCs, admin commands) should require Teleport and call teleportPlayer directly instead of round-
-- tripping through here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Teleport = require(ServerStorage.Modules.Teleport)

Remotes.RequestTeleport.OnServerEvent:Connect(function(player: Player, destination: any)
	-- Untrusted input: must be a string naming a real destination. Everything else (combat-log guard,
	-- access gates) lives in Teleport so server-side callers get the same checks.
	if typeof(destination) ~= "string" or not Teleport.isDestination(destination) then
		return
	end

	local ok, reason = Teleport.teleportPlayer(player, destination)
	if not ok then
		Remotes.TeleportDenied:FireClient(player, destination, reason or "You can't travel there")
	end
end)
