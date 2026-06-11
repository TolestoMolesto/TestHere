--!strict
-- Kai-only weight granting: a player whose ACTIVE slot holds the Kai global race may equip training
-- weights on members of their party, up to their own gravity mastery (a Kai at 10x gravity hands out up
-- to 10-ton weights; 0.25 floor). Lets a strong friend train a weaker one who lacks good weights of
-- their own. Server-authoritative -- the Party panel's Gravity tab only asks; every grant is validated
-- here: caller must be a Kai, target must be in the caller's party, tonnage clamped to [0.25, mastery].

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Manager = require(ServerStorage.Modules.Manager)
local PartyState = require(ServerStorage.Modules.PartyState)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Weights = require(ServerStorage.Modules.Weights)

-- The active slot holds the Kai global when Shared.GlobalRaces.Kai points at the active slot index
-- (mirrors RollRace's ownership record). 0 = no holder.
local function isActiveKai(player: Player): boolean
	local shared = Manager.getShared(player)
	local profile = Manager.getProfile(player)
	if not shared or not profile then
		return false
	end
	local kaiSlot = shared.GlobalRaces.Kai
	return kaiSlot ~= 0 and kaiSlot == profile.Data.ActiveSlot
end

-- A Kai's grant ceiling is their trained gravity mastery; 0 means "not a Kai" (cannot grant at all).
local function grantCap(player: Player): number
	if not isActiveKai(player) then
		return 0
	end
	local slot = Manager.getActiveSlot(player)
	if not slot then
		return 0
	end
	return math.max(slot.GravityMastery or 1, Weights.MIN_TONNAGE)
end

Remotes.GetWeightGrant.OnServerInvoke = function(player: Player): { allowed: boolean, cap: number }
	local cap = grantCap(player)
	return { allowed = cap > 0, cap = cap }
end

Remotes.SetMemberWeight.OnServerEvent:Connect(function(player: Player, targetValue: any, tonnageValue: any)
	local cap = grantCap(player)
	if cap <= 0 then
		return -- not a Kai
	end
	if typeof(targetValue) ~= "Instance" or not targetValue:IsA("Player") then
		return
	end
	if typeof(tonnageValue) ~= "number" or tonnageValue ~= tonnageValue then
		return -- non-number / NaN
	end
	local target = targetValue :: Player

	-- Self is always allowed (a Kai can weight their own character); otherwise the target must share the
	-- caller's party.
	if target ~= player then
		local party = PartyState.getParty(player)
		if not party or PartyState.getParty(target) ~= party then
			return
		end
	end

	local character = target.Character
	if not character then
		return
	end

	if tonnageValue <= 0 then
		Weights.apply(character, 0) -- remove
	else
		Weights.apply(character, math.clamp(tonnageValue, Weights.MIN_TONNAGE, cap))
	end
end)
