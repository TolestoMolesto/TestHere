--!strict
-- Kamehameha: the signature aimed Ki beam -- a longer charge than Energy Wave and a wider, harder
-- lane. Ported onto Shared.beamDamage. TODO: variable hold (charge longer = more damage) needs the
-- Phase 3 hold/release input + remote; for now it's a fixed charge.

local ServerStorage = game:GetService("ServerStorage")

local Shared = require(ServerStorage.Modules.Skills.Shared)
local SkillState = require(ServerStorage.Modules.SkillState)

local CHARGE_TIME = 1.5
local BEAM_LENGTH = 250
local BEAM_WIDTH = 8
local BEAM_DURATION = 1.2
local KNOCKBACK = 150
local CLEANUP_DELAY = 2.5

return function(context: SkillState.Context): ()
	local character = context.character
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local direction = Shared.aimDirection(character, context.aim)
	local origin = root.Position
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude > 0.05 then
		character:PivotTo(CFrame.lookAt(origin, origin + flat))
	end

	Shared.playAnim(character, "Kamehameha")
	character:SetAttribute("Casting", true)
	character:SetAttribute("Stunned", true)

	local container = Instance.new("Folder")
	container.Name = `{character.Name}_Kamehameha`
	container.Parent = Shared.effectsFolder()

	local arm = (character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")) :: BasePart?
	local template = Shared.skillAsset("Kamehameha")
	if template and template:IsA("BasePart") and arm then
		local muzzleOrb = template:Clone()
		Shared.tint(muzzleOrb, Shared.kiColour(character))
		Shared.emitAll(muzzleOrb, 25)
		muzzleOrb.Anchored = true
		muzzleOrb.CanCollide = false
		muzzleOrb.CFrame = CFrame.lookAt(arm.Position, arm.Position + direction)
		muzzleOrb.Parent = container
	end

	task.wait(CHARGE_TIME)

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
	Shared.stopAnim(character, "Kamehameha")
end
