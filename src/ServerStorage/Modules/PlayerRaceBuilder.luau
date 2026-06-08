--!strict
-- ─────────────────────────────────────────────
-- PlayerRaceBuilder.luau
-- Applies race-specific appearance (colours, hair, head accessories, clothing,
-- face decals, animations) to a player's character from their active slot data.
--
-- Usage:
--   PlayerRaceBuilder.build(player, character)   -- called each spawn
--   PlayerRaceBuilder.reroll(player)             -- randomise appearance only
-- ─────────────────────────────────────────────

local CollectionService = game:GetService("CollectionService")
local ServerStorage     = game:GetService("ServerStorage")

local Manager    = require(ServerStorage.Modules.Manager)
local Assets     = ServerStorage:WaitForChild("Assets")

-- ─── Types ───────────────────────────────────────────────────────────────────

type RGBColor = { R: number, G: number, B: number }

-- ─── Constants ───────────────────────────────────────────────────────────────

local UNSET       = "NA"   -- sentinel for "not yet set"
local RNG         = Random.new()
local WHITE       = Color3.fromRGB(255, 255, 255)

-- Race head accessories (cloned when building the character).
-- If a race has no entry here it simply gets no extra head piece.
local RACE_HEADS: { [string]: Accessory } = {
	Acrosian = Assets.Heads.Acrosian.One :: Accessory,
	Majin    = Assets.Heads.Majin.One    :: Accessory,
	Namekian = Assets.Heads.Namekian.One :: Accessory,
	Sphinx   = Assets.Heads.Sphinx.One   :: Accessory,
}

-- Races whose character has a Saiyan tail.
local TAIL_RACES: { [string]: true } = {
	Saiyan               = true,
	LegendarySuperSaiyan = true,
}

-- Races whose characters show hair.
local HAIR_RACES: { [string]: true } = {
	Human                = true,
	Saiyan               = true,
	LegendarySuperSaiyan = true,
}

-- Races whose characters have a Sphinx-style tail.
local SPHINX_TAIL_RACES: { [string]: true } = {
	Sphinx   = true,
	Acrosian = true,
}

-- Fallback face assets per race (used when a player's saved value is missing
-- or invalid). Always the '1' variant so the face is never blank on first spawn.
local DEFAULT_FACES: { [string]: { Eyes: string, Mouth: string, Nose: string } } = {
	Acrosian             = { Eyes = "AcrosianEye1",  Mouth = "AcrosianMouth1",  Nose = "AcrosianNose1"  },
	Majin                = { Eyes = "MajinEye1",     Mouth = "MajinMouth1",     Nose = "MajinNose1"     },
	Namekian             = { Eyes = "NamekianEyes1", Mouth = "NamekianMouth1",  Nose = "NamekianNose1"  },
	Sphinx               = { Eyes = "SphinxEye1",    Mouth = "SphinxMouth1",    Nose = "SphinxNose1"    },
	Saiyan               = { Eyes = "MaleEye1",      Mouth = "Mouth1",          Nose = "Nose1"          },
	LegendarySuperSaiyan = { Eyes = "MaleEye1",      Mouth = "Mouth1",          Nose = "Nose1"          },
	Human                = { Eyes = "MaleEye1",      Mouth = "Mouth1",          Nose = "Nose1"          },
}

-- Race size multipliers. Set BaseScale ~= 1 to resize a race on spawn.
local RACE_SIZES: { [string]: number } = {
	Acrosian             = 1.0,
	Namekian             = 1.0,
	Saiyan               = 1.0,
	LegendarySuperSaiyan = 1.0,
	Sphinx               = 1.0,
	Human                = 1.0,
	Majin                = 1.0,
}

-- Extra clothing parts that must be added for certain multi-piece outfits.
-- The base Shirt / PantsLeft / PantsRight are always added via the normal path.
local OUTFIT_EXTRAS: { [string]: { string } } = {
	TrainingGi = {
		"TrainingGiUnderShirt",
		"TrainingGiBelt",
		"TrainingGiShoeLeft",     "TrainingGiShoeRight",
		"TrainingGiLeftShoulder", "TrainingGiRightShoulder",
		"TrainingGiUnderLeftShoulder", "TrainingGiUnderRightShoulder",
	},
	CraneSchoolGi = {
		"CraneSchoolGiTorso",  "CraneSchoolGiBelt",
		"CraneSchoolGiArmBandLeft",    "CraneSchoolGienArmBandRight",
		"CraneSchoolGiArmRingsLeft",   "CraneSchoolGiArmRingsRight",
		"CraneSchoolGiLegBandLeft",    "CraneSchoolGiLegBandRight",
		"CraneSchoolGiShoeLeft",       "CraneSchoolGiShoeRight",
	},
	VampaWarrior = {
		"VampaWarriorTorso",   "VampaWarriorNeck",
		"VampaWarriorLeftSleeve",  "VampaWarriorRightSleeve",
		"VampaWarriorArmRingsLeft",    "VampaWarriorArmRingsRight",
		"VampaWarriorBandLeft",        "VampaWarriorBandRight",
		"VampaWarriorLegBandLeft",     "VampaWarriorLegRingsLeft",
		"VampaWarriorLegRingsRight",   "VampaWarriorLegPadRight",
		"VampaWarriorShoeLeft",        "VampaWarriorShoeRight",
	},
	MajinVegeta = {
		"MajinVegetaTorso",
		"MajinVegetaShoeLeft",  "MajinVegetaShoeRight",
		"MajinVegetaLeftGlove", "MajinVegetaRightGlove",
	},
}

-- Clothing accessory name patterns used when stripping old clothes.
local CLOTHING_PATTERNS = {
	"Shirt", "Pants", "Waist", "Belt",
	"Shoe",  "Shoulder", "Glove", "Torso", "Arm", "Leg",
}

-- ─── Lookup tables (built once at require-time) ───────────────────────────────

local bodyDecalLookup: { [string]: Shirt | Pants } = {}
local clothesLookup:   { [string]: Accessory      } = {}

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

-- ─── Colour helpers ──────────────────────────────────────────────────────────

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
	return Color3.fromRGB(
		RNG:NextInteger(0, 255),
		RNG:NextInteger(0, 255),
		RNG:NextInteger(0, 255)
	)
end

-- ─── Accessory helpers ───────────────────────────────────────────────────────

-- Tints all tagged BaseParts inside an accessory.
-- CollectionService tags "BodyColor", "HairColor", "KiColor" control which
-- parts receive which colour. Untagged parts are left untouched.
local function colorAccessory(acc: Accessory, body: Color3, hair: Color3, ki: Color3)
	for _, part in acc:GetDescendants() do
		if not part:IsA("BasePart") then continue end
		if CollectionService:HasTag(part, "BodyColor") then
			part.Color = body
		elseif CollectionService:HasTag(part, "HairColor") then
			part.Color = hair
		elseif CollectionService:HasTag(part, "KiColor") then
			part.Color = ki
		end
	end
end

local function addAccessory(humanoid: Humanoid, template: Accessory,
	body: Color3, hair: Color3, ki: Color3)
	local acc = template:Clone()
	colorAccessory(acc, body, hair, ki)
	humanoid:AddAccessory(acc)
end

-- Applies race body colour to all body parts via a BodyColors instance.
local function applyBodyColors(character: Model, color: Color3)
	local existing = character:FindFirstChild("Body Colors")
	if existing then existing:Destroy() end
	local bc = Assets.Skins.RaceColors:Clone()
	bc.HeadColor3      = color; bc.TorsoColor3    = color
	bc.LeftArmColor3   = color; bc.RightArmColor3 = color
	bc.LeftLegColor3   = color; bc.RightLegColor3 = color
	bc.Parent = character
end

-- Ensures the Torso has a WaistBackAttachment (required for tails).
local function ensureWaistAttachment(character: Model)
	local torso = character:FindFirstChild("Torso") :: BasePart?
	if not torso then return end
	if not torso:FindFirstChild("WaistBackAttachment") then
		local att    = Instance.new("Attachment")
		att.Name     = "WaistBackAttachment"
		att.Position = Vector3.new(0, 1, 1)
		att.Parent   = torso
	end
end

-- ─── Colour generation ───────────────────────────────────────────────────────

local function generateRaceColours(slot: any)
	local race       = slot.Race :: string
	local raceFolder = (Assets.Skins.RaceColors:FindFirstChild(race)
		or Assets.Skins.RaceColors:FindFirstChild("Human")) :: Folder
	local colours    = raceFolder:GetChildren()

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
	elseif race == "Acrosian" or race == "Majin"
		or race == "Namekian" or race == "Sphinx" or race == "KAI" then
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

-- ─── Hair ────────────────────────────────────────────────────────────────────

-- Removes all accessories that live in the Hairs folder (any gender).
local function stripHair(character: Model)
	for _, acc in character:GetChildren() do
		if not acc:IsA("Accessory") then continue end
		for _, gender in { "Male", "Female" } do
			local gf = Assets.Hairs:FindFirstChild(gender)
			if gf and gf:FindFirstChild(acc.Name) then
				acc:Destroy()
				break
			end
		end
	end
end

-- Picks a random hair from the gender folder, saves it to the slot, returns the clone.
local function rollHair(slot: any, gender: string): Accessory?
	local folder = Assets.Hairs:FindFirstChild(gender)
	if not folder then return nil end
	local hairs = folder:GetChildren()
	if #hairs == 0 then return nil end
	local chosen = hairs[RNG:NextInteger(1, #hairs)]
	slot.Hair = chosen.Name
	return chosen:Clone() :: Accessory
end

local function applyHair(humanoid: Humanoid, character: Model, slot: any,
	gender: string, body: Color3, hair: Color3, ki: Color3)
	stripHair(character)
	local folder  = Assets.Hairs:FindFirstChild(gender)
	local saved   = folder and slot.Hair ~= UNSET
		and folder:FindFirstChild(slot.Hair) :: Accessory?
	local chosen  = if saved then saved:Clone() else rollHair(slot, gender)
	if not chosen then return end
	colorAccessory(chosen, body, hair, ki)
	humanoid:AddAccessory(chosen)
end

-- ─── Body decal ──────────────────────────────────────────────────────────────

local function applyBodyDecal(character: Model, race: string, gender: string, base: string)
	local shirtKey = if race == "Namekian"
		then "Namekian" .. base .. "Shirt"
		else gender     .. base .. "Shirt"
	local pantKey  = gender .. base .. "Pant"

	local shirt = bodyDecalLookup[shirtKey]
	local pant  = bodyDecalLookup[pantKey]

	if shirt then shirt:Clone().Parent = character
	else warn("[PlayerRaceBuilder] BodyDecal shirt not found:", shirtKey) end

	if pant then pant:Clone().Parent = character
	else warn("[PlayerRaceBuilder] BodyDecal pant not found:", pantKey) end
end

-- ─── Clothing ────────────────────────────────────────────────────────────────

local function stripClothing(character: Model)
	for _, acc in character:GetChildren() do
		if not acc:IsA("Accessory") then continue end
		for _, pat in CLOTHING_PATTERNS do
			if acc.Name:find(pat) then acc:Destroy(); break end
		end
	end
end

-- Normalises legacy outfit names and applies female overrides.
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
		if acc then humanoid:AddAccessory(acc:Clone())
		else warn("[PlayerRaceBuilder] Clothing piece not found:", key) end
	end

	addPiece(shirtName .. "Shirt")
	addPiece(pantsName .. "PantsLeft")
	addPiece(pantsName .. "PantsRight")

	-- Add any extra parts specific to this outfit.
	local extras = OUTFIT_EXTRAS[shirtName] or OUTFIT_EXTRAS[pantsName]
	if extras then
		for _, part in extras do
			addPiece(part)
		end
	end
end

-- ─── Face system ─────────────────────────────────────────────────────────────

-- Returns the face folder for a race, with Human as fallback.
local function getFaceFolder(race: string): Folder?
	return (Assets.Faces:FindFirstChild(race)
		or Assets.Faces:FindFirstChild("Human")) :: Folder?
end

-- "MaleEye1" → "FemaleEye1" for female characters.
local function applyGender(gender: string, name: string): string
	return if gender == "Female" then name:gsub("^Male", "Female") else name
end

-- "AcrosianEye1" → "AcrosianPupil1" etc.
local function toPupilName(eyeName: string): string?
	local name = eyeName:gsub("Eyes", "Pupil"):gsub("Eye", "Pupil")
	return if name ~= eyeName then name else nil
end

local function getFaceDecal(race: string, category: string, assetName: string?): Decal?
	if not assetName or assetName == UNSET or assetName == "" then return nil end
	local folder = getFaceFolder(race)
	if not folder then return nil end
	local cat = folder:FindFirstChild(category)
	if not cat then return nil end
	local found = cat:FindFirstChild(assetName)
	if found and found:IsA("Decal") then return found :: Decal end
	-- Female → male fallback
	if assetName:find("^Female") then
		local male = assetName:gsub("^Female", "Male")
		local fb   = cat:FindFirstChild(male)
		if fb and fb:IsA("Decal") then return fb :: Decal end
	end
	return nil
end

local function isValidFaceAsset(race: string, category: string, name: string?): boolean
	if not name or name == UNSET or name == "" then return false end
	local folder = getFaceFolder(race)
	if not folder then return false end
	local cat = folder:FindFirstChild(category)
	return cat ~= nil and cat:FindFirstChild(name) ~= nil
end

-- Builds a separate head mesh and applies face decals onto it.
-- A separate mesh at SpecialMesh scale 1.25 gives clean decal rendering.
local function applyFace(character: Model, race: string, gender: string, slot: any)
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then return end

	-- Clear existing decals / GUIs and any prior head model.
	for _, c in head:GetChildren() do
		if c:IsA("Decal") or c:IsA("SurfaceGui") then c:Destroy() end
	end
	local existing = head:FindFirstChild("HeadModel")
	if existing then existing:Destroy() end

	-- Resolve each face asset, falling back to race defaults.
	local defaults = DEFAULT_FACES[race] or DEFAULT_FACES.Human
	local function resolve(category: string, saved: string?, default: string): string
		local g = applyGender(gender, if saved ~= nil then saved else UNSET)
		if isValidFaceAsset(race, category, g) then return g end
		local gd = applyGender(gender, default)
		if isValidFaceAsset(race, category, gd) then return gd end
		return default
	end

	slot.Eyes  = resolve("Eyes",  slot.Eyes,  defaults.Eyes)
	slot.Mouth = resolve("Mouth", slot.Mouth, defaults.Mouth)
	slot.Nose  = resolve("Nose",  slot.Nose,  defaults.Nose)

	-- Build the separate head part at the correct mesh scale.
	local headModel       = Instance.new("Model")
	headModel.Name        = "HeadModel"
	headModel.Parent      = head

	local newHead              = Instance.new("Part")
	newHead.Name               = "NewHead"
	newHead.Size               = Vector3.new(2, 1, 1)
	newHead.CanTouch           = false
	newHead.CanQuery           = false
	newHead.CanCollide         = false
	newHead.Massless           = true
	newHead.Color              = head.Color
	newHead.Material           = Enum.Material.SmoothPlastic
	newHead.CFrame             = head.CFrame
	newHead.Parent             = headModel
	headModel.PrimaryPart      = newHead

	local mesh          = Instance.new("SpecialMesh")
	mesh.MeshType       = Enum.MeshType.Head
	mesh.Scale          = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent         = newHead

	local weld   = Instance.new("WeldConstraint")
	weld.Part0   = newHead
	weld.Part1   = head
	weld.Parent  = newHead
	head.Transparency = 1

	-- Apply decals in draw order: Pupils → Eyes → Mouth → Nose.
	local function applyDecal(category: string, name: string?, label: string)
		local decal = getFaceDecal(race, category, name)
		if not decal then return end
		local clone      = decal:Clone()
		clone.Name       = label
		clone.Face       = Enum.NormalId.Front
		clone.Parent     = newHead
	end

	applyDecal("Eyes", toPupilName(slot.Eyes), "Pupils")
	applyDecal("Eyes",  slot.Eyes,  "Eyes")
	applyDecal("Mouth", slot.Mouth, "Mouth")
	applyDecal("Nose",  slot.Nose,  "Nose")
end

-- ─── Full appearance build ───────────────────────────────────────────────────

local function buildAppearance(character: Model, humanoid: Humanoid, slot: any)
	local race   = slot.Race   :: string
	local gender = slot.Gender :: string
	local body   = toColor3(slot.BodyColor)
	local hair   = toColor3(slot.HairColor)
	local ki     = toColor3(slot.KiColor)

	applyBodyColors(character, body)

	-- Race-specific head accessory.
	local headTemplate = RACE_HEADS[race]
	if headTemplate then
		addAccessory(humanoid, headTemplate, body, hair, ki)
	end

	-- Tails.
	if TAIL_RACES[race] then
		ensureWaistAttachment(character)
		addAccessory(humanoid, Assets.Tails.Tail        :: Accessory, body, hair, ki)
		addAccessory(humanoid, Assets.Tails.WrappedTail :: Accessory, body, hair, ki)
	elseif SPHINX_TAIL_RACES[race] then
		ensureWaistAttachment(character)
		addAccessory(humanoid, Assets.Tails.SphinxTail  :: Accessory, body, hair, ki)
	end

	-- Hair.
	if HAIR_RACES[race] then
		applyHair(humanoid, character, slot, gender, body, hair, ki)
	end

	-- Body decal.
	if slot.BodyDecal == UNSET then slot.BodyDecal = "Muscle" end
	applyBodyDecal(character, race, gender, slot.BodyDecal)

	-- Clothing.
	applyClothing(humanoid, character, slot, gender)

	-- Limb materials.
	for _, limbName in { "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" } do
		local limb = character:FindFirstChild(limbName) :: BasePart?
		if limb then limb.Material = Enum.Material.Fabric end
	end
	local head = character:FindFirstChild("Head") :: BasePart?
	if head then head.Material = Enum.Material.SmoothPlastic end

	-- Remove default shirt graphic.
	pcall(function()
		(character:FindFirstChildWhichIsA("ShirtGraphic") :: ShirtGraphic):Destroy()
	end)

	-- Face decals.
	applyFace(character, race, gender, slot)

	-- Race scale.
	local scale = RACE_SIZES[race]
	if scale and scale ~= 1 then
		character:ScaleTo(scale)
	end

end

-- ─── Ensure generated data is present on the slot ────────────────────────────

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

-- ─── Public API ──────────────────────────────────────────────────────────────

local PlayerRaceBuilder = {}

-- Universal build: applies race appearance from any slot data.
-- Use this for both players and AI/NPCs.
function PlayerRaceBuilder.buildFromSlot(character: Model, slot: any)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("[PlayerRaceBuilder] No Humanoid in character")
		return
	end
	ensureGeneratedData(slot)
	buildAppearance(character, humanoid, slot)
end

-- Convenience wrapper for player characters: fetches the active slot automatically.
function PlayerRaceBuilder.build(player: Player, character: Model)
	local slot = Manager.getActiveSlot(player)
	if not slot then
		warn("[PlayerRaceBuilder] No active slot for", player.Name)
		return
	end
	PlayerRaceBuilder.buildFromSlot(character, slot)
end

-- Re-randomises colours and hair for the player's active slot.
-- The change takes effect on the next spawn (or call build() again immediately).
function PlayerRaceBuilder.reroll(player: Player)
	local slot = Manager.getActiveSlot(player)
	if not slot then return end
	generateRaceColours(slot)
	generateKiColour(slot)
	if HAIR_RACES[slot.Race] then
		rollHair(slot, slot.Gender)
	end
end

return PlayerRaceBuilder
