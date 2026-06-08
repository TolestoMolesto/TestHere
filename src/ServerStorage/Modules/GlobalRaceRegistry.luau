--!strict
-- ─────────────────────────────────────────────
-- GlobalRaceRegistry.luau
-- Cross-server registry for limited global races (Angel / God / Kai).
--
-- Limits per race:
--   MAX_TOTAL  = 12  total holders across all servers
--   MAX_ROLLED =  4  of those 12 may come from rolling
--                 8  are reserved for admin grants
--
-- The registry lives in a single DataStore key updated via UpdateAsync
-- so concurrent claims from different servers are atomic.
--
-- An in-memory cache avoids a DataStore read on every roll. It is
-- populated on module load (task.spawn) and kept current by local
-- claim/release operations. Across servers the cache may be slightly
-- stale, but with a 12-person cap the tiny race window is acceptable.
--
-- Public API:
--   canRoll(race)                         → bool  (sync, uses cache)
--   claim(userId, race, isFromRoll)       → (bool, reason?)
--   release(userId, race)                 → bool
--   adminGrant(userId, race)              → (bool, reason?)
--   adminRevoke(userId, race)             → bool
--   fetchCache()                          → bool
-- ─────────────────────────────────────────────

local DataStoreService = game:GetService("DataStoreService")
local RunService       = game:GetService("RunService")

local STORE_NAME   = "GlobalRaceRegistry"
local REGISTRY_KEY = if RunService:IsStudio()
	then "GlobalRacesStudio_v1"
	else "GlobalRacesLive_v1"

local MAX_TOTAL  = 12
local MAX_ROLLED = 4

-- ── Types ────────────────────────────────────────────────────────────

type RaceEntry = {
	rolled: { number }, -- userIds obtained via roll
	admin:  { number }, -- userIds obtained via admin grant
}

type RegistryData = {
	Angel: RaceEntry,
	God:   RaceEntry,
	Kai:   RaceEntry,
}

-- ── Helpers ──────────────────────────────────────────────────────────

local function emptyRegistry(): RegistryData
	return {
		Angel = { rolled = {}, admin = {} },
		God   = { rolled = {}, admin = {} },
		Kai   = { rolled = {}, admin = {} },
	}
end

-- "ANGEL" → "Angel", "angel" → "Angel"
local function normalize(race: string): string
	return race:sub(1, 1):upper() .. race:sub(2):lower()
end

local function contains(list: { number }, userId: number): boolean
	for _, id in list do
		if id == userId then
			return true
		end
	end
	return false
end

-- ── Module ───────────────────────────────────────────────────────────

local Store = DataStoreService:GetDataStore(STORE_NAME)

local cache: RegistryData? = nil

local GlobalRaceRegistry = {}

-- Fetch the live registry and populate the local cache.
-- Returns true on success. Safe to call multiple times.
function GlobalRaceRegistry.fetchCache(): boolean
	local ok, data = pcall(function()
		return Store:GetAsync(REGISTRY_KEY)
	end)
	if ok then
		cache = (data :: RegistryData?) or emptyRegistry()
		return true
	end
	warn("[GlobalRaceRegistry] fetchCache failed:", tostring(data))
	return false
end

-- Returns true if there is an open roll slot for this race.
-- Uses the local cache — call fetchCache on server start.
function GlobalRaceRegistry.canRoll(race: string): boolean
	if not cache then
		return false
	end
	local entry = (cache :: RegistryData)[normalize(race)]
	if not entry then
		return false
	end
	return #entry.rolled < MAX_ROLLED
		and (#entry.rolled + #entry.admin) < MAX_TOTAL
end

-- Atomically claim a global-race slot.
-- isFromRoll = true  → counts against the roll quota (4 per race)
-- isFromRoll = false → counts against the admin quota (8 per race)
-- Returns (true, nil) on success or (false, reason) on failure.
function GlobalRaceRegistry.claim(
	userId: number,
	race: string,
	isFromRoll: boolean
): (boolean, string?)
	local raceKey = normalize(race)
	local reason: string? = nil
	local claimed = false

	local ok, err = pcall(function()
		Store:UpdateAsync(REGISTRY_KEY, function(raw: any)
			local data: RegistryData = raw or emptyRegistry()
			local entry: RaceEntry? = (data :: any)[raceKey]
			if not entry then
				reason = "Unknown race: " .. raceKey
				return nil
			end

			-- No-op if already registered
			if contains(entry.rolled, userId) or contains(entry.admin, userId) then
				reason = "Player is already a holder of this race"
				return nil
			end

			local total = #entry.rolled + #entry.admin
			if total >= MAX_TOTAL then
				reason = "Global race is full (12/12)"
				return nil
			end
			if isFromRoll and #entry.rolled >= MAX_ROLLED then
				reason = "All roll slots for this race are taken (4/4)"
				return nil
			end

			if isFromRoll then
				table.insert(entry.rolled, userId)
			else
				table.insert(entry.admin, userId)
			end

			claimed = true
			cache = data -- keep local cache in sync
			return data
		end)
	end)

	if not ok then
		return false, tostring(err)
	end
	return claimed, reason
end

-- Atomically release a player's global-race slot (e.g. on reroll or reset).
-- Returns true if the player was found and removed, false otherwise.
function GlobalRaceRegistry.release(userId: number, race: string): boolean
	local raceKey = normalize(race)
	local released = false

	local ok, err = pcall(function()
		Store:UpdateAsync(REGISTRY_KEY, function(raw: any)
			local data: RegistryData = raw or emptyRegistry()
			local entry: RaceEntry? = (data :: any)[raceKey]
			if not entry then
				return nil
			end

			for i, id in entry.rolled do
				if id == userId then
					table.remove(entry.rolled, i)
					released = true
					break
				end
			end
			if not released then
				for i, id in entry.admin do
					if id == userId then
						table.remove(entry.admin, i)
						released = true
						break
					end
				end
			end

			if not released then
				return nil -- nothing changed, cancel the write
			end
			cache = data
			return data
		end)
	end)

	if not ok then
		warn("[GlobalRaceRegistry] release failed:", tostring(err))
		return false
	end
	return released
end

-- Convenience wrappers for admin tools.
function GlobalRaceRegistry.adminGrant(userId: number, race: string): (boolean, string?)
	return GlobalRaceRegistry.claim(userId, race, false)
end

function GlobalRaceRegistry.adminRevoke(userId: number, race: string): boolean
	return GlobalRaceRegistry.release(userId, race)
end

-- Seed the cache as soon as the module loads so it is ready before the
-- first player can join.
task.spawn(GlobalRaceRegistry.fetchCache)

return GlobalRaceRegistry
