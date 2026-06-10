--!strict
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Train = require(ServerStorage.Modules.Train)

type Effect = Part & {
	Attacher: {
		Expander: ParticleEmitter,
		Shrink: ParticleEmitter,
	},
}

type EntityCharacter = Model & {
	Humanoid: Humanoid,
	HumanoidRootPart: BasePart,
}

local function resolveVFX(name: string): Instance?
	return ServerStorage.Assets.VFX:FindFirstChild(name)
end
local EFFECT_TEMPLATE = resolveVFX("ParryFXTemplate") :: Effect?

local configuration = {
	TIMEOUT = 1.2,
}

local ParryHandler = {
	Configuration = configuration,
}

local stunGeneration = setmetatable({} :: { [Model]: number }, { __mode = "k" })

local function setAttributes(instance: Instance, attributes: { [string]: any }): ()
	for name, value in attributes do
		instance:SetAttribute(name, value)
	end
end

local function stopTrack(character: Model, trackName: string): ()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	for _, track in (animator :: Animator):GetPlayingAnimationTracks() do
		if track.Name == trackName then
			track:Stop()
		end
	end
end

local function playParryAnimation(character: Model, direction: string): ()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChild("Animator") :: Animator?
	if not animator then
		local created = Instance.new("Animator") :: Animator
		created.Parent = humanoid
		animator = created
	end

	local animationToPlay = if direction == "Left"
		then script:FindFirstChild("ParryLeft")
		else script:FindFirstChild("ParryRight")
	if not animationToPlay or not animationToPlay:IsA("Animation") then
		return
	end

	local track = (animator :: Animator):LoadAnimation(animationToPlay)
	track:Play()
	track.Stopped:Once(function()
		track:Destroy()
	end)
end

local function setShadowConfig(character: Model, values: { [string]: boolean }): ()
	local config = character:FindFirstChild("Config")
	if not config then
		return
	end

	for name, value in values do
		local boolValue = config:FindFirstChild(name)
		if boolValue and boolValue:IsA("BoolValue") then
			boolValue.Value = value
		end
	end
end

function ParryHandler.parry(attacker: Model, target: Model): ()
	local attackingCharacter = attacker :: EntityCharacter
	local targetCharacter = target :: EntityCharacter
	local attackerCombo = attackingCharacter:GetAttribute("AttackSequence") :: number

	-- The defender read the attack and parried: reward their BattleExperience.
	Train.parried(targetCharacter, attackingCharacter)

	stopTrack(attackingCharacter, "Block")

	if attackerCombo == 3 then
		playParryAnimation(targetCharacter, "Left")
	else
		playParryAnimation(targetCharacter, "Right")
	end

	-- Probe the cloned asset's shape defensively: a malformed template degrades to no VFX.
	if EFFECT_TEMPLATE then
		local effect = EFFECT_TEMPLATE:Clone()
		effect.CFrame = targetCharacter.HumanoidRootPart.CFrame * CFrame.new(0, 0, -2)
		effect.Parent = Workspace

		task.spawn(function(): ()
			local attacher = effect:FindFirstChild("Attacher")
			local expander = attacher and attacher:FindFirstChild("Expander")
			local shrink = attacher and attacher:FindFirstChild("Shrink")
			if expander and expander:IsA("ParticleEmitter") then
				expander:Emit()
			end
			task.wait(0.1)
			if shrink and shrink:IsA("ParticleEmitter") then
				shrink:Emit()
			end
			task.wait(1)
			effect:Destroy()
		end)
	end

	setAttributes(attackingCharacter, {
		Blocking = false,
		NoAttacking = true,
		Stunned = true,
	})
	setShadowConfig(attackingCharacter, { Stunned = true, NoAttacking = true, Blocking = false })

	local gen = (stunGeneration[attackingCharacter] or 0) + 1
	stunGeneration[attackingCharacter] = gen

	task.delay(configuration.TIMEOUT, function(): ()
		-- Only the latest parry clears the stun; a re-parry bumped the generation.
		if stunGeneration[attackingCharacter] ~= gen then
			return
		end
		stunGeneration[attackingCharacter] = nil
		setAttributes(attackingCharacter, {
			NoAttacking = false,
			Stunned = false,
		})
		setShadowConfig(attackingCharacter, { Stunned = false, NoAttacking = false })
	end)
end

return ParryHandler
