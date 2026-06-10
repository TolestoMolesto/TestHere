--!strict
-- Item behavior: toggles training weights on the player's current character. Flips the WeightTraining /
-- Weight attributes (a state flag) AND wears/removes the four visible weight Accessories on the limbs
-- (LeftArmWeight, LeftLegWeight, RightArmWeight, RightLegWeight, under ServerStorage.Assets.Items). Weight
-- amount is read from params.weight, defaulting to 0.25. State lives on the character, not the slot, so it
-- resets on respawn -- the worn accessories follow the same lifecycle.

local ServerStorage = game:GetService("ServerStorage")

local ItemState = require(ServerStorage.Modules.ItemState)

local Assets = ServerStorage:WaitForChild("Assets")

-- The four limb weights, all Accessories under Assets.Items.
local WEIGHT_PIECES = { "LeftArmWeight", "LeftLegWeight", "RightArmWeight", "RightLegWeight" }
local WEIGHT_PIECE_SET: { [string]: true } = {}
for _, name in WEIGHT_PIECES do
	WEIGHT_PIECE_SET[name] = true
end

local function stripWeights(character: Model)
	for _, acc in character:GetChildren() do
		if acc:IsA("Accessory") and WEIGHT_PIECE_SET[acc.Name] then
			acc:Destroy()
		end
	end
end

local function attachWeights(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid then
		return
	end
	local itemsFolder = Assets:FindFirstChild("Items")
	if not itemsFolder then
		warn("[ToggleWeights] ServerStorage.Assets.Items folder not found")
		return
	end
	for _, name in WEIGHT_PIECES do
		local template = itemsFolder:FindFirstChild(name)
		if template and template:IsA("Accessory") then
			humanoid:AddAccessory(template:Clone())
		else
			warn("[ToggleWeights] Weight accessory not found:", name)
		end
	end
end

return function(context: ItemState.Context): ()
	local character = context.character
	local params: { [string]: any } = context.def.params or {}
	local weight = (params.weight :: number?) or 0.25
	local enabling = character:GetAttribute("WeightTraining") ~= true

	-- Always clear first, so equipping never stacks a second set and unequipping removes the pieces.
	stripWeights(character)

	if enabling then
		character:SetAttribute("WeightTraining", true)
		character:SetAttribute("Weight", weight)
		attachWeights(character)
	else
		character:SetAttribute("WeightTraining", false)
		character:SetAttribute("Weight", false)
	end
end
