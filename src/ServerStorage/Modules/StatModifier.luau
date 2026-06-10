--!strict

export type StatName =
	"Strength"
	| "Endurance"
	| "Speed"
	| "BattleExperience"
	| "KiControl"
	| "PhysicalResistance"
	| "KiResistance"
	| "Damage"
	| "PhysicalDamage"
	| "KiDamage" -- Percent-only stats (Add / Multi only; no Base or Flat):
	| "AllDamageReduction"
	| "Dodge"
	-- ModStat targets (Flat / Add / Multi only; no Base):
	| "All"
	| "Health"
	| "Ki"
	| "Stamina"

export type Layer = "Flat" | "Add" | "Multi"

local VALID_STATS: { [string]: true } = {
	Strength = true,
	Endurance = true,
	Speed = true,
	BattleExperience = true,
	KiControl = true,
	PhysicalResistance = true,
	KiResistance = true,
	Damage = true,
	PhysicalDamage = true,
	KiDamage = true,
	-- Percent-only; use addAdd / addMulti / removeAdd / removeMulti only.
	AllDamageReduction = true,
	Dodge = true,
	-- ModStat; no Base. Use addFlat / addAdd / addMulti.
	All = true,
	Health = true,
	Ki = true,
	Stamina = true,
}

local StatModifier = {}

local function getStat(slot: any, statName: string): any
	assert(VALID_STATS[statName], "StatModifier: unknown stat '" .. statName .. "'")
	local stat = slot[statName]
	assert(stat, "StatModifier: stat '" .. statName .. "' missing from slot")
	return stat
end

function StatModifier.add(slot: any, statName: string, layer: Layer, amount: number)
	getStat(slot, statName)[layer] += amount
end

function StatModifier.set(slot: any, statName: string, layer: Layer, value: number)
	getStat(slot, statName)[layer] = value
end

function StatModifier.addFlat(slot: any, statName: string, amount: number)
	getStat(slot, statName).Flat += amount
end

function StatModifier.removeFlat(slot: any, statName: string, amount: number)
	getStat(slot, statName).Flat -= amount
end

function StatModifier.addAdd(slot: any, statName: string, amount: number)
	getStat(slot, statName).Add += amount
end

function StatModifier.removeAdd(slot: any, statName: string, amount: number)
	getStat(slot, statName).Add -= amount
end

function StatModifier.addMulti(slot: any, statName: string, amount: number)
	getStat(slot, statName).Multi += amount
end

function StatModifier.removeMulti(slot: any, statName: string, amount: number)
	getStat(slot, statName).Multi -= amount
end

function StatModifier.resetBonuses(slot: any, statName: string)
	local stat = getStat(slot, statName)
	stat.Flat = 0
	stat.Add = 0
	stat.Multi = 0
end

function StatModifier.resetAllBonuses(slot: any)
	for statName in VALID_STATS do
		StatModifier.resetBonuses(slot, statName)
	end
end

function StatModifier.applyFlatBlock(slot: any, block: { [string]: number })
	for statName, amount in block do
		StatModifier.addFlat(slot, statName, amount)
	end
end

function StatModifier.removeFlatBlock(slot: any, block: { [string]: number })
	for statName, amount in block do
		StatModifier.removeFlat(slot, statName, amount)
	end
end

return StatModifier
