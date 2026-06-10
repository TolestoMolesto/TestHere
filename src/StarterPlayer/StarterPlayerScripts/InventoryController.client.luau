--!strict
-- Inventory (bag) UI: an on-screen "Items" button (and the rebindable Inventory key, default B) toggle
-- a panel showing the active slot's items as a grid, with a detail pane that renders the item's
-- description (the standard Type/Rarity/summary/Effects block) and a Use button. Pulls the sanitised
-- list from the server (Remotes.GetInventory) on open and live-updates from Remotes.InventoryChanged
-- after any use/grant. Item balance/config never reaches the client -- we only ever see counts +
-- display + the finished description string. Style/builders mirror SkillLoadoutController.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Keybinds = require(ReplicatedStorage.Modules.Keybinds)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PANEL_BG = Color3.fromRGB(26, 27, 33)
local ROW_BG = Color3.fromRGB(40, 42, 51)
local SLOT_BG = Color3.fromRGB(16, 17, 22)
local ACCENT = Color3.fromRGB(255, 176, 32)
local TEXT_COLOR = Color3.fromRGB(238, 240, 245)
local TEXT_DIM = Color3.fromRGB(150, 153, 165)

-- Rarity border tints (cosmetic only; rarity also reads in the description text).
local RARITY_COLOR: { [string]: Color3 } = {
	Common = Color3.fromRGB(170, 175, 185),
	Uncommon = Color3.fromRGB(90, 200, 110),
	Rare = Color3.fromRGB(70, 150, 255),
	Epic = Color3.fromRGB(180, 100, 240),
	Legendary = Color3.fromRGB(255, 176, 32),
	Mythic = Color3.fromRGB(255, 80, 90),
}

type Entry = {
	id: string,
	displayName: string,
	type: string,
	rarity: string,
	count: number,
	maxAmount: number,
	image: string,
	interactable: boolean,
	description: string,
}

-- Live state, refreshed from the server.
local items: { Entry } = {}
local selectedId: string? = nil

-- Forward declarations: cell clicks call refreshDetail, openPanel calls rebuildGrid (both assigned
-- once the widgets they touch exist).
local refreshDetail: () -> ()
local rebuildGrid: () -> ()

-- Inline builders (mirror SkillLoadoutController) ------------------------------------------------

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
screenGui.Name = "InventoryUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 10
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local openButton = Instance.new("TextButton")
openButton.Name = "OpenItems"
openButton.AnchorPoint = Vector2.new(0.5, 0.5)
openButton.Position = UDim2.fromScale(0.93, 0.19) -- below the Skills button (0.13)
openButton.Size = UDim2.fromScale(0.1, 0.05)
openButton.BackgroundColor3 = PANEL_BG
openButton.AutoButtonColor = true
openButton.Font = Enum.Font.GothamBold
openButton.Text = "Items"
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
corner(panel, 0.04)
panel.Parent = screenGui

local title = makeLabel(panel, "Items", 0.5, 0.06, 0.6, 0.07, Enum.TextXAlignment.Center, 26)
title.Font = Enum.Font.GothamBold

local closeButton = makeButton(panel, "X", 0.94, 0.06, 0.07, 0.06, 20)

-- Item grid (left) -------------------------------------------------------------------------------

local gridScroller = Instance.new("ScrollingFrame")
gridScroller.Name = "Grid"
gridScroller.AnchorPoint = Vector2.new(0.5, 0.5)
gridScroller.Position = UDim2.fromScale(0.31, 0.56)
gridScroller.Size = UDim2.fromScale(0.58, 0.82)
gridScroller.BackgroundTransparency = 1
gridScroller.BorderSizePixel = 0
gridScroller.ScrollBarThickness = 6
gridScroller.ScrollBarImageColor3 = ACCENT
gridScroller.AutomaticCanvasSize = Enum.AutomaticSize.XY
gridScroller.CanvasSize = UDim2.new(0, 0, 0, 0)
gridScroller.Parent = panel

local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromScale(0.31, 0.31)
grid.CellPadding = UDim2.new(0, 0, 0, 0) -- no padding; each cell insets its own visible button
grid.FillDirection = Enum.FillDirection.Horizontal
grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
grid.VerticalAlignment = Enum.VerticalAlignment.Top
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = gridScroller

-- Parented to the panel (not the scroller) so the grid layout never repositions it.
local emptyNotice = makeLabel(panel, "Your bag is empty.", 0.31, 0.56, 0.5, 0.06, Enum.TextXAlignment.Center, 16)
emptyNotice.TextColor3 = TEXT_DIM
emptyNotice.Visible = false

-- Detail pane (right) ----------------------------------------------------------------------------

local detail = Instance.new("Frame")
detail.Name = "Detail"
detail.AnchorPoint = Vector2.new(0.5, 0.5)
detail.Position = UDim2.fromScale(0.79, 0.56)
detail.Size = UDim2.fromScale(0.38, 0.82)
detail.BackgroundColor3 = SLOT_BG
detail.BackgroundTransparency = 0.2
corner(detail, 0.05)
detail.Parent = panel

local detailImage = Instance.new("ImageLabel")
detailImage.AnchorPoint = Vector2.new(0.5, 0.5)
detailImage.Position = UDim2.fromScale(0.5, 0.16)
detailImage.Size = UDim2.fromScale(0.46, 0.22)
detailImage.BackgroundTransparency = 1
detailImage.ScaleType = Enum.ScaleType.Fit
detailImage.Parent = detail

local detailName = makeLabel(detail, "", 0.5, 0.33, 0.92, 0.07, Enum.TextXAlignment.Center, 18)
detailName.Font = Enum.Font.GothamBold

local detailDesc = makeLabel(detail, "", 0.5, 0.63, 0.9, 0.46, Enum.TextXAlignment.Left, 14)
detailDesc.TextWrapped = true
detailDesc.TextYAlignment = Enum.TextYAlignment.Top
detailDesc.TextColor3 = TEXT_DIM

local useButton = makeButton(detail, "Use", 0.5, 0.93, 0.74, 0.1, 18)

local detailPlaceholder =
	makeLabel(detail, "Select an item to inspect it.", 0.5, 0.5, 0.86, 0.12, Enum.TextXAlignment.Center, 16)
detailPlaceholder.TextColor3 = TEXT_DIM

local function findEntry(id: string?): Entry?
	if not id then
		return nil
	end
	for _, entry in items do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

refreshDetail = function()
	local entry = findEntry(selectedId)
	if not entry then
		detailPlaceholder.Visible = true
		detailImage.Visible = false
		detailName.Visible = false
		detailDesc.Visible = false
		useButton.Visible = false
		return
	end
	detailPlaceholder.Visible = false
	detailImage.Visible = true
	detailImage.Image = entry.image
	detailName.Visible = true
	detailName.Text = entry.displayName
	detailDesc.Visible = true
	detailDesc.Text = entry.description
	useButton.Visible = true
	if entry.interactable then
		useButton.Text = "Use"
		useButton.Active = true
		useButton.AutoButtonColor = true
		useButton.BackgroundColor3 = ROW_BG
		useButton.TextColor3 = TEXT_COLOR
	else
		useButton.Text = "Cannot be used"
		useButton.Active = false
		useButton.AutoButtonColor = false
		useButton.BackgroundColor3 = SLOT_BG
		useButton.TextColor3 = TEXT_DIM
	end
end

-- Item cells -------------------------------------------------------------------------------------

local cellWrappers: { Instance } = {}

local function makeCell(entry: Entry, order: number): ()
	-- Transparent wrapper sized by the grid; the visible button insets so cells have a gap without
	-- any padding object.
	local wrapper = Instance.new("Frame")
	wrapper.BackgroundTransparency = 1
	wrapper.LayoutOrder = order
	wrapper.Parent = gridScroller
	table.insert(cellWrappers, wrapper)

	local cell = Instance.new("TextButton")
	cell.AnchorPoint = Vector2.new(0.5, 0.5)
	cell.Position = UDim2.fromScale(0.5, 0.5)
	cell.Size = UDim2.fromScale(0.88, 0.88)
	cell.BackgroundColor3 = SLOT_BG
	cell.AutoButtonColor = true
	cell.Text = ""
	corner(cell, 0.12)
	stroke(cell, 0.03, RARITY_COLOR[entry.rarity] or ACCENT, 0)
	cell.Parent = wrapper

	local image = Instance.new("ImageLabel")
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.3)
	image.Size = UDim2.fromScale(0.62, 0.46)
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.Image = entry.image
	image.Parent = cell

	local nameLabel = makeLabel(cell, entry.displayName, 0.5, 0.66, 0.94, 0.2, Enum.TextXAlignment.Center, 13)
	nameLabel.TextColor3 = TEXT_COLOR

	local countLabel = makeLabel(cell, `x{entry.count}`, 0.5, 0.88, 0.6, 0.16, Enum.TextXAlignment.Center, 13)
	countLabel.Font = Enum.Font.GothamBold
	countLabel.TextColor3 = ACCENT

	local id = entry.id
	cell.Activated:Connect(function()
		selectedId = id
		refreshDetail()
	end)
end

rebuildGrid = function()
	for _, wrapper in cellWrappers do
		wrapper:Destroy()
	end
	table.clear(cellWrappers)
	for index, entry in items do
		makeCell(entry, index)
	end
	emptyNotice.Visible = #items == 0
end

-- Open / close ----------------------------------------------------------------------------------

local function applyView(view: { Entry }?)
	items = view or {}
	-- Drop the selection if the selected item is no longer present (e.g. used the last one).
	if selectedId and not findEntry(selectedId) then
		selectedId = nil
	end
	rebuildGrid()
	refreshDetail()
end

local function openPanel()
	local view = Remotes.GetInventory:InvokeServer() :: { Entry }?
	applyView(view)
	panel.Visible = true
end

local function togglePanel()
	if panel.Visible then
		panel.Visible = false
	else
		openPanel()
	end
end

openButton.Activated:Connect(togglePanel)
closeButton.Activated:Connect(function()
	panel.Visible = false
end)

useButton.Activated:Connect(function()
	local entry = findEntry(selectedId)
	if entry and entry.interactable then
		Remotes.UseItem:FireServer(entry.id)
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if Keybinds.matches(input, "Inventory") then
		togglePanel()
	end
end)

-- Live updates: the server pushes a fresh list after any use/grant. Only redraw if the panel is open
-- (it re-pulls on open anyway), but always keep the cached list current.
Remotes.InventoryChanged.OnClientEvent:Connect(function(list: any)
	if panel.Visible then
		applyView(list :: { Entry }?)
	else
		items = (list :: { Entry }?) or {}
	end
end)

refreshDetail()
