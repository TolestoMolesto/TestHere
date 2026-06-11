--!strict
-- Party + Training hub: one tabbed panel (matching the Inventory/Settings shell) with two tabs.
--   * Party    -- your roster (a leader + up to 5 others) + Leave/Disband, and a player list to invite.
--   * Training -- challenge any player in the server to a spar (consensual 1v1 duel), plus the rules.
-- Opened with the Party key (default P) or the on-screen button. Also drives the incoming party-invite
-- prompt and party toasts. Pure UI -- every action is validated server-side (PartyServer/SparServer);
-- the spar bout HUD + challenge prompt live in SparController. Style/builders mirror InventoryController
-- (Scale-only, AnchorPoint 0.5, no padding, TextScaled + UITextSizeConstraint, scaled UIStroke,
-- ScrollingFrame AutomaticCanvasSize).

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
local GOOD = Color3.fromRGB(120, 220, 130)
local BAD = Color3.fromRGB(235, 110, 110)

-- Inline builders (mirror InventoryController) --------------------------------------------------

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

-- A list row: transparent full-width wrapper + an inset card (gaps come from the inset, not padding).
local function makeRow(parent: Instance, index: number): (Frame, Frame)
	local wrapper = Instance.new("Frame")
	wrapper.BackgroundTransparency = 1
	wrapper.Size = UDim2.fromScale(1, 0.2)
	wrapper.LayoutOrder = index
	wrapper.Parent = parent

	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(0.98, 0.82)
	card.BackgroundColor3 = ROW_BG
	corner(card, 0.25)
	card.Parent = wrapper

	return wrapper, card
end

local function makeScroller(parent: Instance, posY: number, sizeY: number): ScrollingFrame
	local scroller = Instance.new("ScrollingFrame")
	scroller.AnchorPoint = Vector2.new(0.5, 0.5)
	scroller.Position = UDim2.fromScale(0.5, posY)
	scroller.Size = UDim2.fromScale(0.99, sizeY)
	scroller.BackgroundColor3 = SLOT_BG
	scroller.BackgroundTransparency = 0.4
	scroller.BorderSizePixel = 0
	scroller.ScrollBarThickness = 6
	scroller.ScrollBarImageColor3 = ACCENT
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.XY
	scroller.CanvasSize = UDim2.new(0, 0, 0, 0)
	corner(scroller, 0.03)
	scroller.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = scroller

	return scroller
end

-- Shell ------------------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PartyUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 10
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local openButton = Instance.new("TextButton")
openButton.Name = "OpenParty"
openButton.AnchorPoint = Vector2.new(0.5, 0.5)
openButton.Position = UDim2.fromScale(0.93, 0.38) -- below the Play button (0.32)
openButton.Size = UDim2.fromScale(0.1, 0.05)
openButton.BackgroundColor3 = PANEL_BG
openButton.AutoButtonColor = true
openButton.Font = Enum.Font.GothamBold
openButton.Text = "Party"
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

local title = makeLabel(panel, "Party", 0.5, 0.05, 0.6, 0.07, Enum.TextXAlignment.Center, 26)
title.Font = Enum.Font.GothamBold

local closeButton = makeButton(panel, "X", 0.95, 0.05, 0.06, 0.05, 20)

local tabBar = Instance.new("Frame")
tabBar.AnchorPoint = Vector2.new(0.5, 0.5)
tabBar.Position = UDim2.fromScale(0.5, 0.12)
tabBar.Size = UDim2.fromScale(0.44, 0.06)
tabBar.BackgroundTransparency = 1
tabBar.Parent = panel

local partyTabButton = makeButton(tabBar, "Party", 0.255, 0.5, 0.49, 1, 18)
local trainingTabButton = makeButton(tabBar, "Training", 0.745, 0.5, 0.49, 1, 18)
-- Gravity tab button (Kai-only); applyTabLayout positions/hides it once GetWeightGrant resolves.
local gravityTabButton = makeButton(tabBar, "Gravity", 0.83, 0.5, 0.32, 1, 18)
gravityTabButton.Visible = false

local partyContent = Instance.new("Frame")
partyContent.Name = "PartyTab"
partyContent.AnchorPoint = Vector2.new(0.5, 0.5)
partyContent.Position = UDim2.fromScale(0.5, 0.57)
partyContent.Size = UDim2.fromScale(0.96, 0.82)
partyContent.BackgroundTransparency = 1
partyContent.Parent = panel

local trainingContent = Instance.new("Frame")
trainingContent.Name = "TrainingTab"
trainingContent.AnchorPoint = Vector2.new(0.5, 0.5)
trainingContent.Position = UDim2.fromScale(0.5, 0.57)
trainingContent.Size = UDim2.fromScale(0.96, 0.82)
trainingContent.BackgroundTransparency = 1
trainingContent.Visible = false
trainingContent.Parent = panel

local gravityContent = Instance.new("Frame")
gravityContent.Name = "GravityTab"
gravityContent.AnchorPoint = Vector2.new(0.5, 0.5)
gravityContent.Position = UDim2.fromScale(0.5, 0.57)
gravityContent.Size = UDim2.fromScale(0.96, 0.82)
gravityContent.BackgroundTransparency = 1
gravityContent.Visible = false
gravityContent.Parent = panel

local toast = makeLabel(panel, "", 0.5, 0.965, 0.96, 0.04, Enum.TextXAlignment.Center, 15)
toast.Font = Enum.Font.GothamBold
toast.TextTransparency = 1

-- Party tab ------------------------------------------------------------------------------------

makeLabel(partyContent, "Your Party", 0.5, 0.035, 0.9, 0.06, Enum.TextXAlignment.Left, 16).TextColor3 = ACCENT

local rosterScroller = makeScroller(partyContent, 0.23, 0.34)

local emptyParty = makeLabel(
	partyContent,
	"You're not in a party.\nInvite someone below to start one.",
	0.5,
	0.23,
	0.8,
	0.12,
	Enum.TextXAlignment.Center,
	15
)
emptyParty.TextColor3 = TEXT_DIM
emptyParty.TextWrapped = true

local leaveButton = makeButton(partyContent, "Leave Party", 0.28, 0.47, 0.34, 0.07, 16)
leaveButton.BackgroundColor3 = SLOT_BG
leaveButton.Visible = false

local disbandButton = makeButton(partyContent, "Disband", 0.72, 0.47, 0.34, 0.07, 16)
disbandButton.BackgroundColor3 = SLOT_BG
disbandButton.Visible = false

makeLabel(partyContent, "Players", 0.5, 0.57, 0.9, 0.06, Enum.TextXAlignment.Left, 16).TextColor3 = ACCENT

local inviteScroller = makeScroller(partyContent, 0.8, 0.36)

local emptyInvite =
	makeLabel(partyContent, "No one else is here yet.", 0.5, 0.8, 0.8, 0.05, Enum.TextXAlignment.Center, 15)
emptyInvite.TextColor3 = TEXT_DIM

-- Training tab ---------------------------------------------------------------------------------

makeLabel(trainingContent, "Challenge a Spar", 0.5, 0.035, 0.9, 0.06, Enum.TextXAlignment.Left, 16).TextColor3 = ACCENT

local blurb = makeLabel(
	trainingContent,
	"A friendly 1v1 -- no combat tag, and downing your opponent fully restores them (first down wins). "
		.. "If anyone else attacks either fighter, the spar cancels and you both revert to how you started.",
	0.5,
	0.17,
	0.96,
	0.16,
	Enum.TextXAlignment.Left,
	13
)
blurb.TextColor3 = TEXT_DIM
blurb.TextWrapped = true
blurb.TextYAlignment = Enum.TextYAlignment.Top

makeLabel(trainingContent, "Players", 0.5, 0.3, 0.9, 0.06, Enum.TextXAlignment.Left, 16).TextColor3 = ACCENT

local challengeScroller = makeScroller(trainingContent, 0.66, 0.62)

local emptyChallenge =
	makeLabel(trainingContent, "No one else is here to spar.", 0.5, 0.66, 0.8, 0.05, Enum.TextXAlignment.Center, 15)
emptyChallenge.TextColor3 = TEXT_DIM

-- Gravity tab (Kai-only): equip weights on party members, capped at the local Kai's gravity mastery ---

makeLabel(gravityContent, "Weight Training", 0.5, 0.035, 0.9, 0.06, Enum.TextXAlignment.Left, 16).TextColor3 = ACCENT

local gravityBlurb = makeLabel(
	gravityContent,
	"Equip training weights on your party, up to your gravity mastery. Heavier weights train faster -- "
		.. "so a training partner doesn't need their own.",
	0.5,
	0.155,
	0.96,
	0.12,
	Enum.TextXAlignment.Left,
	13
)
gravityBlurb.TextColor3 = TEXT_DIM
gravityBlurb.TextWrapped = true
gravityBlurb.TextYAlignment = Enum.TextYAlignment.Top

local tonnageValueLabel = makeLabel(gravityContent, "1t", 0.5, 0.31, 0.24, 0.06, Enum.TextXAlignment.Center, 22)
tonnageValueLabel.Font = Enum.Font.GothamBold
tonnageValueLabel.TextColor3 = ACCENT

local tonnageMinus1 = makeButton(gravityContent, "-1", 0.1, 0.31, 0.13, 0.06, 14)
tonnageMinus1.BackgroundColor3 = SLOT_BG
local tonnageMinusQ = makeButton(gravityContent, "-0.25", 0.26, 0.31, 0.13, 0.06, 13)
tonnageMinusQ.BackgroundColor3 = SLOT_BG
local tonnagePlusQ = makeButton(gravityContent, "+0.25", 0.74, 0.31, 0.13, 0.06, 13)
tonnagePlusQ.BackgroundColor3 = SLOT_BG
local tonnagePlus1 = makeButton(gravityContent, "+1", 0.9, 0.31, 0.13, 0.06, 14)
tonnagePlus1.BackgroundColor3 = SLOT_BG

makeLabel(gravityContent, "Party", 0.5, 0.42, 0.9, 0.06, Enum.TextXAlignment.Left, 16).TextColor3 = ACCENT

local gravityScroller = makeScroller(gravityContent, 0.72, 0.5)

local gravityEmpty = makeLabel(
	gravityContent,
	"Invite party members to weight them.",
	0.5,
	0.72,
	0.8,
	0.05,
	Enum.TextXAlignment.Center,
	15
)
gravityEmpty.TextColor3 = TEXT_DIM

-- Incoming party-invite confirm overlay --------------------------------------------------------

local overlay = Instance.new("Frame")
overlay.Name = "InvitePrompt"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.5
overlay.Visible = false
overlay.ZIndex = 50
overlay.Parent = screenGui

local promptCard = Instance.new("Frame")
promptCard.AnchorPoint = Vector2.new(0.5, 0.5)
promptCard.Position = UDim2.fromScale(0.5, 0.5)
promptCard.Size = UDim2.fromScale(0.32, 0.2)
promptCard.BackgroundColor3 = PANEL_BG
promptCard.ZIndex = 51
corner(promptCard, 0.06)
stroke(promptCard, 0.02, ACCENT, 0.2)
promptCard.Parent = overlay

local promptMsg = makeLabel(promptCard, "", 0.5, 0.32, 0.9, 0.4, Enum.TextXAlignment.Center, 18)
promptMsg.TextWrapped = true
promptMsg.ZIndex = 52

local promptYes = makeButton(promptCard, "Accept", 0.3, 0.76, 0.42, 0.26, 16)
promptYes.BackgroundColor3 = GOOD
promptYes.TextColor3 = Color3.fromRGB(20, 30, 22)
promptYes.ZIndex = 52

local promptNo = makeButton(promptCard, "Decline", 0.72, 0.76, 0.42, 0.26, 16)
promptNo.BackgroundColor3 = BAD
promptNo.ZIndex = 52

local pendingYes: (() -> ())? = nil
local pendingNo: (() -> ())? = nil

local function showPrompt(message: string, onYes: () -> (), onNo: () -> ()): ()
	promptMsg.Text = message
	pendingYes = onYes
	pendingNo = onNo
	overlay.Visible = true
end

promptYes.Activated:Connect(function()
	overlay.Visible = false
	local fn = pendingYes
	pendingYes, pendingNo = nil, nil
	if fn then
		fn()
	end
end)

promptNo.Activated:Connect(function()
	overlay.Visible = false
	local fn = pendingNo
	pendingYes, pendingNo = nil, nil
	if fn then
		fn()
	end
end)

-- Toast ----------------------------------------------------------------------------------------

local toastToken = 0
local function showToast(message: string, color: Color3?): ()
	toast.Text = message
	toast.TextColor3 = color or TEXT_COLOR
	toast.TextTransparency = 0
	toastToken += 1
	local myToken = toastToken
	task.delay(2.6, function()
		if myToken == toastToken then
			toast.TextTransparency = 1
		end
	end)
end

-- Rendering ------------------------------------------------------------------------------------

local roster: any = nil
local rosterRows: { Instance } = {}
local inviteRows: { Instance } = {}
local challengeRows: { Instance } = {}

local function clearRows(rows: { Instance }): ()
	for _, row in rows do
		row:Destroy()
	end
	table.clear(rows)
end

local function bpOf(target: Player): number
	local character = target.Character
	if not character then
		return 0
	end
	return (character:GetAttribute("BattlePower") :: number?) or 0
end

local function makeRosterRow(member: any, index: number, isLeader: boolean): ()
	local isYou = member.userId == player.UserId
	local isMemberLeader = member.userId == roster.leaderUserId
	local wrapper, card = makeRow(rosterScroller, index)
	table.insert(rosterRows, wrapper)

	local name = member.displayName
	if isMemberLeader then
		name ..= "  (Leader)"
	end
	if isYou then
		name ..= "  (You)"
	end
	local nameLabel = makeLabel(card, name, 0.31, 0.5, 0.58, 0.6, Enum.TextXAlignment.Left, 16)
	if isMemberLeader then
		nameLabel.TextColor3 = ACCENT
	end

	-- The leader can promote/kick anyone but themselves; everyone else just sees the member's BP.
	if isLeader and not isYou then
		local promote = makeButton(card, "Promote", 0.69, 0.5, 0.2, 0.66, 14)
		promote.BackgroundColor3 = SLOT_BG
		promote.Activated:Connect(function()
			local target = Players:GetPlayerByUserId(member.userId)
			if target then
				Remotes.PromoteLeader:FireServer(target)
			end
		end)
		local kick = makeButton(card, "Kick", 0.9, 0.5, 0.18, 0.66, 14)
		kick.BackgroundColor3 = SLOT_BG
		kick.TextColor3 = BAD
		kick.Activated:Connect(function()
			local target = Players:GetPlayerByUserId(member.userId)
			if target then
				Remotes.KickFromParty:FireServer(target)
			end
		end)
	else
		local target = Players:GetPlayerByUserId(member.userId)
		local bp = if target then bpOf(target) else 0
		local bpLabel = makeLabel(card, `BP {math.floor(bp)}`, 0.82, 0.5, 0.34, 0.5, Enum.TextXAlignment.Right, 14)
		bpLabel.TextColor3 = TEXT_DIM
	end
end

local function renderRoster(): ()
	clearRows(rosterRows)
	local members = if roster then roster.members else nil
	if not members or #members == 0 then
		emptyParty.Visible = true
		leaveButton.Visible = false
		disbandButton.Visible = false
		return
	end
	emptyParty.Visible = false
	local isLeader = roster.leaderUserId == player.UserId
	for i, member in members do
		makeRosterRow(member, i, isLeader)
	end
	leaveButton.Visible = true
	disbandButton.Visible = isLeader
end

-- Build a player list (other players in the server) into `scroller`, each row with one action button.
-- `skip` excludes user ids (e.g. current party members from the invite list).
local function buildPlayerList(
	scroller: ScrollingFrame,
	rows: { Instance },
	emptyLabel: TextLabel,
	actionText: string,
	actionColor: Color3?,
	skip: { [number]: boolean }?,
	onAction: (Player) -> ()
): ()
	clearRows(rows)
	local others: { Player } = {}
	for _, p in Players:GetPlayers() do
		if p ~= player and not (skip and skip[p.UserId]) then
			table.insert(others, p)
		end
	end
	emptyLabel.Visible = #others == 0
	for i, target in others do
		local wrapper, card = makeRow(scroller, i)
		table.insert(rows, wrapper)
		makeLabel(card, target.DisplayName, 0.3, 0.5, 0.54, 0.6, Enum.TextXAlignment.Left, 16)
		local btn = makeButton(card, actionText, 0.83, 0.5, 0.28, 0.66, 14)
		btn.BackgroundColor3 = SLOT_BG
		if actionColor then
			btn.TextColor3 = actionColor
		end
		btn.Activated:Connect(function()
			onAction(target)
		end)
	end
end

local function renderPlayers(): ()
	local memberSet: { [number]: boolean } = {}
	if roster and roster.members then
		for _, m in roster.members do
			memberSet[m.userId] = true
		end
	end
	buildPlayerList(inviteScroller, inviteRows, emptyInvite, "Invite", nil, memberSet, function(target)
		Remotes.RequestPartyInvite:FireServer(target)
	end)
	buildPlayerList(challengeScroller, challengeRows, emptyChallenge, "Spar", ACCENT, nil, function(target)
		Remotes.RequestSpar:FireServer(target)
	end)
end

-- Gravity tab state + rendering (Kai-only) -----------------------------------------------------

local WEIGHT_MIN = 0.25
local canGrant = false
local weightCap = 0
local selectedTonnage = 1

local gravityRows: { Instance } = {}
local gravityConns: { RBXScriptConnection } = {}

local function fmtTons(n: number): string
	local s = string.format("%.2f", n):gsub("%.?0+$", "")
	return s .. "t"
end

local function weightOf(target: Player?): number
	local character = if target then target.Character else nil
	if not character then
		return 0
	end
	local w = character:GetAttribute("Weight")
	return if type(w) == "number" and w > 0 then w else 0
end

local function setTonnage(delta: number): ()
	selectedTonnage = math.clamp(selectedTonnage + delta, WEIGHT_MIN, math.max(weightCap, WEIGHT_MIN))
	tonnageValueLabel.Text = fmtTons(selectedTonnage)
end

local function clearGravity(): ()
	for _, row in gravityRows do
		row:Destroy()
	end
	for _, c in gravityConns do
		c:Disconnect()
	end
	table.clear(gravityRows)
	table.clear(gravityConns)
end

local function renderGravity(): ()
	tonnageValueLabel.Text = fmtTons(selectedTonnage)
	clearGravity()

	-- The Kai themselves first, then the rest of the party -- a Kai can weight their own character too
	-- (capped at their mastery, like everyone else), and the tab still works solo with just their row.
	local entries: { any } = { { userId = player.UserId, displayName = player.DisplayName } }
	if roster and roster.members then
		for _, m in roster.members do
			if m.userId ~= player.UserId then
				table.insert(entries, m)
			end
		end
	end
	gravityEmpty.Visible = false

	for i, m in entries do
		local userId = m.userId
		local wrapper, card = makeRow(gravityScroller, i)
		table.insert(gravityRows, wrapper)
		local rowName = if userId == player.UserId then m.displayName .. "  (You)" else m.displayName
		makeLabel(card, rowName, 0.26, 0.5, 0.42, 0.6, Enum.TextXAlignment.Left, 15)

		local curLabel = makeLabel(card, "", 0.55, 0.5, 0.2, 0.5, Enum.TextXAlignment.Center, 13)
		curLabel.TextColor3 = TEXT_DIM
		local function refreshCur(): ()
			local w = weightOf(Players:GetPlayerByUserId(userId))
			curLabel.Text = if w > 0 then fmtTons(w) else "--"
		end
		refreshCur()

		local equip = makeButton(card, "Equip", 0.78, 0.5, 0.2, 0.66, 13)
		equip.BackgroundColor3 = SLOT_BG
		equip.TextColor3 = GOOD
		equip.Activated:Connect(function()
			local target = Players:GetPlayerByUserId(userId)
			if target then
				Remotes.SetMemberWeight:FireServer(target, selectedTonnage)
			end
		end)

		local off = makeButton(card, "Off", 0.95, 0.5, 0.12, 0.66, 12)
		off.BackgroundColor3 = SLOT_BG
		off.TextColor3 = BAD
		off.Activated:Connect(function()
			local target = Players:GetPlayerByUserId(userId)
			if target then
				Remotes.SetMemberWeight:FireServer(target, 0)
			end
		end)

		local liveTarget = Players:GetPlayerByUserId(userId)
		if liveTarget and liveTarget.Character then
			table.insert(gravityConns, liveTarget.Character:GetAttributeChangedSignal("Weight"):Connect(refreshCur))
		end
	end
end

local function applyTabLayout(showGravity: boolean): ()
	gravityTabButton.Visible = showGravity
	if showGravity then
		tabBar.Size = UDim2.fromScale(0.62, 0.06)
		partyTabButton.Position = UDim2.fromScale(0.17, 0.5)
		partyTabButton.Size = UDim2.fromScale(0.32, 1)
		trainingTabButton.Position = UDim2.fromScale(0.5, 0.5)
		trainingTabButton.Size = UDim2.fromScale(0.32, 1)
		gravityTabButton.Position = UDim2.fromScale(0.83, 0.5)
		gravityTabButton.Size = UDim2.fromScale(0.32, 1)
	else
		tabBar.Size = UDim2.fromScale(0.44, 0.06)
		partyTabButton.Position = UDim2.fromScale(0.255, 0.5)
		partyTabButton.Size = UDim2.fromScale(0.49, 1)
		trainingTabButton.Position = UDim2.fromScale(0.745, 0.5)
		trainingTabButton.Size = UDim2.fromScale(0.49, 1)
	end
end

-- Tabs + open/close ----------------------------------------------------------------------------

local function setTab(tab: string): ()
	partyContent.Visible = tab == "party"
	trainingContent.Visible = tab == "training"
	gravityContent.Visible = tab == "gravity"
	local function style(button: TextButton, active: boolean): ()
		button.BackgroundColor3 = if active then ROW_BG else TAB_INACTIVE
		button.TextColor3 = if active then ACCENT else TEXT_DIM
	end
	style(partyTabButton, tab == "party")
	style(trainingTabButton, tab == "training")
	style(gravityTabButton, tab == "gravity")
	if tab == "gravity" then
		renderGravity()
	end
end

local function openPanel(): ()
	roster = Remotes.GetParty:InvokeServer()
	local grant = Remotes.GetWeightGrant:InvokeServer()
	canGrant = grant ~= nil and grant.allowed == true
	weightCap = if grant and type(grant.cap) == "number" then grant.cap else 0
	selectedTonnage = math.clamp(selectedTonnage, WEIGHT_MIN, math.max(weightCap, WEIGHT_MIN))
	applyTabLayout(canGrant)
	if not canGrant and gravityContent.Visible then
		setTab("party")
	end
	renderRoster()
	renderPlayers()
	if gravityContent.Visible then
		renderGravity()
	end
	panel.Visible = true
end

local function togglePanel(): ()
	if panel.Visible then
		panel.Visible = false
	else
		openPanel()
	end
end

partyTabButton.Activated:Connect(function()
	setTab("party")
end)
trainingTabButton.Activated:Connect(function()
	setTab("training")
end)
gravityTabButton.Activated:Connect(function()
	setTab("gravity")
end)
tonnageMinus1.Activated:Connect(function()
	setTonnage(-1)
end)
tonnageMinusQ.Activated:Connect(function()
	setTonnage(-0.25)
end)
tonnagePlusQ.Activated:Connect(function()
	setTonnage(0.25)
end)
tonnagePlus1.Activated:Connect(function()
	setTonnage(1)
end)
openButton.Activated:Connect(togglePanel)
closeButton.Activated:Connect(function()
	panel.Visible = false
end)
leaveButton.Activated:Connect(function()
	Remotes.LeaveParty:FireServer()
end)
disbandButton.Activated:Connect(function()
	Remotes.DisbandParty:FireServer()
end)

Remotes.PartyUpdated.OnClientEvent:Connect(function(newRoster: any)
	roster = newRoster
	renderRoster()
	if panel.Visible then
		renderPlayers()
		if gravityContent.Visible then
			renderGravity()
		end
	end
end)

Remotes.PartyNotice.OnClientEvent:Connect(function(message: string)
	showToast(message, ACCENT)
end)

Remotes.PartyInviteReceived.OnClientEvent:Connect(function(fromDisplayName: string, _fromUserId: number)
	showPrompt(`{fromDisplayName} invited you to their party.`, function()
		Remotes.RespondPartyInvite:FireServer(true)
	end, function()
		Remotes.RespondPartyInvite:FireServer(false)
	end)
end)

-- Keep both player lists fresh while the panel is open.
local function onRosterChange(): ()
	if panel.Visible then
		renderPlayers()
		if gravityContent.Visible then
			renderGravity()
		end
	end
end
Players.PlayerAdded:Connect(onRosterChange)
Players.PlayerRemoving:Connect(onRosterChange)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if Keybinds.matches(input, "Party") then
		togglePanel()
	end
end)

setTab("party")
