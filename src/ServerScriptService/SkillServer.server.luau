-- Server entry for the Skill bucket (keys 1-5): runs the BattlePower unlock pass on spawn / whenever
-- BattlePower changes, and serves the loadout UI (a client-safe catalogue + the current 1-5 loadout,
-- plus equip writes). Skill *casting* is wired in CombatServer (the "Skill" action) -> SkillState.
-- Balance numbers from SkillConfig never leave the server; the catalogue here is sanitised.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Describe = require(ReplicatedStorage.Modules.Describe)
local Manager = require(ServerStorage.Modules.Manager)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local SkillConfig = require(ServerStorage.Modules.SkillConfig)
local SkillGiver = require(ServerStorage.Modules.SkillGiver)

local LOADOUT_SIZE = 5

-- Sanitised, client-safe view of a slot's skills for the loadout UI: id + display + category +
-- unlocked flag, plus the current 1-5 loadout. No balance numbers.
local function buildView(player: Player)
	local slot = Manager.getActiveSlot(player)
	if not slot then
		return nil
	end
	local unlocked = slot.UnlockedSkills or {}
	local catalogue = {}
	for _, entry in SkillConfig.list() do
		local def = entry.def
		-- Auto-append Ki Cost (when > 0) so it can't drift from the real number; Cooldown is appended
		-- by Describe. Physical skills (kiCost 0) state "Cost: Stamina" in their own effect lines.
		local effects = table.clone(def.description.effects)
		if def.kiCost > 0 then
			table.insert(effects, `Ki Cost: {def.kiCost}`)
		end
		table.insert(catalogue, {
			id = entry.id,
			displayName = def.displayName,
			category = def.category,
			type = "Skill", -- the unified inventory sort key (shared with Forms/Items)
			cooldown = def.cooldown, -- player-facing; lets the HUD render the cooldown sweep
			unlocked = unlocked[entry.id] == true,
			description = Describe.format({
				type = "Skill",
				note = def.description.note,
				summary = def.description.summary,
				effects = effects,
				cooldown = def.cooldown,
			}),
		})
	end
	local loadout = {}
	for i = 1, LOADOUT_SIZE do
		loadout[i] = (slot.SkillLoadout and slot.SkillLoadout[i]) or ""
	end
	return { catalogue = catalogue, loadout = loadout }
end

-- Mirrors the equipped skill ids onto the character as SkillSlot1..5 attributes, so other systems
-- (and the client) can read the live loadout without the profile.
local function syncLoadoutAttributes(player: Player, slot: any)
	local character = player.Character
	if not character then
		return
	end
	for i = 1, LOADOUT_SIZE do
		character:SetAttribute(`SkillSlot{i}`, (slot.SkillLoadout and slot.SkillLoadout[i]) or "")
	end
end

Remotes.GetSkillLoadout.OnServerInvoke = function(player: Player)
	return buildView(player)
end

Remotes.SetSkillLoadout.OnServerEvent:Connect(function(player: Player, index: any, skillId: any)
	if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > LOADOUT_SIZE then
		return
	end
	local slot = Manager.getActiveSlot(player)
	if not slot then
		return
	end
	if not slot.SkillLoadout then
		slot.SkillLoadout = { "", "", "", "", "" }
	end

	if skillId == "" or skillId == nil then
		-- Clear the slot.
		slot.SkillLoadout[index] = ""
	elseif
		type(skillId) == "string"
		and SkillConfig.get(skillId) ~= nil
		and slot.UnlockedSkills ~= nil
		and slot.UnlockedSkills[skillId] == true
	then
		-- A skill can only occupy one slot: clear any existing copy before equipping here.
		for i = 1, LOADOUT_SIZE do
			if slot.SkillLoadout[i] == skillId then
				slot.SkillLoadout[i] = ""
			end
		end
		slot.SkillLoadout[index] = skillId
	else
		return -- unknown or not-unlocked skill: ignore
	end

	syncLoadoutAttributes(player, slot)
end)

-- First-time convenience: if the loadout is entirely empty, equip the first few unlocked skills so
-- keys 1-5 work before the player ever opens the loadout UI. Only acts when every slot is blank, so
-- it never fights a player's choices.
local function autoEquipDefaults(slot: any)
	if not slot.SkillLoadout then
		slot.SkillLoadout = { "", "", "", "", "" }
	end
	for i = 1, LOADOUT_SIZE do
		if slot.SkillLoadout[i] ~= nil and slot.SkillLoadout[i] ~= "" then
			return -- already has something equipped; leave it alone
		end
	end
	local unlocked = slot.UnlockedSkills or {}
	local filled = 0
	for _, entry in SkillConfig.list() do
		if unlocked[entry.id] then
			filled += 1
			slot.SkillLoadout[filled] = entry.id
			if filled >= LOADOUT_SIZE then
				break
			end
		end
	end
end

-- Run an unlock pass once the character (and its BattlePower) exists, and again whenever BP changes
-- so newly-earned power unlocks promptly. Idempotent.
local function bindCharacter(player: Player, character: Model)
	task.defer(function()
		SkillGiver.check(player)
		local slot = Manager.getActiveSlot(player)
		if slot then
			autoEquipDefaults(slot)
			syncLoadoutAttributes(player, slot)
		end
	end)
	character:GetAttributeChangedSignal("BattlePower"):Connect(function()
		SkillGiver.check(player)
	end)
end

local function bindPlayer(player: Player)
	if player.Character then
		bindCharacter(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		bindCharacter(player, character)
	end)
end

Players.PlayerAdded:Connect(bindPlayer)
for _, player in Players:GetPlayers() do
	bindPlayer(player)
end
