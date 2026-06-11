--!strict
-- Gravity physiology: turns the world's Workspace.Gravity into per-player movement, damage and
-- training effects, gated by each character's trained "gravity mastery" (slot.GravityMastery, surfaced
-- onto Humanoid.Stats by StatsManager). PURE LOGIC + tuning -- the runtime driver is
-- ServerScriptService/GravityServer.server.luau, the chamber dial is GravityChamberServer.server.luau,
-- and Train.luau reads trainMult so fighting under high gravity trains faster.
--
-- The whole model is ONE ratio with two thresholds:
--     exposure = Workspace.Gravity / DEFAULT_GRAVITY   -- "x Earth" (Earth = 1, a 10x chamber = 10)
--     ratio    = exposure / mastery                    -- how far the world outruns what you've adapted to
--   ratio <= 1      comfortable : full speed, no damage, no acclimation (no stimulus)
--   1 < ratio < 2   strain      : WalkSpeed penalty, faster training + acclimation, no damage
--   ratio >= 2      crush       : damage per second (scales with ratio); still acclimating, so a brave
--                                 player can out-adapt the bleed before they collapse
-- Mastery only ever rises TOWARD the current exposure (you can't adapt past what you're standing in),
-- so progress means cranking the chamber higher -- never AFK-farming a fixed room.

local Workspace = game:GetService("Workspace")

-- Mirrors ServerSettings.DEFAULT_GRAVITY (kept local to avoid a require cycle through Teleport).
local DEFAULT_GRAVITY = 196.2

local Gravity = {}

Gravity.DEFAULT_GRAVITY = DEFAULT_GRAVITY

-- Movement baselines GravityServer stamps on every player Humanoid. BASE_JUMP_POWER is tuned (with
-- UseJumpPower = true) to clear ~7.2 studs at Earth gravity -- matching Roblox's default jump -- so
-- normal worlds feel unchanged while higher Workspace.Gravity now physically crushes the jump.
Gravity.BASE_WALKSPEED = 16
Gravity.BASE_JUMP_POWER = 53

-- Mastery can never read below this (everyone tolerates Earth); also the div-by-zero guard for ratio.
local MASTERY_FLOOR = 1
Gravity.MASTERY_FLOOR = MASTERY_FLOOR

-- Ratio at/above which the crush band begins -- damage starts here ("2x over your mastery").
local CRUSH_RATIO = 2
Gravity.CRUSH_RATIO = CRUSH_RATIO

-- WalkSpeed penalty ramps linearly across the strain band, hitting MAX at the crush line and capping
-- there (a crushed player is slow, never frozen).
local MAX_WALK_PENALTY = 0.5

-- Crush bleed, as a fraction of MAX health per second: BASE right at the crush line, +SCALE for each
-- additional 1.0 of ratio beyond it. Percent-of-max so it's fair across stat tiers.
local BLEED_BASE_PCT = 0.02
local BLEED_SCALE_PCT = 0.02

-- Acclimation: mastery rises toward exposure at ACCLIM_FRACTION of the exposure per second (so high
-- chambers adapt proportionally, not glacially), CRUSH_ACCLIM_MULT faster while being crushed -- the
-- risk/reward of toughing out a chamber above your head.
local ACCLIM_FRACTION = 0.02
local CRUSH_ACCLIM_MULT = 2

-- Training-gain bonus for training under gravity (read by Train, alongside weights). Scales with the
-- ABSOLUTE gravity you train in, but only up to what you've EARNED -- the credited gravity is capped at
-- your mastery (see trainMult), so barging into a 50x chamber at 1x mastery pays ~nothing (and crushes
-- you), while grinding mastery to 50x reaps the full reward. sqrt curve: keeps paying as gravity climbs
-- toward infinity without exploding.
local TRAIN_GAIN_PER_ROOT = 0.35

-- The world's current gravity as a multiple of Earth (Workspace.Gravity is server-wide; the chamber
-- dial moves it in model B).
function Gravity.exposure(): number
	return Workspace.Gravity / DEFAULT_GRAVITY
end

local function readMastery(character: Model): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return MASTERY_FLOOR
	end
	local stats = humanoid:FindFirstChild("Stats")
	if not stats then
		return MASTERY_FLOOR
	end
	local m = stats:GetAttribute("GravityMastery") :: number?
	if type(m) ~= "number" then
		return MASTERY_FLOOR
	end
	return math.max(m, MASTERY_FLOOR)
end

-- Trained gravity tolerance off the live Humanoid.Stats (>= MASTERY_FLOOR; 1 for anyone without it).
function Gravity.masteryOf(character: Model): number
	return readMastery(character)
end

-- exposure / mastery for this character. 1 = exactly at tolerance.
function Gravity.ratioOf(character: Model): number
	return Gravity.exposure() / readMastery(character)
end

-- Fraction [0, MAX_WALK_PENALTY] to slow WalkSpeed by, given a ratio.
function Gravity.walkPenalty(ratio: number): number
	if ratio <= 1 then
		return 0
	end
	local p = (ratio - 1) / (CRUSH_RATIO - 1) * MAX_WALK_PENALTY
	return math.clamp(p, 0, MAX_WALK_PENALTY)
end

-- Damage-per-second in the crush band; 0 below it.
function Gravity.bleedDps(ratio: number, maxHealth: number): number
	if ratio < CRUSH_RATIO then
		return 0
	end
	return maxHealth * (BLEED_BASE_PCT + BLEED_SCALE_PCT * (ratio - CRUSH_RATIO))
end

-- New mastery after `dt` seconds at the given exposure/ratio: creeps toward exposure, faster while
-- crushed, never past exposure. Returns the (possibly unchanged) mastery.
function Gravity.acclimate(mastery: number, exposure: number, ratio: number, dt: number): number
	if ratio <= 1 then
		return mastery
	end
	local rate = ACCLIM_FRACTION * exposure * (if ratio >= CRUSH_RATIO then CRUSH_ACCLIM_MULT else 1)
	return math.min(exposure, mastery + rate * dt)
end

-- Training multiplier for Train: higher gravity trains faster, gated by EARNED mastery. The credited
-- gravity is min(exposure, mastery), so you only ever bank the bonus for gravity you've actually adapted
-- to -- no cheesing gains by standing in a chamber set far above your tolerance (you'd just collapse).
function Gravity.trainMult(character: Model): number
	local credited = math.min(Gravity.exposure(), Gravity.masteryOf(character))
	if credited <= 1 then
		return 1
	end
	return 1 + (math.sqrt(credited) - 1) * TRAIN_GAIN_PER_ROOT
end

return Gravity
