--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Entities = require(ReplicatedStorage.Modules.Entities)

local LockOn = {}
LockOn.LOCKON_PROXIMITY = 200
LockOn.MAX_RANGE = 1000
LockOn.MAX_LOCKON_DISTANCE = LockOn.MAX_RANGE
LockOn.MAX_SCROLL_DISTANCE = LockOn.MAX_RANGE
LockOn.MAX_LEASH_DISTANCE = LockOn.MAX_RANGE + 50
LockOn.BASE_DISTANCE = 6
LockOn.SHOULDER_OFFSET = 5
LockOn.HEIGHT_OFFSET = 3.5
LockOn.CLOSE_DISTANCE_THRESHOLD = 15
LockOn.MIN_CLOSE_DISTANCE = 3
LockOn.GUI_HIDE_DISTANCE = 100
LockOn.SIDE_VIEW_CAMERA_DISTANCE = 18
LockOn.SIDE_VIEW_HEIGHT = 5
LockOn.SIDE_TRANSITION_START = 20
LockOn.SIDE_TRANSITION_END = 8
LockOn.BASE_FOV = 70
LockOn.MAX_FOV = 95
LockOn.SHOULDER_LERP_SPEED = 0.04
LockOn.TARGET_FOLDERS = {
	Entities.Folder.Player,
	Entities.Folder.NPC,
	Entities.Folder.Shadow,
	"Enemies",
}
-- Names never targeted (friendly/static rigs), matched on Model.Name.
LockOn.IGNORE_LIST = {
	"QuestGiver",
	"ShopKeeper",
	"Civilian",
	"Dummy",
}
local state = {
	targetIndex = 1,
	shakeIntensity = 0,
	hitShakeIntensity = 0,
	smoothedShoulderVec = Vector3.new(LockOn.SHOULDER_OFFSET, 0, 0),
	currentSide = 1,
	sideLocked = false,
	smoothedSideRatio = 0,
	smoothedCameraPos = nil,
	smoothedLookTarget = nil,
	lastLockOnStyle = nil,
	smoothedFlatLook = nil,
	swappingZoom = 0,
	rotation1 = 0,
	rotation2 = 0,
	rotationSpeed1 = 2,
	rotationSpeed2 = 1,
	currentLockOnGui = nil :: BillboardGui?,
	currentCloseRangeGui = nil :: BillboardGui?,
	currentLockOnTarget = nil :: Model?,
}
function LockOn.getSearchableFolders(): { Instance }
	local folders: { Instance } = { Workspace }
	for _, name in LockOn.TARGET_FOLDERS do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(folders, folder)
		end
	end
	return folders
end

function LockOn.isValidTarget(model: Model, playerCharacter: Model?): boolean
	if model == playerCharacter then
		return false
	end
	if table.find(LockOn.IGNORE_LIST, model.Name) then
		return false
	end

	-- Shadows are private to their owner: ShadowSpawner names them "<Player>_Shadow" and tags them Shadow.
	if Entities.isShadow(model) then
		local localPlayer = Players.LocalPlayer
		local ownerName = model.Name:match("^(.-)_Shadow$")
		if localPlayer and ownerName ~= localPlayer.Name then
			return false
		end
	end

	local hum = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hum and hrp and hum.Health > 0 then
		return true
	end
	return false
end

function LockOn.findNearestMouseTarget(
	playerCamera: Camera,
	playerRoot: BasePart,
	playerMouse: Mouse,
	playerCharacter: Model?
): Model?
	local bestCursorTarget = nil
	local bestCursorScore = math.huge
	local bestProximityTarget = nil
	local bestProximityDist = math.huge

	for _, folder in LockOn.getSearchableFolders() do
		for _, child in folder:GetChildren() do
			if child:IsA("Model") and LockOn.isValidTarget(child, playerCharacter) then
				local hrp = child:FindFirstChild("HumanoidRootPart")
				if hrp and hrp:IsA("BasePart") then
					local dist = (playerRoot.Position - hrp.Position).Magnitude
					if dist <= LockOn.LOCKON_PROXIMITY then
						if dist < bestProximityDist then
							bestProximityDist = dist
							bestProximityTarget = child
						end
						local screenPoint, onScreen = playerCamera:WorldToScreenPoint(hrp.Position)
						if onScreen then
							local score = (Vector2.new(playerMouse.X, playerMouse.Y) - Vector2.new(
								screenPoint.X,
								screenPoint.Y
							)).Magnitude
							if score < bestCursorScore and score < 80 then
								bestCursorScore = score
								bestCursorTarget = child
							end
						end
					end
				end
			end
		end
	end
	return bestCursorTarget or bestProximityTarget
end

function LockOn.findModelByName(name: string): Model?
	for _, folder in LockOn.getSearchableFolders() do
		local found = folder:FindFirstChild(name)
		if found and found:IsA("Model") then
			return found
		end
	end
	return nil
end

function LockOn.getPotentialTargets(playerRoot: BasePart, playerCharacter: Model?): { Model }
	local potentialTargets = {}
	for _, folder in LockOn.getSearchableFolders() do
		for _, char in folder:GetChildren() do
			if char:IsA("Model") and LockOn.isValidTarget(char, playerCharacter) then
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if hrp and hrp:IsA("BasePart") then
					local distance = (playerRoot.Position - hrp.Position).Magnitude
					if distance <= LockOn.MAX_SCROLL_DISTANCE then
						table.insert(potentialTargets, char)
					end
				end
			end
		end
	end
	return potentialTargets
end

function LockOn.setCharacterTransparency(playerCharacter: Model, amount: number)
	if not playerCharacter then
		return
	end
	for _, part in playerCharacter:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part.LocalTransparencyModifier = amount
		elseif part:IsA("Decal") then
			part.Transparency = amount
		end
	end
end

function LockOn.createLockOnGui(targetModel: Model, lockOnGuiTemplate: Instance?, closeRangeGuiTemplate: Instance?)
	if state.currentLockOnGui then
		state.currentLockOnGui:Destroy()
		state.currentLockOnGui = nil
	end
	if state.currentCloseRangeGui then
		state.currentCloseRangeGui:Destroy()
		state.currentCloseRangeGui = nil
	end
	local targetPart = targetModel:FindFirstChild("Torso")
		or targetModel:FindFirstChild("UpperTorso")
		or targetModel:FindFirstChild("HumanoidRootPart")
	if not targetPart then
		return
	end
	if lockOnGuiTemplate then
		local gui = lockOnGuiTemplate:Clone() :: BillboardGui
		gui.Name = "LockonGui"
		gui.Parent = targetPart
		gui.Adornee = targetPart
		gui.Enabled = true
		gui.AlwaysOnTop = true
		gui.StudsOffset = Vector3.new(0, 0, 0)
		gui.LightInfluence = 0
		gui.ExtentsOffset = Vector3.new(0, 0, 0)
		for _, child in gui:GetChildren() do
			if child:IsA("ImageLabel") or child:IsA("TextLabel") then
				local label = child :: GuiObject
				label.Visible = true
			end
		end
		gui.ClipsDescendants = false
		state.currentLockOnGui = gui
	end
	if closeRangeGuiTemplate then
		local gui = closeRangeGuiTemplate:Clone() :: BillboardGui
		gui.Name = "CloseRangeLockonGui"
		gui.Parent = targetPart
		gui.Adornee = targetPart
		gui.Enabled = true
		gui.AlwaysOnTop = true
		gui.StudsOffset = Vector3.new(0, 0, 0)
		gui.LightInfluence = 0
		gui.ExtentsOffset = Vector3.new(0, 0, 0)
		for _, child in gui:GetChildren() do
			if child:IsA("ImageLabel") or child:IsA("TextLabel") then
				local label = child :: GuiObject
				label.Visible = true
			end
		end
		gui.ClipsDescendants = false
		state.currentCloseRangeGui = gui
	end
	state.currentLockOnTarget = targetModel
end

function LockOn.removeLockOnGui()
	if state.currentLockOnGui then
		state.currentLockOnGui:Destroy()
		state.currentLockOnGui = nil
	end
	if state.currentCloseRangeGui then
		state.currentCloseRangeGui:Destroy()
		state.currentCloseRangeGui = nil
	end
	state.currentLockOnTarget = nil
end

function LockOn.updateLockOnGuiVisuals(distToTarget: number, targetHumanoid: Humanoid?)
	if state.currentLockOnGui and state.currentLockOnGui.Enabled then
		for _, child in state.currentLockOnGui:GetChildren() do
			if child:IsA("ImageLabel") and not child.Visible then
				child.Visible = true
			end
		end
		state.rotation1 = (state.rotation1 + state.rotationSpeed1) % 360
		state.rotation2 = (state.rotation2 - state.rotationSpeed2) % 360
		local effectStartDist = LockOn.MAX_LOCKON_DISTANCE * 0.7
		local distanceRatio =
			math.clamp((distToTarget - effectStartDist) / (LockOn.MAX_LOCKON_DISTANCE - effectStartDist), 0, 1)
		local minSize = 80
		local maxSize = 150
		local sizeRatio = math.clamp(
			(distToTarget - LockOn.GUI_HIDE_DISTANCE) / (LockOn.MAX_LOCKON_DISTANCE - LockOn.GUI_HIDE_DISTANCE),
			0,
			1
		)
		local currentSize = minSize + (maxSize - minSize) * sizeRatio
		state.currentLockOnGui.Size = UDim2.new(0, currentSize, 0, currentSize)
		local image1Size = currentSize
		local image2Size = currentSize * 0.7
		local image1Offset = image1Size / 2
		local image2Offset = image2Size / 2
		local baseColor = Color3.fromRGB(255, 255, 255)
		if targetHumanoid then
			local targetHealthPercent = targetHumanoid.Health / targetHumanoid.MaxHealth
			if targetHealthPercent <= 0.25 then
				baseColor = Color3.fromRGB(255, 0, 0)
			elseif targetHealthPercent <= 0.50 then
				baseColor = Color3.fromRGB(255, 165, 0)
			end
		end
		local grayColor = Color3.fromRGB(150, 150, 150)
		local finalColor = baseColor:Lerp(grayColor, distanceRatio)
		local imageIndex = 0
		for _, child in state.currentLockOnGui:GetChildren() do
			if child:IsA("ImageLabel") then
				imageIndex += 1
				child.ImageColor3 = finalColor
				if imageIndex == 1 then
					child.Rotation = state.rotation1
				else
					child.Rotation = state.rotation2
				end
				if distanceRatio > 0 then
					local shakeX = math.random(-4, 4) * distanceRatio * 2
					local shakeY = math.random(-4, 4) * distanceRatio * 2
					local offsetX = imageIndex == 1 and -image1Offset or -image2Offset
					local offsetY = imageIndex == 1 and -image1Offset or -image2Offset
					child.Position = UDim2.new(0.5, offsetX + shakeX, 0.5, offsetY + shakeY)
				else
					local offsetX = imageIndex == 1 and -image1Offset or -image2Offset
					local offsetY = imageIndex == 1 and -image1Offset or -image2Offset
					child.Position = UDim2.new(0.5, offsetX, 0.5, offsetY)
				end
				if imageIndex == 1 then
					child.Size = UDim2.new(0, image1Size, 0, image1Size)
				else
					child.Size = UDim2.new(0, image2Size, 0, image2Size)
				end
			end
		end
		local distanceLabel = state.currentLockOnGui:FindFirstChild("DistanceLabel")
		if distanceLabel and distanceLabel:IsA("TextLabel") then
			distanceLabel.Visible = true
			distanceLabel.Text = math.floor(distToTarget) .. " studs"
			distanceLabel.TextColor3 = finalColor
			distanceLabel.TextStrokeTransparency = 0.5 + distanceRatio * 0.3
		end
	end
	if state.currentCloseRangeGui and state.currentCloseRangeGui.Enabled then
		for _, child in state.currentCloseRangeGui:GetChildren() do
			if child:IsA("ImageLabel") and not child.Visible then
				child.Visible = true
			end
		end
		local blinkThreshold = 100
		local blinkRange = 20
		local blinkIntensity = 0
		if distToTarget > blinkThreshold - blinkRange and distToTarget < blinkThreshold then
			blinkIntensity = (distToTarget - (blinkThreshold - blinkRange)) / blinkRange
		end
		local baseColor = Color3.fromRGB(255, 255, 255)
		if targetHumanoid then
			local targetHealthPercent = targetHumanoid.Health / targetHumanoid.MaxHealth
			if targetHealthPercent <= 0.25 then
				baseColor = Color3.fromRGB(255, 0, 0)
			elseif targetHealthPercent <= 0.50 then
				baseColor = Color3.fromRGB(255, 165, 0)
			end
		end
		for _, child in state.currentCloseRangeGui:GetChildren() do
			if child:IsA("ImageLabel") then
				child.ImageColor3 = baseColor
				if blinkIntensity > 0 then
					local blinkSpeed = 0.1 + (blinkIntensity * 0.4)
					local blinkPhase = (tick() % blinkSpeed) / blinkSpeed
					local isBlinking = blinkPhase < 0.5
					child.ImageTransparency = isBlinking and (0.5 + blinkIntensity * 0.5) or 0
				else
					child.ImageTransparency = 0
				end
			end
		end
		local distanceLabel = state.currentCloseRangeGui:FindFirstChild("DistanceLabel")
		if distanceLabel and distanceLabel:IsA("TextLabel") then
			distanceLabel.Visible = true
			distanceLabel.Text = math.floor(distToTarget) .. " studs"
			distanceLabel.TextColor3 = baseColor
			distanceLabel.TextStrokeTransparency = 0.5
		end
	end
end

function LockOn.toggleGuiVisibility(distToTarget: number)
	if distToTarget < LockOn.GUI_HIDE_DISTANCE then
		if state.currentLockOnGui then
			state.currentLockOnGui.Enabled = false
		end
		if state.currentCloseRangeGui then
			state.currentCloseRangeGui.Enabled = true
		end
	else
		if state.currentLockOnGui then
			state.currentLockOnGui.Enabled = true
		end
		if state.currentCloseRangeGui then
			state.currentCloseRangeGui.Enabled = false
		end
	end
end

function LockOn.resetState()
	state.smoothedCameraPos = nil
	state.smoothedLookTarget = nil
	state.smoothedSideRatio = 0
	state.sideLocked = false
	state.lastLockOnStyle = nil
	state.smoothedFlatLook = nil
end

function LockOn.getState()
	return state
end

function LockOn.updateState(newState: {})
	for key, value in newState do
		if state[key] ~= nil then
			state[key] = value
		end
	end
end
return LockOn
