--!strict
-- Energy Wave: a quick aimed Ki beam. Charges briefly on the firing arm, then opens a straight
-- damage lane toward the aim (lock-on > mouse > look). Ported from GlobalSkillSet onto the
-- query-based hitbox -- the beam VFX is cosmetic; Shared.beamDamage owns the hit (each target once).

local ServerStorage = game:GetService("ServerStorage")

local Shared = require(ServerStorage.Modules.Skills.Shared)
local SkillState = require(ServerStorage.Modules.SkillState)

local CHARGE_TIME = 0.5
local BEAM_LENGTH = 200
local BEAM_WIDTH = 6
local BEAM_DURATION = 1.0
local KNOCKBACK = 120
local CLEANUP_DELAY = 2

return function(context: SkillState.Context): ()
	local character = context.character
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local direction = Shared.aimDirection(character, context.aim)
	local origin = root.Position

	-- Face the aim, flattened so the model doesn't tip on steep shots.
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude > 0.05 then
		character:PivotTo(CFrame.lookAt(origin, origin + flat))
	end

	Shared.playAnim(character, "EnergyWave")
	character:SetAttribute("Casting", true)
	character:SetAttribute("Stunned", true)

	-- Cosmetic muzzle (guarded; damage lands with or without it). TODO: wire the real beam asset's
	-- Start/End/Beam attachments once its place-side structure is known.
	local container = Instance.new("Folder")
	container.Name = `{character.Name}_EnergyWave`
	container.Parent = Shared.effectsFolder()

	local arm = (character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")) :: BasePart?
	local template = Shared.skillAsset("Energy Wave")
	if template and template:IsA("BasePart") and arm then
		local beamPart = template:Clone()
		Shared.tint(beamPart, Shared.kiColour(character))
		Shared.emitAll(beamPart, 20)
		beamPart.Anchored = true
		beamPart.CanCollide = false
		beamPart.CFrame = CFrame.lookAt(arm.Position, arm.Position + direction)
		beamPart.Parent = container
	end

	task.wait(CHARGE_TIME)

	-- Fire: open the damage lane from just in front of the chest.
	local muzzle = origin + direction * 3 + Vector3.new(0, 1.5, 0)
	Shared.beamDamage(character, muzzle, direction, {
		length = BEAM_LENGTH,
		width = BEAM_WIDTH,
		strength = context.def.strength,
		duration = BEAM_DURATION,
		knockback = KNOCKBACK,
	})

	task.wait(CLEANUP_DELAY)

	container:Destroy()
	character:SetAttribute("Casting", false)
	character:SetAttribute("Stunned", false)
	Shared.stopAnim(character, "EnergyWave")
end
