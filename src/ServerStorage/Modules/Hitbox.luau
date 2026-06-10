--!strict
local Workspace = game:GetService("Workspace")

local Hitbox = {}

-- Min dot(defender facing, direction-to-attacker) for a hit to count as blocked = cos(arc/2).
-- Lower BLOCK_ARC_DEGREES for a tighter guard that's easier to flank.
local BLOCK_ARC_DEGREES = 180
Hitbox.BLOCK_ARC_DOT = math.cos(math.rad(BLOCK_ARC_DEGREES / 2))

local function isEntityCharacter(model: Instance?): boolean
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function overlapParams(excludeDescendantsOf: { Instance }): OverlapParams
	local params = OverlapParams.new()
	params.FilterDescendantsInstances = excludeDescendantsOf
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.CollisionGroup = "Default"
	return params
end

local function collectEntities(parts: { BasePart }): { Model }
	local targets: { Model } = {}

	for _, part in parts do
		local characterFound = part:FindFirstAncestorOfClass("Model")

		if not isEntityCharacter(characterFound) then
			continue
		end

		-- Forcefield (spawn protection / intangibility): untargetable by EVERY scan-based attack
		-- (melee, skills, beams, AoE) from one place.
		if (characterFound :: Model):GetAttribute("Forcefield") then
			continue
		end

		local carriedBy = (characterFound :: Model):GetAttribute("CarriedBy")

		-- Skip grabbed characters (CarriedBy set and not "NA") and anyone already collected.
		if table.find(targets, characterFound :: Model) or (carriedBy ~= nil and carriedBy ~= "NA") then
			continue
		end

		table.insert(targets, characterFound :: Model)
	end

	return targets
end

function Hitbox.scanBox(region: CFrame, size: Vector3, excludeDescendantsOf: { Instance }): { Model }
	return collectEntities(Workspace:GetPartBoundsInBox(region, size, overlapParams(excludeDescendantsOf)))
end

function Hitbox.scanRadius(position: Vector3, radius: number, excludeDescendantsOf: { Instance }): { Model }
	return collectEntities(Workspace:GetPartBoundsInRadius(position, radius, overlapParams(excludeDescendantsOf)))
end

function Hitbox.isInFront(defender: Model, sourcePosition: Vector3, minDot: number?): boolean
	local root = defender:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end

	local from = root.Position
	local toSource = Vector3.new(sourcePosition.X - from.X, 0, sourcePosition.Z - from.Z)
	if toSource.Magnitude < 0.05 then
		return true -- on top of each other; treat as a frontal hit
	end

	local facing = root.CFrame.LookVector
	local facingFlat = Vector3.new(facing.X, 0, facing.Z)
	if facingFlat.Magnitude < 0.05 then
		return true -- looking straight up/down; nothing sensible to compare against
	end

	return facingFlat.Unit:Dot(toSource.Unit) >= (minDot or Hitbox.BLOCK_ARC_DOT)
end

return Hitbox
