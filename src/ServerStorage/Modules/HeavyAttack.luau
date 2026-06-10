local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Animations = require(ReplicatedStorage.Modules.Animations)
local CameraShake = require(ServerStorage.Modules.CameraShake)
local Charge = require(ServerStorage.Modules.Charge)
local CombatTag = require(ServerStorage.Modules.CombatTag)
local Damage = require(ServerStorage.Modules.Damage)
local FormState = require(ServerStorage.Modules.FormState)
local HitFX = require(ServerStorage.Modules.HitFX)
local Hitbox = require(ServerStorage.Modules.Hitbox)
local Knockback = require(ServerStorage.Modules.Knockback)
local ParryHandler = require(ServerStorage.Modules.ParryHandler)
local Train = require(ServerStorage.Modules.Train)

local HEAVY_BASE_DAMAGE = 25
local HEAVY_KNOCKBACK_FORCE = 150
local HEAVY_WINDUP = 0.2
local HEAVY_ACTIVE = 0.3
local HEAVY_RECOVERY = 0.35 -- post-active lockout; kept short so the heavy isn't a long commitment
local HEAVY_RATE_FLOOR = 0.8
local GUARD_BREAK_LOCKOUT = 2.0
local VANISH_WINDOW_DURATION = 1.5
local MAX_POSITION_DELTA_STUDS = 20
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

	-- State gating is enforced centrally in ActionController.perform via ActionConfig.HeavyAttack
	-- .blockedBy (which keys off HeavyCooldown, not AttackCooldown, so a light combo can cancel into a
	-- heavy). The lock-on requirement + rate floor + stamina cost below stay handler-specific.
	local lastHeavyTime = invoker:GetAttribute("LastHeavyTime") :: number? or 0
	local currentTime = DateTime.now().UnixTimestampMillis / 1_000

	if currentTime - lastHeavyTime < HEAVY_RATE_FLOOR then
		return
	end

	local stamina = invoker:GetAttribute("Stamina") :: number? or -1
	local staminaNeeded = invoker:GetAttribute("HeavyStaminaNeeded") :: number? or 0

	if stamina < staminaNeeded then
		return
	end

	local player = Players:GetPlayerFromCharacter(invoker)

	if player and not invoker:GetAttribute("LockedOn") then
		return
	end

	local handlingPerfectBlock = false

	invoker:SetAttribute("LastHeavyTime", currentTime)
	Charge.stop(invoker)

	invoker:SetAttribute("Attacking", true)
	invoker:SetAttribute("HeavyCooldown", true)
	invoker:SetAttribute("CanBlock", false)
	invoker:SetAttribute("Swinging", true)
	invoker:SetAttribute("AttackSequence", 0)
	invoker:SetAttribute("Stamina", stamina - staminaNeeded)

	if not player then
		Animations.play(invoker, "heavyattack", 0.1, nil, Animations.attackSpeed(invoker))
	end

	task.wait(HEAVY_WINDUP)

	-- CanBlock is cleared above so you can't guard mid-swing; nothing else resets it, so this is required.
	task.delay(0.25, function(): ()
		invoker:SetAttribute("Swinging", false)
		invoker:SetAttribute("CanBlock", true)
	end)

	local resolvedCFrame = resolveAttackCFrame(invoker, requestedCFrame)
	local hitboxSize = HITBOX_SIZE

	local entities = Hitbox.scanBox(resolvedCFrame * CFrame.new(0, 0, -hitboxSize.Z / 2), hitboxSize, { invoker })

	for _, entity in entities do
		if entity:GetAttribute("InSafeZone") then
			continue
		end

		local blockingFrontally = entity:GetAttribute("Blocking")
			and Hitbox.isInFront(entity, (hrp :: BasePart).Position)

		-- Perfect block beats everything (deliberate defensive timing), so resolve it first.
		if blockingFrontally and entity:GetAttribute("PerfectBlocked") then
			handlingPerfectBlock = true
			entity:SetAttribute("PerfectBlocked", false)

			ParryHandler.parry(invoker, entity)

			task.delay(ParryHandler.Configuration.TIMEOUT, function(): ()
				invoker:SetAttribute("HeavyCooldown", false)
			end)

			continue
		end

		-- Roll the hit before the guard break so a dodge (0) whiffs completely: no guard break,
		-- no damage, no knockback. Stamina was already paid up-front.
		if Damage.apply(entity, invoker, HEAVY_BASE_DAMAGE, "Physical") == 0 then
			Train.dodged(entity, invoker)
			continue
		end

		FormState.awardCombatHit(invoker)
		Train.landedHeavy(invoker, entity)

		-- Landed on a frontal blocker: break their guard, then fall through to damage + knockback.
		if blockingFrontally then
			HitFX.spawnBlockFX(entity, entity.HumanoidRootPart.Position)

			entity:SetAttribute("Stamina", 0)
			entity:SetAttribute("BlockBroken", true)
			entity:SetAttribute("Blocking", false)
			entity:SetAttribute("NoAttacking", true)
			entity:SetAttribute("NoBlocking", true)

			task.delay(GUARD_BREAK_LOCKOUT, function(): ()
				if entity and entity.Parent then
					entity:SetAttribute("BlockBroken", false)
					entity:SetAttribute("NoAttacking", false)
					entity:SetAttribute("NoBlocking", false)
				end
			end)
		end

		HitFX.spawnOnCharacter(entity, entity.HumanoidRootPart.Position)

		CombatTag.applyCombatTag(invoker, entity)

		if player then
			CameraShake.shakePlayer(player, CameraShake.Intensity.Heavy, 0.4)
		end

		entity:PivotTo(CFrame.lookAt(entity:GetPivot().Position, invoker:GetPivot().Position))
		Knockback.apply(entity, (hrp :: BasePart).CFrame.LookVector, HEAVY_KNOCKBACK_FORCE)

		entity:SetAttribute("CanVanishTo", true)
		task.delay(VANISH_WINDOW_DURATION, function()
			if entity and entity.Parent and entity:GetAttribute("CanVanishTo") then
				entity:SetAttribute("CanVanishTo", false)
			end
		end)
	end

	task.wait(HEAVY_ACTIVE)

	invoker:SetAttribute("Attacking", false)

	-- Perfect block already scheduled the cooldown clear via ParryHandler; don't double-schedule.
	if not handlingPerfectBlock then
		task.delay(HEAVY_RECOVERY, function(): ()
			invoker:SetAttribute("HeavyCooldown", false)
		end)
	end
end
