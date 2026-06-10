--!strict
-- Per-slot inventory API for the Items system: the single clean surface for reading, granting, and
-- consuming items on a player's ACTIVE slot, plus the sanitised list the bag UI renders. Shops,
-- drops, and codes should grant via Inventory.add (it enforces each item's maxAmount cap). Keeps
-- Manager lean -- this is the only place that joins Manager's slot data to ItemConfig.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Describe = require(ReplicatedStorage.Modules.Describe)
local ItemConfig = require(ServerStorage.Modules.ItemConfig)
local Manager = require(ServerStorage.Modules.Manager)

local Inventory = {}

-- The active slot's raw Items map (itemId -> count), or nil if the profile isn't loaded.
local function itemsTable(player: Player): { [string]: number }?
	local slot = Manager.getActiveSlot(player)
	if not slot then
		return nil
	end
	if not slot.Items then
		slot.Items = {}
	end
	return slot.Items
end

function Inventory.count(player: Player, itemId: string): number
	local items = itemsTable(player)
	return if items then (items[itemId] or 0) else 0
end

-- Grant up to `amount`, clamped so the stack never exceeds def.maxAmount. Returns the amount actually
-- granted (0 on unknown item / no profile / already capped).
function Inventory.add(player: Player, itemId: string, amount: number): number
	if amount <= 0 then
		return 0
	end
	local def = ItemConfig.get(itemId)
	if not def then
		return 0
	end
	local items = itemsTable(player)
	if not items then
		return 0
	end
	local current = items[itemId] or 0
	local granted = math.min(amount, math.max(0, def.maxAmount - current))
	if granted > 0 then
		items[itemId] = current + granted
	end
	return granted
end

-- Remove up to `amount`; returns true if anything was removed. Clears the key at zero.
function Inventory.remove(player: Player, itemId: string, amount: number): boolean
	if amount <= 0 then
		return false
	end
	local items = itemsTable(player)
	if not items then
		return false
	end
	local current = items[itemId] or 0
	if current <= 0 then
		return false
	end
	local left = math.max(0, current - amount)
	if left <= 0 then
		-- Clear the key entirely at zero. The map is typed { [string]: number }, so cast to allow nil.
		local clearable = items :: { [string]: number? }
		clearable[itemId] = nil
	else
		items[itemId] = left
	end
	return true
end

export type Entry = {
	id: string,
	displayName: string,
	type: string,
	rarity: string,
	count: number,
	maxAmount: number,
	image: string,
	interactable: boolean,
	description: string, -- the finished Describe string; raw config never crosses to the client
}

-- The player's full inventory view (every owned item with count > 0), sorted like ItemConfig.list.
function Inventory.list(player: Player): { Entry }
	local out: { Entry } = {}
	local items = itemsTable(player)
	if not items then
		return out
	end
	for _, entry in ItemConfig.list() do
		local count = items[entry.id] or 0
		if count > 0 then
			local def = entry.def
			table.insert(out, {
				id = entry.id,
				displayName = def.displayName,
				type = def.type :: string, -- widen the ItemType union to the sanitised wire type
				rarity = def.rarity :: string,
				count = count,
				maxAmount = def.maxAmount,
				image = def.image,
				interactable = def.interactable,
				description = Describe.format({
					type = def.type,
					rarity = def.rarity,
					note = def.description.note,
					summary = def.description.summary,
					effects = def.description.effects,
					cooldown = def.cooldown,
				}),
			})
		end
	end
	return out
end

return Inventory
