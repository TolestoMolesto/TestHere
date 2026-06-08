--!strict
local DURATION = 1.2
local HitStun = {}

function HitStun.apply(entityCharacter: Model): ()
	entityCharacter:SetAttribute("NoAttacking", true)
	entityCharacter:SetAttribute("NoBlocking", true)
	entityCharacter:SetAttribute("Stunned", true)

	task.delay(DURATION, function(): ()
		if not entityCharacter or not entityCharacter.Parent then
			return
		end

		entityCharacter:SetAttribute("NoAttacking", false)
		entityCharacter:SetAttribute("NoBlocking", false)
		entityCharacter:SetAttribute("Stunned", false)
	end)
end

return HitStun
