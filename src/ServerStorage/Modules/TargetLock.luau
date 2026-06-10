--!strict
local TargetLock = {}

-- Must match the client LockOn leash, so server and client agree when a lock is lost.
local MAX_RANGE = 1000

local VALUE_NAME = "LockOnTarget"

local function isTargetable(target: Model, byCharacter: Model): boolean
	if target == byCharacter then
		return false
	end
	-- Spawn-protected (Forcefield) targets can't be locked onto, so homing ki + vanish can't acquire
	-- them either (both resolve through TargetLock).
	if target:GetAttribute("Forcefield") then
		return false
	end
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	local root = target:FindFirstChild("HumanoidRootPart")
	return humanoid ~= nil and root ~= nil and humanoid.Health > 0
end

local function targetValue(character: Model): ObjectValue
	local existing = character:FindFirstChild(VALUE_NAME)
	if existing and existing:IsA("ObjectValue") then
		return existing
	end
	local value = Instance.new("ObjectValue")
	value.Name = VALUE_NAME
	value.Parent = character
	return value
end

function TargetLock.clear(character: Model): ()
	character:SetAttribute("LockedOn", false)
	local value = character:FindFirstChild(VALUE_NAME)
	if value and value:IsA("ObjectValue") then
		value.Value = nil
	end
end

-- `target` is untrusted (it comes straight off a remote), so validate every shape here.
function TargetLock.set(character: Model, target: Instance?): boolean
	if typeof(target) ~= "Instance" or not target:IsA("Model") then
		TargetLock.clear(character)
		return false
	end
	if not isTargetable(target, character) then
		TargetLock.clear(character)
		return false
	end
	local fromRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local toRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not fromRoot or not toRoot then
		TargetLock.clear(character)
		return false
	end
	if (fromRoot.Position - toRoot.Position).Magnitude > MAX_RANGE then
		TargetLock.clear(character)
		return false
	end

	targetValue(character).Value = target
	character:SetAttribute("LockedOn", true)
	return true
end

function TargetLock.get(character: Model): Model?
	if not character:GetAttribute("LockedOn") then
		return nil
	end
	local value = character:FindFirstChild(VALUE_NAME)
	if value and value:IsA("ObjectValue") then
		local target = value.Value
		if target and target:IsA("Model") and isTargetable(target, character) then
			return target
		end
	end
	TargetLock.clear(character)
	return nil
end

return TargetLock
