--!strict
-- Data-driven roster of Passives -- innate traits shown (read-only) in the inventory's Skills tab,
-- the third ability kind alongside Skills (Moves) and Forms/Techniques. Lives in ServerStorage like
-- the other rosters; only the sanitised list (display + description string) crosses to the client.
--
-- Passives are mainly RACE-driven (a `race` field, like SkillConfig/FormConfig: "Any" = universal,
-- else a race id) and presence-based -- a player "has" a passive if it matches their slot's race or
-- is "Any". This pass is DISPLAY-ONLY: we list them with descriptions but do NOT yet wire their
-- effects into gameplay (e.g. gating the Scouter behind Ki Sense). Roster + flavor are placeholders.

export type PassiveDef = {
	displayName: string,
	type: "Passive", -- the unified inventory sort key (shared concept with Skills/Forms/Items)
	race: string, -- "Any" (universal) or a race id; gates who sees it
	-- Optional name of a per-slot boolean (a SlotData field) that must be true for this passive to count
	-- as OWNED. nil = race-presence only (the original model). Lets ACQUIRED passives (e.g. Power
	-- Suppression, granted server-side) live in the same roster without showing as owned for everyone --
	-- the inventory's passives tab filters them on this flag (see ItemServer.GetPassives).
	unlockFlag: string?,
	description: {
		note: string?,
		summary: string,
		effects: { string }?,
	},
}

local passives: { [string]: PassiveDef } = {
	-- ░░ Universal (race = "Any") ░░
	KiSense = {
		displayName = "Ki Sense",
		type = "Passive",
		race = "Any",
		description = {
			summary = "An innate awareness of the life energy around you. Lets you feel out the location "
				.. "and strength of other fighters -- sensing power levels without a Scouter.",
			effects = { "Senses nearby Ki / power levels" },
		},
	},

	-- Acquired (not race-innate): only listed once the slot's PowerSuppression flag is set, which is
	-- what unlocks the bracket-key / Settings output dial (see PowerOutputServer + PowerOutputController).
	KiSuppression = {
		displayName = "Power Suppression",
		type = "Passive",
		race = "Any",
		unlockFlag = "PowerSuppression",
		description = {
			summary = "Mastery over your own energy lets you throttle how much of your power reads to the "
				.. "outside world. Dial your output from 1% to 100% to hide your true strength from scouters "
				.. "and trained senses -- or cut loose and reveal everything.",
			effects = { "Adjust shown power output with [ and ]", "Masks your true Battle Power" },
		},
	},

	-- ░░ Saiyan ░░
	Zenkai = {
		displayName = "Zenkai",
		type = "Passive",
		race = "Saiyan",
		description = {
			summary = "The Saiyan body grows stronger after surviving a brush with death, turning a "
				.. "hard-won beating into lasting power.",
			effects = { "Grows stronger after near-death" },
		},
	},

	-- ░░ Namekian ░░
	NamekianRegeneration = {
		displayName = "Regeneration",
		type = "Passive",
		race = "Namekian",
		description = {
			summary = "Namekian physiology can rebuild lost tissue -- wounds knit and limbs regrow given "
				.. "a moment's respite.",
			effects = { "Regenerates health over time" },
		},
	},

	-- ░░ Majin ░░
	MajinRegeneration = {
		displayName = "Magic Regeneration",
		type = "Passive",
		race = "Majin",
		description = {
			summary = "Majin flesh is like putty -- blown apart, it simply pulls itself back together, "
				.. "shrugging off blows that would end anyone else.",
			effects = { "Reforms from heavy damage" },
		},
	},

	-- ░░ Human ░░
	LatentPotential = {
		displayName = "Latent Potential",
		type = "Passive",
		race = "Human",
		description = {
			summary = "Humans hide vast untapped potential. With training and sheer grit, your growth "
				.. "outpaces what your frame should allow.",
			effects = { "Accelerated training growth" },
		},
	},
}

local PassiveConfig = {}

function PassiveConfig.all(): { [string]: PassiveDef }
	return passives
end

function PassiveConfig.get(id: string): PassiveDef?
	return passives[id]
end

function PassiveConfig.list(): { { id: string, def: PassiveDef } }
	local out: { { id: string, def: PassiveDef } } = {}
	for id, def in passives do
		table.insert(out, { id = id, def = def })
	end
	table.sort(out, function(a, b)
		return a.def.displayName < b.def.displayName
	end)
	return out
end

-- Passives applicable to a race: the universal ones ("Any") plus that race's own, sorted by name.
function PassiveConfig.forRace(race: string): { { id: string, def: PassiveDef } }
	local out: { { id: string, def: PassiveDef } } = {}
	for _, entry in PassiveConfig.list() do
		if entry.def.race == "Any" or entry.def.race == race then
			table.insert(out, entry)
		end
	end
	return out
end

return PassiveConfig
