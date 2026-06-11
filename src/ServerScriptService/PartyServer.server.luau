-- Server entry for the Party system (a Leader + up to 5 others, 6 max). In-memory only -- parties
-- live for the life of the server and are never written to the profile. Wires the party remotes to
-- PartyState and broadcasts the fresh roster to every affected player after each change. "Just a
-- roster" for now: membership + invites + leadership, with no combat/teleport perks yet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local PartyState = require(ServerStorage.Modules.PartyState)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

-- Push each affected player their current roster (nil clears a leaver's UI). De-duped + presence-guarded.
local function pushUpdate(affected: { Player })
	local seen: { [Player]: boolean } = {}
	for _, player in affected do
		if player and not seen[player] and player.Parent then
			seen[player] = true
			Remotes.PartyUpdated:FireClient(player, PartyState.rosterFor(player))
		end
	end
end

local function asPlayer(value: any): Player?
	if typeof(value) == "Instance" and value:IsA("Player") then
		return value
	end
	return nil
end

Remotes.GetParty.OnServerInvoke = function(player: Player)
	return PartyState.rosterFor(player)
end

Remotes.RequestPartyInvite.OnServerEvent:Connect(function(player: Player, targetValue: any)
	local target = asPlayer(targetValue)
	if not target then
		return
	end
	local ok, reason = PartyState.invite(player, target)
	if ok then
		-- Prompt the target, and refresh the inviter (a solo inviter just became a 1-person leader).
		Remotes.PartyInviteReceived:FireClient(target, player.DisplayName, player.UserId)
		pushUpdate({ player })
	else
		Remotes.PartyNotice:FireClient(player, reason or "Couldn't send that invite.")
	end
end)

Remotes.RespondPartyInvite.OnServerEvent:Connect(function(player: Player, accept: any)
	if accept == true then
		local party, reason = PartyState.acceptInvite(player)
		if party then
			pushUpdate(party.members)
			for _, member in party.members do
				if member ~= player and member.Parent then
					Remotes.PartyNotice:FireClient(member, `{player.DisplayName} joined the party.`)
				end
			end
		elseif reason then
			Remotes.PartyNotice:FireClient(player, reason)
		end
	else
		PartyState.declineInvite(player)
	end
end)

Remotes.LeaveParty.OnServerEvent:Connect(function(player: Player)
	pushUpdate(PartyState.leave(player))
end)

Remotes.KickFromParty.OnServerEvent:Connect(function(player: Player, targetValue: any)
	local target = asPlayer(targetValue)
	if not target then
		return
	end
	local affected = PartyState.kick(player, target)
	pushUpdate(affected)
	if #affected > 0 and target.Parent then
		Remotes.PartyNotice:FireClient(target, "You were removed from the party.")
	end
end)

Remotes.PromoteLeader.OnServerEvent:Connect(function(player: Player, targetValue: any)
	local target = asPlayer(targetValue)
	if not target then
		return
	end
	pushUpdate(PartyState.promote(player, target))
end)

Remotes.DisbandParty.OnServerEvent:Connect(function(player: Player)
	local affected = PartyState.disband(player)
	pushUpdate(affected)
	for _, member in affected do
		if member ~= player and member.Parent then
			Remotes.PartyNotice:FireClient(member, "The party was disbanded.")
		end
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	pushUpdate(PartyState.playerLeaving(player))
end)
