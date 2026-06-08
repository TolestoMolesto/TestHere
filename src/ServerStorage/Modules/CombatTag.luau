--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Manager = require(ServerStorage.Modules.Manager)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local COMBAT_TAG_EXTEND_BY = 30
local COMBAT_TAG_MAX_DURATION = 180
local CombatTag = {}

local function getStatus(character: Model): Folder?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return if humanoid then humanoid:FindFirstChild("Status") :: Folder? else nil
end

local function clearCombatTag(character: Model): ()
	if not character or not character.Parent then
		return
	end

	local status = getStatus(character)
	if not status then return end

	status:SetAttribute("CombatTag", false)
	status:SetAttribute("CombatTimerRunning", false)
	status:SetAttribute("CombatTime", 0)

	local playerFound = Players:GetPlayerFromCharacter(character)

	if playerFound then
		local playerProfile = Manager.getProfile(playerFound)
		playerProfile.Data.Stats.CombatTag = false

		Remotes.CombatTagEnded:FireClient(playerFound)
	end
end

local function startCombatTimer(character: Model): ()
	if not character or not character:IsDescendantOf(game) then
		return
	end

	local status = getStatus(character)
	if not status then return end

	local now = os.time()
	local currentTime = status:GetAttribute("CombatTime") or 0

	local newExpire
	if now >= currentTime then
		newExpire = now + COMBAT_TAG_EXTEND_BY
	else
		newExpire = math.min(currentTime + COMBAT_TAG_EXTEND_BY, now + COMBAT_TAG_MAX_DURATION)
	end

	status:SetAttribute("CombatTime", newExpire)
	status:SetAttribute("CombatTag", true)

	if status:GetAttribute("CombatTimerRunning") then
		return
	end

	status:SetAttribute("CombatTimerRunning", true)

	local playerFound = Players:GetPlayerFromCharacter(character)
	if playerFound then
		Remotes.CombatTagged:FireClient(playerFound)
	end

	task.spawn(function()
		while character and character.Parent and status:GetAttribute("CombatTimerRunning") do
			local expireTime = status:GetAttribute("CombatTime") or 0
			if os.time() >= expireTime then
				break
			end
			task.wait(1)
		end

		clearCombatTag(character)
	end)
end

function CombatTag.applyCombatTag(attackerPlayer: Player, targetCharacter: Model): ()
	local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	if not targetPlayer then
		return
	end

	local attackerCharacter = attackerPlayer.Character
	if attackerCharacter then
		startCombatTimer(attackerCharacter)

		local attackerProfile = Manager.getProfile(attackerPlayer)
		if attackerProfile then
			attackerProfile.Data.Stats.CombatTag = true
		end
	end

	startCombatTimer(targetCharacter)

	local targetProfile = Manager.getProfile(targetPlayer)
	if targetProfile then
		targetProfile.Data.Stats.CombatTag = true
	end
end

function CombatTag.forceClearCombatTag(player: Player): ()
	clearCombatTag(player.Character :: Model)
end

local function isTagged(character: Model): boolean
	local status = getStatus(character)
	if not status then return false end
	return status:GetAttribute("CombatTag") == true and (status:GetAttribute("CombatTime") or 0) > os.time()
end

function CombatTag.isInCombat(player: Player): boolean
	local character = player.Character
	if not character then return false end
	return isTagged(character)
end

return CombatTag
