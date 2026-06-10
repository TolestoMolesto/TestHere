--!strict
local Rest = {}

local DEBOUNCE_SECONDS = 1
local START_BLOCKERS = { "CombatTag", "ToggleRagdoll", "Charging", "Blocking" }

local debounce = setmetatable({} :: { [Model]: boolean }, { __mode = "k" })

function Rest.toggle(character: Model): boolean
	local resting = character:GetAttribute("Resting") == true

	if debounce[character] then
		return resting
	end

	if not resting then
		for _, attribute in START_BLOCKERS do
			if character:GetAttribute(attribute) then
				return resting
			end
		end
	end

	debounce[character] = true
	character:SetAttribute("Resting", not resting)

	task.delay(DEBOUNCE_SECONDS, function()
		debounce[character] = nil
	end)

	return not resting
end

return Rest
