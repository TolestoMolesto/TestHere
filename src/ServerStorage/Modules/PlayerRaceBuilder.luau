--!strict

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local Manager = require(ServerStorage.Modules.Manager)
local Assets = ServerStorage:WaitForChild("Assets")

type RGBColor = { R: number, G: number, B: number }

local UNSET = "NA" -- sentinel: slot field not yet assigned
local RNG = Random.new()
local WHITE = Color3.fromRGB(255, 255, 255)

local RACE_HEADS: { [string]: Accessory } = {
	Acrosian = Assets.Heads.Acrosian.One :: Accessory,
	Majin = Assets.Heads.Majin.One :: Accessory,
	Namekian = Assets.Heads.Namekian.One :: Accessory,
	Sphinx = Assets.Heads.Sphinx.One :: Accessory,
}

local TAIL_RACES: { [string]: true } = {
	Saiyan = true,
	LegendarySuperSaiyan = true,
}

local HAIR_RACES: { [string]: true } = {
	Human = true,
	Saiyan = true,
	LegendarySuperSaiyan = true,
}

local SPHINX_TAIL_RACES: { [string]: true } = {
	Sphinx = true,
	Acrosian = true,
}

local DEFAULT_FACES: { [string]: { Eyes: string, Mouth: string, Nose: string } } = {
	Acrosian = { Eyes = "AcrosianEye1", Mouth = "AcrosianMouth1", Nose = "AcrosianNose1" },
	Majin = { Eyes = "MajinEye1", Mouth = "MajinMouth1", Nose = "MajinNose1" },
	Namekian = { Eyes = "NamekianEyes1", Mouth = "NamekianMouth1", Nose = "NamekianNose1" },
	Sphinx = { Eyes = "SphinxEye1", Mouth = "SphinxMouth1", Nose = "SphinxNose1" },
	Saiyan = { Eyes = "MaleEye1", Mouth = "Mouth1", Nose = "Nose1" },
	LegendarySuperSaiyan = { Eyes = "MaleEye1", Mouth = "Mouth1", Nose = "Nose1" },
	Human = { Eyes = "MaleEye1", Mouth = "Mouth1", Nose = "Nose1" },
}

local RACE_SIZES: { [string]: number } = {
	Acrosian = 1.0,
	Namekian = 1.0,
	Saiyan = 1.0,
	LegendarySuperSaiyan = 1.0,
	Sphinx = 1.0,
	Human = 1.0,
	Majin = 1.0,
}

local OUTFIT_EXTRAS: { [string]: { string } } = {
	TrainingGi = {
		"TrainingGiUnderShirt",
		"TrainingGiBelt",
		"TrainingGiShoeLeft",
		"TrainingGiShoeRight",
		"TrainingGiLeftShoulder",
		"TrainingGiRightShoulder",
		"TrainingGiUnderLeftShoulder",
		"TrainingGiUnderRightShoulder",
	},
	CraneSchoolGi = {
		"CraneSchoolGiTorso",
		"CraneSchoolGiBelt",
		"CraneSchoolGiArmBandLeft",
		"CraneSchoolGienArmBandRight",
		"CraneSchoolGiArmRingsLeft",
		"CraneSchoolGiArmRingsRight",
		"CraneSchoolGiLegBandLeft",
		"CraneSchoolGiLegBandRight",
		"CraneSchoolGiShoeLeft",
		"CraneSchoolGiShoeRight",
	},
	VampaWarrior = {
		"VampaWarriorTorso",
		"VampaWarriorNeck",
		"VampaWarriorLeftSleeve",
		"VampaWarriorRightSleeve",
		"VampaWarriorArmRingsLeft",
		"VampaWarriorArmRingsRight",
		"VampaWarriorBandLeft",
		"VampaWarriorBandRight",
		"VampaWarriorLegBandLeft",
		"VampaWarriorLegRingsLeft",
		"VampaWarriorLegRingsRight",
		"VampaWarriorLegPadRight",
		"VampaWarriorShoeLeft",
		"VampaWarriorShoeRight",
	},
	MajinVegeta = {
		"MajinVegetaTorso",
		"MajinVegetaShoeLeft",
		"MajinVegetaShoeRight",
		"MajinVegetaLeftGlove",
		"MajinVegetaRightGlove",
	},
}

local CLOTHING_PATTERNS = {
	"Shirt",
	"Pants",
	"Waist",
	"Belt",
	"Shoe",
	"Shoulder",
	"Glove",
	"Torso",
	"Arm",
	"Leg",
}

local bodyDecalLookup: { [string]: Shirt | Pants } = {}
local clothesLookup: { [string]: Accessory } = {}

for _, v in Assets.BodyDecals:GetDescendants() do
	if v:IsA("Shirt") or v:IsA("Pants") then
		bodyDecalLookup[v.Name] = v :: Shirt | Pants
	end
end

for _, v in Assets.Clothes:GetDescendants() do
	if v:IsA("Accessory") then
		clothesLookup[v.Name] = v :: Accessory
	end
end

local function toColor3(rgb: RGBColor): Color3
	return Color3.fromRGB(rgb.R, rgb.G, rgb.B)
end

local function toRGB(c: Color3): RGBColor
	return {
		R = math.floor(c.R * 255),
		G = math.floor(c.G * 255),
		B = math.floor(c.B * 255),
	}
end

local function randomColor3(): Color3
	return Color3.fromRGB(RNG:NextInteger(0, 255), RNG:NextInteger(0, 255), RNG:NextInteger(0, 255))
end

local function colorAccessory(acc: Accessory, body: Color3, hair: Color3, ki: Color3)
	for _, part in acc:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		if CollectionService:HasTag(part, "BodyColor") then
			part.Color = body
		elseif CollectionService:HasTag(part, "HairColor") then
			part.Color = hair
		elseif CollectionService:HasTag(part, "KiColor") then
			part.Color = ki
		end
	end
end

local function addAccessory(humanoid: Humanoid, template: Accessory, body: Color3, hair: Color3, ki: Color3)
	local acc = template:Clone()
	colorAccessory(acc, body, hair, ki)
	humanoid:AddAccessory(acc)
end

local function applyBodyColors(character: Model, color: Color3)
	local existing = character:FindFirstChild("Body Colors")
	if existing then
		existing:Destroy()
	end
	local bc = Assets.Skins.RaceColors:Clone()
	bc.HeadColor3 = color
	bc.TorsoColor3 = color
	bc.LeftArmColor3 = color
	bc.RightArmColor3 = color
	bc.LeftLegColor3 = color
	bc.RightLegColor3 = color
	bc.Parent = character
end

local function ensureWaistAttachment(character: Model)
	local torso = character:FindFirstChild("Torso") :: BasePart?
	if not torso then
		return
	end
	if not torso:FindFirstChild("WaistBackAttachment") then
		local att = Instance.new("Attachment")
		att.Name = "WaistBackAttachment"
		att.Position = Vector3.new(0, 1, 1)
		att.Parent = torso
	end
end

local function generateRaceColours(slot: any)
	local race = slot.Race :: string
	local raceFolder = (
		Assets.Skins.RaceColors:FindFirstChild(race) or Assets.Skins.RaceColors:FindFirstChild("Human")
	) :: Folder
	local colours = raceFolder:GetChildren()

	local bodyRGB: RGBColor
	if race == "GOD" then
		bodyRGB = toRGB(randomColor3())
	else
		local picked = colours[RNG:NextInteger(1, #colours)] :: Color3Value
		bodyRGB = toRGB(picked.Value)
	end

	local hairRGB: RGBColor
	if race == "ANGEL" then
		hairRGB = toRGB(WHITE)
	elseif race == "Acrosian" or race == "Majin" or race == "Namekian" or race == "Sphinx" or race == "KAI" then
		hairRGB = bodyRGB
	else
		hairRGB = toRGB(randomColor3())
	end

	slot.BodyColor = bodyRGB
	slot.HairColor = hairRGB
end

local function generateKiColour(slot: any)
	slot.KiColor = toRGB(randomColor3())
end

local function stripHair(character: Model)
	for _, acc in character:GetChildren() do
		if not acc:IsA("Accessory") then
			continue
		end
		for _, gender in { "Male", "Female" } do
			local gf = Assets.Hairs:FindFirstChild(gender)
			if gf and gf:FindFirstChild(acc.Name) then
				acc:Destroy()
				break
			end
		end
	end
end

local function rollHair(slot: any, gender: string): Accessory?
	local folder = Assets.Hairs:FindFirstChild(gender)
	if not folder then
		return nil
	end
	local hairs = folder:GetChildren()
	if #hairs == 0 then
		return nil
	end
	local chosen = hairs[RNG:NextInteger(1, #hairs)]
	slot.Hair = chosen.Name
	return chosen:Clone() :: Accessory
end

local function applyHair(
	humanoid: Humanoid,
	character: Model,
	slot: any,
	gender: string,
	body: Color3,
	hair: Color3,
	ki: Color3
)
	stripHair(character)
	local folder = Assets.Hairs:FindFirstChild(gender)
	local saved = folder and slot.Hair ~= UNSET and folder:FindFirstChild(slot.Hair) :: Accessory?
	local chosen = if saved then saved:Clone() else rollHair(slot, gender)
	if not chosen then
		return
	end
	colorAccessory(chosen, body, hair, ki)
	humanoid:AddAccessory(chosen)
end

local function applyBodyDecal(character: Model, race: string, gender: string, base: string)
	local shirtKey = if race == "Namekian" then "Namekian" .. base .. "Shirt" else gender .. base .. "Shirt"
	local pantKey = gender .. base .. "Pant"

	local shirt = bodyDecalLookup[shirtKey]
	local pant = bodyDecalLookup[pantKey]

	if shirt then
		local cloned = (shirt :: Instance):Clone()
		cloned.Parent = character
	else
		warn("[PlayerRaceBuilder] BodyDecal shirt not found:", shirtKey)
	end

	if pant then
		local cloned = (pant :: Instance):Clone()
		cloned.Parent = character
	else
		warn("[PlayerRaceBuilder] BodyDecal pant not found:", pantKey)
	end
end

local function stripClothing(character: Model)
	for _, acc in character:GetChildren() do
		if not acc:IsA("Accessory") then
			continue
		end
		for _, pat in CLOTHING_PATTERNS do
			if acc.Name:find(pat) then
				acc:Destroy()
				break
			end
		end
	end
end

local function resolveOutfit(gender: string, name: string): string
	if name == "Starter" or name == "SaiyanStarter" then
		name = "NewStarterFit"
	end
	if gender == "Female" and (name == "NewStarterFit") then
		return "StarterFemale"
	end
	return name
end

local function applyClothing(humanoid: Humanoid, character: Model, slot: any, gender: string)
	stripClothing(character)

	local hasOutfit = slot.ClothingOutfit ~= UNSET and slot.ClothingOutfit ~= ""
	local shirtName = resolveOutfit(gender, if hasOutfit then slot.ClothingOutfit else slot.Shirt)
	local pantsName = resolveOutfit(gender, if hasOutfit then slot.ClothingOutfit else slot.Pants)

	local function addPiece(key: string)
		local acc = clothesLookup[key]
		if acc then
			humanoid:AddAccessory(acc:Clone())
		else
			warn("[PlayerRaceBuilder] Clothing piece not found:", key)
		end
	end

	addPiece(shirtName .. "Shirt")
	addPiece(pantsName .. "PantsLeft")
	addPiece(pantsName .. "PantsRight")

	local extras = OUTFIT_EXTRAS[shirtName] or OUTFIT_EXTRAS[pantsName]
	if extras then
		for _, part in extras do
			addPiece(part)
		end
	end
end

local function getFaceFolder(race: string): Folder?
	return (Assets.Faces:FindFirstChild(race) or Assets.Faces:FindFirstChild("Human")) :: Folder?
end

local function applyGender(gender: string, name: string): string
	return if gender == "Female" then name:gsub("^Male", "Female") else name
end

local function toPupilName(eyeName: string): string?
	local name = eyeName:gsub("Eyes", "Pupil"):gsub("Eye", "Pupil")
	return if name ~= eyeName then name else nil
end

local function getFaceDecal(race: string, category: string, assetName: string?): Decal?
	if not assetName or assetName == UNSET or assetName == "" then
		return nil
	end
	local folder = getFaceFolder(race)
	if not folder then
		return nil
	end
	local cat = folder:FindFirstChild(category)
	if not cat then
		return nil
	end
	local found = cat:FindFirstChild(assetName)
	if found and found:IsA("Decal") then
		return found :: Decal
	end
	-- fall back to male variant when a female asset is missing
	if assetName:find("^Female") then
		local male = assetName:gsub("^Female", "Male")
		local fb = cat:FindFirstChild(male)
		if fb and fb:IsA("Decal") then
			return fb :: Decal
		end
	end
	return nil
end

local function isValidFaceAsset(race: string, category: string, name: string?): boolean
	if not name or name == UNSET or name == "" then
		return false
	end
	local folder = getFaceFolder(race)
	if not folder then
		return false
	end
	local cat = folder:FindFirstChild(category)
	return cat ~= nil and cat:FindFirstChild(name) ~= nil
end

local function applyFace(character: Model, race: string, gender: string, slot: any)
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end

	for _, c in head:GetChildren() do
		if c:IsA("Decal") or c:IsA("SurfaceGui") then
			c:Destroy()
		end
	end
	local existing = head:FindFirstChild("HeadModel")
	if existing then
		existing:Destroy()
	end

	local defaults = DEFAULT_FACES[race] or DEFAULT_FACES.Human
	local function resolve(category: string, saved: string?, default: string): string
		local g = applyGender(gender, if saved ~= nil then saved else UNSET)
		if isValidFaceAsset(race, category, g) then
			return g
		end
		local gd = applyGender(gender, default)
		if isValidFaceAsset(race, category, gd) then
			return gd
		end
		return default
	end

	slot.Eyes = resolve("Eyes", slot.Eyes, defaults.Eyes)
	slot.Mouth = resolve("Mouth", slot.Mouth, defaults.Mouth)
	slot.Nose = resolve("Nose", slot.Nose, defaults.Nose)

	local headModel = Instance.new("Model")
	headModel.Name = "HeadModel"
	headModel.Parent = head

	local newHead = Instance.new("Part")
	newHead.Name = "NewHead"
	newHead.Size = Vector3.new(2, 1, 1)
	newHead.CanTouch = false
	newHead.CanQuery = false
	newHead.CanCollide = false
	newHead.Massless = true
	newHead.Color = head.Color
	newHead.Material = Enum.Material.SmoothPlastic
	newHead.CFrame = head.CFrame
	newHead.Parent = headModel
	headModel.PrimaryPart = newHead

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = newHead

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = newHead
	weld.Part1 = head
	weld.Parent = newHead
	head.Transparency = 1

	-- draw order matters: Pupils must be under Eyes
	local function applyDecal(category: string, name: string?, label: string)
		local decal = getFaceDecal(race, category, name)
		if not decal then
			return
		end
		local clone = decal:Clone()
		clone.Name = label
		clone.Face = Enum.NormalId.Front
		clone.Parent = newHead
	end

	applyDecal("Eyes", toPupilName(slot.Eyes), "Pupils")
	applyDecal("Eyes", slot.Eyes, "Eyes")
	applyDecal("Mouth", slot.Mouth, "Mouth")
	applyDecal("Nose", slot.Nose, "Nose")
end

local function buildAppearance(character: Model, humanoid: Humanoid, slot: any)
	local race = slot.Race :: string
	local gender = slot.Gender :: string
	local body = toColor3(slot.BodyColor)
	local hair = toColor3(slot.HairColor)
	local ki = toColor3(slot.KiColor)

	applyBodyColors(character, body)

	local headTemplate = RACE_HEADS[race]
	if headTemplate then
		addAccessory(humanoid, headTemplate, body, hair, ki)
	end

	if TAIL_RACES[race] then
		ensureWaistAttachment(character)
		addAccessory(humanoid, Assets.Tails.Tail :: Accessory, body, hair, ki)
		addAccessory(humanoid, Assets.Tails.WrappedTail :: Accessory, body, hair, ki)
	elseif SPHINX_TAIL_RACES[race] then
		ensureWaistAttachment(character)
		addAccessory(humanoid, Assets.Tails.SphinxTail :: Accessory, body, hair, ki)
	end

	if HAIR_RACES[race] then
		applyHair(humanoid, character, slot, gender, body, hair, ki)
	end

	if slot.BodyDecal == UNSET then
		slot.BodyDecal = "Muscle"
	end
	applyBodyDecal(character, race, gender, slot.BodyDecal)

	applyClothing(humanoid, character, slot, gender)

	for _, limbName in { "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" } do
		local limb = character:FindFirstChild(limbName) :: BasePart?
		if limb then
			limb.Material = Enum.Material.Fabric
		end
	end
	local head = character:FindFirstChild("Head") :: BasePart?
	if head then
		head.Material = Enum.Material.SmoothPlastic
	end

	pcall(function()
		(character:FindFirstChildWhichIsA("ShirtGraphic") :: ShirtGraphic):Destroy()
	end)

	applyFace(character, race, gender, slot)

	local scale = RACE_SIZES[race]
	if scale and scale ~= 1 then
		character:ScaleTo(scale)
	end
end

local function isUnsetColor(rgb: any): boolean
	return typeof(rgb) ~= "table" or rgb.R == nil or (rgb.R :: number) < 0
end

local function ensureGeneratedData(slot: any)
	if isUnsetColor(slot.BodyColor) or isUnsetColor(slot.HairColor) then
		generateRaceColours(slot)
	end
	if isUnsetColor(slot.KiColor) then
		generateKiColour(slot)
	end
	if slot.Gender == UNSET or slot.Gender == "" then
		slot.Gender = "Male"
	end
	if slot.Height == UNSET or slot.Height == "" then
		slot.Height = "Adult"
	end
end

local PlayerRaceBuilder = {}

function PlayerRaceBuilder.buildFromSlot(character: Model, slot: any)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("[PlayerRaceBuilder] No Humanoid in character")
		return
	end
	ensureGeneratedData(slot)
	buildAppearance(character, humanoid, slot)
end

function PlayerRaceBuilder.build(player: Player, character: Model)
	local slot = Manager.getActiveSlot(player)
	if not slot then
		warn("[PlayerRaceBuilder] No active slot for", player.Name)
		return
	end
	PlayerRaceBuilder.buildFromSlot(character, slot)
end

function PlayerRaceBuilder.reroll(player: Player)
	local slot = Manager.getActiveSlot(player)
	if not slot then
		return
	end
	generateRaceColours(slot)
	generateKiColour(slot)
	if HAIR_RACES[slot.Race] then
		rollHair(slot, slot.Gender)
	end
end

return PlayerRaceBuilder
