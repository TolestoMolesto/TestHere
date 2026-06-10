local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local ActionController = require(ServerStorage.Modules.ActionController)
-- Knockback required lazily at point of use: it indexes a place-side FX asset at load, which breaks boot on a bare place.
local Block = require(ServerStorage.Modules.Block)
local Flight = require(ReplicatedStorage.Modules.Flight)

local AIController = {}

local TICK = 0.1
local ATTACK_RANGE = 6
local BLOCK_RANGE = 8
local BLOCK_HOLD = 0.4
local BLOCK_COOLDOWN = 1.2
local STRAFE_RANGE = 9
local STRAFE_STEP = 4
local STRAFE_MIN = 0.4
local STRAFE_MAX = 0.9
local PUNISH_INTERVAL_SCALE = 0.6
local FACE_ALIGN_THRESHOLD = 0.985 -- cos(~10°); skip pivot when already aligned
local FLY_TAKEOFF_HEIGHT = 8
local FLY_VERTICAL_DEADZONE = 1.5

export type Level = "Beginner" | "Advanced" | "Master" | "Legendary"

export type Profile = {
	reactionTime: number,
	recoverDelay: number,
	parryWindow: number,
	heavyChance: number,
	blockChance: number,
	aggression: number,
	attackInterval: number,
}

AIController.DEFAULT_LEVEL = "Master" :: Level

AIController.PROFILES = {
	Beginner = {
		reactionTime = 0.45,
		recoverDelay = 0.7,
		parryWindow = 0.06,
		heavyChance = 0.10,
		blockChance = 0.35,
		aggression = 0.45,
		attackInterval = 0.75,
	},
	Advanced = {
		reactionTime = 0.32,
		recoverDelay = 0.5,
		parryWindow = 0.12,
		heavyChance = 0.18,
		blockChance = 0.55,
		aggression = 0.60,
		attackInterval = 0.60,
	},
	Master = {
		reactionTime = 0.22,
		recoverDelay = 0.4,
		parryWindow = 0.20,
		heavyChance = 0.25,
		blockChance = 0.75,
		aggression = 0.75,
		attackInterval = 0.50,
	},
	Legendary = {
		reactionTime = 0.12,
		recoverDelay = 0.25,
		parryWindow = 0.32,
		heavyChance = 0.35,
		blockChance = 0.92,
		aggression = 0.90,
		attackInterval = 0.40,
	},
} :: { [string]: Profile }

function AIController.getProfile(level: Level?): Profile
	return AIController.PROFILES[level or AIController.DEFAULT_LEVEL]
		or AIController.PROFILES[AIController.DEFAULT_LEVEL]
end

export type Options = {
	owner: Model,
	level: Level?,
}

type Brain = {
	npc: Model,
	humanoid: Humanoid,
	root: BasePart,
	owner: Model,
	config: Profile,

	running: boolean,
	engaged: boolean,
	state: string,
	stateEnteredAt: number,

	lastAttackAt: number,
	canAttackAt: number,
	blockOnCooldown: boolean,
	defendUntil: number,
	strafeDir: number,
	strafeUntil: number,
	recoverGen: number, -- generation counter guards the difficulty-delayed knockback cancel

	flying: boolean,
	movers: Flight.Movers?,
	flightConn: RBXScriptConnection?,
	flightIntent: Flight.Intent?,

	target: BasePart?,
	distance: number,
	targetAirborne: boolean,
	selfHurt: boolean,
	ownerOpen: boolean,
	ownerBlocking: boolean,

	connections: { RBXScriptConnection },
}

local function ownerRoot(brain: Brain): BasePart?
	local owner = brain.owner
	if not owner or not owner.Parent then
		return nil
	end
	local ownerHumanoid = owner:FindFirstChildOfClass("Humanoid")
	if not ownerHumanoid or ownerHumanoid.Health <= 0 then
		return nil
	end
	return owner:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- PivotTo every tick on a server-owned rig fights the Humanoid stand force (floor-sink replication); only re-aim on a genuine turn.
local function faceToward(brain: Brain, targetPos: Vector3): ()
	local root = brain.root
	local from = root.Position
	local flat = Vector3.new(targetPos.X, from.Y, targetPos.Z)
	local toTarget = flat - from
	if toTarget.Magnitude < 0.05 then
		return
	end
	if root.CFrame.LookVector:Dot(toTarget.Unit) >= FACE_ALIGN_THRESHOLD then
		return
	end
	brain.npc:PivotTo(CFrame.lookAt(from, flat))
end

local function perceive(brain: Brain): ()
	local target = ownerRoot(brain)
	brain.target = target
	brain.distance = if target then (target.Position - brain.root.Position).Magnitude else math.huge

	local npc = brain.npc
	-- Ragdoll counts as hurt: per-tick PivotTo/MoveTo would snap the rig upright and fight its own ragdoll.
	brain.selfHurt = npc:GetAttribute("HitByKnockBack") == true
		or npc:GetAttribute("Stunned") == true
		or npc:GetAttribute("ToggleRagdoll") == true

	local owner = brain.owner
	brain.ownerOpen = owner:GetAttribute("Stunned") == true
		or owner:GetAttribute("HitByKnockBack") == true
		or owner:GetAttribute("BlockBroken") == true
	brain.ownerBlocking = owner:GetAttribute("Blocking") == true

	local verticalGap = if target then target.Position.Y - brain.root.Position.Y else 0
	brain.targetAirborne = target ~= nil and (owner:GetAttribute("Flying") == true or verticalGap > FLY_TAKEOFF_HEIGHT)
end

local function hoverFacing(brain: Brain): ()
	brain.flightIntent = {
		move = Vector3.zero,
		ascend = false,
		descend = false,
		boost = false,
		lockTarget = brain.owner,
	}
end

local function moveToward(brain: Brain, worldPos: Vector3): ()
	if brain.flying then
		local delta = worldPos - brain.root.Position
		brain.flightIntent = {
			move = Vector3.new(delta.X, 0, delta.Z),
			ascend = delta.Y > FLY_VERTICAL_DEADZONE,
			descend = delta.Y < -FLY_VERTICAL_DEADZONE,
			boost = false,
			lockTarget = brain.owner,
		}
	else
		brain.humanoid:MoveTo(worldPos)
	end
end

local HOVER_INTENT: Flight.Intent =
	{ move = Vector3.zero, ascend = false, descend = false, boost = false, lockTarget = nil }

local function startFlying(brain: Brain): ()
	if brain.flying then
		return
	end
	if not Flight.setEnabled(brain.npc, true) then
		return
	end
	brain.movers = Flight.attach(brain.npc)
	if not brain.movers then
		Flight.setEnabled(brain.npc, false)
		return
	end
	brain.flying = true
	brain.flightIntent = nil
	brain.humanoid.PlatformStand = true
	brain.humanoid.AutoRotate = false
	brain.flightConn = RunService.Heartbeat:Connect(function()
		if not brain.running or not brain.flying or not brain.movers then
			return
		end
		local intent = brain.flightIntent or HOVER_INTENT
		local speed = Flight.resolveSpeed(brain.npc)
		Flight.step(brain.npc, brain.movers, intent, brain.root.CFrame, speed)
		Flight.playAnimation(brain.npc, Flight.chooseAnimation(intent, brain.root.CFrame))
	end)
end

local function stopFlying(brain: Brain): ()
	if not brain.flying then
		return
	end
	brain.flying = false
	if brain.flightConn then
		brain.flightConn:Disconnect()
		brain.flightConn = nil
	end
	brain.movers = nil
	brain.flightIntent = nil
	Flight.setEnabled(brain.npc, false)
	Flight.detach(brain.npc)
end

local function updateFlightMode(brain: Brain): ()
	if brain.selfHurt then
		return
	end
	-- Take off whenever the owner is airborne -- even before the shadow is engaged -- so a
	-- shadow spawned mid-flight hovers alongside the player instead of dropping to the ground.
	if brain.targetAirborne and not brain.flying and brain.target then
		startFlying(brain)
	elseif not brain.targetAirborne and brain.flying then
		stopFlying(brain)
	end
end

type State = {
	enter: ((Brain) -> ())?,
	exit: ((Brain) -> ())?,
	update: (Brain) -> string?,
}

local States: { [string]: State } = {}

local function setState(brain: Brain, name: string): ()
	if brain.state == name then
		return
	end
	local previous = States[brain.state]
	if previous and previous.exit then
		previous.exit(brain)
	end
	brain.state = name
	brain.stateEnteredAt = os.clock()
	local entering = States[name]
	if entering and entering.enter then
		entering.enter(brain)
	end
end

States.Idle = {
	update = function(brain: Brain): string?
		if brain.engaged and brain.target then
			return "Pursue"
		end
		return nil
	end,
}

States.Pursue = {
	update = function(brain: Brain): string?
		local target = brain.target
		if not target then
			return "Idle"
		end
		if brain.distance <= ATTACK_RANGE then
			return "Attack"
		end
		moveToward(brain, target.Position)
		return nil
	end,
}

States.Strafe = {
	enter = function(brain: Brain): ()
		brain.strafeDir = if math.random() < 0.5 then 1 else -1
		brain.strafeUntil = os.clock() + STRAFE_MIN + math.random() * (STRAFE_MAX - STRAFE_MIN)
	end,
	update = function(brain: Brain): string?
		local target = brain.target
		if not target then
			return "Idle"
		end
		if brain.ownerOpen then
			return "Attack"
		end
		if os.clock() >= brain.strafeUntil then
			return if brain.distance <= ATTACK_RANGE then "Attack" else "Pursue"
		end
		if brain.distance > STRAFE_RANGE + ATTACK_RANGE then
			return "Pursue" -- drifted too far; re-close
		end

		if brain.flying then
			hoverFacing(brain)
			return nil
		end
		local selfPos = brain.root.Position
		local targetPos = target.Position
		local flatRadial = Vector3.new(selfPos.X - targetPos.X, 0, selfPos.Z - targetPos.Z)
		if flatRadial.Magnitude < 0.1 then
			flatRadial = Vector3.new(0, 0, 1)
		end
		local radial = flatRadial.Unit
		local tangent = Vector3.new(-radial.Z, 0, radial.X) * brain.strafeDir
		local desired = targetPos + radial * STRAFE_RANGE + tangent * STRAFE_STEP

		brain.humanoid:MoveTo(desired)
		faceToward(brain, targetPos)
		return nil
	end,
}

States.Attack = {
	update = function(brain: Brain): string?
		local target = brain.target
		if not target then
			return if brain.engaged then "Pursue" else "Idle"
		end
		if brain.distance > ATTACK_RANGE then
			return "Pursue"
		end

		if brain.flying then
			hoverFacing(brain)
		else
			brain.humanoid:MoveTo(brain.root.Position)
			faceToward(brain, target.Position)
		end

		local now = os.clock()
		if now < brain.canAttackAt then
			return nil
		end

		local config = brain.config
		local interval = if brain.ownerOpen
			then config.attackInterval * PUNISH_INTERVAL_SCALE
			else config.attackInterval
		if now - brain.lastAttackAt < interval then
			return nil
		end
		brain.lastAttackAt = now

		local npc = brain.npc
		local heavyReady = not npc:GetAttribute("HeavyCooldown")

		if brain.ownerBlocking then
			if heavyReady then
				ActionController.perform(npc, "HeavyAttack")
			else
				return "Strafe"
			end
		elseif brain.ownerOpen then
			ActionController.perform(npc, if heavyReady and math.random() < 0.5 then "HeavyAttack" else "LightAttack")
		else
			local useHeavy = heavyReady and math.random() < config.heavyChance
			ActionController.perform(npc, if useHeavy then "HeavyAttack" else "LightAttack")
		end

		local lowStamina = ((npc:GetAttribute("Stamina") :: number?) or 0) <= 0
		if not brain.ownerOpen and (lowStamina or math.random() > config.aggression) then
			return "Strafe"
		end
		return nil
	end,
}

States.Defend = {
	enter = function(brain: Brain): ()
		brain.defendUntil = os.clock() + BLOCK_HOLD
		brain.blockOnCooldown = true
		task.delay(BLOCK_COOLDOWN, function(): ()
			brain.blockOnCooldown = false
		end)
	end,
	exit = function(brain: Brain): ()
		Block.stop(brain.npc)
	end,
	update = function(brain: Brain): string?
		if os.clock() >= brain.defendUntil then
			return if brain.distance <= ATTACK_RANGE then "Attack" else "Pursue"
		end
		if brain.target then
			if brain.flying then
				hoverFacing(brain)
			else
				faceToward(brain, brain.target.Position)
			end
		end
		return nil
	end,
}

States.Recover = {
	update = function(brain: Brain): string?
		if brain.selfHurt then
			return nil
		end
		if brain.target then
			return if brain.distance <= ATTACK_RANGE then "Attack" else "Pursue"
		end
		return "Idle"
	end,
}

function AIController.start(npc: Model, options: Options): () -> ()
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		warn("[AIController] NPC missing Humanoid/HumanoidRootPart -- not starting")
		return function() end
	end

	local brain: Brain = {
		npc = npc,
		humanoid = humanoid,
		root = root,
		owner = options.owner,
		config = AIController.getProfile(options.level),

		running = true,
		engaged = false,
		state = "Idle",
		stateEnteredAt = os.clock(),

		lastAttackAt = 0,
		canAttackAt = 0,
		blockOnCooldown = false,
		defendUntil = 0,
		strafeDir = 1,
		strafeUntil = 0,
		recoverGen = 0,

		flying = false,
		movers = nil,
		flightConn = nil,
		flightIntent = nil,

		target = nil,
		distance = math.huge,
		targetAirborne = false,
		selfHurt = false,
		ownerOpen = false,
		ownerBlocking = false,

		connections = {},
	}

	local function stop(): ()
		if not brain.running then
			return
		end
		brain.running = false
		for _, c in brain.connections do
			c:Disconnect()
		end
		table.clear(brain.connections)
		stopFlying(brain)
		if npc.Parent then
			Block.stop(npc)
		end
	end

	local lastHealth = humanoid.Health
	table.insert(
		brain.connections,
		humanoid.HealthChanged:Connect(function(health: number)
			if health < lastHealth and not brain.engaged then
				brain.engaged = true
				brain.canAttackAt = os.clock() + brain.config.reactionTime
				if brain.state == "Idle" then
					setState(brain, "Pursue")
				end
			end
			lastHealth = health
		end)
	)

	table.insert(brain.connections, humanoid.Died:Connect(stop))

	table.insert(
		brain.connections,
		npc:GetAttributeChangedSignal("HitByKnockBack"):Connect(function()
			if not npc:GetAttribute("HitByKnockBack") then
				return
			end
			setState(brain, "Recover")

			local gen = brain.recoverGen + 1
			brain.recoverGen = gen
			task.delay(brain.config.recoverDelay, function(): ()
				if brain.running and npc.Parent and brain.recoverGen == gen and npc:GetAttribute("HitByKnockBack") then
					require(ServerStorage.Modules.Knockback).cancel(npc)
				end
			end)
		end)
	)

	table.insert(
		brain.connections,
		npc:GetAttributeChangedSignal("Stunned"):Connect(function()
			if npc:GetAttribute("Stunned") then
				setState(brain, "Recover")
			end
		end)
	)

	table.insert(
		brain.connections,
		options.owner:GetAttributeChangedSignal("Swinging"):Connect(function()
			if not options.owner:GetAttribute("Swinging") then
				return
			end
			if not brain.engaged or brain.blockOnCooldown or brain.state == "Recover" or brain.selfHurt then
				return
			end
			if
				npc:GetAttribute("Attacking")
				or npc:GetAttribute("Stunned")
				or npc:GetAttribute("HitByKnockBack")
				or npc:GetAttribute("Blocking")
			then
				return
			end
			local target = ownerRoot(brain)
			if not target or (target.Position - root.Position).Magnitude > BLOCK_RANGE then
				return
			end
			if math.random() > brain.config.blockChance then
				return
			end
			if Block.start(npc, brain.config.parryWindow) then
				setState(brain, "Defend")
			end
		end)
	)

	task.spawn(function(): ()
		while brain.running and npc.Parent and humanoid.Health > 0 do
			perceive(brain)
			updateFlightMode(brain)

			if brain.selfHurt and brain.state ~= "Recover" then
				setState(brain, "Recover")
			end

			local handler = States[brain.state]
			if handler then
				local nextState = handler.update(brain)
				if nextState and not brain.selfHurt then
					setState(brain, nextState)
				end
			end

			task.wait(TICK)
		end
		stop()
	end)

	return stop
end

return AIController
