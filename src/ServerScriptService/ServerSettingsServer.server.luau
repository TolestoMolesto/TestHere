--!strict
-- Applies this server's environment from ServerStorage/Modules/ServerSettings (the SERVER-side world
-- config -- NOT the player-preferences Settings module). On start it resolves which world this place is
-- from game.PlaceId, sets Workspace.Gravity, then drives Lighting.ClockTime:
--   * a world on a FIXED time has its ClockTime set once.
--   * a world on the global CYCLE has its ClockTime stepped on an interval, resynced to os.time() each
--     tick so all servers/worlds agree and a fresh server lands on the right time immediately
--     (4 IRL hours = one in-game day = ~2h day / ~2h night).
-- An unknown place (not in the world table) is left at its Studio/default gravity and lighting.

local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local ServerSettings = require(ServerStorage.Modules.ServerSettings)

-- How often (seconds) to step ClockTime on cycling worlds. The cycle is slow (one in-game hour every
-- 10 real minutes), so a coarse tick stays visually smooth and costs almost nothing.
local UPDATE_INTERVAL = 2

local world = ServerSettings.getCurrentWorld()
if not world then
	warn(`[ServerSettings] Place {game.PlaceId} isn't a known world; leaving gravity/time at defaults`)
	return
end

local env = ServerSettings.getEnvironment(world)
if not env then
	warn(`[ServerSettings] No environment configured for world "{world}"; leaving defaults`)
	return
end

Workspace.Gravity = env.gravity

local time = env.time
if type(time) == "number" then
	-- Fixed-time world (menu / void): set the clock once, no cycle loop.
	Lighting.ClockTime = time
	return
end

-- Cycling world: step the clock forever, each tick pulled fresh from the global os.time()-based cycle
-- so it can't drift. The first iteration runs before the first wait, so the clock is correct on spawn.
while true do
	Lighting.ClockTime = ServerSettings.getCycleClockTime()
	task.wait(UPDATE_INTERVAL)
end
