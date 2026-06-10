--!strict
-- NOTE: emitters are collapsed onto a single HRP attachment; the old per-limb /
-- floor-ring placement isn't reproduced. To restore it, map named sub-attachments
-- to limbs in build().

local ServerStorage = game:GetService("ServerStorage")

local function resolveVFX(name: string): Instance?
	return ServerStorage.Assets.VFX:FindFirstChild(name)
end
local CHARGE_VFX_TEMPLATE: Instance? = resolveVFX("ChargeVFX")

local AURA_ATTACHMENT_NAME = "ChargeFX"
local DEFAULT_KI_COLOUR = Color3.fromRGB(255, 255, 255)

local function isUntinted(name: string): boolean
	local lower = name:lower()
	return lower:find("floor") ~= nil or lower:find("speed") ~= nil
end

local function getKiColour(character: Model): Color3
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local appearance = humanoid and humanoid:FindFirstChild("Appearance")
	if appearance then
		local r = appearance:GetAttribute("KiColorR") :: number?
		local g = appearance:GetAttribute("KiColorG") :: number?
		local b = appearance:GetAttribute("KiColorB") :: number?
		if r and g and b and r >= 0 and g >= 0 and b >= 0 then
			return Color3.fromRGB(r, g, b)
		end
	end
	return DEFAULT_KI_COLOUR
end

local function build(character: Model, colour: Color3): Attachment?
	if not CHARGE_VFX_TEMPLATE then
		return nil
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return nil
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = AURA_ATTACHMENT_NAME

	local sequence = ColorSequence.new(colour)
	for _, descendant in CHARGE_VFX_TEMPLATE:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			local clone = descendant:Clone()
			if not isUntinted(clone.Name) then
				clone.Color = sequence
			end
			clone.Enabled = true
			clone.Parent = attachment
		elseif descendant:IsA("PointLight") then
			local clone = descendant:Clone()
			clone.Color = colour
			clone.Enabled = true
			clone.Parent = attachment
		end
	end

	attachment.Parent = hrp
	return attachment
end

local ChargeFX = {}

function ChargeFX.bind(character: Model): () -> ()
	if not CHARGE_VFX_TEMPLATE then
		return function() end
	end

	local connections: { RBXScriptConnection } = {}
	local aura: Attachment? = nil

	local function clear()
		if aura then
			aura:Destroy()
			aura = nil
		end
	end

	local function onChange()
		if character:GetAttribute("Charging") then
			if aura then
				return
			end
			aura = build(character, getKiColour(character))
		else
			clear()
		end
	end

	table.insert(connections, character:GetAttributeChangedSignal("Charging"):Connect(onChange))
	if character:GetAttribute("Charging") then
		onChange()
	end

	return function()
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
		clear()
	end
end

return ChargeFX
