-- Ability hotkeys. Keys 6-0 toggle the local player's abilities — Forms and Techniques SHARE
-- this row. The server resolves the slot index to the combined ability line and routes each to
-- its bucket, so a form and a technique stack. Keys 1-5 are reserved for Skills (a separate
-- system) and are intentionally NOT bound here. FormConfig is server-only, so no ability data
-- replicates. Transform is a clientManaged action, so CombatClient ignores it and this script
-- owns keys 6-0.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Keybinds = require(ReplicatedStorage.Modules.Keybinds)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

-- Live bind -> ability slot (1-5). Rebuilt whenever the player rebinds a slot key.
local bindToSlot: { [any]: number } = {}
local function rebuild()
	table.clear(bindToSlot)
	for slot = 1, 5 do
		local bind = Keybinds.get("FormSlot" .. slot)
		if bind then
			bindToSlot[bind] = slot
		end
	end
end
rebuild()
Keybinds.onChanged(rebuild)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	local bind = Keybinds.fromInput(input)
	local slot = bind and bindToSlot[bind]
	if slot then
		Remotes.PerformAction:FireServer("Transform", { slot = slot })
	end
end)
