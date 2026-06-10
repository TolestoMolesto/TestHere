--!strict
-- Aura VFX for active abilities. Mirrors ChargeFX: binds to the active-ability attributes
-- (ActiveForm + ActiveTechnique) and builds one aura attachment per bucket from the ability's
-- template under ServerStorage.Assets.VFX, tinted by KiColor. A Form and a Technique can show
-- their auras at the same time (SSJ + Kaioken). No-ops gracefully if a template is missing
-- (combat FX live in the .rbxl place and are cosmetic-only).

local ServerStorage = game:GetService("ServerStorage")

local FormConfig = require(ServerStorage.Modules.FormConfig)

local DEFAULT_KI_COLOUR = Color3.fromRGB(255, 255, 255)
local ACTIVE_ATTRS = { "ActiveForm", "ActiveTechnique" }

local function vfxTemplate(name: string): Instance?
	local assets = ServerStorage:FindFirstChild("Assets")
	local vfx = assets and assets:FindFirstChild("VFX")
	return vfx and vfx:FindFirstChild(name)
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

local function build(character: Model, template: Instance, colour: Color3, attachmentName: string): Attachment?
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return nil
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = attachmentName

	local sequence = ColorSequence.new(colour)
	for _, descendant in template:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			local clone = descendant:Clone()
			clone.Color = sequence
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

local FormFX = {}

function FormFX.bind(character: Model): () -> ()
	local connections: { RBXScriptConnection } = {}
	local auras: { [string]: Attachment } = {}

	local function clear(attr: string)
		local existing = auras[attr]
		if existing then
			existing:Destroy()
			auras[attr] = nil
		end
	end

	local function refresh(attr: string)
		clear(attr)
		local name = character:GetAttribute(attr)
		if type(name) ~= "string" or name == "" then
			return
		end
		local def = FormConfig.get(name)
		if not def then
			return
		end
		local template = vfxTemplate(def.auraTemplate)
		if not template then
			return
		end
		local aura = build(character, template, getKiColour(character), `FormFX_{attr}`)
		if aura then
			auras[attr] = aura
		end
	end

	for _, attr in ACTIVE_ATTRS do
		table.insert(
			connections,
			character:GetAttributeChangedSignal(attr):Connect(function()
				refresh(attr)
			end)
		)
		if character:GetAttribute(attr) then
			refresh(attr)
		end
	end

	return function()
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
		for _, attr in ACTIVE_ATTRS do
			clear(attr)
		end
	end
end

return FormFX
