--!strict
-- Skill Loadout UI: an on-screen button toggles a panel for equipping unlocked Skills into the five
-- hotkey slots (keys 1-5). Pulls a sanitised catalogue + the active slot's current loadout from the
-- server (Remotes.GetSkillLoadout) on every open -- so it reflects new BP unlocks and slot switches --
-- and pushes one (index, skillId) per change (Remotes.SetSkillLoadout, which validates + persists).
-- Skill balance data never reaches the client; we only ever see id/displayName/category/unlocked.
-- Style + builders mirror SettingsController so the two panels match.

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

local LOADOUT_SIZE = 5

type CatalogueEntry = {
	id: string,
	displayName: string,
	category: string,
	type: string,
	unlocked: boolean,
	description: string,
}
type LoadoutView = { catalogue: { CatalogueEntry }, loadout: { string } }

-- Live state, refreshed from the server on each open.
local catalogue: { CatalogueEntry } = {}
local displayById: { [string]: string } = {}
local unlockedById: { [string]: boolean } = {}
local descById: { [string]: string } = {}
local loadout: { string } = { "", "", "", "", "" }
local selectedSlot: number? = nil

-- Forward declaration: slot/skill click handlers call this, but it's assigned once all the widgets
-- it refreshes exist (near the end).
local refreshAll: () -> ()

-- Inline builders (mirror SettingsController) ----------------------------------------------------

local function corner(object: Instance, scale: number): ()
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = object
end

local function stroke(object: Instance, thickness: number, color: Color3, transparency: number): UIStroke
	local s = Instance.new("UIStroke")
	s.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Thickness = thickness
	s.Color = color
	s.Transparency = transparency
	s.Parent = object
	return s
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

-- Shell ------------------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SkillLoadoutUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 10
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local openButton = Instance.new("TextButton")
openButton.Name = "OpenSkills"
openButton.AnchorPoint = Vector2.new(0.5, 0.5)
openButton.Position = UDim2.fromScale(0.93, 0.13) -- below the Settings button (0.07)
openButton.Size = UDim2.fromScale(0.1, 0.05)
openButton.BackgroundColor3 = PANEL_BG
openButton.AutoButtonColor = true
openButton.Font = Enum.Font.GothamBold
openButton.Text = "Skills"
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
panel.Size = UDim2.fromScale(0.55, 0.62)
panel.BackgroundColor3 = PANEL_BG
panel.BackgroundTransparency = 0.05
panel.Visible = false
corner(panel, 0.05)
panel.Parent = screenGui

local title = makeLabel(panel, "Skills", 0.5, 0.06, 0.6, 0.07, Enum.TextXAlignment.Center, 26)
title.Font = Enum.Font.GothamBold

local closeButton = makeButton(panel, "X", 0.93, 0.06, 0.08, 0.06, 20)

local hint = makeLabel(
	panel,
	"Select a slot, then a skill. Click a filled selected slot to clear it.",
	0.5,
	0.31,
	0.9,
	0.04,
	Enum.TextXAlignment.Center,
	12
)
hint.TextColor3 = TEXT_DIM

-- Loadout slots (keys 1-5) -----------------------------------------------------------------------

local slotRow = Instance.new("Frame")
slotRow.AnchorPoint = Vector2.new(0.5, 0.5)
slotRow.Position = UDim2.fromScale(0.5, 0.2)
slotRow.Size = UDim2.fromScale(0.92, 0.14)
slotRow.BackgroundTransparency = 1
slotRow.Parent = panel

local slotButtons: { TextButton } = {}
local slotStrokes: { UIStroke } = {}

local function onSlotClick(index: number)
	if selectedSlot == index then
		if loadout[index] ~= "" then
			loadout[index] = ""
			Remotes.SetSkillLoadout:FireServer(index, "")
		else
			selectedSlot = nil
		end
	else
		selectedSlot = index
	end
	refreshAll()
end

for i = 1, LOADOUT_SIZE do
	local slot = Instance.new("Frame")
	slot.AnchorPoint = Vector2.new(0.5, 0.5)
	slot.Position = UDim2.fromScale((i - 0.5) / LOADOUT_SIZE, 0.5)
	slot.Size = UDim2.fromScale(0.18, 1)
	slot.BackgroundTransparency = 1
	slot.Parent = slotRow

	local number = makeLabel(slot, tostring(i), 0.5, 0.16, 1, 0.28, Enum.TextXAlignment.Center, 16)
	number.Font = Enum.Font.GothamBold
	number.TextColor3 = ACCENT

	local button = makeButton(slot, "Empty", 0.5, 0.66, 1, 0.62, 12)
	button.BackgroundColor3 = SLOT_BG
	local sStroke = stroke(button, 0.03, ACCENT, 1) -- hidden until selected
	slotButtons[i] = button
	slotStrokes[i] = sStroke

	local index = i
	button.Activated:Connect(function()
		onSlotClick(index)
	end)
end

-- Skill catalogue list ---------------------------------------------------------------------------

local scroller = Instance.new("ScrollingFrame")
scroller.Name = "Catalogue"
scroller.AnchorPoint = Vector2.new(0.5, 0.5)
scroller.Position = UDim2.fromScale(0.3, 0.66)
scroller.Size = UDim2.fromScale(0.56, 0.58)
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

-- Parented to the panel (not the scroller) so the UIListLayout never repositions it.
local emptyNotice = makeLabel(panel, "No skills unlocked yet.", 0.3, 0.66, 0.5, 0.06, Enum.TextXAlignment.Center, 16)
emptyNotice.TextColor3 = TEXT_DIM
emptyNotice.Visible = false

-- Detail pane (right): the selected skill's description (server-built from SkillConfig, balance-free).
local detail = Instance.new("Frame")
detail.Name = "Detail"
detail.AnchorPoint = Vector2.new(0.5, 0.5)
detail.Position = UDim2.fromScale(0.79, 0.66)
detail.Size = UDim2.fromScale(0.38, 0.58)
detail.BackgroundColor3 = SLOT_BG
detail.BackgroundTransparency = 0.2
corner(detail, 0.05)
detail.Parent = panel

local detailName = makeLabel(detail, "", 0.5, 0.1, 0.92, 0.1, Enum.TextXAlignment.Center, 18)
detailName.Font = Enum.Font.GothamBold
detailName.Visible = false

local detailDesc = makeLabel(detail, "", 0.5, 0.58, 0.9, 0.78, Enum.TextXAlignment.Left, 14)
detailDesc.TextWrapped = true
detailDesc.TextYAlignment = Enum.TextYAlignment.Top
detailDesc.TextColor3 = TEXT_DIM
detailDesc.Visible = false

local detailPlaceholder =
	makeLabel(detail, "Select a skill to read about it.", 0.5, 0.5, 0.86, 0.12, Enum.TextXAlignment.Center, 16)
detailPlaceholder.TextColor3 = TEXT_DIM

local function showDetail(id: string)
	detailName.Text = displayById[id] or id
	detailDesc.Text = descById[id] or ""
	detailPlaceholder.Visible = false
	detailName.Visible = true
	detailDesc.Visible = true
end

local rowsBuilt = false
local rowRefreshers: { () -> () } = {}

local function equip(id: string)
	if not unlockedById[id] then
		return
	end
	-- Resolve the destination slot: the selected one, else the first empty, else slot 1.
	-- (`or 1` keeps this a plain number so the array index below typechecks.)
	local target: number = selectedSlot or 1
	if not selectedSlot then
		for i = 1, LOADOUT_SIZE do
			if loadout[i] == "" then
				target = i
				break
			end
		end
	end
	-- A skill occupies one slot: drop any existing copy before equipping (mirrors the server).
	for i = 1, LOADOUT_SIZE do
		if loadout[i] == id then
			loadout[i] = ""
		end
	end
	loadout[target] = id
	selectedSlot = target
	Remotes.SetSkillLoadout:FireServer(target, id)
	refreshAll()
end

local function buildRows()
	local orderIndex = 0
	for _, entry in catalogue do
		orderIndex += 1
		local outer = Instance.new("Frame")
		outer.AnchorPoint = Vector2.new(0.5, 0.5)
		outer.Size = UDim2.fromScale(0.97, 0.16)
		outer.BackgroundTransparency = 1
		outer.LayoutOrder = orderIndex
		outer.Parent = scroller

		local card = Instance.new("TextButton")
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.Position = UDim2.fromScale(0.5, 0.5)
		card.Size = UDim2.fromScale(1, 0.84)
		card.BackgroundColor3 = ROW_BG
		card.BackgroundTransparency = 0.35
		card.AutoButtonColor = true
		card.Text = ""
		corner(card, 0.28)
		local cardStroke = stroke(card, 0.02, ACCENT, 1)
		card.Parent = outer

		local nameLabel = makeLabel(card, entry.displayName, 0.32, 0.5, 0.58, 0.55, Enum.TextXAlignment.Left, 16)
		local statusLabel = makeLabel(card, "", 0.8, 0.5, 0.34, 0.5, Enum.TextXAlignment.Right, 13)

		local id = entry.id
		card.Activated:Connect(function()
			showDetail(id) -- inspect (works even when locked)
			equip(id) -- no-op if the skill isn't unlocked
		end)

		table.insert(rowRefreshers, function()
			local unlocked = unlockedById[id] == true
			local equippedSlot: number? = nil
			for i = 1, LOADOUT_SIZE do
				if loadout[i] == id then
					equippedSlot = i
					break
				end
			end

			card.Active = true -- always clickable so locked skills can still be inspected
			card.AutoButtonColor = unlocked
			card.BackgroundTransparency = if unlocked then 0.35 else 0.72
			nameLabel.TextColor3 = if unlocked then TEXT_COLOR else TEXT_DIM
			cardStroke.Transparency = if equippedSlot then 0.1 else 1

			if not unlocked then
				statusLabel.Text = "Locked"
				statusLabel.TextColor3 = TEXT_DIM
			elseif equippedSlot then
				statusLabel.Text = `Slot {equippedSlot}`
				statusLabel.TextColor3 = ACCENT
			else
				statusLabel.Text = entry.category
				statusLabel.TextColor3 = TEXT_DIM
			end
		end)
	end
end

refreshAll = function()
	for i = 1, LOADOUT_SIZE do
		local id = loadout[i]
		local button = slotButtons[i]
		button.Text = if id ~= "" then (displayById[id] or id) else "Empty"
		button.TextColor3 = if id ~= "" then TEXT_COLOR else TEXT_DIM
		slotStrokes[i].Transparency = if selectedSlot == i then 0 else 1
		button.BackgroundColor3 = if selectedSlot == i then ROW_BG else SLOT_BG
	end
	for _, refresh in rowRefreshers do
		refresh()
	end
	emptyNotice.Visible = #catalogue == 0
end

local function openPanel()
	local view = Remotes.GetSkillLoadout:InvokeServer() :: LoadoutView?
	if typeof(view) == "table" and typeof(view.catalogue) == "table" and typeof(view.loadout) == "table" then
		catalogue = view.catalogue
		table.clear(displayById)
		table.clear(unlockedById)
		table.clear(descById)
		for _, entry in catalogue do
			displayById[entry.id] = entry.displayName
			unlockedById[entry.id] = entry.unlocked
			descById[entry.id] = entry.description
		end
		for i = 1, LOADOUT_SIZE do
			loadout[i] = view.loadout[i] or ""
		end
	end
	selectedSlot = nil
	if not rowsBuilt and #catalogue > 0 then
		buildRows()
		rowsBuilt = true
	end
	refreshAll()
	panel.Visible = true
end

openButton.Activated:Connect(function()
	if panel.Visible then
		panel.Visible = false
	else
		openPanel()
	end
end)

closeButton.Activated:Connect(function()
	panel.Visible = false
end)
