--!strict
-- ─────────────────────────────────────────────
-- RollRace.luau
-- Race assignment for SlotData.
--
-- Lifecycle:
--   • New slots start with Race = "NA".
--   • The first time a slot is activated we auto-roll for FREE
--     (RollRace.autoRoll). The very first roll is "on us".
--   • Subsequent rolls cost 1 Shared.Spins (RollRace.reroll).
--
-- Global races (ANGEL / GOD / KAI) are placeholder rolls. When one
-- lands, the slot's Race holds the global name and callers should
-- surface a picker UI; the player resolves it via RollRace.pickRace
-- by choosing any unlocked basic race.
-- ─────────────────────────────────────────────

local ServerStorage = game:GetService("ServerStorage")

local GlobalRaceRegistry = require(ServerStorage.Modules.GlobalRaceRegistry)
local Manager            = require(ServerStorage.Modules.Manager)
local RaceNames          = require(ServerStorage.Modules.RaceNames)
local RaceStats          = require(ServerStorage.Modules.RaceStats)

local NA = "NA"
local FALLBACK_RACE = "Human"
local GLOBAL_RACE_CHANCE = 10000
local LSSJ_CHANCE = 10000
local REROLL_COST = 1

type BasicRace = {
	Name: string,
	UnlockFlag: string?,
}

local BASIC_RACES: { BasicRace } = {
	{ Name = "Human",    UnlockFlag = nil },
	{ Name = "Namekian", UnlockFlag = nil },
	{ Name = "Acrosian", UnlockFlag = nil },
	{ Name = "Majin",    UnlockFlag = "Majin" },
	{ Name = "Saiyan",   UnlockFlag = nil },
	{ Name = "Sphinx",   UnlockFlag = nil },
}

local GLOBAL_RACES: { string } = { "ANGEL", "GOD", "KAI" }

local RNG = Random.new()

local RollRace = {}

-- Returns the uppercase global race name ("ANGEL", "GOD", "KAI") if the
-- given slot is recorded as its holder in Shared.GlobalRaces, or nil.
-- Keys are stored as "Angel"/"God"/"Kai" so we uppercase before returning.
local function getGlobalRaceForSlot(player: Player, slotIndex: number): string?
	local shared = Manager.getShared(player)
	if not shared then return nil end
	for raceName, heldSlot in shared.GlobalRaces do
		if heldSlot == slotIndex then
			return raceName:upper() -- "Angel" → "ANGEL"
		end
	end
	return nil
end

-- Pick a random name from the race pool and write it to the slot.
-- Also applies the race's base stats. No-op on empty pools.
-- If Shared.GlobalRaces shows this slot holds a global race, names are
-- drawn from that global's pool (ANGEL/GOD/KAI) instead of the basic race.
local function assignRandomName(player: Player, slotIndex: number, slot: any, race: string)
	local globalRace = getGlobalRaceForSlot(player, slotIndex)
	local nameRace = if globalRace then globalRace else race
	local pool = RaceNames.get(nameRace)
	if #pool > 0 then
		slot.Name = pool[RNG:NextInteger(1, #pool)]
	end
	RaceStats.applyToSlot(slot, race)
end

local function isUnlocked(unlocks: { [string]: boolean }?, flag: string?): boolean
	if not flag then
		return true
	end
	return unlocks ~= nil and unlocks[flag] == true
end

local function buildBasicPool(player: Player): { string }
	local shared = Manager.getShared(player)
	local unlocks = if shared then shared.Unlocks else nil
	local pool: { string } = {}
	for _, race in BASIC_RACES do
		if isUnlocked(unlocks, race.UnlockFlag) then
			table.insert(pool, race.Name)
		end
	end
	return pool
end

local function rollOnce(player: Player): string
	local basicPool = buildBasicPool(player)
	if #basicPool == 0 then
		return FALLBACK_RACE
	end
	if RNG:NextInteger(1, GLOBAL_RACE_CHANCE) == 1 then
		-- Only include global races that still have open roll slots.
		local available: { string } = {}
		for _, name in GLOBAL_RACES do
			if GlobalRaceRegistry.canRoll(name) then
				table.insert(available, name)
			end
		end
		if #available > 0 then
			return available[RNG:NextInteger(1, #available)]
		end
		-- All global races are at roll capacity — fall through to basic.
	end
	return basicPool[RNG:NextInteger(1, #basicPool)]
end

function RollRace.isGlobalRace(raceName: string): boolean
	for _, name in GLOBAL_RACES do
		if name == raceName then
			return true
		end
	end
	return false
end

-- Returns the list of selectable names for the given race.
-- Returns an empty table if the race has no defined name list.
function RollRace.getNamesForRace(raceName: string): { string }
	return RaceNames.get(raceName)
end

-- Validate and apply a name choice for a slot.
-- If Shared.GlobalRaces ties this slot to a global race, names must come
-- from that global's pool; otherwise the slot's basic race pool is used.
function RollRace.pickName(player: Player, slotIndex: number, name: string): (boolean, string?)
	local slot = Manager.getSlot(player, slotIndex)
	if not slot then
		return false, "Slot not found"
	end
	local globalRace = getGlobalRaceForSlot(player, slotIndex)
	local poolRace = if globalRace then globalRace else slot.Race
	local validNames = RaceNames.get(poolRace)
	if #validNames == 0 then
		return false, "No names defined for race: " .. poolRace
	end
	for _, validName in validNames do
		if validName == name then
			slot.Name = name
			return true, nil
		end
	end
	return false, "Name is not available for this race"
end

-- One-shot LegendarySuperSaiyan upgrade check. Call this from CharacterAdded
-- (via StatsManager) on every spawn so it fires on the first spawn after a
-- Saiyan roll. Subsequent spawns are no-ops until the race is reassigned.
--
-- Returns:
--   (true,  nil)               → LegendarySuperSaiyan awarded
--   (false, "failed")          → checked but lost the roll
--   (false, "already_checked") → check already ran for this Saiyan roll
--   (false, "not_saiyan")      → slot race is not Saiyan, nothing to do
function RollRace.checkLSSJ(player: Player, slotIndex: number): (boolean, string?)
	local slot = Manager.getSlot(player, slotIndex)
	if not slot then
		return false, "Slot not found"
	end
	if slot.Race ~= "Saiyan" then
		return false, "not_saiyan"
	end
	if slot.LSSJChecked then
		return false, "already_checked"
	end
	slot.LSSJChecked = true
	if RNG:NextInteger(1, LSSJ_CHANCE) == 1 then
		slot.Race = "LegendarySuperSaiyan"
		assignRandomName(player, slotIndex, slot, "LegendarySuperSaiyan")
		return true, nil
	end
	return false, "failed"
end

-- Free roll. No-op if the slot already has a non-NA race so we never
-- silently overwrite a real race on re-entry.
function RollRace.autoRoll(player: Player, slotIndex: number): string?
	local slot = Manager.getSlot(player, slotIndex)
	if not slot then
		return nil
	end
	if slot.Race ~= NA then
		return slot.Race
	end
	slot.Race = rollOnce(player)
	slot.LSSJChecked = false
	assignRandomName(player, slotIndex, slot, slot.Race)
	return slot.Race
end

-- Convenience for the join flow: roll the currently active slot if it
-- has never been rolled.
function RollRace.autoRollActive(player: Player): string?
	local profile = Manager.getProfile(player)
	if not profile then
		return nil
	end
	return RollRace.autoRoll(player, profile.Data.ActiveSlot)
end

-- Paid reroll. Returns (newRace, nil) on success, (nil, reason) on failure.
-- Spins are only deducted after the slot/profile checks pass.
-- If the slot currently holds a global race, the player is removed from
-- the global registry before the new race is assigned.
function RollRace.reroll(player: Player, slotIndex: number): (string?, string?)
	local slot = Manager.getSlot(player, slotIndex)
	if not slot then
		return nil, "Slot not found"
	end
	local shared = Manager.getShared(player)
	if not shared then
		return nil, "Profile not loaded"
	end
	if shared.Spins < REROLL_COST then
		return nil, "Not enough spins"
	end

	-- Release from global registry if this slot is registered as a holder.
	for raceName, heldSlot in shared.GlobalRaces do
		if heldSlot == slotIndex then
			GlobalRaceRegistry.release(player.UserId, raceName)
			shared.GlobalRaces[raceName] = 0
			break -- a slot can hold at most one global race
		end
	end

	shared.Spins -= REROLL_COST
	slot.Race = rollOnce(player)
	slot.LSSJChecked = false
	assignRandomName(player, slotIndex, slot, slot.Race)
	return slot.Race, nil
end

-- Resolve a global-race placeholder by picking any unlocked basic.
-- Rejected if the slot isn't currently holding a global, or the
-- chosen race isn't in the player's unlocked basic pool.
-- On success this also claims the global-race slot in the registry
-- and records the slot index in Shared.GlobalRaces.
function RollRace.pickRace(player: Player, slotIndex: number, raceName: string): (boolean, string?)
	local slot = Manager.getSlot(player, slotIndex)
	if not slot then
		return false, "Slot not found"
	end
	local pendingGlobal = slot.Race -- e.g. "ANGEL" or "KAI"
	if not RollRace.isGlobalRace(pendingGlobal) then
		return false, "Slot is not pending a pick"
	end
	local shared = Manager.getShared(player)
	if not shared then
		return false, "Profile not loaded"
	end
	for _, allowed in buildBasicPool(player) do
		if allowed == raceName then
			-- Attempt to register in the global DataStore first so we
			-- never write the race locally if the registry is full.
			local claimed, reason = GlobalRaceRegistry.claim(player.UserId, pendingGlobal, true)
			if not claimed then
				return false, reason or "Failed to claim global race slot"
			end
			slot.Race = raceName
			slot.LSSJChecked = false
			-- Write shared.GlobalRaces BEFORE assignRandomName so the lookup
			-- inside it sees this slot as a global-race holder.
			local normalized = pendingGlobal:sub(1, 1):upper() .. pendingGlobal:sub(2):lower()
			shared.GlobalRaces[normalized] = slotIndex
			assignRandomName(player, slotIndex, slot, raceName)
			return true, nil
		end
	end
	return false, "Race not unlocked"
end

return RollRace
