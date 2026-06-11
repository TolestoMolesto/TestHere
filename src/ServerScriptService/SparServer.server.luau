-- Server entry for the Spar system (consensual 1v1 "training duel"). Wires the spar remotes to the
-- Spar module; the bout rules themselves (no combat tag, knockdown-to-restore, outsider-cancels-and-
-- reverts) live in Spar + the Damage/CombatTag hooks. Requiring Spar here also starts its leash
-- watchdog at boot. In-memory + per-server; nothing is persisted.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Spar = require(ServerStorage.Modules.Spar)

local function asPlayer(value: any): Player?
	if typeof(value) == "Instance" and value:IsA("Player") then
		return value
	end
	return nil
end

Remotes.RequestSpar.OnServerEvent:Connect(function(player: Player, targetValue: any)
	local target = asPlayer(targetValue)
	if not target then
		return
	end
	local ok, reason = Spar.request(player, target)
	if ok then
		Remotes.SparInvite:FireClient(target, player.DisplayName, player.UserId)
	else
		Remotes.SparNotice:FireClient(player, reason or "Couldn't send that challenge.")
	end
end)

Remotes.RespondSpar.OnServerEvent:Connect(function(player: Player, accept: any)
	if accept == true then
		local opponent, reason = Spar.accept(player)
		if opponent then
			Remotes.SparStarted:FireClient(player, opponent.DisplayName, opponent.UserId)
			Remotes.SparStarted:FireClient(opponent, player.DisplayName, player.UserId)
		elseif reason then
			Remotes.SparNotice:FireClient(player, reason)
		end
	else
		Spar.decline(player)
	end
end)

Remotes.EndSpar.OnServerEvent:Connect(function(player: Player)
	Spar.forfeit(player)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	Spar.playerLeaving(player)
end)
