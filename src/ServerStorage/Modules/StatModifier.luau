--!strict
-- ─────────────────────────────────────────────
-- StatModifier.luau
-- Applies and removes Flat / Add / Multi bonuses on SlotData stats.
--
-- This module only mutates slot data. After calling any modifier,
-- call StatsManager.refresh(player) to push the new finals to the
-- character's attribute folders.
--
-- Layer rules:
--   Base  — never touched here; set exclusively by RaceStats
--   Flat  — raw additive bonus  (+10 Strength from a skill)
--   Add   — additive % bonus    (0.2 = +20%; stacks additively)
--   Multi — multiplicative %    (0.5 = +50%; stacks multiplicatively)
--
-- Final = (Base + Flat) * (1 + Add) * (1 + Multi)
--
-- Usage:
--   local StatModifier = require(ServerStorage.Modules.StatModifier)
--   StatModifier.addFlat(slot, "Strength", 10)
--   StatModifier.addMulti(slot, "KiControl", 0.25)
--   StatsManager.refresh(player)
-- ─────────────────────────────────────────────

export type StatName =
	"Strength"
	| "Endurance"
	| "Speed"
	| "BattleExperience"
	| "KiControl"
	| "PhysicalResistance"
	| "KiResistance"
	| "Damage"	| "PhysicalDamage"
	| "KiDamage"	-- Percent-only stats (Add / Multi only; no Base or Flat):
	| "AllDamageReduction"
	| "Dodge"
	-- ModStat targets (Flat / Add / Multi only; no Base):
	| "All"
	| "Health"
	| "Ki"
	| "Stamina"

export type Layer = "Flat" | "Add" | "Multi"

local VALID_STATS: { [string]: true } = {
	Strength           = true,
	Endurance          = true,
	Speed              = true,
	BattleExperience   = true,
	KiControl          = true,
	PhysicalResistance = true,
	KiResistance       = true,
	Damage             = true,
	PhysicalDamage     = true,
	KiDamage           = true,
	-- Percent-only; use addAdd / addMulti / removeAdd / removeMulti only.
	AllDamageReduction = true,
	Dodge              = true,
	-- ModStat; no Base. Use addFlat / addAdd / addMulti.
	All                = true,
	Health             = true,
	Ki                 = true,
	Stamina            = true,
}

local StatModifier = {}

local function getStat(slot: any, statName: string): any
	assert(VALID_STATS[statName], "StatModifier: unknown stat '" .. statName .. "'")
	local stat = slot[statName]
	assert(stat, "StatModifier: stat '" .. statName .. "' missing from slot")
	return stat
end

-- ── Generic ──────────────────────────────────────────────────────────

-- Add `amount` to a specific layer. Pass a negative amount to remove.
function StatModifier.add(slot: any, statName: string, layer: Layer, amount: number)
	getStat(slot, statName)[layer] += amount
end

-- Set a layer to an exact value (admin / debug / reset).
-- Never pass "Base" here — use RaceStats for that.
function StatModifier.set(slot: any, statName: string, layer: Layer, value: number)
	getStat(slot, statName)[layer] = value
end

-- ── Flat ─────────────────────────────────────────────────────────────

function StatModifier.addFlat(slot: any, statName: string, amount: number)
	getStat(slot, statName).Flat += amount
end

function StatModifier.removeFlat(slot: any, statName: string, amount: number)
	getStat(slot, statName).Flat -= amount
end

-- ── Add (additive %) ─────────────────────────────────────────────────

function StatModifier.addAdd(slot: any, statName: string, amount: number)
	getStat(slot, statName).Add += amount
end

function StatModifier.removeAdd(slot: any, statName: string, amount: number)
	getStat(slot, statName).Add -= amount
end

-- ── Multi (multiplicative %) ─────────────────────────────────────────

function StatModifier.addMulti(slot: any, statName: string, amount: number)
	getStat(slot, statName).Multi += amount
end

function StatModifier.removeMulti(slot: any, statName: string, amount: number)
	getStat(slot, statName).Multi -= amount
end

-- ── Bulk helpers ─────────────────────────────────────────────────────

-- Reset Flat / Add / Multi for one stat back to 0. Base is untouched.
function StatModifier.resetBonuses(slot: any, statName: string)
	local stat = getStat(slot, statName)
	stat.Flat  = 0
	stat.Add   = 0
	stat.Multi = 0
end

-- Reset bonus layers on every stat. Base values are preserved.
function StatModifier.resetAllBonuses(slot: any)
	for statName in VALID_STATS do
		StatModifier.resetBonuses(slot, statName)
	end
end

-- Apply a table of Flat bonuses to multiple stats at once.
-- Example: StatModifier.applyFlatBlock(slot, { Strength = 5, Speed = 3 })
function StatModifier.applyFlatBlock(slot: any, block: { [string]: number })
	for statName, amount in block do
		StatModifier.addFlat(slot, statName, amount)
	end
end

-- Remove a table of Flat bonuses (mirror of applyFlatBlock).
function StatModifier.removeFlatBlock(slot: any, block: { [string]: number })
	for statName, amount in block do
		StatModifier.removeFlat(slot, statName, amount)
	end
end

return StatModifier
