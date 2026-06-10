--!strict
-- Item behavior: toggles equipped training weights on the player's current character.
-- Weight amount is read from params.weight, defaulting to 0.25.

local ServerStorage = game:GetService("ServerStorage")

local ItemState = require(ServerStorage.Modules.ItemState)

return function(context: ItemState.Context): ()
	local character = context.player.Character
	if not character then
		return
	end

	local params: { [string]: any } = context.def.params or {}
	local weight = (params.weight :: number?) or 0.25
	local hasWeight = character:GetAttribute("WeightTraining") == true

	if hasWeight then
		character:SetAttribute("WeightTraining", false)
		character:SetAttribute("Weight", false)
	else
		character:SetAttribute("WeightTraining", true)
		character:SetAttribute("Weight", weight)
	end
end