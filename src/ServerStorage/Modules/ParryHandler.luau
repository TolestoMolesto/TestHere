--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Animations = require(ReplicatedStorage.Modules.Animations)
local GlobalShakeHandler = require(ServerStorage.Modules.GlobalShakeHandler)
local GroundDetectionHandler = require(ServerStorage.Modules.GroundDetectionHandler)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local SharedUtilities = require(ReplicatedStorage.Modules.Utilities)
local Types = require(ServerStorage.Modules.Types)

type Effect = Part & {
	Attacher: {
		Expander: ParticleEmitter,
		Shrink: ParticleEmitter,
	},
}

local EFFECT_TEMPLATE = ServerStorage.HitFX.ParryFXTemplate :: Effect
local DIRECTIONAL_VECTORS = {
	Forward = function(cframe: CFrame, strength: number): (Vector3, CFrame)
		return cframe.LookVector * strength, CFrame.new(0, 0, -strength)
	end,
	Back = function(cframe: CFrame, strength: number): (Vector3, CFrame)
		return cframe.LookVector * -strength, CFrame.new(0, 0, strength)
	end,
	Left = function(cframe: CFrame, strength: number): (Vector3, CFrame)
		return cframe.RightVector * -strength, CFrame.new(-strength, 0, 0)
	end,
	Right = function(cframe: CFrame, strength: number): (Vector3, CFrame)
		return cframe.RightVector * strength, CFrame.new(strength, 0, 0)
	end,
}
local VERTICAL_VECTORS = {
	Up = function(cframe: CFrame, strength: number): (Vector3, CFrame)
		return cframe.UpVector * strength, CFrame.new(0, strength, 0)
	end,
	Down = function(cframe: CFrame, strength: number): (Vector3, CFrame)
		return cframe.UpVector * -strength, CFrame.new(0, -strength, 0)
	end,
}

local configuration = {
	CLEANUP_DELAY = 0.05,
	DEBOUNCE_TIME = 0.5,
	DISTANCE_OFFSET = 4,
	DISTANCE_OFFSET_CLOSE = 4.5,
	DISTANCE_OFFSET_FAR = 7,
	MAX_STRENGTH = 190,
	MAX_VERTICAL_STRENGTH = 70,
	MIN_STRENGTH = 30,
	MIN_VERTICAL_STRENGTH = 30,
	PARRY_CHANCE = 0.5,
	SOUND_CLEANUP_DELAY = 0.5,
	TIMEOUT = 1.2,
	VERTICAL_CHANCE = 0.1,
}

local ParryHandler = {
	Configuration = configuration,
}

local function createRaycastParams(character: Model, enemyCharacter: Model): RaycastParams
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = { character, enemyCharacter, Workspace.IgnoreList }
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	return raycastParams
end

local function validateCharacters(character: Model?, enemyCharacter: Model?): (boolean, BasePart?, BasePart?)
	if not character or not enemyCharacter then
		return false, nil, nil
	end

	local charRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local enemyRoot = enemyCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not charRoot or not enemyRoot then
		return false, nil, nil
	end

	return true, charRoot, enemyRoot
end

local function cleanupBodyMovers(...: BasePart): ()
	for _, root in { ... } do
		local bodyPos = root:FindFirstChild("BodyPosition")
		if bodyPos then
			bodyPos:Destroy()
		end
	end
end

local function setNetworkOwnership(player: Player?, enemyPlayer: Player?, charRoot: BasePart, enemyRoot: BasePart): ()
	pcall(function()
		if player then charRoot:SetNetworkOwner(player) end
	end)
	pcall(function()
		if enemyPlayer then enemyRoot:SetNetworkOwner(enemyPlayer) end
	end)
end

local function playParryAnimation(character: Model, direction: string): ()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local animator = humanoid:FindFirstChild("Animator") :: Animator?
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animationToPlay = if direction == "Left" then script.ParryLeft else script.ParryRight
	if not animationToPlay then return end

	local track = (animator :: Animator):LoadAnimation(animationToPlay)
	track:Play()
	track.Stopped:Once(function()
		track:Destroy()
	end)
end

local function setShadowConfig(character: Model, values: { [string]: boolean }): ()
	local config = character:FindFirstChild("Config")
	if not config then return end

	for name, value in values do
		local boolValue = config:FindFirstChild(name)
		if boolValue and boolValue:IsA("BoolValue") then
			boolValue.Value = value
		end
	end
end

-- Main parry function — called when a perfect block is detected.
-- Accepts raw character Models (no Character wrapper).
function ParryHandler.parry(attacker: Model, target: Model): ()
	local attackingCharacter = attacker :: Types.EntityCharacter
	local targetCharacter = target :: Types.EntityCharacter
	local attackerCombo = attackingCharacter:GetAttribute("ComboCounter") :: number

	Animations.stop(attackingCharacter, "Block")

	if attackerCombo == 3 then
		Animations.play(targetCharacter, "ParryLeft")
	else
		Animations.play(targetCharacter, "ParryRight")
	end

	local effect = EFFECT_TEMPLATE:Clone()
	effect.CFrame = targetCharacter.HumanoidRootPart.CFrame * CFrame.new(0, 0, -2)
	effect.Parent = Workspace

	SharedUtilities.setAttributes(attackingCharacter, {
		Blocking = false,
		NoAttacking = true,
		Stunned = true,
	})
	setShadowConfig(attackingCharacter, { Stunned = true, NoAttacking = true, Blocking = false })

	task.spawn(function(): ()
		effect.Attacher.Expander:Emit()
		task.wait(0.1)
		effect.Attacher.Shrink:Emit()
		task.wait(1)
		effect:Destroy()
	end)

	task.delay(configuration.TIMEOUT, function(): ()
		SharedUtilities.setAttributes(attackingCharacter, {
			NoAttacking = false,
			Stunned = false,
		})
		setShadowConfig(attackingCharacter, { Stunned = false, NoAttacking = false })
	end)
end

function ParryHandler.ParryEffect(character: Model, enemyCharacter: Model, player: Player?, enemyPlayer: Player?, maxStrength: number): ()
	local isValid, charRoot, enemyRoot = validateCharacters(character, enemyCharacter)
	if not isValid or not charRoot or not enemyRoot then
		return
	end

	local parryVFX = EFFECT_TEMPLATE:Clone()
	parryVFX.CFrame = charRoot.CFrame
	parryVFX.Parent = Workspace
	game.Debris:AddItem(parryVFX, 1.5)

	Remotes.ClashShockwaves:FireAllClients(charRoot.CFrame * CFrame.new(0, 0, -1))

	local clashSound = script.Clash:Clone()
	clashSound.Parent = charRoot
	clashSound:Play()

	task.delay(configuration.SOUND_CLEANUP_DELAY, function()
		if clashSound then clashSound:Destroy() end
	end)

	GlobalShakeHandler.GlobalShakeFrom(charRoot)
	GroundDetectionHandler.NearGroundDetection(character, enemyCharacter)

	if math.random() <= configuration.PARRY_CHANCE then
		ParryHandler.ParryMovement(character, enemyCharacter, player, enemyPlayer, maxStrength)
	end
end

function ParryHandler.ParryMovement(character: Model, enemyCharacter: Model, player: Player?, enemyPlayer: Player?, maxStrength: number?): ()
	local isValid, charRoot, enemyRoot = validateCharacters(character, enemyCharacter)
	if not isValid or not charRoot or not enemyRoot then
		return
	end

	local chosenOption = if math.random(1, 2) == 1 then "Left" else "Right"
	playParryAnimation(enemyCharacter, chosenOption)

	local strength = math.random(configuration.MIN_STRENGTH, configuration.MAX_STRENGTH)
	if maxStrength then
		strength = math.random(5, maxStrength)
	end

	local direction, movementDirection = DIRECTIONAL_VECTORS[chosenOption](charRoot.CFrame, strength)
	local raycastResult = Workspace:Raycast(charRoot.Position, direction, createRaycastParams(character, enemyCharacter))

	if raycastResult then
		return
	end

	pcall(function() character.SetCameraCFrame:Destroy() end)
	pcall(function() enemyCharacter.SetCameraCFrame:Destroy() end)

	Remotes.Shockwaves:FireAllClients(charRoot.CFrame)
	GroundDetectionHandler.NearGroundDetection(character, enemyCharacter)

	local myCharPosition = charRoot.CFrame * movementDirection
	cleanupBodyMovers(charRoot :: BasePart, enemyRoot :: BasePart)
	setNetworkOwnership(player, enemyPlayer, charRoot :: BasePart, enemyRoot :: BasePart)

	local bv = Instance.new("BodyPosition")
	local bv2 = Instance.new("BodyPosition")
	bv.MaxForce = Vector3.zero
	bv2.MaxForce = Vector3.zero
	bv.Position = myCharPosition.Position

	pcall(function()
		character.HumanoidRootPart.FlyingPosition.Position = myCharPosition.Position
	end)

	bv.Parent = charRoot
	charRoot.CFrame = myCharPosition

	local targetCharPosition = charRoot.CFrame + charRoot.CFrame.LookVector * configuration.DISTANCE_OFFSET
	bv2.Position = targetCharPosition.Position
	bv2.Parent = enemyRoot

	task.delay(configuration.CLEANUP_DELAY, function()
		if bv then bv:Destroy() end
		if bv2 then bv2:Destroy() end
	end)

	enemyRoot.CFrame = targetCharPosition
	enemyRoot.CFrame = CFrame.new(
		enemyRoot.Position,
		Vector3.new(charRoot.Position.X, enemyRoot.Position.Y, charRoot.Position.Z)
	)

	ParryHandler.ParryMovementYAxis(character, enemyCharacter, player, enemyPlayer, maxStrength)
end

function ParryHandler.ParryMovementYAxis(character: Model, enemyCharacter: Model, player: Player?, enemyPlayer: Player?, maxStrength: number?, clashStyle: number?): ()
	if math.random() >= configuration.VERTICAL_CHANCE then
		return
	end

	local isValid, charRoot, enemyRoot = validateCharacters(character, enemyCharacter)
	if not isValid or not charRoot or not enemyRoot then
		return
	end

	local options = { "Up", "Down" }
	local chosenOption = options[math.random(1, #options)]
	local maxVertical = configuration.MAX_VERTICAL_STRENGTH

	if maxStrength then
		if maxStrength < maxVertical then maxStrength = maxVertical end
		maxVertical = maxVertical + (maxStrength / 5)
	end

	local strength = math.random(configuration.MIN_VERTICAL_STRENGTH, maxVertical)
	local direction, movementDirection = VERTICAL_VECTORS[chosenOption](charRoot.CFrame, strength)
	local raycastResult = Workspace:Raycast(charRoot.Position, direction, createRaycastParams(character, enemyCharacter))

	if raycastResult then
		return
	end

	GroundDetectionHandler.NearGroundDetection(character, enemyCharacter)

	local myCharPosition = charRoot.CFrame * movementDirection
	cleanupBodyMovers(charRoot :: BasePart, enemyRoot :: BasePart)
	setNetworkOwnership(player, enemyPlayer, charRoot :: BasePart, enemyRoot :: BasePart)

	local bv = Instance.new("BodyPosition")
	local bv2 = Instance.new("BodyPosition")
	bv.MaxForce = Vector3.zero
	bv2.MaxForce = Vector3.zero
	bv.Position = myCharPosition.Position
	bv.Parent = charRoot
	charRoot.CFrame = myCharPosition

	local distanceOffset = if clashStyle ~= nil and clashStyle ~= 1
		then configuration.DISTANCE_OFFSET_FAR
		else configuration.DISTANCE_OFFSET_CLOSE
	local targetCharPosition = charRoot.CFrame + charRoot.CFrame.LookVector * distanceOffset
	bv2.Position = targetCharPosition.Position
	bv2.Parent = enemyRoot

	task.delay(configuration.CLEANUP_DELAY, function()
		if bv then bv:Destroy() end
		if bv2 then bv2:Destroy() end
	end)

	enemyRoot.CFrame = targetCharPosition
	enemyRoot.CFrame = CFrame.new(
		enemyRoot.Position,
		Vector3.new(charRoot.Position.X, enemyRoot.Position.Y, charRoot.Position.Z)
	)

	if player then
		pcall(function() Remotes.FlyOn:InvokeClient(player) end)
	end
	if enemyPlayer then
		pcall(function() Remotes.FlyOn:InvokeClient(enemyPlayer) end)
	end
end

return ParryHandler
