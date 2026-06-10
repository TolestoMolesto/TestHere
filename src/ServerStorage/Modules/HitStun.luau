--!strict
local DURATION = 1.2
local HitStun = {}

-- NOTE: ParryHandler also owns Stunned with its own generation; a character stunned by
-- both at once can be cleared early by whichever timer fires first (known limitation).
local generation = setmetatable({} :: { [Model]: number }, { __mode = "k" })

function HitStun.apply(entityCharacter: Model): ()
	entityCharacter:SetAttribute("NoAttacking", true)
	entityCharacter:SetAttribute("NoBlocking", true)
	entityCharacter:SetAttribute("Stunned", true)

	local gen = (generation[entityCharacter] or 0) + 1
	generation[entityCharacter] = gen

	task.delay(DURATION, function(): ()
		-- Only the latest hit clears the flags; a re-hit bumped the generation.
		if generation[entityCharacter] ~= gen or not entityCharacter.Parent then
			return
		end
		generation[entityCharacter] = nil

		entityCharacter:SetAttribute("NoAttacking", false)
		entityCharacter:SetAttribute("NoBlocking", false)
		entityCharacter:SetAttribute("Stunned", false)
	end)
end

return HitStun
