local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Template = require(ServerStorage.Modules.TemplateData)
local ProfileStore = require(ServerStorage.Modules.ProfileStore)

-- Versioned keys: bump the suffix if the template ever changes in a
-- breaking way that Reconcile() can't handle. Studio playtests run
-- against a separate store so they never touch production data.
local DATA_KEY = if RunService:IsStudio() then "ReworkStudio_v1" else "ReworkLive_v1"

local PlayerStore = ProfileStore.New(DATA_KEY, Template.PLAYER_DATA_TEMPLATE)

export type ActiveProfile = typeof(PlayerStore:StartSessionAsync(""))

local Manager = {}

Manager.PlayerStore = PlayerStore
Manager.Profiles = {} :: {[Player]: ActiveProfile}

function Manager.getProfile(player: Player): ActiveProfile?
	return Manager.Profiles[player]
end

function Manager.getShared(player: Player): Template.SharedData?
	local profile = Manager.Profiles[player]
	return if profile then profile.Data.Shared else nil
end

function Manager.getSlotCount(player: Player): number
	local profile = Manager.Profiles[player]
	return if profile then #profile.Data.Slots else 0
end

function Manager.getSlot(player: Player, index: number): Template.SlotData?
	local profile = Manager.Profiles[player]
	if not profile then
		return nil
	end
	return profile.Data.Slots[index]
end

function Manager.getActiveSlot(player: Player): Template.SlotData?
	local profile = Manager.Profiles[player]
	if not profile then
		return nil
	end
	return profile.Data.Slots[profile.Data.ActiveSlot]
end

-- Append a fresh slot from SLOT_TEMPLATE. Returns the new slot and its
-- 1-based index, or nil if the profile isn't loaded.
function Manager.addSlot(player: Player): (Template.SlotData?, number?)
	local profile = Manager.Profiles[player]
	if not profile then
		return nil, nil
	end
	local slot = Template.newSlot()
	table.insert(profile.Data.Slots, slot)
	return slot, #profile.Data.Slots
end

-- Switch which slot is active. Returns true on success, false if the
-- profile isn't loaded or the index is out of range.
function Manager.switchSlot(player: Player, index: number): boolean
	local profile = Manager.Profiles[player]
	if not profile then
		return false
	end
	if index < 1 or index > #profile.Data.Slots then
		return false
	end
	profile.Data.ActiveSlot = index
	return true
end

ProfileStore.OnError:Connect(function(message: string, storeName: string, profileKey: string)
	warn(`[ProfileStore] error in {storeName}:{profileKey} -- {message}`)
end)

ProfileStore.OnCriticalToggle:Connect(function(isCritical: boolean)
	warn(`[ProfileStore] critical state -> {isCritical}`)
end)

return Manager
