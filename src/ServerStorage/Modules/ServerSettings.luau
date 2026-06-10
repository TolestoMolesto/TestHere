--!strict
-- SERVER-side, per-world environment config. NOT the player-preferences module -- that's
-- ReplicatedStorage/Modules/Settings.luau (music/SFX volume etc, saved to the profile). THIS module
-- owns SERVER-wide, PLACE-determined environment: which world this server is (by PlaceId), the world's
-- gravity, and the synchronized day/night cycle. The driver that applies it at runtime is
-- ServerScriptService/ServerSettingsServer.server.luau.
--
-- A "world" is one of the Teleport destinations (each is a separate Roblox place). We reuse Teleport's
-- place-id table as the single source of truth and only add the per-world ENVIRONMENT on top, keyed by
-- the same destination names -- so there's never a second copy of the place ids to keep in sync.
--
-- Day/night: one in-game day (a full 0->24 ClockTime sweep) takes DAY_LENGTH real seconds (4 IRL
-- hours), synchronized to os.time() -- UTC Unix time, identical on every Roblox server -- so every
-- server and world agrees on the time of day and it survives restarts. Sweeping 0->24 over 4 hours
-- naturally yields ~2h daylight / ~2h night, because
-- Roblox renders ClockTime 6-18 as day and 18-6 as night (each half = 2 IRL hours) -- the requested
-- 2h-day / 2h-night split, no special casing needed.

local ServerStorage = game:GetService("ServerStorage")

local Teleport = require(ServerStorage.Modules.Teleport)

-- Roblox's default Workspace.Gravity (studs/s^2). Worlds default to this; override per world below.
local DEFAULT_GRAVITY = 196.2

-- Real-time length of one full in-game day (a 0->24 ClockTime sweep), in seconds. 4 IRL hours.
local DAY_LENGTH = 4 * 60 * 60

-- How a world handles time of day:
--   * "cycle"  -> follows the global, os.time()-synced day/night cycle.
--   * a number -> a FIXED ClockTime in [0, 24) (e.g. 12 = always noon). Use for menus / void worlds.
export type TimeMode = "cycle" | number

export type WorldEnvironment = {
	gravity: number,
	time: TimeMode,
}

-- Per-world environment, keyed by Teleport destination name. Every key here MUST be a real destination
-- (see Teleport.luau). To tune a world: change its `gravity`, or set `time` to a fixed ClockTime.
--
-- Right now every world is plain Earth gravity on the shared cycle. Example DBZ-style overrides for when
-- you want them (drop them straight in):
--   GravityChamber = { gravity = DEFAULT_GRAVITY * 10, time = "cycle" }, -- 10x training gravity
--   HTC            = { gravity = DEFAULT_GRAVITY * 10, time = 12 },      -- 10x G, endless white noon
local ENVIRONMENTS: { [string]: WorldEnvironment } = {
	MainMenu = { gravity = DEFAULT_GRAVITY, time = "cycle" },
	Earth = { gravity = DEFAULT_GRAVITY, time = "cycle" },
	GravityChamber = { gravity = DEFAULT_GRAVITY, time = "cycle" },
	HTC = { gravity = DEFAULT_GRAVITY, time = "cycle" },
	OtherWorld = { gravity = DEFAULT_GRAVITY, time = "cycle" },
}

local ServerSettings = {}

ServerSettings.DEFAULT_GRAVITY = DEFAULT_GRAVITY
ServerSettings.DAY_LENGTH = DAY_LENGTH

-- The world this server is running, by reverse-lookup on game.PlaceId (nil if this place isn't a known
-- world). Thin wrapper over Teleport so there's one place-id source of truth.
function ServerSettings.getCurrentWorld(): Teleport.Destination?
	return Teleport.getCurrentDestination()
end

-- The environment for a world name (nil if the name isn't configured). Returns nil rather than guessing
-- a default so callers decide their own fallback.
function ServerSettings.getEnvironment(world: string): WorldEnvironment?
	return ENVIRONMENTS[world]
end

-- The current synchronized in-game ClockTime in [0, 24). os.time() is UTC Unix time -- the SAME value
-- on every Roblox server -- so this reads identically everywhere with zero coordination. And because the
-- epoch is UTC midnight and DAY_LENGTH (4h) divides 24h evenly, the cycle also lines up with the real
-- clock: in-game midnight lands at UTC 00:00 / 04:00 / 08:00 / 12:00 / 16:00 / 20:00. World-independent
-- -- any world following "cycle" displays exactly this.
function ServerSettings.getCycleClockTime(): number
	local secondsIntoDay = os.time() % DAY_LENGTH
	return (secondsIntoDay / DAY_LENGTH) * 24
end

-- The ClockTime a given world should show right now: its fixed time, or the global cycle time when it
-- follows "cycle". nil if the world isn't configured.
function ServerSettings.getClockTimeFor(world: string): number?
	local env = ENVIRONMENTS[world]
	if not env then
		return nil
	end
	local mode = env.time
	if type(mode) == "number" then
		return mode
	end
	return ServerSettings.getCycleClockTime()
end

-- True when the global cycle is currently in its night half (ClockTime < 6 or >= 18). Lets server
-- systems (events, spawns) branch on the shared day/night without re-deriving the math. Reflects the
-- GLOBAL cycle, not a fixed-time world's local clock.
function ServerSettings.isNight(): boolean
	local clock = ServerSettings.getCycleClockTime()
	return clock < 6 or clock >= 18
end

return ServerSettings
