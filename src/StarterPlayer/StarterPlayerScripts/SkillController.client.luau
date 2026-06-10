-- Skill hotkeys. Keys 1-5 cast the local player's EQUIPPED skills (the offensive bucket), the
-- counterpart to FormController's 6-0 ability row. Each key maps to a loadout index (1-5); the
-- server resolves the index to the equipped skill id on the active slot and runs its behavior.
-- SkillConfig is server-only, so no skill data replicates -- we only send the index + an aim CFrame
-- (mouse hit). Skill is a clientManaged action, so CombatClient ignores it and this script owns
-- keys 1-5. Mirror of FormController.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Keybinds = require(ReplicatedStorage.Modules.Keybinds)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local player = Players.LocalPlayer
local mouse = player:GetMouse()

-- Live bind -> skill slot (1-5). Rebuilt whenever the player rebinds a slot key.
local bindToSlot: { [any]: number } = {}
local function rebuild()
	table.clear(bindToSlot)
	for slot = 1, 5 do
		local bind = Keybinds.get("SkillSlot" .. slot)
		if bind then
			bindToSlot[bind] = slot
		end
	end
end
rebuild()
Keybinds.onChanged(rebuild)

-- Cheap local gate so dead keypresses don't spam the server; the server re-checks authoritatively.
local function canCast(character: Model): boolean
	return not (
		character:GetAttribute("Casting")
		or character:GetAttribute("Stunned")
		or character:GetAttribute("HitByKnockBack")
		or character:GetAttribute("Resting")
	)
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	local bind = Keybinds.fromInput(input)
	local slot = bind and bindToSlot[bind]
	if not slot then
		return
	end
	local character = player.Character
	if not character or not canCast(character) then
		return
	end
	Remotes.PerformAction:FireServer("Skill", { slot = slot, cframe = mouse.Hit })
end)
