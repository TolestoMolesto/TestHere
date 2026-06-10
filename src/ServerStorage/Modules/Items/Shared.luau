--!strict
-- Small helpers shared by Item behavior modules. Deliberately lean (NOT the heavy combat
-- Skills/Shared): items mostly top up the user's own resources. Health is the Humanoid's; Ki and
-- Stamina are character attributes (MaxKi / MaxStamina), matching the rest of the combat code.

local ItemsShared = {}

function ItemsShared.humanoid(character: Model): Humanoid?
	return character:FindFirstChildOfClass("Humanoid") :: Humanoid?
end

-- True while the character is a live, usable target.
function ItemsShared.isAlive(character: Model): boolean
	local humanoid = ItemsShared.humanoid(character)
	return humanoid ~= nil and humanoid.Health > 0
end

-- Add `amount` Health, clamped to MaxHealth. No-op on a dead/missing humanoid.
function ItemsShared.healHealth(character: Model, amount: number): ()
	local humanoid = ItemsShared.humanoid(character)
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	humanoid.Health = math.min(humanoid.Health + amount, humanoid.MaxHealth)
end

-- Add `amount` to an attribute-backed resource ("Ki" -> "MaxKi", "Stamina" -> "MaxStamina"),
-- clamped to its max attribute.
function ItemsShared.restoreAttribute(character: Model, attr: string, maxAttr: string, amount: number): ()
	local current = (character:GetAttribute(attr) :: number?) or 0
	local max = (character:GetAttribute(maxAttr) :: number?) or 0
	character:SetAttribute(attr, math.min(current + amount, max))
end

return ItemsShared
