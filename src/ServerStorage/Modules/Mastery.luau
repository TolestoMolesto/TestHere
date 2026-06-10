--!strict
-- Per-slot transformation mastery (levels 1..Max). Mastery raises a form's active duration
-- (to infinite at max level) and lowers its Ki drain (to zero at max level). Stored on the
-- slot (slot.FormMastery) so it persists; this is intended progression, unlike the runtime
-- stat overlay which never touches the saved slot.

local ServerStorage = game:GetService("ServerStorage")

local FormConfig = require(ServerStorage.Modules.FormConfig)

local MAX = FormConfig.Config.MaxMasteryLevel

local Mastery = {}

export type Entry = { Level: number, XP: number }

-- XP required to go from `level` to `level + 1`.
local function xpToNext(level: number): number
	return FormConfig.Config.XpBasePerLevel * level
end

function Mastery.ensure(slot: any, formName: string): Entry
	if not slot.FormMastery then
		slot.FormMastery = {}
	end
	local entry = slot.FormMastery[formName]
	if not entry then
		entry = { Level = 1, XP = 0 }
		slot.FormMastery[formName] = entry
	end
	return entry
end

function Mastery.getLevel(slot: any, formName: string): number
	local fm = slot.FormMastery
	local entry = fm and fm[formName]
	return if entry then entry.Level else 1
end

-- Adds XP and applies any resulting level-ups. Returns (newLevel, leveledUp).
function Mastery.addXP(slot: any, formName: string, amount: number): (number, boolean)
	local entry = Mastery.ensure(slot, formName)
	if entry.Level >= MAX then
		entry.XP = 0
		return entry.Level, false
	end

	entry.XP += amount
	local leveled = false
	while entry.Level < MAX and entry.XP >= xpToNext(entry.Level) do
		entry.XP -= xpToNext(entry.Level)
		entry.Level += 1
		leveled = true
	end
	if entry.Level >= MAX then
		entry.XP = 0
	end
	return entry.Level, leveled
end

-- Active duration in seconds; math.huge at max level (caller skips the expire timer).
function Mastery.durationForLevel(def: FormConfig.FormDef, level: number): number
	if level >= MAX then
		return math.huge
	end
	return def.baseDuration + (level - 1) * def.durationStep
end

-- Drain scale (1 at level 1 → 0 at max level). Multiply any per-second base drain by this.
function Mastery.drainScale(level: number): number
	if level >= MAX then
		return 0
	end
	return 1 - (level - 1) / (MAX - 1)
end

return Mastery
