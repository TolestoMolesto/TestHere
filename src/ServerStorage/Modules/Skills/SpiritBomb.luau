--!strict
-- Spirit Bomb: a long, dramatic overhead charge that roots the caster, then lobs a huge, slow orb
-- toward the aim. On impact it detonates into a wide radial burst. Ported onto the explodeOnly
-- projectile + Shared.aoeDamage.

local ServerStorage = game:GetService("ServerStorage")

local Shared = require(ServerStorage.Modules.Skills.Shared)
local SkillState = require(ServerStorage.Modules.SkillState)

local CHARGE_TIME = 3.0 -- shortened from the legacy 5s for feel; tune later
local SPEED = 60
local LIFETIME = 14
local HIT_RADIUS = 8
local BLAST_RADIUS = 30
local KNOCKBACK = 180
local RELEASE_DELAY = 1.5

return function(context: SkillState.Context): ()
	local character = context.character
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local direction = Shared.aimDirection(character, context.aim)

	Shared.playAnim(character, "SpiritBomb")
	character:SetAttribute("Casting", true)
	character:SetAttribute("Stunned", true)
	root.Anchored = true -- rooted through the long charge

	-- Charge the orb high overhead so it clears the caster at full size.
	local spawnPos = root.Position + Vector3.new(0, 14, 0)
	local orb = Shared.makeProjectile(character, "Spirit Bomb", spawnPos, Vector3.new(12, 12, 12))

	task.wait(CHARGE_TIME)

	root.Anchored = false

	Shared.launchProjectile(character, orb, direction, {
		speed = SPEED,
		lifetime = LIFETIME,
		radius = HIT_RADIUS,
		strength = context.def.strength,
		knockback = KNOCKBACK,
		explodeOnly = true,
		onExpire = function(part: BasePart)
			local at = part.Position
			Shared.spawnExplosion("Spirit Bomb Explosion", at, Vector3.new(60, 60, 60), 0.6)
			Shared.aoeDamage(character, at, BLAST_RADIUS, context.def.strength, KNOCKBACK)
		end,
	})

	task.wait(RELEASE_DELAY)

	character:SetAttribute("Casting", false)
	character:SetAttribute("Stunned", false)
	Shared.stopAnim(character, "SpiritBomb")
end
