-- ─────────────────────────────────────────────
-- StatsManager.luau
-- Bridges profile data onto the player's Humanoid via category folders:
--
--   Humanoid
--     ├ Identity   attrs: Name, Race, Gender, ...
--     ├ Stats      attrs: Strength, Speed, ...        (TBD)
--     ├ Currency   attrs: Spins, Zeni, ...
--     └ Status     attrs: Stamina, CombatTag, Lives   (TBD)
--
-- Authoritative source is still the profile (and Shared). Folder
-- attributes are a replicated read-only view that only the server
-- writes. Combat / AI / UI all read through these folders, so player
-- and NPC humanoids share the exact same surface.
--
-- Usage:
--   StatsManager.bind(player)     -- once, after the profile is loaded
--   StatsManager.refresh(player)  -- after a server-side mutation
--                                    (slot switch, stat change, etc.)
-- ─────────────────────────────────────────────

local ServerStorage = game:GetService("ServerStorage")

local Manager           = require(ServerStorage.Modules.Manager)
local PlayerRaceBuilder = require(ServerStorage.Modules.PlayerRaceBuilder)
local RollRace          = require(ServerStorage.Modules.RollRace)

local CATEGORIES = { "Identity", "Stats", "Currency", "Combat", "Appearance" }

type Folders = { [string]: Folder }

-- Seeds all runtime combat flags into the Combat folder so they are
-- never nil when read by Knockback, LightAttack, HitStun, or any other system.
local function initRuntimeFlags(combat: Folder): ()
	-- Knockback state
	combat:SetAttribute("HitByKnockBack", false)
	combat:SetAttribute("CanRecover",    false)
	combat:SetAttribute("CanVanishTo",   false)
	-- Attack / stun state
	combat:SetAttribute("AttackCooldown",  false)
	combat:SetAttribute("Blocking",        false)
	combat:SetAttribute("HeavyCooldown",   false)
	combat:SetAttribute("Stunned",         false)
	combat:SetAttribute("ToggleRagdoll",   false)
	combat:SetAttribute("KiBlasting",      false)
	combat:SetAttribute("NoAttacking",     false)
	combat:SetAttribute("InCustomization", false)
	combat:SetAttribute("InSafeZone",      false)
	combat:SetAttribute("LastAttackTime",  0)
end

local StatsManager = {}

local function createCategories(humanoid: Humanoid): Folders
	-- Character is fresh on every spawn, so we create unconditionally.
	-- A name collision would mean another script is pre-creating one of
	-- these folders, which Roblox would auto-rename -- a real bug.
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
	-- refresh() runs after bind() created the folders. Missing folder =
	-- bind didn't run (or the character is being torn down) -- error
	-- loudly so we hear about it.
	local folders: Folders = {}
	for _, name in CATEGORIES do
		local f = humanoid:FindFirstChild(name)
		assert(f and f:IsA("Folder"), `Humanoid.{name} missing -- StatsManager.bind must run on spawn before refresh`)
		folders[name] = f
	end
	return folders
end

-- Resistance softcap constant.  TypeReduction = Raw / (Raw + RESIST_K)
local RESIST_K = 80000
-- Softcap constant for AllDamageReduction and Dodge.
-- Formula: Raw / (Raw + CURVE_K).  50% midpoint = CURVE_K raw.
local CURVE_K  = 1000

-- BattlePower contribution weight per final stat (tune to balance).
local BP_WEIGHTS = {
	Strength         = 1,
	Endurance        = 1,
	Speed            = 1,
	BattleExperience = 1,
	KiControl        = 1,
}

-- Final = (Base + Flat + All.Flat) x (1 + Add + All.Add) x Multi x All.Multi
local function computeFinal(stat: any, all: any): number
	return (stat.Base + stat.Flat + all.Flat)
		* (1 + stat.Add + all.Add)
		* stat.Multi
		* all.Multi
end

-- Stats NOT affected by All bonuses: Damage, Dodge, AllDamageReduction.
local function computeFinalNoAll(stat: any): number
	return (stat.Base + stat.Flat) * (1 + stat.Add) * stat.Multi
end

local function writeValues(folders: Folders, slot: any, shared: any)
	folders.Identity:SetAttribute("Name",  slot.Name)
	folders.Identity:SetAttribute("Race",  slot.Race)
	folders.Currency:SetAttribute("Spins", shared.Spins)

	local all  = slot.All
	local str  = computeFinal(slot.Strength,           all)
	local end_ = computeFinal(slot.Endurance,          all)
	local spd  = computeFinal(slot.Speed,              all)
	local bxp  = computeFinal(slot.BattleExperience,   all)
	local ki   = computeFinal(slot.KiControl,          all)
	local phyr = computeFinal(slot.PhysicalResistance, all)
	local kir  = computeFinal(slot.KiResistance,       all)
	local dmg      = computeFinalNoAll(slot.Damage)
	local physdmg  = computeFinalNoAll(slot.PhysicalDamage)
	local kidmg    = computeFinalNoAll(slot.KiDamage)

	-- BattlePower: weighted sum of final combat stats.
	-- Computed first so the BP-based resistance bonus can reference it.
	local bp = (str  * BP_WEIGHTS.Strength)
		+ (end_ * BP_WEIGHTS.Endurance)
		+ (spd  * BP_WEIGHTS.Speed)
		+ (bxp  * BP_WEIGHTS.BattleExperience)
		+ (ki   * BP_WEIGHTS.KiControl)
	bp = math.max(1, bp)
	slot.BattlePower = bp

	-- Effective resistance = raw stat + 5% of BP (passive floor).
	-- Raw / (Raw + 80,000)
	local effPhyr = phyr + bp * 0.05
	local effKir  = kir  + bp * 0.05
	local phyrPct = effPhyr / (effPhyr + RESIST_K)
	local kirPct  = effKir  / (effKir  + RESIST_K)

	-- AllDamageReduction and Dodge: raw stat -> softcapped %
	-- Formula: Raw / (Raw + CURVE_K)
	local rawAdr = computeFinalNoAll(slot.AllDamageReduction)
	local rawDdg = computeFinalNoAll(slot.Dodge)
	local adrPct = rawAdr / (rawAdr + CURVE_K)
	local ddgPct = rawDdg / (rawDdg + CURVE_K)

	-- Health: base = (BP * 0.05) + 1000, then modified by Health + All
	local healthBase = (bp * 0.05) + 1000
	local maxHealth  = math.floor(
		(healthBase + slot.Health.Flat + all.Flat)
		* (1 + slot.Health.Add + all.Add)
		* slot.Health.Multi
		* all.Multi
	)

	-- Ki and Stamina: fixed base of 100, modified by their bonuses + All
	local maxKi = math.floor(
		(100 + slot.Ki.Flat + all.Flat)
		* (1 + slot.Ki.Add + all.Add)
		* slot.Ki.Multi
		* all.Multi
	)
	local maxStamina = math.floor(
		(100 + slot.Stamina.Flat + all.Flat)
		* (1 + slot.Stamina.Add + all.Add)
		* slot.Stamina.Multi
		* all.Multi
	)

	folders.Stats:SetAttribute("BattlePower",           bp)
	folders.Stats:SetAttribute("Strength",              str)
	folders.Stats:SetAttribute("Endurance",             end_)
	folders.Stats:SetAttribute("Speed",                 spd)
	folders.Stats:SetAttribute("BattleExperience",      bxp)
	folders.Stats:SetAttribute("KiControl",             ki)
	folders.Stats:SetAttribute("PhysicalResistance",    phyr)
	folders.Stats:SetAttribute("PhysicalResistancePct", phyrPct)
	folders.Stats:SetAttribute("KiResistance",          kir)
	folders.Stats:SetAttribute("KiResistancePct",       kirPct)
	folders.Stats:SetAttribute("Damage",                dmg)
	folders.Stats:SetAttribute("PhysicalDamage",        physdmg)
	folders.Stats:SetAttribute("KiDamage",              kidmg)
	folders.Stats:SetAttribute("AllDamageReduction",    adrPct)
	folders.Stats:SetAttribute("Dodge",                 ddgPct)
	folders.Stats:SetAttribute("MaxHealth",             maxHealth)
	folders.Stats:SetAttribute("MaxKi",                 maxKi)
	folders.Stats:SetAttribute("MaxStamina",            maxStamina)

	-- Appearance
	folders.Appearance:SetAttribute("Gender",           slot.Gender)
	folders.Appearance:SetAttribute("Age",              slot.Age)
	folders.Appearance:SetAttribute("Height",           slot.Height)
	folders.Appearance:SetAttribute("Hair",             slot.Hair)
	folders.Appearance:SetAttribute("HairColorR",       slot.HairColor.R)
	folders.Appearance:SetAttribute("HairColorG",       slot.HairColor.G)
	folders.Appearance:SetAttribute("HairColorB",       slot.HairColor.B)
	folders.Appearance:SetAttribute("BodyColorR",       slot.BodyColor.R)
	folders.Appearance:SetAttribute("BodyColorG",       slot.BodyColor.G)
	folders.Appearance:SetAttribute("BodyColorB",       slot.BodyColor.B)
	folders.Appearance:SetAttribute("KiColorR",         slot.KiColor.R)
	folders.Appearance:SetAttribute("KiColorG",         slot.KiColor.G)
	folders.Appearance:SetAttribute("KiColorB",         slot.KiColor.B)
	folders.Appearance:SetAttribute("Eyebrows",         slot.Eyebrows)
	folders.Appearance:SetAttribute("Eyes",             slot.Eyes)
	folders.Appearance:SetAttribute("EyeColor",         slot.EyeColor)
	folders.Appearance:SetAttribute("Nose",             slot.Nose)
	folders.Appearance:SetAttribute("Mouth",            slot.Mouth)
	folders.Appearance:SetAttribute("BodyDecal",        slot.BodyDecal)
	folders.Appearance:SetAttribute("ClothingOutfit",   slot.ClothingOutfit)
	folders.Appearance:SetAttribute("Outfit",           slot.Outfit)
	folders.Appearance:SetAttribute("Shirt",            slot.Shirt)
	folders.Appearance:SetAttribute("Pants",            slot.Pants)
	folders.Appearance:SetAttribute("ScouterEquipped",  slot.ScouterEquipped)

	-- Combat status (managed at runtime by CombatTag)
	folders.Combat:SetAttribute("CombatTag",          false)
	folders.Combat:SetAttribute("CombatTimerRunning", false)
	folders.Combat:SetAttribute("CombatTime",         0)
end

function StatsManager.refresh(player: Player)
	local slot = Manager.getActiveSlot(player)
	local shared = Manager.getShared(player)
	if not slot or not shared or not player.Character then
		return
	end
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local cats = getCategories(humanoid)
		writeValues(cats, slot, shared)

		-- Keep the Humanoid's built-in health bar in sync with the new MaxHealth.
		local maxHealth  = cats.Stats:GetAttribute("MaxHealth")  :: number
		local maxKi      = cats.Stats:GetAttribute("MaxKi")      :: number
		local maxStamina = cats.Stats:GetAttribute("MaxStamina") :: number

		humanoid.MaxHealth = maxHealth
		humanoid.Health    = maxHealth

		-- Clamp current Ki/Stamina down to the new max if stats changed.
		-- Never raise them here; runtime systems own the current value.
		local curKi  = cats.Stats:GetAttribute("Ki")      :: number?
		local curStam = cats.Stats:GetAttribute("Stamina") :: number?
		if curKi   then cats.Stats:SetAttribute("Ki",      math.min(curKi,   maxKi))      end
		if curStam then cats.Stats:SetAttribute("Stamina", math.min(curStam, maxStamina)) end
	end
end

function StatsManager.bind(player: Player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 5)
		if not humanoid or not humanoid:IsA("Humanoid") then
			return
		end
		local folders = createCategories(humanoid)
		initRuntimeFlags(folders.Combat)
		local slot = Manager.getActiveSlot(player)
		local shared = Manager.getShared(player)
		if slot and shared then
			writeValues(folders, slot, shared)
			PlayerRaceBuilder.buildFromSlot(character, slot)

			-- If the slot is a Saiyan that hasn't had the LSSJ check yet, roll now.
			-- checkLSSJ mutates slot.Race in place on a win, so re-apply everything
			-- with the updated data before we lock in the humanoid values.
			local profile = Manager.getProfile(player)
			if profile then
				local awarded = RollRace.checkLSSJ(player, profile.Data.ActiveSlot)
				if awarded then
					writeValues(folders, slot, shared)
					PlayerRaceBuilder.buildFromSlot(character, slot)
				end
			end

			-- Apply computed MaxHealth to the Humanoid so the health bar is correct.
			local maxHealth  = folders.Stats:GetAttribute("MaxHealth")  :: number
			local maxKi      = folders.Stats:GetAttribute("MaxKi")      :: number
			local maxStamina = folders.Stats:GetAttribute("MaxStamina") :: number

			humanoid.MaxHealth = maxHealth
			humanoid.Health    = maxHealth

			folders.Stats:SetAttribute("Ki",      maxKi)
			folders.Stats:SetAttribute("Stamina", maxStamina)
		end
	end)
end

-- Binds an AI / NPC character directly from a slot data table.
-- slotData must match SlotData layout from TemplateData.
function StatsManager.bindNPC(character: Model, slotData: any)
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid or not humanoid:IsA("Humanoid") then return end
	local folders = createCategories(humanoid)
	initRuntimeFlags(folders.Combat)
	local dummyShared = { Spins = 0 }
	writeValues(folders, slotData, dummyShared)
	PlayerRaceBuilder.buildFromSlot(character, slotData)
end

return StatsManager
