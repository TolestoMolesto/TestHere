--!strict
-- TODO: Make this work for entities as well
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Character = require(ReplicatedStorage.Modules.Character)
local Colour = require(ServerStorage.Modules.Colour)
local Manager = require(ServerStorage.PlayerData.Manager)
local Raycast = require(ReplicatedStorage.Modules.Raycast)
local SharedTypes = require(ReplicatedStorage.Modules.Types)
local SharedUtilities = require(ReplicatedStorage.Modules.Utilities)
local SparkingMode = require(ServerStorage.Modules.SparkingMode)
local Types = require(ServerStorage.Modules.Types)

local SPARKING_MODE_DRAIN_RATE = 0.02
local EFFECTS = script.Effects
local FLOOR_EFFECTS = script.FloorEffects
local SPARKING_MODE_EFFECTS = script.SparkingModeEffects
local SPARKING_MODE_FLOOR_EFFECTS = script.SparkingModeFloorEffects
local Charge = {}

local effectObjectCache =
	setmetatable({} :: { [Model]: { Instance & (Colour.Effect | Colour.PhysicalEffectObject) } }, { __mode = "k" })

local function cacheEffectObject(
	entityCharacter: Types.EntityCharacter,
	effect: Colour.Effect | Colour.PhysicalEffectObject
): ()
	if not effectObjectCache[entityCharacter] then
		effectObjectCache[entityCharacter] = { effect }

		return
	end

	table.insert(effectObjectCache[entityCharacter], effect)
end

local function clearCacheEntry(entityCharacter: Model): ()
	effectObjectCache[entityCharacter] = {}
end

local function weldTo(entityCharacter: Types.EntityCharacter, object: BasePart): WeldConstraint
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = object
	weld.Part1 = entityCharacter.PrimaryPart :: BasePart
	weld.Parent = entityCharacter

	return weld
end

local function directlyAboveFloor(playerCharacter: Character.Type): boolean
	return if Raycast.execute(playerCharacter.HumanoidRootPart.Position, Vector3.new(0, -10, 0), {
			FilterDescendantsInstances = {
				Workspace.Dummies,
				Workspace.Hitboxes,
				Workspace.NPCs,
				Workspace.Players,
				Workspace.QuestNPCs,
				Workspace.Regions,
				Workspace.Shadows,
			},
		})
		then true
		else false
end

local function generateAura(playerCharacter: Character.Type, playerKiColour: Color3): ()
	for _, effect in EFFECTS:GetChildren() :: { Instance & (Colour.Effect | Colour.PhysicalEffectObject) } do
		local newEffect = effect:Clone()

		Colour.sprayPaintEffect(newEffect, playerKiColour)

		newEffect.Parent = playerCharacter.HumanoidRootPart

		cacheEffectObject(playerCharacter.Instance :: Types.EntityCharacter, newEffect)
	end

	if directlyAboveFloor(playerCharacter) then
		local floorEffect = FLOOR_EFFECTS:Clone()
		floorEffect.CFrame = playerCharacter.HumanoidRootPart.CFrame

		for _, effect in floorEffect:GetChildren() :: { Colour.Effect | Colour.PhysicalEffectObject } do
			Colour.sprayPaintEffect(effect, playerKiColour)
		end

		floorEffect.Parent = playerCharacter.HumanoidRootPart
		local weld = weldTo(playerCharacter.Instance :: Types.EntityCharacter, floorEffect)

		cacheEffectObject(playerCharacter.Instance :: Types.EntityCharacter, floorEffect)
		cacheEffectObject(playerCharacter.Instance :: Types.EntityCharacter, weld)
	end
end

local function removeAura(character: Model): ()
	local cachedObjectsFound = effectObjectCache[character] or {}

	for _, object in cachedObjectsFound :: { Instance } do
		object:Destroy()
	end

	clearCacheEntry(character)
end

local function generateSparkingModeAura(playerCharacter: Character.Type, playerKiColour: Color3): ()
	for _, effect in SPARKING_MODE_EFFECTS:GetChildren() :: { Instance & (ParticleEmitter | Attachment) } do
		local newEffect = effect:Clone()

		Colour.sprayPaintEffect(newEffect, playerKiColour)

		newEffect.Parent = playerCharacter.HumanoidRootPart

		cacheEffectObject(playerCharacter.Instance :: Types.EntityCharacter, newEffect)
	end

	if directlyAboveFloor(playerCharacter) then
		local floorEffect = SPARKING_MODE_FLOOR_EFFECTS:Clone()
		floorEffect.CFrame = playerCharacter.HumanoidRootPart.CFrame

		for _, effect in floorEffect:GetChildren() :: { Colour.Effect | Colour.PhysicalEffectObject } do
			Colour.sprayPaintEffect(effect, playerKiColour)
		end

		floorEffect.Parent = playerCharacter.HumanoidRootPart
		local weld = weldTo(playerCharacter.Instance :: Types.EntityCharacter, floorEffect)

		cacheEffectObject(playerCharacter.Instance :: Types.EntityCharacter, floorEffect)
		cacheEffectObject(playerCharacter.Instance :: Types.EntityCharacter, weld)
	end
end

function Charge.start(playerCharacter: Character.Type): ()
	if
		playerCharacter.Instance:GetAttribute("Charging")
		or playerCharacter.Instance:GetAttribute("InSparkingMode")
		or playerCharacter.Instance:GetAttribute("ToggleRagdoll")
		or playerCharacter.Instance:GetAttribute("Resting")
		or playerCharacter.Instance:GetAttribute("Attacking")
		or playerCharacter.Instance:GetAttribute("AttackCooldown")
		or playerCharacter.Instance:GetAttribute("HeavyCooldown")
		or playerCharacter.Instance:GetAttribute("InCustomization")
	then
		return
	end

	local playerAnimations = playerCharacter.getAnimations()
	local playerProfile = Manager.getProfile(playerCharacter.Player)
	local playerKiColour =
		SharedUtilities.colourTableToColour3(playerProfile.Data.Appearance.KiColor :: SharedTypes.ColourTable)
	local wasInSparkingMode = false
	playerCharacter.HumanoidRootPart.Anchored = true
	local chargingSparkingMode = false

	generateAura(playerCharacter, playerKiColour)
	playerAnimations.Charge:Play()
	playerCharacter.Instance:SetAttribute("KiColor", playerKiColour)
	playerCharacter.Instance:SetAttribute("Charging", true)
	playerCharacter.Instance:SetAttribute("CanBlock", false)

	while playerCharacter.Instance:GetAttribute("Charging") do
		if playerCharacter.Instance:GetAttribute("InSparkingMode") then
			playerCharacter.Instance:SetAttribute("Charging", false)

			break
		end

		local currentKi = playerCharacter.Instance:GetAttribute("Ki") :: number
		local currentMaxKi = playerCharacter.Instance:GetAttribute("MaxKi") :: number

		if currentKi < currentMaxKi then
			local newKi = math.clamp(currentKi + (currentMaxKi / 15), 0, currentMaxKi)

			playerCharacter.Instance:SetAttribute("Ki", newKi)
			task.wait(1 / 15)
		elseif playerProfile.Data.SkillTreeData.UnlockedTechniques["SparkingMode"] then
			if not chargingSparkingMode then
				removeAura(playerCharacter.Instance :: Model)
				generateSparkingModeAura(playerCharacter, playerKiColour)

				chargingSparkingMode = true
			end

			local currentSparkingCharge = playerCharacter.Instance:GetAttribute("SparkingCharge") :: number? or 0
			local maxSparkingCharge = playerCharacter.Instance:GetAttribute("MaxSparkingCharge") :: number? or 100

			if currentSparkingCharge < maxSparkingCharge then
				local newCharge = math.min(currentSparkingCharge + (maxSparkingCharge * 0.04), maxSparkingCharge)

				playerCharacter.Instance:SetAttribute("SparkingCharge", newCharge)

				if newCharge >= maxSparkingCharge then
					local hasUnlocked = SparkingMode.hasUnlockedSparkingMode(playerCharacter.Player)
					local meetsBP, currentBP = SparkingMode.meetsBPRequirement(playerCharacter.Player, playerCharacter.Instance)

					if not hasUnlocked then
						playerCharacter.Instance:SetAttribute("Charging", false)
						break
					end

					if not meetsBP then
						playerCharacter.Instance:SetAttribute("Charging", false)
						break
					end

					wasInSparkingMode = true
					playerCharacter.HumanoidRootPart.Anchored = false

					removeAura(playerCharacter.Instance :: Model)
					playerAnimations.Charge:Stop()
					playerCharacter.Instance:SetAttribute("InSparkingMode", true)
					playerCharacter.Instance:SetAttribute("Charging", false)

					break
				end
			end
		end

		task.wait(0.2)
	end

	if wasInSparkingMode then
		playerAnimations.Charge:Stop()
	end

	if not wasInSparkingMode and not playerCharacter.Instance:GetAttribute("InSparkingMode") then
		local currentSparkingCharge = playerCharacter.Instance:GetAttribute("SparkingCharge") :: number? or 0
		local maxSparkingCharge = playerCharacter.Instance:GetAttribute("MaxSparkingCharge") :: number? or 100

		while currentSparkingCharge > 0 and playerCharacter.Instance.Parent do
			if playerCharacter.Instance:GetAttribute("Charging") then
				break
			end

			if playerCharacter.Instance:GetAttribute("InSparkingMode") then
				break
			end

			currentSparkingCharge = math.max(currentSparkingCharge - (maxSparkingCharge * SPARKING_MODE_DRAIN_RATE), 0)

			playerCharacter.Instance:SetAttribute("SparkingCharge", currentSparkingCharge)

			task.wait(0.2)
		end
	end
end

-- Accepts a raw character Model — called from attack handlers that don't hold
-- a Character wrapper (e.g. LightAttack, HeavyAttack).
function Charge.stop(character: Model): ()
	if not character:GetAttribute("Charging") then
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		hrp.Anchored = false
	end

	removeAura(character)
	character:SetAttribute("Charging", false)
	character:SetAttribute("CanBlock", true)

	-- Stop the Charge animation track directly via the Animator
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in animator:GetPlayingAnimationTracks() do
				if track.Name == "Charge" then
					track:Stop()
					break
				end
			end
		end
	end

	task.wait(0.2)
end

return Charge
