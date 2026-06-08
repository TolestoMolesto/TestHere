--!strict
local Chat = game:GetService("Chat")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Manager = require(ServerStorage.PlayerData.Manager)
local UpdateStats = require(ServerStorage.Modules.UpdateStats)

local TrainingModule = {}

local RACE_TRAINING_RATES = {
	Saiyan =              { KiBlast = 20, HeavyAttack = 35, LightAttack = 50, WeightTraining = 55, ShadowHit = 30 },
	LegendarySuperSaiyan = { KiBlast = 25, HeavyAttack = 40, LightAttack = 45, WeightTraining = 60, ShadowHit = 35 },
	Acrosian =            { KiBlast = 30, HeavyAttack = 30, LightAttack = 45, WeightTraining = 50, ShadowHit = 25 },
	Namekian =            { KiBlast = 25, HeavyAttack = 32, LightAttack = 42, WeightTraining = 55, ShadowHit = 32 },
	Human =               { KiBlast = 22, HeavyAttack = 33, LightAttack = 48, WeightTraining = 58, ShadowHit = 28 },
	Majin =               { KiBlast = 28, HeavyAttack = 35, LightAttack = 40, WeightTraining = 48, ShadowHit = 38 },
	Sphinx =              { KiBlast = 24, HeavyAttack = 36, LightAttack = 52, WeightTraining = 52, ShadowHit = 30 },
}

local DEFAULT_RATES = { KiBlast = 20, HeavyAttack = 32, LightAttack = 45, WeightTraining = 50, ShadowHit = 25 }
local ADMIN_MULTIPLIERS = { KAI = 2.5, GOD = 5, ANGEL = 10 }

local GRAVITY_CHAMBER_PLACE_ID = 70731873074651
local GRAVITY_CHAMBER_BOOST = 1.5
local HTC_PLACE_ID = 87688265644198
local HTC_LONGEVITY_COST = 0.05 -- 5% of normal drain — time barely passes outside

local LIMIT_BREAK = {
	BASE_GAIN = 1,
	GRAVITY_GAP_MULTIPLIER = 0.035,
	MAX_GRAVITY_BONUS = 3,
	WEIGHT_TRAINING_MULTIPLIER = 2.5,
	OVERFLOW_SCALING = 2,
	ADMIN_MULTIPLIER = 5,
	BP_SCALING_DIVISOR = 50000,
	BP_BONUS_PERCENT = 0.02,
	BP_BONUS_MIN = 500,
}

local GRAVITY_GROWTH_STAGES = {
	{ threshold = 0.5,  factor = 0.05 },
	{ threshold = 0.6,  factor = 0.2  },
	{ threshold = 0.75, factor = 0.45 },
	{ threshold = 0.85, factor = 0.7  },
	{ threshold = 0.95, factor = 0.5  },
	{ threshold = 0.99, factor = 0.75 },
	{ threshold = 1.0,  factor = 0.4  },
}

local TRAINING_CONSTANTS = {
	BASE_BP_MULTIPLIER = 3,
	LONGEVITY_BASE_PENALTY = 0.2,
	LONGEVITY_GRAVITY_PENALTY = 0.04,
	LONGEVITY_FAIL_DRAIN_RATIO = 0.25,
	BP_GAIN_MIN = 2,
	BP_GAIN_MAX = 5,
	SOFT_CAP_MULTIPLIER = 2,
	LB_THRESHOLD_PERCENTAGE = 0.45,
	LB_THRESHOLD_MIN = 5000,
	LB_THRESHOLD_MAX = 100000,
	LB_THRESHOLD_INITIAL_MIN = 500,
	LB_THRESHOLD_INITIAL_MAX = 5000,
	SWEATING_DURATION = 2,
	GRAVITY_BASE_GAIN = 0.0001,
	GRAVITY_GROWTH_MULTIPLIER = 0.0003,
	LONGEVITY_MAX_PENALTY = 2,
}

local function getServerSetting(path: string): any
	local current = ServerScriptService.ServerSettings
	for segment in string.gmatch(path, "[^.]+") do
		current = current:FindFirstChild(segment)
		if not current then
			return nil
		end
	end
	return current
end

local function getGravityValue(): number
	local setting = getServerSetting("Gravity")
	return setting and setting.Value or 1
end

local function getBPMultiplierActive(multiplierName: string): boolean
	local setting = getServerSetting("Timers." .. multiplierName)
	return setting ~= nil and setting.Value ~= 0
end

local function getAdminMultipliers(profile): number
	local multiplier = 1
	if not profile.Data.Admin then return multiplier end

	if profile.Data.Admin.KAI   == true then multiplier = math.max(multiplier, ADMIN_MULTIPLIERS.KAI)   end
	if profile.Data.Admin.GOD   == true then multiplier = math.max(multiplier, ADMIN_MULTIPLIERS.GOD)   end
	if profile.Data.Admin.ANGEL == true then multiplier = math.max(multiplier, ADMIN_MULTIPLIERS.ANGEL) end

	return multiplier
end

local function getEventMultipliers(): number
	local multiplier = 1
	if getBPMultiplierActive("TwoTimeBPMulti")   then multiplier *= 2 end
	if getBPMultiplierActive("ThreeTimeBPMulti") then multiplier *= 3 end
	return multiplier
end

local function getTrainingSuccessChance(action: string, profile): number
	local race = profile.Data.Stats.Race or "Human"
	local raceRates = RACE_TRAINING_RATES[race] or DEFAULT_RATES
	local baseChance = raceRates[action] or DEFAULT_RATES[action] or 5

	if profile.Data.Skills and profile.Data.Skills["The Blessed"] == true then
		baseChance *= 1.5
	end

	return baseChance
end

local function calculateBPGain(profile, character: Model, baseMultiplier: number): number
	local bpBoost = profile.Data.Stats.BPBoost or 1
	local gravityValue = getGravityValue()
	local playerGravity = character:GetAttribute("Gravity") or 0
	local gravityGap = math.max(gravityValue - playerGravity, 0)

	local base = TRAINING_CONSTANTS.BASE_BP_MULTIPLIER * bpBoost * (1 + gravityGap / 200)

	if character:GetAttribute("WeightTraining") then
		local weight = character:GetAttribute("Weight") or 0
		base *= 1 + weight
	end

	return base * getAdminMultipliers(profile) * getEventMultipliers() + baseMultiplier
end

local function calculateLimitBreakGain(profile, character: Model, gravityValue: number): number
	local currentBP = profile.Data.Stats.Battlepower.Base or 0
	local playerGravity = profile.Data.Stats.Gravity or 0
	local gravityGap = math.max(gravityValue - playerGravity, 0)

	local gravityBonus = math.clamp(gravityGap * LIMIT_BREAK.GRAVITY_GAP_MULTIPLIER, 0, LIMIT_BREAK.MAX_GRAVITY_BONUS)
	local gravityFactor = math.clamp(1 + gravityGap / 5, 1, 100)
	local bpFactor = math.max(1, math.sqrt(currentBP / LIMIT_BREAK.BP_SCALING_DIVISOR))
	local lbGain = (LIMIT_BREAK.BASE_GAIN + gravityBonus) * gravityFactor * bpFactor

	if character:GetAttribute("WeightTraining") then
		lbGain *= LIMIT_BREAK.WEIGHT_TRAINING_MULTIPLIER
	end

	local softCap = profile.Data.Extras.SoftCap or 0
	if currentBP > softCap then
		local overflow = currentBP - softCap
		lbGain += math.clamp(overflow / softCap, 0, LIMIT_BREAK.OVERFLOW_SCALING) * 2
	end

	local baseCap = character:GetAttribute("WeightTraining") and 50 or 10
	lbGain = math.min(lbGain, math.floor(baseCap * gravityFactor * bpFactor))

	if getAdminMultipliers(profile) > 1 then
		lbGain *= LIMIT_BREAK.ADMIN_MULTIPLIER
	end

	if game.PlaceId == GRAVITY_CHAMBER_PLACE_ID then
		lbGain *= GRAVITY_CHAMBER_BOOST
	end

	return lbGain
end

local function fireLimitBreak(profile, character: Model): ()
	local currentBP = profile.Data.Stats.Battlepower.Base or 0
	local bpBonus = math.max(currentBP * LIMIT_BREAK.BP_BONUS_PERCENT, LIMIT_BREAK.BP_BONUS_MIN)

	profile.Data.Extras.LimitBreakProgress = 0
	profile.Data.Stats.Battlepower.Base = currentBP + bpBonus
	profile.Data.Extras.SoftCap = profile.Data.Stats.Battlepower.Base * TRAINING_CONSTANTS.SOFT_CAP_MULTIPLIER
	profile.Data.Extras.LimitBreakThreshold = math.clamp(
		profile.Data.Stats.Battlepower.Base * TRAINING_CONSTANTS.LB_THRESHOLD_PERCENTAGE,
		TRAINING_CONSTANTS.LB_THRESHOLD_MIN,
		TRAINING_CONSTANTS.LB_THRESHOLD_MAX
	)

	local head = character:FindFirstChild("Head")
	if head then
		local msg = game.PlaceId == HTC_PLACE_ID
			and "A YEAR OF TRAINING IN A SINGLE DAY... I'VE SHATTERED MY LIMITS!!!"
			or "I'VE REACHED PAST MY LIMITS!!!"
		Chat:Chat(head, msg, Enum.ChatColor.Red)
	end
end

local function processLimitBreak(profile, character: Model, gravityValue: number): boolean
	local softCap = profile.Data.Extras.SoftCap or 0
	local currentBP = profile.Data.Stats.Battlepower.Base or 0

	if softCap <= 0 then
		profile.Data.Extras.SoftCap = math.max(currentBP * TRAINING_CONSTANTS.SOFT_CAP_MULTIPLIER, 1)
		return false
	end

	if not profile.Data.Extras.LimitBreakThreshold or profile.Data.Extras.LimitBreakThreshold == 0 then
		profile.Data.Extras.LimitBreakThreshold = math.clamp(
			softCap * TRAINING_CONSTANTS.LB_THRESHOLD_PERCENTAGE,
			TRAINING_CONSTANTS.LB_THRESHOLD_INITIAL_MIN,
			TRAINING_CONSTANTS.LB_THRESHOLD_INITIAL_MAX
		)
	end

	local lbThreshold = profile.Data.Extras.LimitBreakThreshold
	local savedProgress = profile.Data.Extras.LimitBreakProgress or 0

	-- Fire a pending break if progress was already at the threshold from a previous session
	if savedProgress >= lbThreshold then
		fireLimitBreak(profile, character)
		return true
	end

	if currentBP < softCap then
		return false
	end

	local lbProgress = savedProgress + calculateLimitBreakGain(profile, character, gravityValue)

	if lbProgress >= lbThreshold then
		fireLimitBreak(profile, character)
		return true
	end

	profile.Data.Extras.LimitBreakProgress = lbProgress
	return false
end

local function applyLongevityDrain(profile, character: Model, gravityValue: number, drainMultiplier: number?): ()
	local playerGravity = profile.Data.Stats.Gravity or 0
	local gravityGap = gravityValue - playerGravity
	local penalty = gravityGap > 0
		and (TRAINING_CONSTANTS.LONGEVITY_BASE_PENALTY + gravityGap * TRAINING_CONSTANTS.LONGEVITY_GRAVITY_PENALTY)
		or TRAINING_CONSTANTS.LONGEVITY_BASE_PENALTY

	penalty = math.min(penalty, TRAINING_CONSTANTS.LONGEVITY_MAX_PENALTY) * (drainMultiplier or 1)

	if game.PlaceId == HTC_PLACE_ID then
		penalty *= HTC_LONGEVITY_COST
	end

	profile.Data.Stats.Longevity = math.max(profile.Data.Stats.Longevity - penalty, 0)

	if character then
		character:SetAttribute("Longevity", math.floor(profile.Data.Stats.Longevity))
	end
end

local function getBPScaling(currentBP: number): number
	-- Scale factor grows sub-linearly with BP: 1.0x at 0 → 2.1x at 1M+
	if currentBP < 1000    then return 1.0 + (currentBP / 1000) * 0.3 end
	if currentBP < 10000   then return 1.3 + ((currentBP - 1000)   / 9000)   * 0.2 end
	if currentBP < 50000   then return 1.5 + ((currentBP - 10000)  / 40000)  * 0.2 end
	if currentBP < 100000  then return 1.7 + ((currentBP - 50000)  / 50000)  * 0.1 end
	if currentBP < 500000  then return 1.8 + ((currentBP - 100000) / 400000) * 0.2 end
	if currentBP < 1000000 then return 2.0 + ((currentBP - 500000) / 500000) * 0.1 end
	return 2.1
end

local function applyBattlePowerGain(profile, baseBPGain: number): ()
	local currentBP = profile.Data.Stats.Battlepower.Base or 0
	local softCap = profile.Data.Extras.SoftCap or 0
	local randomMultiplier = math.random(TRAINING_CONSTANTS.BP_GAIN_MIN, TRAINING_CONSTANTS.BP_GAIN_MAX)
	local scaling = getBPScaling(currentBP)

	local gain
	if currentBP < softCap then
		gain = randomMultiplier * baseBPGain * scaling
	else
		local reductionFactor = 1 / (1 + ((currentBP - softCap) / math.max(softCap, 1)))
		gain = randomMultiplier * baseBPGain * reductionFactor * scaling
	end

	profile.Data.Stats.Battlepower.Base += gain
end

local function getGravityGrowthFactor(adaptationRatio: number): number
	for _, stage in GRAVITY_GROWTH_STAGES do
		if adaptationRatio < stage.threshold then
			return stage.factor
		end
	end
	return 0
end

local function updateGravityResistance(profile, character: Model, gravityValue: number): ()
	local playerGravity = profile.Data.Stats.Gravity or 0
	if playerGravity >= gravityValue then return end

	local growthFactor = getGravityGrowthFactor(playerGravity / gravityValue)
	local growth = (TRAINING_CONSTANTS.GRAVITY_BASE_GAIN + growthFactor * TRAINING_CONSTANTS.GRAVITY_GROWTH_MULTIPLIER)
		/ math.sqrt(gravityValue)

	if game.PlaceId == GRAVITY_CHAMBER_PLACE_ID then growth *= GRAVITY_CHAMBER_BOOST end

	if character:GetAttribute("WeightTraining") then
		local weight = character:GetAttribute("Weight") or 0
		growth *= 1 + weight
	end

	profile.Data.Stats.Gravity = playerGravity + growth
end

function TrainingModule.Train(player: Player, action: string, multiplier: number?): boolean
	if not player or not player.Parent then return false end

	local character = player.Character
	if not character or not character.Parent then return false end

	local profile = Manager.getProfile(player)
	if not profile then return false end

	local gravityValue = getGravityValue()

	if not profile.Data.Stats.Longevity or profile.Data.Stats.Longevity <= 0 then
		profile.Data.Stats.Longevity = 0
		UpdateStats.StatUpdate(player)
		return false
	end

	processLimitBreak(profile, character, gravityValue)
	updateGravityResistance(profile, character, gravityValue)

	local trainingChance = getTrainingSuccessChance(action, profile)
	if math.random(1, 100) > trainingChance then
		applyLongevityDrain(profile, character, gravityValue, TRAINING_CONSTANTS.LONGEVITY_FAIL_DRAIN_RATIO)
		UpdateStats.StatUpdate(player)
		return false
	end

	local baseBPGain = calculateBPGain(profile, character, multiplier or 1)
	applyLongevityDrain(profile, character, gravityValue)
	applyBattlePowerGain(profile, baseBPGain)

	character:SetAttribute("Sweating", true)
	task.delay(TRAINING_CONSTANTS.SWEATING_DURATION, function()
		if character and character.Parent then
			character:SetAttribute("Sweating", false)
		end
	end)

	UpdateStats.StatUpdate(player)
	return true
end

return TrainingModule
