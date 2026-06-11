--!strict
-- Settings UI: an on-screen button toggles a panel listing the player's settings. Reads with
-- Settings.get and writes with Settings.set (which validates, persists to the server, and notifies
-- the rest of the game); subscribes to Settings.onChanged so every control reflects the saved
-- values once they hydrate. SettingsBootstrap handles load + audio sync -- this file is just the
-- view. Sliders move live while dragging but only commit on release, so a drag is one server push
-- instead of one per mouse-move.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Keybinds = require(ReplicatedStorage.Modules.Keybinds)
local KeybindConfig = require(ReplicatedStorage.Modules.KeybindConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Settings = require(ReplicatedStorage.Modules.Settings)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PANEL_BG = Color3.fromRGB(26, 27, 33)
local ROW_BG = Color3.fromRGB(40, 42, 51)
local TRACK_BG = Color3.fromRGB(16, 17, 22)
local ACCENT = Color3.fromRGB(255, 176, 32)
local ON_COLOR = Color3.fromRGB(96, 200, 120)
local OFF_COLOR = Color3.fromRGB(70, 72, 82)
local TEXT_COLOR = Color3.fromRGB(238, 240, 245)
local BAD_COLOR = Color3.fromRGB(235, 110, 110)

type Row = {
	kind: string,
	section: string,
	key: string,
	label: string,
	min: number?,
	max: number?,
	step: number?,
	options: { string }?,
	display: { [string]: string }?,
}

type Section = { name: string, rows: { Row } }

local SECTIONS: { Section } = {
	{
		name = "Audio",
		rows = {
			{ kind = "slider", section = "Audio", key = "Music", label = "Music", min = 0, max = 1 },
			{ kind = "slider", section = "Audio", key = "SFX", label = "SFX", min = 0, max = 1 },
		},
	},
	{
		name = "Lock-On",
		rows = {
			{
				kind = "options",
				section = "LockOn",
				key = "Style",
				label = "Camera Style",
				options = { "Dynamic_View", "FreeCam", "FaceOff" },
				display = { Dynamic_View = "Dynamic", FreeCam = "Free Cam", FaceOff = "Face Off" },
			},
			{ kind = "slider", section = "LockOn", key = "FOV", label = "Distance", min = 1, max = 10, step = 1 },
			{
				kind = "slider",
				section = "LockOn",
				key = "Transparency",
				label = "Body Transparency",
				min = 0,
				max = 1,
			},
		},
	},
	{
		name = "Camera",
		rows = {
			{ kind = "toggle", section = "Camera", key = "Shake", label = "Camera Shake" },
		},
	},
}

-- Small inline builders (no helper module) ------------------------------------------------------

local function corner(object: Instance, scale: number): ()
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = object
end

local function stroke(object: Instance, thickness: number, color: Color3, transparency: number): ()
	local s = Instance.new("UIStroke")
	s.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	-- Border, not Contextual: Contextual strokes the text glyphs on a TextButton and looks wrong.
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Thickness = thickness
	s.Color = color
	s.Transparency = transparency
	s.Parent = object
end

local function constrainText(textObject: Instance, minSize: number, maxSize: number): ()
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = minSize
	constraint.MaxTextSize = maxSize
	constraint.Parent = textObject
end

-- Locks an element's width:height so Scale sizing can't stretch it (a round knob stays round, a
-- pill stays a pill) regardless of the screen's aspect ratio.
local function aspect(object: Instance, ratio: number): ()
	local constraint = Instance.new("UIAspectRatioConstraint")
	constraint.AspectRatio = ratio
	constraint.Parent = object
end

local function makeLabel(
	parent: Instance,
	text: string,
	posX: number,
	posY: number,
	sizeX: number,
	sizeY: number,
	align: Enum.TextXAlignment,
	maxSize: number
): TextLabel
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(posX, posY)
	label.Size = UDim2.fromScale(sizeX, sizeY)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.Text = text
	label.TextColor3 = TEXT_COLOR
	label.TextScaled = true
	label.TextXAlignment = align
	constrainText(label, 8, maxSize)
	label.Parent = parent
	return label
end

local function makeButton(
	parent: Instance,
	text: string,
	posX: number,
	posY: number,
	sizeX: number,
	sizeY: number,
	maxSize: number
): TextButton
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(posX, posY)
	button.Size = UDim2.fromScale(sizeX, sizeY)
	button.BackgroundColor3 = ROW_BG
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = TEXT_COLOR
	button.TextScaled = true
	constrainText(button, 8, maxSize)
	corner(button, 0.3)
	button.Parent = parent
	return button
end

-- Shell -----------------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SettingsUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 10
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local openButton = Instance.new("TextButton")
openButton.Name = "OpenSettings"
openButton.AnchorPoint = Vector2.new(0.5, 0.5)
openButton.Position = UDim2.fromScale(0.93, 0.07)
openButton.Size = UDim2.fromScale(0.1, 0.05)
openButton.BackgroundColor3 = PANEL_BG
openButton.AutoButtonColor = true
openButton.Font = Enum.Font.GothamBold
openButton.Text = "Settings"
openButton.TextColor3 = TEXT_COLOR
openButton.TextScaled = true
constrainText(openButton, 8, 20)
corner(openButton, 0.3)
stroke(openButton, 0.02, ACCENT, 0.2)
openButton.Parent = screenGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromScale(0.4, 0.6)
panel.BackgroundColor3 = PANEL_BG
panel.BackgroundTransparency = 0.05
panel.Visible = false
corner(panel, 0.05)
panel.Parent = screenGui

local title = makeLabel(panel, "Settings", 0.5, 0.06, 0.6, 0.07, Enum.TextXAlignment.Center, 26)
title.Font = Enum.Font.GothamBold

local closeButton = makeButton(panel, "X", 0.93, 0.06, 0.08, 0.06, 20)

-- Tab bar ---------------------------------------------------------------------------------------

local TAB_ACTIVE = ROW_BG
local TAB_INACTIVE = Color3.fromRGB(30, 31, 38)
local TEXT_DIM = Color3.fromRGB(150, 153, 165)

local tabBar = Instance.new("Frame")
tabBar.AnchorPoint = Vector2.new(0.5, 0.5)
tabBar.Position = UDim2.fromScale(0.5, 0.155)
tabBar.Size = UDim2.fromScale(0.86, 0.08)
tabBar.BackgroundTransparency = 1
tabBar.Parent = panel

local generalTab = makeButton(tabBar, "General", 0.255, 0.5, 0.49, 1, 18)
local hotkeysTab = makeButton(tabBar, "Hotkeys", 0.745, 0.5, 0.49, 1, 18)

local scroller = Instance.new("ScrollingFrame")
scroller.Name = "List"
scroller.AnchorPoint = Vector2.new(0.5, 0.5)
scroller.Position = UDim2.fromScale(0.5, 0.6)
scroller.Size = UDim2.fromScale(0.92, 0.66)
scroller.BackgroundTransparency = 1
scroller.BorderSizePixel = 0
scroller.ScrollBarThickness = 6
scroller.ScrollBarImageColor3 = ACCENT
scroller.AutomaticCanvasSize = Enum.AutomaticSize.XY
scroller.CanvasSize = UDim2.new(0, 0, 0, 0)
scroller.Parent = panel

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Top
layout.Parent = scroller

-- Rows ------------------------------------------------------------------------------------------

local refreshers: { [string]: (any) -> () } = {}
local order = 0

local function nextOrder(): number
	order += 1
	return order
end

local function makeRowFrame(height: number): Frame
	local row = Instance.new("Frame")
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Size = UDim2.fromScale(0.96, height)
	row.BackgroundTransparency = 1
	row.LayoutOrder = nextOrder()
	row.Parent = scroller
	return row
end

local function makeHeader(name: string): ()
	local row = makeRowFrame(0.09)
	local label = makeLabel(row, name, 0.5, 0.5, 0.96, 0.7, Enum.TextXAlignment.Left, 18)
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = ACCENT
end

-- A transparent outer row holding an inset card; the inset (Scale, not padding) is what makes the
-- visual gap between rows. Returns the card so the control can be parented into it.
local function controlRow(row: Row): Frame
	local outer = makeRowFrame(0.15)
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(1, 0.82)
	card.BackgroundColor3 = ROW_BG
	card.BackgroundTransparency = 0.35
	corner(card, 0.28)
	card.Parent = outer
	makeLabel(card, row.label, 0.25, 0.5, 0.42, 0.6, Enum.TextXAlignment.Left, 16)
	return card
end

local function buildSlider(row: Row): ()
	local card = controlRow(row)
	local minV = row.min or 0
	local maxV = row.max or 1
	local step = row.step

	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.Position = UDim2.fromScale(0.65, 0.5)
	track.Size = UDim2.fromScale(0.38, 0.16)
	track.BackgroundColor3 = TRACK_BG
	corner(track, 0.5)
	track.Parent = card

	-- Centre-anchored fill: left edge pinned at 0, right edge tracks the ratio.
	local fill = Instance.new("Frame")
	fill.AnchorPoint = Vector2.new(0.5, 0.5)
	fill.Position = UDim2.fromScale(0, 0.5)
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = ACCENT
	corner(fill, 0.5)
	fill.Parent = track

	local handle = Instance.new("Frame")
	handle.AnchorPoint = Vector2.new(0.5, 0.5)
	handle.Position = UDim2.fromScale(0, 0.5)
	handle.Size = UDim2.fromScale(0.045, 1.7)
	handle.BackgroundColor3 = TEXT_COLOR
	corner(handle, 0.5)
	handle.Parent = track

	local valueLabel = makeLabel(card, "", 0.93, 0.5, 0.12, 0.6, Enum.TextXAlignment.Right, 14)

	-- Transparent catcher over the track (taller for an easier grab) so input lands reliably.
	local catcher = Instance.new("ImageButton")
	catcher.AnchorPoint = Vector2.new(0.5, 0.5)
	catcher.Position = UDim2.fromScale(0.5, 0.5)
	catcher.Size = UDim2.fromScale(1, 3)
	catcher.BackgroundTransparency = 1
	catcher.Image = ""
	catcher.ScaleType = Enum.ScaleType.Fit
	catcher.Parent = track

	local function applyVisual(num: number): ()
		local ratio = math.clamp((num - minV) / (maxV - minV), 0, 1)
		fill.Position = UDim2.fromScale(ratio / 2, 0.5)
		fill.Size = UDim2.fromScale(ratio, 1)
		handle.Position = UDim2.fromScale(ratio, 0.5)
		if step then
			valueLabel.Text = tostring(math.floor(num + 0.5))
		else
			valueLabel.Text = tostring(math.floor(num * 100 + 0.5)) .. "%"
		end
	end

	local function valueFromX(px: number): number
		local ratio = math.clamp((px - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		local v = minV + ratio * (maxV - minV)
		if step then
			v = math.floor((v - minV) / step + 0.5) * step + minV
		end
		return v
	end

	local dragging = false
	local lastSent: number? = nil

	-- Live: apply the visual and push the value as the handle moves (Settings.set drives the audio /
	-- camera in real time). Skip the push when the value hasn't moved so a held drag isn't remote spam.
	local function commit(px: number): ()
		local v = valueFromX(px)
		applyVisual(v)
		if v ~= lastSent then
			lastSent = v
			Settings.set(row.section, row.key, v)
		end
	end

	catcher.InputBegan:Connect(function(input: InputObject): ()
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			commit(input.Position.X)
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject): ()
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			commit(input.Position.X)
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject): ()
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)

	refreshers[row.section .. "." .. row.key] = function(value: any): ()
		if not dragging then
			applyVisual(if typeof(value) == "number" then value else minV)
		end
	end
	applyVisual(Settings.get(row.section, row.key))
end

local function buildOptions(row: Row): ()
	local card = controlRow(row)
	local options: { string } = row.options or {}
	local display: { [string]: string } = row.display or {}

	local valueLabel = makeLabel(card, "", 0.75, 0.5, 0.28, 0.6, Enum.TextXAlignment.Center, 16)

	local function indexOf(value: any): number
		for i, opt in options do
			if opt == value then
				return i
			end
		end
		return 1
	end

	local function cycle(delta: number): ()
		local current = Settings.get(row.section, row.key)
		local nextIndex = (indexOf(current) - 1 + delta) % #options + 1
		Settings.set(row.section, row.key, options[nextIndex])
	end

	local left = makeButton(card, "<", 0.55, 0.5, 0.08, 0.55, 18)
	left.Activated:Connect(function(): ()
		cycle(-1)
	end)

	local right = makeButton(card, ">", 0.94, 0.5, 0.08, 0.55, 18)
	right.Activated:Connect(function(): ()
		cycle(1)
	end)

	refreshers[row.section .. "." .. row.key] = function(value: any): ()
		valueLabel.Text = display[value :: string] or tostring(value)
	end
	refreshers[row.section .. "." .. row.key](Settings.get(row.section, row.key))
end

local function buildToggle(row: Row): ()
	local card = controlRow(row)

	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.Position = UDim2.fromScale(0.85, 0.5)
	track.Size = UDim2.fromScale(1, 0.5)
	track.BackgroundColor3 = OFF_COLOR
	corner(track, 0.5)
	aspect(track, 2.2) -- 2.2:1 pill, height-driven
	track.Parent = card

	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0.28, 0.5)
	knob.Size = UDim2.fromScale(1, 0.74)
	knob.BackgroundColor3 = TEXT_COLOR
	corner(knob, 0.5)
	aspect(knob, 1) -- round knob
	knob.Parent = track

	local catcher = Instance.new("ImageButton")
	catcher.AnchorPoint = Vector2.new(0.5, 0.5)
	catcher.Position = UDim2.fromScale(0.5, 0.5)
	catcher.Size = UDim2.fromScale(1, 1)
	catcher.BackgroundTransparency = 1
	catcher.Image = ""
	catcher.ScaleType = Enum.ScaleType.Fit
	catcher.Parent = track

	catcher.Activated:Connect(function(): ()
		Settings.set(row.section, row.key, not Settings.get(row.section, row.key))
	end)

	refreshers[row.section .. "." .. row.key] = function(value: any): ()
		local on = value == true
		track.BackgroundColor3 = if on then ON_COLOR else OFF_COLOR
		knob.Position = if on then UDim2.fromScale(0.72, 0.5) else UDim2.fromScale(0.28, 0.5)
	end
	refreshers[row.section .. "." .. row.key](Settings.get(row.section, row.key))
end

for _, section in SECTIONS do
	makeHeader(section.name)
	for _, row in section.rows do
		if row.kind == "slider" then
			buildSlider(row)
		elseif row.kind == "options" then
			buildOptions(row)
		elseif row.kind == "toggle" then
			buildToggle(row)
		end
	end
end

-- Combat -> Power Output (Ki suppression). Unlike every row above, this value is PER-SLOT: it lives on
-- Humanoid.Stats (written by StatsManager), not the global Settings blob. So this bespoke slider reads
-- the live attribute and pushes via the SetPowerOutput remote instead of Settings.get/set, and the whole
-- section hides until the slot owns the passive (Stats.CanSuppress) -- mirroring the HUD readout and the
-- bracket-key dial. It's the same drag-slider visuals as buildSlider, just bound to a different source.
local POWER_MIN = 1
local POWER_MAX = 100

local combatHeader = makeRowFrame(0.09)
local combatHeaderLabel = makeLabel(combatHeader, "Combat", 0.5, 0.5, 0.96, 0.7, Enum.TextXAlignment.Left, 18)
combatHeaderLabel.Font = Enum.Font.GothamBold
combatHeaderLabel.TextColor3 = ACCENT

local powerCard = controlRow({ kind = "slider", section = "Power", key = "Output", label = "Power Output" })
local powerOuter = powerCard.Parent :: Frame

local powerTrack = Instance.new("Frame")
powerTrack.AnchorPoint = Vector2.new(0.5, 0.5)
powerTrack.Position = UDim2.fromScale(0.65, 0.5)
powerTrack.Size = UDim2.fromScale(0.38, 0.16)
powerTrack.BackgroundColor3 = TRACK_BG
corner(powerTrack, 0.5)
powerTrack.Parent = powerCard

local powerFill = Instance.new("Frame")
powerFill.AnchorPoint = Vector2.new(0.5, 0.5)
powerFill.Position = UDim2.fromScale(0, 0.5)
powerFill.Size = UDim2.fromScale(0, 1)
powerFill.BackgroundColor3 = ACCENT
corner(powerFill, 0.5)
powerFill.Parent = powerTrack

local powerHandle = Instance.new("Frame")
powerHandle.AnchorPoint = Vector2.new(0.5, 0.5)
powerHandle.Position = UDim2.fromScale(0, 0.5)
powerHandle.Size = UDim2.fromScale(0.045, 1.7)
powerHandle.BackgroundColor3 = TEXT_COLOR
corner(powerHandle, 0.5)
powerHandle.Parent = powerTrack

local powerValueLabel = makeLabel(powerCard, "", 0.93, 0.5, 0.12, 0.6, Enum.TextXAlignment.Right, 14)

local powerCatcher = Instance.new("ImageButton")
powerCatcher.AnchorPoint = Vector2.new(0.5, 0.5)
powerCatcher.Position = UDim2.fromScale(0.5, 0.5)
powerCatcher.Size = UDim2.fromScale(1, 3)
powerCatcher.BackgroundTransparency = 1
powerCatcher.Image = ""
powerCatcher.ScaleType = Enum.ScaleType.Fit
powerCatcher.Parent = powerTrack

local function powerApplyVisual(num: number): ()
	local ratio = math.clamp((num - POWER_MIN) / (POWER_MAX - POWER_MIN), 0, 1)
	powerFill.Position = UDim2.fromScale(ratio / 2, 0.5)
	powerFill.Size = UDim2.fromScale(ratio, 1)
	powerHandle.Position = UDim2.fromScale(ratio, 0.5)
	powerValueLabel.Text = tostring(math.floor(num + 0.5)) .. "%"
end

local function powerValueFromX(px: number): number
	local ratio = math.clamp((px - powerTrack.AbsolutePosition.X) / powerTrack.AbsoluteSize.X, 0, 1)
	return math.floor(POWER_MIN + ratio * (POWER_MAX - POWER_MIN) + 0.5)
end

-- The local character's Humanoid.Stats folder, resolved live so respawns need no special handling.
local function getLocalStats(): Folder?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local stats = humanoid and humanoid:FindFirstChild("Stats")
	return if stats and stats:IsA("Folder") then stats else nil
end

local powerDragging = false
local powerLastSent: number? = nil

-- Live drag: move the handle and push the value as it changes (the server clamps + gates). Skip the
-- push when the value hasn't moved so a held drag isn't remote spam (same trick as buildSlider).
local function powerCommit(px: number): ()
	local v = powerValueFromX(px)
	powerApplyVisual(v)
	if v ~= powerLastSent then
		powerLastSent = v
		Remotes.SetPowerOutput:FireServer(v)
	end
end

powerCatcher.InputBegan:Connect(function(input: InputObject): ()
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		powerDragging = true
		powerCommit(input.Position.X)
	end
end)

UserInputService.InputChanged:Connect(function(input: InputObject): ()
	if
		powerDragging
		and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch)
	then
		powerCommit(input.Position.X)
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject): ()
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		powerDragging = false
	end
end)

-- Reflect the live attributes: hide the whole section until the passive is owned, and (when not mid-
-- drag) snap the slider to the current output value.
local function powerRefresh(): ()
	local stats = getLocalStats()
	local canSuppress = stats ~= nil and stats:GetAttribute("CanSuppress") == true
	combatHeader.Visible = canSuppress
	powerOuter.Visible = canSuppress
	if stats and not powerDragging then
		local raw = stats:GetAttribute("PowerOutput")
		powerApplyVisual(if typeof(raw) == "number" then raw else POWER_MAX)
	end
end

local powerConnections: { RBXScriptConnection } = {}

local function powerBind(): ()
	for _, c in powerConnections do
		c:Disconnect()
	end
	table.clear(powerConnections)
	local stats = getLocalStats()
	if stats then
		table.insert(powerConnections, stats:GetAttributeChangedSignal("PowerOutput"):Connect(powerRefresh))
		table.insert(powerConnections, stats:GetAttributeChangedSignal("CanSuppress"):Connect(powerRefresh))
	end
	powerRefresh()
end

player.CharacterAdded:Connect(function(character: Model): ()
	-- The Stats folder lands a beat after the character; wait for it, then (re)bind to the new humanoid.
	task.spawn(function(): ()
		local humanoid = character:WaitForChild("Humanoid", 5)
		if humanoid then
			humanoid:WaitForChild("Stats", 5)
		end
		if player.Character == character then
			powerBind()
		end
	end)
end)
powerBind()

-- Codes section: redeem a code for rewards. Account-wide rewards (Spins/Passes) apply instantly; item
-- rewards are sent to the mailbox to claim. Unlike the Main Menu code box, race-gated codes CAN be
-- redeemed here -- the server checks the active slot's race (we pass source = "Settings"). Appended to
-- the General tab's scroller, so it shows/hides + scrolls with the rest of the rows.
makeHeader("Codes")

local codeOuter = makeRowFrame(0.15)
local codeCard = Instance.new("Frame")
codeCard.AnchorPoint = Vector2.new(0.5, 0.5)
codeCard.Position = UDim2.fromScale(0.5, 0.5)
codeCard.Size = UDim2.fromScale(1, 0.82)
codeCard.BackgroundColor3 = ROW_BG
codeCard.BackgroundTransparency = 0.35
corner(codeCard, 0.28)
codeCard.Parent = codeOuter

local codeBox = Instance.new("TextBox")
codeBox.AnchorPoint = Vector2.new(0.5, 0.5)
codeBox.Position = UDim2.fromScale(0.38, 0.5)
codeBox.Size = UDim2.fromScale(0.66, 0.56)
codeBox.BackgroundColor3 = TRACK_BG
codeBox.ClearTextOnFocus = false
codeBox.Font = Enum.Font.Gotham
codeBox.PlaceholderText = "Enter code"
codeBox.PlaceholderColor3 = TEXT_DIM
codeBox.Text = ""
codeBox.TextColor3 = TEXT_COLOR
codeBox.TextScaled = true
constrainText(codeBox, 8, 16)
corner(codeBox, 0.3)
stroke(codeBox, 0.02, ACCENT, 0.4)
codeBox.Parent = codeCard

local redeemButton = makeButton(codeCard, "Redeem", 0.85, 0.5, 0.24, 0.62, 15)
redeemButton.BackgroundColor3 = TRACK_BG
stroke(redeemButton, 0.02, ACCENT, 0.4)

local codeStatusRow = makeRowFrame(0.07)
local codeStatus = makeLabel(codeStatusRow, "", 0.5, 0.5, 0.96, 0.85, Enum.TextXAlignment.Center, 13)
codeStatus.TextColor3 = TEXT_DIM

local redeeming = false
local function submitCode(): ()
	if redeeming then
		return
	end
	if (codeBox.Text:gsub("%s+", "")) == "" then
		codeStatus.Text = "Enter a code"
		codeStatus.TextColor3 = BAD_COLOR
		return
	end
	redeeming = true
	redeemButton.Text = "..."
	local res = Remotes.RedeemCode:InvokeServer(codeBox.Text, "Settings") :: { ok: boolean?, message: string? }?
	redeeming = false
	redeemButton.Text = "Redeem"
	if typeof(res) == "table" then
		local ok = res.ok == true
		codeStatus.Text = res.message or (if ok then "Redeemed!" else "Couldn't redeem")
		codeStatus.TextColor3 = if ok then ON_COLOR else BAD_COLOR
		if ok then
			codeBox.Text = ""
		end
	else
		codeStatus.Text = "Couldn't redeem"
		codeStatus.TextColor3 = BAD_COLOR
	end
end

redeemButton.Activated:Connect(submitCode)
codeBox.FocusLost:Connect(function(enterPressed: boolean): ()
	if enterPressed then
		submitCode()
	end
end)

-- Hotkeys tab: a rebind row per KeybindConfig action, grouped + ordered. ------------------------

local hotkeysContent = Instance.new("Frame")
hotkeysContent.AnchorPoint = Vector2.new(0.5, 0.5)
hotkeysContent.Position = UDim2.fromScale(0.5, 0.6)
hotkeysContent.Size = UDim2.fromScale(0.92, 0.66)
hotkeysContent.BackgroundTransparency = 1
hotkeysContent.Visible = false
hotkeysContent.Parent = panel

local MOUSE_NAMES = { MouseButton1 = "M1", MouseButton2 = "M2", MouseButton3 = "M3" }
local KEY_NAMES = { Backquote = "`" }
local function bindDisplay(bind: Keybinds.Bind?): string
	if bind == nil then
		return "—"
	end
	local item = bind :: any
	return KEY_NAMES[item.Name] or MOUSE_NAMES[item.Name] or item.Name
end

local keyScroller = Instance.new("ScrollingFrame")
keyScroller.AnchorPoint = Vector2.new(0.5, 0.5)
keyScroller.Position = UDim2.fromScale(0.5, 0.45)
keyScroller.Size = UDim2.fromScale(1, 0.86)
keyScroller.BackgroundTransparency = 1
keyScroller.BorderSizePixel = 0
keyScroller.ScrollBarThickness = 6
keyScroller.ScrollBarImageColor3 = ACCENT
keyScroller.AutomaticCanvasSize = Enum.AutomaticSize.XY
keyScroller.CanvasSize = UDim2.new(0, 0, 0, 0)
keyScroller.Parent = hotkeysContent

local keyLayout = Instance.new("UIListLayout")
keyLayout.FillDirection = Enum.FillDirection.Vertical
keyLayout.SortOrder = Enum.SortOrder.LayoutOrder
keyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
keyLayout.VerticalAlignment = Enum.VerticalAlignment.Top
keyLayout.Parent = keyScroller

local keyButtons: { [string]: TextButton } = {}
local listeningAction: string? = nil

local function refreshRow(action: string): ()
	local button: TextButton? = keyButtons[action]
	if button then
		button.Text = bindDisplay(Keybinds.get(action))
	end
end

local function cancelListening(): ()
	local action = listeningAction
	if action ~= nil then
		listeningAction = nil
		refreshRow(action)
	end
end

local keyOrder = 0
local function keyRow(height: number): Frame
	keyOrder += 1
	local row = Instance.new("Frame")
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Size = UDim2.fromScale(0.96, height)
	row.BackgroundTransparency = 1
	row.LayoutOrder = keyOrder
	row.Parent = keyScroller
	return row
end

local sortedIds: { string } = {}
for id in KeybindConfig do
	table.insert(sortedIds, id)
end
table.sort(sortedIds, function(a: string, b: string): boolean
	return KeybindConfig[a].order < KeybindConfig[b].order
end)

local lastGroup: string? = nil
for _, id in sortedIds do
	local entry = KeybindConfig[id]
	if entry.group ~= lastGroup then
		lastGroup = entry.group
		local header = keyRow(0.085)
		local headerLabel = makeLabel(header, entry.group, 0.5, 0.5, 0.96, 0.7, Enum.TextXAlignment.Left, 16)
		headerLabel.Font = Enum.Font.GothamBold
		headerLabel.TextColor3 = ACCENT
	end

	local outer = keyRow(0.12)
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(1, 0.85)
	card.BackgroundColor3 = ROW_BG
	card.BackgroundTransparency = 0.35
	corner(card, 0.3)
	card.Parent = outer

	makeLabel(card, entry.label, 0.33, 0.5, 0.58, 0.5, Enum.TextXAlignment.Left, 15)

	local keyButton = makeButton(card, bindDisplay(Keybinds.get(id)), 0.82, 0.5, 0.28, 0.62, 15)
	keyButton.BackgroundColor3 = TRACK_BG
	stroke(keyButton, 0.02, ACCENT, 0.4)
	keyButtons[id] = keyButton

	local actionId = id
	keyButton.Activated:Connect(function(): ()
		cancelListening()
		listeningAction = actionId
		keyButton.Text = "Press..."
	end)
end

local resetButton = makeButton(hotkeysContent, "Reset to Defaults", 0.5, 0.95, 0.5, 0.08, 16)
resetButton.Activated:Connect(function(): ()
	Keybinds.resetDefaults()
end)

Keybinds.onChanged(function(action: string): ()
	refreshRow(action)
end)

-- Capture the next press for the listening row. Esc cancels even when game-processed; otherwise we
-- ignore game-processed input so clicking another row's button doesn't get bound as a mouse press.
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean): ()
	local action = listeningAction
	if action == nil then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape then
		listeningAction = nil
		refreshRow(action)
		return
	end
	if gameProcessed then
		return
	end
	local bind = Keybinds.fromInput(input)
	if bind == nil then
		return
	end
	listeningAction = nil
	Keybinds.set(action, bind)
	refreshRow(action)
end)

local function setTab(general: boolean): ()
	cancelListening()
	scroller.Visible = general
	hotkeysContent.Visible = not general
	generalTab.BackgroundColor3 = if general then TAB_ACTIVE else TAB_INACTIVE
	generalTab.TextColor3 = if general then ACCENT else TEXT_DIM
	hotkeysTab.BackgroundColor3 = if general then TAB_INACTIVE else TAB_ACTIVE
	hotkeysTab.TextColor3 = if general then TEXT_DIM else ACCENT
end

generalTab.Activated:Connect(function(): ()
	setTab(true)
end)
hotkeysTab.Activated:Connect(function(): ()
	setTab(false)
end)
setTab(true)

-- Reflect saved/hydrated values (and any change made elsewhere) on the matching control.
Settings.onChanged(function(section: string, key: string, value: any): ()
	local refresh = refreshers[section .. "." .. key]
	if refresh then
		refresh(value)
	end
end)

openButton.Activated:Connect(function(): ()
	panel.Visible = not panel.Visible
end)

closeButton.Activated:Connect(function(): ()
	cancelListening()
	panel.Visible = false
end)
