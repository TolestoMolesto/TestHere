-- Server entry for the Race Roller UI. Wires the roll/pick remotes (RollRace does the real work) and
-- assembles the read-only GetRollState the panel pulls on open. Everything is re-validated here --
-- the client only ever sends a confirm flag or a race name. Rolling operates on the player's ACTIVE
-- slot (the character they're currently in); like the free join-time auto-roll, the new race applies
-- to the body on the next spawn. (Code redemption lives in its own system -- see Codes.luau / CodesServer.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GlobalRaceRegistry = require(ServerStorage.Modules.GlobalRaceRegistry)
local Manager = require(ServerStorage.Modules.Manager)
local RollRace = require(ServerStorage.Modules.RollRace)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

-- Re-publish the live Spins ("Rolls") attribute after any change so HUDs reading the character's
-- Currency folder update without a respawn (StatsManager seeds this attribute on spawn).
local function publishSpins(player: Player)
	local shared = Manager.getShared(player)
	local character = player.Character
	if not shared or not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local currency = humanoid:FindFirstChild("Currency")
	if currency then
		currency:SetAttribute("Spins", shared.Spins)
	end
end

-- Read-only snapshot the panel renders from on open.
local function buildState(player: Player)
	local profile = Manager.getProfile(player)
	if not profile then
		return nil
	end
	local data = profile.Data
	local shared = data.Shared
	local idx = data.ActiveSlot
	local slot = data.Slots[idx]
	if not slot then
		return nil
	end

	local unlocked = RollRace.unlockedBasics(player)
	local pity = shared.GlobalPity

	return {
		slotIndex = idx,
		race = slot.Race,
		name = slot.Name,
		isPendingGlobal = RollRace.isGlobalRace(slot.Race),
		hasGlobal = RollRace.hasGlobal(player, idx),
		spins = shared.Spins,
		rollCount = shared.RollCount,
		pity = pity,
		pityGuarantee = RollRace.PITY_GUARANTEE,
		globalChance = RollRace.globalChance(pity),
		uniformOdds = if #unlocked > 0 then 1 / #unlocked else 0,
		basics = RollRace.allBasics(player), -- { { name, unlocked }, ... } -- collection + reels + targets
		globalNames = RollRace.globalRaces(),
		globals = GlobalRaceRegistry.availability(),
	}
end

Remotes.GetRollState.OnServerInvoke = function(player: Player)
	return buildState(player)
end

Remotes.RollSlot.OnServerInvoke = function(player: Player, confirmed: any)
	local profile = Manager.getProfile(player)
	if not profile then
		return { ok = false, error = "no_profile" }
	end
	local idx = profile.Data.ActiveSlot
	local race, err = RollRace.reroll(player, idx, confirmed == true)
	if not race then
		if err == "needs_confirmation" then
			return { ok = false, needsConfirmation = true }
		elseif err == "Not enough spins" then
			return { ok = false, error = "no_spins" }
		end
		return { ok = false, error = err or "failed" }
	end
	publishSpins(player)
	local shared = profile.Data.Shared
	return {
		ok = true,
		race = race,
		isPendingGlobal = RollRace.isGlobalRace(race),
		spins = shared.Spins,
		rollCount = shared.RollCount,
		pity = shared.GlobalPity,
		globalChance = RollRace.globalChance(shared.GlobalPity),
		globals = GlobalRaceRegistry.availability(),
	}
end

Remotes.PickRace.OnServerInvoke = function(player: Player, raceName: any)
	if typeof(raceName) ~= "string" then
		return { ok = false, error = "bad_race" }
	end
	local profile = Manager.getProfile(player)
	if not profile then
		return { ok = false, error = "no_profile" }
	end
	local idx = profile.Data.ActiveSlot
	local ok, reason = RollRace.pickRace(player, idx, raceName)
	if not ok then
		return { ok = false, error = reason }
	end
	local slot = profile.Data.Slots[idx]
	return {
		ok = true,
		race = slot and slot.Race,
		globals = GlobalRaceRegistry.availability(),
	}
end
