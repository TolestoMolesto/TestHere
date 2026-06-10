--!strict

local ServerStorage = game:GetService("ServerStorage")

local GlobalRaceRegistry = require(ServerStorage.Modules.GlobalRaceRegistry)
local Manager = require(ServerStorage.Modules.Manager)
local RaceNames = require(ServerStorage.Modules.RaceNames)
local RaceStats = require(ServerStorage.Modules.RaceStats)

local NA = "NA"
local FALLBACK_RACE = "Human"
local LSSJ_CHANCE = 10000
local REROLL_COST = 1

-- Global-race odds with pity. Basic-race odds stay uniform; only the chance to enter the global
-- branch is affected. The chance starts at GLOBAL_BASE_CHANCE and ramps with GlobalPity (rolls since
-- the last global), reaching a guaranteed 1.0 at PITY_GUARANTEE. PITY_CURVE shapes the ramp: 1 is a
-- straight line (generous early); higher values keep the odds near base for longer and concentrate
-- the boost near the guarantee, so PITY_GUARANTEE stays a meaningful bad-luck ceiling. Tune freely.
local GLOBAL_BASE_CHANCE = 1 / 10000
local PITY_GUARANTEE = 10000
local PITY_CURVE = 3

type BasicRace = {
	Name: string,
	UnlockFlag: string?,
}

local BASIC_RACES: { BasicRace } = {
	{ Name = "Human", UnlockFlag = nil },
	{ Name = "Namekian", UnlockFlag = nil },
	{ Name = "Acrosian", UnlockFlag = nil },
	{ Name = "Majin", UnlockFlag = "Majin" },
	{ Name = "Saiyan", UnlockFlag = nil },
	{ Name = "Sphinx", UnlockFlag = nil },
}

local GLOBAL_RACES: { string } = { "ANGEL", "GOD", "KAI" }

local RNG = Random.new()

local RollRace = {}

-- Keys stored as "Angel"/"God"/"Kai" in Shared.GlobalRaces; uppercase on return.
local function getGlobalRaceForSlot(player: Player, slotIndex: number): string?
	local shared = Manager.getShared(player)
	if not shared then
		return nil
	end
	for raceName, heldSlot in shared.GlobalRaces do
		if heldSlot == slotIndex then
			return raceName:upper() -- "Angel" → "ANGEL"
		end
	end
	return nil
end

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

-- Per-roll probability of entering the global branch, given pity (rolls since the last global).
local function computeGlobalChance(pity: number): number
	if pity >= PITY_GUARANTEE then
		return 1
	end
	local t = pity / PITY_GUARANTEE
	return math.clamp(GLOBAL_BASE_CHANCE + (1 - GLOBAL_BASE_CHANCE) * t ^ PITY_CURVE, GLOBAL_BASE_CHANCE, 1)
end

local function rollOnce(player: Player): string
	local shared = Manager.getShared(player)
	local basicPool = buildBasicPool(player)
	if #basicPool == 0 then
		return FALLBACK_RACE
	end
	if shared then
		shared.RollCount += 1
	end
	local pity = if shared then shared.GlobalPity else 0
	if RNG:NextNumber() < computeGlobalChance(pity) then
		-- Only include global races that still have open roll slots.
		local available: { string } = {}
		for _, name in GLOBAL_RACES do
			if GlobalRaceRegistry.canRoll(name) then
				table.insert(available, name)
			end
		end
		if #available > 0 then
			if shared then
				shared.GlobalPity = 0 -- a global landed: pity resets
			end
			return available[RNG:NextInteger(1, #available)]
		end
		-- A global was due but every race is at roll capacity: hold pity (don't reset) so the
		-- guarantee carries to the next roll, and fall through to a basic this time.
	end
	if shared then
		shared.GlobalPity += 1
	end
	return basicPool[RNG:NextInteger(1, #basicPool)]
end

-- True if this slot currently has a global, either as a pending pick (slot.Race is "ANGEL"/etc, not
-- yet converted) or as a claimed holder recorded in Shared.GlobalRaces. Used to gate reroll.
local function holdsGlobal(slotIndex: number, slot: any, shared: any): boolean
	if RollRace.isGlobalRace(slot.Race) then
		return true
	end
	for _, heldSlot in shared.GlobalRaces do
		if heldSlot == slotIndex then
			return true
		end
	end
	return false
end

function RollRace.isGlobalRace(raceName: string): boolean
	for _, name in GLOBAL_RACES do
		if name == raceName then
			return true
		end
	end
	return false
end

function RollRace.getNamesForRace(raceName: string): { string }
	return RaceNames.get(raceName)
end

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

function RollRace.autoRollActive(player: Player): string?
	local profile = Manager.getProfile(player)
	if not profile then
		return nil
	end
	return RollRace.autoRoll(player, profile.Data.ActiveSlot)
end

function RollRace.reroll(player: Player, slotIndex: number, confirmed: boolean?): (string?, string?)
	local slot = Manager.getSlot(player, slotIndex)
	if not slot then
		return nil, "Slot not found"
	end
	local shared = Manager.getShared(player)
	if not shared then
		return nil, "Profile not loaded"
	end
	-- Rerolling releases any held/pending global back to the registry -- i.e. you lose it. Require an
	-- explicit confirmation so a stray click (or an auto-spin) can't throw away something this rare.
	if not confirmed and holdsGlobal(slotIndex, slot, shared) then
		return nil, "needs_confirmation"
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
			local claimed, reason = GlobalRaceRegistry.claim(player.UserId, pendingGlobal, true)
			if not claimed then
				return false, reason or "Failed to claim global race slot"
			end
			slot.Race = raceName
			slot.LSSJChecked = false
			-- Must write GlobalRaces BEFORE assignRandomName so getGlobalRaceForSlot sees it.
			local normalized = pendingGlobal:sub(1, 1):upper() .. pendingGlobal:sub(2):lower()
			shared.GlobalRaces[normalized] = slotIndex
			assignRandomName(player, slotIndex, slot, raceName)
			return true, nil
		end
	end
	return false, "Race not unlocked"
end

-- === State helpers for the Race Roller UI (RollServer assembles GetRollState from these) =========

RollRace.PITY_GUARANTEE = PITY_GUARANTEE

-- Current per-roll global chance for this many dry rolls (0..1). Exposed so the UI can display it.
function RollRace.globalChance(pity: number): number
	return computeGlobalChance(pity)
end

-- The unlocked basic races this player can actually roll (respects unlock flags).
function RollRace.unlockedBasics(player: Player): { string }
	return buildBasicPool(player)
end

-- Every basic race with its unlock state, for the collection list (so locked races still show).
function RollRace.allBasics(player: Player): { { name: string, unlocked: boolean } }
	local shared = Manager.getShared(player)
	local unlocks = if shared then shared.Unlocks else nil
	local out: { { name: string, unlocked: boolean } } = {}
	for _, race in BASIC_RACES do
		table.insert(out, { name = race.Name, unlocked = isUnlocked(unlocks, race.UnlockFlag) })
	end
	return out
end

-- The global race ids in roll order, for the UI's global panel.
function RollRace.globalRaces(): { string }
	return table.clone(GLOBAL_RACES)
end

-- Whether a slot currently holds a global (pending pick or claimed). Gates the reroll confirmation.
function RollRace.hasGlobal(player: Player, slotIndex: number): boolean
	local slot = Manager.getSlot(player, slotIndex)
	local shared = Manager.getShared(player)
	if not slot or not shared then
		return false
	end
	return holdsGlobal(slotIndex, slot, shared)
end

return RollRace
