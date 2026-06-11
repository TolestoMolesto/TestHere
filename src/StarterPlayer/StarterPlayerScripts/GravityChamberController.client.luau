--!strict
-- Gravity Chamber control panel (model B). Always on-screen while you're in the Gravity Chamber place
-- (GetChamberState returns nil anywhere else, so this self-hides). Everyone sees the live gravity + who
-- controls it; only the OWNER (first in, server-authoritative -- GravityChamberServer) sees the
-- +/-/Reset buttons and the Change Owner picker. Style mirrors PartyController (Scale-only, AnchorPoint
-- 0.5, no padding, TextScaled + UITextSizeConstraint, scaled UIStroke).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Modules.Remotes)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PANEL_BG = Color3.fromRGB(26, 27, 33)
local ROW_BG = Color3.fromRGB(40, 42, 51)
local SLOT_BG = Color3.fromRGB(16, 17, 22)
local ACCENT = Color3.fromRGB(255, 176, 32)
local TEXT_COLOR = Color3.fromRGB(238, 240, 245)
local TEXT_DIM = Color3.fromRGB(150, 153, 165)
local GOOD = Color3.fromRGB(120, 220, 130)
local BAD = Color3.fromRGB(235, 110, 110)

type ChamberState = { multiplier: number, ownerUserId: number, baseMultiplier: number }

local currentState: ChamberState? = nil

-- Builders (mirror PartyController) --------------------------------------------------------------

local function corner(object: Instance, scale: number): ()
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = object
end

local function stroke(object: Instance, thickness: number, color: Color3, transparency: number): ()
	local s = Instance.new("UIStroke")
	s.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
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

local function makeScroller(parent: Instance, posY: number, sizeY: number): ScrollingFrame
	local scroller = Instance.new("ScrollingFrame")
	scroller.AnchorPoint = Vector2.new(0.5, 0.5)
	scroller.Position = UDim2.fromScale(0.5, posY)
	scroller.Size = UDim2.fromScale(0.92, sizeY)
	scroller.BackgroundColor3 = SLOT_BG
	scroller.BackgroundTransparency = 0.4
	scroller.BorderSizePixel = 0
	scroller.ScrollBarThickness = 6
	scroller.ScrollBarImageColor3 = ACCENT
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.XY
	scroller.CanvasSize = UDim2.new(0, 0, 0, 0)
	corner(scroller, 0.04)
	scroller.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = scroller

	return scroller
end

-- Compact "x Earth" multiple: 11x, 1.5x, 1e+07x for the silly-high end.
local function fmtMult(m: number): string
	if m % 1 == 0 and m < 1e9 then
		return string.format("%d", m) .. "x"
	end
	return string.format("%.4g", m) .. "x"
end

-- Shell ------------------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GravityChamberUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 9
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Enabled = false
screenGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.15, 0.62)
panel.Size = UDim2.fromScale(0.24, 0.34)
panel.BackgroundColor3 = PANEL_BG
panel.BackgroundTransparency = 0.05
corner(panel, 0.05)
stroke(panel, 0.02, ACCENT, 0.3)
panel.Parent = screenGui

makeLabel(panel, "Gravity Chamber", 0.5, 0.08, 0.9, 0.1, Enum.TextXAlignment.Center, 18).Font = Enum.Font.GothamBold

local readout = makeLabel(panel, "1x", 0.5, 0.25, 0.9, 0.16, Enum.TextXAlignment.Center, 40)
readout.Font = Enum.Font.GothamBold
readout.TextColor3 = ACCENT

local ownerLabel = makeLabel(panel, "", 0.5, 0.41, 0.92, 0.07, Enum.TextXAlignment.Center, 13)
ownerLabel.TextColor3 = TEXT_DIM

-- Owner-only controls (toggled against `hint` in render) -----------------------------------------

local controls = Instance.new("Frame")
controls.Name = "Controls"
controls.AnchorPoint = Vector2.new(0.5, 0.5)
controls.Position = UDim2.fromScale(0.5, 0.74)
controls.Size = UDim2.fromScale(0.94, 0.44)
controls.BackgroundTransparency = 1
controls.Parent = panel

local STEPS = { -100, -10, -1, 1, 10, 100 }
for i, delta in STEPS do
	local label = if delta > 0 then `+{delta}` else tostring(delta)
	local btn = makeButton(controls, label, 0.09 + (i - 1) * 0.164, 0.25, 0.15, 0.38, 13)
	btn.BackgroundColor3 = SLOT_BG
	btn.TextColor3 = if delta > 0 then GOOD else BAD
	btn.Activated:Connect(function()
		local state = currentState
		if state then
			Remotes.RequestChamberGravity:FireServer(state.multiplier + delta)
		end
	end)
end

local resetBtn = makeButton(controls, "Reset", 0.28, 0.78, 0.42, 0.34, 15)
resetBtn.Activated:Connect(function()
	local state = currentState
	if state then
		Remotes.RequestChamberGravity:FireServer(state.baseMultiplier)
	end
end)

local changeOwnerBtn = makeButton(controls, "Change Owner", 0.72, 0.78, 0.42, 0.34, 14)
changeOwnerBtn.TextColor3 = ACCENT

local hint = makeLabel(panel, "", 0.5, 0.74, 0.88, 0.34, Enum.TextXAlignment.Center, 14)
hint.TextColor3 = TEXT_DIM
hint.TextWrapped = true
hint.Visible = false

-- Change Owner picker overlay --------------------------------------------------------------------

local overlay = Instance.new("Frame")
overlay.Name = "OwnerPicker"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.5
overlay.Visible = false
overlay.ZIndex = 50
overlay.Parent = screenGui

local pickerCard = Instance.new("Frame")
pickerCard.AnchorPoint = Vector2.new(0.5, 0.5)
pickerCard.Position = UDim2.fromScale(0.5, 0.5)
pickerCard.Size = UDim2.fromScale(0.32, 0.46)
pickerCard.BackgroundColor3 = PANEL_BG
pickerCard.ZIndex = 51
corner(pickerCard, 0.05)
stroke(pickerCard, 0.02, ACCENT, 0.2)
pickerCard.Parent = overlay

local pickerTitle = makeLabel(pickerCard, "Give control to...", 0.5, 0.09, 0.9, 0.1, Enum.TextXAlignment.Center, 18)
pickerTitle.Font = Enum.Font.GothamBold
pickerTitle.ZIndex = 52

local pickerScroller = makeScroller(pickerCard, 0.5, 0.62)
pickerScroller.ZIndex = 52

local pickerEmpty = makeLabel(pickerCard, "No one else is here.", 0.5, 0.5, 0.8, 0.08, Enum.TextXAlignment.Center, 14)
pickerEmpty.TextColor3 = TEXT_DIM
pickerEmpty.ZIndex = 53

local cancelBtn = makeButton(pickerCard, "Cancel", 0.5, 0.91, 0.5, 0.1, 15)
cancelBtn.BackgroundColor3 = SLOT_BG
cancelBtn.ZIndex = 52

local pickerRows: { Instance } = {}

local function clearPickerRows(): ()
	for _, row in pickerRows do
		row:Destroy()
	end
	table.clear(pickerRows)
end

local function buildPickerList(): ()
	clearPickerRows()
	local others: { Player } = {}
	for _, p in Players:GetPlayers() do
		if p ~= player then
			table.insert(others, p)
		end
	end
	pickerEmpty.Visible = #others == 0
	for i, target in others do
		local wrapper = Instance.new("Frame")
		wrapper.BackgroundTransparency = 1
		wrapper.Size = UDim2.fromScale(1, 0.2)
		wrapper.LayoutOrder = i
		wrapper.ZIndex = 52
		wrapper.Parent = pickerScroller
		table.insert(pickerRows, wrapper)

		local card = Instance.new("Frame")
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.Position = UDim2.fromScale(0.5, 0.5)
		card.Size = UDim2.fromScale(0.96, 0.82)
		card.BackgroundColor3 = ROW_BG
		card.ZIndex = 52
		corner(card, 0.2)
		card.Parent = wrapper

		local name = makeLabel(card, target.DisplayName, 0.32, 0.5, 0.58, 0.6, Enum.TextXAlignment.Left, 15)
		name.ZIndex = 53

		local give = makeButton(card, "Give", 0.82, 0.5, 0.3, 0.66, 13)
		give.BackgroundColor3 = SLOT_BG
		give.TextColor3 = ACCENT
		give.ZIndex = 53
		give.Activated:Connect(function()
			Remotes.TransferChamberOwner:FireServer(target)
			overlay.Visible = false
		end)
	end
end

changeOwnerBtn.Activated:Connect(function()
	buildPickerList()
	overlay.Visible = true
end)
cancelBtn.Activated:Connect(function()
	overlay.Visible = false
end)

-- Render -----------------------------------------------------------------------------------------

local function render(): ()
	local state = currentState
	if not state then
		return
	end
	readout.Text = fmtMult(state.multiplier)

	local isOwner = state.ownerUserId == player.UserId
	local ownerPlayer = if state.ownerUserId ~= 0 then Players:GetPlayerByUserId(state.ownerUserId) else nil
	local ownerName = if ownerPlayer then ownerPlayer.DisplayName else "nobody"

	ownerLabel.Text = if isOwner then "You control the chamber" else `Controlled by {ownerName}`
	controls.Visible = isOwner
	hint.Visible = not isOwner
	if not isOwner then
		hint.Text = `Only {ownerName} can change the gravity.`
		overlay.Visible = false -- lost control while picking
	elseif overlay.Visible then
		buildPickerList() -- keep the list fresh as players join/leave
	end
end

-- Init: confirm we're in a chamber, then show + listen. Retry the pull a few times in case the server
-- handler isn't bound the instant the client loads.
local function init(): ()
	local state: any = nil
	for _ = 1, 5 do
		local ok, result = pcall(function()
			return Remotes.GetChamberState:InvokeServer()
		end)
		if ok then
			state = result
			break
		end
		task.wait(0.5)
	end
	if state == nil then
		screenGui:Destroy()
		return
	end

	currentState = state
	render()
	screenGui.Enabled = true

	Remotes.ChamberStateChanged.OnClientEvent:Connect(function(newState: any)
		currentState = newState
		render()
	end)

	local function onRoster(): ()
		if currentState then
			render()
		end
	end
	Players.PlayerAdded:Connect(onRoster)
	Players.PlayerRemoving:Connect(onRoster)
end

init()
