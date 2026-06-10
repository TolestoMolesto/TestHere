--!strict
-- Unified Inventory hub. One panel, opened/closed with the Inventory key (default backtick `) or the
-- on-screen button, with two tabs:
--   * Items  -- consumables: a grid + a detail pane with Use (GetInventory / UseItem).
--   * Skills -- ONE combined, colour-coded, sortable list of every ability: Passives + Skills (Moves,
--               keys 1-5) + Forms/Tech (keys 6-0). Selecting a Move or Form shows a key selector in
--               the detail pane to (re)assign its hotkey slot; Passives are read-only info.
-- Balance/config never reaches the client -- the server sends only sanitised lists + the finished
-- description string. Style/builders mirror SettingsController & the other panels.

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
local TAB_INACTIVE = Color3.fromRGB(30, 31, 38)

-- Item rarity border tints.
local RARITY_COLOR: { [string]: Color3 } = {
	Common = Color3.fromRGB(170, 175, 185),
	Uncommon = Color3.fromRGB(90, 200, 110),
	Rare = Color3.fromRGB(70, 150, 255),
	Epic = Color3.fromRGB(180, 100, 240),
	Legendary = Color3.fromRGB(255, 176, 32),
	Mythic = Color3.fromRGB(255, 80, 90),
}

-- Ability kind tints for the combined Skills list (the three groups the user asked to read apart).
local KIND_COLOR: { [string]: Color3 } = {
	Skill = Color3.fromRGB(240, 140, 60), -- Moves (keys 1-5)
	Form = Color3.fromRGB(170, 110, 240), -- Forms / Techniques (keys 6-0)
	Passive = Color3.fromRGB(90, 190, 180), -- read-only innate traits
}
local KIND_ORDER: { [string]: number } = { Skill = 1, Form = 2, Passive = 3 }

type ItemEntry = {
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

type AbilityEntry = {
	id: string,
	displayName: string,
	kind: string, -- "Skill" | "Form" | "Passive" (colour + sort group)
	typeLabel: string, -- "Skill" | "Form" | "Technique" | "Passive"
	description: string,
	unlocked: boolean,
	equippable: boolean,
	slotKind: string?, -- "Skill" | "Form" (which loadout); nil for passives
	slotIndex: number?, -- current loadout slot 1-5, or nil if unequipped
}

local LOADOUT_SIZE = 5

-- Inline builders (mirror SettingsController / the other panels) --------------------------------

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

-- Hotkey display: digits read "1".."0", mouse buttons "M1".."M3", backtick "`", else the raw name.
local DIGIT_NAMES: { [string]: string } = {
	One = "1",
	Two = "2",
	Three = "3",
	Four = "4",
	Five = "5",
	Six = "6",
	Seven = "7",
	Eight = "8",
	Nine = "9",
	Zero = "0",
}
local MOUSE_NAMES: { [string]: string } = { MouseButton1 = "M1", MouseButton2 = "M2", MouseButton3 = "M3" }
local function keyName(bind: Keybinds.Bind?): string
	if bind == nil then
		return "—"
	end
	local n = (bind :: any).Name
	return DIGIT_NAMES[n] or MOUSE_NAMES[n] or (if n == "Backquote" then "`" else n)
end

-- The live key bound to loadout slot `index` for an ability of `slotKind` ("Skill"/"Form").
local function slotKeyName(slotKind: string?, index: number): string
	local action = (if slotKind == "Skill" then "SkillSlot" else "FormSlot") .. index
	return keyName(Keybinds.get(action))
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
openButton.Name = "OpenInventory"
openButton.AnchorPoint = Vector2.new(0.5, 0.5)
openButton.Position = UDim2.fromScale(0.93, 0.13) -- below the Settings button (0.07)
openButton.Size = UDim2.fromScale(0.1, 0.05)
openButton.BackgroundColor3 = PANEL_BG
openButton.AutoButtonColor = true
openButton.Font = Enum.Font.GothamBold
openButton.Text = "Inventory"
openButton.TextColor3 = TEXT_COLOR
openButton.TextScaled = true
constrainText(openButton, 8, 18)
corner(openButton, 0.3)
stroke(openButton, 0.02, ACCENT, 0.2)
openButton.Parent = screenGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromScale(0.6, 0.66)
panel.BackgroundColor3 = PANEL_BG
panel.BackgroundTransparency = 0.05
panel.Visible = false
corner(panel, 0.04)
panel.Parent = screenGui

local title = makeLabel(panel, "Inventory", 0.5, 0.05, 0.6, 0.07, Enum.TextXAlignment.Center, 26)
title.Font = Enum.Font.GothamBold

local closeButton = makeButton(panel, "X", 0.95, 0.05, 0.06, 0.05, 20)

local tabBar = Instance.new("Frame")
tabBar.AnchorPoint = Vector2.new(0.5, 0.5)
tabBar.Position = UDim2.fromScale(0.5, 0.12)
tabBar.Size = UDim2.fromScale(0.44, 0.06)
tabBar.BackgroundTransparency = 1
tabBar.Parent = panel

local itemsTabButton = makeButton(tabBar, "Items", 0.255, 0.5, 0.49, 1, 18)
local skillsTabButton = makeButton(tabBar, "Skills", 0.745, 0.5, 0.49, 1, 18)

local itemsContent = Instance.new("Frame")
itemsContent.Name = "ItemsTab"
itemsContent.AnchorPoint = Vector2.new(0.5, 0.5)
itemsContent.Position = UDim2.fromScale(0.5, 0.57)
itemsContent.Size = UDim2.fromScale(0.96, 0.82)
itemsContent.BackgroundTransparency = 1
itemsContent.Parent = panel

local skillsContent = Instance.new("Frame")
skillsContent.Name = "SkillsTab"
skillsContent.AnchorPoint = Vector2.new(0.5, 0.5)
skillsContent.Position = UDim2.fromScale(0.5, 0.57)
skillsContent.Size = UDim2.fromScale(0.96, 0.82)
skillsContent.BackgroundTransparency = 1
skillsContent.Visible = false
skillsContent.Parent = panel

-- ================================================================================================
-- ITEMS TAB
-- ================================================================================================

local items: { ItemEntry } = {}
local selectedItemId: string? = nil

local gridScroller = Instance.new("ScrollingFrame")
gridScroller.Name = "Grid"
gridScroller.AnchorPoint = Vector2.new(0.5, 0.5)
gridScroller.Position = UDim2.fromScale(0.31, 0.5)
gridScroller.Size = UDim2.fromScale(0.6, 0.98)
gridScroller.BackgroundTransparency = 1
gridScroller.BorderSizePixel = 0
gridScroller.ScrollBarThickness = 6
gridScroller.ScrollBarImageColor3 = ACCENT
gridScroller.AutomaticCanvasSize = Enum.AutomaticSize.XY
gridScroller.CanvasSize = UDim2.new(0, 0, 0, 0)
gridScroller.Parent = itemsContent

local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromScale(0.31, 0.31)
grid.CellPadding = UDim2.new(0, 0, 0, 0) -- no padding; each cell insets its own visible button
grid.FillDirection = Enum.FillDirection.Horizontal
grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
grid.VerticalAlignment = Enum.VerticalAlignment.Top
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = gridScroller

local itemsEmpty = makeLabel(itemsContent, "Your bag is empty.", 0.31, 0.5, 0.5, 0.06, Enum.TextXAlignment.Center, 16)
itemsEmpty.TextColor3 = TEXT_DIM
itemsEmpty.Visible = false

local itemDetail = Instance.new("Frame")
itemDetail.AnchorPoint = Vector2.new(0.5, 0.5)
itemDetail.Position = UDim2.fromScale(0.8, 0.5)
itemDetail.Size = UDim2.fromScale(0.38, 0.98)
itemDetail.BackgroundColor3 = SLOT_BG
itemDetail.BackgroundTransparency = 0.2
corner(itemDetail, 0.05)
itemDetail.Parent = itemsContent

local itemImage = Instance.new("ImageLabel")
itemImage.AnchorPoint = Vector2.new(0.5, 0.5)
itemImage.Position = UDim2.fromScale(0.5, 0.16)
itemImage.Size = UDim2.fromScale(0.46, 0.22)
itemImage.BackgroundTransparency = 1
itemImage.ScaleType = Enum.ScaleType.Fit
itemImage.Parent = itemDetail

local itemName = makeLabel(itemDetail, "", 0.5, 0.33, 0.92, 0.07, Enum.TextXAlignment.Center, 18)
itemName.Font = Enum.Font.GothamBold

local itemDesc = makeLabel(itemDetail, "", 0.5, 0.63, 0.9, 0.46, Enum.TextXAlignment.Left, 14)
itemDesc.TextWrapped = true
itemDesc.TextYAlignment = Enum.TextYAlignment.Top
itemDesc.TextColor3 = TEXT_DIM

local useButton = makeButton(itemDetail, "Use", 0.5, 0.93, 0.74, 0.1, 18)

local itemPlaceholder =
	makeLabel(itemDetail, "Select an item to inspect it.", 0.5, 0.5, 0.86, 0.12, Enum.TextXAlignment.Center, 16)
itemPlaceholder.TextColor3 = TEXT_DIM

local function findItem(id: string?): ItemEntry?
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

local function refreshItemDetail(): ()
	local entry = findItem(selectedItemId)
	if not entry then
		itemPlaceholder.Visible = true
		itemImage.Visible = false
		itemName.Visible = false
		itemDesc.Visible = false
		useButton.Visible = false
		return
	end
	itemPlaceholder.Visible = false
	itemImage.Visible = true
	itemImage.Image = entry.image
	itemName.Visible = true
	itemName.Text = entry.displayName
	itemDesc.Visible = true
	itemDesc.Text = entry.description
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

local itemCells: { Instance } = {}

local function makeCell(entry: ItemEntry, order: number): ()
	local wrapper = Instance.new("Frame")
	wrapper.BackgroundTransparency = 1
	wrapper.LayoutOrder = order
	wrapper.Parent = gridScroller
	table.insert(itemCells, wrapper)

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
		selectedItemId = id
		refreshItemDetail()
	end)
end

local function rebuildGrid(): ()
	for _, wrapper in itemCells do
		wrapper:Destroy()
	end
	table.clear(itemCells)
	for index, entry in items do
		makeCell(entry, index)
	end
	itemsEmpty.Visible = #items == 0
end

local function applyItemView(view: { ItemEntry }?): ()
	items = view or {}
	if selectedItemId and not findItem(selectedItemId) then
		selectedItemId = nil
	end
	rebuildGrid()
	refreshItemDetail()
end

local function pullItems(): ()
	applyItemView(Remotes.GetInventory:InvokeServer() :: { ItemEntry }?)
end

useButton.Activated:Connect(function()
	local entry = findItem(selectedItemId)
	if entry and entry.interactable then
		Remotes.UseItem:FireServer(entry.id)
	end
end)

-- ================================================================================================
-- SKILLS TAB (combined Passives + Moves + Forms)
-- ================================================================================================

type LoadoutView = { catalogue: { any }, loadout: { string } }

local skillCatalogue: { any } = {}
local skillLoadout: { string } = { "", "", "", "", "" }
local formCatalogue: { any } = {}
local formLoadout: { string } = { "", "", "", "", "" }
local passiveList: { any } = {}

local abilities: { AbilityEntry } = {}
local selectedAbilityId: string? = nil
local sortMode = "Type" -- "Type" | "Name"

-- Forward declarations (closures below reference these before they're assigned).
local rebuildAbilityList: () -> ()
local refreshAbilityDetail: () -> ()

local function indexInLoadout(loadout: { string }, id: string): number?
	for i = 1, LOADOUT_SIZE do
		if loadout[i] == id then
			return i
		end
	end
	return nil
end

local function buildAbilities(): ()
	table.clear(abilities)
	for _, c in skillCatalogue do
		table.insert(abilities, {
			id = c.id,
			displayName = c.displayName,
			kind = "Skill",
			typeLabel = "Skill",
			description = c.description or "",
			unlocked = c.unlocked == true,
			equippable = true,
			slotKind = "Skill",
			slotIndex = indexInLoadout(skillLoadout, c.id),
		})
	end
	for _, c in formCatalogue do
		table.insert(abilities, {
			id = c.id,
			displayName = c.displayName,
			kind = "Form",
			typeLabel = c.kind or "Form", -- "Form" or "Technique"
			description = c.description or "",
			unlocked = c.unlocked == true,
			equippable = true,
			slotKind = "Form",
			slotIndex = indexInLoadout(formLoadout, c.id),
		})
	end
	for _, p in passiveList do
		table.insert(abilities, {
			id = p.id,
			displayName = p.displayName,
			kind = "Passive",
			typeLabel = "Passive",
			description = p.description or "",
			unlocked = true,
			equippable = false,
			slotKind = nil,
			slotIndex = nil,
		})
	end

	if sortMode == "Name" then
		table.sort(abilities, function(a, b)
			return a.displayName < b.displayName
		end)
	else
		table.sort(abilities, function(a, b)
			if a.kind ~= b.kind then
				return (KIND_ORDER[a.kind] or 9) < (KIND_ORDER[b.kind] or 9)
			end
			return a.displayName < b.displayName
		end)
	end
end

local function findAbility(id: string?): AbilityEntry?
	if not id then
		return nil
	end
	for _, entry in abilities do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

-- Sort control + list ----------------------------------------------------------------------------

local sortButton = makeButton(skillsContent, "Sort: Type", 0.15, 0.035, 0.26, 0.06, 14)
sortButton.BackgroundColor3 = ROW_BG
sortButton.Activated:Connect(function()
	sortMode = if sortMode == "Type" then "Name" else "Type"
	sortButton.Text = `Sort: {sortMode}`
	buildAbilities()
	rebuildAbilityList()
end)

local listScroller = Instance.new("ScrollingFrame")
listScroller.Name = "AbilityList"
listScroller.AnchorPoint = Vector2.new(0.5, 0.5)
listScroller.Position = UDim2.fromScale(0.31, 0.55)
listScroller.Size = UDim2.fromScale(0.6, 0.88)
listScroller.BackgroundTransparency = 1
listScroller.BorderSizePixel = 0
listScroller.ScrollBarThickness = 6
listScroller.ScrollBarImageColor3 = ACCENT
listScroller.AutomaticCanvasSize = Enum.AutomaticSize.XY
listScroller.CanvasSize = UDim2.new(0, 0, 0, 0)
listScroller.Parent = skillsContent

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.VerticalAlignment = Enum.VerticalAlignment.Top
listLayout.Parent = listScroller

local abilitiesEmpty =
	makeLabel(skillsContent, "Nothing here yet.", 0.31, 0.55, 0.5, 0.06, Enum.TextXAlignment.Center, 16)
abilitiesEmpty.TextColor3 = TEXT_DIM
abilitiesEmpty.Visible = false

-- Detail pane (right) ----------------------------------------------------------------------------

local abDetail = Instance.new("Frame")
abDetail.AnchorPoint = Vector2.new(0.5, 0.5)
abDetail.Position = UDim2.fromScale(0.8, 0.5)
abDetail.Size = UDim2.fromScale(0.38, 0.98)
abDetail.BackgroundColor3 = SLOT_BG
abDetail.BackgroundTransparency = 0.2
corner(abDetail, 0.05)
abDetail.Parent = skillsContent

local abName = makeLabel(abDetail, "", 0.5, 0.07, 0.92, 0.08, Enum.TextXAlignment.Center, 18)
abName.Font = Enum.Font.GothamBold
abName.Visible = false

local abTag = makeLabel(abDetail, "", 0.5, 0.15, 0.6, 0.05, Enum.TextXAlignment.Center, 12)
abTag.Font = Enum.Font.GothamBold
abTag.Visible = false

local abDesc = makeLabel(abDetail, "", 0.5, 0.47, 0.9, 0.56, Enum.TextXAlignment.Left, 14)
abDesc.TextWrapped = true
abDesc.TextYAlignment = Enum.TextYAlignment.Top
abDesc.TextColor3 = TEXT_DIM
abDesc.Visible = false

local abSlotHint = makeLabel(abDetail, "Assign to a key:", 0.5, 0.82, 0.9, 0.05, Enum.TextXAlignment.Center, 13)
abSlotHint.TextColor3 = TEXT_DIM
abSlotHint.Visible = false

local abSlotRow = Instance.new("Frame")
abSlotRow.AnchorPoint = Vector2.new(0.5, 0.5)
abSlotRow.Position = UDim2.fromScale(0.5, 0.92)
abSlotRow.Size = UDim2.fromScale(0.92, 0.1)
abSlotRow.BackgroundTransparency = 1
abSlotRow.Visible = false
abSlotRow.Parent = abDetail

local slotButtons: { TextButton } = {}
for i = 1, LOADOUT_SIZE do
	local b = makeButton(abSlotRow, "", (i - 0.5) / LOADOUT_SIZE, 0.5, 0.17, 1, 16)
	b.BackgroundColor3 = SLOT_BG
	local index = i
	b.Activated:Connect(function()
		local entry = findAbility(selectedAbilityId)
		if not entry or not entry.equippable or not entry.unlocked then
			return
		end
		-- Click the current slot to clear it; otherwise (re)assign to this key.
		local newId = if entry.slotIndex == index then "" else entry.id
		local loadout = if entry.slotKind == "Skill" then skillLoadout else formLoadout
		-- Optimistic local update mirroring the server's one-per-slot rule.
		for k = 1, LOADOUT_SIZE do
			if loadout[k] == entry.id then
				loadout[k] = ""
			end
		end
		loadout[index] = newId
		if entry.slotKind == "Skill" then
			Remotes.SetSkillLoadout:FireServer(index, newId)
		else
			Remotes.SetFormLoadout:FireServer(index, newId)
		end
		buildAbilities()
		rebuildAbilityList()
		refreshAbilityDetail()
	end)
	slotButtons[i] = b
end

local abPlaceholder = makeLabel(abDetail, "Select an ability.", 0.5, 0.5, 0.86, 0.12, Enum.TextXAlignment.Center, 16)
abPlaceholder.TextColor3 = TEXT_DIM

refreshAbilityDetail = function()
	local entry = findAbility(selectedAbilityId)
	if not entry then
		abPlaceholder.Visible = true
		abName.Visible = false
		abTag.Visible = false
		abDesc.Visible = false
		abSlotHint.Visible = false
		abSlotRow.Visible = false
		return
	end
	abPlaceholder.Visible = false
	abName.Visible = true
	abName.Text = entry.displayName
	abTag.Visible = true
	abTag.Text = entry.typeLabel
	abTag.TextColor3 = KIND_COLOR[entry.kind] or TEXT_DIM
	abDesc.Visible = true
	abDesc.Text = entry.description

	local showSlots = entry.equippable and entry.unlocked
	abSlotHint.Visible = showSlots
	abSlotRow.Visible = showSlots
	if showSlots then
		abSlotHint.Text = if entry.slotIndex
			then `Equipped on key {slotKeyName(entry.slotKind, entry.slotIndex)} — tap it to remove`
			else "Tap a key to equip"
		for i = 1, LOADOUT_SIZE do
			local b = slotButtons[i]
			b.Text = slotKeyName(entry.slotKind, i)
			local isCurrent = entry.slotIndex == i
			b.BackgroundColor3 = if isCurrent then ACCENT else SLOT_BG
			b.TextColor3 = if isCurrent then SLOT_BG else TEXT_COLOR
		end
	end
end

local abilityRows: { Instance } = {}

local function makeAbilityRow(entry: AbilityEntry, order: number): ()
	local outer = Instance.new("Frame")
	outer.AnchorPoint = Vector2.new(0.5, 0.5)
	outer.Size = UDim2.fromScale(0.97, 0.14)
	outer.BackgroundTransparency = 1
	outer.LayoutOrder = order
	outer.Parent = listScroller
	table.insert(abilityRows, outer)

	local card = Instance.new("TextButton")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(1, 0.86)
	card.BackgroundColor3 = ROW_BG
	card.BackgroundTransparency = if entry.unlocked then 0.35 else 0.72
	card.AutoButtonColor = true
	card.Text = ""
	corner(card, 0.22)
	stroke(card, 0.025, KIND_COLOR[entry.kind] or ACCENT, 0.15)
	card.Parent = outer

	local nameLabel = makeLabel(card, entry.displayName, 0.35, 0.5, 0.6, 0.5, Enum.TextXAlignment.Left, 15)
	nameLabel.TextColor3 = if entry.unlocked then TEXT_COLOR else TEXT_DIM

	local tag = makeLabel(card, entry.typeLabel, 0.83, 0.32, 0.3, 0.32, Enum.TextXAlignment.Right, 11)
	tag.TextColor3 = KIND_COLOR[entry.kind] or TEXT_DIM

	-- Status: equipped key / Off / Innate / Locked.
	local statusText, statusColor
	if not entry.unlocked then
		statusText, statusColor = "Locked", TEXT_DIM
	elseif not entry.equippable then
		statusText, statusColor = "Innate", TEXT_DIM
	elseif entry.slotIndex then
		statusText, statusColor = `Key {slotKeyName(entry.slotKind, entry.slotIndex)}`, ACCENT
	else
		statusText, statusColor = "Off", TEXT_DIM
	end
	local status = makeLabel(card, statusText, 0.83, 0.68, 0.3, 0.32, Enum.TextXAlignment.Right, 11)
	status.TextColor3 = statusColor

	local id = entry.id
	card.Activated:Connect(function()
		selectedAbilityId = id
		refreshAbilityDetail()
	end)
end

rebuildAbilityList = function()
	for _, row in abilityRows do
		row:Destroy()
	end
	table.clear(abilityRows)
	for index, entry in abilities do
		makeAbilityRow(entry, index)
	end
	abilitiesEmpty.Visible = #abilities == 0
end

local function pullAbilities(): ()
	local sv = Remotes.GetSkillLoadout:InvokeServer() :: LoadoutView?
	if typeof(sv) == "table" and typeof(sv.catalogue) == "table" then
		skillCatalogue = sv.catalogue
		skillLoadout = { "", "", "", "", "" }
		for i = 1, LOADOUT_SIZE do
			skillLoadout[i] = (sv.loadout and sv.loadout[i]) or ""
		end
	end
	local fv = Remotes.GetFormLoadout:InvokeServer() :: LoadoutView?
	if typeof(fv) == "table" and typeof(fv.catalogue) == "table" then
		formCatalogue = fv.catalogue
		formLoadout = { "", "", "", "", "" }
		for i = 1, LOADOUT_SIZE do
			formLoadout[i] = (fv.loadout and fv.loadout[i]) or ""
		end
	end
	local pv = Remotes.GetPassives:InvokeServer()
	passiveList = (if typeof(pv) == "table" then pv else {}) :: { any }

	buildAbilities()
	if selectedAbilityId and not findAbility(selectedAbilityId) then
		selectedAbilityId = nil
	end
	rebuildAbilityList()
	refreshAbilityDetail()
end

-- ================================================================================================
-- Tabs + open/close
-- ================================================================================================

local function setTab(itemsActive: boolean): ()
	itemsContent.Visible = itemsActive
	skillsContent.Visible = not itemsActive
	itemsTabButton.BackgroundColor3 = if itemsActive then ROW_BG else TAB_INACTIVE
	itemsTabButton.TextColor3 = if itemsActive then ACCENT else TEXT_DIM
	skillsTabButton.BackgroundColor3 = if itemsActive then TAB_INACTIVE else ROW_BG
	skillsTabButton.TextColor3 = if itemsActive then TEXT_DIM else ACCENT
end

itemsTabButton.Activated:Connect(function()
	setTab(true)
end)
skillsTabButton.Activated:Connect(function()
	setTab(false)
end)

local function openPanel(): ()
	pullItems()
	pullAbilities()
	panel.Visible = true
end

local function togglePanel(): ()
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

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if Keybinds.matches(input, "Inventory") then
		togglePanel()
	end
end)

-- Live updates while open: item counts after a use/grant, and the form row after a rearrange.
Remotes.InventoryChanged.OnClientEvent:Connect(function(list: any)
	if panel.Visible and itemsContent.Visible then
		applyItemView(list :: { ItemEntry }?)
	else
		items = (list :: { ItemEntry }?) or {}
	end
end)

Remotes.FormLoadoutChanged.OnClientEvent:Connect(function()
	if panel.Visible then
		pullAbilities()
	end
end)

setTab(true)
refreshItemDetail()
refreshAbilityDetail()
