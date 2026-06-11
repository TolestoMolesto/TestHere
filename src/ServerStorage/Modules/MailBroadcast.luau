--!strict
-- Global broadcast-mail registry: the shared store behind "send this mail + rewards to EVERYONE".
-- Modeled on GlobalRaceRegistry -- one DataStore key holds the list of active broadcasts; every server
-- reads it (cached) and materializes new ones into each player's account-wide inbox (Mail.syncBroadcasts),
-- so a broadcast reaches offline players and anyone who joins within its lifetime -- not just whoever's
-- online when it's posted. Personal mail does NOT come through here (it's appended straight to a profile).
--
-- POST a broadcast = MailBroadcast.post(spec); spec mirrors a personal mail: { from, subject, body,
-- rewards, expiresInDays? }. Expired broadcasts are pruned inside the same write, so the key stays small.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Template = require(ServerStorage.Modules.TemplateData)

local STORE_NAME = "MailBroadcast"
local REGISTRY_KEY = if RunService:IsStudio() then "MailBroadcastStudio_v1" else "MailBroadcastLive_v1"

local DAY_SECONDS = 86400
local DEFAULT_EXPIRY_DAYS = 7
-- Hard cap on stored broadcasts so the single key can never grow unbounded; oldest fall off first.
local MAX_BROADCASTS = 50

export type Broadcast = {
	id: string,
	from: string,
	subject: string,
	body: string,
	sentAt: number,
	expiresAt: number,
	rewards: { Template.MailReward },
}

export type Spec = {
	from: string?,
	subject: string?,
	body: string?,
	rewards: { Template.MailReward }?,
	expiresInDays: number?,
}

type RegistryData = {
	broadcasts: { Broadcast },
}

local Store = DataStoreService:GetDataStore(STORE_NAME)
local cache: { Broadcast } = {}

local MailBroadcast = {}

local function isActive(b: Broadcast, now: number): boolean
	return typeof(b) == "table" and typeof(b.expiresAt) == "number" and b.expiresAt > now
end

-- Drop expired entries and clamp to the newest MAX_BROADCASTS (keeps the stored key bounded). Entries
-- are appended in order, so index 1 is always the oldest.
local function cleanse(list: { Broadcast }, now: number): { Broadcast }
	local out: { Broadcast } = {}
	for _, b in list do
		if isActive(b, now) then
			table.insert(out, b)
		end
	end
	while #out > MAX_BROADCASTS do
		table.remove(out, 1)
	end
	return out
end

-- Refresh the local cache from the store (mirrors GlobalRaceRegistry.fetchCache); eventually consistent
-- across servers. Returns true on a successful read.
function MailBroadcast.fetchCache(): boolean
	local ok, data = pcall(function()
		return Store:GetAsync(REGISTRY_KEY)
	end)
	if ok then
		local raw = data :: RegistryData?
		local list = if raw and typeof(raw.broadcasts) == "table" then raw.broadcasts else {}
		cache = cleanse(list, os.time())
		return true
	end
	warn("[MailBroadcast] fetchCache failed:", tostring(data))
	return false
end

-- The currently-active broadcasts (cached, re-filtered by time on read so a stale cache never serves an
-- expired one). Mail.syncBroadcasts iterates this.
function MailBroadcast.activeBroadcasts(): { Broadcast }
	return cleanse(cache, os.time())
end

-- Append a new broadcast for everyone; returns (id, nil) on success or (nil, err). Stamps id/sentAt/
-- expiresAt and prunes expired entries in the same transaction.
function MailBroadcast.post(spec: Spec): (string?, string?)
	if typeof(spec) ~= "table" then
		return nil, "spec must be a table"
	end
	local now = os.time()
	local days = if typeof(spec.expiresInDays) == "number" and spec.expiresInDays > 0
		then spec.expiresInDays
		else DEFAULT_EXPIRY_DAYS
	local entry: Broadcast = {
		id = HttpService:GenerateGUID(false),
		from = tostring(spec.from or "System"),
		subject = tostring(spec.subject or "Mail"),
		body = tostring(spec.body or ""),
		sentAt = now,
		expiresAt = now + math.floor(days * DAY_SECONDS),
		rewards = spec.rewards or {},
	}

	local ok, err = pcall(function()
		Store:UpdateAsync(REGISTRY_KEY, function(raw: any): RegistryData?
			local data: RegistryData = if typeof(raw) == "table" then raw else { broadcasts = {} }
			if typeof(data.broadcasts) ~= "table" then
				data.broadcasts = {}
			end
			table.insert(data.broadcasts, entry)
			data.broadcasts = cleanse(data.broadcasts, now)
			cache = data.broadcasts -- keep this server's cache fresh immediately
			return data
		end)
	end)
	if not ok then
		return nil, tostring(err)
	end
	return entry.id, nil
end

task.spawn(MailBroadcast.fetchCache)

return MailBroadcast
