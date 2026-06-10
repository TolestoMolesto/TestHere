--!strict
-- Ability controller for transformations (Forms) and Techniques. Both work identically; they
-- differ only in bucket: a Form lives on the `ActiveForm` attribute, a Technique on
-- `ActiveTechnique`. One of each can be active at once and they stack (e.g. SSJ + Kaioken).
-- Owns activate/deactivate/toggle, the per-second drain + mastery-XP loop, the duration expire
-- timer, and per-ability cooldowns. The active-ability attributes are the single source of
-- truth (read by FormOverlay for stats and FormFX for auras); no buff is written to the slot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Damage = require(ServerStorage.Modules.Damage)
local Describe = require(ReplicatedStorage.Modules.Describe)
local FormConfig = require(ServerStorage.Modules.FormConfig)
local Manager = require(ServerStorage.Modules.Manager)
local Mastery = require(ServerStorage.Modules.Mastery)
local StatsManager = require(ServerStorage.Modules.StatsManager)

local MAX_LEVEL = FormConfig.Config.MaxMasteryLevel
-- A draining technique can't drop you below this; it forces a deactivate instead of a knockout.
local HEALTH_FLOOR = 1

local BUCKET_ATTR: { [string]: string } = {
	Form = "ActiveForm",
	Technique = "ActiveTechnique",
}

-- Per-(character, bucket) generation guard: each activation bumps its bucket's count; loops and
-- timers retire themselves when superseded. Keyed per-bucket so toggling a Technique never
-- cancels an active Form's loop (and vice-versa).
local generation = setmetatable({} :: { [Model]: { [string]: number } }, { __mode = "k" })

local FormState = {}

local function getPlayer(character: Model): Player?
	return Players:GetPlayerFromCharacter(character)
end

local function getRace(character: Model): string?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local identity = humanoid and humanoid:FindFirstChild("Identity")
	return if identity then identity:GetAttribute("Race") :: string? else nil
end

local function cooldownAttr(abilityName: string): string
	return `Ability_{abilityName}_ReadyAt`
end

-- When the active form expires (synced server clock). 0 = active but permanent (max mastery, no
-- timer). Cleared on deactivate. Read by the client HUD to show the active-duration countdown.
local function expiresAttr(abilityName: string): string
	return `Ability_{abilityName}_ExpiresAt`
end

local function bumpGen(character: Model, bucket: string): number
	local g = generation[character]
	if not g then
		g = {}
		generation[character] = g
	end
	g[bucket] = (g[bucket] or 0) + 1
	return g[bucket]
end

local function genOf(character: Model, bucket: string): number
	local g = generation[character]
	return if g then (g[bucket] or 0) else 0
end

local function canTransform(character: Model): boolean
	if not character.Parent then
		return false
	end
	return not (character:GetAttribute("ToggleRagdoll") or character:GetAttribute("InCustomization"))
end

local function deactivate(character: Model, player: Player, abilityName: string, _reason: string): ()
	local def = FormConfig.get(abilityName)
	if not def then
		return
	end
	local bucket = def.kind

	-- Retire the sustain loop / expire timer tied to this bucket's current activation.
	bumpGen(character, bucket)

	character:SetAttribute(BUCKET_ATTR[bucket], "")
	character:SetAttribute(expiresAttr(abilityName), nil) -- no longer active; drop the duration timer
	-- Recompute without this ability's overlay; preserveHealth clamps HP down to the new max.
	StatsManager.refresh(player, { preserveHealth = true })

	if def.cooldown > 0 then
		character:SetAttribute(cooldownAttr(abilityName), workspace:GetServerTimeNow() + def.cooldown)
	end
end

local function startSustainLoop(
	character: Model,
	player: Player,
	slot: any,
	abilityName: string,
	def: FormConfig.FormDef,
	bucket: string,
	gen: number
): ()
	local activeAttr = BUCKET_ATTR[bucket]
	task.spawn(function()
		while character.Parent and genOf(character, bucket) == gen do
			task.wait(1)
			if genOf(character, bucket) ~= gen or character:GetAttribute(activeAttr) ~= abilityName then
				break
			end

			-- Passive mastery XP for time spent active.
			Mastery.addXP(slot, abilityName, FormConfig.Config.XpPerSecond)
			local scale = Mastery.drainScale(Mastery.getLevel(slot, abilityName))

			-- Per-resource drains (each ramps to zero at max level). Exhausting any forces a deactivate.
			local depleted = false

			local kiDrain = (def.baseKiDrain or 0) * scale
			if kiDrain > 0 then
				local ki = math.max(0, ((character:GetAttribute("Ki") :: number?) or 0) - kiDrain)
				character:SetAttribute("Ki", ki)
				if ki <= 0 then
					depleted = true
				end
			end

			local staminaDrain = (def.baseStaminaDrain or 0) * scale
			if staminaDrain > 0 then
				local stamina = math.max(0, ((character:GetAttribute("Stamina") :: number?) or 0) - staminaDrain)
				character:SetAttribute("Stamina", stamina)
				if stamina <= 0 then
					depleted = true
				end
			end

			local healthDrain = (def.baseHealthDrain or 0) * scale
			if healthDrain > 0 then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					-- Never drain into a knockout: bail out of the ability instead.
					if humanoid.Health - healthDrain <= HEALTH_FLOOR then
						depleted = true
					else
						humanoid.Health -= healthDrain
					end
				end
			end

			if depleted then
				deactivate(character, player, abilityName, "depleted")
				break
			end
		end
	end)
end

local function scheduleExpire(
	character: Model,
	player: Player,
	slot: any,
	abilityName: string,
	def: FormConfig.FormDef,
	bucket: string,
	gen: number
): ()
	local duration = Mastery.durationForLevel(def, Mastery.getLevel(slot, abilityName))
	-- Publish the expiry for the HUD: a real timestamp, or 0 for "permanent" (max mastery).
	character:SetAttribute(
		expiresAttr(abilityName),
		if duration == math.huge then 0 else workspace:GetServerTimeNow() + duration
	)
	if duration == math.huge then
		return -- max level: stays on until toggled off.
	end
	local activeAttr = BUCKET_ATTR[bucket]
	task.delay(duration, function()
		if genOf(character, bucket) ~= gen or character:GetAttribute(activeAttr) ~= abilityName then
			return
		end
		-- If mastery reached max while active, it became permanent; don't expire it.
		if Mastery.getLevel(slot, abilityName) >= MAX_LEVEL then
			return
		end
		deactivate(character, player, abilityName, "expired")
	end)
end

local function activate(character: Model, player: Player, abilityName: string, def: FormConfig.FormDef): ()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local slot = Manager.getActiveSlot(player)
	if not slot then
		return
	end
	Mastery.ensure(slot, abilityName)
	local bucket = def.kind

	-- Capture pre-activation maxima so we heal / top up by the delta only.
	local oldMaxHealth = humanoid.MaxHealth
	local oldMaxKi = (character:GetAttribute("MaxKi") :: number?) or 0
	local oldMaxStamina = (character:GetAttribute("MaxStamina") :: number?) or 0
	local curKi = (character:GetAttribute("Ki") :: number?) or 0
	local curStamina = (character:GetAttribute("Stamina") :: number?) or 0

	-- The bucket attribute drives the stat overlay (FormOverlay) and the aura (FormFX).
	character:SetAttribute(BUCKET_ATTR[bucket], abilityName)
	StatsManager.refresh(player, { preserveHealth = true })

	-- Heal the MaxHealth delta and add the gained Ki/Stamina headroom to the current pools.
	Damage.heal(character, humanoid.MaxHealth - oldMaxHealth)
	local newMaxKi = (character:GetAttribute("MaxKi") :: number?) or 0
	local newMaxStamina = (character:GetAttribute("MaxStamina") :: number?) or 0
	character:SetAttribute("Ki", math.min(curKi + (newMaxKi - oldMaxKi), newMaxKi))
	character:SetAttribute("Stamina", math.min(curStamina + (newMaxStamina - oldMaxStamina), newMaxStamina))

	local gen = bumpGen(character, bucket)
	startSustainLoop(character, player, slot, abilityName, def, bucket, gen)
	scheduleExpire(character, player, slot, abilityName, def, bucket, gen)
end

-- Toggles `abilityName` on/off within its own bucket (Form or Technique), swapping out any
-- other ability in that same bucket. The other bucket is untouched, so a Form and a Technique
-- can be active at once. Subject to race / unlock / state / cooldown gates.
function FormState.toggle(character: Model, abilityName: string): ()
	local def = FormConfig.get(abilityName)
	if not def then
		return
	end
	local player = getPlayer(character)
	if not player or not canTransform(character) then
		return
	end
	if def.race ~= "Any" and getRace(character) ~= def.race then
		return
	end

	local bucket = def.kind
	local activeAttr = BUCKET_ATTR[bucket]
	local current = character:GetAttribute(activeAttr)
	if current == abilityName then
		deactivate(character, player, abilityName, "toggle")
		return
	end

	if def.unlockFlag then
		local shared = Manager.getShared(player)
		if not (shared and shared.Unlocks[def.unlockFlag]) then
			return
		end
	end

	local readyAt = character:GetAttribute(cooldownAttr(abilityName)) :: number?
	if readyAt and workspace:GetServerTimeNow() < readyAt then
		return
	end

	-- Swap within this bucket: drop the current ability (starting its cooldown) first.
	if type(current) == "string" and current ~= "" then
		deactivate(character, player, current, "swap")
	end

	activate(character, player, abilityName, def)
end

-- Client entry: the client sends a slot index for the 6-0 hotkey row (1 = key 6). We resolve it to
-- the ability equipped in that slot of the active slot's FormLoadout, so no ability data is shared
-- with the client. The selected ability's kind routes it to its bucket, so a form and a technique
-- on the same row still stack.
function FormState.toggleByIndex(character: Model, index: number): ()
	local player = getPlayer(character)
	if not player then
		return
	end
	local slot = Manager.getActiveSlot(player)
	local loadout = slot and slot.FormLoadout
	local formId = (loadout and loadout[index]) or ""
	if formId ~= "" then
		FormState.toggle(character, formId)
	end
end

-- Build the player-facing tooltip for an ability: DERIVE the boost lines from the real stats/packs
-- (so the shown numbers can't drift), append any authored flavor effects, then Duration (base
-- mastery) + Cooldown. Mirrors the Type/Note/summary/Effects layout shared with Skills + Items.
local function formDescription(def: FormConfig.FormDef): string
	local effects: { string } = {}
	local core = def.stats.Strength
	local amount = if core then (core.Multi or 0) else 0
	table.insert(effects, `Battle Power Boost: ×{1 + amount}`)
	if def.kiPack and def.kiPack > 0 then
		table.insert(effects, `Ki Boost: +{math.round(def.kiPack * 100)}%`)
	end
	if def.staminaPack and def.staminaPack > 0 then
		table.insert(effects, `Stamina Boost: +{math.round(def.staminaPack * 100)}%`)
	end
	if def.healthPack and def.healthPack > 0 then
		table.insert(effects, `Health Boost: +{math.round(def.healthPack * 100)}%`)
	end
	if def.description.effects then
		for _, line in def.description.effects do
			table.insert(effects, line)
		end
	end
	return Describe.format({
		type = def.kind :: string,
		note = def.description.note,
		summary = def.description.summary,
		effects = effects,
		duration = def.baseDuration,
		cooldown = def.cooldown,
	})
end

-- The active slot's 6-0 ability ROW (slot index 1 = key 6), resolved through FormLoadout, for the
-- HUD's labels + tooltip. Always 5 entries; an empty slot is a sentinel with id = "". Only
-- player-facing fields leave the server; runtime state (active/cooldown/expiry) the HUD reads from
-- attributes. Mirrors toggleByIndex.
function FormState.getBar(
	character: Model
): { { id: string, displayName: string, kind: string, cooldown: number, description: string } }
	local out: { { id: string, displayName: string, kind: string, cooldown: number, description: string } } = {}
	local player = getPlayer(character)
	local slot = if player then Manager.getActiveSlot(player) else nil
	local loadout = slot and slot.FormLoadout
	for i = 1, 5 do
		local id = (loadout and loadout[i]) or ""
		local def = if id ~= "" then FormConfig.get(id) else nil
		if def then
			out[i] = {
				id = id,
				displayName = def.displayName,
				kind = def.kind :: string,
				cooldown = def.cooldown,
				description = formDescription(def),
			}
		else
			out[i] = { id = "", displayName = "", kind = "", cooldown = 0, description = "" }
		end
	end
	return out
end

-- Sanitised loadout view for the inventory's Skills tab (Forms section): the race's full forms/techs
-- catalogue (id/name/kind/cooldown/unlocked + the curated description) plus the active slot's current
-- 6-0 loadout (5 form ids, "" = empty). No balance numbers cross. Mirrors SkillServer's buildView.
type FormCatalogueEntry = {
	id: string,
	displayName: string,
	kind: string,
	cooldown: number,
	unlocked: boolean,
	description: string,
}
function FormState.getLoadoutView(character: Model): { catalogue: { FormCatalogueEntry }, loadout: { string } }
	local view = { catalogue = {} :: { FormCatalogueEntry }, loadout = { "", "", "", "", "" } }
	local player = getPlayer(character)
	if not player then
		return view
	end
	local race = getRace(character)
	if not race then
		return view
	end
	local shared = Manager.getShared(player)
	for _, entry in FormConfig.getRaceAbilities(race) do
		local def = entry.def
		local unlocked = true
		if def.unlockFlag then
			unlocked = shared ~= nil and shared.Unlocks[def.unlockFlag] == true
		end
		table.insert(view.catalogue, {
			id = entry.id,
			displayName = def.displayName,
			kind = def.kind :: string,
			cooldown = def.cooldown,
			unlocked = unlocked,
			description = formDescription(def),
		})
	end
	local slot = Manager.getActiveSlot(player)
	if slot and slot.FormLoadout then
		for i = 1, 5 do
			view.loadout[i] = slot.FormLoadout[i] or ""
		end
	end
	return view
end

-- Equip `formId` into 6-0 slot `index` (1-5) on the active slot, or clear it (""). Validates the
-- form belongs to the slot's race (or "Any") and is unlocked; enforces one form per slot. Mirrors
-- the Skill loadout writer (SkillServer.SetSkillLoadout).
function FormState.setLoadout(player: Player, index: number, formId: string): boolean
	if index < 1 or index > 5 then
		return false
	end
	local slot = Manager.getActiveSlot(player)
	if not slot then
		return false
	end
	if not slot.FormLoadout then
		slot.FormLoadout = { "", "", "", "", "" }
	end

	if formId == "" then
		slot.FormLoadout[index] = ""
		return true
	end

	local def = FormConfig.get(formId)
	if not def then
		return false
	end
	if def.race ~= "Any" and def.race ~= slot.Race then
		return false
	end
	if def.unlockFlag then
		local shared = Manager.getShared(player)
		if not (shared and shared.Unlocks[def.unlockFlag]) then
			return false
		end
	end

	-- One form per slot: drop any existing copy before equipping here.
	for i = 1, 5 do
		if slot.FormLoadout[i] == formId then
			slot.FormLoadout[i] = ""
		end
	end
	slot.FormLoadout[index] = formId
	return true
end

-- Reconcile the active slot's 6-0 loadout with the current race, on spawn:
--   * prune any equipped ability this race can't use (e.g. left over after a reroll), then
--   * if no race-specific Form remains, (re)build the default race line (keys 6-0 in order).
-- Idempotent for a stable race; preserves a player's arrangement as long as it still holds a race
-- form, while guaranteeing a freshly-rolled race's forms populate the bar.
function FormState.reconcileLoadout(slot: any, race: string): ()
	if not slot.FormLoadout then
		slot.FormLoadout = { "", "", "", "", "" }
	end
	local loadout = slot.FormLoadout
	-- Drop entries this race can't use.
	for i = 1, 5 do
		local id = loadout[i]
		if id ~= "" then
			local def = FormConfig.get(id)
			if not def or (def.race ~= "Any" and def.race ~= race) then
				loadout[i] = ""
			end
		end
	end
	-- Still holding a race-specific Form? If not (empty, or only race-agnostic techniques), default
	-- the whole row to the race line.
	local hasRaceForm = false
	for i = 1, 5 do
		local def = if loadout[i] ~= "" then FormConfig.get(loadout[i]) else nil
		if def and def.kind == "Form" and def.race == race then
			hasRaceForm = true
			break
		end
	end
	if not hasRaceForm then
		local abilities = FormConfig.getRaceAbilities(race)
		for i = 1, 5 do
			local entry = abilities[i]
			loadout[i] = if entry then entry.id else ""
		end
	end
end

-- Awards the combat-bonus mastery XP to every active ability; safe on every landed hit.
function FormState.awardCombatHit(character: Model): ()
	local player = getPlayer(character)
	if not player then
		return
	end
	local slot = Manager.getActiveSlot(player)
	if not slot then
		return
	end
	for _, attr in BUCKET_ATTR do
		local name = character:GetAttribute(attr)
		if type(name) == "string" and name ~= "" then
			Mastery.addXP(slot, name, FormConfig.Config.XpPerHit)
		end
	end
end

return FormState
