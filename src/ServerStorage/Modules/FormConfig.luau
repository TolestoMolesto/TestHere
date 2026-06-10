--!strict
-- Data-driven ability definitions: transformations (kind = "Form") and techniques
-- (kind = "Technique"). Both work identically; they differ only in bucket — a Form and a
-- Technique can be active at once and stack (e.g. SSJ + Kaioken). Lives in ServerStorage on
-- purpose: the balance numbers and even the roster must NOT replicate to clients. The client
-- only sends a bucket kind + numeric slot index; the server resolves it via getAbilities.
-- Mastery scales duration + drain (see Mastery.luau); the stat deltas here are flat per
-- ability. All numbers are PLACEHOLDERS to be tuned for feel later.
--
-- `description` is the curated, player-facing tooltip content (shared shape with SkillConfig +
-- ItemConfig; rendered via ReplicatedStorage.Modules.Describe). Only note + summary are authored
-- here -- FormState.getBar DERIVES the Battle Power / Ki / Stamina / Health boost lines from the
-- real stats/packs and appends Duration/Cooldown, so the shown numbers can never drift. Optional
-- `effects` adds extra flavor lines (e.g. Kaioken's drain).

export type StatDelta = {
	Add: number?,
	Multi: number?,
}

export type FormDef = {
	displayName: string,
	kind: "Form" | "Technique", -- which bucket; Forms and Techniques stack (one of each at once)
	race: string, -- race that may use it; "Any" = race-agnostic (typical for techniques)
	unlockFlag: string?, -- nil = always available; else checked vs Shared.Unlocks
	order: number, -- position in the bucket's line for this race; the client's slot index selects by this
	stats: { [string]: StatDelta }, -- Multi deltas stack multiplicatively across abilities; Add stacks additively
	kiPack: number?, -- → Ki.Add (extra MaxKi as a fraction of base)
	staminaPack: number?, -- → Stamina.Add
	healthPack: number?, -- → Health.Add
	cooldown: number, -- seconds; starts when the ability ends
	auraTemplate: string, -- name of a template under ServerStorage.Assets.VFX
	-- Mastery curve inputs (per-ability). Duration grows to infinite at max level; each drain
	-- below ramps from its level-1 value to 0 at max level. Omitted drains default to 0.
	baseDuration: number,
	durationStep: number,
	baseKiDrain: number?,
	baseHealthDrain: number?,
	baseStaminaDrain: number?,
	description: { -- curated tooltip content (Describe); stat lines are derived in FormState.getBar
		note: string?,
		summary: string,
		effects: { string }?,
	},
}

local Config = {
	MaxMasteryLevel = 10,
	XpPerSecond = 1, -- passive mastery XP per second while active
	XpPerHit = 5, -- bonus mastery XP per landed hit while active
	XpBasePerLevel = 100, -- XP needed for level L -> L+1 is XpBasePerLevel * L
}

-- Standard note shared by every Form (Techniques carry their own).
local FORM_NOTE = "Cannot be stacked with other Forms. Compatible with Techniques."

-- Buffs all five BattlePower-contributing stats by the same Multi, so BP scales ~(1 + amount).
local function coreMulti(amount: number): { [string]: StatDelta }
	return {
		Strength = { Multi = amount },
		Endurance = { Multi = amount },
		Speed = { Multi = amount },
		BattleExperience = { Multi = amount },
		KiControl = { Multi = amount },
	}
end

local forms: { [string]: FormDef } = {
	-- ░░ Human (Form) ░░
	PotentialUnlock = {
		displayName = "Potential Unlock",
		kind = "Form",
		race = "Human",
		unlockFlag = nil,
		order = 1,
		stats = coreMulti(0.75),
		kiPack = 0.3,
		staminaPack = 0.15,
		healthPack = 0.25,
		cooldown = 40,
		auraTemplate = "PotentialUnlockAura",
		baseDuration = 35,
		durationStep = 9,
		baseKiDrain = 4,
		description = {
			note = FORM_NOTE,
			summary = "An Elder's ritual draws out the hidden depths of your potential, unleashing power "
				.. "you never knew you had.",
		},
	},

	-- ░░ Saiyan (Form) ░░
	SSJ = {
		displayName = "Super Saiyan",
		kind = "Form",
		race = "Saiyan",
		unlockFlag = nil,
		order = 1,
		stats = coreMulti(0.5),
		kiPack = 0.25,
		staminaPack = 0.1,
		healthPack = 0.2,
		cooldown = 30,
		auraTemplate = "SSJAura",
		baseDuration = 30,
		durationStep = 8,
		baseKiDrain = 5,
		description = {
			note = FORM_NOTE,
			summary = "The legendary transformation of Saiyan lore -- golden hair, a blazing aura, and a "
				.. "surge of raw power born of righteous fury.",
		},
	},
	SSJ2 = {
		displayName = "Super Saiyan 2",
		kind = "Form",
		race = "Saiyan",
		unlockFlag = nil,
		order = 2,
		stats = coreMulti(1.0),
		kiPack = 0.4,
		staminaPack = 0.15,
		healthPack = 0.3,
		cooldown = 45,
		auraTemplate = "SSJ2Aura",
		baseDuration = 25,
		durationStep = 9,
		baseKiDrain = 8,
		description = {
			note = FORM_NOTE,
			summary = "A sharper, fiercer evolution of the Super Saiyan state, crackling with bioelectric "
				.. "energy and far greater might.",
		},
	},
	SSJ3 = {
		displayName = "Super Saiyan 3",
		kind = "Form",
		race = "Saiyan",
		unlockFlag = nil,
		order = 3,
		stats = coreMulti(2.0),
		kiPack = 0.6,
		staminaPack = 0.2,
		healthPack = 0.4,
		cooldown = 60,
		auraTemplate = "SSJ3Aura",
		baseDuration = 20,
		durationStep = 10,
		baseKiDrain = 12,
		description = {
			note = FORM_NOTE,
			summary = "The pinnacle of the Super Saiyan line -- flowing hair and immense power, drawn at a "
				.. "punishing cost to your reserves.",
		},
	},

	-- ░░ Legendary Super Saiyan (Form, LegendarySuperSaiyan race) ░░
	LSSJ = {
		displayName = "Legendary Super Saiyan",
		kind = "Form",
		race = "LegendarySuperSaiyan",
		unlockFlag = nil,
		order = 1,
		stats = coreMulti(1.5),
		kiPack = 0.5,
		staminaPack = 0.2,
		healthPack = 0.35,
		cooldown = 50,
		auraTemplate = "LSSJAura",
		baseDuration = 25,
		durationStep = 9,
		baseKiDrain = 9,
		description = {
			note = FORM_NOTE,
			summary = "The fabled Legendary Super Saiyan -- a monstrous, unstoppable form that dwarfs the "
				.. "ordinary Super Saiyan.",
		},
	},
	LSSJ2 = {
		displayName = "Legendary Super Saiyan 2",
		kind = "Form",
		race = "LegendarySuperSaiyan",
		unlockFlag = nil,
		order = 2,
		stats = coreMulti(2.5),
		kiPack = 0.7,
		staminaPack = 0.25,
		healthPack = 0.45,
		cooldown = 65,
		auraTemplate = "LSSJ2Aura",
		baseDuration = 20,
		durationStep = 10,
		baseKiDrain = 14,
		description = {
			note = FORM_NOTE,
			summary = "The Legendary power pushed beyond all reason -- a towering avatar of destruction "
				.. "that buries everything before it.",
		},
	},

	-- ░░ Namekian (Form) ░░
	SuperNamekian = {
		displayName = "Super Namekian",
		kind = "Form",
		race = "Namekian",
		unlockFlag = nil,
		order = 1,
		stats = coreMulti(0.8),
		kiPack = 0.35,
		staminaPack = 0.2,
		healthPack = 0.3,
		cooldown = 40,
		auraTemplate = "SuperNamekianAura",
		baseDuration = 35,
		durationStep = 9,
		baseKiDrain = 5,
		description = {
			note = FORM_NOTE,
			summary = "Drawing on your warrior heritage, your body swells with Namekian might and a deep, "
				.. "stubborn resilience.",
		},
	},

	-- ░░ Acrosian (Form) ░░
	SecondForm = {
		displayName = "Second Form",
		kind = "Form",
		race = "Acrosian",
		unlockFlag = nil,
		order = 1,
		stats = coreMulti(0.6),
		kiPack = 0.25,
		staminaPack = 0.1,
		healthPack = 0.2,
		cooldown = 30,
		auraTemplate = "SecondFormAura",
		baseDuration = 30,
		durationStep = 8,
		baseKiDrain = 5,
		description = {
			note = FORM_NOTE,
			summary = "Shedding your first shell, you grow larger and far more powerful -- a brutal step "
				.. "up in raw strength.",
		},
	},
	ThirdForm = {
		displayName = "Third Form",
		kind = "Form",
		race = "Acrosian",
		unlockFlag = nil,
		order = 2,
		stats = coreMulti(1.2),
		kiPack = 0.4,
		staminaPack = 0.15,
		healthPack = 0.3,
		cooldown = 45,
		auraTemplate = "ThirdFormAura",
		baseDuration = 25,
		durationStep = 9,
		baseKiDrain = 8,
		description = {
			note = FORM_NOTE,
			summary = "Transform into Third Form, a more powerful and intimidating form. This elongated, "
				.. "armoured shape grants greater Battle Power and enhanced combat capabilities.",
		},
	},
	FinalForm = {
		displayName = "Final Form",
		kind = "Form",
		race = "Acrosian",
		unlockFlag = nil,
		order = 3,
		stats = coreMulti(2.2),
		kiPack = 0.6,
		staminaPack = 0.2,
		healthPack = 0.4,
		cooldown = 60,
		auraTemplate = "FinalFormAura",
		baseDuration = 20,
		durationStep = 10,
		baseKiDrain = 12,
		description = {
			note = FORM_NOTE,
			summary = "Your true and ultimate form -- sleek, perfected, and overflowing with terrifying "
				.. "power held under complete control.",
		},
	},

	-- ░░ Majin (Form) ░░
	PureEvil = {
		displayName = "Pure Evil",
		kind = "Form",
		race = "Majin",
		unlockFlag = nil,
		order = 1,
		stats = coreMulti(1.0),
		kiPack = 0.4,
		staminaPack = 0.2,
		healthPack = 0.35,
		cooldown = 45,
		auraTemplate = "PureEvilAura",
		baseDuration = 30,
		durationStep = 9,
		baseKiDrain = 8,
		description = {
			note = FORM_NOTE,
			summary = "Giving in fully to your dark nature, malevolent energy floods your body and "
				.. "amplifies every ounce of your power.",
		},
	},

	-- ░░ Techniques (race-agnostic, stack on top of a Form) ░░
	Kaioken = {
		displayName = "Kaioken",
		kind = "Technique",
		race = "Any",
		unlockFlag = nil,
		order = 1,
		stats = coreMulti(0.5),
		cooldown = 35,
		auraTemplate = "KaiokenAura",
		baseDuration = 25,
		durationStep = 9,
		-- Body strain: drains health + stamina (not Ki) while active.
		baseHealthDrain = 3,
		baseStaminaDrain = 4,
		description = {
			note = "Stacks on top of a Form.",
			summary = "A risky technique that multiplies your power for a short burst -- but the strain "
				.. "steadily drains your body the whole time it's active.",
			effects = {
				"Drains Health & Stamina while active",
			},
		},
	},
}

local FormConfig = {
	Config = Config,
	forms = forms,
}

function FormConfig.get(abilityName: string): FormDef?
	return forms[abilityName]
end

-- Abilities of a given kind ("Form"/"Technique") usable by a race (race match or "Any"),
-- sorted by line order (slot index 1 = lowest order).
function FormConfig.getAbilities(race: string, kind: string): { { id: string, def: FormDef } }
	local list: { { id: string, def: FormDef } } = {}
	for id, def in forms do
		if def.kind == kind and (def.race == race or def.race == "Any") then
			table.insert(list, { id = id, def = def })
		end
	end
	table.sort(list, function(a, b)
		return a.def.order < b.def.order
	end)
	return list
end

-- All abilities usable by a race for the shared 6-0 hotkey row: Forms first (by order), then
-- Techniques (by order). Slot index 1 = key 6. Each ability's kind still routes it to its own
-- bucket, so a form + a technique chosen from this one row stack.
function FormConfig.getRaceAbilities(race: string): { { id: string, def: FormDef } }
	local combined = FormConfig.getAbilities(race, "Form")
	for _, entry in FormConfig.getAbilities(race, "Technique") do
		table.insert(combined, entry)
	end
	return combined
end

return FormConfig
