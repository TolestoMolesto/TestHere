--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Remotes = require(ReplicatedStorage.Modules.Remotes)

local KNOCKBACK_DURATION = 5.0
local RECOVERY_START_TIME = 0.5

local function resolveVFX(name: string): Instance?
	return ServerStorage.Assets.VFX:FindFirstChild(name)
end
local EFFECT_TEMPLATE: Instance? = resolveVFX("KnockbackFXTemplate")

local function resolveVelocityTemplate(): BodyVelocity
	local existing = script:FindFirstChild("BodyVelocity")
	if existing and existing:IsA("BodyVelocity") then
		return existing
	end
	local template = Instance.new("BodyVelocity")
	template.Name = "BodyVelocity"
	template.MaxForce = Vector3.new(1, 1, 1) * math.huge
	template.P = 1250
	template.Velocity = Vector3.zero
	template.Parent = script
	return template
end
local VELOCITY_TEMPLATE = resolveVelocityTemplate()

-- Indexed directly (not FindFirstChild) on purpose: a missing part is meant to throw.
type Character = Model & {
	Humanoid: Humanoid,
	HumanoidRootPart: BasePart,
}

local Knockback = {}

local objectCache = setmetatable({} :: { [Model]: { Instance } }, { __mode = "k" })
local knockbackGeneration = setmetatable({} :: { [Model]: number }, { __mode = "k" })

local function clearKnockbackState(entity: Model): ()
	local character = entity :: Character
	character.Humanoid.AutoRotate = true
	entity:SetAttribute("HitByKnockBack", false)
	entity:SetAttribute("CanRecover", false)
	entity:SetAttribute("CanVanishTo", false)
end

local function performRecovery(entityCharacter: Model): ()
	local character = entityCharacter :: Character
	character.HumanoidRootPart.Anchored = true

	local playerFound = Players:GetPlayerFromCharacter(entityCharacter)
	if playerFound then
		Remotes.UpdateFlightPosition:FireClient(playerFound, character.HumanoidRootPart.Position)
	end

	local recoveryCache = objectCache[entityCharacter]
	if recoveryCache then
		for _, object in recoveryCache do
			object:Destroy()
		end
	end

	character.HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
	character.HumanoidRootPart.Anchored = false
	objectCache[entityCharacter] = nil
	knockbackGeneration[entityCharacter] = nil

	clearKnockbackState(entityCharacter)
end

function Knockback.apply(entityCharacter: Model, direction: Vector3, force: number?, suppressAutoRecovery: boolean?): ()
	-- Spawn protection / intangibility: a Forcefield target can't be displaced.
	if entityCharacter:GetAttribute("Forcefield") then
		return
	end
	local character = entityCharacter :: Character
	local castedForce = force or 150

	local generation = (knockbackGeneration[entityCharacter] or 0) + 1
	knockbackGeneration[entityCharacter] = generation

	local previousCache = objectCache[entityCharacter]
	if previousCache then
		for _, object in previousCache do
			object:Destroy()
		end
	end
	local newCache = {}

	local fxTemplate = EFFECT_TEMPLATE
	if fxTemplate then
		for _, childEffect in fxTemplate:GetChildren() do
			local effect = childEffect:Clone()
			effect.Parent = character.HumanoidRootPart
			table.insert(newCache, effect)
		end
	end

	local velocityInstance = VELOCITY_TEMPLATE:Clone()
	velocityInstance.Name = "KnockbackVelocity"
	velocityInstance.Velocity = direction * castedForce
	velocityInstance.Parent = character.HumanoidRootPart
	table.insert(newCache, velocityInstance)

	objectCache[entityCharacter] = newCache
	character.Humanoid.AutoRotate = false
	entityCharacter:SetAttribute("HitByKnockBack", true)
	entityCharacter:SetAttribute("CanVanishTo", true)

	-- Generation-guarded: a superseded knockback's stale timer must not grant CanRecover.
	task.delay(RECOVERY_START_TIME, function(): ()
		if knockbackGeneration[entityCharacter] == generation and entityCharacter:GetAttribute("HitByKnockBack") then
			entityCharacter:SetAttribute("CanRecover", true)
		end
	end)

	if not suppressAutoRecovery then
		task.delay(KNOCKBACK_DURATION, function(): ()
			if
				knockbackGeneration[entityCharacter] == generation and entityCharacter:GetAttribute("HitByKnockBack")
			then
				performRecovery(entityCharacter)
			end
		end)
	end
end

function Knockback.cancel(entity: Model): ()
	performRecovery(entity)
end

return Knockback
