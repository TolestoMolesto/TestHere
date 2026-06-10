--!strict
-- Central collision-group registration. Players and shadows each get their own group so a shadow
-- can pass straight through player characters -- it's invisible to everyone but its owner (see
-- ShadowVisibilityController), so nobody should bump a body they can't see -- while still resting on
-- the world. Every other pairing stays at the default (collidable), so player/world and
-- player/player collision are unchanged. (Ragdoll registers its own "Ragdoll" group separately.)

local PhysicsService = game:GetService("PhysicsService")

local CollisionGroups = {}

CollisionGroups.Player = "Player"
CollisionGroups.Shadow = "Shadow"

-- pcall-guarded (mirrors Ragdoll) so a registration hiccup can't brick spawning; `ready` gates assign().
local ready = pcall(function()
	for _, name in { CollisionGroups.Player, CollisionGroups.Shadow } do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(CollisionGroups.Shadow, CollisionGroups.Player, false)
	PhysicsService:CollisionGroupSetCollidable(CollisionGroups.Shadow, CollisionGroups.Shadow, false)
end)

-- Put every BasePart of `model` into `group`. Idempotent; safe to call on each (re)spawn.
function CollisionGroups.assign(model: Model, group: string): ()
	if not ready then
		return
	end
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.CollisionGroup = group
		end
	end
end

return CollisionGroups
