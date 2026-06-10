--!strict
-- Wolf Fang Fist: a fast physical flurry (Yamcha's) with a launching finisher -- quicker and with
-- more strikes than Galick Cannon. Ported onto Shared.meleeHit. The wolf-mesh VFX + dynamic camera
-- are cosmetic and land in Phase 3.

local ServerStorage = game:GetService("ServerStorage")

local Shared = require(ServerStorage.Modules.Skills.Shared)
local SkillState = require(ServerStorage.Modules.SkillState)

local HITS = 6
local HIT_INTERVAL = 0.14
local HIT_SIZE = Vector3.new(6, 6, 6)
local REACH = 3
local FINISHER_SIZE = Vector3.new(9, 9, 9)
local FINISHER_REACH = 4
local FINISHER_KNOCKBACK = 110
local RECOVER_DELAY = 0.4

return function(context: SkillState.Context): ()
	local character = context.character
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local strength = context.def.strength

	Shared.playAnim(character, "WolfFangFist")
	character:SetAttribute("Casting", true)
	root.Anchored = true

	for _ = 1, HITS do
		Shared.meleeHit(character, HIT_SIZE, REACH, strength, nil)
		task.wait(HIT_INTERVAL)
	end

	Shared.meleeHit(character, FINISHER_SIZE, FINISHER_REACH, math.floor(strength * 1.5), FINISHER_KNOCKBACK, {
		shockwave = 2,
		spark = 20,
		hit = 2,
	})

	task.wait(RECOVER_DELAY)
	root.Anchored = false
	character:SetAttribute("Casting", false)
	Shared.stopAnim(character, "WolfFangFist")
end
