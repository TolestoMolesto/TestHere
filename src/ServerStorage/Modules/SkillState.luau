--!strict
-- Runtime controller for the Skill bucket (hotkeys 1-5): the counterpart to FormState. Resolves a
-- loadout index to the equipped skill, gates the cast (unlocked / cooldown / state / Ki), spends
-- Ki, starts the cooldown, then runs the skill's behavior module. Behaviors live under
-- ServerStorage.Modules.Skills and are required lazily (like the combat handlers in CombatServer)
-- so a missing place-side behavior never hangs boot. The cast is authoritative here -- the client
-- only requests; every gate is re-checked server-side.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local Manager = require(ServerStorage.Modules.Manager)
local SkillConfig = require(ServerStorage.Modules.SkillConfig)

export type Context = {
	character: Model,
	player: Player,
	skillId: string,
	def: SkillConfig.SkillDef,
	aim: CFrame?, -- mouse-hit CFrame the client sent (nil = aim from the caster's look vector)
}

local SkillState = {}

local function cooldownAttr(skillId: string): string
	return `Skill_{skillId}_ReadyAt`
end

-- Returns a variadic-return type so `pcall(behavior, ...)` typechecks as (boolean, ...any); the
-- behaviors themselves return nothing.
local function getBehavior(name: string): ((Context) -> ...any)?
	local folder = ServerStorage.Modules:FindFirstChild("Skills")
	local moduleScript = folder and folder:FindFirstChild(name)
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		warn(`[SkillState] No behavior module 'Skills.{name}'; skill does nothing yet.`)
		return nil
	end
	local ok, result = pcall(require, moduleScript)
	if not ok or type(result) ~= "function" then
		warn(`[SkillState] Behavior 'Skills.{name}' failed to load or isn't a function: {tostring(result)}`)
		return nil
	end
	return result :: (Context) -> ...any
end

-- Shared cast gates. False if the character can't act right now.
local function canCast(character: Model): boolean
	if not character.Parent then
		return false
	end
	return not (
		character:GetAttribute("Casting")
		or character:GetAttribute("Stunned")
		or character:GetAttribute("HitByKnockBack")
		or character:GetAttribute("Resting")
		or character:GetAttribute("ToggleRagdoll")
		or character:GetAttribute("InCustomization")
	)
end

-- Cast a specific skill id (already resolved). Runs every gate, spends Ki, starts the cooldown,
-- then spawns the behavior. NPC/shadow casting (no Player) is not supported yet -- callers should
-- only reach this for player characters.
function SkillState.use(character: Model, skillId: string, aim: CFrame?): ()
	local def = SkillConfig.get(skillId)
	if not def then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	local slot = Manager.getActiveSlot(player)
	if not slot then
		return
	end
	-- Must be unlocked on this slot.
	if not (slot.UnlockedSkills and slot.UnlockedSkills[skillId]) then
		return
	end
	if not canCast(character) then
		return
	end
	-- Cooldown gate. Uses the synced server clock so the client HUD can render the sweep accurately.
	local readyAt = character:GetAttribute(cooldownAttr(skillId)) :: number?
	if readyAt and workspace:GetServerTimeNow() < readyAt then
		return
	end
	-- Ki gate + spend.
	local ki = (character:GetAttribute("Ki") :: number?) or 0
	if ki < def.kiCost then
		return
	end
	if def.kiCost > 0 then
		character:SetAttribute("Ki", ki - def.kiCost)
	end
	-- Cooldown starts on cast begin (matches the old per-skill IntValue cooldowns).
	if def.cooldown > 0 then
		character:SetAttribute(cooldownAttr(skillId), workspace:GetServerTimeNow() + def.cooldown)
	end

	local behavior = getBehavior(def.behavior)
	if not behavior then
		return
	end

	local context: Context = {
		character = character,
		player = player,
		skillId = skillId,
		def = def,
		aim = aim,
	}
	task.spawn(function()
		local ok, err = pcall(behavior, context)
		if not ok then
			warn(`[SkillState] Skill '{skillId}' behavior errored: {tostring(err)}`)
			-- Best-effort: clear the cast flags a crashed behavior may have left set.
			character:SetAttribute("Casting", false)
			character:SetAttribute("Stunned", false)
		end
	end)
end

-- Client entry: resolve a loadout index (1-5) on the active slot to its equipped skill id.
function SkillState.useByIndex(character: Model, index: number, aim: CFrame?): ()
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	local slot = Manager.getActiveSlot(player)
	if not slot then
		return
	end
	local loadout = slot.SkillLoadout
	local skillId = loadout and loadout[index]
	if type(skillId) == "string" and skillId ~= "" then
		SkillState.use(character, skillId, aim)
	end
end

return SkillState
