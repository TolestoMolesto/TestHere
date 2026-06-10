--!strict
-- Central audio routing. Two SoundGroups (Music / SFX) are created in code at runtime -- nothing
-- is prestaged in SoundService, so there's no asset/replication cost sitting in the tree before a
-- sound actually plays.
--
-- The player's Music/SFX sliders just set the matching group's Volume *locally* on each client,
-- which scales every sound routed through that group. That includes server-spawned sounds (ki
-- blasts, vanish FX): the Sound instance and its .SoundGroup link replicate, but each client owns
-- its own copy of the group's Volume, so the slider is genuinely per-player.
--
-- "SFX" is the default category -- everything that isn't music.

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Audio = {}

export type Category = "Music" | "SFX"
export type Def = {
	SoundId: string,
	Volume: number?,
	Looped: boolean?,
	PlaybackSpeed: number?,
	RollOffMaxDistance: number?,
}

local CATEGORIES: { Category } = { "Music", "SFX" }
local GROUP_WAIT = 10
local ONESHOT_SAFETY = 30 -- cleanup net for a one-shot whose .Ended never fires (asset failed)

-- The server owns creation so there's a single canonical group every server-spawned sound can
-- point at; clients wait for it to replicate.
local function ensureGroup(name: string): SoundGroup
	local existing = SoundService:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	if not RunService:IsServer() then
		local replicated = SoundService:WaitForChild(name, GROUP_WAIT)
		if replicated and replicated:IsA("SoundGroup") then
			return replicated
		end
		warn(`[Audio] SoundGroup "{name}" never replicated; using a local fallback`)
	end
	local group = Instance.new("SoundGroup")
	group.Name = name
	group.Volume = 1
	group.Parent = SoundService
	return group
end

-- Keyed by string (not Category) so the "or SFX" default and the loop var index cleanly; the
-- public functions still constrain callers to Category.
local groups: { [string]: SoundGroup } = {}
for _, name in CATEGORIES do
	groups[name] = ensureGroup(name)
end

-- Named library: call sites reference a sound by meaning, not a bare asset id, and all the ids
-- live in one place. Add new SFX here.
local SFX: { [string]: Def } = {
	-- Scouter
	Found = { SoundId = "rbxassetid://234331877", Volume = 0.6 },
	Searching = { SoundId = "rbxassetid://891918584", Volume = 0.5, Looped = true },
	-- Flight
	ActivateFlight = { SoundId = "rbxassetid://254903597", Volume = 0.5 },
	Fly = { SoundId = "rbxassetid://254902618", Volume = 0.4, Looped = true },
	Land = { SoundId = "rbxassetid://254903308", Volume = 0.5 },
	-- Entrance fanfare played for everyone when the special person joins.
	SpecialJoin = { SoundId = "rbxassetid://131239150106458", Volume = 0.7 },
}
Audio.SFX = SFX

-- Music tracks. The Music slider scales the Music SoundGroup these route through.
local MUSIC: { [string]: Def } = {
	Default = { SoundId = "rbxassetid://106753822730934", Volume = 0.5, Looped = true },
}
Audio.Music = MUSIC

function Audio.group(category: Category): SoundGroup
	return groups[category]
end

-- Set a category's local volume (0..1). The client calls this when a slider moves.
function Audio.setVolume(category: Category, volume: number): ()
	groups[category].Volume = math.clamp(volume, 0, 1)
end

-- Route an already-built Sound into a category (default SFX). For inline sounds you don't want to
-- rewrite onto a Def.
function Audio.tag(sound: Sound, category: Category?): Sound
	sound.SoundGroup = groups[category or "SFX"]
	return sound
end

-- Build a routed Sound from a Def; the caller owns its lifecycle (parent / play / stop / destroy).
-- Use this for looped or persistent sounds.
function Audio.create(def: Def, category: Category?): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = def.SoundId
	sound.Volume = def.Volume or 0.5
	sound.Looped = def.Looped or false
	if def.PlaybackSpeed then
		sound.PlaybackSpeed = def.PlaybackSpeed
	end
	if def.RollOffMaxDistance then
		sound.RollOffMaxDistance = def.RollOffMaxDistance
	end
	sound.SoundGroup = groups[category or "SFX"]
	return sound
end

-- Fire-and-forget one-shot: create + parent + play, then clean up when it finishes. Parent to a
-- BasePart for positional 3D audio, or omit for a 2D sound under SoundService.
function Audio.play(def: Def, parent: Instance?, category: Category?): Sound
	local sound = Audio.create(def, category)
	sound.Parent = parent or SoundService
	sound:Play()
	if not sound.Looped then
		sound.Ended:Once(function()
			sound:Destroy()
		end)
		Debris:AddItem(sound, ONESHOT_SAFETY)
	end
	return sound
end

return Audio
