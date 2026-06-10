--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animations = require(ReplicatedStorage.Modules.Animations)

local Flight = {}

Flight.DEFAULT_FLIGHT_SPEED = 1.5
Flight.COMBAT_FLIGHT_SPEED = 1.0
Flight.BLOCKING_FLIGHT_SPEED = 0.3
Flight.BOOST_SPEED_MULTIPLIER = 6
Flight.ATTACK_SPEED_MULTIPLIER = 0.4

local GYRO_D = 150
local GYRO_P = 3000
local GYRO_MAX_TORQUE = Vector3.new(300000, 300000, 300000)

local POSITION_D = 350
local POSITION_BOOST_D = 500 -- D swaps to this while boosting (snappier), matching old BoostD attribute
local POSITION_P = 3000
local POSITION_MAX_FORCE = Vector3.new(30000, 30000, 30000)

local POSITION_NAME = "FlyingPosition"
local GYRO_NAME = "FlyingGyro"
local UP = Vector3.yAxis
local EPSILON = 1e-3

export type Intent = {
	move: Vector3, -- world-space desired direction (need NOT be unit); zero = hover
	ascend: boolean,
	descend: boolean,
	boost: boolean,
	lockTarget: Model?, -- when set, face this target instead of the move/camera direction
}

export type Movers = {
	position: BodyPosition,
	gyro: BodyGyro,
}

local function targetPart(model: Model): BasePart?
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	local torso = model:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		return torso
	end
	return nil
end

local function flatten(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function buildGyro(): BodyGyro
	local template = script:FindFirstChild(GYRO_NAME)
	if template and template:IsA("BodyGyro") then
		return template:Clone()
	end
	local gyro = Instance.new("BodyGyro")
	gyro.Name = GYRO_NAME
	gyro.D = GYRO_D
	gyro.P = GYRO_P
	gyro.MaxTorque = GYRO_MAX_TORQUE
	return gyro
end

local function buildPosition(): BodyPosition
	local template = script:FindFirstChild(POSITION_NAME)
	if template and template:IsA("BodyPosition") then
		return template:Clone()
	end
	local position = Instance.new("BodyPosition")
	position.Name = POSITION_NAME
	position.D = POSITION_D
	position.P = POSITION_P
	position.MaxForce = POSITION_MAX_FORCE
	return position
end

function Flight.attach(character: Model): Movers?
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end

	local existingPosition = root:FindFirstChild(POSITION_NAME)
	local existingGyro = root:FindFirstChild(GYRO_NAME)
	local position = if existingPosition and existingPosition:IsA("BodyPosition")
		then existingPosition
		else buildPosition()
	local gyro = if existingGyro and existingGyro:IsA("BodyGyro") then existingGyro else buildGyro()

	position.Position = root.Position
	gyro.CFrame = root.CFrame
	position.Parent = root
	gyro.Parent = root

	return { position = position, gyro = gyro }
end

function Flight.detach(character: Model): ()
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		for _, name in { POSITION_NAME, GYRO_NAME } do
			local mover = root:FindFirstChild(name)
			if mover then
				mover:Destroy()
			end
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
	end

	Flight.stopAnimation(character)
end

function Flight.resolveSpeed(character: Model): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 1 then
		return 0
	end
	if
		character:GetAttribute("ToggleRagdoll")
		or character:GetAttribute("Stunned")
		or character:GetAttribute("KiBlasting")
	then
		return 0
	end
	if character:GetAttribute("Blocking") then
		return Flight.BLOCKING_FLIGHT_SPEED
	end

	local base = if character:GetAttribute("CombatTag") then Flight.COMBAT_FLIGHT_SPEED else Flight.DEFAULT_FLIGHT_SPEED
	if character:GetAttribute("AttackCooldown") then
		base *= Flight.ATTACK_SPEED_MULTIPLIER
	end
	return base
end

function Flight.computeRotation(root: BasePart, facingCFrame: CFrame, intent: Intent): CFrame
	local position = root.Position

	local lockTarget = intent.lockTarget
	if lockTarget then
		local part = targetPart(lockTarget)
		if part then
			return CFrame.lookAt(position, part.Position)
		end
	end

	if intent.boost and not (intent.ascend or intent.descend) then
		return CFrame.lookAt(position, position + facingCFrame.LookVector)
	end

	local horizontal = flatten(intent.move)
	if horizontal.Magnitude > EPSILON then
		-- Face the camera's flat forward, NOT the move direction, so movement keys
		-- translate the body without spinning it: S flies backwards and A/D strafe
		-- while still facing forward. chooseAnimation() picks the matching pose.
		local facing = flatten(facingCFrame.LookVector)
		if facing.Magnitude > EPSILON then
			return CFrame.lookAt(position, position + facing.Unit)
		end
	end

	return root.CFrame
end

function Flight.chooseAnimation(intent: Intent, facingCFrame: CFrame): string
	local lockedOn = intent.lockTarget ~= nil
	local horizontal = flatten(intent.move)

	if horizontal.Magnitude < EPSILON then
		if intent.ascend then
			return "ascend"
		elseif intent.descend then
			return "descend"
		end
		return if lockedOn then "fightingstance" else "flyidle"
	end

	local moveUnit = horizontal.Unit
	local forwardDot = moveUnit:Dot(flatten(facingCFrame.LookVector).Unit)
	local rightDot = moveUnit:Dot(flatten(facingCFrame.RightVector).Unit)

	-- When locked on the body faces the target, so movement still reads as fly forwards/
	-- backwards/strafe relative to it (the caller passes a target-facing basis). lockedonboost
	-- is the locked-on dash, so it only replaces the forward boost -- not every direction.
	if math.abs(forwardDot) >= math.abs(rightDot) then
		if forwardDot >= 0 then
			if intent.boost then
				return if lockedOn then "lockedonboost" else "boost"
			end
			return "flyforwards"
		end
		return "flybackwards"
	end
	return if rightDot >= 0 then "flyright" else "flyleft"
end

function Flight.step(character: Model, movers: Movers, intent: Intent, facingCFrame: CFrame, speed: number): ()
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	-- Knockback: zero our force so KnockbackVelocity throws us; server snaps back via UpdateFlightPosition on recovery.
	if character:GetAttribute("HitByKnockBack") then
		movers.position.MaxForce = Vector3.zero
		movers.gyro.CFrame = root.CFrame
		return
	end
	movers.position.MaxForce = POSITION_MAX_FORCE

	if speed <= 0 then
		movers.position.Position = root.Position
		movers.gyro.CFrame = root.CFrame
		return
	end

	movers.gyro.CFrame = Flight.computeRotation(root, facingCFrame, intent)

	if character:GetAttribute("Charging") then
		movers.position.Position = root.Position
		return
	end

	movers.position.D = if intent.boost then POSITION_BOOST_D else POSITION_D

	local effective = speed * (if intent.boost then Flight.BOOST_SPEED_MULTIPLIER else 1)
	local target = root.Position
	-- intent.move is the full world-space desired direction (see the type above). The
	-- player controller already flattens it for non-boost free flight, and the AI passes
	-- a flat move with ascend/descend set -- so honoring its Y here only affects the cases
	-- that encode a vertical direction: boosting (and approaching a lock-on target) while
	-- looking up/down now climbs or dives instead of sliding flat.
	if intent.move.Magnitude > EPSILON then
		target += intent.move.Unit * effective
	end
	if intent.ascend then
		target += UP * effective
	end
	if intent.descend then
		target -= UP * effective
	end
	movers.position.Position = target
end

-- Weak-keyed table; entries die with the model when garbage-collected.
local currentFlightAnimation = setmetatable({} :: { [Model]: string }, { __mode = "k" })

function Flight.playAnimation(character: Model, name: string): ()
	if currentFlightAnimation[character] == name then
		return
	end
	local previous = currentFlightAnimation[character]
	if previous then
		Animations.stop(character, previous, 0.15)
	end
	currentFlightAnimation[character] = name
	Animations.play(character, name, 0.15)
end

function Flight.stopAnimation(character: Model): ()
	local current = currentFlightAnimation[character]
	if current then
		Animations.stop(character, current, 0.15)
		currentFlightAnimation[character] = nil
	end
end

-- Health floor is 1 (downed state); require strictly above it to allow takeoff.
function Flight.canTakeOff(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 1 then
		return false
	end
	return not (
		character:GetAttribute("ToggleRagdoll")
		or character:GetAttribute("Stunned")
		or character:GetAttribute("InCustomization")
	)
end

function Flight.setEnabled(character: Model, enabled: boolean): boolean
	if enabled then
		if character:GetAttribute("Flying") then
			return true
		end
		if not Flight.canTakeOff(character) then
			return false
		end
		character:SetAttribute("Flying", true)
		return true
	end

	character:SetAttribute("Flying", false)
	character:SetAttribute("BoostFlying", false)
	return false
end

function Flight.setBoost(character: Model, boost: boolean): ()
	if not character:GetAttribute("Flying") then
		return
	end
	character:SetAttribute("BoostFlying", boost)
end

return Flight
