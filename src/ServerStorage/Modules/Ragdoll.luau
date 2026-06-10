--!strict

local PhysicsService = game:GetService("PhysicsService")

local Ragdoll = {}

local ROOT_JOINT = "RootJoint"

local SOCKET_LIMITS = false
local SOCKET_UPPER_ANGLE = 45
local SOCKET_TWIST = 45

local COLLISION_GROUP = "Ragdoll"
-- groupReady gates use of the group so a pcall failure here can't break ragdolling outright.
local groupReady = pcall(function()
	if not PhysicsService:IsCollisionGroupRegistered(COLLISION_GROUP) then
		PhysicsService:RegisterCollisionGroup(COLLISION_GROUP)
	end
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP, COLLISION_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP, "Default", true)
end)

-- Restore saved state values on disable to re-arm ShadowSpawner's anti-flop baseline for shadows and leave players untouched.
local MANAGED_STATES = {
	Enum.HumanoidStateType.Physics,
	Enum.HumanoidStateType.GettingUp,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
}

type Record = {
	motors: { Motor6D },
	created: { Instance },
	savedCollide: { [BasePart]: boolean },
	savedStates: { [Enum.HumanoidStateType]: boolean },
	savedPlatformStand: boolean,
	savedAutoRotate: boolean,
}

local active = setmetatable({} :: { [Model]: Record }, { __mode = "k" })

-- Generation guard: a re-knock mid-flop bumps the counter so only the latest timer fires.
local knockdownGen = setmetatable({} :: { [Model]: number }, { __mode = "k" })

local function buildSocket(motor: Motor6D, into: { Instance }): ()
	local part0 = motor.Part0
	local part1 = motor.Part1
	if not part0 or not part1 then
		return
	end

	local a0 = Instance.new("Attachment")
	a0.Name = "RagdollAtt0"
	a0.CFrame = motor.C0
	a0.Parent = part0

	local a1 = Instance.new("Attachment")
	a1.Name = "RagdollAtt1"
	a1.CFrame = motor.C1
	a1.Parent = part1

	local socket = Instance.new("BallSocketConstraint")
	socket.Name = "RagdollSocket"
	socket.Attachment0 = a0
	socket.Attachment1 = a1
	socket.LimitsEnabled = SOCKET_LIMITS
	if SOCKET_LIMITS then
		socket.UpperAngle = SOCKET_UPPER_ANGLE
		socket.TwistLimitsEnabled = true
		socket.TwistLowerAngle = -SOCKET_TWIST
		socket.TwistUpperAngle = SOCKET_TWIST
	end
	socket.Parent = part0

	motor.Enabled = false

	table.insert(into, a0)
	table.insert(into, a1)
	table.insert(into, socket)
end

local function buildCollider(part: BasePart, character: Model, into: { Instance }): ()
	local collider = Instance.new("Part")
	collider.Name = "RagdollCollider"
	collider.Size = part.Size
	collider.CFrame = part.CFrame
	collider.Transparency = 1
	collider.CanCollide = true
	collider.CanQuery = false
	collider.CanTouch = false
	collider.Massless = true
	if groupReady then
		collider.CollisionGroup = COLLISION_GROUP
	end

	local weld = Instance.new("WeldConstraint")
	weld.Name = "RagdollColliderWeld"
	weld.Part0 = part
	weld.Part1 = collider
	weld.Parent = collider

	collider.Parent = character

	table.insert(into, collider)
	table.insert(into, weld)
end

function Ragdoll.enable(character: Model): ()
	if active[character] then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		warn(`[Ragdoll] {character.Name} missing Humanoid/HumanoidRootPart -- cannot ragdoll`)
		return
	end

	local motors: { Motor6D } = {}
	local created: { Instance } = {}
	local bodyParts: { [BasePart]: boolean } = {}
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") then
			local part0 = descendant.Part0
			local part1 = descendant.Part1
			if part0 then
				bodyParts[part0] = true
			end
			if part1 then
				bodyParts[part1] = true
			end
			if descendant.Name ~= ROOT_JOINT and part0 and part1 then
				buildSocket(descendant, created)
				table.insert(motors, descendant)
			end
		end
	end

	local savedCollide: { [BasePart]: boolean } = {}
	for part in bodyParts do
		savedCollide[part] = part.CanCollide
		part.CanCollide = false
		if part ~= root then
			buildCollider(part, character, created)
		end
	end

	local savedStates: { [Enum.HumanoidStateType]: boolean } = {}
	for _, state in MANAGED_STATES do
		savedStates[state] = humanoid:GetStateEnabled(state)
		humanoid:SetStateEnabled(state, true)
	end

	active[character] = {
		motors = motors,
		created = created,
		savedCollide = savedCollide,
		savedStates = savedStates,
		savedPlatformStand = humanoid.PlatformStand,
		savedAutoRotate = humanoid.AutoRotate,
	}

	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
end

function Ragdoll.disable(character: Model): ()
	local record = active[character]
	if not record then
		return
	end
	active[character] = nil

	for _, instance in record.created do
		instance:Destroy()
	end
	for _, motor in record.motors do
		if motor.Parent then
			motor.Enabled = true
		end
	end

	for part, canCollide in record.savedCollide do
		if part.Parent then
			part.CanCollide = canCollide
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		for _, state in MANAGED_STATES do
			local saved = record.savedStates[state]
			if saved ~= nil then
				humanoid:SetStateEnabled(state, saved)
			end
		end
		humanoid.PlatformStand = record.savedPlatformStand
		humanoid.AutoRotate = record.savedAutoRotate
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
end

function Ragdoll.setEnabled(character: Model, on: boolean): ()
	if on then
		Ragdoll.enable(character)
	else
		Ragdoll.disable(character)
	end
end

function Ragdoll.knockdown(character: Model, duration: number): ()
	character:SetAttribute("ToggleRagdoll", true)

	local generation = (knockdownGen[character] or 0) + 1
	knockdownGen[character] = generation

	task.delay(duration, function()
		if knockdownGen[character] == generation and character.Parent then
			character:SetAttribute("ToggleRagdoll", false)
		end
	end)
end

function Ragdoll.isRagdolled(character: Model): boolean
	return active[character] ~= nil
end

return Ragdoll
