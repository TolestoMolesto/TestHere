--!strict
-- Runtime driver for the gravity physiology (logic + tuning live in ServerStorage/Modules/Gravity).
-- Per player, once a second (and immediately whenever the world gravity changes): slow WalkSpeed by the
-- strain penalty, bleed crush damage, and acclimate GravityMastery toward the current exposure. Also
-- stamps the movement baselines (UseJumpPower + JumpPower) on every fresh character so real
-- Workspace.Gravity physically shapes the jump (model B: the chamber dial moves Workspace.Gravity for
-- the whole server -- see GravityChamberServer).
--
-- The bleed is ENVIRONMENTAL: it never combat-tags, never credits a killer, never cancels a Spar, and
-- floors at the knockout HP (StateBinders' bindKnockout downs + revives from there) -- so overloading a
-- chamber makes you COLLAPSE, not die a PvP death. Forcefield (spawn protection), being downed and
-- safe-zone worlds are all skipped, and a short grace after a gravity collapse stops an instant re-down.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Gravity = require(ServerStorage.Modules.Gravity)
local Manager = require(ServerStorage.Modules.Manager)
local ServerSettings = require(ServerStorage.Modules.ServerSettings)

-- Mirrors StateBinders.KNOCKOUT_FLOOR / Damage.apply: never take a player below this HP -- leave the
-- knockout system to ragdoll + revive them from the floor.
local KNOCKOUT_FLOOR = 1

local TICK = 1 -- seconds between bleed/acclimation passes (movement also re-applies here)
local POST_DOWN_GRACE = 10 -- seconds of bleed immunity after a gravity collapse, so revive isn't an instant re-down

-- Worlds where the crush bleed is suppressed entirely (lobby/menu). Movement + acclimation still run,
-- but they're no-ops at 1x gravity anyway.
local SAFE_WORLD = { MainMenu = true }

-- Per-character timestamp (os.clock) until which the bleed is paused. Weak-keyed so dead characters GC.
local graceUntil: { [Model]: number } = {}
setmetatable(graceUntil, { __mode = "k" })

local function isSafeWorld(): boolean
	local world = ServerSettings.getCurrentWorld()
	return world ~= nil and SAFE_WORLD[world] == true
end

local function setupMovement(humanoid: Humanoid)
	-- UseJumpPower (not JumpHeight) so higher Workspace.Gravity actually flattens the jump; the base
	-- power matches Earth's default ~7.2-stud hop.
	humanoid.UseJumpPower = true
	humanoid.JumpPower = Gravity.BASE_JUMP_POWER
end

-- Apply only the WalkSpeed strain penalty -- cheap, and reused on the gravity-changed signal so the
-- dial responds instantly instead of up to a tick later.
local function applyMovement(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid then
		return
	end
	local penalty = Gravity.walkPenalty(Gravity.ratioOf(character))
	humanoid.WalkSpeed = Gravity.BASE_WALKSPEED * (1 - penalty)
end

local function applyMovementToAll()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			applyMovement(character)
		end
	end
end

local function tickPlayer(player: Player, dt: number, safe: boolean)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local stats = humanoid:FindFirstChild("Stats")
	if not stats then
		return
	end

	local exposure = Gravity.exposure()
	local mastery = Gravity.masteryOf(character)
	local ratio = exposure / mastery

	-- Movement penalty (strain band and up).
	humanoid.WalkSpeed = Gravity.BASE_WALKSPEED * (1 - Gravity.walkPenalty(ratio))

	-- Crush bleed -- environmental, never below the knockout floor. Skipped while protected, in a safe
	-- world, or inside the post-collapse grace window. While they're actually downed we instead keep
	-- pushing the grace window ahead of the revive, so a fresh-revived player isn't instantly re-downed.
	local protected = character:GetAttribute("Forcefield") == true
	if character:GetAttribute("ToggleRagdoll") == true then
		graceUntil[character] = os.clock() + POST_DOWN_GRACE
	elseif not safe and not protected and os.clock() >= (graceUntil[character] or 0) then
		local dps = Gravity.bleedDps(ratio, humanoid.MaxHealth)
		if dps > 0 then
			local survivable = math.max(humanoid.Health - KNOCKOUT_FLOOR, 0)
			local applied = math.min(dps * dt, survivable)
			if applied > 0 then
				humanoid:TakeDamage(applied)
			end
		end
	end

	-- Acclimation: raise GravityMastery toward exposure, mutating the slot + mirroring the live attribute
	-- (same pattern as Longevity). NPCs/shadows have no player, so this path is players-only by design.
	local newMastery = Gravity.acclimate(mastery, exposure, ratio, dt)
	if newMastery > mastery then
		local slot = Manager.getActiveSlot(player)
		if slot then
			slot.GravityMastery = newMastery
			stats:SetAttribute("GravityMastery", newMastery)
		end
	end
end

local function setupCharacter(character: Model)
	local h = character:WaitForChild("Humanoid", 5)
	if h and h:IsA("Humanoid") then
		setupMovement(h)
	end
end

local function bindPlayer(player: Player)
	if player.Character then
		setupCharacter(player.Character)
	end
	player.CharacterAdded:Connect(setupCharacter)
end

for _, player in Players:GetPlayers() do
	bindPlayer(player)
end
Players.PlayerAdded:Connect(bindPlayer)

Workspace:GetPropertyChangedSignal("Gravity"):Connect(applyMovementToAll)

task.spawn(function()
	local last = os.clock()
	while true do
		task.wait(TICK)
		local now = os.clock()
		local dt = now - last
		last = now
		local safe = isSafeWorld()
		for _, player in Players:GetPlayers() do
			tickPlayer(player, dt, safe)
		end
	end
end)
