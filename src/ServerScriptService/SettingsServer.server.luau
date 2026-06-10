--!strict
-- Persists player Settings (Audio / LockOn / Camera) to GLOBAL profile data (PlayerData.Settings,
-- not per slot). Clients pull their saved blob via GetSettings on load and push one key per change
-- via UpdateSetting. Every value is re-validated here -- the client is never trusted.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Manager = require(ServerStorage.Modules.Manager)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Template = require(ServerStorage.Modules.TemplateData)

-- Create the Music/SFX SoundGroups on the server at startup, so they exist for clients to wait on
-- and server-spawned sounds (ki blasts, vanish FX) have a canonical group to route through.
require(ReplicatedStorage.Modules.Audio)

local LOCK_ON_STYLES: { [string]: boolean } = {
	Dynamic_View = true,
	FreeCam = true,
	FaceOff = true,
}

local DEFAULT_SETTINGS = Template.PLAYER_DATA_TEMPLATE.Settings

-- Returns a sanitised value, or nil to reject. Shape is checked against the template defaults
-- (known section + key, matching type); per-field constraints clamp/whitelist the value.
local function sanitise(section: string, key: string, value: any): any?
	local sectionDefaults = (DEFAULT_SETTINGS :: any)[section]
	if typeof(sectionDefaults) ~= "table" or sectionDefaults[key] == nil then
		return nil
	end
	if typeof(value) ~= typeof(sectionDefaults[key]) then
		return nil
	end
	if section == "Audio" then
		return math.clamp(value, 0, 1)
	elseif section == "LockOn" then
		if key == "Style" then
			return if LOCK_ON_STYLES[value] then value else nil
		elseif key == "FOV" then
			return math.clamp(value, 1, 10)
		elseif key == "Transparency" then
			return math.clamp(value, 0, 1)
		end
	end
	return value
end

Remotes.GetSettings.OnServerInvoke = function(player: Player): any
	local profile = Manager.getProfile(player)
	return if profile then profile.Data.Settings else nil
end

Remotes.UpdateSetting.OnServerEvent:Connect(function(player: Player, section: any, key: any, value: any)
	if typeof(section) ~= "string" or typeof(key) ~= "string" then
		return
	end
	local profile = Manager.getProfile(player)
	if not profile then
		return
	end
	local clean = sanitise(section, key, value)
	if clean == nil then
		return
	end
	local settings = profile.Data.Settings :: any
	if typeof(settings[section]) == "table" then
		settings[section][key] = clean
	end
end)
