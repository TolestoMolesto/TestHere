local ServerStorage = game:GetService("ServerStorage")

local Manager = require(ServerStorage.Modules.Manager)
local CombatState = require(ServerStorage.Modules.CombatState)
local FormOverlay = require(ServerStorage.Modules.FormOverlay)
local PlayerRaceBuilder = require(ServerStorage.Modules.PlayerRaceBuilder)
local RollRace = require(ServerStorage.Modules.RollRace)
local StateBinders = require(ServerStorage.Modules.StateBinders)

local CATEGORIES = { "Identity", "Stats", "Currency", "Appearance" }

type Folders = { [string]: Folder }

local StatsManager = {}

local function createCategories(humanoid: Humanoid): Folders
	-- Created unconditionally; a name collision means another script is pre-creating folders (Roblox auto-renames -- real bug).
	local folders: Folders = {}
	for _, name in CATEGORIES do
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = humanoid
		folders[name] = f
	end
	return folders
end

local function getCategories(humanoid: Humanoid): Folders
	local folders: Folders = {}
	for _, name in CATEGORIES do
		local f = humanoid:FindFirstChild(name)
		assert(f and f:IsA("Folder"), `Humanoid.{name} missing -- StatsManager.bind must run on spawn before refresh`)
		folders[name] = f
	end
	return folders
end

-- TypeReduction = Raw / (Raw + RESIST_K)
local RESIST_K = 80000
-- AllDamageReduction/Dodge softcap: Raw / (Raw + CURVE_K); 50% midpoint = CURVE_K raw.
local CURVE_K = 1000

local BP_WEIGHTS = {
	Strength = 1,
	Endurance = 1,
	Speed = 1,
	BattleExperience = 1,
	KiControl = 1,
}

-- Final = (Base + Flat + All.Flat) * (1 + Add + All.Add) * Multi * All.Multi
local function computeFinal(stat: any, all: any): number
	return (stat.Base + stat.Flat + all.Flat) * (1 + stat.Add + all.Add) * stat.Multi * all.Multi
end

-- Damage, Dodge, AllDamageReduction are NOT affected by All bonuses.
local function computeFinalNoAll(stat: any): number
	return (stat.Base + stat.Flat) * (1 + stat.Add) * stat.Multi
end

-- === Core-stat -> combat-stat wiring ================================================
-- Each core stat feeds a specific combat stat through a soft cap:
--     wire(stat, cap) = cap * stat / (stat + WIRE_KNEE)
-- It half-maxes at WIRE_KNEE (aligned with Train's earning soft cap) and asymptotes to `cap`.
-- This is the "compressed power" lever behind the casual-vs-hardcore goal: because EVERY raw
-- contribution is bounded, combat power asymptotes even as BattlePower runs to the millions, so a
-- maxed grinder stays only a small multiple of a competitive casual. BattlePower itself is left as
-- the UNBOUNDED prestige number -- it no longer feeds raw power; the caps below do. Builds diverge
-- from WHERE the points go (each capped stat is its own axis), not from runaway scaling of one.
local WIRE_KNEE = 5000
local function wire(stat: number, cap: number): number
	return cap * stat / (stat + WIRE_KNEE)
end

-- Caps are starting values leaning toward compression (a ~2x maxed-vs-casual gap). They're the
-- whole balance surface for divergence; tune against fight pace (and each move's base damage).
local W = {
	HealthFromBP = 1500, -- universal HP floor (BP >> knee => ~flat: everyone gets most of it)
	HealthFromEnd = 1800, -- Endurance's HP specialty, stacked on top
	KiFromKiControl = 900, -- KiControl -> MaxKi headroom
	PhysDmgFromStr = 150, -- Strength -> bonus PhysicalDamage
	KiDmgFromKiControl = 150, -- KiControl -> bonus KiDamage
	DamageFromBxp = 60, -- BattleExperience -> bonus universal Damage
	ResistFromBP = 3000, -- universal resistance floor, raw/pre-curve (replaces the old bp*0.05)
	ResistFromEnd = 12000, -- Endurance -> raw Physical + Ki resistance
	DodgeFromSpd = 250, -- Speed -> raw Dodge (the /(+CURVE_K) curve still caps the %)
	AdrFromBxp = 180, -- BattleExperience -> raw AllDamageReduction
	AttackSpeedFromSpd = 0.5, -- Speed -> attack-animation speed bonus (on the 1.0 base => up to ~1.5x maxed)
}
-- ====================================================================================

local function writeValues(folders: Folders, slot: any, shared: any)
	folders.Identity:SetAttribute("Name", slot.Name)
	folders.Identity:SetAttribute("Race", slot.Race)
	folders.Currency:SetAttribute("Spins", shared.Spins)

	local all = slot.All
	local str = computeFinal(slot.Strength, all)
	local end_ = computeFinal(slot.Endurance, all)
	local spd = computeFinal(slot.Speed, all)
	local bxp = computeFinal(slot.BattleExperience, all)
	local ki = computeFinal(slot.KiControl, all)
	local phyr = computeFinal(slot.PhysicalResistance, all)
	local kir = computeFinal(slot.KiResistance, all)

	-- BattlePower is the prestige headline: the raw sum of the five core stats, unbounded. It no
	-- longer feeds raw combat power -- the wire() caps below do -- so the number can climb forever
	-- without letting a grinder outscale a casual.
	local bp = (str * BP_WEIGHTS.Strength)
		+ (end_ * BP_WEIGHTS.Endurance)
		+ (spd * BP_WEIGHTS.Speed)
		+ (bxp * BP_WEIGHTS.BattleExperience)
		+ (ki * BP_WEIGHTS.KiControl)
	bp = math.max(1, bp)
	slot.BattlePower = bp

	-- Offense: each stat adds a soft-capped flat bonus on top of its own race/form layers.
	local dmg = computeFinalNoAll(slot.Damage) + wire(bxp, W.DamageFromBxp)
	local physdmg = computeFinalNoAll(slot.PhysicalDamage) + wire(str, W.PhysDmgFromStr)
	local kidmg = computeFinalNoAll(slot.KiDamage) + wire(ki, W.KiDmgFromKiControl)

	-- Resistance: a near-flat universal floor from BP + Endurance's specialty; then Raw / (Raw + 80,000).
	local resistFloor = wire(bp, W.ResistFromBP)
	local effPhyr = phyr + resistFloor + wire(end_, W.ResistFromEnd)
	local effKir = kir + resistFloor + wire(end_, W.ResistFromEnd)
	local phyrPct = effPhyr / (effPhyr + RESIST_K)
	local kirPct = effKir / (effKir + RESIST_K)

	-- Dodge (Speed) and AllDamageReduction (BattleExperience): wire() the raw, then Raw / (Raw + CURVE_K).
	local rawAdr = computeFinalNoAll(slot.AllDamageReduction) + wire(bxp, W.AdrFromBxp)
	local rawDdg = computeFinalNoAll(slot.Dodge) + wire(spd, W.DodgeFromSpd)
	local adrPct = rawAdr / (rawAdr + CURVE_K)
	local ddgPct = rawDdg / (rawDdg + CURVE_K)

	-- Health: a near-flat universal floor from BP (BP >> knee) + Endurance's specialty on top.
	local healthBase = 1000 + wire(bp, W.HealthFromBP) + wire(end_, W.HealthFromEnd)
	local maxHealth = math.floor(
		(healthBase + slot.Health.Flat + all.Flat) * (1 + slot.Health.Add + all.Add) * slot.Health.Multi * all.Multi
	)

	-- Ki base 100 + KiControl headroom; Stamina base 100.
	local kiBase = 100 + wire(ki, W.KiFromKiControl)
	local maxKi =
		math.floor((kiBase + slot.Ki.Flat + all.Flat) * (1 + slot.Ki.Add + all.Add) * slot.Ki.Multi * all.Multi)
	local maxStamina = math.floor(
		(100 + slot.Stamina.Flat + all.Flat) * (1 + slot.Stamina.Add + all.Add) * slot.Stamina.Multi * all.Multi
	)

	folders.Stats:SetAttribute("BattlePower", bp)
	-- Plain meta numbers carried straight from the slot (HUD reads them off Humanoid.Stats).
	folders.Stats:SetAttribute("Lives", slot.Lives)
	folders.Stats:SetAttribute("Longevity", slot.Longevity)
	folders.Stats:SetAttribute("Strength", str)
	folders.Stats:SetAttribute("Endurance", end_)
	folders.Stats:SetAttribute("Speed", spd)
	folders.Stats:SetAttribute("AttackSpeed", wire(spd, W.AttackSpeedFromSpd))
	folders.Stats:SetAttribute("BattleExperience", bxp)
	folders.Stats:SetAttribute("KiControl", ki)
	folders.Stats:SetAttribute("PhysicalResistance", phyr)
	folders.Stats:SetAttribute("PhysicalResistancePct", phyrPct)
	folders.Stats:SetAttribute("KiResistance", kir)
	folders.Stats:SetAttribute("KiResistancePct", kirPct)
	folders.Stats:SetAttribute("Damage", dmg)
	folders.Stats:SetAttribute("PhysicalDamage", physdmg)
	folders.Stats:SetAttribute("KiDamage", kidmg)
	folders.Stats:SetAttribute("AllDamageReduction", adrPct)
	folders.Stats:SetAttribute("Dodge", ddgPct)
	folders.Stats:SetAttribute("MaxHealth", maxHealth)
	folders.Stats:SetAttribute("MaxKi", maxKi)
	folders.Stats:SetAttribute("MaxStamina", maxStamina)

	folders.Appearance:SetAttribute("Gender", slot.Gender)
	folders.Appearance:SetAttribute("Age", slot.Age)
	folders.Appearance:SetAttribute("Height", slot.Height)
	folders.Appearance:SetAttribute("Hair", slot.Hair)
	folders.Appearance:SetAttribute("HairColorR", slot.HairColor.R)
	folders.Appearance:SetAttribute("HairColorG", slot.HairColor.G)
	folders.Appearance:SetAttribute("HairColorB", slot.HairColor.B)
	folders.Appearance:SetAttribute("BodyColorR", slot.BodyColor.R)
	folders.Appearance:SetAttribute("BodyColorG", slot.BodyColor.G)
	folders.Appearance:SetAttribute("BodyColorB", slot.BodyColor.B)
	folders.Appearance:SetAttribute("KiColorR", slot.KiColor.R)
	folders.Appearance:SetAttribute("KiColorG", slot.KiColor.G)
	folders.Appearance:SetAttribute("KiColorB", slot.KiColor.B)
	folders.Appearance:SetAttribute("Eyebrows", slot.Eyebrows)
	folders.Appearance:SetAttribute("Eyes", slot.Eyes)
	folders.Appearance:SetAttribute("EyeColor", slot.EyeColor)
	folders.Appearance:SetAttribute("Nose", slot.Nose)
	folders.Appearance:SetAttribute("Mouth", slot.Mouth)
	folders.Appearance:SetAttribute("BodyDecal", slot.BodyDecal)
	folders.Appearance:SetAttribute("ClothingOutfit", slot.ClothingOutfit)
	folders.Appearance:SetAttribute("Outfit", slot.Outfit)
	folders.Appearance:SetAttribute("Shirt", slot.Shirt)
	folders.Appearance:SetAttribute("Pants", slot.Pants)
	folders.Appearance:SetAttribute("ScouterEquipped", slot.ScouterEquipped)
end

local function applySpawnState(character: Model, humanoid: Humanoid, folders: Folders): ()
	local maxHealth = folders.Stats:GetAttribute("MaxHealth") :: number
	local maxKi = folders.Stats:GetAttribute("MaxKi") :: number
	local maxStamina = folders.Stats:GetAttribute("MaxStamina") :: number

	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth

	character:SetAttribute("MaxHealth", maxHealth)
	character:SetAttribute("MaxKi", maxKi)
	character:SetAttribute("MaxStamina", maxStamina)
	character:SetAttribute("AttackSpeed", folders.Stats:GetAttribute("AttackSpeed"))
	character:SetAttribute("Ki", maxKi)
	character:SetAttribute("Stamina", maxStamina)

	CombatState.init(character)

	StateBinders.bind(character)
end

function StatsManager.refresh(player: Player, opts: { preserveHealth: boolean? }?)
	local slot = Manager.getActiveSlot(player)
	local shared = Manager.getShared(player)
	if not slot or not shared or not player.Character then
		return
	end
	-- Fold in the active transformation (if any) without mutating the saved slot.
	slot = FormOverlay.apply(player.Character, slot)
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local cats = getCategories(humanoid)
		writeValues(cats, slot, shared)

		local maxHealth = cats.Stats:GetAttribute("MaxHealth") :: number
		local maxKi = cats.Stats:GetAttribute("MaxKi") :: number
		local maxStamina = cats.Stats:GetAttribute("MaxStamina") :: number

		humanoid.MaxHealth = maxHealth
		-- preserveHealth keeps current HP (clamped down) so transforms heal the MaxHealth
		-- delta themselves instead of full-healing on every recompute.
		if opts and opts.preserveHealth then
			humanoid.Health = math.min(humanoid.Health, maxHealth)
		else
			humanoid.Health = maxHealth
		end

		local character = player.Character :: Model
		character:SetAttribute("MaxHealth", maxHealth)
		character:SetAttribute("MaxKi", maxKi)
		character:SetAttribute("MaxStamina", maxStamina)
		character:SetAttribute("AttackSpeed", cats.Stats:GetAttribute("AttackSpeed"))

		-- Only clamp down; never raise -- runtime systems own the current value.
		local curKi = character:GetAttribute("Ki") :: number?
		local curStam = character:GetAttribute("Stamina") :: number?
		if curKi then
			character:SetAttribute("Ki", math.min(curKi, maxKi))
		end
		if curStam then
			character:SetAttribute("Stamina", math.min(curStam, maxStamina))
		end
	end
end

function StatsManager.bind(player: Player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 5)
		if not humanoid or not humanoid:IsA("Humanoid") then
			return
		end
		local folders = createCategories(humanoid)
		local slot = Manager.getActiveSlot(player)
		local shared = Manager.getShared(player)
		if slot and shared then
			writeValues(folders, slot, shared)
			PlayerRaceBuilder.buildFromSlot(character, slot)

			local profile = Manager.getProfile(player)
			if profile then
				local awarded = RollRace.checkLSSJ(player, profile.Data.ActiveSlot)
				if awarded then
					writeValues(folders, slot, shared)
					PlayerRaceBuilder.buildFromSlot(character, slot)
				end
			end

			applySpawnState(character, humanoid, folders)
		end
	end)
end

-- slotData must match SlotData layout from TemplateData.
function StatsManager.bindNPC(character: Model, slotData: any)
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	local folders = createCategories(humanoid)
	local dummyShared = { Spins = 0 }
	writeValues(folders, slotData, dummyShared)
	PlayerRaceBuilder.buildFromSlot(character, slotData)
	applySpawnState(character, humanoid, folders)
end

return StatsManager
