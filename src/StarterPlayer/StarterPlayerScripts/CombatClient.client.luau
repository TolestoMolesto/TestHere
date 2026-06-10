local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ActionConfig = require(ReplicatedStorage.Modules.ActionConfig)
local Animations = require(ReplicatedStorage.Modules.Animations)
local Keybinds = require(ReplicatedStorage.Modules.Keybinds)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local player = Players.LocalPlayer

local COMBO_TIMEOUT = 1.2
local MIN_SWING_INTERVAL = 0.12
local HEAVY_MIN_INTERVAL = 0.8
local KI_BLAST_MIN_INTERVAL = 0.5
local KI_COST_FRACTION = 0.05 -- 5% of MaxKi per blast, mirrors server gate
local VANISH_COST_FRACTION = 0.1 -- 10% of MaxStamina per vanish, mirrors server gate

-- Live bind -> action. Built from Keybinds (which defaults to ActionConfig's bindings) and rebuilt on
-- any rebind, so changing a combat key takes effect without a rejoin. Trigger/clientManaged still come
-- from ActionConfig -- only the key itself is now player-controlled.
local pressActions: { [any]: string } = {}
local releaseActions: { [any]: string } = {}
local function rebuildBinds()
	table.clear(pressActions)
	table.clear(releaseActions)
	for actionId, def in ActionConfig do
		if def.clientManaged then
			continue
		end
		local bind = Keybinds.get(actionId)
		if bind == nil then
			continue
		end
		if def.trigger == "Release" then
			releaseActions[bind] = actionId
		elseif def.trigger == "Hold" then
			pressActions[bind] = actionId
			releaseActions[bind] = actionId
		else
			pressActions[bind] = actionId
		end
	end
end
rebuildBinds()
Keybinds.onChanged(rebuildBinds)

local comboIndex = 1
local lastSwingClock = 0

local function presentLightAttack(): boolean
	local character = player.Character
	if not character then
		return false
	end
	if
		character:GetAttribute("Stunned")
		or character:GetAttribute("Blocking")
		or character:GetAttribute("HitByKnockBack")
		or character:GetAttribute("AttackCooldown")
		or character:GetAttribute("NoAttacking")
	then
		return false
	end

	local now = os.clock()
	local sinceLast = now - lastSwingClock
	if sinceLast < MIN_SWING_INTERVAL then
		return false
	end
	if sinceLast > COMBO_TIMEOUT then
		comboIndex = 1
	end

	Animations.playLightAttack(character, comboIndex, Animations.attackSpeed(character))

	comboIndex = (comboIndex % Animations.LIGHT_ATTACK_COUNT) + 1
	lastSwingClock = now
	return true
end

local lastHeavyClock = 0
local function presentHeavyAttack(): boolean
	local character = player.Character
	if not character then
		return false
	end
	-- Heavy is lock-on only: right-click without lock-on goes to camera, never throws. Server enforces this too.
	if not character:GetAttribute("LockedOn") then
		return false
	end
	if
		character:GetAttribute("Stunned")
		or character:GetAttribute("Blocking")
		or character:GetAttribute("HitByKnockBack")
		or character:GetAttribute("HeavyCooldown")
		or character:GetAttribute("NoAttacking")
	then
		return false
	end

	local now = os.clock()
	if now - lastHeavyClock < HEAVY_MIN_INTERVAL then
		return false
	end
	lastHeavyClock = now

	Animations.play(character, "heavyattack", 0.1, nil, Animations.attackSpeed(character))
	return true
end

local function presentRecover(): boolean
	local character = player.Character
	if not character then
		return false
	end
	return character:GetAttribute("HitByKnockBack") == true and character:GetAttribute("CanRecover") == true
end

local function presentBlock(phase: string?): boolean
	if phase == "stop" then
		return true
	end
	local character = player.Character
	if not character then
		return false
	end
	if
		character:GetAttribute("Stunned")
		or character:GetAttribute("HitByKnockBack")
		or character:GetAttribute("Attacking")
		or character:GetAttribute("NoBlocking")
		or character:GetAttribute("BlockBroken")
		or not character:GetAttribute("CanBlock")
		or ((character:GetAttribute("Stamina") :: number?) or 0) <= 0
	then
		return false
	end
	return true
end

local function presentCharge(phase: string?): boolean
	if phase == "stop" then
		return true
	end
	local character = player.Character
	if not character then
		return false
	end
	if
		character:GetAttribute("Charging")
		or character:GetAttribute("Stunned")
		or character:GetAttribute("HitByKnockBack")
		or character:GetAttribute("Attacking")
		or character:GetAttribute("Blocking")
		or character:GetAttribute("BlockBroken")
		or character:GetAttribute("ToggleRagdoll")
		or character:GetAttribute("InCustomization")
	then
		return false
	end
	return true
end

local function presentRest(): boolean
	local character = player.Character
	if not character then
		return false
	end
	if character:GetAttribute("Resting") then
		return true
	end
	if
		character:GetAttribute("CombatTag")
		or character:GetAttribute("ToggleRagdoll")
		or character:GetAttribute("Charging")
		or character:GetAttribute("Blocking")
	then
		return false
	end
	return true
end

local lastKiBlastClock = 0
local kiBlastHand = "Right"
local function presentKiBlast(): boolean
	local character = player.Character
	if not character then
		return false
	end
	if
		character:GetAttribute("Stunned")
		or character:GetAttribute("Blocking")
		or character:GetAttribute("Charging")
		or character:GetAttribute("HitByKnockBack")
		or character:GetAttribute("KiBlasting")
	then
		return false
	end
	local maxKi = (character:GetAttribute("MaxKi") :: number?) or 0
	local currentKi = (character:GetAttribute("Ki") :: number?) or 0
	if currentKi < maxKi * KI_COST_FRACTION then
		return false
	end
	local now = os.clock()
	if now - lastKiBlastClock < KI_BLAST_MIN_INTERVAL then
		return false
	end
	lastKiBlastClock = now

	kiBlastHand = if kiBlastHand == "Right" then "Left" else "Right"
	Animations.play(character, if kiBlastHand == "Right" then "kiblastright" else "kiblastleft", 0.1)
	return true
end

local function presentVanish(): boolean
	local character = player.Character
	if not character then
		return false
	end
	if character:GetAttribute("Stunned") or character:GetAttribute("ToggleRagdoll") then
		return false
	end
	if character:GetAttribute("LockedOn") ~= true then
		return false
	end
	-- Stay permissive: if target can't be resolved cleanly, still send (server is authoritative).
	local targetValue = character:FindFirstChild("LockOnTarget")
	local target: Instance? = if targetValue and targetValue:IsA("ObjectValue") then targetValue.Value else nil
	if target and target:IsA("Model") and target:GetAttribute("CanVanishTo") ~= true then
		return false
	end
	local maxStamina = (character:GetAttribute("MaxStamina") :: number?) or 0
	local stamina = (character:GetAttribute("Stamina") :: number?) or 0
	if stamina < maxStamina * VANISH_COST_FRACTION then
		return false
	end
	return true
end

local presentation: { [string]: (phase: string?) -> boolean } = {
	LightAttack = presentLightAttack,
	HeavyAttack = presentHeavyAttack,
	Recover = presentRecover,
	Block = presentBlock,
	Charge = presentCharge,
	Rest = presentRest,
	KiBlast = presentKiBlast,
	Vanish = presentVanish,
}

local function bindCombo(character: Model)
	comboIndex = 1
	character:GetAttributeChangedSignal("AttackSequence"):Connect(function()
		if (character:GetAttribute("AttackSequence") or 0) == 0 then
			comboIndex = 1
		end
	end)
end

local function onCharacter(character: Model)
	bindCombo(character)
	Animations.bindBlockAnimation(character)
	Animations.bindChargeAnimation(character)
	Animations.bindRestAnimation(character)

	-- Kill the stock FallingDown state: knockback, bumping geometry, and steep ground would otherwise flop
	-- players into an uncontrollable tumble that fights combat feel. Only the server-side Ragdoll module
	-- (PlatformStand + constraints, a separate path) should down a player. This MUST run client-side:
	-- SetStateEnabled does not replicate and the local player network-owns their character, so a server
	-- call would be a no-op here.
	local humanoid = character:WaitForChild("Humanoid", 5)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	end
end
if player.Character then
	onCharacter(player.Character)
end
player.CharacterAdded:Connect(onCharacter)

local function buildParams(actionId: string, phase: string)
	local params = { phase = phase }
	if actionId == "LightAttack" or actionId == "HeavyAttack" then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			params.cframe = root.CFrame
		end
	end
	return params
end

local function trigger(actionId: string, phase: string)
	local present = presentation[actionId]
	if present and present(phase) == false then
		return
	end
	Remotes.PerformAction:FireServer(actionId, buildParams(actionId, phase))
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	local key = Keybinds.fromInput(input)
	local actionId = key and pressActions[key]
	if actionId then
		trigger(actionId, "start")
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	local key = Keybinds.fromInput(input)
	local actionId = key and releaseActions[key]
	if actionId then
		trigger(actionId, "stop")
	end
end)
