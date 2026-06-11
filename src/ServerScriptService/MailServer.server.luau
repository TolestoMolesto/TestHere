-- Server entry for the Mail system, mirroring ItemServer. Serves the mailbox UI the sanitised list
-- (Mail.list), handles claim / delete / mark-read requests, runs the join + periodic broadcast sync,
-- and pokes the client (MailChanged) after any change. Mail balance/config never leaves the server;
-- only the curated list (display + resolved reward icons) crosses.
--
-- BROADCAST SYNC: a posted broadcast (MailBroadcast) reaches everyone via two paths -- (1) the player's
-- join sync, and (2) a periodic re-sync loop that refreshes the shared cache and materializes new
-- broadcasts into every online player's inbox. So offline players + future joiners pick it up at load,
-- and currently-online players within one re-sync interval, with no MessagingService needed.
--
-- TEST SCAFFOLDING (Studio or an Admin, like ItemServer's seedTestItems): on first join a sample
-- personal mail is sent so claiming is testable end-to-end. The canonical way to fire a BROADCAST is
-- Mail.broadcast({...}) (call it from real code -- codes / world boss / admin tooling -- or the Studio
-- command bar); an Admin "/mailtest" chat command is wired below as a convenience where chat fires.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Mail = require(ServerStorage.Modules.Mail)
local MailBroadcast = require(ServerStorage.Modules.MailBroadcast)
local Manager = require(ServerStorage.Modules.Manager)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local PROFILE_WAIT_TIMEOUT = 30
local RESYNC_INTERVAL = 60 -- seconds between shared-cache refresh + materialize for online players

local SAMPLE_FROM = "Project Kaioshin"
local SAMPLE_SUBJECT = "Welcome to the Mailbox!"

local function isTester(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	local shared = Manager.getShared(player)
	return shared ~= nil and shared.Admin == true
end

local function pushMail(player: Player)
	Remotes.MailChanged:FireClient(player, Mail.list(player))
end

-- Block until the player's profile is loaded (Manager holds it), or the timeout elapses / they leave.
local function waitForProfile(player: Player): boolean
	local elapsed = 0
	while player.Parent == Players do
		if Manager.getProfile(player) then
			return true
		end
		if elapsed >= PROFILE_WAIT_TIMEOUT then
			return false
		end
		task.wait(0.5)
		elapsed += 0.5
	end
	return false
end

local function hasSample(player: Player): boolean
	for _, m in Mail.list(player) do
		if m.from == SAMPLE_FROM and m.subject == SAMPLE_SUBJECT then
			return true
		end
	end
	return false
end

-- One sample personal mail so the system is testable. Rewards intentionally use items the ItemServer
-- tester-seed does NOT fill to cap (statues / a Dragon Ball), so the happy claim path works out of the
-- box. (Mailing an already-capped item like a seeded Sensu Bean is what exercises the slot-full reject.)
local function seedTestMail(player: Player)
	if not isTester(player) then
		return
	end
	if not Manager.getProfile(player) then
		return
	end
	if hasSample(player) then
		return -- already seeded on a previous session; don't pile up duplicates
	end
	Mail.sendToPlayer(player, {
		from = SAMPLE_FROM,
		subject = SAMPLE_SUBJECT,
		body = "Thanks for testing the mail system! Claim the rewards below. Items land on whichever character "
			.. "slot is active when you claim; Race Spins and Game Passes go to your account.",
		rewards = {
			{ kind = "Item", itemId = "HerculeStatueCopper", amount = 3 },
			{ kind = "Item", itemId = "EarthDragonBall1", amount = 1 },
			{ kind = "Spins", amount = 10 },
			{ kind = "Pass", passKey = "InstantSpins" },
		},
	})
end

-- Admin convenience: post a sample broadcast to everyone. Player.Chatted only fires under legacy chat;
-- if this game runs TextChatService, trigger a broadcast with Mail.broadcast({...}) from the command bar.
local function handleChat(player: Player, message: string)
	if not isTester(player) then
		return
	end
	if message:lower():gsub("%s+", "") ~= "/mailtest" then
		return
	end
	local id, err = Mail.broadcast({
		from = SAMPLE_FROM,
		subject = "Compensation: Server Update",
		body = "We found a bug and pushed a fix. Here's a little something for everyone -- thanks for your patience!",
		rewards = {
			{ kind = "Spins", amount = 5 },
			{ kind = "Item", itemId = "HerculeStatueSilver", amount = 1 },
		},
	})
	if id then
		print(`[MailServer] /mailtest posted broadcast {id}`)
	else
		warn(`[MailServer] /mailtest failed: {err}`)
	end
end

Remotes.GetMail.OnServerInvoke = function(player: Player)
	return Mail.list(player)
end

Remotes.ClaimMail.OnServerInvoke = function(player: Player, mailId: any)
	if type(mailId) ~= "string" then
		return { ok = false, reason = "Invalid mail", mail = Mail.list(player) }
	end
	local ok, reason = Mail.claim(player, mailId)
	return { ok = ok, reason = reason, mail = Mail.list(player) }
end

Remotes.DeleteMail.OnServerEvent:Connect(function(player: Player, mailId: any)
	if type(mailId) == "string" then
		Mail.delete(player, mailId)
	end
end)

Remotes.MarkMailRead.OnServerEvent:Connect(function(player: Player, mailId: any)
	if type(mailId) == "string" then
		Mail.markRead(player, mailId)
	end
end)

local function onPlayerAdded(player: Player)
	task.spawn(function()
		if not waitForProfile(player) then
			return
		end
		Mail.syncBroadcasts(player) -- pulls any active broadcasts into the inbox (pushes if it adds any)
		seedTestMail(player)
		pushMail(player) -- guarantees the client has a list (+ unread badge) on join, even if nothing new
	end)
	player.Chatted:Connect(function(message)
		handleChat(player, message)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

-- Periodic broadcast re-sync: keep the shared cache fresh and materialize new broadcasts for everyone
-- online, so a broadcast posted on another server reaches them without a rejoin.
task.spawn(function()
	while true do
		task.wait(RESYNC_INTERVAL)
		MailBroadcast.fetchCache()
		for _, player in Players:GetPlayers() do
			if Manager.getProfile(player) then
				Mail.syncBroadcasts(player)
			end
		end
	end
end)
