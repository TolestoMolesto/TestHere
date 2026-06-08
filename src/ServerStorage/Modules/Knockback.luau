--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Remotes = require(ReplicatedStorage.Modules.Remotes)

local KNOCKBACK_DURATION = 5.0
local RECOVERY_START_TIME = 0.5

local EFFECT_TEMPLATE: Part = ServerStorage.HitFX.KnockbackFXTemplate
local VELOCITY_TEMPLATE = script.BodyVelocity
local Knockback = {}

local objectCache = setmetatable({} :: { [Model]: { Instance } }, { __mode = "k" })
local knockbackGeneration = setmetatable({} :: { [Model]: number }, { __mode = "k" })

local function clearKnockbackState(entity: Model): ()
	entity.Humanoid.AutoRotate = true
	entity:SetAttribute("HitByKnockBack", false)
	entity:SetAttribute("CanRecover", false)
	entity:SetAttribute("CanVanishTo", false)
end

local function performRecovery(entityCharacter: Model): ()
	entityCharacter.HumanoidRootPart.Anchored = true

	local playerFound = Players:GetPlayerFromCharacter(entityCharacter)
	if playerFound then
		Remotes.UpdateFlightPosition:FireClient(playerFound, entityCharacter.HumanoidRootPart.Position)
	end

	for _, object in objectCache[entityCharacter] or {} do
		object:Destroy()
	end

	entityCharacter.HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
	entityCharacter.HumanoidRootPart.Anchored = false
	objectCache[entityCharacter] = nil
	knockbackGeneration[entityCharacter] = nil

	clearKnockbackState(entityCharacter)
end

function Knockback.apply(
	entityCharacter: Model,
	direction: Vector3,
	force: number?,
	suppressAutoRecovery: boolean?
): ()
	local castedForce = force or 150

	local generation = (knockbackGeneration[entityCharacter] or 0) + 1
	knockbackGeneration[entityCharacter] = generation

	-- Destroy any objects from a previous knockback before applying new ones
	for _, object in objectCache[entityCharacter] or {} do
		object:Destroy()
	end
	local newCache = {}

	for _, childEffect in EFFECT_TEMPLATE:GetChildren() do
		local effect = childEffect:Clone()
		effect.Parent = entityCharacter.HumanoidRootPart
		table.insert(newCache, effect)
	end

	local velocityInstance = VELOCITY_TEMPLATE:Clone()
	velocityInstance.Name = "KnockbackVelocity"
	velocityInstance.Velocity = direction * castedForce
	velocityInstance.Parent = entityCharacter.HumanoidRootPart
	table.insert(newCache, velocityInstance)

	objectCache[entityCharacter] = newCache
	entityCharacter.Humanoid.AutoRotate = false
	entityCharacter:SetAttribute("HitByKnockBack", true)
	entityCharacter:SetAttribute("CanVanishTo", true)

	task.delay(RECOVERY_START_TIME, function(): ()
		if entityCharacter:GetAttribute("HitByKnockBack") then
			entityCharacter:SetAttribute("CanRecover", true)
		end
	end)

	if not suppressAutoRecovery then
		task.delay(KNOCKBACK_DURATION, function(): ()
			if knockbackGeneration[entityCharacter] == generation and entityCharacter:GetAttribute("HitByKnockBack") then
				performRecovery(entityCharacter)
			end
		end)
	end
end

function Knockback.cancel(entity: Model): ()
	performRecovery(entity)
end

return Knockback
