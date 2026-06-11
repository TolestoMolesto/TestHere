--!strict
-- Spar UI (consensual 1v1 "training duel"). Three pieces: the incoming-challenge accept/decline
-- prompt (SparInvite), a small in-bout HUD that names your opponent and offers a Forfeit button
-- (SparStarted -> EndSpar), and a result banner when the bout ends (SparEnded: win / loss /
-- interrupted / ended). SparNotice drives a short toast for challenge failures. Challenges are SENT
-- from the Party panel's player list (PartyController). Pure UI -- the bout rules are server-side.
-- Style/builders mirror the other panels (Scale-only, AnchorPoint 0.5, no padding, TextScaled).

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

-- Inline builders (mirror the other controllers) ------------------------------------------------

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

-- Screen ---------------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SparUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 11 -- above the Party panel
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- In-bout HUD (opponent name + Forfeit) --------------------------------------------------------

local boutHud = Instance.new("Frame")
boutHud.Name = "BoutHud"
boutHud.AnchorPoint = Vector2.new(0.5, 0.5)
boutHud.Position = UDim2.fromScale(0.5, 0.14)
boutHud.Size = UDim2.fromScale(0.26, 0.07)
boutHud.BackgroundColor3 = PANEL_BG
boutHud.BackgroundTransparency = 0.1
boutHud.Visible = false
corner(boutHud, 0.2)
stroke(boutHud, 0.02, ACCENT, 0.2)
boutHud.Parent = screenGui

local boutLabel = makeLabel(boutHud, "Sparring", 0.36, 0.5, 0.64, 0.7, Enum.TextXAlignment.Left, 15)
boutLabel.Font = Enum.Font.GothamBold

local forfeitButton = makeButton(boutHud, "Forfeit", 0.82, 0.5, 0.3, 0.66, 14)
forfeitButton.BackgroundColor3 = SLOT_BG
forfeitButton.TextColor3 = BAD
forfeitButton.Activated:Connect(function()
	Remotes.EndSpar:FireServer()
end)

-- Result banner --------------------------------------------------------------------------------

local resultBanner = makeLabel(screenGui, "", 0.5, 0.4, 0.5, 0.1, Enum.TextXAlignment.Center, 40)
resultBanner.Font = Enum.Font.GothamBlack
resultBanner.TextTransparency = 1
resultBanner.TextStrokeTransparency = 0.4

local resultToken = 0
local function showResult(text: string, color: Color3): ()
	resultBanner.Text = text
	resultBanner.TextColor3 = color
	resultBanner.TextTransparency = 0
	resultToken += 1
	local myToken = resultToken
	task.delay(2.8, function()
		if myToken == resultToken then
			resultBanner.TextTransparency = 1
		end
	end)
end

-- Notice toast ---------------------------------------------------------------------------------

local toast = makeLabel(screenGui, "", 0.5, 0.24, 0.5, 0.04, Enum.TextXAlignment.Center, 15)
toast.Font = Enum.Font.GothamBold
toast.TextTransparency = 1
toast.TextStrokeTransparency = 0.6

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

-- Challenge accept/decline prompt --------------------------------------------------------------

local overlay = Instance.new("Frame")
overlay.Name = "ChallengePrompt"
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

-- Wiring ---------------------------------------------------------------------------------------

Remotes.SparInvite.OnClientEvent:Connect(function(fromDisplayName: string, _fromUserId: number)
	showPrompt(`{fromDisplayName} challenges you to a spar.`, function()
		Remotes.RespondSpar:FireServer(true)
	end, function()
		Remotes.RespondSpar:FireServer(false)
	end)
end)

Remotes.SparStarted.OnClientEvent:Connect(function(opponentDisplayName: string, _opponentUserId: number)
	boutLabel.Text = `Sparring {opponentDisplayName}`
	boutHud.Visible = true
	resultBanner.TextTransparency = 1
end)

local RESULT_TEXT: { [string]: { text: string, color: Color3 } } = {
	win = { text = "You win!", color = GOOD },
	loss = { text = "You lost", color = BAD },
	interrupted = { text = "Spar interrupted", color = ACCENT },
	ended = { text = "Spar ended", color = TEXT_DIM },
}

Remotes.SparEnded.OnClientEvent:Connect(function(result: string)
	boutHud.Visible = false
	local mapped = RESULT_TEXT[result] or RESULT_TEXT.ended
	showResult(mapped.text, mapped.color)
end)

Remotes.SparNotice.OnClientEvent:Connect(function(message: string)
	showToast(message, ACCENT)
end)
