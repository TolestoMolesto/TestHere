--!strict
-- Server for the Ki-suppression "power output" dial. Two jobs:
--   * SetPowerOutput: a client (the bracket keys or the Settings slider) pushes a desired output %
--     (1-100). We clamp it, gate on the slot owning the PowerSuppression passive, write the slot, then
--     re-derive Humanoid.Stats so the reduced readout (DisplayedBattlePower) replicates to every lens.
--   * TEST GRANT: in Studio or for an Admin, flip the active slot's PowerSuppression on each spawn so
--     the feature is testable end-to-end. Live, non-admin players stay locked until a real acquisition
--     path sets the flag (acquisition is a known project-wide TODO; mirrors ItemServer's seedTestItems).
-- Both paths follow Train's shape: grab the live slot -> mutate it -> StatsManager.refresh; the profile
-- autosaves. The reduced number is pushed back purely through replicated attributes -- no echo remote.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Manager = require(ServerStorage.Modules.Manager)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local StatsManager = require(ServerStorage.Modules.StatsManager)

local MIN_OUTPUT = 1
local MAX_OUTPUT = 100

-- Studio or an Admin profile: the only ones granted the passive for now (see header).
local function isTester(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	local shared = Manager.getShared(player)
	return shared ~= nil and shared.Admin == true
end

-- Re-derive Humanoid.Stats, but only once the stat folders exist (StatsManager.bind ran on spawn).
-- If they don't yet, the pending writeValues will read whatever we just wrote to the slot anyway.
local function refreshIfReady(player: Player): ()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid:FindFirstChild("Stats") then
		StatsManager.refresh(player, { preserveHealth = true })
	end
end

Remotes.SetPowerOutput.OnServerEvent:Connect(function(player: Player, value: any)
	-- Reject non-numbers and NaN before clamping.
	if typeof(value) ~= "number" or value ~= value then
		return
	end
	local slot = Manager.getActiveSlot(player)
	if not slot then
		return
	end
	-- Gate: no passive, no dial. (StatsManager forces output to 100 without it anyway, so a stale write
	-- couldn't take effect -- but reject up front so we don't churn a needless refresh.)
	if slot.PowerSuppression ~= true then
		return
	end
	local clamped = math.clamp(math.floor(value + 0.5), MIN_OUTPUT, MAX_OUTPUT)
	if slot.PowerOutput == clamped then
		return -- unchanged; skip the refresh
	end
	slot.PowerOutput = clamped
	refreshIfReady(player)
end)

-- Grant the passive to testers on spawn, then refresh so CanSuppress + the dial reflect it at once.
local function grantIfTester(player: Player): ()
	if not isTester(player) then
		return
	end
	local slot = Manager.getActiveSlot(player)
	if not slot then
		return -- profile not loaded yet; a later spawn catches it
	end
	if slot.PowerSuppression ~= true then
		slot.PowerSuppression = true
	end
	refreshIfReady(player)
end

local function bindPlayer(player: Player): ()
	if player.Character then
		task.defer(grantIfTester, player)
	end
	player.CharacterAdded:Connect(function()
		task.defer(grantIfTester, player)
	end)
end

Players.PlayerAdded:Connect(bindPlayer)
for _, player in Players:GetPlayers() do
	bindPlayer(player)
end
