local Block = {}

local PERFECT_BLOCK_WINDOW = 0.2

-- Window generation: a stale window's expiry must not clear a newer block's flag.
local generation = setmetatable({}, { __mode = "k" })

local function canBlock(character: Model): boolean
	if character:GetAttribute("Blocking") then
		return false
	end
	if
		character:GetAttribute("Stunned")
		or character:GetAttribute("HitByKnockBack")
		or character:GetAttribute("Attacking")
		or character:GetAttribute("NoBlocking")
		or character:GetAttribute("BlockBroken")
		or not character:GetAttribute("CanBlock")
	then
		return false
	end
	return ((character:GetAttribute("Stamina") :: number?) or 0) > 0
end

function Block.start(character: Model, perfectWindow: number?): boolean
	if not character or not character.Parent or not canBlock(character) then
		return false
	end

	character:SetAttribute("Blocking", true)
	character:SetAttribute("PerfectBlocked", true)

	local gen = (generation[character] or 0) + 1
	generation[character] = gen

	task.delay(perfectWindow or PERFECT_BLOCK_WINDOW, function(): ()
		if character and character.Parent and generation[character] == gen then
			character:SetAttribute("PerfectBlocked", false)
		end
	end)

	return true
end

function Block.stop(character: Model): ()
	if not character then
		return
	end
	character:SetAttribute("Blocking", false)
	character:SetAttribute("PerfectBlocked", false)
end

return Block
