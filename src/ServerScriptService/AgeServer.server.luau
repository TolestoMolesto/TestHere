--!strict
-- Runtime driver for character aging (logic + tuning live in ServerStorage/Modules/Age).
--
-- The aging model is ACTIVE PLAYTIME: once every few seconds, each player who's alive in a real world
-- accumulates the elapsed time onto their ACTIVE slot's PlayTime. Age + body scale both derive from
-- that, so a brand-new character spawns kid-sized (Age.KID_SCALE) and grows to full adult size over
-- Age.GROW_PLAY_HOURS of play. Nothing ages offline, on a slot you aren't playing, or while parked in
-- the Main Menu lobby.
--
-- Spawn-time scale is set by PlayerRaceBuilder (every respawn rebuilds at the current size). Here we
-- also (a) keep the live Humanoid.Appearance.Age attribute fresh for any HUD/UI, and (b) gently grow
-- the LIVE character between respawns once it's drifted past SCALE_EPSILON -- rare (a step every
-- several minutes of play), so a live ScaleTo never disturbs the playing animations.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local Age = require(ServerStorage.Modules.Age)
local Manager = require(ServerStorage.Modules.Manager)
local PlayerRaceBuilder = require(ServerStorage.Modules.PlayerRaceBuilder)
local ServerSettings = require(ServerStorage.Modules.ServerSettings)

local TICK = 5 -- seconds between aging passes
local SCALE_EPSILON = 0.01 -- only re-scale a live body once age has moved it at least this much

-- The Main Menu lobby isn't "playing a character", so no aging happens there (mirrors GravityServer).
local SAFE_WORLD = { MainMenu = true }

local function isMenuWorld(): boolean
	local world = ServerSettings.getCurrentWorld()
	return world ~= nil and SAFE_WORLD[world] == true
end

local function tickPlayer(player: Player, dt: number)
	local slot = Manager.getActiveSlot(player)
	if not slot then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Accumulate active play time, then refresh the derived age (cached on the slot + mirrored live).
	slot.PlayTime += dt
	slot.Age = Age.ageFromPlayTime(slot.PlayTime)
	local appearance = humanoid:FindFirstChild("Appearance")
	if appearance then
		appearance:SetAttribute("Age", slot.Age)
	end

	-- Grow the live body when it's drifted from the age-driven target (kept rare by SCALE_EPSILON, so
	-- the occasional ScaleTo doesn't disturb whatever animation is playing). Skipped while ragdolled/
	-- downed so a resize never pops the physics ragdoll -- the next respawn rebuilds at the right size.
	if character:GetAttribute("ToggleRagdoll") ~= true then
		local target = PlayerRaceBuilder.bodyScale(slot)
		if math.abs(target - character:GetScale()) >= SCALE_EPSILON then
			character:ScaleTo(target)
		end
	end
end

task.spawn(function()
	local last = os.clock()
	while true do
		task.wait(TICK)
		local now = os.clock()
		local dt = now - last
		last = now
		if isMenuWorld() then
			continue
		end
		for _, player in Players:GetPlayers() do
			tickPlayer(player, dt)
		end
	end
end)
