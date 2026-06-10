local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CameraShake = require(ServerStorage.Modules.CameraShake)
local Animations = require(ReplicatedStorage.Modules.Animations)
local Charge = require(ServerStorage.Modules.Charge)
local CombatTag = require(ServerStorage.Modules.CombatTag)
local Damage = require(ServerStorage.Modules.Damage)
local FormState = require(ServerStorage.Modules.FormState)
local HitFX = require(ServerStorage.Modules.HitFX)
local HitStun = require(ServerStorage.Modules.HitStun)
local Hitbox = require(ServerStorage.Modules.Hitbox)
local Knockback = require(ServerStorage.Modules.Knockback)
local ParryHandler = require(ServerStorage.Modules.ParryHandler)
local Train = require(ServerStorage.Modules.Train)

local LIGHT_BASE_DAMAGE = 5
local COMBO_FINISHER_FORCE = 150
local MAX_POSITION_DELTA_STUDS = 20
local VANISH_WINDOW_DURATION = 1.5
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

return function(invoker: Model, requestedCFrame: CFrame?): ()
	local hrp = invoker:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	-- State gating (cooldowns, Stunned, Resting, KiBlasting, etc.) is enforced centrally in
	-- ActionController.perform via ActionConfig.LightAttack.blockedBy; reaching here means it passed.
	local lastAttackTime = invoker:GetAttribute("LastAttackTime") :: number? or 0
	local currentTime = DateTime.now().UnixTimestampMillis / 1_000

	if currentTime - lastAttackTime < 0.15 then
		return
	end

	local player = Players:GetPlayerFromCharacter(invoker)

	invoker:SetAttribute("LastAttackTime", currentTime)
	Charge.stop(invoker)

	local handlingPerfectBlock = false
	local combo = (invoker:GetAttribute("AttackSequence") :: number? or 0) + 1
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
	invoker:SetAttribute("AttackSequence", combo)
	invoker:SetAttribute("Stamina", stamina - staminaNeeded)

	if not player then
		Animations.playLightAttack(invoker, combo, Animations.attackSpeed(invoker))
	end

	task.wait(0.1)

	task.delay(0.25, function(): ()
		invoker:SetAttribute("Swinging", false)
		-- CanBlock is cleared above so you can't guard mid-swing; nothing else resets it, so this is required.
		invoker:SetAttribute("CanBlock", true)
	end)

	task.delay(1.2, function(): ()
		if invoker:GetAttribute("AttackSequence") ~= currentCombo then
			return
		end

		if invoker:GetAttribute("Blocking") then
			invoker:GetAttributeChangedSignal("Blocking"):Wait()
			task.wait(1.2)

			if invoker:GetAttribute("AttackSequence") ~= currentCombo then
				return
			end
		end

		invoker:SetAttribute("AttackSequence", 0)
		invoker:SetAttribute("Attacking", false)
	end)

	if combo >= 4 then
		invoker:SetAttribute("AttackSequence", 0)
		invoker:SetAttribute("Attacking", false)

		task.delay(0.7, function(): ()
			invoker:SetAttribute("AttackCooldown", false)
		end)
	end

	local resolvedCFrame = resolveAttackCFrame(invoker, requestedCFrame)
	local hitboxSize = HITBOX_SIZE

	local entities = Hitbox.scanBox(resolvedCFrame * CFrame.new(0, 0, -hitboxSize.Z / 2), hitboxSize, { invoker })

	for _, entity in entities do
		local blockingFrontally = entity:GetAttribute("Blocking")
			and Hitbox.isInFront(entity, (hrp :: BasePart).Position)

		if blockingFrontally then
			if entity:GetAttribute("PerfectBlocked") then
				handlingPerfectBlock = true
				entity:SetAttribute("PerfectBlocked", false)

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
			Train.blocked(entity, invoker)

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

		-- A return of 0 means the target dodged: the swing whiffs. Stamina was paid up-front,
		-- but none of the on-hit reactions below land.
		if Damage.apply(entity, invoker, LIGHT_BASE_DAMAGE, "Physical") == 0 then
			Train.dodged(entity, invoker)
			continue
		end

		FormState.awardCombatHit(invoker)
		Train.landedLight(invoker, entity)

		local attackerStamina = invoker:GetAttribute("Stamina") :: number? or 0
		local attackerMaxStamina = invoker:GetAttribute("MaxStamina") :: number? or 100
		invoker:SetAttribute("Stamina", math.min(attackerStamina + 3, attackerMaxStamina))
		HitFX.spawnOnCharacter(entity, entity.HumanoidRootPart.Position)

		CombatTag.applyCombatTag(invoker, entity)

		if player then
			CameraShake.shakePlayer(player, 1.5, 0.25)
		end

		if combo >= 4 then
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

	invoker:SetAttribute("Attacking", false)

	if combo <= 3 and not handlingPerfectBlock then
		invoker:SetAttribute("AttackCooldown", false)
	end
end
