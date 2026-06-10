--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local NEAR_GROUND_DISTANCE = 10

local GroundDetectionHandler = {}

function GroundDetectionHandler.NearGroundDetection(character: Model, enemyCharacter: Model): boolean?
	if character:FindFirstChild("ShadowScript") ~= nil or enemyCharacter:FindFirstChild("ShadowScript") ~= nil then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { character, enemyCharacter }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local result = Workspace:Raycast(root.Position, root.CFrame.UpVector * -NEAR_GROUND_DISTANCE, params)
	if not result then
		return false
	end

	if result.Instance.Name == "Terrain" then
		-- Fire the optional place-side water-ripple remote, if the Events folder exists.
		local events = ReplicatedStorage:FindFirstChild("Events")
		local ripple = events and events:FindFirstChild("WaterRipple")
		if ripple and ripple:IsA("RemoteEvent") then
			ripple:FireAllClients(result.Position)
		end
		return nil
	end

	-- Near solid ground: hook for ground-impact FX (pebbles, etc.).
	return true
end

return GroundDetectionHandler
