local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local AIController = require(ServerStorage.Modules.AIController)
local Animations = require(ReplicatedStorage.Modules.Animations)
local CollisionGroups = require(ServerStorage.Modules.CollisionGroups)
local Entities = require(ReplicatedStorage.Modules.Entities)
local Manager = require(ServerStorage.Modules.Manager)
local StatsManager = require(ServerStorage.Modules.StatsManager)

local ShadowSpawner = {}

local SPAWN_DISTANCE = 7
local SHADOW_WALK_SPEED = 16 -- below Animations' run threshold (20)
local SHADOW_LEVEL = "Beginner"
local KNOCKED_HEALTH = 1 -- keep in sync with StateBinders' KNOCKOUT_FLOOR
local CATEGORY_FOLDERS = { "Identity", "Stats", "Currency", "Appearance" }

local activeShadows: { [Player]: Model } = {}
local stoppers: { [Player]: () -> () } = {}

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value do
		copy[key] = deepCopy(child)
	end
	return copy
end

local function sanitize(model: Model): ()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") or descendant:IsA("GuiObject") or descendant:IsA("LayerCollector") then
			descendant:Destroy()
		end
	end

	for _, child in model:GetChildren() do
		if child:IsA("Accessory") then
			child:Destroy()
		end
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		for _, name in CATEGORY_FOLDERS do
			local existing = humanoid:FindFirstChild(name)
			if existing then
				existing:Destroy()
			end
		end
	end
end

local function buildBody(player: Player, character: Model): Model
	local wasArchivable = character.Archivable
	character.Archivable = true
	local shadow = character:Clone()
	character.Archivable = wasArchivable

	shadow.Name = `{player.Name}_Shadow`
	sanitize(shadow)
	return shadow
end

function ShadowSpawner.isActive(player: Player): boolean
	return activeShadows[player] ~= nil
end

function ShadowSpawner.despawn(player: Player): ()
	local stop = stoppers[player]
	if stop then
		stop()
		stoppers[player] = nil
	end

	local existing = activeShadows[player]
	if existing then
		existing:Destroy()
		activeShadows[player] = nil
	end
end

function ShadowSpawner.spawn(player: Player): Model?
	local character = player.Character
	if not character or not character.Parent then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end

	local slot = Manager.getActiveSlot(player)
	if not slot then
		warn(`[ShadowSpawner] No active slot for {player.Name} -- cannot spawn shadow`)
		return nil
	end

	ShadowSpawner.despawn(player)

	local shadow = buildBody(player, character)

	StatsManager.bindNPC(shadow, deepCopy(slot))
	shadow:SetAttribute("IsShadow", true)

	-- Shadow is server-owned so it gets full knockback impulse and topples; disable physics states to keep it standing.
	local shadowHumanoid = shadow:FindFirstChildOfClass("Humanoid")
	if shadowHumanoid then
		shadowHumanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		shadowHumanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		shadowHumanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
		shadowHumanoid.WalkSpeed = SHADOW_WALK_SPEED
	end

	-- Clone inherits the owner's "Player" group; move it to "Shadow" so players pass through the body
	-- they can't see (ShadowVisibilityController hides it for everyone but the owner).
	CollisionGroups.assign(shadow, CollisionGroups.Shadow)

	local spawnPosition = (root.CFrame * CFrame.new(0, 0, -SPAWN_DISTANCE)).Position
	shadow:PivotTo(CFrame.lookAt(spawnPosition, root.Position))
	-- Tags NPC + Shadow (stripping the Player tag the clone inherited) and parents into Workspace.Shadows.
	Entities.register(shadow, "Shadow")

	activeShadows[player] = shadow

	local stopAI = AIController.start(shadow, { owner = character, level = SHADOW_LEVEL })
	local stopLocomotion = Animations.bindLocomotion(shadow)
	local stopKnockbackAnim = Animations.bindKnockbackAnimation(shadow)
	local stopHitAnim = Animations.bindHitReactionAnimation(shadow)
	local stopBlockAnim = Animations.bindBlockAnimation(shadow)
	local stopChargeAnim = Animations.bindChargeAnimation(shadow)
	local stopRestAnim = Animations.bindRestAnimation(shadow)

	local ownerHumanoid = character:FindFirstChildOfClass("Humanoid")
	local function despawnIfKnocked(health: number)
		if health <= KNOCKED_HEALTH then
			ShadowSpawner.despawn(player)
		end
	end
	local shadowHealthConn = if shadowHumanoid then shadowHumanoid.HealthChanged:Connect(despawnIfKnocked) else nil
	local ownerHealthConn = if ownerHumanoid then ownerHumanoid.HealthChanged:Connect(despawnIfKnocked) else nil

	stoppers[player] = function()
		stopAI()
		stopLocomotion()
		stopKnockbackAnim()
		stopHitAnim()
		stopBlockAnim()
		stopChargeAnim()
		stopRestAnim()
		if shadowHealthConn then
			shadowHealthConn:Disconnect()
		end
		if ownerHealthConn then
			ownerHealthConn:Disconnect()
		end
	end

	return shadow
end

Players.PlayerRemoving:Connect(ShadowSpawner.despawn)

return ShadowSpawner
