--!strict
-- A shadow is a private sparring partner: only the player who summoned it may see it. Every shadow
-- replicates server-side into Workspace.Shadows named "<Owner>_Shadow" (see ShadowSpawner). On each
-- client we fully hide any shadow that isn't ours -- body, decals, emitters, and the name/health bar
-- -- using LocalTransparencyModifier and other client-only properties that never replicate back, so
-- to everyone else the shadow simply isn't there. The owner's own client leaves its shadow untouched.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Entities = require(ReplicatedStorage.Modules.Entities)

local localPlayer = Players.LocalPlayer :: Player

local function hideInstance(inst: Instance): ()
	if inst:IsA("BasePart") then
		inst.LocalTransparencyModifier = 1
	elseif inst:IsA("Decal") or inst:IsA("Texture") then
		(inst :: Decal).Transparency = 1 -- Texture <: Decal, so both share .Transparency
	elseif inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") then
		(inst :: any).Enabled = false
	elseif inst:IsA("Humanoid") then
		inst.NameDisplayDistance = 0
		inst.HealthDisplayDistance = 0
	end
end

local conns: { [Instance]: RBXScriptConnection } = {}

local function onShadowAdded(shadow: Instance): ()
	if not shadow:IsA("Model") then
		return
	end
	-- Mirrors ShadowSpawner's "<Owner>_Shadow" naming; non-shadow models won't match and are ignored.
	local ownerName = shadow.Name:match("^(.-)_Shadow$")
	if not ownerName or ownerName == localPlayer.Name then
		return -- not a shadow, or it's ours: leave it visible
	end

	for _, desc in shadow:GetDescendants() do
		hideInstance(desc)
	end
	-- Parts/decals/FX can stream in a frame or two after the Model first replicates.
	conns[shadow] = shadow.DescendantAdded:Connect(hideInstance)
end

local function onShadowRemoved(shadow: Instance): ()
	local conn = conns[shadow]
	if conn then
		conn:Disconnect()
		conns[shadow] = nil
	end
end

local function watchFolder(folder: Instance): ()
	for _, child in folder:GetChildren() do
		onShadowAdded(child)
	end
	folder.ChildAdded:Connect(onShadowAdded)
	folder.ChildRemoved:Connect(onShadowRemoved)
end

-- The Shadows folder is created at server boot, so it's usually already here; fall back to waiting
-- for it in case this script runs before it replicates.
local existing = Workspace:FindFirstChild(Entities.Folder.Shadow)
if existing then
	watchFolder(existing)
else
	Workspace.ChildAdded:Connect(function(child: Instance): ()
		if child.Name == Entities.Folder.Shadow and child:IsA("Folder") then
			watchFolder(child)
		end
	end)
end
