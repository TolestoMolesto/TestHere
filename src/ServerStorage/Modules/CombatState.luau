--!strict
local CombatState = {}

CombatState.DEFAULTS = {
	AttackCooldown = false,
	Attacking = false,
	Blocking = false,
	BlockBroken = false,
	CanBlock = true,
	HeavyCooldown = false,
	NoAttacking = false,
	NoBlocking = false,
	PerfectBlocked = false,
	Swinging = false,
	AttackSequence = 0, -- 0 = no combo in progress

	HitByKnockBack = false,
	CanRecover = false,
	CanVanishTo = false,
	Stunned = false,
	ToggleRagdoll = false,

	Flying = false,
	BoostFlying = false,
	Running = false,

	KiBlasting = false,
	Charging = false,
	Resting = false,
	IsShadow = false,

	-- "" when inactive; else the active ability name (drives FormOverlay + FormFX). Two
	-- independent buckets so a Form and a Technique can be active at once (e.g. SSJ + Kaioken).
	ActiveForm = "",
	ActiveTechnique = "",

	-- Bool flag only; the target Instance rides a LockOnTarget ObjectValue child (set by TargetLock).
	LockedOn = false,

	InCustomization = false,
	InSafeZone = false,

	-- Spawn/respawn protection. While true the character is fully intangible -- no incoming damage,
	-- knockback, lock-on, vanish, or scan-based hit (enforced in Damage/Knockback/Hitbox/TargetLock).
	-- Granted on spawn by StateBinders; dropped on a timeout or the first offensive action (perform).
	Forcefield = false,

	LastAttackTime = 0,
	LastHeavyTime = 0,
	StaminaNeeded = 0,
	HeavyStaminaNeeded = 0,

	CombatTag = false,
	CombatTimerRunning = false,
	CombatTime = 0,
}

function CombatState.init(character: Model): ()
	for name, value in CombatState.DEFAULTS :: { [string]: any } do
		character:SetAttribute(name, value)
	end
end

return CombatState
