-- StatData layers: Base (race base, never modified by bonuses), Flat (additive bonus),
-- Add (additive % bonus; 0=none), Multi (direct multiplier; 1=none).
-- Final = (Base + Flat + All.Flat) × (1 + Add + All.Add) × Multi × All.Multi
export type StatData = {
	Base: number,
	Flat: number,
	Add: number,
	Multi: number,
}

export type ModStat = {
	Flat: number,
	Add: number,
	Multi: number,
}

-- Color3 is not DataStore-serializable; use this table instead.
export type RGBColor = {
	R: number,
	G: number,
	B: number,
}

export type SlotData = {
	Name: string,
	Race: string,
	-- Home world this slot plays on: a Teleport destination NAME (see Teleport.luau). The Main Menu
	-- "Play" button sends the player here. Defaults to "Earth"; validated server-side before travel.
	Planet: string,
	LSSJChecked: boolean,
	FormMastery: { [string]: { Level: number, XP: number } },
	-- Offensive Skills (keys 1-5): the collected/unlocked set, and the equipped 5-slot loadout
	-- (skill ids matching SkillConfig; "" = empty). Per slot, since each slot is its own character.
	UnlockedSkills: { [string]: boolean },
	SkillLoadout: { string },
	-- Equipped Forms/Techniques per hotkey slot (keys 6-0; form ids matching FormConfig, "" = empty),
	-- the Forms counterpart to SkillLoadout. Resolved by FormState.toggleByIndex.
	FormLoadout: { string },
	-- Per-slot inventory for the data-driven Items system: itemId (matching ItemConfig) -> count.
	Items: { [string]: number },
	BattlePower: number,
	Lives: number,
	Longevity: number,
	Strength: StatData,
	Endurance: StatData,
	Speed: StatData,
	BattleExperience: StatData,
	KiControl: StatData,
	PhysicalResistance: StatData,
	KiResistance: StatData,
	Damage: StatData,
	PhysicalDamage: StatData,
	KiDamage: StatData,
	AllDamageReduction: StatData,
	Dodge: StatData,
	All: ModStat,
	Health: ModStat,
	Ki: ModStat,
	Stamina: ModStat,
	Gender: string,
	Age: number,
	Height: string,
	BodyColor: RGBColor,
	HairColor: RGBColor,
	KiColor: RGBColor,
	Hair: string,
	Eyebrows: string,
	Eyes: string,
	EyeColor: string,
	Nose: string,
	Mouth: string,
	BodyDecal: string,
	ClothingOutfit: string,
	Outfit: string,
	Shirt: string,
	Pants: string,
	ScouterEquipped: string,
}

export type SharedData = {
	Spins: number,
	Admin: boolean,
	Unlocks: { [string]: boolean },
	Passes: { [string]: boolean }, -- owned game passes (key -> true); persistent so passes can be gifted
	GlobalRaces: { [string]: number }, -- slot index holding that race; 0 = not a holder
	RollCount: number, -- lifetime rolls (never resets); powers the "Total Rolls" HUD + pity
	GlobalPity: number, -- rolls since the last global; ramps global odds, guaranteed at PITY_GUARANTEE
	RedeemedCodes: { [string]: boolean }, -- normalised codes this account has already redeemed
	PurchaseIds: { string }, -- rolling log of granted Dev Product PurchaseIds; makes ProcessReceipt idempotent
	PurchasedSlots: number, -- character slots bought via the Slot dev product; gates the buyable cap (total slots are uncapped)
}

-- Account-wide client preferences. Mirrors ReplicatedStorage.Modules.Settings DEFAULTS. Saved
-- GLOBALLY (top-level, alongside Shared), never per slot.
export type SettingsData = {
	Audio: { Music: number, SFX: number },
	LockOn: { Style: string, FOV: number, Transparency: number },
	Camera: { Shake: boolean },
}

export type PlayerData = {
	Version: number,
	ActiveSlot: number,
	Slots: { SlotData },
	Shared: SharedData,
	Settings: SettingsData,
	Keybinds: { [string]: string }, -- rebindable action id -> serialized bind; only non-default overrides
}

-- Race "NA" signals RollRace that this slot is unrolled; first activation is free.
local SLOT_TEMPLATE: SlotData = {
	Name = "",
	Race = "NA",
	Planet = "Earth",
	LSSJChecked = false,
	FormMastery = {},
	UnlockedSkills = {},
	SkillLoadout = { "", "", "", "", "" },
	FormLoadout = { "", "", "", "", "" },
	Items = {},
	BattlePower = 0,
	Lives = 7,
	Longevity = 100,
	Strength = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
	Endurance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
	Speed = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
	BattleExperience = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
	KiControl = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
	PhysicalResistance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
	KiResistance = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
	Damage = { Base = 1, Flat = 0, Add = 0, Multi = 1 },
	PhysicalDamage = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
	KiDamage = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
	AllDamageReduction = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
	Dodge = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
	All = { Flat = 0, Add = 0, Multi = 1 },
	Health = { Flat = 0, Add = 0, Multi = 1 },
	Ki = { Flat = 0, Add = 0, Multi = 1 },
	Stamina = { Flat = 0, Add = 0, Multi = 1 },
	Gender = "Male",
	Age = 0,
	Height = "Adult",
	BodyColor = { R = -1, G = -1, B = -1 },
	HairColor = { R = -1, G = -1, B = -1 },
	KiColor = { R = -1, G = -1, B = -1 },
	Hair = "NA",
	Eyebrows = "NA",
	Eyes = "NA",
	EyeColor = "NA",
	Nose = "NA",
	Mouth = "NA",
	BodyDecal = "NA",
	ClothingOutfit = "NewStarterFit",
	Outfit = "NA",
	Shirt = "NewStarterFit",
	Pants = "NewStarterFit",
	ScouterEquipped = "None",
}

local PLAYER_DATA_TEMPLATE: PlayerData = {
	-- v11: added per-slot FormLoadout (equipped Forms/Techniques on keys 6-0; "" = empty), making the
	-- 6-0 ability row rearrangeable like SkillLoadout.
	-- v10: added per-slot Items (inventory map itemId -> count for the data-driven Items system).
	-- v9: added Shared.PurchasedSlots (count of character slots bought via the Slot dev product; gates
	-- the 5-buyable cap -- total slots stay uncapped for free/race grants). v8: added per-slot Planet (the
	-- home world the Main Menu "Play" button travels to; defaults to "Earth"). Additive --
	-- reconcileShared/reconcileSlot/mergeDefaults backfill both onto existing saves.
	-- v7: added Shared.PurchaseIds (Dev Product receipt idempotency) + Shared.Passes (persistent,
	-- giftable game-pass ownership) for Monetization. v6 added
	-- Shared.RollCount/GlobalPity/RedeemedCodes for the Race Roller (rolls economy + pity + codes); new
	-- profiles start with 25 rolls. v5 added per-slot Lives + Longevity. v4 added UnlockedSkills +
	-- SkillLoadout. All additive -- reconcileShared/reconcileSlot backfill onto existing saves, so no
	-- version-gated migration is needed.
	Version = 11,
	ActiveSlot = 1,
	Slots = { SLOT_TEMPLATE },
	Shared = {
		Spins = 25,
		Admin = false,
		Unlocks = {
			Majin = false,
		},
		Passes = {},
		GlobalRaces = {
			Angel = 0,
			God = 0,
			Kai = 0,
		},
		RollCount = 0,
		GlobalPity = 0,
		RedeemedCodes = {},
		PurchaseIds = {},
		PurchasedSlots = 0,
	},
	Settings = {
		Audio = { Music = 0.5, SFX = 0.5 },
		LockOn = { Style = "Dynamic_View", FOV = 1, Transparency = 0.5 },
		Camera = { Shake = true },
	},
	Keybinds = {},
}

local function deepCopy<T>(value: T): T
	if typeof(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value :: any do
		out[k] = deepCopy(v)
	end
	return out :: any
end

local function newSlot(): SlotData
	return deepCopy(SLOT_TEMPLATE)
end

-- ProfileStore:Reconcile() doesn't deep-merge every nested table: Slots is a number-keyed array it
-- skips entirely, and Settings nests deeper than it fills reliably. These helpers patch what it
-- leaves untouched, recursively filling missing keys from the template.
local function mergeDefaults(target: { [string]: any }, template: { [string]: any })
	for k, v in template do
		if target[k] == nil then
			target[k] = if typeof(v) == "table" then deepCopy(v) else v
		elseif typeof(v) == "table" and typeof(target[k]) ~= "table" then
			target[k] = deepCopy(v)
		elseif typeof(v) == "table" and typeof(target[k]) == "table" then
			mergeDefaults(target[k], v)
		end
	end
end

local function reconcileSlot(slot: any)
	mergeDefaults(slot, SLOT_TEMPLATE :: any)
end

local function reconcileSettings(data: any)
	if typeof(data.Settings) ~= "table" then
		data.Settings = deepCopy(PLAYER_DATA_TEMPLATE.Settings)
		return
	end
	mergeDefaults(data.Settings, PLAYER_DATA_TEMPLATE.Settings :: any)
end

-- Shared holds nested tables (Unlocks/GlobalRaces) and the newer roller fields (RollCount/GlobalPity/
-- RedeemedCodes) that Reconcile() doesn't fill deeply; backfill them without clobbering existing
-- balances (an existing save keeps its Spins -- new fields just appear with their template defaults).
local function reconcileShared(data: any)
	if typeof(data.Shared) ~= "table" then
		data.Shared = deepCopy(PLAYER_DATA_TEMPLATE.Shared)
		return
	end
	mergeDefaults(data.Shared, PLAYER_DATA_TEMPLATE.Shared :: any)
end

-- Keybinds is a flat string map of overrides (no nesting), so it only needs to exist as a table;
-- missing/unknown action ids fall back to KeybindConfig defaults client-side.
local function reconcileKeybinds(data: any)
	if typeof(data.Keybinds) ~= "table" then
		data.Keybinds = {}
	end
end

return {
	PLAYER_DATA_TEMPLATE = PLAYER_DATA_TEMPLATE,
	SLOT_TEMPLATE = SLOT_TEMPLATE,
	newSlot = newSlot,
	reconcileSlot = reconcileSlot,
	reconcileSettings = reconcileSettings,
	reconcileShared = reconcileShared,
	reconcileKeybinds = reconcileKeybinds,
}
