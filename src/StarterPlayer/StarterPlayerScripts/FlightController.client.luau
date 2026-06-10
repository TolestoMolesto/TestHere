local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Audio = require(ReplicatedStorage.Modules.Audio)
local Flight = require(ReplicatedStorage.Modules.Flight)
local Keybinds = require(ReplicatedStorage.Modules.Keybinds)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local player = Players.LocalPlayer

local DOUBLE_TAP_WINDOW = 0.4
local LEAN_SPEED = 0.1
local LAND_PROBE = 5
local EPSILON = 1e-3

local KEY_FORWARD = Enum.KeyCode.W
local KEY_BACK = Enum.KeyCode.S
local KEY_LEFT = Enum.KeyCode.A
local KEY_RIGHT = Enum.KeyCode.D
-- Ascend / Descend / Boost are rebindable -- read from Keybinds (FlightAscend/Descend/Boost).

local character: Model? = nil
local humanoid: Humanoid? = nil
local root: BasePart? = nil
local flying = false
local boosting = false
local movers: Flight.Movers? = nil
local expectingDoubleTap = false

local function flatten(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function send(phase: string, extra: { [string]: any }?)
	local params = { phase = phase }
	if extra then
		for key, value in extra do
			params[key] = value
		end
	end
	Remotes.PerformAction:FireServer("Flight", params)
end

-- Coded SFX (ids in Audio.SFX), routed through the SFX SoundGroup -- no prestaged Sounds folder.
-- Fly is a 2D loop held under the script, started/stopped as you move; Land and ActivateFlight are
-- one-shot 2D pings on landing / takeoff.
local flySound = Audio.create(Audio.SFX.Fly)
flySound.Parent = script

local function playLandSound()
	Audio.play(Audio.SFX.Land)
end

local function playActivateSound()
	Audio.play(Audio.SFX.ActivateFlight)
end

local function setFlySound(on: boolean)
	if on and not flySound.IsPlaying then
		flySound:Play()
	elseif not on and flySound.IsPlaying then
		flySound:Stop()
	end
end

local function getLockTarget(): Model?
	local char = character
	if not char or char:GetAttribute("LockedOn") ~= true then
		return nil
	end
	local value = char:FindFirstChild("LockOnTarget")
	if value and value:IsA("ObjectValue") and value.Value and value.Value:IsA("Model") then
		return value.Value
	end
	return nil
end

local function buildIntent(camera: Camera): Flight.Intent
	local char = character :: Model
	local hrp = root :: BasePart
	local lockTarget = getLockTarget()

	local forward, right
	local lockRoot = lockTarget and lockTarget:FindFirstChild("HumanoidRootPart")
	if lockRoot and lockRoot:IsA("BasePart") then
		forward = CFrame.lookAt(hrp.Position, lockRoot.Position).LookVector
		right = Vector3.new(-forward.Z, 0, forward.X)
	elseif boosting then
		forward = camera.CFrame.LookVector
		right = camera.CFrame.RightVector
	else
		forward = flatten(camera.CFrame.LookVector)
		right = flatten(camera.CFrame.RightVector)
	end

	local move = Vector3.zero
	if UserInputService:IsKeyDown(KEY_FORWARD) then
		move += forward
	end
	if UserInputService:IsKeyDown(KEY_BACK) then
		move -= if boosting then camera.CFrame.LookVector else forward
	end
	if UserInputService:IsKeyDown(KEY_LEFT) then
		move -= right
	end
	if UserInputService:IsKeyDown(KEY_RIGHT) then
		move += right
	end

	return {
		move = move,
		ascend = Keybinds.isDown("FlightAscend"),
		descend = Keybinds.isDown("FlightDescend"),
		boost = boosting,
		lockTarget = lockTarget,
	}
end

local function leanPlayer(rootJoint: Motor6D)
	local hrp = root :: BasePart
	local baseCFrame = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	local relativeVelocity = hrp.CFrame:VectorToObjectSpace(hrp.AssemblyLinearVelocity)
	local x = math.rad(math.clamp(-relativeVelocity.X * 3, -3, 3))
	local z = math.rad(math.clamp(relativeVelocity.Z * 4, -4, 4))
	local rotX = math.rad(math.clamp(hrp.AssemblyAngularVelocity.Y * 3, -3, 3))
	rootJoint.C0 = rootJoint.C0:Lerp(baseCFrame * CFrame.Angles(z, rotX + x, 0), LEAN_SPEED)
end

local landParams = RaycastParams.new()
landParams.FilterType = Enum.RaycastFilterType.Exclude
landParams.IgnoreWater = true

local function groundBelow(): boolean
	local char, hrp = character, root
	if not char or not hrp then
		return false
	end
	landParams.FilterDescendantsInstances = { char }
	local result = Workspace:Raycast(hrp.Position, Vector3.new(0, -LAND_PROBE, 0), landParams)
	return result ~= nil and result.Instance.CanCollide
end

RunService.RenderStepped:Connect(function()
	local char, hrp, hum = character, root, humanoid
	if not (flying and movers and char and char.Parent and hrp and hrp.Parent and hum) then
		setFlySound(false)
		return
	end

	local camera = Workspace.CurrentCamera
	local intent = buildIntent(camera)
	local speed = Flight.resolveSpeed(char)

	-- Locked on, the body faces the target, so the animation basis must too; otherwise it is
	-- the camera. (step() ignores facing while locked on -- it always aims at the target -- but
	-- chooseAnimation needs this basis to read movement as forwards/backwards/strafe.)
	local facing = camera.CFrame
	local lockTarget = intent.lockTarget
	if lockTarget then
		local lockRoot = lockTarget:FindFirstChild("HumanoidRootPart")
		if lockRoot and lockRoot:IsA("BasePart") then
			facing = CFrame.lookAt(hrp.Position, lockRoot.Position)
		end
	end

	Flight.step(char, movers, intent, facing, speed)

	if intent.descend and groundBelow() then
		send("stop")
		setFlySound(false)
		return
	end

	if char:GetAttribute("HitByKnockBack") or char:GetAttribute("Stunned") or char:GetAttribute("Charging") then
		setFlySound(false)
		return
	end

	Flight.playAnimation(char, Flight.chooseAnimation(intent, facing))

	local moving = intent.move.Magnitude > EPSILON or intent.ascend or intent.descend
	local boostMoving = boosting and moving
	hum.PlatformStand = boostMoving
	hum.AutoRotate = not (boostMoving or intent.lockTarget ~= nil)

	local rootJoint = hrp:FindFirstChildOfClass("Motor6D")
	if rootJoint then
		leanPlayer(rootJoint)
	end

	setFlySound(moving)
end)

local function onFlyingChanged()
	local char = character
	if not char then
		return
	end
	local now = char:GetAttribute("Flying") == true
	if now == flying then
		return
	end
	flying = now
	if flying then
		movers = Flight.attach(char)
		if not movers then
			flying = false
		else
			playActivateSound()
		end
	else
		boosting = false
		Flight.detach(char)
		movers = nil
		setFlySound(false)
		playLandSound()
	end
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	if Keybinds.matches(input, "FlightAscend") then
		if expectingDoubleTap then
			expectingDoubleTap = false
			send("toggle")
		else
			expectingDoubleTap = true
			task.delay(DOUBLE_TAP_WINDOW, function()
				expectingDoubleTap = false
			end)
		end
	elseif Keybinds.matches(input, "FlightBoost") then
		local char = character
		if flying and char and not char:GetAttribute("Running") and not boosting then
			boosting = true
			send("boost", { value = true })
		end
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if Keybinds.matches(input, "FlightBoost") and boosting then
		boosting = false
		send("boost", { value = false })
	end
end)

Remotes.UpdateFlightPosition.OnClientEvent:Connect(function(position: any)
	if movers and typeof(position) == "Vector3" then
		movers.position.Position = position
	end
end)

local function bindCharacter(char: Model)
	character = char
	humanoid = char:WaitForChild("Humanoid") :: Humanoid
	root = char:WaitForChild("HumanoidRootPart") :: BasePart
	flying = false
	boosting = false
	movers = nil
	expectingDoubleTap = false

	char:GetAttributeChangedSignal("Flying"):Connect(onFlyingChanged)
	if char:GetAttribute("Flying") then
		onFlyingChanged()
	end

	local diedHumanoid = humanoid :: Humanoid
	diedHumanoid.Died:Connect(function()
		if flying then
			flying = false
			Flight.detach(char)
			movers = nil
			setFlySound(false)
		end
	end)
end

if player.Character then
	bindCharacter(player.Character)
end
player.CharacterAdded:Connect(bindCharacter)
