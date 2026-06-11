--!strict
-- Mailbox UI. One panel, opened/closed with the on-screen Mail button (carries an unread badge), with
-- a list of mail on the left and a detail pane on the right. Each mail shows its sender, date, subject,
-- and -- when opened -- a body and a strip of reward icons (rendered like the inventory, not as text).
-- Claiming routes server-side: items to the active slot, Spins/Passes to the account. Balance/config
-- never reaches the client -- the server sends only the sanitised list + resolved reward display info.
-- Style/builders mirror InventoryController & the other panels.

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
local GOOD_COLOR = Color3.fromRGB(90, 200, 110)
local BAD_COLOR = Color3.fromRGB(235, 90, 90)

-- Item rarity border tints (matches InventoryController); non-item rewards (Spins/Pass) fall back to ACCENT.
local RARITY_COLOR: { [string]: Color3 } = {
	Common = Color3.fromRGB(170, 175, 185),
	Uncommon = Color3.fromRGB(90, 200, 110),
	Rare = Color3.fromRGB(70, 150, 255),
	Epic = Color3.fromRGB(180, 100, 240),
	Legendary = Color3.fromRGB(255, 176, 32),
	Mythic = Color3.fromRGB(255, 80, 90),
}

type Reward = {
	kind: string,
	image: string,
	displayName: string,
	rarity: string?,
	count: number,
	label: string,
}

type MailEntry = {
	id: string,
	from: string,
	subject: string,
	body: string,
	sentAt: number,
	expiresAt: number,
	read: boolean,
	claimed: boolean,
	rewards: { Reward },
}

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

-- Date helpers (client-side; sentAt/expiresAt are unix seconds) ---------------------------------

local function dateText(unix: number): string
	return os.date("%b %d, %Y", unix)
end

local function expiryText(expiresAt: number): string
	local days = math.ceil((expiresAt - os.time()) / 86400)
	if days <= 0 then
		return "Expired"
	elseif days == 1 then
		return "Expires in 1 day"
	end
	return `Expires in {days} days`
end

-- Shell ------------------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MailUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 10
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local openButton = Instance.new("TextButton")
openButton.Name = "OpenMail"
openButton.AnchorPoint = Vector2.new(0.5, 0.5)
openButton.Position = UDim2.fromScale(0.93, 0.44) -- below the Party button (0.38)
openButton.Size = UDim2.fromScale(0.1, 0.05)
openButton.BackgroundColor3 = PANEL_BG
openButton.AutoButtonColor = true
openButton.Font = Enum.Font.GothamBold
openButton.Text = "Mail"
openButton.TextColor3 = TEXT_COLOR
openButton.TextScaled = true
constrainText(openButton, 8, 18)
corner(openButton, 0.3)
stroke(openButton, 0.02, ACCENT, 0.2)
openButton.Parent = screenGui

-- Unread badge: an accent pip on the button's top-right corner, shown only when unread > 0.
local badge = Instance.new("TextLabel")
badge.Name = "UnreadBadge"
badge.AnchorPoint = Vector2.new(0.5, 0.5)
badge.Position = UDim2.fromScale(1, 0)
badge.Size = UDim2.fromScale(0.4, 0.7)
badge.BackgroundColor3 = BAD_COLOR
badge.Font = Enum.Font.GothamBold
badge.Text = "0"
badge.TextColor3 = TEXT_COLOR
badge.TextScaled = true
badge.Visible = false
constrainText(badge, 8, 16)
corner(badge, 0.5)
badge.Parent = openButton

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

local title = makeLabel(panel, "Mail", 0.5, 0.05, 0.6, 0.07, Enum.TextXAlignment.Center, 26)
title.Font = Enum.Font.GothamBold

local closeButton = makeButton(panel, "X", 0.95, 0.05, 0.06, 0.05, 20)

local content = Instance.new("Frame")
content.AnchorPoint = Vector2.new(0.5, 0.5)
content.Position = UDim2.fromScale(0.5, 0.55)
content.Size = UDim2.fromScale(0.96, 0.84)
content.BackgroundTransparency = 1
content.Parent = panel

-- Toast ------------------------------------------------------------------------------------------

local toast = makeLabel(panel, "", 0.5, 0.965, 0.9, 0.04, Enum.TextXAlignment.Center, 15)
toast.Font = Enum.Font.GothamBold
toast.TextTransparency = 1

local toastToken = 0
local function showToast(message: string, color: Color3?): ()
	toast.Text = message
	toast.TextColor3 = color or TEXT_COLOR
	toast.TextTransparency = 0
	toastToken += 1
	local myToken = toastToken
	task.delay(2.5, function()
		if myToken == toastToken then
			toast.TextTransparency = 1
		end
	end)
end

-- State ------------------------------------------------------------------------------------------

local mail: { MailEntry } = {}
local selectedId: string? = nil

local rebuildList: () -> ()
local refreshDetail: () -> ()

local function findMail(id: string?): MailEntry?
	if not id then
		return nil
	end
	for _, m in mail do
		if m.id == id then
			return m
		end
	end
	return nil
end

local function unreadCount(): number
	local n = 0
	for _, m in mail do
		if not m.read then
			n += 1
		end
	end
	return n
end

local function refreshBadge(): ()
	local n = unreadCount()
	badge.Visible = n > 0
	badge.Text = if n > 9 then "9+" else tostring(n)
end

-- List (left) ------------------------------------------------------------------------------------

local listScroller = Instance.new("ScrollingFrame")
listScroller.Name = "MailList"
listScroller.AnchorPoint = Vector2.new(0.5, 0.5)
listScroller.Position = UDim2.fromScale(0.3, 0.5)
listScroller.Size = UDim2.fromScale(0.58, 0.98)
listScroller.BackgroundTransparency = 1
listScroller.BorderSizePixel = 0
listScroller.ScrollBarThickness = 6
listScroller.ScrollBarImageColor3 = ACCENT
listScroller.AutomaticCanvasSize = Enum.AutomaticSize.XY
listScroller.CanvasSize = UDim2.new(0, 0, 0, 0)
listScroller.Parent = content

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.VerticalAlignment = Enum.VerticalAlignment.Top
listLayout.Parent = listScroller

local listEmpty = makeLabel(content, "No mail.", 0.3, 0.5, 0.5, 0.06, Enum.TextXAlignment.Center, 16)
listEmpty.TextColor3 = TEXT_DIM
listEmpty.Visible = false

local listRows: { Instance } = {}

local function makeRow(entry: MailEntry, order: number): ()
	local outer = Instance.new("Frame")
	outer.AnchorPoint = Vector2.new(0.5, 0.5)
	outer.Size = UDim2.fromScale(0.97, 0.16)
	outer.BackgroundTransparency = 1
	outer.LayoutOrder = order
	outer.Parent = listScroller
	table.insert(listRows, outer)

	local card = Instance.new("TextButton")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(1, 0.88)
	card.BackgroundColor3 = ROW_BG
	card.BackgroundTransparency = if entry.read then 0.45 else 0.15
	card.AutoButtonColor = true
	card.Text = ""
	corner(card, 0.16)
	stroke(card, 0.02, if entry.read then TEXT_DIM else ACCENT, if entry.read then 0.5 else 0.1)
	card.Parent = outer

	local subject = makeLabel(card, entry.subject, 0.46, 0.32, 0.84, 0.36, Enum.TextXAlignment.Left, 15)
	subject.Font = Enum.Font.GothamBold
	subject.TextColor3 = if entry.read then TEXT_DIM else TEXT_COLOR

	local sub = makeLabel(
		card,
		`{entry.from}  •  {dateText(entry.sentAt)}`,
		0.46,
		0.68,
		0.84,
		0.28,
		Enum.TextXAlignment.Left,
		12
	)
	sub.TextColor3 = TEXT_DIM

	-- Right-side status: Claimed, else days-left; plus an unread pip when not yet read.
	local statusText = if entry.claimed then "Claimed" else expiryText(entry.expiresAt)
	local status = makeLabel(card, statusText, 0.84, 0.68, 0.3, 0.26, Enum.TextXAlignment.Right, 11)
	status.TextColor3 = if entry.claimed then GOOD_COLOR else TEXT_DIM

	if not entry.read then
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.95, 0.32)
		dot.Size = UDim2.fromScale(0.05, 0.22)
		dot.BackgroundColor3 = ACCENT
		corner(dot, 0.5)
		dot.Parent = card
	end

	local id = entry.id
	card.Activated:Connect(function()
		selectedId = id
		if not entry.read then
			entry.read = true -- optimistic; server confirms via MarkMailRead -> MailChanged
			Remotes.MarkMailRead:FireServer(id)
			refreshBadge()
		end
		rebuildList()
		refreshDetail()
	end)
end

rebuildList = function()
	for _, row in listRows do
		row:Destroy()
	end
	table.clear(listRows)
	for index, entry in mail do
		makeRow(entry, index)
	end
	listEmpty.Visible = #mail == 0
end

-- Detail (right) ---------------------------------------------------------------------------------

local detail = Instance.new("Frame")
detail.AnchorPoint = Vector2.new(0.5, 0.5)
detail.Position = UDim2.fromScale(0.79, 0.5)
detail.Size = UDim2.fromScale(0.4, 0.98)
detail.BackgroundColor3 = SLOT_BG
detail.BackgroundTransparency = 0.2
corner(detail, 0.05)
detail.Parent = content

local dSubject = makeLabel(detail, "", 0.5, 0.07, 0.92, 0.08, Enum.TextXAlignment.Center, 18)
dSubject.Font = Enum.Font.GothamBold
dSubject.Visible = false

local dMeta = makeLabel(detail, "", 0.5, 0.15, 0.92, 0.05, Enum.TextXAlignment.Center, 12)
dMeta.TextColor3 = TEXT_DIM
dMeta.Visible = false

local dBody = makeLabel(detail, "", 0.5, 0.37, 0.9, 0.36, Enum.TextXAlignment.Left, 15)
dBody.TextWrapped = true
dBody.TextYAlignment = Enum.TextYAlignment.Top
dBody.TextColor3 = TEXT_COLOR
dBody.Visible = false

local dRewardsHeader = makeLabel(detail, "Rewards", 0.5, 0.6, 0.9, 0.045, Enum.TextXAlignment.Left, 13)
dRewardsHeader.Font = Enum.Font.GothamBold
dRewardsHeader.TextColor3 = TEXT_DIM
dRewardsHeader.Visible = false

local rewardsStrip = Instance.new("ScrollingFrame")
rewardsStrip.Name = "Rewards"
rewardsStrip.AnchorPoint = Vector2.new(0.5, 0.5)
rewardsStrip.Position = UDim2.fromScale(0.5, 0.72)
rewardsStrip.Size = UDim2.fromScale(0.92, 0.2)
rewardsStrip.BackgroundTransparency = 1
rewardsStrip.BorderSizePixel = 0
rewardsStrip.ScrollBarThickness = 4
rewardsStrip.ScrollBarImageColor3 = ACCENT
rewardsStrip.ScrollingDirection = Enum.ScrollingDirection.X
rewardsStrip.AutomaticCanvasSize = Enum.AutomaticSize.X
rewardsStrip.CanvasSize = UDim2.new(0, 0, 0, 0)
rewardsStrip.Visible = false
rewardsStrip.Parent = detail

local rewardsLayout = Instance.new("UIListLayout")
rewardsLayout.FillDirection = Enum.FillDirection.Horizontal
rewardsLayout.SortOrder = Enum.SortOrder.LayoutOrder
rewardsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
rewardsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
rewardsLayout.Parent = rewardsStrip

local dNoRewards = makeLabel(detail, "No rewards.", 0.5, 0.72, 0.9, 0.05, Enum.TextXAlignment.Center, 13)
dNoRewards.TextColor3 = TEXT_DIM
dNoRewards.Visible = false

local claimButton = makeButton(detail, "Claim", 0.3, 0.91, 0.42, 0.1, 16)
claimButton.Visible = false

local deleteButton = makeButton(detail, "Delete", 0.74, 0.91, 0.42, 0.1, 16)
deleteButton.BackgroundColor3 = SLOT_BG
deleteButton.Visible = false

local detailPlaceholder =
	makeLabel(detail, "Select a message to read it.", 0.5, 0.5, 0.86, 0.12, Enum.TextXAlignment.Center, 16)
detailPlaceholder.TextColor3 = TEXT_DIM

local rewardCells: { Instance } = {}

local function makeRewardCell(reward: Reward, order: number): ()
	local wrapper = Instance.new("Frame")
	wrapper.Size = UDim2.fromScale(0.24, 1)
	wrapper.BackgroundTransparency = 1
	wrapper.LayoutOrder = order
	wrapper.Parent = rewardsStrip
	table.insert(rewardCells, wrapper)

	local cell = Instance.new("Frame")
	cell.AnchorPoint = Vector2.new(0.5, 0.5)
	cell.Position = UDim2.fromScale(0.5, 0.5)
	cell.Size = UDim2.fromScale(0.86, 0.86)
	cell.BackgroundColor3 = SLOT_BG
	corner(cell, 0.14)
	stroke(cell, 0.04, (reward.rarity and RARITY_COLOR[reward.rarity]) or ACCENT, 0)
	cell.Parent = wrapper

	local image = Instance.new("ImageLabel")
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.34)
	image.Size = UDim2.fromScale(0.62, 0.5)
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.Image = reward.image
	image.Parent = cell

	if reward.count > 1 then
		local countLabel = makeLabel(cell, `x{reward.count}`, 0.5, 0.62, 0.7, 0.18, Enum.TextXAlignment.Center, 13)
		countLabel.Font = Enum.Font.GothamBold
		countLabel.TextColor3 = ACCENT
	end

	local nameLabel = makeLabel(cell, reward.label, 0.5, 0.85, 0.94, 0.24, Enum.TextXAlignment.Center, 11)
	nameLabel.TextColor3 = TEXT_COLOR
end

local function rebuildRewards(entry: MailEntry): ()
	for _, c in rewardCells do
		c:Destroy()
	end
	table.clear(rewardCells)
	for index, reward in entry.rewards do
		makeRewardCell(reward, index)
	end
end

-- Delete is a two-click confirm (deleting drops unclaimed rewards). Confirm reverts after a beat.
local deleteArmedFor: string? = nil
local deleteToken = 0
local function resetDelete(): ()
	deleteArmedFor = nil
	deleteButton.Text = "Delete"
	deleteButton.TextColor3 = TEXT_COLOR
end

refreshDetail = function()
	local entry = findMail(selectedId)
	if not entry then
		detailPlaceholder.Visible = true
		dSubject.Visible = false
		dMeta.Visible = false
		dBody.Visible = false
		dRewardsHeader.Visible = false
		rewardsStrip.Visible = false
		dNoRewards.Visible = false
		claimButton.Visible = false
		deleteButton.Visible = false
		return
	end
	if deleteArmedFor ~= entry.id then
		resetDelete()
	end
	detailPlaceholder.Visible = false
	dSubject.Visible = true
	dSubject.Text = entry.subject
	dMeta.Visible = true
	dMeta.Text = `From {entry.from}  •  {dateText(entry.sentAt)}  •  {expiryText(entry.expiresAt)}`
	dBody.Visible = true
	dBody.Text = entry.body

	local hasRewards = #entry.rewards > 0
	dRewardsHeader.Visible = hasRewards
	rewardsStrip.Visible = hasRewards
	dNoRewards.Visible = not hasRewards
	if hasRewards then
		rebuildRewards(entry)
	end

	claimButton.Visible = true
	deleteButton.Visible = true
	if not hasRewards then
		claimButton.Text = "No Rewards"
		claimButton.Active = false
		claimButton.AutoButtonColor = false
		claimButton.BackgroundColor3 = SLOT_BG
		claimButton.TextColor3 = TEXT_DIM
	elseif entry.claimed then
		claimButton.Text = "Claimed"
		claimButton.Active = false
		claimButton.AutoButtonColor = false
		claimButton.BackgroundColor3 = SLOT_BG
		claimButton.TextColor3 = GOOD_COLOR
	else
		claimButton.Text = "Claim"
		claimButton.Active = true
		claimButton.AutoButtonColor = true
		claimButton.BackgroundColor3 = ROW_BG
		claimButton.TextColor3 = ACCENT
	end
end

-- Apply a fresh list from the server: refresh state, drop a stale selection, rebuild, update badge.
local function applyMailView(list: { MailEntry }?): ()
	mail = list or {}
	if selectedId and not findMail(selectedId) then
		selectedId = nil
		resetDelete()
	end
	rebuildList()
	refreshDetail()
	refreshBadge()
end

claimButton.Activated:Connect(function()
	local entry = findMail(selectedId)
	if not entry or entry.claimed or #entry.rewards == 0 then
		return
	end
	local res = Remotes.ClaimMail:InvokeServer(entry.id) :: { ok: boolean, reason: string?, mail: { MailEntry }? }?
	if typeof(res) == "table" then
		applyMailView(res.mail)
		if res.ok then
			showToast("Rewards claimed!", GOOD_COLOR)
		else
			showToast(res.reason or "Couldn't claim", BAD_COLOR)
		end
	end
end)

deleteButton.Activated:Connect(function()
	local entry = findMail(selectedId)
	if not entry then
		return
	end
	if deleteArmedFor ~= entry.id then
		-- First click: arm + auto-disarm after a beat.
		deleteArmedFor = entry.id
		deleteButton.Text = "Confirm Delete"
		deleteButton.TextColor3 = BAD_COLOR
		deleteToken += 1
		local myToken = deleteToken
		task.delay(2.5, function()
			if myToken == deleteToken and deleteArmedFor == entry.id then
				resetDelete()
			end
		end)
		return
	end
	-- Second click: commit.
	resetDelete()
	Remotes.DeleteMail:FireServer(entry.id)
	selectedId = nil
	refreshDetail()
end)

-- Open / close -----------------------------------------------------------------------------------

local function pullMail(): ()
	applyMailView(Remotes.GetMail:InvokeServer() :: { MailEntry }?)
end

local function togglePanel(): ()
	if panel.Visible then
		panel.Visible = false
	else
		pullMail()
		panel.Visible = true
	end
end

openButton.Activated:Connect(togglePanel)
closeButton.Activated:Connect(function()
	panel.Visible = false
end)

-- Live updates (new mail, claim/delete results, broadcast arrivals): re-apply + keep the badge fresh
-- even while the panel is closed.
Remotes.MailChanged.OnClientEvent:Connect(function(list: any)
	applyMailView(list :: { MailEntry }?)
end)

refreshDetail()
refreshBadge()
