--!strict

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local STORE_NAME = "GlobalRaceRegistry"
local REGISTRY_KEY = if RunService:IsStudio() then "GlobalRacesStudio_v1" else "GlobalRacesLive_v1"

local MAX_TOTAL = 12
local MAX_ROLLED = 4

type RaceEntry = {
	rolled: { number },
	admin: { number },
}

type RegistryData = {
	Angel: RaceEntry,
	God: RaceEntry,
	Kai: RaceEntry,
}

local function emptyRegistry(): RegistryData
	return {
		Angel = { rolled = {}, admin = {} },
		God = { rolled = {}, admin = {} },
		Kai = { rolled = {}, admin = {} },
	}
end

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

local Store = DataStoreService:GetDataStore(STORE_NAME)

local cache: RegistryData? = nil

local GlobalRaceRegistry = {}

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

function GlobalRaceRegistry.canRoll(race: string): boolean
	if not cache then
		return false
	end
	local entry = (cache :: RegistryData)[normalize(race)]
	if not entry then
		return false
	end
	return #entry.rolled < MAX_ROLLED and (#entry.rolled + #entry.admin) < MAX_TOTAL
end

function GlobalRaceRegistry.claim(userId: number, race: string, isFromRoll: boolean): (boolean, string?)
	local raceKey = normalize(race)
	local reason: string? = nil
	local claimed = false

	local ok, err = pcall(function()
		Store:UpdateAsync(REGISTRY_KEY, function(raw: any): RegistryData?
			local data: RegistryData = raw or emptyRegistry()
			local entry: RaceEntry? = (data :: any)[raceKey]
			if not entry then
				reason = "Unknown race: " .. raceKey
				return nil
			end

			-- no-op if already a holder (UpdateAsync requires returning nil to cancel)
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

function GlobalRaceRegistry.release(userId: number, race: string): boolean
	local raceKey = normalize(race)
	local released = false

	local ok, err = pcall(function()
		Store:UpdateAsync(REGISTRY_KEY, function(raw: any): RegistryData?
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
				return nil -- cancel write: nothing changed
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

type Availability = { rolled: number, rolledMax: number, total: number, totalMax: number }

-- Live counts for the roller UI ("0/4 Available"). Reads the local cache, so it reflects the last
-- successful fetch/claim/release on this server (eventually consistent across servers).
function GlobalRaceRegistry.availability(): { [string]: Availability }
	local out: { [string]: Availability } = {}
	for _, key in { "Angel", "God", "Kai" } do
		local entry: RaceEntry? = if cache then (cache :: any)[key] else nil
		local rolled = if entry then #entry.rolled else 0
		local admin = if entry then #entry.admin else 0
		out[key] = {
			rolled = rolled,
			rolledMax = MAX_ROLLED,
			total = rolled + admin,
			totalMax = MAX_TOTAL,
		}
	end
	return out
end

function GlobalRaceRegistry.adminGrant(userId: number, race: string): (boolean, string?)
	return GlobalRaceRegistry.claim(userId, race, false)
end

function GlobalRaceRegistry.adminRevoke(userId: number, race: string): boolean
	return GlobalRaceRegistry.release(userId, race)
end

task.spawn(GlobalRaceRegistry.fetchCache)

return GlobalRaceRegistry
