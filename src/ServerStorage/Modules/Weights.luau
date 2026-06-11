--!strict
-- Shared training-weights logic: equips/removes the WeightTraining / Weight character attributes (read
-- by Train.weightMult to accelerate gains) AND the four visible limb Accessories (LeftArmWeight,
-- LeftLegWeight, RightArmWeight, RightLegWeight, under ServerStorage.Assets.Items). Used both by the
-- ToggleWeights item (a player weighting themselves) and by a Kai granting weights to a party member
-- (WeightsServer). State lives on the CHARACTER, so it resets on respawn.

local ServerStorage = game:GetService("ServerStorage")

local Assets = ServerStorage:WaitForChild("Assets")
local PlayerRaceBuilder = require(ServerStorage.Modules.PlayerRaceBuilder)

local Weights = {}

-- Lowest equippable tonnage (the Kai grant + the item both floor here; below it means "remove").
Weights.MIN_TONNAGE = 0.25

local WEIGHT_PIECES = { "LeftArmWeight", "LeftLegWeight", "RightArmWeight", "RightLegWeight" }
local WEIGHT_PIECE_SET: { [string]: true } = {}
for _, name in WEIGHT_PIECES do
	WEIGHT_PIECE_SET[name] = true
end

local function strip(character: Model): ()
	for _, acc in character:GetChildren() do
		if acc:IsA("Accessory") and WEIGHT_PIECE_SET[acc.Name] then
			acc:Destroy()
		end
	end
end

local function attach(character: Model): ()
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid then
		return
	end
	local itemsFolder = Assets:FindFirstChild("Items")
	if not itemsFolder then
		warn("[Weights] ServerStorage.Assets.Items folder not found")
		return
	end
	for _, name in WEIGHT_PIECES do
		local template = itemsFolder:FindFirstChild(name)
		if template and template:IsA("Accessory") then
			-- Scaled to the body so weights fit an age-shrunk character instead of arriving full-size.
			PlayerRaceBuilder.addScaledAccessory(humanoid, character, template)
		else
			warn("[Weights] Weight accessory not found:", name)
		end
	end
end

-- Set the character's training weights. tonnage > 0 equips that many tons (+ the visible pieces);
-- tonnage <= 0 removes them. Always clears first so re-equipping never stacks a second set.
function Weights.apply(character: Model, tonnage: number): ()
	strip(character)
	if tonnage > 0 then
		character:SetAttribute("WeightTraining", true)
		character:SetAttribute("Weight", tonnage)
		attach(character)
	else
		character:SetAttribute("WeightTraining", false)
		character:SetAttribute("Weight", false)
	end
end

return Weights
