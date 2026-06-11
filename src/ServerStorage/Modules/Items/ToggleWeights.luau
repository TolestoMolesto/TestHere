--!strict
-- Item behavior: toggles training weights on the player's current character via the shared Weights
-- module (sets the WeightTraining / Weight attributes + the four visible limb Accessories). Tonnage is
-- read from params.weight (default 0.25). State lives on the character, not the slot, so it resets on
-- respawn -- the worn accessories follow the same lifecycle.

local ServerStorage = game:GetService("ServerStorage")

local ItemState = require(ServerStorage.Modules.ItemState)
local Weights = require(ServerStorage.Modules.Weights)

return function(context: ItemState.Context): ()
	local character = context.character
	local params: { [string]: any } = context.def.params or {}
	local weight = (params.weight :: number?) or 0.25
	-- Toggle: equip the configured tonnage if currently off, remove if already on.
	local enabling = character:GetAttribute("WeightTraining") ~= true
	Weights.apply(character, if enabling then weight else 0)
end
