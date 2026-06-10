--!strict
-- Bridges the client Settings singleton to the server: applies the Audio settings to the live
-- SoundGroups, then hydrates Settings + Keybinds from the player's saved (global) profile data on load.
-- Settings.set() pushes individual changes back on its own; this only handles load + audio sync.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Audio = require(ReplicatedStorage.Modules.Audio)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Settings = require(ReplicatedStorage.Modules.Settings)
local Keybinds = require(ReplicatedStorage.Modules.Keybinds)

local player = Players.LocalPlayer

-- Keep the SoundGroup volumes in step with the Audio settings (covers both hydration and live
-- slider moves, since hydrate() fires onChanged too).
Settings.onChanged(function(section: string, key: string, value: any): ()
	if section == "Audio" then
		Audio.setVolume(key :: Audio.Category, value)
	end
end)

-- Apply current (default) volumes immediately so audio is sane before the saved blob arrives.
Audio.setVolume("Music", Settings.get("Audio", "Music"))
Audio.setVolume("SFX", Settings.get("Audio", "SFX"))

local hydrated = false
local function hydrate(): ()
	if hydrated then
		return
	end
	hydrated = true
	Settings.hydrate(Remotes.GetSettings:InvokeServer())
	Keybinds.hydrate(Remotes.GetKeybinds:InvokeServer())
end

-- The profile may already be loaded (attribute), arrive via the event, or land between the two --
-- cover all three, with the guard preventing a double pull.
Remotes.ProfileLoaded.OnClientEvent:Connect(hydrate)
player:GetAttributeChangedSignal("ProfileLoaded"):Connect(function(): ()
	if player:GetAttribute("ProfileLoaded") then
		hydrate()
	end
end)
if player:GetAttribute("ProfileLoaded") then
	hydrate()
end
