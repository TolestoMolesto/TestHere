--!strict
-- Renders the hit/block sparks for THIS player's shadow. A shadow is invisible to everyone else, so
-- the server (HitFX) doesn't spawn its FX into the world -- it sends them here, to the owner alone,
-- and we burst them locally. Templates are mirrored into ReplicatedStorage.Assets.VFX by HitFX at
-- load, so no manual asset placement is needed; if one isn't there yet we simply skip that burst.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FXBurst = require(ReplicatedStorage.Modules.FXBurst)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local vfxFolder: Instance? = nil
local function getVFX(): Instance?
	if vfxFolder and vfxFolder.Parent then
		return vfxFolder
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	vfxFolder = (assets and assets:FindFirstChild("VFX")) or nil
	return vfxFolder
end

Remotes.ShadowFX.OnClientEvent:Connect(
	function(
		templateName: string,
		position: Vector3,
		duration: number,
		defaultEmit: number,
		emitCounts: { [string]: number }?
	)
		local folder = getVFX()
		if not folder then
			return
		end
		local template = folder:FindFirstChild(templateName)
		if template then
			FXBurst.burst(position, template, duration, defaultEmit, emitCounts)
		end
	end
)
