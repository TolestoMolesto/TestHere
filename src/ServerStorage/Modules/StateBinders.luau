--!strict

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local ChargeFX = require(ServerStorage.Modules.ChargeFX)
local Damage = require(ServerStorage.Modules.Damage)
local FormFX = require(ServerStorage.Modules.FormFX)
local Manager = require(ServerStorage.Modules.Manager)
local Ragdoll = require(ServerStorage.Modules.Ragdoll)

local StateBinders = {}

type Stop = () -> ()

local STAMINA_REGEN_DELAY = 10
local STAMINA_REGEN_RATE = 0.05
local STAMINA_REGEN_TICK = 1

local REST_HEAL_RATE = 0.05
local REST_HEAL_INTERVAL = 5
-- Resting also tops Stamina + Ki back up, each `rate` of max per REST_HEAL_INTERVAL (~20s empty->
-- full). No idle delay (unlike STAMINA_REGEN_DELAY), so resting is the fast, deliberate recovery;
-- Charge still refills Ki faster for the focused case.
local REST_STAMINA_RATE = 0.25
local REST_KI_RATE = 0.25

-- Resting also refills Longevity (Train's BP-gating pool). From empty that's
-- ceil(LONGEVITY_MAX / LONGEVITY_REGEN_PER_TICK) ticks of REST_HEAL_INTERVAL each (~40s here).
-- LONGEVITY_MAX mirrors the per-slot starting Longevity in TemplateData.
local LONGEVITY_MAX = 100
local LONGEVITY_REGEN_PER_TICK = 12

local NAMEKIAN_RACE = "Namekian"
local NAMEKIAN_KI_REGEN_RATE = 0.02
local KI_REGEN_TICK = 1

local KNOCKOUT_FLOOR = 1 -- pairs with Damage.apply; keep in sync
local KNOCKOUT_DURATION = 30
local KNOCKOUT_REVIVE_FRACTION = 0.25

-- Seconds a freshly-spawned player stays intangible (Forcefield) if they never act. The shield also
-- drops the instant they commit to an offensive action (ActionController.perform).
local SPAWN_PROTECTION_DURATION = 8

local function bindStaminaRegen(character: Model): Stop
	local connections: { RBXScriptConnection } = {}
	local thread: thread? = nil
	local regenerating = false
	local alive = true

	local function stopThread()
		if thread then
			task.cancel(thread)
			thread = nil
		end
	end

	local function schedule()
		if regenerating or not alive then
			return
		end
		local current = character:GetAttribute("Stamina") :: number?
		local max = character:GetAttribute("MaxStamina") :: number?
		if current == nil or max == nil then
			return
		end
		if current >= max then
			stopThread()
			return
		end
		stopThread()
		thread = task.spawn(function()
			task.wait(STAMINA_REGEN_DELAY)
			regenerating = true
			while alive and character.Parent do
				local cur = character:GetAttribute("Stamina") :: number?
				local m = character:GetAttribute("MaxStamina") :: number?
				if cur == nil or m == nil then
					task.wait(STAMINA_REGEN_TICK)
					continue
				end
				if cur >= m then
					break
				end
				character:SetAttribute("Stamina", math.min(cur + m * STAMINA_REGEN_RATE, m))
				task.wait(STAMINA_REGEN_TICK)
			end
			regenerating = false
			thread = nil
		end)
	end

	table.insert(connections, character:GetAttributeChangedSignal("Stamina"):Connect(schedule))
	schedule()

	return function()
		alive = false
		stopThread()
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
	end
end

-- Restore a current/max resource pair on the Model (Stamina, Ki) toward its max by `rate` of max,
-- clamped up. Mirrors how bindStaminaRegen/bindKiRegen write these attrs; combat + HUD read them live.
local function regenResource(character: Model, currentAttr: string, maxAttr: string, rate: number): ()
	local current = character:GetAttribute(currentAttr) :: number?
	local max = character:GetAttribute(maxAttr) :: number?
	if current == nil or max == nil or current >= max then
		return
	end
	character:SetAttribute(currentAttr, math.min(current + max * rate, max))
end

-- While Resting, top the active slot's Longevity back up (players only -- NPCs/shadows have no
-- profile, so they no-op). Mutates the slot (the source of truth) and mirrors onto Humanoid.Stats so
-- the HUD ticks up live; StatsManager re-derives the same number on its next refresh.
local function regenLongevity(character: Model, humanoid: Humanoid): ()
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	local slot = Manager.getActiveSlot(player)
	if not slot or slot.Longevity >= LONGEVITY_MAX then
		return
	end
	local restored = math.min(LONGEVITY_MAX, slot.Longevity + LONGEVITY_REGEN_PER_TICK)
	slot.Longevity = restored
	local stats = humanoid:FindFirstChild("Stats")
	if stats then
		stats:SetAttribute("Longevity", restored)
	end
end

local function bindRestingHeal(character: Model): Stop
	local connections: { RBXScriptConnection } = {}
	local looping = false
	local alive = true

	local function onChange()
		if not alive or looping or not character:GetAttribute("Resting") then
			return
		end
		looping = true
		task.spawn(function()
			local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
			if not humanoid then
				looping = false
				return
			end
			while alive and character.Parent and character:GetAttribute("Resting") do
				Damage.heal(character, humanoid.MaxHealth * REST_HEAL_RATE)
				regenLongevity(character, humanoid)
				regenResource(character, "Stamina", "MaxStamina", REST_STAMINA_RATE)
				regenResource(character, "Ki", "MaxKi", REST_KI_RATE)
				task.wait(REST_HEAL_INTERVAL)
			end
			looping = false
		end)
	end

	table.insert(connections, character:GetAttributeChangedSignal("Resting"):Connect(onChange))

	return function()
		alive = false
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
	end
end

local function bindKiRegen(character: Model): Stop
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return function() end
	end
	local identity = humanoid:FindFirstChild("Identity")
	if not identity or identity:GetAttribute("Race") ~= NAMEKIAN_RACE then
		return function() end
	end

	local alive = true
	task.spawn(function()
		while alive and character.Parent do
			task.wait(KI_REGEN_TICK)
			if not alive then
				break
			end
			if character:GetAttribute("Charging") then
				continue
			end
			local ki = character:GetAttribute("Ki") :: number?
			local maxKi = character:GetAttribute("MaxKi") :: number?
			if ki == nil or maxKi == nil or ki >= maxKi then
				continue
			end
			character:SetAttribute("Ki", math.min(ki + maxKi * NAMEKIAN_KI_REGEN_RATE, maxKi))
		end
	end)

	return function()
		alive = false
	end
end

local function bindRagdoll(character: Model): Stop
	local connection = character:GetAttributeChangedSignal("ToggleRagdoll"):Connect(function()
		Ragdoll.setEnabled(character, character:GetAttribute("ToggleRagdoll") == true)
	end)

	if character:GetAttribute("ToggleRagdoll") then
		Ragdoll.setEnabled(character, true)
	end

	return function()
		connection:Disconnect()
		Ragdoll.setEnabled(character, false)
	end
end

local function bindKnockout(character: Model): Stop
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid then
		return function() end
	end
	humanoid.BreakJointsOnDeath = false

	local connections: { RBXScriptConnection } = {}
	local downed = false
	local generation = 0
	local alive = true

	local function revive()
		character:SetAttribute("ToggleRagdoll", false)
		if humanoid.Parent then
			humanoid.Health = math.max(humanoid.Health, math.floor(humanoid.MaxHealth * KNOCKOUT_REVIVE_FRACTION))
		end
		downed = false
	end

	local function enterDowned()
		if downed then
			return
		end
		downed = true

		for _, flag in { "Flying", "BoostFlying", "Resting", "Charging", "Blocking" } do
			character:SetAttribute(flag, false)
		end
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.Anchored = false
		end

		character:SetAttribute("ToggleRagdoll", true)

		local gen = generation + 1
		generation = gen
		task.delay(KNOCKOUT_DURATION, function()
			if alive and downed and generation == gen and character.Parent then
				revive()
			end
		end)
	end

	-- IsShadow is set just AFTER bind runs, so check at down-time not bind-time.
	table.insert(
		connections,
		humanoid.HealthChanged:Connect(function(health: number)
			if downed or health > KNOCKOUT_FLOOR then
				return
			end
			if character:GetAttribute("IsShadow") then
				return
			end
			enterDowned()
		end)
	)

	return function()
		alive = false
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
	end
end

-- Grants players a Forcefield the instant they spawn -- "haven't done anything yet": fully
-- intangible, so no incoming damage, knockback, lock-on, or scan-based hit lands (enforced in
-- Damage/Knockback/Hitbox/TargetLock). It clears after SPAWN_PROTECTION_DURATION, or the moment they
-- commit to an offensive action (ActionController.perform drops it on a dropsProtection action).
-- NPCs/shadows have no Player, so they never receive it.
local function bindSpawnProtection(character: Model): Stop
	if not Players:GetPlayerFromCharacter(character) then
		return function() end
	end

	character:SetAttribute("Forcefield", true)

	local alive = true
	task.delay(SPAWN_PROTECTION_DURATION, function()
		if alive and character.Parent and character:GetAttribute("Forcefield") then
			character:SetAttribute("Forcefield", false)
		end
	end)

	return function()
		alive = false
	end
end

function StateBinders.bind(character: Model): Stop
	local stoppers: { Stop } = {
		bindStaminaRegen(character),
		bindRestingHeal(character),
		bindKiRegen(character),
		bindSpawnProtection(character),
		ChargeFX.bind(character),
		FormFX.bind(character),
		bindRagdoll(character),
		bindKnockout(character),
	}

	local stopped = false
	local function stop()
		if stopped then
			return
		end
		stopped = true
		for _, s in stoppers do
			s()
		end
		table.clear(stoppers)
	end

	character.Destroying:Connect(stop)

	return stop
end

return StateBinders
