--!strict
-- Passive stat training. The five core stats (Strength / Speed / Endurance / KiControl /
-- BattleExperience) grow from combat itself: each landed, blocked, dodged or parried event awards
-- its mapped stats. Two principles drive the design:
--   * You earn from what you SPEND and RISK, not what you HOLD -- gains fire on a connecting hit, an
--     absorbed block, a dodge or a parry, never on charging/holding a button, so there's no free XP.
--   * Gains write straight to the slot's Base layer (the earned, buff-proof core) and DIMINISH as
--     the stat climbs, so spammable actions taper off and high stats are genuinely earned.
-- Each action feeds a PRIMARY stat plus small spillover, so training mirrors what you're doing.
-- Mirrors FormState.awardCombatHit: grab the live slot, mutate it, let ProfileStore autosave. The
-- live Humanoid.Stats attributes are re-derived on a per-player throttle, not on every hit.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local Gravity = require(ServerStorage.Modules.Gravity)
local Manager = require(ServerStorage.Modules.Manager)
local StatsManager = require(ServerStorage.Modules.StatsManager)

local RNG = Random.new()

local Train = {}

-- === Tuning dials (this block is the whole balance surface) =========================
-- Base gain per successful event, before diminishing + opponent scaling. Each action feeds a
-- PRIMARY stat plus small spillover: punches (light + heavy) build Strength, evading (dodge +
-- vanish) builds Speed, ki blasts build KiControl, and ANY exchange builds BattleExperience -- the
-- "you fight a lot" stat. The spread is deliberate: cheap spammable actions are worth little,
-- committal / skilful ones a lot.
local GAIN = {
	-- Primary -- the action's main stat.
	Light = 1, -- Strength: a quick physical strike (M1, spammable -> cheap)
	Heavy = 4, -- Strength: a committed power blow
	KiBlast = 3, -- KiControl: shaping a ki blast
	TakeHit = 1.5, -- Endurance: eating a blow
	Block = 2, -- Endurance: absorbing one on guard
	Dodge = 2, -- Speed: slipping a hit entirely (evasion)
	Vanish = 2.5, -- Speed: an evasive blink behind a target
	Parry = 6, -- BattleExperience: a high-skill defensive read
	-- Secondary spillover -- every exchange also banks a little BattleExperience.
	Fight = 0.5, -- landing / taking / blocking / dodging a hit -> BattleExperience
}

-- diminish(base) = 1 / (1 + base/SOFTCAP): 1x at 0, 0.5x at SOFTCAP, 0.33x at 2*SOFTCAP.
-- Larger SOFTCAP = slower taper = longer grind. This value targets the "standard" tier; drop it
-- for casual, raise it for hardcore.
local SOFTCAP = 5000

-- Training against a real player pays full; a shadow / NPC dummy pays less, so PvP always leads.
local OPPONENT_MULT = { Player = 1, Dummy = 0.4 }

-- The live Humanoid.Stats attributes are re-derived at most this often per player while training,
-- so a fast M1 combo doesn't recompute every stat each swing.
local REFRESH_INTERVAL = 3

-- Training is tiring: each successful event spends a small RANDOM slice of Longevity -- a 0-100 pool
-- that starts full. At 0 you gain nothing until you Rest to refill it (see StateBinders), the soft
-- gate that stops endless BP farming. Kept low so a normal fight barely notices -- the pool funds a
-- few minutes of continuous training first. Drain is flat per event, so committal/skilful actions
-- (which bank more stats per event) are more Longevity-efficient than M1 spam -- intended.
local LONGEVITY_DRAIN_MIN = 0.1
local LONGEVITY_DRAIN_MAX = 0.3

-- High-gravity training is more TIRING: the per-event Longevity drain scales by the gravity training
-- bonus raised to this exponent (0.5 = sqrt). Total gains per Longevity pool then scale with
-- bonus^(1 - exp), so high gravity still nets MORE per pool (the bonus outruns the drain) but Longevity
-- keeps it from being a free lunch. Set to 0 to decouple (flat drain regardless of gravity).
local LONGEVITY_GRAVITY_DRAIN_EXP = 0.5

-- Training weights (the WeightTraining / Weight attributes the ToggleWeights item sets on the
-- character) accelerate every gain: heavier weights, faster growth. The multiplier is
-- 1 + Weight * WEIGHT_GAIN_PER_TON, so the 0.25-ton starter set pays 1.25x and each extra ton adds
-- another full base's worth. It rides on top of opponent scaling and diminishing returns, and only
-- counts while the weights are actually worn (the flag is cleared on unequip and on respawn).
local WEIGHT_GAIN_PER_TON = 1.0
-- ====================================================================================

local pendingRefresh = setmetatable({} :: { [Player]: boolean }, { __mode = "k" })

local function requestRefresh(player: Player): ()
	if pendingRefresh[player] then
		return
	end
	pendingRefresh[player] = true
	task.delay(REFRESH_INTERVAL, function(): ()
		pendingRefresh[player] = nil
		-- preserveHealth: training only ever raises MaxHealth, so this clamps (never heals) -- you
		-- don't get topped up mid-fight for landing hits.
		if player.Parent and player.Character then
			StatsManager.refresh(player, { preserveHealth = true })
		end
	end)
end

local function diminish(base: number): number
	return 1 / (1 + base / SOFTCAP)
end

local function opponentMult(opponent: Model?): number
	if not opponent then
		return 1
	end
	return if Players:GetPlayerFromCharacter(opponent) then OPPONENT_MULT.Player else OPPONENT_MULT.Dummy
end

-- Weights worn on the trainee scale every gain up. Reads the live character attributes the
-- ToggleWeights item writes; returns 1 (no change) whenever weights are off or the amount is missing.
local function weightMult(character: Model): number
	if character:GetAttribute("WeightTraining") ~= true then
		return 1
	end
	local weight = character:GetAttribute("Weight")
	if type(weight) ~= "number" then
		return 1
	end
	return 1 + weight * WEIGHT_GAIN_PER_TON
end

-- Internal: apply one stat's diminished, mult-scaled gain to an already-fetched slot.
local function applyGain(slot: any, statName: string, amount: number, mult: number): ()
	local stat = slot[statName]
	if stat and stat.Base ~= nil then
		stat.Base += amount * diminish(stat.Base) * mult
	end
end

-- Core engine. Awards a BUNDLE of stat gains in one slot fetch + one refresh; `gains` maps
-- statName -> baseAmount. No-ops for anything without a live profile (NPCs, shadows). `opponent`,
-- if given, scales every gain (a real player trains you faster than a dummy).
function Train.awardMany(character: Model, gains: { [string]: number }, opponent: Model?): ()
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	local slot = Manager.getActiveSlot(player)
	if not slot then
		return
	end
	-- Longevity gate: an empty pool yields no training until the player Rests to refill it.
	if slot.Longevity <= 0 then
		return
	end
	-- Weights AND ambient gravity scale the trainee's own gains (training under gravity you've
	-- mastered banks faster, like weights); opponent scaling rides on top.
	local gravityMult = Gravity.trainMult(character)
	local mult = opponentMult(opponent) * weightMult(character) * gravityMult
	for statName, amount in gains do
		applyGain(slot, statName, amount, mult)
	end
	-- Spend a random slice of Longevity, scaled up by the gravity bonus so high-G training tires you
	-- faster (still net-positive per pool -- see LONGEVITY_GRAVITY_DRAIN_EXP).
	local drain = RNG:NextNumber(LONGEVITY_DRAIN_MIN, LONGEVITY_DRAIN_MAX) * gravityMult ^ LONGEVITY_GRAVITY_DRAIN_EXP
	slot.Longevity = math.max(0, slot.Longevity - drain)
	requestRefresh(player)
end

-- Single-stat convenience over awardMany.
function Train.award(character: Model, statName: string, baseAmount: number, opponent: Model?): ()
	Train.awardMany(character, { [statName] = baseAmount }, opponent)
end

-- Combat-event API: call sites name the event, Train owns which stats each feeds (primary +
-- spillover). A landed blow trains the attacker's offence and the target's Endurance, and both
-- sides bank a little BattleExperience for being in the fight.
function Train.landedLight(attacker: Model, target: Model): ()
	Train.awardMany(attacker, { Strength = GAIN.Light, BattleExperience = GAIN.Fight }, target)
	Train.awardMany(target, { Endurance = GAIN.TakeHit, BattleExperience = GAIN.Fight }, attacker)
end

function Train.landedHeavy(attacker: Model, target: Model): ()
	Train.awardMany(attacker, { Strength = GAIN.Heavy, BattleExperience = GAIN.Fight }, target)
	Train.awardMany(target, { Endurance = GAIN.TakeHit, BattleExperience = GAIN.Fight }, attacker)
end

function Train.landedKiBlast(attacker: Model, target: Model): ()
	Train.awardMany(attacker, { KiControl = GAIN.KiBlast, BattleExperience = GAIN.Fight }, target)
	Train.awardMany(target, { Endurance = GAIN.TakeHit, BattleExperience = GAIN.Fight }, attacker)
end

function Train.blocked(defender: Model, attacker: Model): ()
	Train.awardMany(defender, { Endurance = GAIN.Block, BattleExperience = GAIN.Fight }, attacker)
end

-- The defender slipped the hit entirely (Damage.apply returned 0): pure evasion -> Speed.
function Train.dodged(defender: Model, attacker: Model): ()
	Train.awardMany(defender, { Speed = GAIN.Dodge, BattleExperience = GAIN.Fight }, attacker)
end

function Train.parried(defender: Model, attacker: Model): ()
	Train.awardMany(defender, { BattleExperience = GAIN.Parry }, attacker)
end

-- An evasive vanish (blink behind a locked target) -> Speed.
function Train.vanished(character: Model, target: Model?): ()
	Train.award(character, "Speed", GAIN.Vanish, target)
end

return Train
