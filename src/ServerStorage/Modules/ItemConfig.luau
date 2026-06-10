--!strict
-- Data-driven roster for the Items system (the per-slot inventory), the counterpart to SkillConfig
-- (offensive skills) and FormConfig (transformations). Lives in ServerStorage on purpose: balance /
-- config must NOT replicate to clients -- the client only ever receives the sanitised list built by
-- Inventory.list (counts + display + the finished description string).
--
-- Adding an item = one entry here + (for usable items) one behavior module under
-- ServerStorage.Modules.Items. The old Instance-based config children map 1:1 onto fields:
--   Description -> description, Image -> image, Interactable -> interactable, MaxAmount -> maxAmount,
--   Rarity -> rarity. `type` is the unified sort key shared with Skills/Forms for the future
--   unified inventory. Image ids below are PLACEHOLDERS (rbxassetid://0) -- swap in real assets.

export type ItemType = "Consumable" | "Material" | "Key" | "Boost"
export type ItemRarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

export type ItemDef = {
	displayName: string,
	type: ItemType, -- unified sort key for the inventory (shared concept with Skills/Forms)
	rarity: ItemRarity,
	maxAmount: number, -- per-slot stack cap (old "MaxAmount")
	image: string, -- "rbxassetid://…" (old "Image")
	interactable: boolean, -- true = can be actively Used (consumed); false = passive/material
	behavior: string?, -- module name under ServerStorage.Modules.Items (nil for passive items)
	cooldown: number?, -- optional use-cooldown in seconds
	params: { [string]: any }?, -- inputs the behavior reads, so one behavior serves many items
	description: {
		note: string?,
		summary: string,
		effects: { string }, -- curated, player-facing lines (e.g. "Health Restore: 100%")
	},
}

local items: { [string]: ItemDef } = {
	SenzuBean = {
		displayName = "Senzu Bean",
		type = "Consumable",
		rarity = "Rare",
		maxAmount = 5,
		image = "rbxassetid://0",
		interactable = true,
		behavior = "InstantRestore",
		params = { health = 1, ki = 1, stamina = 1 },
		description = {
			summary = "A mystical bean grown at Korin's Tower. Eating one instantly restores your body "
				.. "to peak condition -- mending every wound and refilling your energy in a single bite.",
			effects = {
				"Health Restore: 100%",
				"Ki Restore: 100%",
				"Stamina Restore: 100%",
			},
		},
	},

	SenzuBean75OT = {
		displayName = "Senzu Bean (Sustained)",
		type = "Consumable",
		rarity = "Uncommon",
		maxAmount = 10,
		image = "rbxassetid://0",
		interactable = true,
		behavior = "RestoreOverTime",
		params = { fraction = 0.75, duration = 30 },
		description = {
			note = "Heals gradually -- stay alive to reap the full benefit.",
			summary = "A half-ripened senzu. Instead of an instant cure, its energy seeps in over time, "
				.. "steadily knitting wounds and restoring your stamina and ki.",
			effects = {
				"Health Restore: 75% over 30s",
				"Ki Restore: 75% over 30s",
				"Stamina Restore: 75% over 30s",
			},
		},
	},

	DragonRadar = {
		displayName = "Dragon Radar",
		type = "Key",
		rarity = "Epic",
		maxAmount = 1,
		image = "rbxassetid://0",
		interactable = false, -- passive keepsake: shows in the bag, but isn't consumed
		description = {
			summary = "Bulma's invention -- a handheld device that pinpoints the faint energy signature "
				.. "of every Dragon Ball on the planet. A treasured keepsake, not something you use up.",
			effects = {
				"Reveals nearby Dragon Balls",
			},
		},
	},
}

local ItemConfig = {}

-- The whole roster (id -> def). Iterate for grants / UI catalogues.
function ItemConfig.all(): { [string]: ItemDef }
	return items
end

function ItemConfig.get(itemId: string): ItemDef?
	return items[itemId]
end

local RARITY_RANK: { [string]: number } = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythic = 6,
}

-- Roster as a stable array, sorted by type, then rarity rank, then display name (UI ordering).
function ItemConfig.list(): { { id: string, def: ItemDef } }
	local out: { { id: string, def: ItemDef } } = {}
	for id, def in items do
		table.insert(out, { id = id, def = def })
	end
	table.sort(out, function(a, b)
		if a.def.type ~= b.def.type then
			return a.def.type < b.def.type
		end
		local ra = RARITY_RANK[a.def.rarity] or 0
		local rb = RARITY_RANK[b.def.rarity] or 0
		if ra ~= rb then
			return ra < rb
		end
		return a.def.displayName < b.def.displayName
	end)
	return out
end

return ItemConfig
