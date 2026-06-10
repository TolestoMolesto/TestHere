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

local SENSU_SEED_DROP = { seedDropItemId = "SensuBeanSeed", seedDropChance = 0.25 }

local items: { [string]: ItemDef } = {
	SensuBean33 = {
		displayName = "Sensu Bean",
		type = "Consumable",
		rarity = "Common",
		maxAmount = 10,
		image = "rbxassetid://0",
		interactable = true,
		behavior = "InstantRestore",
		params = { health = 0.33, ki = 0.33, stamina = 0.33, seedDropItemId = SENSU_SEED_DROP.seedDropItemId, seedDropChance = SENSU_SEED_DROP.seedDropChance },
		description = {
			summary = "A mystical bean grown at Korin's Tower. This weaker bean instantly restores part of your body and energy.",
			effects = {
				"Health Restore: 33%",
				"Ki Restore: 33%",
				"Stamina Restore: 33%",
				"25% chance to create a Sensu Bean Seed",
			},
		},
	},

	SensuBean66 = {
		displayName = "Sensu Bean",
		type = "Consumable",
		rarity = "Rare",
		maxAmount = 10,
		image = "rbxassetid://0",
		interactable = true,
		behavior = "InstantRestore",
		params = { health = 0.66, ki = 0.66, stamina = 0.66, seedDropItemId = SENSU_SEED_DROP.seedDropItemId, seedDropChance = SENSU_SEED_DROP.seedDropChance },
		description = {
			summary = "A mystical bean grown at Korin's Tower. Eating one instantly restores a large portion of your body and energy.",
			effects = {
				"Health Restore: 66%",
				"Ki Restore: 66%",
				"Stamina Restore: 66%",
				"25% chance to create a Sensu Bean Seed",
			},
		},
	},

	-- Backwards-compatible id for the original full bean, now displayed as Sensu Bean.
	SenzuBean = {
		displayName = "Sensu Bean",
		type = "Consumable",
		rarity = "Legendary",
		maxAmount = 5,
		image = "rbxassetid://0",
		interactable = true,
		behavior = "InstantRestore",
		params = { health = 1, ki = 1, stamina = 1, seedDropItemId = SENSU_SEED_DROP.seedDropItemId, seedDropChance = SENSU_SEED_DROP.seedDropChance },
		description = {
			summary = "A mystical bean grown at Korin's Tower. Eating one instantly restores your body to peak condition.",
			effects = {
				"Health Restore: 100%",
				"Ki Restore: 100%",
				"Stamina Restore: 100%",
				"25% chance to create a Sensu Bean Seed",
			},
		},
	},

	SensuBean33OT = {
		displayName = "Sensu Bean",
		type = "Consumable",
		rarity = "Uncommon",
		maxAmount = 10,
		image = "rbxassetid://0",
		interactable = true,
		behavior = "RestoreOverTime",
		params = { fraction = 0.33, duration = 30, seedDropItemId = SENSU_SEED_DROP.seedDropItemId, seedDropChance = SENSU_SEED_DROP.seedDropChance },
		description = {
			note = "Heals gradually -- stay alive to reap the full benefit.",
			summary = "A slow-release Sensu Bean. Its energy seeps in over time, steadily restoring your body, stamina, and ki.",
			effects = {
				"Health Restore: 33% over 30s",
				"Ki Restore: 33% over 30s",
				"Stamina Restore: 33% over 30s",
				"25% chance to create a Sensu Bean Seed",
			},
		},
	},

	SensuBean66OT = {
		displayName = "Sensu Bean",
		type = "Consumable",
		rarity = "Epic",
		maxAmount = 10,
		image = "rbxassetid://0",
		interactable = true,
		behavior = "RestoreOverTime",
		params = { fraction = 0.66, duration = 30, seedDropItemId = SENSU_SEED_DROP.seedDropItemId, seedDropChance = SENSU_SEED_DROP.seedDropChance },
		description = {
			note = "Heals gradually -- stay alive to reap the full benefit.",
			summary = "A slow-release Sensu Bean. Its energy seeps in over time, steadily restoring your body, stamina, and ki.",
			effects = {
				"Health Restore: 66% over 30s",
				"Ki Restore: 66% over 30s",
				"Stamina Restore: 66% over 30s",
				"25% chance to create a Sensu Bean Seed",
			},
		},
	},

	SensuBean100OT = {
		displayName = "Sensu Bean",
		type = "Consumable",
		rarity = "Mythic",
		maxAmount = 5,
		image = "rbxassetid://0",
		interactable = true,
		behavior = "RestoreOverTime",
		params = { fraction = 1, duration = 30, seedDropItemId = SENSU_SEED_DROP.seedDropItemId, seedDropChance = SENSU_SEED_DROP.seedDropChance },
		description = {
			note = "Heals gradually -- stay alive to reap the full benefit.",
			summary = "A slow-release Sensu Bean. Its energy seeps in over time, steadily restoring your body, stamina, and ki.",
			effects = {
				"Health Restore: 100% over 30s",
				"Ki Restore: 100% over 30s",
				"Stamina Restore: 100% over 30s",
				"25% chance to create a Sensu Bean Seed",
			},
		},
	},

	SensuBeanSeed = {
		displayName = "Sensu Bean Seed",
		type = "Material",
		rarity = "Common",
		maxAmount = 99,
		image = "rbxassetid://0",
		interactable = false,
		description = {
			summary = "A tiny seed from a Sensu Bean. It does nothing for now.",
			effects = {
				"No effect",
			},
		},
	},

	EarthDragonBall1 = {
		displayName = "1-Star Dragon Ball",
		type = "Key",
		rarity = "Legendary",
		maxAmount = 1,
		image = "rbxassetid://0",
		interactable = false,
		description = {
			summary = "The One-Star Earth Dragon Ball. Gather all seven to call forth Earth's eternal dragon.",
			effects = {
				"Earth Variant",
				"One-Star Dragon Ball",
			},
		},
	},

	EarthDragonBall2 = {
		displayName = "2-Star Dragon Ball",
		type = "Key",
		rarity = "Legendary",
		maxAmount = 1,
		image = "rbxassetid://0",
		interactable = false,
		description = {
			summary = "The Two-Star Earth Dragon Ball. Gather all seven to call forth Earth's eternal dragon.",
			effects = {
				"Earth Variant",
				"Two-Star Dragon Ball",
			},
		},
	},

	EarthDragonBall3 = {
		displayName = "3-Star Dragon Ball",
		type = "Key",
		rarity = "Legendary",
		maxAmount = 1,
		image = "rbxassetid://0",
		interactable = false,
		description = {
			summary = "The Three-Star Earth Dragon Ball. Gather all seven to call forth Earth's eternal dragon.",
			effects = {
				"Earth Variant",
				"Three-Star Dragon Ball",
			},
		},
	},

	EarthDragonBall4 = {
		displayName = "4-Star Dragon Ball",
		type = "Key",
		rarity = "Legendary",
		maxAmount = 1,
		image = "rbxassetid://0",
		interactable = false,
		description = {
			summary = "The Four-Star Earth Dragon Ball. Gather all seven to call forth Earth's eternal dragon.",
			effects = {
				"Earth Variant",
				"Four-Star Dragon Ball",
			},
		},
	},

	EarthDragonBall5 = {
		displayName = "5-Star Dragon Ball",
		type = "Key",
		rarity = "Legendary",
		maxAmount = 1,
		image = "rbxassetid://0",
		interactable = false,
		description = {
			summary = "The Five-Star Earth Dragon Ball. Gather all seven to call forth Earth's eternal dragon.",
			effects = {
				"Earth Variant",
				"Five-Star Dragon Ball",
			},
		},
	},

	EarthDragonBall6 = {
		displayName = "6-Star Dragon Ball",
		type = "Key",
		rarity = "Legendary",
		maxAmount = 1,
		image = "rbxassetid://0",
		interactable = false,
		description = {
			summary = "The Six-Star Earth Dragon Ball. Gather all seven to call forth Earth's eternal dragon.",
			effects = {
				"Earth Variant",
				"Six-Star Dragon Ball",
			},
		},
	},

	EarthDragonBall7 = {
		displayName = "7-Star Dragon Ball",
		type = "Key",
		rarity = "Legendary",
		maxAmount = 1,
		image = "rbxassetid://0",
		interactable = false,
		description = {
			summary = "The Seven-Star Earth Dragon Ball. Gather all seven to call forth Earth's eternal dragon.",
			effects = {
				"Earth Variant",
				"Seven-Star Dragon Ball",
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