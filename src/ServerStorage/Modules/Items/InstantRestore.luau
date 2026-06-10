--!strict
-- Item behavior: instantly restore resources, each by `fraction * max` (clamped to max). Reads
-- params.health / params.ki / params.stamina (each a fraction of that resource's max; default 0).
-- Used by SenzuBean ({ health = 1, ki = 1, stamina = 1 } = a full heal). Behaviors never consume the
-- item -- ItemState does that up front.

local ServerStorage = game:GetService("ServerStorage")

local Shared = require(ServerStorage.Modules.Items.Shared)
local ItemState = require(ServerStorage.Modules.ItemState)

return function(context: ItemState.Context): ()
	local character = context.character
	local params: { [string]: any } = context.def.params or {}

	local humanoid = Shared.humanoid(character)
	if humanoid then
		local healFrac = (params.health :: number?) or 0
		if healFrac > 0 then
			Shared.healHealth(character, humanoid.MaxHealth * healFrac)
		end
	end

	local kiFrac = (params.ki :: number?) or 0
	if kiFrac > 0 then
		local maxKi = (character:GetAttribute("MaxKi") :: number?) or 0
		Shared.restoreAttribute(character, "Ki", "MaxKi", maxKi * kiFrac)
	end

	local stamFrac = (params.stamina :: number?) or 0
	if stamFrac > 0 then
		local maxStam = (character:GetAttribute("MaxStamina") :: number?) or 0
		Shared.restoreAttribute(character, "Stamina", "MaxStamina", maxStam * stamFrac)
	end
end
