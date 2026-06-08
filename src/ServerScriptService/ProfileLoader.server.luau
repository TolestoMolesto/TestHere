-- ─────────────────────────────────────────────
-- ProfileLoader.server.luau
-- Handles: Profile loading, session management,
-- data migration, BindToClose saving.
--
-- ProfileLoaded contract:
--   On successful load we set the `ProfileLoaded` attribute first,
--   THEN fire the `ProfileLoaded` RemoteEvent. Clients should read
--   the attribute on init; if it's not yet true, connect to the
--   event and wait. This avoids the late-connect race where a
--   client registers its listener after the server has fired.
-- ─────────────────────────────────────────────

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Manager = require(ServerStorage.Modules.Manager)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local RollRace = require(ServerStorage.Modules.RollRace)
local StatsManager = require(ServerStorage.Modules.StatsManager)
local Template = require(ServerStorage.Modules.TemplateData)

local LOG = "[ProfileLoader]"
local MAX_LOAD_RETRIES = 3
local RETRY_DELAY = 2
local KICK_MESSAGES = {
	Default = "You have been disconnected. Contact us on Discord if issues persist.",
	Shutdown = "Server has shutdown for an update! Check Discord for patch notes.",
	DataLoadFailed = "Failed to load your data after multiple attempts. Please rejoin!",
}

local function loadPlayerProfile(player: Player)
	for attempt = 1, MAX_LOAD_RETRIES do
		local success, result = pcall(function()
			return Manager.PlayerStore:StartSessionAsync(`{player.UserId}`, {
				Cancel = function()
					return player.Parent ~= Players
				end,
			})
		end)
		if success and result then
			return result
		end
		warn(`{LOG} Profile load attempt {attempt}/{MAX_LOAD_RETRIES} failed for {player.Name}: {tostring(result)}`)
		if attempt < MAX_LOAD_RETRIES then
			task.wait(RETRY_DELAY)
		end
	end
	return nil
end

local function endSessionAndKick(player: Player, profile, reason: string)
	if profile then
		Manager.Profiles[player] = nil
		profile:EndSession()
	end
	if player.Parent == Players then
		player:Kick(reason)
	end
end

local function onPlayerAdded(player: Player)
	local profile = loadPlayerProfile(player)
	if not profile then
		warn(`{LOG} Data load failed for {player.Name} ({player.UserId}) — kicking`)
		if player.Parent == Players then
			player:Kick(KICK_MESSAGES.DataLoadFailed)
		end
		return
	end

	-- Player may have left while StartSessionAsync was yielding.
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	-- profile:Reconcile() walks string-keyed nested tables (so Shared
	-- backfills automatically) but skips number-keyed entries, which
	-- means every slot in profile.Data.Slots is invisible to it.
	-- Reconcile each slot ourselves so new SlotData fields land on
	-- existing saves the next time the player joins.
	for _, slot in profile.Data.Slots do
		Template.reconcileSlot(slot)
	end

	profile.OnSessionEnd:Connect(function()
		Manager.Profiles[player] = nil
		if player.Parent == Players then
			player:Kick(KICK_MESSAGES.Default)
		end
	end)
	Manager.Profiles[player] = profile

	-- Auto-roll the active slot if it has never been rolled (Race == "NA").
	-- Must happen BEFORE LoadCharacter so the CharacterAdded handler in
	-- StatsManager.bind sees the resolved race on the very first spawn.
	RollRace.autoRollActive(player)

	-- Connect CharacterAdded BEFORE LoadCharacter so the mirror runs on
	-- this spawn (and every respawn) without a manual first-shot call.
	StatsManager.bind(player)

	local loadSuccess, loadErr = pcall(function()
		player:LoadCharacter()
	end)
	if not loadSuccess then
		warn(`{LOG} Failed to load character for {player.Name}: {tostring(loadErr)}`)
		endSessionAndKick(player, profile, KICK_MESSAGES.Default)
		return
	end

	-- Attribute is race-safe for clients that connect late; the event
	-- covers clients that are already listening.
	player:SetAttribute("ProfileLoaded", true)
	Remotes.ProfileLoaded:FireClient(player)
end

local function onPlayerRemoving(player: Player)
	local profile = Manager.Profiles[player]
	if profile then
		Manager.Profiles[player] = nil
		profile:EndSession()
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(onPlayerAdded, player)
end)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Save all active profiles concurrently on shutdown so a slow save
-- doesn't gate the rest within BindToClose's 30s window.
game:BindToClose(function()
	local players = Players:GetPlayers()
	local remaining = #players
	if remaining == 0 then
		return
	end
	local done = Instance.new("BindableEvent")
	for _, player in players do
		task.spawn(function()
			onPlayerRemoving(player)
			remaining -= 1
			if remaining == 0 then
				done:Fire()
			end
		end)
	end
	done.Event:Wait()
end)
