--!strict
-- Main Menu UI: a PLAY button and a SLOTS panel. PLAY asks the server to travel the player to their
-- ACTIVE slot's home planet (the server reads + validates the slot's stored Planet -- the client never
-- names a place). The Slots panel lists every slot the player owns -- slot number, race, Battle Power --
-- lets them click one to make it active, and offers "+ New Slot" up to the server's cap. All mutation
-- goes through RemoteFunctions so the server stays authoritative (MenuServer re-validates everything).
--
-- Visibility: gated on MAIN_MENU_ONLY. Off (current default) the buttons show in every place; flip it
-- on to restrict them to the Main Menu lobby -- the client reads the world name the server publishes to
-- ReplicatedStorage ("CurrentWorld"), so no place ids ever reach the client.
--
-- Style + inline builders mirror RaceRollerController / SettingsController so the panels match.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Modules.Remotes)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Flip to true to show PLAY + SLOTS only in the Main Menu lobby (gated on the replicated world name).
local MAIN_MENU_ONLY = false

local PANEL_BG = Color3.fromRGB(26, 27, 33)
local ROW_BG = Color3.fromRGB(40, 42, 51)
local SLOT_BG = Color3.fromRGB(16, 17, 22)
local ACCENT = Color3.fromRGB(255, 176, 32)
local GOOD_COLOR = Color3.fromRGB(120, 220, 130)
local BAD_COLOR = Color3.fromRGB(235, 110, 110)
local TEXT_COLOR = Color3.fromRGB(238, 240, 245)
local TEXT_DIM = Color3.fromRGB(150, 153, 165)

type SlotEntry = { index: number, race: string, battlePower: number, planet: string }
type Roster = {
	activeSlot: number,
	slots: { SlotEntry },
	purchasedSlots: number, -- character slots bought via the Slot dev product
	maxBuyable: number, -- how many slots are buyable in total (Buy button hides once purchasedSlots hits this)
	slotProductId: number, -- the Slot dev product id to prompt (0 if not configured)
}
type SlotResult = { ok: boolean?, error: string?, state: Roster? }
type PlayResult = { ok: boolean?, reason: string?, planet: string? }

-- Live roster, refreshed from the server on open, after each select, and after a slot purchase.
local roster: Roster? = nil
local playing = false -- guards against double-firing Play while a request is in flight
local slotPrice: number? = nil -- Slot product price in Robux, fetched once and cached for the Buy button

-- Forward declarations (handlers below reference these before they're assigned).
local rebuildRows: () -> ()
local selectSlot: (index: number) -> ()
local buySlot: () -> ()
local doPlay: () -> ()

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

-- 12345 -> "12,345" for readable Battle Power.
local function withCommas(n: number): string
	local s = tostring(math.floor(n))
	while true do
		local replaced
		s, replaced = s:gsub("^(%-?%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return s
end

local function raceText(race: string): string
	return if race == "" or race == "NA" then "Unrolled" else race
end

-- Shell ------------------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MainMenuUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 9
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- Right-edge button stack, continuing the column the other panels use (Settings 0.07, Skills 0.13,
-- Race Roll 0.19). Slots opens the panel; Play is the accented primary action just below it.
local slotsButton = Instance.new("TextButton")
slotsButton.Name = "OpenSlots"
slotsButton.AnchorPoint = Vector2.new(0.5, 0.5)
slotsButton.Position = UDim2.fromScale(0.93, 0.25)
slotsButton.Size = UDim2.fromScale(0.1, 0.05)
slotsButton.BackgroundColor3 = PANEL_BG
slotsButton.AutoButtonColor = true
slotsButton.Font = Enum.Font.GothamBold
slotsButton.Text = "Slots"
slotsButton.TextColor3 = TEXT_COLOR
slotsButton.TextScaled = true
constrainText(slotsButton, 8, 20)
corner(slotsButton, 0.3)
stroke(slotsButton, 0.02, ACCENT, 0.2)
slotsButton.Parent = screenGui

local playButton = Instance.new("TextButton")
playButton.Name = "Play"
playButton.AnchorPoint = Vector2.new(0.5, 0.5)
playButton.Position = UDim2.fromScale(0.93, 0.32)
playButton.Size = UDim2.fromScale(0.11, 0.06)
playButton.BackgroundColor3 = ACCENT
playButton.AutoButtonColor = true
playButton.Font = Enum.Font.GothamBold
playButton.Text = "PLAY"
playButton.TextColor3 = Color3.fromRGB(20, 16, 6)
playButton.TextScaled = true
constrainText(playButton, 8, 26)
corner(playButton, 0.3)
playButton.Parent = screenGui

-- A short-lived status line near the buttons.
local toast = makeLabel(screenGui, "", 0.93, 0.385, 0.16, 0.035, Enum.TextXAlignment.Center, 15)
toast.Font = Enum.Font.GothamBold
toast.TextTransparency = 1

-- Slots panel ------------------------------------------------------------------------------------

local panel = Instance.new("Frame")
panel.Name = "SlotsPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromScale(0.46, 0.64)
panel.BackgroundColor3 = PANEL_BG
panel.BackgroundTransparency = 0.05
panel.Visible = false
corner(panel, 0.04)
panel.Parent = screenGui

local title = makeLabel(panel, "YOUR SLOTS", 0.5, 0.07, 0.6, 0.07, Enum.TextXAlignment.Center, 24)
title.Font = Enum.Font.GothamBold
title.TextColor3 = ACCENT

local closeButton = makeButton(panel, "X", 0.93, 0.07, 0.08, 0.06, 18)

local slotList = Instance.new("ScrollingFrame")
slotList.AnchorPoint = Vector2.new(0.5, 0.5)
slotList.Position = UDim2.fromScale(0.5, 0.43)
slotList.Size = UDim2.fromScale(0.9, 0.5)
slotList.BackgroundTransparency = 1
slotList.BorderSizePixel = 0
slotList.ScrollBarThickness = 5
slotList.ScrollBarImageColor3 = ACCENT
slotList.AutomaticCanvasSize = Enum.AutomaticSize.XY
slotList.CanvasSize = UDim2.new(0, 0, 0, 0)
slotList.Parent = panel

local slotLayout = Instance.new("UIListLayout")
slotLayout.FillDirection = Enum.FillDirection.Vertical
slotLayout.SortOrder = Enum.SortOrder.LayoutOrder
slotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
slotLayout.Parent = slotList

-- Redeem-code row: type a code + hit Redeem. Account-wide rewards (Spins/Passes) apply instantly; item
-- rewards are sent to the mailbox. Race-gated codes are rejected here on purpose (the server tells the
-- player to use the in-game Settings box) -- we send source = "MainMenu" so it can make that call.
local codeBox = Instance.new("TextBox")
codeBox.Name = "CodeBox"
codeBox.AnchorPoint = Vector2.new(0.5, 0.5)
codeBox.Position = UDim2.fromScale(0.34, 0.75)
codeBox.Size = UDim2.fromScale(0.56, 0.07)
codeBox.BackgroundColor3 = SLOT_BG
codeBox.ClearTextOnFocus = false
codeBox.Font = Enum.Font.Gotham
codeBox.PlaceholderText = "Enter code"
codeBox.PlaceholderColor3 = TEXT_DIM
codeBox.Text = ""
codeBox.TextColor3 = TEXT_COLOR
codeBox.TextScaled = true
constrainText(codeBox, 8, 16)
corner(codeBox, 0.3)
stroke(codeBox, 0.03, ACCENT, 0.4)
codeBox.Parent = panel

local redeemButton = makeButton(panel, "Redeem", 0.8, 0.75, 0.22, 0.07, 16)
redeemButton.BackgroundColor3 = SLOT_BG
redeemButton.TextColor3 = ACCENT
stroke(redeemButton, 0.03, ACCENT, 0.4)

local codeStatus = makeLabel(panel, "", 0.5, 0.825, 0.86, 0.04, Enum.TextXAlignment.Center, 13)
codeStatus.TextColor3 = TEXT_DIM

local redeeming = false
local function submitCode()
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
	local res = Remotes.RedeemCode:InvokeServer(codeBox.Text, "MainMenu") :: { ok: boolean?, message: string? }?
	redeeming = false
	redeemButton.Text = "Redeem"
	if typeof(res) == "table" then
		local ok = res.ok == true
		codeStatus.Text = res.message or (if ok then "Redeemed!" else "Couldn't redeem")
		codeStatus.TextColor3 = if ok then GOOD_COLOR else BAD_COLOR
		if ok then
			codeBox.Text = ""
		end
	else
		codeStatus.Text = "Couldn't redeem"
		codeStatus.TextColor3 = BAD_COLOR
	end
end

redeemButton.Activated:Connect(submitCode)
codeBox.FocusLost:Connect(function(enterPressed: boolean)
	if enterPressed then
		submitCode()
	end
end)

-- Footer Play button: launches the active slot (same as the corner Play), so you can pick + play here.
local panelPlay = makeButton(panel, "PLAY", 0.5, 0.92, 0.5, 0.1, 26)
panelPlay.BackgroundColor3 = ACCENT
panelPlay.TextColor3 = Color3.fromRGB(20, 16, 6)

-- Toast ------------------------------------------------------------------------------------------

local toastToken = 0
local function showToast(message: string, color: Color3?)
	toast.Text = message
	toast.TextColor3 = color or TEXT_COLOR
	toast.TextTransparency = 0
	toastToken += 1
	local myToken = toastToken
	task.delay(2.4, function()
		if myToken == toastToken then
			toast.TextTransparency = 1
		end
	end)
end

-- Rows -------------------------------------------------------------------------------------------

local function clearRows()
	for _, child in slotList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

-- Fetch the Slot product's live Robux price once, cache it, then rebuild so the Buy button can show it.
local function ensurePrice(productId: number)
	if slotPrice ~= nil or productId <= 0 then
		return
	end
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
		end)
		if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
			slotPrice = info.PriceInRobux
			rebuildRows()
		end
	end)
end

rebuildRows = function()
	clearRows()
	local current = roster
	if not current then
		return
	end

	for _, entry in current.slots do
		local active = entry.index == current.activeSlot
		-- A transparent outer frame is the layout slot; the inner card is shorter, so the empty band
		-- above/below each card is the row gap -- spacing without any UIPadding.
		local outer = Instance.new("Frame")
		outer.Size = UDim2.fromScale(0.98, 0.2)
		outer.BackgroundTransparency = 1
		outer.LayoutOrder = entry.index
		outer.Parent = slotList

		local card = Instance.new("TextButton")
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.Position = UDim2.fromScale(0.5, 0.5)
		card.Size = UDim2.fromScale(1, 0.82)
		card.BackgroundColor3 = ROW_BG
		card.BackgroundTransparency = if active then 0.1 else 0.45
		card.AutoButtonColor = true
		card.Text = ""
		corner(card, 0.18)
		stroke(card, 0.04, ACCENT, if active then 0 else 1)
		card.Parent = outer

		local slotLabel = makeLabel(card, `Slot {entry.index}`, 0.2, 0.5, 0.32, 0.6, Enum.TextXAlignment.Left, 17)
		slotLabel.Font = Enum.Font.GothamBold
		slotLabel.TextColor3 = if active then ACCENT else TEXT_COLOR

		local race = makeLabel(card, raceText(entry.race), 0.52, 0.5, 0.32, 0.55, Enum.TextXAlignment.Center, 15)
		race.TextColor3 = if entry.race == "" or entry.race == "NA" then TEXT_DIM else TEXT_COLOR

		local bp =
			makeLabel(card, `BP {withCommas(entry.battlePower)}`, 0.8, 0.5, 0.3, 0.5, Enum.TextXAlignment.Right, 13)
		bp.TextColor3 = TEXT_DIM

		local idx = entry.index
		card.Activated:Connect(function()
			selectSlot(idx)
		end)
	end

	-- "Buy Slot" while below the buyable cap. Buying is a normal Dev Product purchase; the granted slot
	-- shows up on the roster refresh that PromptProductPurchaseFinished triggers.
	if current.purchasedSlots < current.maxBuyable and current.slotProductId > 0 then
		local outer = Instance.new("Frame")
		outer.Size = UDim2.fromScale(0.98, 0.2)
		outer.BackgroundTransparency = 1
		outer.LayoutOrder = #current.slots + 1
		outer.Parent = slotList

		local buyBtn = Instance.new("TextButton")
		buyBtn.AnchorPoint = Vector2.new(0.5, 0.5)
		buyBtn.Position = UDim2.fromScale(0.5, 0.5)
		buyBtn.Size = UDim2.fromScale(1, 0.82)
		buyBtn.BackgroundColor3 = SLOT_BG
		buyBtn.AutoButtonColor = true
		buyBtn.Font = Enum.Font.GothamBold
		buyBtn.Text = if slotPrice then `Buy Slot · {slotPrice} R$` else "Buy Slot"
		buyBtn.TextColor3 = ACCENT
		buyBtn.TextScaled = true
		constrainText(buyBtn, 8, 16)
		corner(buyBtn, 0.18)
		stroke(buyBtn, 0.03, ACCENT, 0.4)
		buyBtn.Parent = outer
		buyBtn.Activated:Connect(buySlot)

		ensurePrice(current.slotProductId)
	end
end

-- Mutations --------------------------------------------------------------------------------------

selectSlot = function(index: number)
	local res = Remotes.SelectSlot:InvokeServer(index) :: SlotResult?
	if typeof(res) == "table" and res.ok then
		if res.state then
			roster = res.state
		end
		rebuildRows()
	end
end

buySlot = function()
	local current = roster
	if not current or current.slotProductId <= 0 then
		showToast("Slots aren't purchasable right now", BAD_COLOR)
		return
	end
	if current.purchasedSlots >= current.maxBuyable then
		showToast(`You've bought all {current.maxBuyable} extra slots`, BAD_COLOR)
		return
	end
	-- Prompt client-side with the server-provided id (Monetization endorses prompting with the id).
	-- ProcessReceipt grants the slot; the PromptProductPurchaseFinished handler refreshes the panel.
	MarketplaceService:PromptProductPurchase(player, current.slotProductId)
end

doPlay = function()
	if playing then
		return
	end
	playing = true
	showToast("Launching...", ACCENT)
	-- Yields; in a live server the place hops out from under us before this returns. In Studio teleport
	-- is a no-op that returns ok, so we surface that instead of appearing to hang.
	local res = Remotes.RequestPlay:InvokeServer() :: PlayResult?
	if typeof(res) == "table" and res.ok then
		showToast(`Launching to {res.planet or "your planet"}...`, ACCENT)
	else
		local reason = if typeof(res) == "table" then res.reason else nil
		showToast(reason or "Couldn't launch", BAD_COLOR)
	end
	playing = false
end

-- Open / close -----------------------------------------------------------------------------------

local function openSlots()
	local res = Remotes.GetSlots:InvokeServer() :: Roster?
	if typeof(res) ~= "table" then
		showToast("Still loading...", BAD_COLOR)
		return
	end
	roster = res
	rebuildRows()
	panel.Visible = true
end

-- Re-pull the roster without opening the panel (used after a slot purchase); rebuilds if it's open.
local function refreshSlots()
	local res = Remotes.GetSlots:InvokeServer() :: Roster?
	if typeof(res) == "table" then
		roster = res
		if panel.Visible then
			rebuildRows()
		end
	end
end

slotsButton.Activated:Connect(function()
	if panel.Visible then
		panel.Visible = false
	else
		openSlots()
	end
end)

closeButton.Activated:Connect(function()
	panel.Visible = false
end)

playButton.Activated:Connect(doPlay)
panelPlay.Activated:Connect(doPlay)

-- A slot purchase grants server-side in ProcessReceipt, which lands just after this client event fires.
-- Poll the roster until the bought-count ticks up, then reflect the new slot.
MarketplaceService.PromptProductPurchaseFinished:Connect(
	function(_userId: number, productId: number, wasPurchased: boolean)
		local current = roster
		if not wasPurchased or not current or productId ~= current.slotProductId then
			return
		end
		local before = current.purchasedSlots
		task.spawn(function()
			for _ = 1, 10 do
				task.wait(0.5)
				refreshSlots()
				local now = roster
				if now and now.purchasedSlots > before then
					showToast("Slot added!", GOOD_COLOR)
					return
				end
			end
		end)
	end
)

-- Visibility -------------------------------------------------------------------------------------

local function currentWorld(): string?
	local w = ReplicatedStorage:GetAttribute("CurrentWorld")
	return if typeof(w) == "string" then w else nil
end

local function refreshVisibility()
	local show = (not MAIN_MENU_ONLY) or currentWorld() == "MainMenu"
	slotsButton.Visible = show
	playButton.Visible = show
	if not show then
		panel.Visible = false
	end
end

ReplicatedStorage:GetAttributeChangedSignal("CurrentWorld"):Connect(refreshVisibility)
refreshVisibility()
