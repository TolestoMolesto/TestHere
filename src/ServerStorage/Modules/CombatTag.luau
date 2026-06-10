--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Modules.Remotes)

local COMBAT_TAG_EXTEND_BY = 30
local COMBAT_TAG_MAX_DURATION = 180
local CombatTag = {}

local function clearCombatTag(character: Model): ()
	if not character or not character.Parent then
		return
	end

	character:SetAttribute("CombatTag", false)
	character:SetAttribute("CombatTimerRunning", false)
	character:SetAttribute("CombatTime", 0)

	local playerFound = Players:GetPlayerFromCharacter(character)
	if playerFound then
		Remotes.CombatTagEnded:FireClient(playerFound)
	end
end

local function startCombatTimer(character: Model): ()
	if not character or not character:IsDescendantOf(game) then
		return
	end

	local now = os.time()
	local currentTime = character:GetAttribute("CombatTime") :: number? or 0

	local newExpire
	if now >= currentTime then
		newExpire = now + COMBAT_TAG_EXTEND_BY
	else
		newExpire = math.min(currentTime + COMBAT_TAG_EXTEND_BY, now + COMBAT_TAG_MAX_DURATION)
	end

	character:SetAttribute("CombatTime", newExpire)
	character:SetAttribute("CombatTag", true)

	if character:GetAttribute("CombatTimerRunning") then
		return
	end

	character:SetAttribute("CombatTimerRunning", true)

	local playerFound = Players:GetPlayerFromCharacter(character)
	if playerFound then
		Remotes.CombatTagged:FireClient(playerFound)
	end

	task.spawn(function()
		while character and character.Parent and character:GetAttribute("CombatTimerRunning") do
			local expireTime = character:GetAttribute("CombatTime") :: number? or 0
			if os.time() >= expireTime then
				break
			end
			task.wait(1)
		end

		clearCombatTag(character)
	end)
end

function CombatTag.applyCombatTag(attackerCharacter: Model, targetCharacter: Model): ()
	-- A shadow is a private sparring partner; fighting one never puts either side in combat.
	if attackerCharacter:GetAttribute("IsShadow") or targetCharacter:GetAttribute("IsShadow") then
		return
	end
	startCombatTimer(attackerCharacter)
	startCombatTimer(targetCharacter)
end

function CombatTag.forceClearCombatTag(character: Model): ()
	clearCombatTag(character)
end

function CombatTag.isInCombat(character: Model): boolean
	return character:GetAttribute("CombatTag") == true
		and (character:GetAttribute("CombatTime") :: number? or 0) > os.time()
end

return CombatTag
