--!strict
-- Cross-place travel. Each "world" is a separate Roblox place under this universe; teleporting hops
-- the player between them with TeleportService. This module is the single server-authoritative entry:
-- it owns the place-id table, the per-destination ACCESS GATES (Battle Power / unlock / race / admin /
-- custom), and the anti-combat-log guard on safe zones. Clients never pass a place id -- only a known
-- destination NAME (validated in TeleportServer) -- so they can't redirect themselves anywhere.
--
-- Two ways to drive it:
--   * server code (portals, NPCs, admin commands): require this and call Teleport.teleportPlayer
--   * the client (a travel menu / button): fire Remotes.RequestTeleport -> TeleportServer -> here
--
-- Adding a gated place: add an entry below with `requirements = { ... }`; leave `requirements` out
-- (nil) for somewhere anyone can reach. See the commented VIPArea example for the full gate vocabulary.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TeleportService = game:GetService("TeleportService")

local CombatTag = require(ServerStorage.Modules.CombatTag)
local Manager = require(ServerStorage.Modules.Manager)

-- A destination name -- one of the keys of `destinations` below. Kept as a plain string alias and
-- validated at runtime via Teleport.isDestination, matching how the codebase handles ids elsewhere
-- (SkillConfig ids, Settings keys) rather than a literal union.
export type Destination = string

-- A gate set. An absent (nil) field is not checked; every field that IS set must pass. Reads come from
-- the live character (Battle Power off Humanoid.Stats, per the project's stats rule) and the profile
-- (unlock/admin/race), so a gate reflects the player's state at the moment they try to travel.
type Requirements = {
	minBattlePower: number?, -- Humanoid.Stats.BattlePower must be >= this
	unlock: string?, -- key in profile Shared.Unlocks must be true (e.g. a bought pass)
	races: { string }?, -- active slot's Race must be one of these
	adminOnly: boolean?, -- profile Shared.Admin must be true
	-- Escape hatch for anything bespoke. Return (true) to allow, or (false, reason) to deny. Must NOT
	-- yield -- it runs inside the synchronous access check.
	custom: ((player: Player) -> (boolean, string?))?,
}

type DestinationConfig = {
	placeId: number,
	displayName: string, -- player-facing label (travel menu, denial messages)
	safeZone: boolean?, -- if true, blocked while combat-tagged so players can't combat-log to safety
	requirements: Requirements?,
}

local destinations: { [Destination]: DestinationConfig } = {
	MainMenu = { placeId = 125626767229578, displayName = "Main Menu", safeZone = true },
	Earth = { placeId = 93068734301350, displayName = "Earth" },
	GravityChamber = { placeId = 70731873074651, displayName = "Gravity Chamber" },
	HTC = { placeId = 87688265644198, displayName = "Hyperbolic Time Chamber" },
	OtherWorld = { placeId = 101872272526649, displayName = "Other World" },

	-- Example of a gated place. Copy this shape, drop in the real placeId, then add the key to
	-- DESTINATION_ORDER below so it shows up in travel menus. Use any subset of the gates -- all the
	-- ones you list must pass.
	-- VIPArea = {
	-- 	placeId = 0, -- TODO: real place id
	-- 	displayName = "VIP Lounge",
	-- 	requirements = {
	-- 		minBattlePower = 1_000_000,
	-- 		unlock = "VIPPass", -- add `VIPPass = false` to Shared.Unlocks in TemplateData first
	-- 		races = { "Saiyan", "God" },
	-- 		adminOnly = false,
	-- 		custom = function(player)
	-- 			-- gate on anything the fields above don't cover; return (false, "reason") to deny
	-- 			return true
	-- 		end,
	-- 	},
	-- },
}

-- Menu order for listDestinations -- the map above has no defined iteration order. Must list every
-- key in `destinations`; a missing one simply won't appear in a travel menu.
local DESTINATION_ORDER: { Destination } = { "MainMenu", "Earth", "GravityChamber", "HTC", "OtherWorld" }

local Teleport = {}

-- Outgoing-teleport tracker (replaces the old PlayerTracker): records where a player is being sent so
-- other systems can ask mid-hop. Cleared when they leave (or if dispatch fails).
local pending: { [Player]: Destination } = {}

-- Live stat read off Humanoid.Stats (the project's single source of truth for stats). nil if the
-- player isn't spawned / the folder isn't up yet.
local function readStatNumber(player: Player, attr: string): number?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local stats = humanoid:FindFirstChild("Stats")
	if not stats then
		return nil
	end
	return stats:GetAttribute(attr) :: number?
end

-- 1000000 -> "1,000,000" for readable denial messages (these strings are shown to players as-is).
local function withCommas(n: number): string
	local formatted = tostring(math.floor(n))
	while true do
		local replaced
		formatted, replaced = formatted:gsub("^(%-?%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return formatted
end

-- True if `name` is a real destination (narrows an untrusted client string before use).
function Teleport.isDestination(name: string): boolean
	return destinations[name] ~= nil
end

-- The Roblox place id behind a destination name (nil if the name is unknown). Lets other server
-- systems compare against game.PlaceId without re-hard-coding ids -- e.g. AntiIdleServer asking
-- "is this the Main Menu place?".
function Teleport.getPlaceId(destination: Destination): number?
	local config = destinations[destination]
	if not config then
		return nil
	end
	return config.placeId
end

-- The destination NAME of the place this server is running, by reverse-lookup on game.PlaceId (nil if
-- this place isn't in the table). Lets a server publish "which world am I?" to clients without leaking
-- the place-id table -- e.g. so a Main-Menu-only UI can gate on a replicated world name.
function Teleport.getCurrentDestination(): Destination?
	for name, config in destinations do
		if config.placeId == game.PlaceId then
			return name
		end
	end
	return nil
end

-- Runs every gate on a destination's requirements. Returns (true) if the player may enter, or
-- (false, reason) with a player-facing reason for the first gate that fails.
function Teleport.canAccess(player: Player, destination: Destination): (boolean, string?)
	local config = destinations[destination]
	if not config then
		return false, "Unknown destination"
	end
	local req = config.requirements
	if not req then
		return true
	end

	if req.adminOnly then
		local shared = Manager.getShared(player)
		if not (shared and shared.Admin) then
			return false, "Staff only"
		end
	end

	if req.unlock then
		local shared = Manager.getShared(player)
		if not (shared and shared.Unlocks[req.unlock]) then
			return false, `{config.displayName} is locked`
		end
	end

	if req.races then
		local slot = Manager.getActiveSlot(player)
		local race = slot and slot.Race
		if not (race and table.find(req.races, race)) then
			return false, `Your race can't enter {config.displayName}`
		end
	end

	-- NOTE: reads the LIVE (transform-inclusive) Battle Power off Humanoid.Stats. If you'd rather gate
	-- on base progression that a temporary form can't inflate, read Manager.getActiveSlot(player).BattlePower.
	if req.minBattlePower then
		local bp = readStatNumber(player, "BattlePower") or 0
		if bp < req.minBattlePower then
			return false, `Requires {withCommas(req.minBattlePower)} Battle Power`
		end
	end

	if req.custom then
		local ok, reason = req.custom(player)
		if not ok then
			return false, reason or "You don't meet the requirements"
		end
	end

	return true
end

export type DestinationListing = {
	name: Destination,
	displayName: string,
	locked: boolean,
	reason: string?, -- why it's locked, when locked
}

-- A player-facing view of every destination with its lock state -- ready for a travel menu that greys
-- out places the player can't reach yet. Ordered by DESTINATION_ORDER.
function Teleport.listDestinations(player: Player): { DestinationListing }
	local out: { DestinationListing } = {}
	for _, name in DESTINATION_ORDER do
		local config = destinations[name]
		local ok, reason = Teleport.canAccess(player, name)
		table.insert(out, {
			name = name,
			displayName = config.displayName,
			locked = not ok,
			reason = if ok then nil else reason,
		})
	end
	return out
end

-- Where a player is currently being teleported (nil if not mid-hop).
function Teleport.getPlayerDestination(player: Player): Destination?
	return pending[player]
end

-- The one place that actually moves a player. Runs all guards (valid player/character, safe-zone
-- combat-log block, full access check) then dispatches. Returns (true) on dispatch, or (false, reason)
-- so callers (e.g. TeleportServer) can surface the reason. In Studio, TeleportService can't really
-- teleport, so it logs the decision and returns true -- letting you test the GATES without a live place.
function Teleport.teleportPlayer(
	player: Player,
	destination: Destination,
	options: { [string]: any }?
): (boolean, string?)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "Invalid player"
	end

	local config = destinations[destination]
	if not config then
		warn(`[Teleport] Invalid destination: {tostring(destination)}`)
		return false, "Unknown destination"
	end

	local character = player.Character
	if not character then
		return false, "You need to be spawned to travel"
	end

	if config.safeZone and CombatTag.isInCombat(character) then
		warn(`[Teleport] {player.Name} tried to combat-log to {destination} while tagged`)
		return false, "You can't travel there while in combat"
	end

	local ok, reason = Teleport.canAccess(player, destination)
	if not ok then
		return false, reason
	end

	if RunService:IsStudio() then
		warn(`[Teleport] (Studio) {player.Name} passed all gates for {destination}; skipping TeleportAsync`)
		pending[player] = destination
		return true
	end

	local teleportOptions = Instance.new("TeleportOptions")
	-- The arrival place reads this via TeleportService:GetLocalPlayerTeleportData().
	local data: { [string]: any } = { destination = destination }
	if options then
		data.options = options
	end
	teleportOptions:SetTeleportData(data)

	pending[player] = destination
	local success, err = pcall(function()
		TeleportService:TeleportAsync(config.placeId, { player }, teleportOptions)
	end)
	if not success then
		pending[player] = nil
		warn(`[Teleport] TeleportAsync failed for {player.Name} -> {destination}: {tostring(err)}`)
		return false, "Teleport failed, please try again"
	end

	return true
end

Players.PlayerRemoving:Connect(function(player)
	pending[player] = nil
end)

return Teleport
