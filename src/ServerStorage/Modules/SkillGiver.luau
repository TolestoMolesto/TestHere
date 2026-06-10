--!strict
-- Unlocks Skills (the offensive 1-5 bucket) onto a slot as its BattlePower grows -- the rewrite of
-- the old SkillGiver's BP gates for the slot data model. Unlocked skills live in slot.UnlockedSkills
-- (per slot, since each slot is effectively its own character). Equipping unlocked skills into
-- slot.SkillLoadout is a separate concern (SkillServer + the loadout UI).
--
-- NOTE: the legacy SkillGiver also handled forms/techniques, the LSSJ awakening, and rare-passive
-- rolls. Forms/techniques are now FormConfig's job; the rolls are a separate system. This module
-- ONLY grants the offensive Skills defined in SkillConfig.

local ServerStorage = game:GetService("ServerStorage")

local Manager = require(ServerStorage.Modules.Manager)
local SkillConfig = require(ServerStorage.Modules.SkillConfig)

local SkillGiver = {}

-- Best available BattlePower for the active slot: the live character attribute (set by StatsManager)
-- when present, else the persisted slot value.
local function currentBP(player: Player, slot: any): number
	local persisted = (slot.BattlePower :: number?) or 0
	local character = player.Character
	if character then
		local live = (character:GetAttribute("BaseBattlePower") :: number?)
			or character:GetAttribute("BattlePower") :: number?
		if live then
			return math.max(persisted, live)
		end
	end
	return persisted
end

-- Grants a single skill id to the player's active slot (no BP check). Returns true if newly granted.
function SkillGiver.grant(player: Player, skillId: string): boolean
	if not SkillConfig.get(skillId) then
		return false
	end
	local slot = Manager.getActiveSlot(player)
	if not slot then
		return false
	end
	if not slot.UnlockedSkills then
		slot.UnlockedSkills = {}
	end
	if slot.UnlockedSkills[skillId] then
		return false
	end
	slot.UnlockedSkills[skillId] = true
	return true
end

-- Unlocks every race-eligible skill whose unlockBP the active slot has reached. Idempotent -- safe
-- to call on spawn and whenever BattlePower changes. Returns the list of newly unlocked skill ids.
function SkillGiver.check(player: Player): { string }
	local slot = Manager.getActiveSlot(player)
	if not slot then
		return {}
	end
	if not slot.UnlockedSkills then
		slot.UnlockedSkills = {}
	end

	local bp = currentBP(player, slot)
	local race = slot.Race
	local granted: { string } = {}

	for id, def in SkillConfig.all() do
		if slot.UnlockedSkills[id] then
			continue
		end
		if def.race ~= "Any" and def.race ~= race then
			continue
		end
		if bp >= def.unlockBP then
			slot.UnlockedSkills[id] = true
			table.insert(granted, id)
		end
	end

	return granted
end

return SkillGiver
