--!strict
-- CLIENT-ONLY: mutable singleton — requiring on the server would share state across all players.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Settings = {}

export type LockOnStyle = "Dynamic_View" | "FreeCam" | "FaceOff"

local LOCK_ON_STYLES: { [string]: boolean } = {
	Dynamic_View = true,
	FreeCam = true,
	FaceOff = true,
}

local DEFAULTS = {
	Audio = {
		Music = 0.5, -- 0..1, scales the Music SoundGroup
		SFX = 0.5, -- 0..1, scales the SFX SoundGroup (everything that isn't music)
	},
	LockOn = {
		Style = "Dynamic_View" :: string, -- one of LOCK_ON_STYLES
		FOV = 1, -- 1..10 dial; the controller maps it to a field-of-view
		Transparency = 0.5, -- 0..1 LocalTransparencyModifier on your own body while locked
	},
	Camera = {
		Shake = true, -- master toggle for hit/damage camera shake
	},
}

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value do
		copy[key] = deepCopy(child)
	end
	return copy
end

local values = deepCopy(DEFAULTS)
local listeners: { (section: string, key: string, value: any) -> () } = {}

local function fireChanged(section: string, key: string, value: any): ()
	for _, fn in listeners do
		task.spawn(fn, section, key, value)
	end
end

function Settings.get(section: string, key: string): any
	local group = values[section]
	assert(group ~= nil, `Settings: unknown section "{section}"`)
	local value = group[key]
	assert(value ~= nil, `Settings: unknown key "{section}.{key}"`)
	return value
end

-- Applies a value locally (validate -> store -> notify) WITHOUT pushing to the server. Shared by
-- the user-facing set() and by hydrate() when saved values come back from the server.
local function applyLocal(section: string, key: string, value: any): boolean
	local group = values[section]
	if group == nil or group[key] == nil then
		return false
	end
	if typeof(value) ~= typeof(group[key]) then
		return false
	end
	if section == "LockOn" and key == "Style" and not LOCK_ON_STYLES[value] then
		return false
	end
	if section == "Audio" then
		value = math.clamp(value, 0, 1)
	end
	group[key] = value
	fireChanged(section, key, value)
	return true
end

-- The server re-validates and persists to GLOBAL profile data (PlayerData.Settings). Lazy-require
-- Remotes so this module stays importable without forcing the Remotes folder to exist yet.
local function push(section: string, key: string, value: any): ()
	if not RunService:IsClient() then
		return
	end
	local Remotes = require(ReplicatedStorage.Modules.Remotes)
	Remotes.UpdateSetting:FireServer(section, key, value)
end

function Settings.set(section: string, key: string, value: any): boolean
	if not applyLocal(section, key, value) then
		return false
	end
	push(section, key, values[section][key]) -- push the stored (clamped) value
	return true
end

-- Overwrite local values from a server blob without echoing back. Unknown sections/keys and type
-- mismatches are ignored by applyLocal.
function Settings.hydrate(blob: { [string]: { [string]: any } }?): ()
	if typeof(blob) ~= "table" then
		return
	end
	for section, keys in blob do
		if typeof(keys) == "table" then
			for key, value in keys do
				applyLocal(section, key, value)
			end
		end
	end
end

function Settings.onChanged(fn: (section: string, key: string, value: any) -> ()): () -> ()
	table.insert(listeners, fn)
	return function()
		local index = table.find(listeners, fn)
		if index then
			table.remove(listeners, index)
		end
	end
end

return Settings
