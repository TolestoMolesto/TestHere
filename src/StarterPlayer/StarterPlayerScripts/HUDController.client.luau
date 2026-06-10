--!strict
-- Resource HUD: three stacked bars (Health, Ki, Stamina) at the top-left, each showing a fill and a
-- "current / max" readout. Health is read from the Humanoid; Ki and Stamina are character attributes
-- written by StatsManager and updated live by the combat systems -- all replicate to the client, so
-- this is a pure view with no remotes. Rebinds on respawn and follows MaxHealth/MaxKi/MaxStamina so
-- transformations rescale the bars correctly.

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TEXT_COLOR = Color3.fromRGB(238, 240, 245)
local TRACK_BG = Color3.fromRGB(16, 17, 22)
local OUTLINE = Color3.fromRGB(0, 0, 0)
local HEALTH_COLOR = Color3.fromRGB(86, 196, 102)
local KI_COLOR = Color3.fromRGB(74, 158, 255)
local STAMINA_COLOR = Color3.fromRGB(255, 184, 48)

-- Inline builders (no helper module, per project UI conventions) ---------------------------------

local function corner(object: Instance, scale: number): ()
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = object
end

local function border(object: Instance, thickness: number, color: Color3, transparency: number): ()
	local s = Instance.new("UIStroke")
	s.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Thickness = thickness
	s.Color = color
	s.Transparency = transparency
	s.Parent = object
end

local function makeLabel(parent: Instance, posX: number, sizeX: number, align: Enum.TextXAlignment): TextLabel
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(posX, 0.5)
	label.Size = UDim2.fromScale(sizeX, 0.62)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = ""
	label.TextColor3 = TEXT_COLOR
	label.TextScaled = true
	label.TextXAlignment = align
	-- Thin glyph outline (Contextual) so the readout stays legible over the filled and empty parts of
	-- the bar alike; kept hairline-thin to avoid the blobby look thick strokes give text.
	local s = Instance.new("UIStroke")
	s.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	s.Thickness = 0.03
	s.Color = OUTLINE
	s.Transparency = 0.2
	s.Parent = label
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 8
	constraint.MaxTextSize = 18
	constraint.Parent = label
	label.Parent = parent
	return label
end

-- Shell -----------------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ResourceHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 8
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "Bars"
container.AnchorPoint = Vector2.new(0.5, 0.5)
container.Position = UDim2.fromScale(0.17, 0.12)
container.Size = UDim2.fromScale(0.3, 0.185)
container.BackgroundTransparency = 1
container.Visible = false
container.Parent = screenGui

type Bar = { fill: Frame, value: TextLabel }

local function makeBar(name: string, color: Color3, posY: number): Bar
	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.Position = UDim2.fromScale(0.5, posY)
	track.Size = UDim2.fromScale(1, 0.2)
	track.BackgroundColor3 = TRACK_BG
	track.BackgroundTransparency = 0.15
	corner(track, 0.5)
	border(track, 0.02, OUTLINE, 0.4)
	track.Parent = container

	-- Centre-anchored fill: left edge pinned at 0, right edge tracks the ratio (same trick as the
	-- settings sliders, so Scale sizing keeps the AnchorPoint at 0.5/0.5).
	local fill = Instance.new("Frame")
	fill.AnchorPoint = Vector2.new(0.5, 0.5)
	fill.Position = UDim2.fromScale(0, 0.5)
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = color
	corner(fill, 0.5)
	fill.Parent = track

	local nameLabel = makeLabel(track, 0.26, 0.46, Enum.TextXAlignment.Left)
	nameLabel.Text = name

	local value = makeLabel(track, 0.74, 0.46, Enum.TextXAlignment.Right)

	return { fill = fill, value = value }
end

local healthBar = makeBar("Health", HEALTH_COLOR, 0.13)
local kiBar = makeBar("Ki", KI_COLOR, 0.37)
local staminaBar = makeBar("Stamina", STAMINA_COLOR, 0.61)

-- Plain number readouts (no bar) beneath the resource bars.
local infoRow = Instance.new("Frame")
infoRow.AnchorPoint = Vector2.new(0.5, 0.5)
infoRow.Position = UDim2.fromScale(0.5, 0.85)
infoRow.Size = UDim2.fromScale(1, 0.2)
infoRow.BackgroundTransparency = 1
infoRow.Parent = container

local livesLabel = makeLabel(infoRow, 0.26, 0.46, Enum.TextXAlignment.Left)
local longevityLabel = makeLabel(infoRow, 0.74, 0.46, Enum.TextXAlignment.Right)

local function setBar(bar: Bar, current: number, max: number): ()
	local ratio = if max > 0 then math.clamp(current / max, 0, 1) else 0
	bar.fill.Position = UDim2.fromScale(ratio / 2, 0.5)
	bar.fill.Size = UDim2.fromScale(ratio, 1)
	bar.value.Text = string.format("%d / %d", math.floor(current + 0.5), math.floor(max + 0.5))
end

-- Binding ---------------------------------------------------------------------------------------

local connections: { RBXScriptConnection } = {}

local function clearConnections(): ()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
end

local function bind(character: Model): ()
	clearConnections()
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	local function refreshHealth(): ()
		setBar(healthBar, humanoid.Health, humanoid.MaxHealth)
	end
	local function refreshKi(): ()
		setBar(kiBar, (character:GetAttribute("Ki") :: number?) or 0, (character:GetAttribute("MaxKi") :: number?) or 0)
	end
	local function refreshStamina(): ()
		setBar(
			staminaBar,
			(character:GetAttribute("Stamina") :: number?) or 0,
			(character:GetAttribute("MaxStamina") :: number?) or 0
		)
	end

	-- HealthChanged covers current HP; MaxHealth/MaxKi/MaxStamina move on transform, so watch them too.
	table.insert(connections, humanoid.HealthChanged:Connect(refreshHealth))
	table.insert(connections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refreshHealth))
	table.insert(connections, character:GetAttributeChangedSignal("Ki"):Connect(refreshKi))
	table.insert(connections, character:GetAttributeChangedSignal("MaxKi"):Connect(refreshKi))
	table.insert(connections, character:GetAttributeChangedSignal("Stamina"):Connect(refreshStamina))
	table.insert(connections, character:GetAttributeChangedSignal("MaxStamina"):Connect(refreshStamina))

	refreshHealth()
	refreshKi()
	refreshStamina()
	container.Visible = true

	-- Lives/Longevity are plain numbers on Humanoid.Stats (written by StatsManager). Read them once the
	-- folder has replicated; never block the bars on it. The guard drops a stale bind after a respawn.
	local stats = humanoid:WaitForChild("Stats", 5)
	if stats and character == player.Character then
		local function refreshNumbers(): ()
			livesLabel.Text = "Lives: " .. tostring((stats:GetAttribute("Lives") :: number?) or 0)
			-- Longevity carries fractional drain from training; show a clean integer.
			longevityLabel.Text = "Longevity: "
				.. tostring(math.floor((stats:GetAttribute("Longevity") :: number?) or 0))
		end
		table.insert(connections, stats:GetAttributeChangedSignal("Lives"):Connect(refreshNumbers))
		table.insert(connections, stats:GetAttributeChangedSignal("Longevity"):Connect(refreshNumbers))
		refreshNumbers()
	end
end

if player.Character then
	bind(player.Character)
end
player.CharacterAdded:Connect(bind)
