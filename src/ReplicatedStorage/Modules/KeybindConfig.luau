--!strict
-- Shared, stateless catalogue of every rebindable action: its default key, a UI label, and which
-- group/row it shows in. Required by BOTH the client Keybinds singleton and the server KeybindsServer
-- (so the server can validate action ids) -- keep it free of client-only services. Combat defaults
-- are pulled straight from ActionConfig so those keys keep a single source of truth.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionConfig = require(ReplicatedStorage.Modules.ActionConfig)

export type Bind = Enum.KeyCode | Enum.UserInputType
export type Entry = { default: Bind, label: string, group: string, order: number }

local function combat(id: string, label: string, order: number): Entry
	local def = ActionConfig[id]
	local binding = def and def.binding
	assert(binding ~= nil, `KeybindConfig: ActionConfig.{id} has no binding to inherit`)
	return { default = binding :: Bind, label = label, group = "Combat", order = order }
end

local KeybindConfig: { [string]: Entry } = {
	LightAttack = combat("LightAttack", "Light Attack", 1),
	HeavyAttack = combat("HeavyAttack", "Heavy Attack", 2),
	Block = combat("Block", "Block", 3),
	Charge = combat("Charge", "Charge", 4),
	KiBlast = combat("KiBlast", "Ki Blast", 5),
	Vanish = combat("Vanish", "Vanish", 6),
	Recover = combat("Recover", "Recover", 7),
	Rest = combat("Rest", "Rest", 8),
	SpawnShadow = combat("SpawnShadow", "Spawn Shadow", 9),

	Scouter = { default = Enum.KeyCode.E, label = "Toggle Scouter", group = "Utility", order = 10 },
	LockOn = { default = Enum.KeyCode.L, label = "Lock On", group = "Utility", order = 11 },
	-- Opens the Inventory (bag) panel; owned by InventoryController. Keys 1-5/6-0 are taken by Skills
	-- and Forms, so the bag lives on its own toggle.
	Inventory = { default = Enum.KeyCode.Backquote, label = "Inventory", group = "Utility", order = 25 },
	-- Opens the Party panel (roster + a player list to invite to party / challenge to spar). Owned by
	-- PartyController. Spar challenges are sent from that panel, so spar needs no key of its own.
	Party = { default = Enum.KeyCode.P, label = "Party", group = "Utility", order = 26 },
	-- Ki suppression dial (PowerOutputController): step the shown BattlePower output up / down by 10%
	-- (clamped 1-100). Only does anything while the slot owns the PowerSuppression passive.
	RaisePower = { default = Enum.KeyCode.RightBracket, label = "Raise Power Output", group = "Utility", order = 27 },
	LowerPower = { default = Enum.KeyCode.LeftBracket, label = "Lower Power Output", group = "Utility", order = 28 },

	-- Offensive skill loadout (keys 1-5). Owned by SkillController, fired as the "Skill" action.
	SkillSlot1 = { default = Enum.KeyCode.One, label = "Skill Slot 1", group = "Skills", order = 12 },
	SkillSlot2 = { default = Enum.KeyCode.Two, label = "Skill Slot 2", group = "Skills", order = 13 },
	SkillSlot3 = { default = Enum.KeyCode.Three, label = "Skill Slot 3", group = "Skills", order = 14 },
	SkillSlot4 = { default = Enum.KeyCode.Four, label = "Skill Slot 4", group = "Skills", order = 15 },
	SkillSlot5 = { default = Enum.KeyCode.Five, label = "Skill Slot 5", group = "Skills", order = 16 },

	FormSlot1 = { default = Enum.KeyCode.Six, label = "Ability Slot 1", group = "Abilities", order = 17 },
	FormSlot2 = { default = Enum.KeyCode.Seven, label = "Ability Slot 2", group = "Abilities", order = 18 },
	FormSlot3 = { default = Enum.KeyCode.Eight, label = "Ability Slot 3", group = "Abilities", order = 19 },
	FormSlot4 = { default = Enum.KeyCode.Nine, label = "Ability Slot 4", group = "Abilities", order = 20 },
	FormSlot5 = { default = Enum.KeyCode.Zero, label = "Ability Slot 5", group = "Abilities", order = 21 },

	FlightAscend = { default = Enum.KeyCode.Space, label = "Fly Up / Activate", group = "Flight", order = 22 },
	FlightDescend = { default = Enum.KeyCode.LeftControl, label = "Fly Down", group = "Flight", order = 23 },
	FlightBoost = { default = Enum.KeyCode.LeftShift, label = "Flight Boost", group = "Flight", order = 24 },
}

return KeybindConfig
