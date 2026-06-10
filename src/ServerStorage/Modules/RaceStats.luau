--!strict

export type StatEntry = {
	Base: number,
	Flat: number?,
	Add: number?,
	Multi: number?,
}

export type AllBonus = {
	Flat: number,
	Add: number,
	Multi: number,
}

export type StatBlock = {
	Strength: StatEntry,
	Endurance: StatEntry,
	Speed: StatEntry,
	BattleExperience: StatEntry,
	KiControl: StatEntry,
	PhysicalResistance: StatEntry,
	KiResistance: StatEntry,
	Damage: StatEntry,
	AllDamageReduction: StatEntry,
	Dodge: StatEntry,
	All: AllBonus,
	Health: AllBonus,
	Ki: AllBonus,
	Stamina: AllBonus,
}

local Stats: { [string]: StatBlock } = {
	Human = {
		Strength = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Endurance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Speed = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		BattleExperience = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiControl = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		PhysicalResistance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiResistance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Damage = { Base = 1, Flat = 0, Add = 0, Multi = 1 },
		AllDamageReduction = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Dodge = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		All = { Flat = 0, Add = 0, Multi = 1 },
		Health = { Flat = 0, Add = 0, Multi = 1 },
		Ki = { Flat = 0, Add = 0, Multi = 1 },
		Stamina = { Flat = 0, Add = 0, Multi = 1 },
	},
	Namekian = {
		Strength = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Endurance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Speed = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		BattleExperience = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiControl = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		PhysicalResistance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiResistance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Damage = { Base = 1, Flat = 0, Add = 0, Multi = 1 },
		AllDamageReduction = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Dodge = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		All = { Flat = 0, Add = 0, Multi = 1 },
		Health = { Flat = 0, Add = 0, Multi = 1 },
		Ki = { Flat = 0, Add = 0, Multi = 1 },
		Stamina = { Flat = 0, Add = 0, Multi = 1 },
	},
	Acrosian = {
		Strength = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Endurance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Speed = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		BattleExperience = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiControl = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		PhysicalResistance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiResistance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Damage = { Base = 1, Flat = 0, Add = 0, Multi = 1 },
		AllDamageReduction = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Dodge = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		All = { Flat = 0, Add = 0, Multi = 1 },
		Health = { Flat = 0, Add = 0, Multi = 1 },
		Ki = { Flat = 0, Add = 0, Multi = 1 },
		Stamina = { Flat = 0, Add = 0, Multi = 1 },
	},
	Majin = {
		Strength = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Endurance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Speed = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		BattleExperience = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiControl = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		PhysicalResistance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiResistance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Damage = { Base = 1, Flat = 0, Add = 0, Multi = 1 },
		AllDamageReduction = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Dodge = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		All = { Flat = 0, Add = 0, Multi = 1 },
		Health = { Flat = 0, Add = 0, Multi = 1 },
		Ki = { Flat = 0, Add = 0, Multi = 1 },
		Stamina = { Flat = 0, Add = 0, Multi = 1 },
	},
	Saiyan = {
		Strength = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Endurance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Speed = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		BattleExperience = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiControl = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		PhysicalResistance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiResistance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Damage = { Base = 1, Flat = 0, Add = 0, Multi = 1 },
		AllDamageReduction = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Dodge = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		All = { Flat = 0, Add = 0, Multi = 1 },
		Health = { Flat = 0, Add = 0, Multi = 1 },
		Ki = { Flat = 0, Add = 0, Multi = 1 },
		Stamina = { Flat = 0, Add = 0, Multi = 1 },
	},
	Sphinx = {
		Strength = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Endurance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Speed = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		BattleExperience = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiControl = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		PhysicalResistance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiResistance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Damage = { Base = 1, Flat = 0, Add = 0, Multi = 1 },
		AllDamageReduction = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Dodge = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		All = { Flat = 0, Add = 0, Multi = 1 },
		Health = { Flat = 0, Add = 0, Multi = 1 },
		Ki = { Flat = 0, Add = 0, Multi = 1 },
		Stamina = { Flat = 0, Add = 0, Multi = 1 },
	},
	-- Not rollable; only awarded via the LegendarySuperSaiyan spawn check.
	LegendarySuperSaiyan = {
		Strength = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Endurance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Speed = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		BattleExperience = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiControl = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		PhysicalResistance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		KiResistance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Damage = { Base = 1, Flat = 0, Add = 0, Multi = 1 },
		AllDamageReduction = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		Dodge = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
		All = { Flat = 0, Add = 0, Multi = 1 },
		Health = { Flat = 0, Add = 0, Multi = 1 },
		Ki = { Flat = 0, Add = 0, Multi = 1 },
		Stamina = { Flat = 0, Add = 0, Multi = 1 },
	},
}

-- Multi defaults to 1 (not 0) — no change.
local function applyEntry(statData: any, entry: StatEntry)
	statData.Base = entry.Base
	statData.Flat = entry.Flat or 0
	statData.Add = entry.Add or 0
	statData.Multi = entry.Multi or 1
end

local function applyMod(modData: any, entry: AllBonus)
	modData.Flat = entry.Flat or 0
	modData.Add = entry.Add or 0
	modData.Multi = entry.Multi or 1
end

local function applyToSlot(slot: any, race: string)
	local block = Stats[race]
	if not block then
		return
	end
	applyEntry(slot.Strength, block.Strength)
	applyEntry(slot.Endurance, block.Endurance)
	applyEntry(slot.Speed, block.Speed)
	applyEntry(slot.BattleExperience, block.BattleExperience)
	applyEntry(slot.KiControl, block.KiControl)
	applyEntry(slot.PhysicalResistance, block.PhysicalResistance)
	applyEntry(slot.KiResistance, block.KiResistance)
	applyEntry(slot.Damage, block.Damage)
	applyEntry(slot.AllDamageReduction, block.AllDamageReduction)
	applyEntry(slot.Dodge, block.Dodge)
	applyMod(slot.All, block.All)
	applyMod(slot.Health, block.Health)
	applyMod(slot.Ki, block.Ki)
	applyMod(slot.Stamina, block.Stamina)
end

return {
	Stats = Stats,
	applyToSlot = applyToSlot,
}
