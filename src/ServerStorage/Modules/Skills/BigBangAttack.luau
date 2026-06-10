--!strict
-- Big Bang Attack: charges a ball on the palm, then fires it straight ahead; on impact (a fighter
-- or the end of its flight) it detonates into a radial Ki burst. Ported onto the explodeOnly
-- projectile + Shared.aoeDamage so the struck target isn't double-hit.

local ServerStorage = game:GetService("ServerStorage")

local Shared = require(ServerStorage.Modules.Skills.Shared)
local SkillState = require(ServerStorage.Modules.SkillState)

local CHARGE_TIME = 1.2
local SPEED = 160
local LIFETIME = 8
local HIT_RADIUS = 4 -- contact radius of the travelling ball
local BLAST_RADIUS = 18 -- AoE radius of the detonation
local KNOCKBACK = 160
local RELEASE_DELAY = 1.2 -- how long the caster stays locked after firing

return function(context: SkillState.Context): ()
	local character = context.character
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local arm = (character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")) :: BasePart?

	local direction = Shared.aimDirection(character, context.aim)
	local origin = root.Position
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude > 0.05 then
		character:PivotTo(CFrame.lookAt(origin, origin + flat))
	end

	Shared.playAnim(character, "BigBangAttack")
	character:SetAttribute("Casting", true)
	character:SetAttribute("Stunned", true)

	local spawnPos = (arm or root).Position + direction * 2 + Vector3.new(0, 1, 0)
	local ball = Shared.makeProjectile(character, "Big Bang Attack", spawnPos, Vector3.new(3, 3, 3))

	task.wait(CHARGE_TIME)

	Shared.launchProjectile(character, ball, direction, {
		speed = SPEED,
		lifetime = LIFETIME,
		radius = HIT_RADIUS,
		strength = context.def.strength,
		knockback = KNOCKBACK,
		explodeOnly = true,
		onExpire = function(part: BasePart)
			local at = part.Position
			Shared.spawnExplosion("Big Bang Explosion", at, Vector3.new(40, 40, 40), 0.5)
			Shared.aoeDamage(character, at, BLAST_RADIUS, context.def.strength, KNOCKBACK)
		end,
	})

	task.wait(RELEASE_DELAY)

	character:SetAttribute("Casting", false)
	character:SetAttribute("Stunned", false)
	Shared.stopAnim(character, "BigBangAttack")
end
