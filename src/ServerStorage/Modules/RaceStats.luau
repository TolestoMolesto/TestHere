--!strict
-- ─────────────────────────────────────────────
-- RaceStats.luau
-- Base starting stats for every playable race.
-- These values are written to a slot the moment a race is assigned.
-- Adjust the numbers here to balance the game; the stat names must
-- match the fields in TemplateData.SlotData exactly.
--
-- Usage:
--   local RaceStats = require(ServerStorage.Modules.RaceStats)
--   RaceStats.applyToSlot(slot, "Saiyan")
-- ─────────────────────────────────────────────

-- Per-stat entry inside a StatBlock.
-- Base is required. Flat / Add / Multi are optional and default to 0.
export type StatEntry = {
	Base:  number,
	Flat:  number?,
	Add:   number?,
	Multi: number?,
}

-- Modifier-only bonus shape: no Base. Used for All, Health, Ki, Stamina.
-- Multi is a direct multiplier (1 = no change).
export type AllBonus = {
	Flat:  number,
	Add:   number,
	Multi: number,
}

export type StatBlock = {
	Strength:           StatEntry,
	Endurance:          StatEntry,
	Speed:              StatEntry,
	BattleExperience:   StatEntry,
	KiControl:          StatEntry,
	PhysicalResistance: StatEntry,
	KiResistance:       StatEntry,
	Damage:             StatEntry,
	AllDamageReduction: StatEntry,
	Dodge:              StatEntry,
	-- ModStat entries (Flat / Add / Multi only; no Base).
	All:                AllBonus,
	Health:             AllBonus,
	Ki:                 AllBonus,
	Stamina:            AllBonus,
}

-- Tweak these values to set each race's starting baseline.
-- Most entries only need { Base = X }; add Flat/Add/Multi when a race
-- deserves a built-in bonus on top of its base.
local Stats: { [string]: StatBlock } = {
	Human = {
		Strength           = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Endurance          = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Speed              = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		BattleExperience   = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiControl          = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		PhysicalResistance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiResistance       = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Damage             = { Base = 1, Flat = 0, Add = 0, Multi = 1 },
		AllDamageReduction = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Dodge              = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		All                = { Flat = 0, Add = 0, Multi = 1 },
		Health             = { Flat = 0, Add = 0, Multi = 1 },
		Ki                 = { Flat = 0, Add = 0, Multi = 1 },
		Stamina            = { Flat = 0, Add = 0, Multi = 1 },
	},
	Namekian = {
		Strength           = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Endurance          = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Speed              = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		BattleExperience   = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiControl          = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		PhysicalResistance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiResistance       = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Damage             = { Base = 1, Flat = 0, Add = 0, Multi = 1 },
		AllDamageReduction = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Dodge              = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		All                = { Flat = 0, Add = 0, Multi = 1 },
		Health             = { Flat = 0, Add = 0, Multi = 1 },
		Ki                 = { Flat = 0, Add = 0, Multi = 1 },
		Stamina            = { Flat = 0, Add = 0, Multi = 1 },
	},
	Acrosian = {
		Strength           = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Endurance          = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Speed              = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		BattleExperience   = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiControl          = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		PhysicalResistance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiResistance       = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Damage             = { Base = 1, Flat = 0, Add = 0, Multi = 1 },
		AllDamageReduction = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Dodge              = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		All                = { Flat = 0, Add = 0, Multi = 1 },
		Health             = { Flat = 0, Add = 0, Multi = 1 },
		Ki                 = { Flat = 0, Add = 0, Multi = 1 },
		Stamina            = { Flat = 0, Add = 0, Multi = 1 },
	},
	Majin = {
		Strength           = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Endurance          = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Speed              = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		BattleExperience   = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiControl          = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		PhysicalResistance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiResistance       = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Damage             = { Base = 1, Flat = 0, Add = 0, Multi = 1 },
		AllDamageReduction = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Dodge              = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		All                = { Flat = 0, Add = 0, Multi = 1 },
		Health             = { Flat = 0, Add = 0, Multi = 1 },
		Ki                 = { Flat = 0, Add = 0, Multi = 1 },
		Stamina            = { Flat = 0, Add = 0, Multi = 1 },
	},
	Saiyan = {
		Strength           = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Endurance          = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Speed              = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		BattleExperience   = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiControl          = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		PhysicalResistance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiResistance       = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Damage             = { Base = 1, Flat = 0, Add = 0, Multi = 1 },
		AllDamageReduction = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Dodge              = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		All                = { Flat = 0, Add = 0, Multi = 1 },
		Health             = { Flat = 0, Add = 0, Multi = 1 },
		Ki                 = { Flat = 0, Add = 0, Multi = 1 },
		Stamina            = { Flat = 0, Add = 0, Multi = 1 },
	},
	Sphinx = {
		Strength           = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Endurance          = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Speed              = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		BattleExperience   = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiControl          = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		PhysicalResistance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiResistance       = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Damage             = { Base = 1, Flat = 0, Add = 0, Multi = 1 },
		AllDamageReduction = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Dodge              = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		All                = { Flat = 0, Add = 0, Multi = 1 },
		Health             = { Flat = 0, Add = 0, Multi = 1 },
		Ki                 = { Flat = 0, Add = 0, Multi = 1 },
		Stamina            = { Flat = 0, Add = 0, Multi = 1 },
	},
	-- Not rollable; only awarded via the LegendarySuperSaiyan spawn check.
	LegendarySuperSaiyan = {
		Strength           = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Endurance          = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Speed              = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		BattleExperience   = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiControl          = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		PhysicalResistance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiResistance       = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Damage             = { Base = 1, Flat = 0, Add = 0, Multi = 1 },
		AllDamageReduction = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Dodge              = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		All                = { Flat = 0, Add = 0, Multi = 1 },
		Health             = { Flat = 0, Add = 0, Multi = 1 },
		Ki                 = { Flat = 0, Add = 0, Multi = 1 },
		Stamina            = { Flat = 0, Add = 0, Multi = 1 },
	},
	-- Global races (ANGEL / GOD / KAI) are not listed here. When a player
	-- rolls a global they still pick a basic race via pickRace, and that
	-- basic race's stats apply. applyToSlot will simply no-op if called
	-- with a global placeholder name.
}

-- Writes all four layers of a StatData field.
-- Multi is a direct multiplier; default 1 (no change, not 0).
local function applyEntry(statData: any, entry: StatEntry)
	statData.Base  = entry.Base
	statData.Flat  = entry.Flat  or 0
	statData.Add   = entry.Add   or 0
	statData.Multi = entry.Multi or 1
end

-- Writes a ModStat field (Flat / Add / Multi only; no Base).
local function applyMod(modData: any, entry: AllBonus)
	modData.Flat  = entry.Flat  or 0
	modData.Add   = entry.Add   or 0
	modData.Multi = entry.Multi or 1
end

-- Writes the race's stat values onto `slot`.
-- slot.All is set from the race block and read by StatsManager at compute time.
-- If the race has no entry the slot is left unchanged.
local function applyToSlot(slot: any, race: string)
	local block = Stats[race]
	if not block then
		return
	end
	applyEntry(slot.Strength,           block.Strength)
	applyEntry(slot.Endurance,          block.Endurance)
	applyEntry(slot.Speed,              block.Speed)
	applyEntry(slot.BattleExperience,   block.BattleExperience)
	applyEntry(slot.KiControl,          block.KiControl)
	applyEntry(slot.PhysicalResistance, block.PhysicalResistance)
	applyEntry(slot.KiResistance,       block.KiResistance)
	applyEntry(slot.Damage,             block.Damage)
	applyEntry(slot.AllDamageReduction, block.AllDamageReduction)
	applyEntry(slot.Dodge,              block.Dodge)
	applyMod(slot.All,     block.All)
	applyMod(slot.Health,  block.Health)
	applyMod(slot.Ki,      block.Ki)
	applyMod(slot.Stamina, block.Stamina)
end

return {
	Stats       = Stats,
	applyToSlot = applyToSlot,
}
