--!strict
-- Galick Cannon: a rushing physical combo -- a flurry of strikes capped by a launching finisher.
-- Ported from GlobalSkillSet onto Shared.meleeHit. The legacy version scheduled hits 2-5 TWICE (a
-- real double-hit bug, ~9 hits for a "5-hit combo"); this fires one clean sequence. Light hits
-- carry no knockback so the target stays in range; only the finisher launches. The 2D-camera +
-- impact-frame cutscene is cosmetic and lands in Phase 3.

local ServerStorage = game:GetService("ServerStorage")

local Shared = require(ServerStorage.Modules.Skills.Shared)
local SkillState = require(ServerStorage.Modules.SkillState)

local HITS = 5
local HIT_INTERVAL = 0.18
local HIT_SIZE = Vector3.new(6, 6, 6)
local REACH = 3
local FINISHER_SIZE = Vector3.new(10, 10, 10)
local FINISHER_REACH = 5
local FINISHER_KNOCKBACK = 150
local RECOVER_DELAY = 0.4

return function(context: SkillState.Context): ()
	local character = context.character
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local strength = context.def.strength

	Shared.playAnim(character, "GalickCannon")
	character:SetAttribute("Casting", true)
	root.Anchored = true

	for _ = 1, HITS do
		Shared.meleeHit(character, HIT_SIZE, REACH, strength, nil)
		task.wait(HIT_INTERVAL)
	end

	-- Finisher: heavier hit that launches everyone still in range.
	Shared.meleeHit(character, FINISHER_SIZE, FINISHER_REACH, strength * 2, FINISHER_KNOCKBACK, {
		shockwave = 2,
		spark = 25,
		hit = 2,
	})

	task.wait(RECOVER_DELAY)
	root.Anchored = false
	character:SetAttribute("Casting", false)
	Shared.stopAnim(character, "GalickCannon")
end
