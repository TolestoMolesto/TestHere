--!strict
local Debris = game:GetService("Debris")
local ServerStorage = game:GetService("ServerStorage")

local HitFXFolder = ServerStorage:FindFirstChild("HitFX", true)
local HIT_FX_TEMPLATE = HitFXFolder and HitFXFolder:FindFirstChild("HitFXTemplate")
local PARRY_FX_TEMPLATE = HitFXFolder and HitFXFolder:FindFirstChild("ParryFXTemplate")

local FX_DURATION = 1.5
local BLOCK_FX_DURATION = 1.0

-- Resolves the world position for an effect, falling back to the character's HRP.
local function resolvePosition(character: Model, hitPosition: Vector3?): Vector3?
	if hitPosition then
		return hitPosition
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return hrp and hrp.Position
end

-- Core emitter: clones all ParticleEmitters from `template` onto a temporary
-- Attachment at `position`. `defaultEmit` sets the emit count; pass `emitCounts`
-- to override per-emitter by name pattern.
local function spawnFX(
	position: Vector3,
	template: Instance,
	duration: number,
	defaultEmit: number,
	emitCounts: { [string]: number }?
): ()
	local attachment = Instance.new("Attachment")
	attachment.Name = "HitFXAttachment"
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain

	for _, emitter in template:GetChildren() do
		if not emitter:IsA("ParticleEmitter") then continue end

		local clone = emitter:Clone()
		clone.Parent = attachment

		local count = defaultEmit
		if emitCounts then
			for pattern, n in emitCounts do
				if clone.Name:lower():find(pattern:lower()) then
					count = n
					break
				end
			end
		end

		clone:Emit(count)
	end

	Debris:AddItem(attachment, duration)
end

local HitFX = {}

function HitFX.spawnOnCharacter(character: Model, hitPosition: Vector3?): ()
	if not HIT_FX_TEMPLATE then return end
	local position = resolvePosition(character, hitPosition)
	if not position then return end
	spawnFX(position, HIT_FX_TEMPLATE, FX_DURATION, 1)
end

function HitFX.spawnBlockFX(character: Model, hitPosition: Vector3?): ()
	if not PARRY_FX_TEMPLATE then return end
	local position = resolvePosition(character, hitPosition)
	if not position then return end
	spawnFX(position, PARRY_FX_TEMPLATE, BLOCK_FX_DURATION, 3)
end

function HitFX.spawnOnCharacterCustom(character: Model, hitPosition: Vector3?, emitCounts: { [string]: number }): ()
	if not HIT_FX_TEMPLATE then return end
	local position = resolvePosition(character, hitPosition)
	if not position then return end
	spawnFX(position, HIT_FX_TEMPLATE, FX_DURATION, 1, emitCounts)
end

return HitFX
