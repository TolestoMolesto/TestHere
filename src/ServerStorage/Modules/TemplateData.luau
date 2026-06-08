-- Persistent player data.
--
-- Layout:
--   PlayerData = {
--       Version    : number          -- bump if a future change can't be
--                                      reconciled by ProfileStore:Reconcile()
--       ActiveSlot : number          -- 1-based index into Slots
--       Slots      : { SlotData }    -- one per character. Grows via Manager.addSlot.
--       Shared     : SharedData      -- account-wide. One copy per player.
--   }
--
-- Add a field by extending the type AND its template entry together --
-- the template is what Reconcile() and reconcileSlot() backfill against.
--
-- IMPORTANT: All values must be serializable.
--   ✗ No Color3, Vector3, CFrame, Instance, function, mixed/gapped tables
--   ✓ Plain tables, numbers, strings, booleans

-- Each combat stat has four layers:
--   Base  = race-assigned value; never modified by bonuses
--   Flat  = flat additive bonus  (items, skills, leveling)
--   Add   = additive % bonus     (0 = none, 0.5 = +50%)
--   Multi = direct multiplier    (1 = none, 1.5 = +50%)
-- Final = (Base + Flat + All.Flat) x (1 + Add + All.Add) x Multi x All.Multi
export type StatData = {
	Base:  number,
	Flat:  number,
	Add:   number,
	Multi: number,
}

-- Modifier-only stat: no Base (base is computed or fixed elsewhere).
-- Used for All, Health, Ki, and Stamina.
export type ModStat = {
	Flat:  number,
	Add:   number,
	Multi: number,
}

-- Serializable RGB colour (Color3 cannot be stored in DataStore).
export type RGBColor = {
	R: number,
	G: number,
	B: number,
}

export type SlotData = {
	Name: string,
	Race: string,
	LSSJChecked: boolean,
	-- BattlePower is derived at runtime; stored for quick reads.
	BattlePower:         number,
	-- Combat stats
	Strength:            StatData,
	Endurance:           StatData,
	Speed:               StatData,
	BattleExperience:    StatData,
	KiControl:           StatData,
	PhysicalResistance:  StatData,
	KiResistance:        StatData,
	Damage:              StatData,
	PhysicalDamage:      StatData,
	KiDamage:            StatData,
	AllDamageReduction:  StatData,
	Dodge:               StatData,
	-- Modifier-only bonuses
	All:                 ModStat,
	Health:              ModStat,
	Ki:                  ModStat,
	Stamina:             ModStat,
	-- Appearance
	Gender:              string,
	Age:                 number,
	Height:              string,
	BodyColor:           RGBColor,
	HairColor:           RGBColor,
	KiColor:             RGBColor,
	Hair:                string,
	Eyebrows:            string,
	Eyes:                string,
	EyeColor:            string,
	Nose:                string,
	Mouth:               string,
	BodyDecal:           string,
	ClothingOutfit:      string,
	Outfit:              string,
	Shirt:               string,
	Pants:               string,
	ScouterEquipped:     string,
}

export type SharedData = {
	Spins: number,
	Admin: boolean,
	Unlocks: { [string]: boolean },
	-- Tracks which slot (1-based index) holds each global race for this
	-- player. 0 means the player is not currently a holder of that race.
	GlobalRaces: { [string]: number },
}

export type PlayerData = {
	Version: number,
	ActiveSlot: number,
	Slots: { SlotData },
	Shared: SharedData,
}

-- Race = "NA" is the sentinel that tells RollRace this slot has never
-- been rolled. The first activation auto-rolls for free; subsequent
-- rolls cost a Shared.Spins.
local SLOT_TEMPLATE: SlotData = {
	Name = "",
	Race = "NA",
	LSSJChecked = false,
	BattlePower          = 0,
	Strength             = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
	Endurance            = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
	Speed                = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
	BattleExperience     = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
	KiControl            = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
	PhysicalResistance   = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
	KiResistance         = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
	Damage               = { Base = 1, Flat = 0, Add = 0, Multi = 1 },
	PhysicalDamage       = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
	KiDamage             = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
	AllDamageReduction   = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
	Dodge                = { Base = 0, Flat = 0, Add = 0, Multi = 1 },
	All                  = { Flat = 0, Add = 0, Multi = 1 },
	Health               = { Flat = 0, Add = 0, Multi = 1 },
	Ki                   = { Flat = 0, Add = 0, Multi = 1 },
	Stamina              = { Flat = 0, Add = 0, Multi = 1 },
	-- Appearance
	Gender               = "Male",
	Age                  = 0,
	Height               = "Adult",
	BodyColor            = { R = -1, G = -1, B = -1 },
	HairColor            = { R = -1, G = -1, B = -1 },
	KiColor              = { R = -1, G = -1, B = -1 },
	Hair                 = "NA",
	Eyebrows             = "NA",
	Eyes                 = "NA",
	EyeColor             = "NA",
	Nose                 = "NA",
	Mouth                = "NA",
	BodyDecal            = "NA",
	ClothingOutfit       = "NewStarterFit",
	Outfit               = "NA",
	Shirt                = "NewStarterFit",
	Pants                = "NewStarterFit",
	ScouterEquipped      = "None",
}

local PLAYER_DATA_TEMPLATE: PlayerData = {
	Version = 3,
	ActiveSlot = 1,
	Slots = { SLOT_TEMPLATE },
	Shared = {
		Spins = 0,
		Admin = false,
		Unlocks = {
			Majin = false,
		},
		GlobalRaces = {
			Angel = 0,
			God   = 0,
			Kai   = 0,
		},
	},
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

-- Returns a fresh deep-copy of SLOT_TEMPLATE so callers can mutate it
-- without poisoning the template for the next slot.
local function newSlot(): SlotData
	return deepCopy(SLOT_TEMPLATE)
end

-- Backfill missing keys in `slot` from SLOT_TEMPLATE. ProfileStore:Reconcile()
-- only walks profile.Data's top level; sub-tables inside the Slots array
-- need this manual pass when we add new SlotData fields later.
local function reconcileSlot(slot: any)
	local function merge(target: {[string]: any}, template: {[string]: any})
		for k, v in template do
			if target[k] == nil then
				-- Key missing entirely: backfill from template.
				target[k] = if typeof(v) == "table" then deepCopy(v) else v
			elseif typeof(v) == "table" and typeof(target[k]) ~= "table" then
				-- Saved value is the wrong type (e.g. plain number where a
				-- stat table is now expected). Replace with template default.
				target[k] = deepCopy(v)
			elseif typeof(v) == "table" and typeof(target[k]) == "table" then
				merge(target[k], v)
			end
		end
	end
	merge(slot, SLOT_TEMPLATE :: any)
end

return {
	PLAYER_DATA_TEMPLATE = PLAYER_DATA_TEMPLATE,
	SLOT_TEMPLATE = SLOT_TEMPLATE,
	newSlot = newSlot,
	reconcileSlot = reconcileSlot,
}
