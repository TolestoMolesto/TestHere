--!strict
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Animations = require(ReplicatedStorage.Modules.Animations)
local Audio = require(ReplicatedStorage.Modules.Audio)
local CombatTag = require(ServerStorage.Modules.CombatTag)
local Damage = require(ServerStorage.Modules.Damage)
local HitFX = require(ServerStorage.Modules.HitFX)
local TargetLock = require(ServerStorage.Modules.TargetLock)
local Train = require(ServerStorage.Modules.Train)

local KI_BLAST_COOLDOWN = 0.5
local KI_COST_FRACTION = 0.05
local KI_BLAST_SPEED = 200
local KI_BLAST_LIFETIME = 8
local KI_BLAST_PROXIMITY = 3
local KI_BLAST_BASE_DAMAGE = 1
local SPAWN_OFFSET = CFrame.new(0, 1, -3)
local DEFAULT_KI_COLOUR = Color3.fromRGB(255, 255, 255)
local KI_BLAST_SOUND_ID = "rbxassetid://586187912"
local KI_BLAST_SOUND_LIFETIME = 4

local lastHand = setmetatable({} :: { [Model]: string }, { __mode = "k" })

local function isFighter(model: Instance, firer: Model): boolean
	if model == firer or not model:IsA("Model") then
		return false
	end
	-- Spawn-protected (Forcefield) targets are intangible: the blast passes through them.
	if model:GetAttribute("Forcefield") then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	return humanoid ~= nil and root ~= nil and humanoid.Health > 0
end

local function getKiColour(character: Model): Color3
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local appearance = humanoid and humanoid:FindFirstChild("Appearance")
	if appearance then
		local r = appearance:GetAttribute("KiColorR") :: number?
		local g = appearance:GetAttribute("KiColorG") :: number?
		local b = appearance:GetAttribute("KiColorB") :: number?
		if r and g and b and r >= 0 and g >= 0 and b >= 0 then
			return Color3.fromRGB(r, g, b)
		end
	end
	return DEFAULT_KI_COLOUR
end

local function tintBlast(blast: Instance, colour: Color3): ()
	if blast:IsA("BasePart") then
		blast.Color = colour
	end
	local sequence = ColorSequence.new(colour)
	for _, descendant in blast:GetDescendants() do
		if descendant:IsA("Trail") or descendant:IsA("ParticleEmitter") then
			local colorable = descendant :: any
			colorable.Color = sequence
		end
	end
end

local function emitAll(blast: Instance, count: number): ()
	for _, descendant in blast:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			descendant:Emit(count)
		end
	end
end

return function(invoker: Model, requestedCFrame: CFrame?): ()
	local hrp = invoker:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	-- State gating is enforced centrally in ActionController.perform via ActionConfig.KiBlast.blockedBy.
	local maxKi = invoker:GetAttribute("MaxKi") :: number? or 0
	local currentKi = invoker:GetAttribute("Ki") :: number? or 0
	local kiCost = maxKi * KI_COST_FRACTION
	if currentKi < kiCost then
		return
	end

	local template = ServerStorage.Assets:FindFirstChild("KiBlast")
	if not template or not template:IsA("BasePart") then
		warn("[KiBlast] prefab ServerStorage.Assets.KiBlast missing -- no projectile fired")
		return
	end

	invoker:SetAttribute("Ki", currentKi - kiCost)
	invoker:SetAttribute("KiBlasting", true)

	local player = Players:GetPlayerFromCharacter(invoker)
	if not player then
		local side = if lastHand[invoker] == "Right" then "Left" else "Right"
		lastHand[invoker] = side
		Animations.play(invoker, if side == "Right" then "kiblastright" else "kiblastleft", 0.1)
	end

	local sound = Instance.new("Sound")
	sound.SoundId = KI_BLAST_SOUND_ID
	sound.SoundGroup = Audio.group("SFX")
	sound.Parent = hrp
	sound:Play()
	Debris:AddItem(sound, KI_BLAST_SOUND_LIFETIME)

	local muzzle = if requestedCFrame then CFrame.new(hrp.Position) * requestedCFrame.Rotation else hrp.CFrame
	local blast = template:Clone() :: Part
	tintBlast(blast, getKiColour(invoker))
	emitAll(blast, 5)
	blast.CFrame = muzzle * SPAWN_OFFSET
	blast.Anchored = true
	blast.CanCollide = false
	blast.Parent = Workspace:FindFirstChild("Ignore") or Workspace

	Debris:AddItem(blast, KI_BLAST_LIFETIME)

	local startClock = os.clock()
	local hitRegistered = false
	local connection: RBXScriptConnection? = nil

	local function cleanup(): ()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		if blast.Parent then
			blast:Destroy()
		end
	end

	local function registerHit(target: Instance): ()
		if hitRegistered or not isFighter(target, invoker) then
			return
		end
		local victim = target :: Model

		if victim:GetAttribute("InSafeZone") or victim:GetAttribute("Blocking") then
			hitRegistered = true
			cleanup()
			return
		end

		hitRegistered = true
		local hitPosition = blast.Position
		cleanup()

		-- A return of 0 means the target dodged: the blast is still spent (Ki paid up-front)
		-- but lands none of the on-hit reactions.
		if Damage.apply(victim, invoker, KI_BLAST_BASE_DAMAGE, "Ki") == 0 then
			Train.dodged(victim, invoker)
			return
		end

		HitFX.spawnOnCharacter(victim, hitPosition)
		CombatTag.applyCombatTag(invoker, victim)
		Train.landedKiBlast(invoker, victim)
	end

	connection = RunService.Heartbeat:Connect(function(dt: number): ()
		if hitRegistered or not blast.Parent or os.clock() - startClock > KI_BLAST_LIFETIME then
			cleanup()
			return
		end

		local target = TargetLock.get(invoker)
		local targetRoot = target and target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if target and targetRoot then
			local toTarget = targetRoot.Position - blast.Position
			local distance = toTarget.Magnitude
			if distance <= KI_BLAST_PROXIMITY then
				registerHit(target)
				return
			end
			blast.CFrame = CFrame.new(blast.Position + (toTarget / distance) * KI_BLAST_SPEED * dt, targetRoot.Position)
		else
			blast.CFrame = blast.CFrame + blast.CFrame.LookVector * KI_BLAST_SPEED * dt
		end
	end)

	blast.Touched:Connect(function(part: BasePart): ()
		if hitRegistered then
			return
		end
		local model = part:FindFirstAncestorOfClass("Model")
		if model then
			registerHit(model)
		end
	end)

	task.delay(KI_BLAST_COOLDOWN, function(): ()
		if invoker.Parent then
			invoker:SetAttribute("KiBlasting", false)
		end
	end)
end
