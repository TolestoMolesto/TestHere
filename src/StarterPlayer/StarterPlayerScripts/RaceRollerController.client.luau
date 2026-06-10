--!strict
-- Race Roller UI: a slot-machine reel that lands on the race the server rolled. Pulls the full panel
-- state from the server on open (Remotes.GetRollState) -- rolls left, total rolls, pity, the race
-- collection, and live global-race availability -- and drives every mutation through a RemoteFunction
-- so the server stays authoritative (RollServer re-validates everything). Rolling acts on the active
-- slot; the new race applies to the body on the next spawn, same as the free join-time auto-roll.
--   * Roll spends one "Roll" (internally Spins). Instant Spin skips the reel animation.
--   * Auto Spin re-rolls until rolls run out, a global lands (always stops), or a targeted race lands
--     (click a collection row to target it). Rerolling a slot that HOLDS a global asks to confirm.
--   * Landing a global drops into a pick-a-base-race prompt (PickRace).
-- Style + inline builders mirror SettingsController / SkillLoadoutController so the panels match.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Modules.Remotes)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PANEL_BG = Color3.fromRGB(26, 27, 33)
local ROW_BG = Color3.fromRGB(40, 42, 51)
local SLOT_BG = Color3.fromRGB(16, 17, 22)
local ACCENT = Color3.fromRGB(255, 176, 32)
local GLOBAL_COLOR = Color3.fromRGB(255, 215, 0)
local GOOD_COLOR = Color3.fromRGB(120, 220, 130)
local BAD_COLOR = Color3.fromRGB(235, 110, 110)
local TEXT_COLOR = Color3.fromRGB(238, 240, 245)
local TEXT_DIM = Color3.fromRGB(150, 153, 165)

-- 3x3 slot machine. Each column is a vertical reel: a clipped window showing REEL_ROWS cells, with a
-- tall strip (STRIP_CELLS symbols) that scrolls up and eases to a stop. The 3 cells that come to rest
-- are LAND_TOP..LAND_TOP+2; the cells past them are overshoot buffer for the bounce. Which of the
-- three rows shows the matching race (the win row) is picked at random each spin.
local REEL_COLS = 3
local REEL_ROWS = 3
local STRIP_CELLS = 18
local LAND_TOP = 13
local SPIN_END = -((LAND_TOP - 1) / REEL_ROWS) -- strip Y (in window heights) that parks LAND_TOP on top
local SPIN_TIMES = { 1.0, 1.35, 1.7 } -- per-column spin duration; columns lock left-to-right
local AUTO_DELAY = 0.35 -- pause between auto-spins

local rng = Random.new()

type Basic = { name: string, unlocked: boolean }
type GlobalAvail = { rolled: number, rolledMax: number, total: number, totalMax: number }
type RollState = {
	slotIndex: number,
	race: string,
	isPendingGlobal: boolean,
	hasGlobal: boolean,
	spins: number,
	rollCount: number,
	pity: number,
	pityGuarantee: number,
	globalChance: number,
	uniformOdds: number,
	basics: { Basic },
	globalNames: { string },
	globals: { [string]: GlobalAvail },
}
type RollResult = {
	ok: boolean,
	needsConfirmation: boolean?,
	error: string?,
	race: string?,
	isPendingGlobal: boolean?,
	spins: number?,
	rollCount: number?,
	pity: number?,
	globalChance: number?,
	globals: { [string]: GlobalAvail }?,
}

-- Live state, refreshed from the server on open and after each mutation.
local slotIndex = 1
local curRace = "NA"
local isPendingGlobal = false
local hasGlobal = false
local spins = 0
local rollCount = 0
local pity = 0
local pityGuarantee = 10000
local globalChance = 0
local uniformOdds = 0
local basics: { Basic } = {}
local globalNames: { string } = {}
local globals: { [string]: GlobalAvail } = {}
local targets: { [string]: boolean? } = {} -- raceName -> true when targeted; cleared back to nil

local autoSpinning = false
local instantSpin = false
local rolling = false -- true while a single reel animation is in flight (blocks overlapping rolls)

-- Forward declarations (handlers below reference these before they're assigned).
local refreshAll: () -> ()
local performRoll: (confirmed: boolean, onResult: ((RollResult?) -> ())?) -> ()
local stopAuto: (status: string?) -> ()

-- Inline builders --------------------------------------------------------------------------------

local function corner(object: Instance, scale: number)
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

local function constrainText(textObject: Instance, minSize: number, maxSize: number)
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
screenGui.Name = "RaceRollerUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 10
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local openButton = Instance.new("TextButton")
openButton.Name = "OpenRoller"
openButton.AnchorPoint = Vector2.new(0.5, 0.5)
openButton.Position = UDim2.fromScale(0.93, 0.19) -- below the Skills button (0.13)
openButton.Size = UDim2.fromScale(0.1, 0.05)
openButton.BackgroundColor3 = PANEL_BG
openButton.AutoButtonColor = true
openButton.Font = Enum.Font.GothamBold
openButton.Text = "Race Roll"
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
panel.Size = UDim2.fromScale(0.62, 0.72)
panel.BackgroundColor3 = PANEL_BG
panel.BackgroundTransparency = 0.05
panel.Visible = false
corner(panel, 0.04)
panel.Parent = screenGui

local title = makeLabel(panel, "RACE ROLLER", 0.5, 0.05, 0.5, 0.06, Enum.TextXAlignment.Center, 24)
title.Font = Enum.Font.GothamBold
title.TextColor3 = ACCENT

local closeButton = makeButton(panel, "X", 0.955, 0.05, 0.05, 0.05, 18)

-- Column frames (transparent) --------------------------------------------------------------------

local function makeColumn(posX: number): Frame
	local col = Instance.new("Frame")
	col.AnchorPoint = Vector2.new(0.5, 0.5)
	col.Position = UDim2.fromScale(posX, 0.56)
	col.Size = UDim2.fromScale(0.32, 0.86)
	col.BackgroundTransparency = 1
	col.Parent = panel
	return col
end

local leftCol = makeColumn(0.18)
local centerCol = makeColumn(0.5)
local rightCol = makeColumn(0.82)

-- Left column: current race + counters + collection ----------------------------------------------

makeLabel(leftCol, "CURRENT", 0.5, 0.03, 0.9, 0.04, Enum.TextXAlignment.Center, 14).TextColor3 = TEXT_DIM
local currentValue = makeLabel(leftCol, "[Slot 1] —", 0.5, 0.085, 0.98, 0.055, Enum.TextXAlignment.Center, 19)
currentValue.Font = Enum.Font.GothamBold

local rollsValue = makeLabel(leftCol, "Rolls: 0", 0.5, 0.16, 0.95, 0.05, Enum.TextXAlignment.Center, 17)
rollsValue.TextColor3 = ACCENT
local totalValue = makeLabel(leftCol, "Total Rolls: 0", 0.5, 0.215, 0.95, 0.04, Enum.TextXAlignment.Center, 14)
totalValue.TextColor3 = TEXT_DIM

makeLabel(leftCol, "RACE COLLECTION", 0.5, 0.275, 0.95, 0.04, Enum.TextXAlignment.Center, 13).TextColor3 = TEXT_DIM

local collection = Instance.new("ScrollingFrame")
collection.AnchorPoint = Vector2.new(0.5, 0.5)
collection.Position = UDim2.fromScale(0.5, 0.66)
collection.Size = UDim2.fromScale(0.98, 0.64)
collection.BackgroundTransparency = 1
collection.BorderSizePixel = 0
collection.ScrollBarThickness = 5
collection.ScrollBarImageColor3 = ACCENT
collection.AutomaticCanvasSize = Enum.AutomaticSize.XY
collection.CanvasSize = UDim2.new(0, 0, 0, 0)
collection.Parent = leftCol

local collectionLayout = Instance.new("UIListLayout")
collectionLayout.FillDirection = Enum.FillDirection.Vertical
collectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
collectionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
collectionLayout.Parent = collection

-- Center column: reels + controls ----------------------------------------------------------------

local reelRow = Instance.new("Frame")
reelRow.AnchorPoint = Vector2.new(0.5, 0.5)
reelRow.Position = UDim2.fromScale(0.5, 0.15)
reelRow.Size = UDim2.fromScale(1, 0.26)
reelRow.BackgroundColor3 = SLOT_BG
reelRow.BackgroundTransparency = 0.3
corner(reelRow, 0.06)
stroke(reelRow, 0.02, ACCENT, 0.4)
reelRow.Parent = centerCol

type Reel = { strip: Frame, cells: { TextLabel } }
local reels: { Reel } = {}
local CELL_GAP = 0.12 -- fraction of each cell left empty, so stacked symbols don't touch

for col = 1, REEL_COLS do
	local window = Instance.new("Frame")
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale((col - 0.5) / REEL_COLS, 0.5)
	window.Size = UDim2.fromScale(0.92 / REEL_COLS, 0.9)
	window.BackgroundColor3 = PANEL_BG
	window.ClipsDescendants = true
	corner(window, 0.1)
	window.Parent = reelRow

	-- The strip is STRIP_CELLS/REEL_ROWS window-heights tall; scrolling its Y from 0 to SPIN_END walks
	-- cells LAND_TOP..LAND_TOP+2 up into the three visible rows.
	local strip = Instance.new("Frame")
	strip.AnchorPoint = Vector2.new(0.5, 0)
	strip.Position = UDim2.fromScale(0.5, 0)
	strip.Size = UDim2.fromScale(1, STRIP_CELLS / REEL_ROWS)
	strip.BackgroundTransparency = 1
	strip.Parent = window

	local cells: { TextLabel } = {}
	for j = 1, STRIP_CELLS do
		local cell = makeLabel(
			strip,
			"?",
			0.5,
			(j - 0.5) / STRIP_CELLS,
			0.92,
			(1 - CELL_GAP) / STRIP_CELLS,
			Enum.TextXAlignment.Center,
			22
		)
		cell.Font = Enum.Font.GothamBold
		cells[j] = cell
	end
	reels[col] = { strip = strip, cells = cells }
end

-- Win line: a glowing outline around the winning row (no fill, so it never hides the text). Moved to
-- the random win row on each spin; hidden while the reels are spinning.
local payline = Instance.new("Frame")
payline.AnchorPoint = Vector2.new(0.5, 0.5)
payline.Position = UDim2.fromScale(0.5, 0.5)
payline.Size = UDim2.fromScale(0.97, 0.9 / REEL_ROWS)
payline.BackgroundTransparency = 1
payline.ZIndex = 5
payline.Visible = false
corner(payline, 0.2)
local paylineStroke = stroke(payline, 0.05, ACCENT, 0)
payline.Parent = reelRow

local statusLabel = makeLabel(centerCol, "Ready to roll!", 0.5, 0.33, 0.96, 0.06, Enum.TextXAlignment.Center, 22)
statusLabel.Font = Enum.Font.GothamBold

local rollButton = makeButton(centerCol, "ROLL", 0.5, 0.45, 0.92, 0.13, 28)
rollButton.BackgroundColor3 = ACCENT
rollButton.TextColor3 = Color3.fromRGB(20, 16, 6)

local instantButton = makeButton(centerCol, "Instant Spin: Off", 0.5, 0.6, 0.92, 0.08, 16)
instantButton.BackgroundColor3 = SLOT_BG
local autoButton = makeButton(centerCol, "Auto Spin: Off", 0.5, 0.71, 0.92, 0.08, 16)
autoButton.BackgroundColor3 = SLOT_BG

local oddsLabel = makeLabel(centerCol, "Global chance: 0.01%", 0.5, 0.81, 0.96, 0.045, Enum.TextXAlignment.Center, 14)
oddsLabel.TextColor3 = TEXT_DIM

local toast = makeLabel(centerCol, "", 0.5, 0.93, 0.98, 0.05, Enum.TextXAlignment.Center, 15)
toast.Font = Enum.Font.GothamBold
toast.TextTransparency = 1

-- Right column: global races + tips --------------------------------------------------------------

makeLabel(rightCol, "GLOBAL RACES", 0.5, 0.04, 0.95, 0.05, Enum.TextXAlignment.Center, 22).Font = Enum.Font.GothamBold

type GlobalRow = { title: TextLabel, avail: TextLabel }
local globalRows: { [string]: GlobalRow } = {}
local GLOBAL_ORDER = { "Angel", "God", "Kai" } -- normalised keys from GlobalRaceRegistry.availability()
for i, key in GLOBAL_ORDER do
	local box = Instance.new("Frame")
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.15 + (i - 1) * 0.18)
	box.Size = UDim2.fromScale(0.96, 0.16)
	box.BackgroundColor3 = SLOT_BG
	box.BackgroundTransparency = 0.3
	corner(box, 0.15)
	box.Parent = rightCol
	local nameLabel = makeLabel(box, key:upper(), 0.5, 0.33, 0.9, 0.44, Enum.TextXAlignment.Center, 24)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextColor3 = GLOBAL_COLOR
	local availLabel = makeLabel(box, "0/4 open", 0.5, 0.75, 0.9, 0.34, Enum.TextXAlignment.Center, 18)
	availLabel.TextColor3 = TEXT_DIM
	globalRows[key] = { title = nameLabel, avail = availLabel }
end

local tips = makeLabel(
	rightCol,
	"Re-rolling removes your global race.\nAuto Spin stops on a global or a targeted race.\nClick a race to target it.",
	0.5,
	0.8,
	0.96,
	0.26,
	Enum.TextXAlignment.Center,
	15
)
tips.TextColor3 = TEXT_DIM
tips.TextWrapped = true
tips.TextYAlignment = Enum.TextYAlignment.Top

-- Overlays: confirm dialog + pick-a-race ---------------------------------------------------------

local function makeOverlay(): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	f.BackgroundTransparency = 0.45
	f.Visible = false
	f.ZIndex = 5
	f.Parent = panel
	return f
end

-- Confirm dialog
local confirmOverlay = makeOverlay()
local confirmCard = Instance.new("Frame")
confirmCard.AnchorPoint = Vector2.new(0.5, 0.5)
confirmCard.Position = UDim2.fromScale(0.5, 0.5)
confirmCard.Size = UDim2.fromScale(0.45, 0.3)
confirmCard.BackgroundColor3 = PANEL_BG
confirmCard.ZIndex = 6
corner(confirmCard, 0.06)
stroke(confirmCard, 0.02, ACCENT, 0.2)
confirmCard.Parent = confirmOverlay
local confirmMsg = makeLabel(confirmCard, "", 0.5, 0.32, 0.9, 0.4, Enum.TextXAlignment.Center, 18)
confirmMsg.TextWrapped = true
confirmMsg.ZIndex = 7
local confirmYes = makeButton(confirmCard, "Reroll anyway", 0.3, 0.75, 0.4, 0.25, 16)
confirmYes.BackgroundColor3 = BAD_COLOR
confirmYes.ZIndex = 7
local confirmNo = makeButton(confirmCard, "Keep it", 0.72, 0.75, 0.4, 0.25, 16)
confirmNo.ZIndex = 7

local pendingConfirm: (() -> ())? = nil
local function showConfirm(message: string, onYes: () -> ())
	confirmMsg.Text = message
	pendingConfirm = onYes
	confirmOverlay.Visible = true
end
confirmYes.Activated:Connect(function()
	confirmOverlay.Visible = false
	local fn = pendingConfirm
	pendingConfirm = nil
	if fn then
		fn()
	end
end)
confirmNo.Activated:Connect(function()
	confirmOverlay.Visible = false
	pendingConfirm = nil
end)

-- Pick-a-base-race prompt (after landing a global)
local pickOverlay = makeOverlay()
local pickCard = Instance.new("Frame")
pickCard.AnchorPoint = Vector2.new(0.5, 0.5)
pickCard.Position = UDim2.fromScale(0.5, 0.5)
pickCard.Size = UDim2.fromScale(0.5, 0.45)
pickCard.BackgroundColor3 = PANEL_BG
pickCard.ZIndex = 6
corner(pickCard, 0.06)
stroke(pickCard, 0.02, GLOBAL_COLOR, 0.1)
pickCard.Parent = pickOverlay
local pickTitle = makeLabel(pickCard, "Choose your base race", 0.5, 0.12, 0.9, 0.14, Enum.TextXAlignment.Center, 20)
pickTitle.Font = Enum.Font.GothamBold
pickTitle.TextColor3 = GLOBAL_COLOR
pickTitle.ZIndex = 7
local pickList = Instance.new("ScrollingFrame")
pickList.AnchorPoint = Vector2.new(0.5, 0.5)
pickList.Position = UDim2.fromScale(0.5, 0.62)
pickList.Size = UDim2.fromScale(0.9, 0.66)
pickList.BackgroundTransparency = 1
pickList.BorderSizePixel = 0
pickList.ScrollBarThickness = 5
pickList.ScrollBarImageColor3 = ACCENT
pickList.AutomaticCanvasSize = Enum.AutomaticSize.XY
pickList.CanvasSize = UDim2.new(0, 0, 0, 0)
pickList.ZIndex = 7
pickList.Parent = pickCard
local pickLayout = Instance.new("UIListLayout")
pickLayout.SortOrder = Enum.SortOrder.LayoutOrder
pickLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
pickLayout.Parent = pickList

-- Toast ------------------------------------------------------------------------------------------

local toastToken = 0
local function showToast(message: string, color: Color3?)
	toast.Text = message
	toast.TextColor3 = color or TEXT_COLOR
	toast.TextTransparency = 0
	toastToken += 1
	local myToken = toastToken
	task.delay(2.2, function()
		if myToken == toastToken then
			toast.TextTransparency = 1
		end
	end)
end

-- Reel animation ---------------------------------------------------------------------------------

local function reelSymbols(): { string }
	local symbols: { string } = {}
	for _, b in basics do
		if b.unlocked then
			table.insert(symbols, b.name)
		end
	end
	for _, g in globalNames do
		table.insert(symbols, g)
	end
	if #symbols == 0 then
		table.insert(symbols, "?")
	end
	return symbols
end

local function isGlobalName(race: string): boolean
	for _, g in globalNames do
		if g == race then
			return true
		end
	end
	return false
end

-- y-centre (in reelRow scale) of a given visible row, for placing the payline outline.
local function paylineY(row: number): number
	return 0.05 + (row - 0.5) * (0.9 / REEL_ROWS)
end

local function spinReels(result: string, instant: boolean, onDone: () -> ())
	local symbols = reelSymbols()
	local winRow = rng:NextInteger(1, REEL_ROWS) -- random top / middle / bottom each spin
	local winColor = if isGlobalName(result) then GLOBAL_COLOR else ACCENT
	local landIndex = LAND_TOP + (winRow - 1)

	-- Reset each reel: copy the 3 parked faces onto cells 1-3 so snapping the strip back to the top
	-- doesn't visibly jump, randomise the rest, then drop `result` onto the win-row landing cell --
	-- same row + same race on all three reels.
	for _, reel in reels do
		local cells = reel.cells
		local keep1, keep2, keep3 = cells[LAND_TOP].Text, cells[LAND_TOP + 1].Text, cells[LAND_TOP + 2].Text
		for j = 1, STRIP_CELLS do
			cells[j].Text = symbols[rng:NextInteger(1, #symbols)]
			cells[j].TextColor3 = TEXT_COLOR
		end
		cells[1].Text, cells[2].Text, cells[3].Text = keep1, keep2, keep3
		cells[landIndex].Text = result
		reel.strip.Position = UDim2.fromScale(0.5, 0)
	end
	payline.Visible = false

	-- Once the reels stop: light the win row, dim the rest, frame the win row with the payline.
	local function settle()
		for _, reel in reels do
			for r = 1, REEL_ROWS do
				reel.cells[LAND_TOP + (r - 1)].TextColor3 = if r == winRow then winColor else TEXT_DIM
			end
		end
		paylineStroke.Color = winColor
		payline.Position = UDim2.fromScale(0.5, paylineY(winRow))
		payline.Visible = true
		onDone()
	end

	if instant then
		for _, reel in reels do
			reel.strip.Position = UDim2.fromScale(0.5, SPIN_END)
		end
		settle()
		return
	end

	-- Each column scrolls up and eases to a stop with a slight overshoot bounce, locking left-to-right.
	local finished = 0
	for col, reel in reels do
		local info = TweenInfo.new(SPIN_TIMES[col] or 1.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local tween = TweenService:Create(reel.strip, info, { Position = UDim2.fromScale(0.5, SPIN_END) })
		tween.Completed:Connect(function()
			finished += 1
			if finished == #reels then
				settle()
			end
		end)
		tween:Play()
	end
end

-- Park the machine on a static frame (panel open): the given race on the middle row, randoms elsewhere.
local function parkReels(race: string)
	local symbols = reelSymbols()
	local winColor = if isGlobalName(race) then GLOBAL_COLOR else ACCENT
	for _, reel in reels do
		for j = 1, STRIP_CELLS do
			reel.cells[j].Text = symbols[rng:NextInteger(1, #symbols)]
			reel.cells[j].TextColor3 = TEXT_DIM
		end
		reel.cells[LAND_TOP + 1].Text = race -- middle landing cell
		for r = 1, REEL_ROWS do
			reel.cells[LAND_TOP + (r - 1)].TextColor3 = if r == 2 then winColor else TEXT_DIM
		end
		reel.strip.Position = UDim2.fromScale(0.5, SPIN_END)
	end
	paylineStroke.Color = winColor
	payline.Position = UDim2.fromScale(0.5, paylineY(2))
	payline.Visible = true
end

-- Collection rows --------------------------------------------------------------------------------

local collectionBuilt = false
local rowRefreshers: { () -> () } = {}

local function buildCollection()
	for i, b in basics do
		-- A transparent outer frame is the layout slot; the inner card is shorter than it, so the
		-- empty band above/below each card is the row gap -- spacing without any UIPadding.
		local outer = Instance.new("Frame")
		outer.Size = UDim2.fromScale(0.97, 0.155)
		outer.BackgroundTransparency = 1
		outer.LayoutOrder = i
		outer.Parent = collection

		local row = Instance.new("TextButton")
		row.AnchorPoint = Vector2.new(0.5, 0.5)
		row.Position = UDim2.fromScale(0.5, 0.5)
		row.Size = UDim2.fromScale(1, 0.82)
		row.BackgroundColor3 = ROW_BG
		row.BackgroundTransparency = 0.35
		row.AutoButtonColor = true
		row.Text = ""
		corner(row, 0.25)
		local rowStroke = stroke(row, 0.03, ACCENT, 1)
		row.Parent = outer

		local nameLabel = makeLabel(row, b.name, 0.34, 0.5, 0.62, 0.6, Enum.TextXAlignment.Left, 16)
		local rowOdds = makeLabel(row, "", 0.8, 0.5, 0.34, 0.55, Enum.TextXAlignment.Right, 13)

		local raceName = b.name
		row.Activated:Connect(function()
			-- Only unlocked races can be targeted for auto-spin.
			local entry: Basic? = nil
			for _, e in basics do
				if e.name == raceName then
					entry = e
					break
				end
			end
			if not entry or not entry.unlocked then
				return
			end
			targets[raceName] = not targets[raceName] or nil
			refreshAll()
		end)

		table.insert(rowRefreshers, function()
			local entry: Basic? = nil
			for _, e in basics do
				if e.name == raceName then
					entry = e
					break
				end
			end
			local unlocked = entry ~= nil and entry.unlocked
			nameLabel.TextColor3 = if unlocked then TEXT_COLOR else TEXT_DIM
			row.BackgroundTransparency = if unlocked then 0.35 else 0.7
			if not unlocked then
				rowOdds.Text = "Locked"
				rowOdds.TextColor3 = TEXT_DIM
				rowStroke.Transparency = 1
			elseif targets[raceName] then
				rowOdds.Text = "Target"
				rowOdds.TextColor3 = ACCENT
				rowStroke.Transparency = 0.1
			else
				rowOdds.Text = string.format("%.1f%%", uniformOdds * 100)
				rowOdds.TextColor3 = TEXT_DIM
				rowStroke.Transparency = 1
			end
		end)
	end
end

-- Refresh ----------------------------------------------------------------------------------------

refreshAll = function()
	local shown = if curRace == "NA" then "—" else curRace
	currentValue.Text = `[Slot {slotIndex}] {shown}`
	currentValue.TextColor3 = if isPendingGlobal then GLOBAL_COLOR else TEXT_COLOR
	rollsValue.Text = `Rolls: {spins}`
	totalValue.Text = `Total Rolls: {rollCount}`
	oddsLabel.Text = string.format("Global chance: %.3f%%  (pity %d/%d)", globalChance * 100, pity, pityGuarantee)

	for _, key in GLOBAL_ORDER do
		local row = globalRows[key]
		if row then
			local a = globals[key]
			if a then
				local open = math.max(0, a.rolledMax - a.rolled)
				row.avail.Text = `{open}/{a.rolledMax} open`
				row.avail.TextColor3 = if open > 0 then GOOD_COLOR else BAD_COLOR
			else
				row.avail.Text = "—"
				row.avail.TextColor3 = TEXT_DIM
			end
		end
	end

	rollButton.Text = if spins > 0 then `ROLL  ({spins})` else "No Rolls"
	instantButton.Text = if instantSpin then "Instant Spin: On" else "Instant Spin: Off"
	instantButton.TextColor3 = if instantSpin then ACCENT else TEXT_COLOR
	autoButton.Text = if autoSpinning then "Auto Spin: On" else "Auto Spin: Off"
	autoButton.TextColor3 = if autoSpinning then ACCENT else TEXT_COLOR

	for _, refresh in rowRefreshers do
		refresh()
	end
end

-- Apply a server roll/pick response onto local state.
local function applyResult(res: RollResult)
	if res.race ~= nil then
		curRace = res.race
	end
	if res.isPendingGlobal ~= nil then
		isPendingGlobal = res.isPendingGlobal
		hasGlobal = res.isPendingGlobal -- a freshly-claimed/pending global is the only one a roll can leave
	end
	if res.spins ~= nil then
		spins = res.spins
	end
	if res.rollCount ~= nil then
		rollCount = res.rollCount
	end
	if res.pity ~= nil then
		pity = res.pity
	end
	if res.globalChance ~= nil then
		globalChance = res.globalChance
	end
	if res.globals ~= nil then
		globals = res.globals
	end
end

-- Pick-a-race prompt -----------------------------------------------------------------------------

local function clearPickButtons()
	for _, child in pickList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function hidePick()
	pickOverlay.Visible = false
	clearPickButtons()
end

local function showPick(globalName: string)
	pickTitle.Text = `{globalName}! Choose your base race`
	clearPickButtons()
	local order = 0
	for _, b in basics do
		if b.unlocked then
			order += 1
			-- Spacer-frame layout (no padding): transparent slot, shorter inner button = the gap.
			local outer = Instance.new("Frame")
			outer.Size = UDim2.fromScale(0.96, 0.22)
			outer.BackgroundTransparency = 1
			outer.LayoutOrder = order
			outer.ZIndex = 7
			outer.Parent = pickList

			local btn = Instance.new("TextButton")
			btn.AnchorPoint = Vector2.new(0.5, 0.5)
			btn.Position = UDim2.fromScale(0.5, 0.5)
			btn.Size = UDim2.fromScale(1, 0.82)
			btn.BackgroundColor3 = ROW_BG
			btn.AutoButtonColor = true
			btn.Font = Enum.Font.GothamBold
			btn.Text = b.name
			btn.TextColor3 = TEXT_COLOR
			btn.TextScaled = true
			btn.ZIndex = 7
			constrainText(btn, 8, 18)
			corner(btn, 0.25)
			btn.Parent = outer
			local chosen = b.name
			btn.Activated:Connect(function()
				local res = Remotes.PickRace:InvokeServer(chosen) :: RollResult?
				if typeof(res) == "table" and res.ok then
					applyResult(res)
					isPendingGlobal = false
					hasGlobal = true
					statusLabel.Text = `{globalName} {chosen}!`
					statusLabel.TextColor3 = GLOBAL_COLOR
					showToast(`Claimed {globalName} ({chosen})`, GLOBAL_COLOR)
					hidePick()
					refreshAll()
				else
					local err = if typeof(res) == "table" then res.error else nil
					showToast(`Could not claim: {err or "try another"}`, BAD_COLOR)
				end
			end)
		end
	end
	pickOverlay.Visible = true
end

-- Rolling --------------------------------------------------------------------------------------

local function errorText(code: string?): string
	if code == "no_spins" then
		return "Out of rolls!"
	elseif code == "no_profile" then
		return "Still loading..."
	end
	return "Roll failed"
end

performRoll = function(confirmed: boolean, onResult: ((RollResult?) -> ())?)
	if rolling then
		return
	end
	rolling = true
	local res = Remotes.RollSlot:InvokeServer(confirmed) :: RollResult?
	if typeof(res) ~= "table" then
		rolling = false
		if onResult then
			onResult(nil)
		end
		return
	end
	local result = res :: RollResult
	if result.needsConfirmation then
		rolling = false
		showConfirm("Rerolling will destroy your global race. Reroll anyway?", function()
			performRoll(true, onResult)
		end)
		return
	end
	if not result.ok then
		rolling = false
		statusLabel.Text = errorText(result.error)
		statusLabel.TextColor3 = BAD_COLOR
		refreshAll()
		if onResult then
			onResult(result)
		end
		return
	end
	applyResult(result)
	statusLabel.Text = "Rolling..."
	statusLabel.TextColor3 = TEXT_COLOR
	refreshAll()
	local landed = result.race or "?"
	spinReels(landed, instantSpin, function()
		rolling = false
		if result.isPendingGlobal then
			statusLabel.Text = `Global! ({landed})`
			statusLabel.TextColor3 = GLOBAL_COLOR
		else
			statusLabel.Text = landed
			statusLabel.TextColor3 = TEXT_COLOR
		end
		refreshAll()
		if result.isPendingGlobal then
			showPick(landed)
		end
		if onResult then
			onResult(result)
		end
	end)
end

-- Auto-spin --------------------------------------------------------------------------------------

local autoToken = 0

stopAuto = function(status: string?)
	autoSpinning = false
	autoToken += 1
	if status then
		showToast(status, ACCENT)
	end
	refreshAll()
end

local function autoStep(myToken: number)
	if not autoSpinning or myToken ~= autoToken then
		return
	end
	if spins <= 0 then
		stopAuto("Out of rolls")
		return
	end
	-- hasGlobal is only true on the first step (we confirmed before starting); pass it through so the
	-- destructive reroll is authorised without a second dialog.
	performRoll(hasGlobal, function(res)
		if not autoSpinning or myToken ~= autoToken then
			return
		end
		if not res or not res.ok then
			stopAuto()
			return
		end
		if res.isPendingGlobal then
			stopAuto("Global landed!")
			return
		end
		if res.race and targets[res.race] then
			stopAuto(`Target: {res.race}!`)
			return
		end
		task.delay(AUTO_DELAY, function()
			autoStep(myToken)
		end)
	end)
end

local function startAuto()
	if autoSpinning then
		return
	end
	if spins <= 0 then
		showToast("Out of rolls", BAD_COLOR)
		return
	end
	autoSpinning = true
	autoToken += 1
	refreshAll()
	autoStep(autoToken)
end

-- Wiring -----------------------------------------------------------------------------------------

rollButton.Activated:Connect(function()
	if autoSpinning then
		return
	end
	performRoll(false, nil)
end)

instantButton.Activated:Connect(function()
	instantSpin = not instantSpin
	refreshAll()
end)

autoButton.Activated:Connect(function()
	if autoSpinning then
		stopAuto("Auto Spin stopped")
		return
	end
	if hasGlobal then
		showConfirm("Auto Spin will reroll away your global race. Continue?", startAuto)
	else
		startAuto()
	end
end)

-- Open / close -----------------------------------------------------------------------------------

local function openPanel()
	local state = Remotes.GetRollState:InvokeServer() :: RollState?
	if typeof(state) == "table" then
		local s = state :: RollState
		slotIndex = s.slotIndex
		curRace = s.race
		isPendingGlobal = s.isPendingGlobal
		hasGlobal = s.hasGlobal
		spins = s.spins
		rollCount = s.rollCount
		pity = s.pity
		pityGuarantee = s.pityGuarantee
		globalChance = s.globalChance
		uniformOdds = s.uniformOdds
		basics = s.basics
		globalNames = s.globalNames
		globals = s.globals
	end
	if not collectionBuilt and #basics > 0 then
		buildCollection()
		collectionBuilt = true
	end
	statusLabel.Text = if isPendingGlobal then `Global pending: {curRace}` else "Ready to roll!"
	statusLabel.TextColor3 = if isPendingGlobal then GLOBAL_COLOR else TEXT_COLOR
	-- Park the reels on the current race so the panel doesn't open mid-spin.
	parkReels(if curRace == "NA" then "?" else curRace)
	refreshAll()
	if isPendingGlobal then
		showPick(curRace)
	end
	panel.Visible = true
end

openButton.Activated:Connect(function()
	if panel.Visible then
		stopAuto()
		panel.Visible = false
	else
		openPanel()
	end
end)

closeButton.Activated:Connect(function()
	stopAuto()
	panel.Visible = false
end)
