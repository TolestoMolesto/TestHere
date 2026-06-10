--!strict
-- Item behavior: restore a fraction of max Health/Ki/Stamina spread evenly over a duration (1 tick
-- per second). Bails if the character dies, despawns, or respawns mid-heal. Reads params.fraction
-- (of each max) and params.duration (seconds). Used by SenzuBean75OT ({ fraction = 0.75,
-- duration = 30 }). This is the ported "Senzu Beans 75% OverTime" logic.

local ServerStorage = game:GetService("ServerStorage")

local Shared = require(ServerStorage.Modules.Items.Shared)
local ItemState = require(ServerStorage.Modules.ItemState)

return function(context: ItemState.Context): ()
	local character = context.character
	local player = context.player
	local params: { [string]: any } = context.def.params or {}

	local fraction = (params.fraction :: number?) or 0.75
	local duration = (params.duration :: number?) or 30
	local ticks = math.max(1, math.floor(duration))

	local humanoid = Shared.humanoid(character)
	if not humanoid then
		return
	end

	-- Capture totals up front so a mid-heal MaxHealth/MaxKi change (e.g. a transform) doesn't distort
	-- the per-tick step.
	local healPerTick = (humanoid.MaxHealth * fraction) / ticks
	local kiPerTick = (((character:GetAttribute("MaxKi") :: number?) or 0) * fraction) / ticks
	local stamPerTick = (((character:GetAttribute("MaxStamina") :: number?) or 0) * fraction) / ticks

	for _ = 1, ticks do
		task.wait(1)
		-- Stop if the player left, respawned into a new character, or died.
		if player.Character ~= character or not Shared.isAlive(character) then
			break
		end
		Shared.healHealth(character, healPerTick)
		Shared.restoreAttribute(character, "Ki", "MaxKi", kiPerTick)
		Shared.restoreAttribute(character, "Stamina", "MaxStamina", stamPerTick)
	end
end
