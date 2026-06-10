--!strict
-- Data-driven roster for the offensive "Skill" bucket (hotkeys 1-5), the counterpart to
-- FormConfig's transformations/techniques (keys 6-0). Lives in ServerStorage on purpose: the
-- balance numbers must NOT replicate to clients. The client only sends a numeric loadout slot
-- (1-5) + an aim CFrame; the server resolves it to the equipped skill id via the player's slot
-- loadout, then SkillState runs the matching behavior module under ServerStorage.Modules.Skills.
--
-- Unlike Forms (fixed per-race lines), Skills are COLLECTED: a slot unlocks skills (gated by
-- BattlePower via SkillGiver) into slot.UnlockedSkills, then the player equips any 5 into
-- slot.SkillLoadout. Most skills are race-agnostic (race = "Any").
--
-- All numbers are PLACEHOLDERS to be tuned for feel later. `strength` is the per-skill damage
-- multiplier the old code called `setdamage`; SkillState/KiMove feed it into the Damage module's
-- BiStat formula. No mastery yet (flat cost/cooldown/strength) -- a Mastery pass mirrors forms later.
--
-- `description` is the curated, player-facing tooltip content (shared shape with FormConfig + Items;
-- rendered via ReplicatedStorage.Modules.Describe). The Type line is always "Skill" (the unified
-- inventory sort key); the Beam/Projectile/Physical/Utility `category` rides in the effect lines.
-- SkillServer auto-appends "Ki Cost" + "Cooldown" from the real numbers so those never drift. The
-- raw strength is described qualitatively here -- it never crosses to the client.

export type SkillCategory = "Beam" | "Projectile" | "Physical" | "Utility"

export type SkillDef = {
	displayName: string,
	category: SkillCategory,
	race: string, -- "Any" or a race id; gates who can unlock/equip it
	unlockBP: number, -- slot BattlePower required before SkillGiver unlocks it (0 = from the start)
	kiCost: number, -- flat Ki spent on cast
	cooldown: number, -- seconds; starts when the cast begins
	strength: number, -- per-skill damage multiplier (old `setdamage`)
	holdable: boolean?, -- supports the HoldingSkill charge-up loop (Kamehameha / Galick Gun)
	behavior: string, -- module name under ServerStorage.Modules.Skills
	unlockMessage: string?, -- chat line shouted when first unlocked (flavor)
	description: { -- curated tooltip content (Describe); never leaks raw balance numbers
		note: string?,
		summary: string,
		effects: { string },
	},
}

local skills: { [string]: SkillDef } = {
	EnergyWave = {
		displayName = "Energy Wave",
		category = "Beam",
		race = "Any",
		unlockBP = 1,
		kiCost = 10,
		cooldown = 2,
		strength = 6,
		behavior = "EnergyWave",
		unlockMessage = "I'LL WIPE YOU OUT WITH THIS!!",
		description = {
			summary = "A quick sweeping wave of raw ki fired from the palms -- the bread-and-butter "
				.. "blast every fighter learns first.",
			effects = {
				"Category: Beam",
				"Damage: Moderate",
				"Range: Long",
			},
		},
	},
	Kamehameha = {
		displayName = "Kamehameha",
		category = "Beam",
		race = "Any",
		unlockBP = 10,
		kiCost = 25,
		cooldown = 6,
		strength = 8,
		holdable = true,
		behavior = "Kamehameha",
		unlockMessage = "KA-ME-HA-ME-HAAA!!",
		description = {
			note = "Hold to charge for greater power.",
			summary = "The signature technique of the Turtle School: cupped hands gather a brilliant "
				.. "blue beam that erupts in a devastating torrent of energy.",
			effects = {
				"Category: Beam",
				"Damage: High",
				"Range: Long",
				"Chargeable",
			},
		},
	},
	GalickGun = {
		displayName = "Galick Gun",
		category = "Beam",
		race = "Any",
		unlockBP = 10,
		kiCost = 25,
		cooldown = 6,
		strength = 8,
		holdable = true,
		behavior = "GalickGun",
		unlockMessage = "GALICK GUN!!",
		description = {
			note = "Hold to charge for greater power.",
			summary = "A vivid violet beam channelled with both hands -- the Saiyan prince's answer to "
				.. "the Kamehameha, fuelled by sheer pride and fury.",
			effects = {
				"Category: Beam",
				"Damage: High",
				"Range: Long",
				"Chargeable",
			},
		},
	},
	SpecialBeamCannon = {
		displayName = "Special Beam Cannon",
		category = "Beam",
		race = "Any",
		unlockBP = 20,
		kiCost = 30,
		cooldown = 8,
		strength = 10,
		behavior = "SpecialBeamCannon",
		unlockMessage = "SPECIAL BEAM CANNON!!",
		description = {
			summary = "A drilling, spiralling beam concentrated to a single piercing point -- it bores "
				.. "straight through whatever it strikes.",
			effects = {
				"Category: Beam",
				"Damage: Very High",
				"Range: Long",
				"Armour-piercing",
			},
		},
	},
	BigBangAttack = {
		displayName = "Big Bang Attack",
		category = "Projectile",
		race = "Any",
		unlockBP = 25,
		kiCost = 35,
		cooldown = 8,
		strength = 12,
		behavior = "BigBangAttack",
		unlockMessage = "BIG BANG ATTACK!!",
		description = {
			summary = "A compact sphere of condensed energy hurled from an open palm, detonating into a "
				.. "thunderous blast on impact.",
			effects = {
				"Category: Projectile",
				"Damage: Very High",
				"Area blast on impact",
			},
		},
	},
	SpiritBomb = {
		displayName = "Spirit Bomb",
		category = "Projectile",
		race = "Any",
		unlockBP = 25,
		kiCost = 40,
		cooldown = 12,
		strength = 20,
		behavior = "SpiritBomb",
		unlockMessage = "SPIRIT BOMB!!",
		description = {
			note = "Slow to form, but overwhelming.",
			summary = "Energy borrowed from every living thing around you, gathered into a colossal "
				.. "orb -- the ultimate last resort.",
			effects = {
				"Category: Projectile",
				"Damage: Massive",
				"Long wind-up",
			},
		},
	},
	DestructoDisk = {
		displayName = "Destructo Disk",
		category = "Projectile",
		race = "Any",
		unlockBP = 15,
		kiCost = 20,
		cooldown = 3,
		strength = 8,
		behavior = "DestructoDisk",
		unlockMessage = "DESTRUCTO DISK!!",
		description = {
			summary = "A razor-edged ring of humming ki, thrown like a saw blade -- it shears clean "
				.. "through almost anything in its path.",
			effects = {
				"Category: Projectile",
				"Damage: High",
				"Cuts through defences",
			},
		},
	},
	SolarFlare = {
		displayName = "Solar Flare",
		category = "Utility",
		race = "Any",
		unlockBP = 5,
		kiCost = 10,
		cooldown = 15,
		strength = 0, -- pure utility (blind); deals no damage
		behavior = "SolarFlare",
		unlockMessage = "SOLAR FLARE!!",
		description = {
			note = "Deals no damage -- a setup tool.",
			summary = "A searing burst of light from the whole body that overloads the eyes of anyone "
				.. "watching, leaving them blind and reeling.",
			effects = {
				"Category: Utility",
				"Blinds nearby foes",
				"No damage",
			},
		},
	},
	GalickCannon = {
		displayName = "Galick Cannon",
		category = "Physical",
		race = "Any",
		unlockBP = 20,
		kiCost = 0, -- physical combo: costs stamina inside the behavior, not Ki
		cooldown = 10,
		strength = 5,
		behavior = "GalickCannon",
		unlockMessage = "GALICK CANNON!!",
		description = {
			summary = "A relentless close-range rush of ki-charged blows, ending in a point-blank "
				.. "discharge that sends the target flying.",
			effects = {
				"Category: Physical",
				"Damage: Moderate",
				"Cost: Stamina",
			},
		},
	},
	WolfFangFist = {
		displayName = "Wolf Fang Fist",
		category = "Physical",
		race = "Any",
		unlockBP = 15,
		kiCost = 0, -- physical combo: costs stamina inside the behavior, not Ki
		cooldown = 8,
		strength = 8,
		behavior = "WolfFangFist",
		unlockMessage = "WOLF FANG FIST!!",
		description = {
			summary = "A savage flurry of clawing strikes delivered like a pouncing wolf, finished with "
				.. "a heavy knockback blow.",
			effects = {
				"Category: Physical",
				"Damage: High",
				"Multi-hit combo",
				"Cost: Stamina",
			},
		},
	},
}

local SkillConfig = {}

-- The whole roster (id -> def). Iterate for unlock scans / UI catalogues.
function SkillConfig.all(): { [string]: SkillDef }
	return skills
end

function SkillConfig.get(skillId: string): SkillDef?
	return skills[skillId]
end

-- Roster as a stable array, sorted by unlock cost then display name (UI ordering).
function SkillConfig.list(): { { id: string, def: SkillDef } }
	local out: { { id: string, def: SkillDef } } = {}
	for id, def in skills do
		table.insert(out, { id = id, def = def })
	end
	table.sort(out, function(a, b)
		if a.def.unlockBP ~= b.def.unlockBP then
			return a.def.unlockBP < b.def.unlockBP
		end
		return a.def.displayName < b.def.displayName
	end)
	return out
end

return SkillConfig
