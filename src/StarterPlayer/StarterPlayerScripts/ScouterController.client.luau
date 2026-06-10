--!strict
-- Scouter controller: hold E (while a scouter is equipped) to scan nearby entities and read
-- their BattlePower. Pairs with ReplicatedStorage.Modules.Scouter the same way
-- LockOnController pairs with LockOn -- this script owns the lifecycle, threads and input.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Animations = require(ReplicatedStorage.Modules.Animations)
local Audio = require(ReplicatedStorage.Modules.Audio)
local Keybinds = require(ReplicatedStorage.Modules.Keybinds)
local Scouter = require(ReplicatedStorage.Modules.Scouter)

local player = Players.LocalPlayer :: Player

local character = (player.Character or player.CharacterAdded:Wait()) :: Model
local humanoidRootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
local humanoid = character:WaitForChild("Humanoid") :: Humanoid

-- Coded SFX (no Studio step), routed through the SFX SoundGroup so the player's SFX slider scales
-- them. "searching" hums while reading; "found" pings as each target is read. Ids live in Audio.SFX.
local searchingSound = Audio.create(Audio.SFX.Searching)
searchingSound.Parent = script
local foundSound = Audio.create(Audio.SFX.Found)
foundSound.Parent = script

-- Templates live in ReplicatedStorage.Assets.ScouterGUI (Location + PLIndicator). nil-safe:
-- if the art isn't synced yet the scouter just shows nothing rather than erroring.
local function getTemplate(name: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local gui = assets and assets:FindFirstChild("ScouterGUI")
	return (gui and gui:FindFirstChild(name)) or nil
end

type Tracker = { active: boolean }

local isScouterActive = false
local currentScanID = 0
local activeTrackers: { Tracker } = {}
local lastSoundPlayedTime: { [Model]: number } = {}

local function createIndicator(targetRoot: BasePart, indicatorType: string): Instance?
	local template = getTemplate(indicatorType)
	if not template then
		return nil
	end
	local indicator = template:Clone()
	indicator.Parent = targetRoot
	if indicator:IsA("BillboardGui") then
		indicator.Adornee = targetRoot
		indicator.Enabled = true
	end
	return indicator
end

local function removeAllIndicators()
	for _, target in Scouter.getTargets(character) do
		local root = target:FindFirstChild("HumanoidRootPart")
		if root then
			for _, name in { "Location", "PLIndicator" } do
				local existing = root:FindFirstChild(name)
				if existing then
					existing:Destroy()
				end
			end
		end
	end
end

local function playSoundIfReady(target: Model)
	local now = os.clock()
	if now - (lastSoundPlayedTime[target] or 0) > Scouter.SOUND_COOLDOWN then
		foundSound:Play()
		lastSoundPlayedTime[target] = now
	end
end

local function cancelAllTrackers()
	for _, tracker in activeTrackers do
		tracker.active = false
	end
	activeTrackers = {}
end

-- One target's lifetime: spawn an icon, then keep it correct (Location <-> PL by range,
-- blink, colour) until the scan ends, the target leaves, or we die.
local function trackTarget(target: Model, scanID: number, range: number, max: number)
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	if not (targetRoot and targetRoot:IsA("BasePart")) then
		return
	end

	local tracker: Tracker = { active = true }
	table.insert(activeTrackers, tracker)

	playSoundIfReady(target)

	local currentIndicator = createIndicator(targetRoot, "Location")
	local lastIndicatorType = "Location"
	if currentIndicator then
		Scouter.colorizeIndicator(currentIndicator, Scouter.getIndicatorColor(target, true, character))
	end

	local lastBlink = os.clock()
	while tracker.active and isScouterActive and scanID == currentScanID and humanoid.Health > 0 do
		if not target.Parent or not targetRoot.Parent then
			break
		end

		local dist = (targetRoot.Position - humanoidRootPart.Position).Magnitude
		local inRange = dist < range
		local desired = if inRange then "PLIndicator" else "Location"

		if desired ~= lastIndicatorType then
			if currentIndicator then
				currentIndicator:Destroy()
			end
			currentIndicator = createIndicator(targetRoot, desired)
			lastIndicatorType = desired
			local color = Scouter.getIndicatorColor(target, desired == "Location", character)
			if currentIndicator then
				Scouter.colorizeIndicator(currentIndicator, color)
				if inRange then
					Scouter.updatePowerLevelDisplay(currentIndicator, target, color, max, character)
				end
			end
		end

		if os.clock() - lastBlink >= Scouter.BLINK_SPEED then
			if currentIndicator then
				Scouter.blinkIndicator(currentIndicator)
			end
			lastBlink = os.clock()
		end

		task.wait(Scouter.UPDATE_INTERVAL)
	end

	if currentIndicator then
		currentIndicator:Destroy()
	end
	tracker.active = false
end

local function updateScouterSettings(scanID: number)
	cancelAllTrackers()
	removeAllIndicators()

	local tier = Scouter.getTier(Scouter.getEquipped(character))
	if not tier then
		return -- not equipped (scouterOn already gates on this)
	end

	for _, target in Scouter.getTargets(character) do
		if not isScouterActive then
			break
		end
		local root = target:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and Scouter.getBattlePower(target) ~= nil then
			task.spawn(trackTarget, target, scanID, tier.Range, tier.Max)
			task.wait(Scouter.SPAWN_STAGGER)
		end
	end
end

local function scouterOn()
	if isScouterActive then
		return
	end
	if Scouter.getTier(Scouter.getEquipped(character)) == nil then
		return -- no scouter equipped
	end

	isScouterActive = true
	currentScanID += 1
	local thisScan = currentScanID

	searchingSound:Play()
	Animations.play(character, "scouterread")

	task.delay(Scouter.SCAN_DELAY, function()
		if isScouterActive and thisScan == currentScanID then
			updateScouterSettings(thisScan)
		end
	end)
end

local function scouterOff()
	if not isScouterActive then
		return
	end
	isScouterActive = false

	searchingSound:Stop()
	Animations.stop(character, "scouterread")

	cancelAllTrackers()
	removeAllIndicators()
	lastSoundPlayedTime = {}
end

local function onCharacterAdded(newCharacter: Model)
	scouterOff()
	character = newCharacter
	humanoidRootPart = newCharacter:WaitForChild("HumanoidRootPart") :: BasePart
	humanoid = newCharacter:WaitForChild("Humanoid") :: Humanoid
	lastSoundPlayedTime = {}
end

player.CharacterAdded:Connect(onCharacterAdded)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if Keybinds.matches(input, "Scouter") then
		scouterOn()
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if Keybinds.matches(input, "Scouter") then
		scouterOff()
	end
end)
