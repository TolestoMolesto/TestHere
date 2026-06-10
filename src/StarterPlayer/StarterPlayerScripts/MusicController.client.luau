--!strict
-- Background music. The default song loops through the Music SoundGroup, so the player's Music
-- slider (Settings.Audio.Music, applied by SettingsBootstrap) controls its volume.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Audio = require(ReplicatedStorage.Modules.Audio)

local music = Audio.create(Audio.Music.Default, "Music")
music.Parent = SoundService
music:Play()
