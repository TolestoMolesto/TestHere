--!strict
-- Character aging -- pure math, the single source of every tunable. The model is "active playtime":
-- a slot accumulates real seconds played (slot.PlayTime, driven by ServerScriptService.AgeServer),
-- and BOTH the displayed age number and the body scale derive from it. Nothing ages offline or on a
-- slot you aren't playing.
--
-- The body grows from KID_SCALE (a brand-new, age-1 character) up to ADULT_SCALE over GROW_PLAY_HOURS
-- of play, then holds at adult size. The age NUMBER keeps climbing past that.
--
-- ---- Tuning ------------------------------------------------------------------------------------
--   * KID_SCALE / ADULT_SCALE  -- body size at birth vs. full-grown.
--   * GROW_PLAY_HOURS          -- real played hours from newborn to full size (~1 week at ~2h/day).
--   * INGAME_DAYS_PER_REAL_DAY -- the "6 in-game days per real day" clock, applied to play time; this
--                                 only sets how fast the age NUMBER ticks, not the body scale.
--   * START_AGE                -- the age a fresh character is born at.
-- Want age shown in years instead of in-game days? Divide the result of ageFromPlayTime by 365 where
-- it's displayed (or fold a /365 in here) -- the scale ramp is independent of this.
-- ------------------------------------------------------------------------------------------------

local Age = {}

Age.KID_SCALE = 0.6
Age.ADULT_SCALE = 1.0
Age.GROW_PLAY_HOURS = 14
Age.INGAME_DAYS_PER_REAL_DAY = 6
Age.START_AGE = 1

local SECONDS_PER_HOUR = 3600
local SECONDS_PER_DAY = 86400

-- Displayed age (in-game days since birth, offset by START_AGE) for a given amount of active play.
function Age.ageFromPlayTime(playSeconds: number): number
	local inGameDays = playSeconds * Age.INGAME_DAYS_PER_REAL_DAY / SECONDS_PER_DAY
	return Age.START_AGE + inGameDays
end

-- Body scale in [KID_SCALE, ADULT_SCALE], ramping linearly over the first GROW_PLAY_HOURS of play
-- and then capped at adult size.
function Age.scaleFromPlayTime(playSeconds: number): number
	local growSeconds = Age.GROW_PLAY_HOURS * SECONDS_PER_HOUR
	local t = if growSeconds > 0 then math.clamp(playSeconds / growSeconds, 0, 1) else 1
	return Age.KID_SCALE + (Age.ADULT_SCALE - Age.KID_SCALE) * t
end

-- Slot convenience wrappers. A slot with no PlayTime field (NPCs / ad-hoc data built by bindNPC) is
-- treated as a full-grown adult rather than a newborn -- only real, persisted slots start at age 1.
function Age.ageOf(slot: any): number
	local pt = slot.PlayTime
	return if typeof(pt) == "number" then Age.ageFromPlayTime(pt) else Age.START_AGE
end

function Age.scaleOf(slot: any): number
	local pt = slot.PlayTime
	return if typeof(pt) == "number" then Age.scaleFromPlayTime(pt) else Age.ADULT_SCALE
end

return Age
