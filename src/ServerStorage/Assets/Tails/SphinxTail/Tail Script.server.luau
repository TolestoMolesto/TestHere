-- Server Script inside the Tail model
local Players = game:GetService("Players")

local AC = script.Parent:WaitForChild("AnimationController")
local char = script.Parent.Parent
local humanoid = char:WaitForChild("Humanoid")

-- ✅ Set Tail Color
local function applyColor()
	local appearance = humanoid:WaitForChild("Appearance", 5)

	local color
	if appearance then
		local r = appearance:GetAttribute("BodyColorR")
		local g = appearance:GetAttribute("BodyColorG")
		local b = appearance:GetAttribute("BodyColorB")
		if r and g and b then
			color = Color3.fromRGB(r, g, b)
		end
	end

	if not color then
		warn("[Tail] Appearance folder not found, falling back to Head color")
		color = char.Head.Color
	end

	for _, piece in script.Parent:GetChildren() do
		if piece:IsA("MeshPart") then
			piece.Color = color
		end
	end
end

applyColor()

-- ✅ Play Wag animation server-side
local WagAnim = AC:LoadAnimation(script:WaitForChild("Wag"))
WagAnim:Play()