local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Manager = require(ServerStorage.Modules.Manager)
local Monetization = require(ServerStorage.Modules.Monetization)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local RollRace = require(ServerStorage.Modules.RollRace)
local StatsManager = require(ServerStorage.Modules.StatsManager)
local Template = require(ServerStorage.Modules.TemplateData)

-- Wire the single ProcessReceipt callback + game-pass purchase handling once, at server start.
Monetization.init()

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

	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	-- Reconcile() skips number-keyed entries, so Slots are invisible to it; patch each slot manually.
	for _, slot in profile.Data.Slots do
		Template.reconcileSlot(slot)
	end
	-- Global client preferences nest deeper than Reconcile() fills; patch them too.
	Template.reconcileSettings(profile.Data)
	Template.reconcileKeybinds(profile.Data)
	-- Shared's newer roller fields (RollCount/GlobalPity/RedeemedCodes) need the same backfill.
	Template.reconcileShared(profile.Data)
	-- Mail is a top-level array Reconcile() skips (SeenBroadcasts rides along in Shared, handled above).
	Template.reconcileMail(profile.Data)

	profile.OnSessionEnd:Connect(function()
		Manager.Profiles[player] = nil
		if player.Parent == Players then
			player:Kick(KICK_MESSAGES.Default)
		end
	end)
	Manager.Profiles[player] = profile

	-- Resolve game-pass ownership and apply unlocks before the character builds, so a pass that
	-- unlocks a race is reflected on first spawn. Yields briefly on the ownership web calls.
	Monetization.onProfileLoaded(player)

	-- Must run before LoadCharacter so StatsManager.bind sees the resolved race on first spawn.
	RollRace.autoRollActive(player)

	StatsManager.bind(player)

	local loadSuccess, loadErr = pcall(function()
		player:LoadCharacter()
	end)
	if not loadSuccess then
		warn(`{LOG} Failed to load character for {player.Name}: {tostring(loadErr)}`)
		endSessionAndKick(player, profile, KICK_MESSAGES.Default)
		return
	end

	-- Attribute guards late-connecting clients; event covers clients already listening.
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
