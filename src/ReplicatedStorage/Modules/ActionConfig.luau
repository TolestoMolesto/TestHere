--!strict

export type Trigger = "Press" | "Release" | "Hold"

export type ActionDef = {
	binding: (Enum.KeyCode | Enum.UserInputType)?,
	trigger: Trigger,
	-- When true, CombatClient skips this action; a dedicated controller fires it via PerformAction.
	clientManaged: boolean?,
	-- Character attributes that, while truthy, prevent this action from STARTING. Enforced centrally
	-- in ActionController.perform -- the single chokepoint every player + AI action routes through --
	-- so THIS table, not a hand-rolled `if GetAttribute(...)` block inside the handler, is the source
	-- of truth for "what stops this action". The check is skipped on a "stop" phase (releasing a Hold)
	-- so a player CC'd mid-hold can never get stuck holding it. Handlers keep their own non-attribute
	-- gates (cooldowns, stamina cost, lock-on, re-entrancy).
	blockedBy: { string }?,
	-- When true, successfully starting this action ends the actor's spawn-protection Forcefield
	-- ("you've done something"). Set on the actions that deal damage on use; see StateBinders.
	dropsProtection: boolean?,
}

-- Hard crowd-control: states in which you can't initiate ANY combat action. Folded into each
-- fully-migrated action's blockedBy below so the shared set lives in exactly one place.
local HARD_CC = { "Stunned", "HitByKnockBack", "ToggleRagdoll", "InCustomization" }

-- HARD_CC plus the action-specific blockers, as a fresh list.
local function blockers(extra: { string }): { string }
	local out = table.clone(HARD_CC)
	for _, name in extra do
		table.insert(out, name)
	end
	return out
end

local ActionConfig: { [string]: ActionDef } = {
	SpawnShadow = { binding = Enum.KeyCode.K, trigger = "Press" },
	-- Charging is intentionally absent from LightAttack.blockedBy: a light attack CANCELS a charge
	-- (the handler calls Charge.stop) rather than being blocked by it.
	LightAttack = {
		binding = Enum.UserInputType.MouseButton1,
		trigger = "Press",
		blockedBy = blockers({
			"AttackCooldown",
			"Blocking",
			"HeavyCooldown",
			"InSafeZone",
			"KiBlasting",
			"NoAttacking",
			"Resting",
		}),
		dropsProtection = true,
	},
	-- HeavyAttack is lock-on only; M2 otherwise stays free for camera look (gated server-side). It
	-- keys off HeavyCooldown, not AttackCooldown, so a light combo can cancel into a heavy.
	HeavyAttack = {
		binding = Enum.UserInputType.MouseButton2,
		trigger = "Press",
		blockedBy = blockers({
			"Blocking",
			"HeavyCooldown",
			"InSafeZone",
			"KiBlasting",
			"NoAttacking",
			"Resting",
		}),
		dropsProtection = true,
	},
	Recover = { binding = Enum.KeyCode.R, trigger = "Press" },
	-- Block & Charge keep their handler guards (CanBlock/stamina/re-entrancy, canCharge); the central
	-- gate only adds the cross-cutting Resting block they were both missing.
	Block = { binding = Enum.KeyCode.F, trigger = "Hold", blockedBy = { "Resting" } },
	Charge = { binding = Enum.KeyCode.C, trigger = "Hold", blockedBy = { "Resting" } },
	Rest = { binding = Enum.KeyCode.N, trigger = "Press" },
	KiBlast = {
		binding = Enum.KeyCode.Q,
		trigger = "Press",
		blockedBy = blockers({
			"Attacking",
			"Blocking",
			"Charging",
			"InSafeZone",
			"KiBlasting",
			"Resting",
		}),
		dropsProtection = true,
	},
	-- Vanish keeps its handler's debounce + stamina gate; Resting is the only central addition.
	-- HitByKnockBack is deliberately NOT a blocker -- you can vanish while being knocked back.
	Vanish = { binding = Enum.KeyCode.V, trigger = "Press", blockedBy = { "Resting" } },
	Flight = { trigger = "Press", clientManaged = true },
	-- All forms route through one action; the form name rides in params (set by FormController).
	Transform = { trigger = "Press", clientManaged = true },
	-- All offensive skills route through one action; the loadout slot (1-5) + aim CFrame ride in
	-- params (set by SkillController). The server resolves the slot to the equipped skill id.
	-- SkillState.canCast already gates Resting/CC server-side, so no blockedBy here -- but landing a
	-- cast still counts as "doing something", so it drops spawn protection.
	Skill = { trigger = "Press", clientManaged = true, dropsProtection = true },
}

return ActionConfig
