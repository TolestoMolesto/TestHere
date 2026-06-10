--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local FXBurst = require(ReplicatedStorage.Modules.FXBurst)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local function resolveVFX(name: string): Instance?
	return ServerStorage.Assets.VFX:FindFirstChild(name)
end

local FX_DURATION = 1.5
local BLOCK_FX_DURATION = 1.0

type FXKind = {
	templateName: string,
	template: Instance?,
	duration: number,
	defaultEmit: number,
}

local KIND: { [string]: FXKind } = {
	Hit = {
		templateName = "HitFXTemplate",
		template = resolveVFX("HitFXTemplate"),
		duration = FX_DURATION,
		defaultEmit = 1,
	},
	Block = {
		templateName = "ParryFXTemplate",
		template = resolveVFX("ParryFXTemplate"),
		duration = BLOCK_FX_DURATION,
		defaultEmit = 3,
	},
}

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- The client renders owner-only shadow FX from ReplicatedStorage (it can't see ServerStorage), so
-- mirror the templates it needs there once at load. No-op for any already copied or missing.
local function ensureReplicatedTemplates(): ()
	local vfx = ensureFolder(ensureFolder(ReplicatedStorage, "Assets"), "VFX")
	for _, cfg in KIND do
		if cfg.template and not vfx:FindFirstChild(cfg.templateName) then
			local clone = cfg.template:Clone()
			clone.Name = cfg.templateName
			clone.Parent = vfx
		end
	end
end
ensureReplicatedTemplates()

local function resolvePosition(character: Model, hitPosition: Vector3?): Vector3?
	if hitPosition then
		return hitPosition
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return hrp and hrp.Position
end

-- A shadow is invisible to everyone but its owner (ShadowVisibilityController), so its hit sparks
-- must not spawn for the whole server. Returns the owner to render them privately, else nil (public).
local function privateViewer(character: Model): Player?
	if not character:GetAttribute("IsShadow") then
		return nil
	end
	local ownerName = character.Name:match("^(.-)_Shadow$")
	if not ownerName then
		return nil
	end
	return Players:FindFirstChild(ownerName) :: Player?
end

local function play(character: Model, kind: string, position: Vector3, emitCounts: { [string]: number }?): ()
	local cfg = KIND[kind]
	local viewer = privateViewer(character)
	if viewer then
		Remotes.ShadowFX:FireClient(viewer, cfg.templateName, position, cfg.duration, cfg.defaultEmit, emitCounts)
		return
	end
	if cfg.template then
		FXBurst.burst(position, cfg.template, cfg.duration, cfg.defaultEmit, emitCounts)
	end
end

local HitFX = {}

function HitFX.spawnOnCharacter(character: Model, hitPosition: Vector3?): ()
	local position = resolvePosition(character, hitPosition)
	if position then
		play(character, "Hit", position, nil)
	end
end

function HitFX.spawnBlockFX(character: Model, hitPosition: Vector3?): ()
	local position = resolvePosition(character, hitPosition)
	if position then
		play(character, "Block", position, nil)
	end
end

function HitFX.spawnOnCharacterCustom(character: Model, hitPosition: Vector3?, emitCounts: { [string]: number }): ()
	local position = resolvePosition(character, hitPosition)
	if position then
		play(character, "Hit", position, emitCounts)
	end
end

return HitFX
