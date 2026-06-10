--!strict
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Audio = require(ReplicatedStorage.Modules.Audio)
local Knockback = require(ServerStorage.Modules.Knockback)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local TargetLock = require(ServerStorage.Modules.TargetLock)
local Train = require(ServerStorage.Modules.Train)

local VANISH_COST_FRACTION = 0.1
local MAX_VANISH_DISTANCE = 300
local BEHIND_DISTANCE = 3
local SUCCESS_COOLDOWN = 0.5
local FAILED_COOLDOWN = 1
local REPOSITION_SETTLE = 0.05

local debounce = setmetatable({} :: { [Model]: boolean }, { __mode = "k" })

local function resolveVanishFX(): Instance?
	return ServerStorage.Assets.VFX:FindFirstChild("Tele")
end

local function spawnVanishFX(cframe: CFrame, lifetime: number): ()
	local template = resolveVanishFX()
	if not template then
		return
	end
	local effect = template:Clone()
	effect.Parent = Workspace:FindFirstChild("Ignore") or Workspace
	if effect:IsA("PVInstance") then
		effect:PivotTo(cframe)
	end
	local sound = effect:FindFirstChildWhichIsA("Sound", true) :: Sound?
	if sound then
		Audio.tag(sound)
		sound:Play()
	end
	Debris:AddItem(effect, lifetime)
end

local function startDebounce(character: Model, seconds: number): ()
	debounce[character] = true
	task.delay(seconds, function()
		debounce[character] = nil
	end)
end

return function(character: Model): ()
	if debounce[character] or character:GetAttribute("ToggleRagdoll") or character:GetAttribute("Stunned") then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local stamina = (character:GetAttribute("Stamina") :: number?) or 0
	local maxStamina = (character:GetAttribute("MaxStamina") :: number?) or 0
	if maxStamina <= 0 or stamina < maxStamina * VANISH_COST_FRACTION then
		return
	end

	local target = TargetLock.get(character)
	if not target then
		startDebounce(character, FAILED_COOLDOWN)
		return
	end
	local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not targetRoot then
		startDebounce(character, FAILED_COOLDOWN)
		return
	end

	if (root.Position - targetRoot.Position).Magnitude > MAX_VANISH_DISTANCE then
		startDebounce(character, FAILED_COOLDOWN)
		return
	end

	if not target:GetAttribute("CanVanishTo") then
		startDebounce(character, FAILED_COOLDOWN)
		return
	end

	-- Claim the window now so a second attacker on the same victim can't also cash in.
	target:SetAttribute("CanVanishTo", false)

	character:SetAttribute("Stamina", stamina - maxStamina * VANISH_COST_FRACTION)
	startDebounce(character, SUCCESS_COOLDOWN)
	Train.vanished(character, target)

	local player = Players:GetPlayerFromCharacter(character)

	-- Rebound as non-optional upvalues: Luau drops the nil-refinement inside the closure.
	local hrp = root
	local victim = target

	local ok, err = pcall(function()
		spawnVanishFX(hrp.CFrame, 0.5)

		Knockback.cancel(victim)

		local pivot = victim:GetPivot()
		local behind = pivot * CFrame.new(0, 0, BEHIND_DISTANCE)
		hrp.Anchored = true
		hrp.CFrame = CFrame.lookAt(behind.Position, pivot.Position)
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero

		if player then
			Remotes.UpdateFlightPosition:FireClient(player, hrp.Position)
		end

		spawnVanishFX(hrp.CFrame, 0.85)

		task.wait(REPOSITION_SETTLE)
		hrp.Anchored = false
	end)

	if not ok then
		warn(`[Vanish] {character.Name} teleport errored, force-unanchoring: {err}`)
		pcall(function()
			hrp.Anchored = false
		end)
	end
end
