local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local CameraShake = require(ServerStorage.Modules.CameraShake)
local Charge = require(ServerStorage.Modules.Charge)
local CombatTag = require(ServerStorage.Modules.CombatTag)
local Damage = require(ServerStorage.Modules.Damage)
local HitFX = require(ServerStorage.Modules.HitFX)
local HitStun = require(ServerStorage.Modules.HitStun)
local Hitbox = require(ServerStorage.Modules.Hitbox)
local Knockback = require(ServerStorage.Modules.Knockback)
local ParryHandler = require(ServerStorage.Modules.ParryHandler)

local COMBO_FINISHER_FORCE = 150
local MAX_POSITION_DELTA_STUDS = 20
local VANISH_WINDOW_DURATION = 1.5
local RUNNER_HITBOX_SIZE_MULTIPLIER = 2
local HITBOX_SIZE = Vector3.new(3, 7, 5)

local function resolveAttackCFrame(invoker: Model, requestedCFrame: CFrame?): CFrame
	local hrp = invoker:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return requestedCFrame or CFrame.identity
	end

	local serverCFrame = hrp.CFrame
	if not requestedCFrame then
		return serverCFrame
	end

	if (requestedCFrame.Position - serverCFrame.Position).Magnitude > MAX_POSITION_DELTA_STUDS then
		return serverCFrame
	end

	return CFrame.new(requestedCFrame.Position) * serverCFrame.Rotation
end

local function resolveHitboxSize(invoker: Model, isRunning: boolean?): Vector3
	local hitboxSize = HITBOX_SIZE
	local isFlying = invoker:GetAttribute("Flying") :: boolean? or invoker:GetAttribute("BoostFlying") :: boolean?

	if not isFlying and isRunning then
		hitboxSize *= RUNNER_HITBOX_SIZE_MULTIPLIER
	end

	return hitboxSize
end

local function applyPlayerHitEffects(attackerPlayer: Player, entity: Model, _lightDamage: number?)
	CameraShake.shakePlayer(attackerPlayer, 1.5, 0.25)
	CombatTag.applyCombatTag(attackerPlayer, entity)
end

-- invoker is the attacking character Model (player or NPC).
-- requestedCFrame is the attack origin from the caller, if available.
return function(invoker: Model, requestedCFrame: CFrame?, isRunning: boolean?): ()
	local hrp = invoker:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	if
		invoker:GetAttribute("AttackCooldown")
		or invoker:GetAttribute("Blocking")
		or invoker:GetAttribute("HeavyCooldown")
		or invoker:GetAttribute("HitByKnockBack")
		or invoker:GetAttribute("InCustomization")
		or invoker:GetAttribute("InSafeZone")
		or invoker:GetAttribute("KiBlasting")
		or invoker:GetAttribute("NoAttacking")
		or invoker:GetAttribute("Stunned")
		or invoker:GetAttribute("ToggleRagdoll")
	then
		return
	end

	local lastAttackTime = invoker:GetAttribute("LastAttackTime") :: number? or 0
	local currentTime = DateTime.now().UnixTimestampMillis / 1_000

	if currentTime - lastAttackTime < 0.15 then
		return
	end

	local player = Players:GetPlayerFromCharacter(invoker)

	invoker:SetAttribute("LastAttackTime", currentTime)
	Charge.stop(invoker)

	local handlingPerfectBlock = false
	local combo = (invoker:GetAttribute("ComboCounter") :: number? or 0) + 1
	local currentCombo = combo
	local stamina = invoker:GetAttribute("Stamina") :: number? or -1
	local staminaNeeded = invoker:GetAttribute("StaminaNeeded") :: number? or 0

	if stamina < staminaNeeded then
		return
	end

	invoker:SetAttribute("Attacking", true)
	invoker:SetAttribute("AttackCooldown", true)
	invoker:SetAttribute("CanBlock", false)
	invoker:SetAttribute("Swinging", true)
	invoker:SetAttribute("StaminaTime", 1)
	invoker:SetAttribute("ComboCounter", combo)
	invoker:SetAttribute("Stamina", stamina - staminaNeeded)

	task.wait(0.1)

	task.delay(0.25, function(): ()
		invoker:SetAttribute("Swinging", false)
	end)

	task.delay(1.2, function(): ()
		if invoker:GetAttribute("ComboCounter") ~= currentCombo then
			return
		end

		if invoker:GetAttribute("Blocking") then
			invoker:GetAttributeChangedSignal("Blocking"):Wait()
			task.wait(1.2)

			if invoker:GetAttribute("ComboCounter") ~= currentCombo then
				return
			end
		end

		invoker:SetAttribute("ComboCounter", 1)
		invoker:SetAttribute("Attacking", false)
	end)

	if combo >= 5 then
		invoker:SetAttribute("ComboCounter", 1)
		invoker:SetAttribute("Attacking", false)

		task.delay(0.7, function(): ()
			invoker:SetAttribute("AttackCooldown", false)
		end)
	end

	local resolvedCFrame = resolveAttackCFrame(invoker, requestedCFrame)
	local hitboxSize = resolveHitboxSize(invoker, isRunning)

	local hitbox = Hitbox.create(hitboxSize, resolvedCFrame * CFrame.new(0, 0, -hitboxSize.Z / 2), invoker)

	local overlapParams = OverlapParams.new()
	overlapParams.FilterDescendantsInstances = { invoker }
	local parryHitboxDetected = false

	for _, part in Workspace.Ignore.Hitboxes:GetChildren() do
		if part:GetAttribute("IsParryHitbox") then
			local partsInHitbox = Workspace:GetPartsInPart(hitbox, overlapParams)

			for _, overlappingPart in partsInHitbox do
				if overlappingPart == part then
					parryHitboxDetected = true
					break
				end
			end

			if parryHitboxDetected then
				break
			end
		end
	end

	local entities = Hitbox.processHitscan(hitbox, { invoker })

	for _, entity in entities do
		if entity:GetAttribute("Blocking") then
			local isDummy = not entity:FindFirstChild("Player")

			if entity:GetAttribute("PerfectBlocked") and (parryHitboxDetected or isDummy) then
				handlingPerfectBlock = true

				if not isDummy then
					entity:SetAttribute("PerfectBlocked", false)
					entity:SetAttribute("LastPerfectBlockTime", os.clock())
				end

				ParryHandler.parry(invoker, entity)

				task.delay(ParryHandler.Configuration.TIMEOUT, function(): ()
					invoker:SetAttribute("AttackCooldown", false)
				end)

				continue
			end

			local defenderStamina: number = entity:GetAttribute("Stamina") :: number? or 0
			local newDefenderStamina = math.max(0, defenderStamina - 8)

			entity:SetAttribute("Stamina", newDefenderStamina)
			HitFX.spawnBlockFX(entity, entity.HumanoidRootPart.Position)

			local attackerStamina: number = invoker:GetAttribute("Stamina") :: number? or 0
			local attackerMaxStamina: number = invoker:GetAttribute("MaxStamina") :: number? or 100

			invoker:SetAttribute("Stamina", math.min(attackerStamina + 1, attackerMaxStamina))

			if newDefenderStamina <= 0 then
				entity:SetAttribute("BlockBroken", true)
				entity:SetAttribute("Blocking", false)
				entity:SetAttribute("NoAttacking", true)
				entity:SetAttribute("NoBlocking", true)

				task.delay(1.5, function(): ()
					if entity and entity.Parent then
						entity:SetAttribute("BlockBroken", false)
						entity:SetAttribute("NoAttacking", false)
						entity:SetAttribute("NoBlocking", false)
					end
				end)
			end

			continue
		end

		local attackerStamina = invoker:GetAttribute("Stamina") :: number? or 0
		local attackerMaxStamina = invoker:GetAttribute("MaxStamina") :: number? or 100
		local lightDamage = Damage.apply(entity, invoker, 1, "Physical")

		invoker:SetAttribute("Stamina", math.min(attackerStamina + 3, attackerMaxStamina))
		HitFX.spawnOnCharacter(entity, entity.HumanoidRootPart.Position)

		if player then
			applyPlayerHitEffects(player, entity, lightDamage)
		end

		if combo >= 5 then
			entity:PivotTo(CFrame.lookAt(entity:GetPivot().Position, invoker:GetPivot().Position))
			Knockback.apply(entity, (hrp :: BasePart).CFrame.LookVector, COMBO_FINISHER_FORCE)

			entity:SetAttribute("CanVanishTo", true)
			task.delay(VANISH_WINDOW_DURATION, function()
				if entity and entity.Parent and entity:GetAttribute("CanVanishTo") then
					entity:SetAttribute("CanVanishTo", false)
				end
			end)
		else
			entity.HumanoidRootPart.AssemblyLinearVelocity = (hrp :: BasePart).CFrame.LookVector * 20
			HitStun.apply(entity)
		end
	end

	task.wait(0.3)

	hitbox:Destroy()
	invoker:SetAttribute("Attacking", false)

	if combo <= 4 and not handlingPerfectBlock then
		invoker:SetAttribute("AttackCooldown", false)
	end
end
