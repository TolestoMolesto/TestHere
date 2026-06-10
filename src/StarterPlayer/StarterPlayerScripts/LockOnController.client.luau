--!strict

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Keybinds = require(ReplicatedStorage.Modules.Keybinds)
local LockOn = require(ReplicatedStorage.Modules.LockOn)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Settings = require(ReplicatedStorage.Modules.Settings)

local player = Players.LocalPlayer :: Player
local playerCamera = Workspace.CurrentCamera :: Camera
local playerCharacter = player.Character or player.CharacterAdded:Wait()
local playerRoot = playerCharacter:WaitForChild("HumanoidRootPart") :: Part
local playerHumanoid = playerCharacter:WaitForChild("Humanoid") :: Humanoid
local playerMouse = player:GetMouse()

local LOCK_ON_MOUSE = Enum.UserInputType.MouseButton3 -- middle mouse button (fixed secondary)

local config = {
	Style = Settings.get("LockOn", "Style") :: string,
	FOV = Settings.get("LockOn", "FOV") :: number,
	Transparency = Settings.get("LockOn", "Transparency") :: number,
	Shake = Settings.get("Camera", "Shake") :: boolean,
}
local function refreshConfig()
	config.Style = Settings.get("LockOn", "Style")
	config.FOV = Settings.get("LockOn", "FOV")
	config.Transparency = Settings.get("LockOn", "Transparency")
	config.Shake = Settings.get("Camera", "Shake")
end
Settings.onChanged(refreshConfig)

local shakeIntensity = 0
local hitShakeIntensity = 0
local playerLastHealth = playerHumanoid.Health
local swappingZoom = 0
local smoothedShoulderVec = Vector3.new(LockOn.SHOULDER_OFFSET, 0, 0)
local currentSide = 1
local sideLocked = false
local smoothedSideRatio = 0
local smoothedCameraPos: Vector3? = nil
local smoothedLookTarget: Vector3? = nil
local lastLockOnStyle: string? = nil
local smoothedFlatLook: Vector3? = nil
-- Persistent horizontal camera azimuth (target -> player), held stable while the
-- fighters are vertically stacked so the view can't snap/spin. See updateCamera.
local orbitDir: Vector3? = nil

local isLocked = false
local currentTargetModel: Model? = nil

-- We drive MouseBehavior directly while locked on, bypassing the stock camera
-- module's save/restore, so we must hand the mouse back ourselves on unlock.
-- Without this the mouse stays LockCenter and feels like Shift Lock got stuck on.
-- The flag keeps the reset a one-shot on the lock->unlock edge so idle (unlocked)
-- frames never fight a player's real Shift Lock.
local mouseLockApplied = false

local function applyMouseLock()
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	mouseLockApplied = true
end

local function releaseMouseLock()
	if mouseLockApplied then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		mouseLockApplied = false
	end
end

local state = LockOn.getState()

local lockOnGuiTemplate = ReplicatedStorage:FindFirstChild("LockonGui")
local closeRangeGuiTemplate = ReplicatedStorage:FindFirstChild("CloseRangeLockonGui")

local healthVignette = Lighting:FindFirstChild("HealthVignette") :: ColorCorrectionEffect?
	or Instance.new("ColorCorrectionEffect")
healthVignette.Name = "HealthVignette"
healthVignette.Parent = Lighting

local transitionBlur = Lighting:FindFirstChild("LockOnBlur") :: BlurEffect? or Instance.new("BlurEffect")
transitionBlur.Name = "LockOnBlur"
transitionBlur.Size = 0
transitionBlur.Parent = Lighting

local lockCorrection = Lighting:FindFirstChild("LockOnCorrection") :: ColorCorrectionEffect?
	or Instance.new("ColorCorrectionEffect")
lockCorrection.Name = "LockOnCorrection"
lockCorrection.Parent = Lighting

local crosshairGui = Instance.new("ScreenGui")
crosshairGui.Name = "FreeCamCrosshair"
crosshairGui.ResetOnSpawn = false
crosshairGui.IgnoreGuiInset = true
crosshairGui.Parent = player:WaitForChild("PlayerGui")

local crosshair = Instance.new("ImageLabel")
crosshair.Name = "Crosshair"
crosshair.Size = UDim2.new(0, 32, 0, 32)
crosshair.Position = UDim2.new(0.5, -16, 0.5, -16)
crosshair.BackgroundTransparency = 1
crosshair.Image = "rbxassetid://7072725342"
crosshair.ImageColor3 = Color3.fromRGB(255, 255, 255)
crosshair.Visible = false
crosshair.Parent = crosshairGui

local function lockOnto(target: Model?)
	currentTargetModel = target
	isLocked = target ~= nil
	Remotes.SetLockOnTarget:FireServer(target)
end

local function watchServerLock(character: Model)
	character:GetAttributeChangedSignal("LockedOn"):Connect(function()
		if isLocked and character:GetAttribute("LockedOn") == false then
			isLocked = false
			currentTargetModel = nil
		end
	end)
end

local function handleLockOn(input: InputObject, inGui: boolean)
	if inGui then
		return
	end

	if Keybinds.matches(input, "LockOn") or input.UserInputType == LOCK_ON_MOUSE then
		if not isLocked then
			local target = LockOn.findNearestMouseTarget(playerCamera, playerRoot, playerMouse, playerCharacter)
			if target then
				lockOnto(target)
			end
		else
			lockOnto(nil)
		end
	end
end

UserInputService.InputChanged:Connect(function(input, processed)
	if processed or not isLocked then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		local potentialTargets = LockOn.getPotentialTargets(playerRoot, playerCharacter)

		if #potentialTargets > 1 then
			if input.Position.Z > 0 then
				state.targetIndex = (state.targetIndex % #potentialTargets) + 1
			else
				state.targetIndex = (state.targetIndex - 2 + #potentialTargets) % #potentialTargets + 1
			end
			local newTarget = potentialTargets[state.targetIndex]
			if newTarget then
				lockOnto(newTarget)
				swappingZoom = 15
			end
		end
	end
end)

local function updateCamera()
	local isSelfRagdolled = playerCharacter:GetAttribute("ToggleRagdoll")
	local isDead = playerHumanoid.Health <= 0
	local myHealth = playerHumanoid.Health
	local lockOnStyle = config.Style

	if myHealth < playerLastHealth and config.Shake then
		shakeIntensity = 0.5
	end

	playerLastHealth = myHealth
	shakeIntensity = math.lerp(shakeIntensity, 0, 0.1)
	hitShakeIntensity = math.lerp(hitShakeIntensity, 0, 0.15)

	if not isLocked or isSelfRagdolled or isDead then
		LockOn.removeLockOnGui()
		crosshair.Visible = false
		UserInputService.MouseIconEnabled = true
		releaseMouseLock()

		LockOn.resetState()
		smoothedCameraPos = nil
		smoothedLookTarget = nil
		smoothedSideRatio = 0
		sideLocked = false
		lastLockOnStyle = nil
		smoothedFlatLook = nil
		orbitDir = nil

		if playerCamera.CameraType == Enum.CameraType.Scriptable then
			playerCamera.CameraType = Enum.CameraType.Custom
			playerCamera.CameraSubject = playerHumanoid
			playerHumanoid.AutoRotate = true
			LockOn.setCharacterTransparency(playerCharacter, 0)
		end

		-- Guarded by isLocked so ragdoll/death doesn't fire the remote every idle frame.
		if isLocked then
			lockOnto(nil)
		end
		return
	end

	local isStunned = playerCharacter:GetAttribute("Stunned")
	local isCharging = playerCharacter:GetAttribute("Charging")
	local isKiBlasting = playerCharacter:GetAttribute("KiBlasting")
	local shouldRotateCharacter = not isStunned and not isCharging and not isKiBlasting

	local targetModel = currentTargetModel

	if not targetModel or not targetModel:FindFirstChild("Humanoid") then
		lockOnto(nil)
		LockOn.removeLockOnGui()
		UserInputService.MouseIconEnabled = true
		releaseMouseLock()
		return
	end

	if state.currentLockOnTarget ~= targetModel then
		LockOn.createLockOnGui(targetModel, lockOnGuiTemplate, closeRangeGuiTemplate)
	end

	local targetHumanoid = targetModel:FindFirstChildOfClass("Humanoid")
	local targetRoot = targetModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	local targetTorso = (
		targetModel:FindFirstChild("Torso")
		or targetModel:FindFirstChild("UpperTorso")
		or targetRoot
	) :: BasePart?

	if not targetRoot or not targetTorso then
		return
	end

	local distToTarget = (playerRoot.Position - targetRoot.Position).Magnitude

	if lockOnStyle == "FreeCam" then
		crosshair.Visible = true
		UserInputService.MouseIconEnabled = false
		applyMouseLock()
		playerHumanoid.AutoRotate = false

		LockOn.setCharacterTransparency(playerCharacter, config.Transparency)

		local freeCamFOV = 70 - ((config.FOV - 1) * 2.22)
		playerCamera.FieldOfView = math.lerp(playerCamera.FieldOfView, freeCamFOV + swappingZoom, 0.1)

		local playerPos = playerRoot.Position
		local targetPos = targetTorso.Position

		local heightDiffFree = playerPos.Y - targetPos.Y
		local horizontalDistFree = Vector3.new(targetPos.X - playerPos.X, 0, targetPos.Z - playerPos.Z).Magnitude
		local verticalAngleFree = math.atan2(heightDiffFree, horizontalDistFree)

		local dirToTarget = (targetPos - playerPos)
		local flatDirToTarget = Vector3.new(dirToTarget.X, 0, dirToTarget.Z)
		if flatDirToTarget.Magnitude > 0.001 then
			flatDirToTarget = flatDirToTarget.Unit
		else
			flatDirToTarget = Vector3.new(0, 0, -1)
		end

		local fullDirToTargetFree = dirToTarget.Magnitude > 0.001 and dirToTarget.Unit or Vector3.new(0, -1, 0)

		local shoulderDir = Vector3.new(-flatDirToTarget.Z, 0, flatDirToTarget.X) * -1
		local shoulderOffset = shoulderDir * LockOn.SHOULDER_OFFSET
		local heightOffset = Vector3.new(0, LockOn.HEIGHT_OFFSET, 0)
		local backOffset = -flatDirToTarget * 8

		local cameraGoal = playerPos + backOffset + shoulderOffset + heightOffset
		local midpoint = playerPos:Lerp(targetPos, 0.5)
		local lookTarget = midpoint + Vector3.new(0, 1.5, 0)

		if not smoothedCameraPos then
			smoothedCameraPos = cameraGoal
			smoothedLookTarget = lookTarget
		end

		local playerVelocity = playerRoot.AssemblyLinearVelocity
		local playerSpeed = playerVelocity.Magnitude

		local MIN_CAMERA_LERP = 0.15
		local MAX_CAMERA_LERP = 0.5
		local VELOCITY_INFLUENCE = 60
		local CLOSE_RANGE_SLOWDOWN = 0.7

		local baseCameraSpeed = MIN_CAMERA_LERP + (playerSpeed / VELOCITY_INFLUENCE)
		local cameraSpeed = math.clamp(baseCameraSpeed, MIN_CAMERA_LERP, MAX_CAMERA_LERP)

		if distToTarget < LockOn.CLOSE_DISTANCE_THRESHOLD then
			local closeRatio = 1 - (distToTarget / LockOn.CLOSE_DISTANCE_THRESHOLD)
			cameraSpeed = cameraSpeed * (1 - closeRatio * (1 - CLOSE_RANGE_SLOWDOWN))
		end

		smoothedCameraPos = (smoothedCameraPos :: Vector3):Lerp(cameraGoal, cameraSpeed)
		smoothedLookTarget = (smoothedLookTarget :: Vector3):Lerp(lookTarget, cameraSpeed)

		playerCamera.CameraType = Enum.CameraType.Scriptable
		playerCamera.CFrame = CFrame.lookAt(smoothedCameraPos :: Vector3, smoothedLookTarget :: Vector3)

		local isExtremeAngleFree = math.abs(verticalAngleFree) >= math.rad(45) or horizontalDistFree < 3
		local facingDirFree = isExtremeAngleFree and fullDirToTargetFree or flatDirToTarget

		if not smoothedFlatLook then
			smoothedFlatLook = facingDirFree
		end

		local facingLerpSpeedFree = isExtremeAngleFree and 0.04 or 0.12
		smoothedFlatLook = (smoothedFlatLook :: Vector3):Lerp(facingDirFree, facingLerpSpeedFree)

		if shouldRotateCharacter then
			local targetFacingFree = CFrame.lookAt(playerPos, playerPos + (smoothedFlatLook :: Vector3))
			playerRoot.CFrame = playerRoot.CFrame:Lerp(targetFacingFree, facingLerpSpeedFree)
		end

		LockOn.toggleGuiVisibility(distToTarget)
		return
	else
		crosshair.Visible = false
		smoothedCameraPos = nil
		smoothedLookTarget = nil
	end

	if distToTarget > LockOn.MAX_LEASH_DISTANCE then
		lockOnto(nil)
		return
	end

	LockOn.setCharacterTransparency(playerCharacter, config.Transparency)

	local preferredFOV = 70 - ((config.FOV - 1) * 2.22)
	local baseDist = 10
	local dynamicDist = baseDist - (config.FOV * 0.6)

	if lockOnStyle == "FaceOff" then
		dynamicDist = 4
		preferredFOV = 70 - ((config.FOV - 1) * 2.22)
	end

	UserInputService.MouseIconEnabled = false
	applyMouseLock()
	playerHumanoid.AutoRotate = false

	swappingZoom = math.lerp(swappingZoom, 0, 0.1)
	playerCamera.FieldOfView = math.lerp(playerCamera.FieldOfView, preferredFOV + swappingZoom, 0.1)

	local playerPos = playerRoot.Position
	local targetPos = targetTorso.Position

	local heightDiff = playerPos.Y - targetPos.Y
	local horizontalDist = Vector3.new(targetPos.X - playerPos.X, 0, targetPos.Z - playerPos.Z).Magnitude
	local verticalAngle = math.atan2(heightDiff, horizontalDist)

	local EXTREME_ANGLE_THRESHOLD = math.rad(45)
	local isExtremeAngle = math.abs(verticalAngle) >= EXTREME_ANGLE_THRESHOLD or horizontalDist < 3

	-- Stable horizontal azimuth (target -> player) used for ALL camera framing below.
	-- While the fighters are stacked (small horizontal gap: right on top, or directly
	-- above/below) the raw player<->target line is vertical, so every horizontal
	-- vector derived from it collapses to an arbitrary world axis -- that is what
	-- makes the view snap and spin. We refresh the azimuth only when there is a real
	-- horizontal gap, and otherwise hold the last good direction.
	local STACK_THRESHOLD = 4
	local flatToPlayer = Vector3.new(playerPos.X - targetPos.X, 0, playerPos.Z - targetPos.Z)
	if flatToPlayer.Magnitude > STACK_THRESHOLD then
		local desired = flatToPlayer.Unit
		if orbitDir then
			local blended = (orbitDir :: Vector3):Lerp(desired, 0.3)
			orbitDir = blended.Magnitude > 0.001 and blended.Unit or desired
		else
			orbitDir = desired
		end
	elseif not orbitDir then
		-- First frame and already stacked: seed from where the camera currently sits.
		local camFlat =
			Vector3.new(playerCamera.CFrame.Position.X - targetPos.X, 0, playerCamera.CFrame.Position.Z - targetPos.Z)
		if camFlat.Magnitude > 0.001 then
			orbitDir = camFlat.Unit
		else
			local camLook = Vector3.new(playerCamera.CFrame.LookVector.X, 0, playerCamera.CFrame.LookVector.Z)
			orbitDir = camLook.Magnitude > 0.001 and camLook.Unit or Vector3.new(0, 0, 1)
		end
	end
	local stableOrbitDir = orbitDir :: Vector3

	-- The character only ever faces the target horizontally. Feeding a near-vertical
	-- look into CFrame.lookAt (default up = +Y) is singular and spins the rig when the
	-- target is directly above/below; the camera conveys the vertical angle instead.
	local facingDir = -stableOrbitDir

	if not smoothedFlatLook then
		smoothedFlatLook = facingDir
	end

	local facingLerpSpeed = isExtremeAngle and 0.06 or 0.12
	local blendedFace = (smoothedFlatLook :: Vector3):Lerp(facingDir, facingLerpSpeed)
	smoothedFlatLook = blendedFace.Magnitude > 0.001 and blendedFace.Unit or facingDir

	if shouldRotateCharacter then
		local targetFacing = CFrame.lookAt(playerPos, playerPos + (smoothedFlatLook :: Vector3))
		playerRoot.CFrame = playerRoot.CFrame:Lerp(targetFacing, facingLerpSpeed)
	end

	local totalShake = shakeIntensity + hitShakeIntensity
	local camShake = Vector3.new(
		math.random(-100, 100) / 100 * totalShake,
		math.random(-100, 100) / 100 * totalShake,
		math.random(-100, 100) / 100 * totalShake
	)

	local targetSideRatio = 0

	if lastLockOnStyle ~= lockOnStyle then
		smoothedSideRatio = 0
		sideLocked = false
		smoothedCameraPos = nil
		smoothedLookTarget = nil
		smoothedFlatLook = nil
		orbitDir = nil
		lastLockOnStyle = lockOnStyle
	end

	if lockOnStyle == "Dynamic_View" then
		targetSideRatio = math.clamp(
			1
				- (distToTarget - LockOn.SIDE_TRANSITION_END)
					/ (LockOn.SIDE_TRANSITION_START - LockOn.SIDE_TRANSITION_END),
			0,
			1
		)
	elseif lockOnStyle == "FaceOff" then
		targetSideRatio = 0
	end

	local sideLerpSpeed = targetSideRatio > smoothedSideRatio and 0.05 or 0.1
	smoothedSideRatio = math.lerp(smoothedSideRatio, targetSideRatio, sideLerpSpeed)
	local sideRatio = smoothedSideRatio

	if sideRatio > 0.1 and not sideLocked then
		local camToMid = (playerCamera.CFrame.Position - playerPos:Lerp(targetPos, 0.5))
		local flatCamToMid = Vector3.new(camToMid.X, 0, camToMid.Z)
		if flatCamToMid.Magnitude > 0.001 then
			-- perpendicular to the (stable) sightline, so the side can't flip when stacked
			local perp = Vector3.new(stableOrbitDir.Z, 0, -stableOrbitDir.X)
			currentSide = perp:Dot(flatCamToMid) > 0 and 1 or -1
		else
			currentSide = 1
		end
		sideLocked = true
	elseif sideRatio < 0.05 then
		sideLocked = false
	end

	local currentShoulderOffset = LockOn.SHOULDER_OFFSET
	local rawShoulderVec = Vector3.new(-stableOrbitDir.Z, 0, stableOrbitDir.X) * currentShoulderOffset

	smoothedShoulderVec = smoothedShoulderVec:Lerp(rawShoulderVec, LockOn.SHOULDER_LERP_SPEED)
	local shoulderVec = smoothedShoulderVec

	-- Camera sits along the stable azimuth; never recomputed from the degenerate line.
	local flatDirToTarget = stableOrbitDir

	local verticalHeightAdjust = 0
	if math.abs(verticalAngle) > 0.1 then
		local angleFactor = math.clamp(math.abs(verticalAngle) / (math.pi / 4), 0, 1)
		verticalHeightAdjust = math.sign(heightDiff) * angleFactor * 8
	end

	-- Pull the camera back as the fight goes vertical so both fighters stay framed
	-- instead of overlapping on screen when one is directly above the other.
	local verticalStandoff = math.clamp(math.abs(heightDiff) * 0.4, 0, 14)
	local effectiveDist = dynamicDist + verticalStandoff

	local normalCameraGoal = playerPos
		+ (flatDirToTarget * effectiveDist)
		+ Vector3.new(0, LockOn.HEIGHT_OFFSET + verticalHeightAdjust, 0)
		+ shoulderVec
		+ camShake

	local lookTargetY = targetPos.Y
	if math.abs(verticalAngle) > 0.2 then
		local blendFactor = math.clamp(math.abs(verticalAngle) / (math.pi / 3), 0, 0.5)
		lookTargetY = math.lerp(targetPos.Y, playerPos.Y, blendFactor)
	end
	local normalLookTarget = Vector3.new(targetPos.X, lookTargetY, targetPos.Z):Lerp(playerPos, 0.2)

	local midpoint = playerPos:Lerp(targetPos, 0.5)
	-- player -> target horizontal, from the stable azimuth (never snaps when stacked)
	local flatLineDir = -stableOrbitDir

	local sideDir = Vector3.new(-flatLineDir.Z, 0, flatLineDir.X) * currentSide
	local cameraDist = LockOn.SIDE_VIEW_CAMERA_DISTANCE + (distToTarget * 0.6)

	local sideHeightAdjust = 0
	if math.abs(verticalAngle) > 0.1 then
		local angleFactor = math.clamp(math.abs(verticalAngle) / (math.pi / 4), 0, 1)
		sideHeightAdjust = math.sign(heightDiff) * angleFactor * 6
	end

	local sideCameraGoal = midpoint
		+ (sideDir * cameraDist)
		+ Vector3.new(0, LockOn.SIDE_VIEW_HEIGHT + sideHeightAdjust, 0)
		+ camShake

	local sideLookY = midpoint.Y
	if math.abs(verticalAngle) > 0.2 then
		local blendFactor = math.clamp(math.abs(verticalAngle) / (math.pi / 3), 0, 0.4)
		sideLookY = math.lerp(midpoint.Y, playerPos.Y, blendFactor)
	end
	local sideLookTarget = Vector3.new(midpoint.X, sideLookY, midpoint.Z)

	local cameraGoal = normalCameraGoal:Lerp(sideCameraGoal, sideRatio)
	local lookTarget = normalLookTarget:Lerp(sideLookTarget, sideRatio)

	local viewMidpoint = playerPos:Lerp(targetPos, 0.5)
	local viewMidpointY = viewMidpoint.Y
	if math.abs(verticalAngle) > 0.2 then
		local blendFactor = math.clamp(math.abs(verticalAngle) / (math.pi / 3), 0, 0.3)
		viewMidpointY = math.lerp(viewMidpoint.Y, playerPos.Y, blendFactor)
	end
	lookTarget = Vector3.new(viewMidpoint.X, viewMidpointY + 1, viewMidpoint.Z)

	if not smoothedCameraPos then
		smoothedCameraPos = cameraGoal
		smoothedLookTarget = lookTarget
	end

	local playerVelocity = playerRoot.AssemblyLinearVelocity
	local playerSpeed = playerVelocity.Magnitude

	local MIN_CAMERA_LERP = 0.15
	local MAX_CAMERA_LERP = 0.5
	local VELOCITY_INFLUENCE = 60
	local CLOSE_RANGE_SLOWDOWN = 0.7

	local baseCameraSpeed = MIN_CAMERA_LERP + (playerSpeed / VELOCITY_INFLUENCE)
	local cameraSpeed = math.clamp(baseCameraSpeed, MIN_CAMERA_LERP, MAX_CAMERA_LERP)

	if distToTarget < LockOn.CLOSE_DISTANCE_THRESHOLD then
		local closeRatio = 1 - (distToTarget / LockOn.CLOSE_DISTANCE_THRESHOLD)
		cameraSpeed = cameraSpeed * (1 - closeRatio * (1 - CLOSE_RANGE_SLOWDOWN))
	end

	smoothedCameraPos = (smoothedCameraPos :: Vector3):Lerp(cameraGoal, cameraSpeed)
	smoothedLookTarget = (smoothedLookTarget :: Vector3):Lerp(lookTarget, cameraSpeed)

	playerCamera.CameraType = Enum.CameraType.Scriptable
	local currentCF = playerCamera.CFrame
	local newPos = smoothedCameraPos :: Vector3
	local finalLerp = math.clamp(MIN_CAMERA_LERP + (playerSpeed / 120), MIN_CAMERA_LERP, MAX_CAMERA_LERP * 0.8)
	playerCamera.CFrame = currentCF:Lerp(CFrame.lookAt(newPos, smoothedLookTarget :: Vector3), finalLerp)

	LockOn.toggleGuiVisibility(distToTarget)
	LockOn.updateLockOnGuiVisuals(distToTarget, targetHumanoid)
end

local function onCharacterAdded(newCharacter: Model)
	playerCharacter = newCharacter
	playerRoot = newCharacter:WaitForChild("HumanoidRootPart") :: Part
	playerHumanoid = newCharacter:WaitForChild("Humanoid") :: Humanoid
	playerLastHealth = playerHumanoid.Health

	isLocked = false
	currentTargetModel = nil
	releaseMouseLock()
	LockOn.resetState()
	LockOn.removeLockOnGui()
	smoothedCameraPos = nil
	smoothedLookTarget = nil
	smoothedSideRatio = 0
	sideLocked = false
	lastLockOnStyle = nil
	smoothedFlatLook = nil
	orbitDir = nil

	watchServerLock(newCharacter)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

Remotes.CameraShake.OnClientEvent:Connect(function(intensity: number, _duration: number)
	if config.Shake then
		hitShakeIntensity = intensity
	end
end)

UserInputService.InputBegan:Connect(handleLockOn)
RunService.RenderStepped:Connect(updateCamera)
