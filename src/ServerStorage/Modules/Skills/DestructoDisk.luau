--!strict
-- Destructo Disk: a fast homing blade. Spins up on the palm, then launches toward the aim and
-- steers into the lock-on target. One clean hit via the shared projectile (radius scan), then it's
-- spent. Ported from GlobalSkillSet onto the query-based projectile (no Touched / SkillVelocity).

local ServerStorage = game:GetService("ServerStorage")

local Shared = require(ServerStorage.Modules.Skills.Shared)
local SkillState = require(ServerStorage.Modules.SkillState)

local CHARGE_TIME = 0.5
local SPEED = 200
local LIFETIME = 7
local HIT_RADIUS = 4
local KNOCKBACK = 120
local SPAWN_OFFSET = Vector3.new(0, 3, 0)

return function(context: SkillState.Context): ()
	local character = context.character
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local arm = (character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")) :: BasePart?

	local direction = Shared.aimDirection(character, context.aim)

	Shared.playAnim(character, "DestructoDisk")
	character:SetAttribute("Stunned", true)
	root.Anchored = true

	-- Charge: spin up the disk on the palm (cosmetic, guarded).
	local template = Shared.skillAsset("Destructo Disk")
	local disk: BasePart? = nil
	if template and template:IsA("BasePart") then
		local clone = template:Clone()
		Shared.tint(clone, Shared.kiColour(character))
		Shared.emitAll(clone, 10)
		clone.Anchored = true
		clone.CanCollide = false
		clone.CFrame = CFrame.new((arm or root).Position + SPAWN_OFFSET)
		clone.Parent = Shared.effectsFolder()
		disk = clone
	end

	task.wait(CHARGE_TIME)

	root.Anchored = false
	character:SetAttribute("Stunned", false)

	-- Fly the cosmetic disk if we have one; otherwise an invisible carrier so the hit still resolves.
	local projectile: BasePart
	if disk then
		projectile = disk
	else
		local carrier = Instance.new("Part")
		carrier.Transparency = 1
		carrier.Size = Vector3.new(1, 1, 1)
		carrier.Anchored = true
		carrier.CanCollide = false
		carrier.CFrame = CFrame.new(root.Position + SPAWN_OFFSET)
		carrier.Parent = Shared.effectsFolder()
		projectile = carrier
	end

	Shared.launchProjectile(character, projectile, direction, {
		speed = SPEED,
		lifetime = LIFETIME,
		radius = HIT_RADIUS,
		strength = context.def.strength,
		knockback = KNOCKBACK,
		homing = true,
	})

	Shared.stopAnim(character, "DestructoDisk")
end
