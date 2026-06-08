--!strict

-- Hitbox
-- Handles creation and scanning of combat hitboxes.
-- All active hitboxes are parented to Workspace.Ignore.Hitboxes so they
-- don't interfere with normal gameplay collision groups.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ServerStorage.Modules.Types)

-- Template parts cloned whenever a new hitbox is needed.
-- Keeping them as children of the script makes them easy to tweak in Studio.
local HITBOX = script:WaitForChild("Hitbox") :: Part
local CYLINDRICAL_HITBOX = script:WaitForChild("CylindricalHitbox") :: MeshPart
local PARRY_HITBOX = script:WaitForChild("ParryHitbox") :: Part

-- Folder in Workspace where all spawned hitboxes live.
local DIRECTORY = Workspace.Ignore.Hitboxes :: Folder

-- Template BindableEvent cloned per-hitbox so each one gets its own signal.
local ENTITY_HIT_EVENT = script:WaitForChild("EntityHit") :: BindableEvent

local Hitbox = {}

type Options = {
	Shape: Enum.PartType?, -- Cylinder uses CYLINDRICAL_HITBOX; anything else uses the default box HITBOX
}

-- Returns true if the given model is a valid entity (has a Humanoid).
local function isEntityCharacter(model: Model?): boolean
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

-- Scans the volume of an existing hitbox part and returns all entity characters
-- found inside it, excluding any models listed in excludeDescendantsOf.
-- Also skips characters that are currently being carried by another entity
-- (CarriedBy attribute is set and isn't "NA").
function Hitbox.processHitscan(hitbox: BasePart, excludeDescendantsOf: { Instance }): { Types.EntityCharacter }
	local overlapParameters = OverlapParams.new()
	overlapParameters.FilterDescendantsInstances = excludeDescendantsOf
	overlapParameters.FilterType = Enum.RaycastFilterType.Exclude
	overlapParameters.CollisionGroup = "Default"

	local targets: { Types.EntityCharacter } = {}

	for _, part in Workspace:GetPartBoundsInBox(hitbox.CFrame, hitbox.Size, overlapParameters) do
		-- Walk up to the top-level character Model from whatever part was hit.
		local characterFound = part:FindFirstAncestorOfClass("Model")

		if not isEntityCharacter(characterFound) then
			continue
		end

		local carriedBy = characterFound:GetAttribute("CarriedBy")

		-- Skip duplicates and characters that are mid-carry (can't be hit while grabbed).
		if table.find(targets, characterFound :: Types.EntityCharacter) or (carriedBy ~= nil and carriedBy ~= "NA") then
			continue
		end

		table.insert(targets, characterFound :: Types.EntityCharacter)
	end

	return targets
end

-- Spawns a hitbox part in the world at the given position and size.
-- invoker is the attacking character Model (player or NPC). It is not stored on the
-- hitbox — self-exclusion is handled by passing the invoker into processHitscan's
-- excludeDescendantsOf list at the call site.
-- Pass Shape = Enum.PartType.Cylinder in options to get a cylindrical hitbox instead.
function Hitbox.create(size: Vector3, position: CFrame, invoker: Model, options: Options?): BasePart
	local realOptions = options or {} :: Options
	local templateHitbox: BasePart = if realOptions.Shape == Enum.PartType.Cylinder then CYLINDRICAL_HITBOX else HITBOX

	local hitbox = templateHitbox:Clone()
	hitbox.Name = "Hitbox"
	hitbox.Size = size
	hitbox:PivotTo(position)
	hitbox.Parent = DIRECTORY

	return hitbox
end

-- Spawns a parry hitbox at the given position.
-- invoker is the parrying character Model (player or NPC). Self-exclusion is handled
-- by the caller passing invoker into processHitscan's excludeDescendantsOf list.
-- Parry hitboxes get several extra attributes:
--   ParryId       - Unique ID built from a timestamp + random number to avoid collisions.
--   IsParryHitbox - Flag so other systems can tell this isn't a normal attack hitbox.
--   CreatedTime   - Unix timestamp (seconds) of when the parry was created, used for timing windows.
function Hitbox.createParry(position: CFrame, invoker: Model?): Part
	local hitbox = PARRY_HITBOX:Clone()
	hitbox:PivotTo(position)

	local createdAtTimestamp = DateTime.now().UnixTimestampMillis / 1_000
	hitbox:SetAttribute("ParryId", `Parry_{createdAtTimestamp}_{math.random(1, 999999)}`)
	hitbox:SetAttribute("IsParryHitbox", true)
	hitbox:SetAttribute("CreatedTime", createdAtTimestamp)
	hitbox.Parent = DIRECTORY

	return hitbox
end

-- Attaches a Touched listener to the given hitbox and returns an event that fires
-- once per unique entity character that enters the hitbox volume.
-- Deduplication is handled locally — processedEntities prevents the same
-- character from triggering the event twice even if multiple body parts touch the hitbox.
-- The internal BindableEvent (and its listener) are cleaned up automatically
-- when the hitbox part is destroyed.
function Hitbox.createEntityHitSignal(hitbox: BasePart): RBXScriptSignal
	local signal = ENTITY_HIT_EVENT:Clone()
	local processedEntities: { Types.EntityCharacter } = {}

	hitbox.Touched:Connect(function(hit: BasePart): ()
		local entityFound = hit:FindFirstAncestorOfClass("Model")

		if not isEntityCharacter(entityFound) then
			return
		end

		local entityCharacter = entityFound :: Types.EntityCharacter

		-- Each character should only register one hit per hitbox lifetime.
		if table.find(processedEntities, entityCharacter) then
			return
		end

		table.insert(processedEntities, entityCharacter)
		signal:Fire(entityCharacter)
	end)

	-- Clean up the cloned BindableEvent when the hitbox is removed from the world.
	hitbox.Destroying:Connect(function(): ()
		signal:Destroy()
	end)

	return signal.Event
end

return Hitbox
