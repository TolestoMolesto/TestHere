--!strict
-- Runtime controller for USING an item, mirroring SkillState: resolve the item, run every gate,
-- consume one, start any cooldown, then run its behavior module. Consuming up front (before the
-- behavior, which may run for many seconds -- e.g. a heal-over-time) stops a single stack from being
-- spent twice mid-effect. Passive/material items (interactable = false) can never be used here.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local ItemConfig = require(ServerStorage.Modules.ItemConfig)
local Inventory = require(ServerStorage.Modules.Inventory)

local ItemState = {}

export type Context = {
	player: Player,
	character: Model,
	itemId: string,
	def: ItemConfig.ItemDef,
}

-- Lazily required behavior modules, cached after first load (mirrors SkillState).
local behaviors: { [string]: (Context) -> () } = {}

local function loadBehavior(name: string): ((Context) -> ())?
	if behaviors[name] then
		return behaviors[name]
	end
	local folder = ServerStorage.Modules:FindFirstChild("Items")
	local module = folder and folder:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		warn(`[ItemState] missing behavior module "{name}"`)
		return nil
	end
	local ok, result = pcall(require, module)
	if not ok or type(result) ~= "function" then
		warn(`[ItemState] behavior "{name}" failed to load: {result}`)
		return nil
	end
	local fn = result :: (Context) -> ()
	behaviors[name] = fn
	return fn
end

-- Try to use one of `itemId` from the player's active slot. Returns true if it was consumed + run.
function ItemState.use(player: Player, itemId: string): boolean
	local def = ItemConfig.get(itemId)
	if not def then
		return false
	end
	-- Passive/material items can't be used; only items with a behavior can.
	if not def.interactable or not def.behavior then
		return false
	end

	local character = player.Character
	if not character or not character.Parent then
		return false
	end
	if character:GetAttribute("InCustomization") then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	-- Cooldown gate (only for items that define one), tracked as a synced server timestamp.
	local now = Workspace:GetServerTimeNow()
	if def.cooldown and def.cooldown > 0 then
		local readyAt = (character:GetAttribute(`Item_{itemId}_ReadyAt`) :: number?) or 0
		if now < readyAt then
			return false
		end
	end

	-- Must have at least one in stock.
	if Inventory.count(player, itemId) <= 0 then
		return false
	end

	local behavior = loadBehavior(def.behavior)
	if not behavior then
		return false
	end

	-- Consume up front, then start the cooldown, then run the (possibly long-running) effect.
	if not Inventory.remove(player, itemId, 1) then
		return false
	end
	if def.cooldown and def.cooldown > 0 then
		character:SetAttribute(`Item_{itemId}_ReadyAt`, now + def.cooldown)
	end

	local context: Context = {
		player = player,
		character = character,
		itemId = itemId,
		def = def,
	}
	task.spawn(behavior, context)
	return true
end

return ItemState
