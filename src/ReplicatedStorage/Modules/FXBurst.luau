--!strict
-- Generic one-shot particle burst: drop a transient Attachment at `position`, clone every
-- ParticleEmitter out of `template` onto it, :Emit, and clean up after `duration`. `emitCounts` maps
-- a (case-insensitive) substring of an emitter's name to its emit count, else `defaultEmit`.
--
-- Shared so the same burst renders identically whether the server spawns it publicly (HitFX) or a
-- single client spawns it for an owner-only shadow hit (ShadowFXController).

local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local FXBurst = {}

function FXBurst.burst(
	position: Vector3,
	template: Instance,
	duration: number,
	defaultEmit: number,
	emitCounts: { [string]: number }?
): ()
	local attachment = Instance.new("Attachment")
	attachment.Name = "HitFXAttachment"
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain

	for _, emitter in template:GetChildren() do
		if not emitter:IsA("ParticleEmitter") then
			continue
		end

		local clone = emitter:Clone()
		clone.Parent = attachment

		local count = defaultEmit
		if emitCounts then
			for pattern, n in emitCounts do
				if clone.Name:lower():find(pattern:lower()) then
					count = n
					break
				end
			end
		end

		clone:Emit(count)
	end

	Debris:AddItem(attachment, duration)
end

return FXBurst
