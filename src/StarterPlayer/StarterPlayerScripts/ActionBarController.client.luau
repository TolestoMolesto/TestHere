--!strict
-- Combat action bar: a bottom-centre HUD of 10 slots -- the equipped Skills (keys 1-5) and the
-- race's abilities (keys 6-0) -- each with a live cooldown sweep, and (for active forms/techniques)
-- a duration countdown. Display-only: the slots are Frames/Labels, never Buttons, so they never eat
-- combat clicks. Names/cooldowns come from the server once (GetSkillLoadout catalogue + GetFormBar);
-- the live equipped skill ids and all cooldown/active/expiry state are read from character
-- attributes each frame against workspace:GetServerTimeNow() (the same synced clock the server
-- stamps cooldowns with). Keys reflect the player's rebinds. Style mirrors the other panels.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Keybinds = require(ReplicatedStorage.Modules.Keybinds)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SLOT_BG = Color3.fromRGB(26, 27, 33)
local OVERLAY = Color3.fromRGB(8, 8, 10)
local ACCENT = Color3.fromRGB(255, 176, 32)
local ACTIVE = Color3.fromRGB(96, 200, 120)
local TEXT_COLOR = Color3.fromRGB(238, 240, 245)
local TEXT_DIM = Color3.fromRGB(150, 153, 165)

local SKILL_COUNT = 5
local FORM_COUNT = 5
local SLOT_PITCH = 0.088 -- container-relative centre-to-centre spacing between slots

type Slot = {
	frame: Frame,
	keyLabel: TextLabel,
	nameLabel: TextLabel,
	timerLabel: TextLabel,
	overlay: Frame,
	overlayGradient: UIGradient,
	stroke: UIStroke,
}

type FormEntry = { id: string, displayName: string, kind: string, cooldown: number, description: string }

local skillInfo: { [string]: { name: string, cooldown: number, description: string } } = {}
local formBar: { FormEntry } = {}

-- Inline builders (mirror the other UI controllers) ----------------------------------------------

local function corner(object: Instance, scale: number): ()
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = object
end

local function constrainText(textObject: Instance, minSize: number, maxSize: number): ()
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = minSize
	constraint.MaxTextSize = maxSize
	constraint.Parent = textObject
end

local function makeLabel(
	parent: Instance,
	posX: number,
	posY: number,
	sizeX: number,
	sizeY: number,
	maxSize: number,
	color: Color3,
	bold: boolean
): TextLabel
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(posX, posY)
	label.Size = UDim2.fromScale(sizeX, sizeY)
	label.BackgroundTransparency = 1
	label.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	label.Text = ""
	label.TextColor3 = color
	label.TextScaled = true
	label.ZIndex = 3
	constrainText(label, 6, maxSize)
	label.Parent = parent
	return label
end

-- Key display: digits read "1".."0", mouse buttons "M1".."M3", everything else its raw name.
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
	return DIGIT_NAMES[n] or MOUSE_NAMES[n] or n
end

-- Shell ------------------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ActionBarUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 8
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "ActionBar"
container.AnchorPoint = Vector2.new(0.5, 0.5)
container.Position = UDim2.fromScale(0.5, 0.9)
container.Size = UDim2.fromScale(0.62, 0.08)
container.BackgroundTransparency = 1
container.Parent = screenGui

-- Hover tooltip: shows the hovered slot's description above the bar (desktop hover only). The slots
-- stay Frames so they never sink combat clicks -- MouseEnter/MouseLeave don't either.
local tooltip = Instance.new("Frame")
tooltip.Name = "Tooltip"
tooltip.AnchorPoint = Vector2.new(0.5, 1)
tooltip.Position = UDim2.fromScale(0.5, 0.86) -- bottom edge just above the bar (container at 0.9)
tooltip.Size = UDim2.fromScale(0.32, 0.5)
tooltip.BackgroundColor3 = SLOT_BG
tooltip.BackgroundTransparency = 0.05
tooltip.Visible = false
tooltip.ZIndex = 20
corner(tooltip, 0.06)
tooltip.Parent = screenGui

local tooltipText = Instance.new("TextLabel")
tooltipText.AnchorPoint = Vector2.new(0.5, 0.5)
tooltipText.Position = UDim2.fromScale(0.5, 0.5)
tooltipText.Size = UDim2.fromScale(0.9, 0.88)
tooltipText.BackgroundTransparency = 1
tooltipText.Font = Enum.Font.Gotham
tooltipText.Text = ""
tooltipText.TextColor3 = TEXT_COLOR
tooltipText.TextScaled = true
tooltipText.TextWrapped = true
tooltipText.TextXAlignment = Enum.TextXAlignment.Left
tooltipText.TextYAlignment = Enum.TextYAlignment.Top
tooltipText.ZIndex = 21
constrainText(tooltipText, 6, 14)
tooltipText.Parent = tooltip

local function showTooltip(text: string): ()
	if text == "" then
		return
	end
	tooltipText.Text = text
	tooltip.Visible = true
end

local function hideTooltip(): ()
	tooltip.Visible = false
end

-- Slots are positioned by relayout() (called each frame), which packs the *visible* ones
-- contiguously and centres them, so hiding an empty slot closes its gap.
local function makeSlot(): Slot
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(SLOT_PITCH, 1)
	frame.BackgroundColor3 = SLOT_BG
	frame.BackgroundTransparency = 0.2
	frame.ClipsDescendants = true
	frame.ZIndex = 1
	corner(frame, 0.16)
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.Parent = frame

	local slotStroke = Instance.new("UIStroke")
	slotStroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	slotStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	slotStroke.Thickness = 0.04
	slotStroke.Color = ACTIVE
	slotStroke.Transparency = 1 -- shown only while the ability is active
	slotStroke.Parent = frame

	-- Cooldown sweep: a full-slot dark fill sharing the slot's corner radius (so it can't poke
	-- square corners past the rounded slot). A vertical gradient drains it downward -- transparent
	-- above the remaining-fraction line, dark below -- updated each frame by setCooldown.
	local overlay = Instance.new("Frame")
	overlay.AnchorPoint = Vector2.new(0.5, 0.5)
	overlay.Position = UDim2.fromScale(0.5, 0.5)
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = OVERLAY
	overlay.BackgroundTransparency = 0.3
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 2
	overlay.Visible = false
	corner(overlay, 0.16)
	local overlayGradient = Instance.new("UIGradient")
	overlayGradient.Rotation = 90 -- vertical; gradient time 0 = top, 1 = bottom
	overlayGradient.Parent = overlay
	overlay.Parent = frame

	local keyLabel = makeLabel(frame, 0.5, 0.2, 0.9, 0.34, 18, ACCENT, true)
	local nameLabel = makeLabel(frame, 0.5, 0.82, 0.94, 0.3, 11, TEXT_DIM, false)
	local timerLabel = makeLabel(frame, 0.5, 0.52, 0.8, 0.46, 22, TEXT_COLOR, true)
	timerLabel.Visible = false

	frame.Parent = container

	return {
		frame = frame,
		keyLabel = keyLabel,
		nameLabel = nameLabel,
		timerLabel = timerLabel,
		overlay = overlay,
		overlayGradient = overlayGradient,
		stroke = slotStroke,
	}
end

local skillSlots: { Slot } = {}
local formSlots: { Slot } = {}
local orderedSlots: { Slot } = {} -- display order: skills 1-5, then forms 6-0
for i = 1, SKILL_COUNT do
	skillSlots[i] = makeSlot()
	table.insert(orderedSlots, skillSlots[i])
end
for i = 1, FORM_COUNT do
	formSlots[i] = makeSlot()
	table.insert(orderedSlots, formSlots[i])
end

-- Hover wiring: skill slots show the currently-equipped skill's description, form slots the
-- ability's. Empty slots show nothing. (MouseEnter/MouseLeave on a Frame don't sink combat input.)
for i = 1, SKILL_COUNT do
	local index = i
	local slot = skillSlots[index]
	slot.frame.MouseEnter:Connect(function()
		local char = player.Character
		local id = char and char:GetAttribute("SkillSlot" .. index)
		local info = if type(id) == "string" then skillInfo[id] else nil
		if info then
			showTooltip(info.description)
		end
	end)
	slot.frame.MouseLeave:Connect(hideTooltip)
end
for i = 1, FORM_COUNT do
	local index = i
	local slot = formSlots[index]
	slot.frame.MouseEnter:Connect(function()
		local entry = formBar[index]
		if entry then
			showTooltip(entry.description)
		end
	end)
	slot.frame.MouseLeave:Connect(hideTooltip)
end

-- Packs the visible slots contiguously and centres them (skills then forms, in order), so an
-- equipped 1, 2, 4 with empty 3 shows three adjacent slots rather than a gap.
local function relayout(): ()
	local visibleCount = 0
	for _, slot in orderedSlots do
		if slot.frame.Visible then
			visibleCount += 1
		end
	end
	if visibleCount == 0 then
		return
	end
	local startX = 0.5 - (visibleCount * SLOT_PITCH) / 2
	local index = 0
	for _, slot in orderedSlots do
		if slot.frame.Visible then
			index += 1
			slot.frame.Position = UDim2.fromScale(startX + (index - 0.5) * SLOT_PITCH, 0.5)
		end
	end
end

-- Data ------------------------------------------------------------------------------------------

local function refreshKeyLabels(): ()
	for i = 1, SKILL_COUNT do
		skillSlots[i].keyLabel.Text = keyName(Keybinds.get("SkillSlot" .. i))
	end
	for i = 1, FORM_COUNT do
		formSlots[i].keyLabel.Text = keyName(Keybinds.get("FormSlot" .. i))
	end
end

local function fetchData(): ()
	local view = Remotes.GetSkillLoadout:InvokeServer()
	table.clear(skillInfo)
	if typeof(view) == "table" and typeof(view.catalogue) == "table" then
		for _, entry in view.catalogue do
			skillInfo[entry.id] =
				{ name = entry.displayName, cooldown = entry.cooldown or 0, description = entry.description or "" }
		end
	end

	local bar = Remotes.GetFormBar:InvokeServer()
	formBar = (if typeof(bar) == "table" then bar else {}) :: { FormEntry }

	-- Form names are static per race -- set them once here; their live state ticks in the loop.
	for i = 1, FORM_COUNT do
		local entry = formBar[i]
		local filled = entry ~= nil and entry.id ~= ""
		formSlots[i].frame.Visible = filled
		formSlots[i].nameLabel.Text = if entry and entry.id ~= "" then entry.displayName else ""
	end
end

-- Live tick -------------------------------------------------------------------------------------

local function clearTiming(slot: Slot): ()
	slot.overlay.Visible = false
	slot.timerLabel.Visible = false
end

-- Drives the cooldown overlay's drain via its gradient (rounded-corner safe). The dark covers the
-- bottom `remaining/total` of the slot and recedes downward as it elapses.
local function setCooldown(slot: Slot, remaining: number, total: number): ()
	slot.overlay.Visible = true
	-- Boundary measured from the top: transparent above it (revealed), dark below (cooling).
	local f = math.clamp(1 - remaining / total, 0.0001, 0.9999)
	slot.overlayGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(f, 1),
		NumberSequenceKeypoint.new(f, 0),
		NumberSequenceKeypoint.new(1, 0),
	})
end

local function updateSkillSlot(i: number, char: Model?, now: number): ()
	local slot = skillSlots[i]
	-- An empty slot (no equipped skill, or no character) is hidden entirely.
	if not char then
		slot.frame.Visible = false
		return
	end
	local id = char:GetAttribute("SkillSlot" .. i)
	if type(id) ~= "string" or id == "" then
		slot.frame.Visible = false
		return
	end
	slot.frame.Visible = true

	local info = skillInfo[id]
	slot.nameLabel.Text = if info then info.name else id

	local readyAt = char:GetAttribute(`Skill_{id}_ReadyAt`)
	local total = if info then info.cooldown else 0
	if type(readyAt) == "number" and total > 0 and readyAt > now then
		setCooldown(slot, readyAt - now, total)
		slot.timerLabel.Text = tostring(math.ceil(readyAt - now))
		slot.timerLabel.Visible = true
	else
		clearTiming(slot)
	end
end

local function updateFormSlot(i: number, char: Model?, now: number): ()
	local slot = formSlots[i]
	local entry = formBar[i]
	if not entry or entry.id == "" then
		slot.frame.Visible = false -- empty slot -> hide it
		return
	end
	slot.frame.Visible = true

	local id = entry.id
	local active = char ~= nil and (char:GetAttribute("ActiveForm") == id or char:GetAttribute("ActiveTechnique") == id)

	if active and char then
		slot.stroke.Transparency = 0
		slot.overlay.Visible = false
		local expiresAt = char:GetAttribute(`Ability_{id}_ExpiresAt`)
		if type(expiresAt) == "number" and expiresAt > 0 then
			slot.timerLabel.Text = tostring(math.ceil(math.max(0, expiresAt - now)))
		else
			slot.timerLabel.Text = "ON" -- permanent (max mastery)
		end
		slot.timerLabel.Visible = true
		return
	end

	slot.stroke.Transparency = 1
	local readyAt = if char then char:GetAttribute(`Ability_{id}_ReadyAt`) else nil
	if type(readyAt) == "number" and entry.cooldown > 0 and readyAt > now then
		setCooldown(slot, readyAt - now, entry.cooldown)
		slot.timerLabel.Text = tostring(math.ceil(readyAt - now))
		slot.timerLabel.Visible = true
	else
		clearTiming(slot)
	end
end

RunService.RenderStepped:Connect(function()
	local char = player.Character
	local now = workspace:GetServerTimeNow()
	for i = 1, SKILL_COUNT do
		updateSkillSlot(i, char, now)
	end
	for i = 1, FORM_COUNT do
		updateFormSlot(i, char, now)
	end
	relayout()
end)

refreshKeyLabels()
Keybinds.onChanged(refreshKeyLabels)

-- Refetch names/cooldowns on load and on each spawn (the race -- and so the form line -- can change
-- with a slot switch). The skill loadout itself stays live via the SkillSlot* attributes.
Remotes.ProfileLoaded.OnClientEvent:Connect(fetchData)
player.CharacterAdded:Connect(function()
	task.wait(0.5) -- let the server resolve race + sync loadout attributes first
	fetchData()
end)
task.defer(fetchData)

-- A loadout change from the inventory rearranges the 6-0 row; re-pull so the bar reflects it.
Remotes.FormLoadoutChanged.OnClientEvent:Connect(fetchData)
