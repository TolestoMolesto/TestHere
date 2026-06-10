--!strict
-- Scouter: scans nearby entities and surfaces their BattlePower as floating indicators.
-- This module holds the client-safe logic + display helpers; the scan lifecycle, the
-- per-target threads and the input live in StarterPlayerScripts/ScouterController -- the
-- same split the codebase uses for LockOn / LockOnController.
--
-- Everything the scouter shows is read off already-replicated instance state, so no remotes
-- are needed:
--   * a target's power  -> Humanoid.Stats.BattlePower        (written by StatsManager)
--   * the local scouter -> Humanoid.Appearance.ScouterEquipped
--
-- Bounty / Party are not ported to the slot model yet: the colour-priority paths that read
-- them are kept but inert (nothing writes those attributes), so re-adding the systems later
-- is drop-in. Every such spot is marked "PLACEHOLDER".

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Entities = require(ReplicatedStorage.Modules.Entities)
local LockOn = require(ReplicatedStorage.Modules.LockOn)

local Scouter = {}

-- Tunables (ported from the old module).
Scouter.SCAN_DELAY = 3 -- seconds of "reading" before results appear
Scouter.BLINK_SPEED = 0.4 -- seconds between In/Out blink toggles
Scouter.SOUND_COOLDOWN = 2 -- seconds between "found" pings per target
Scouter.UPDATE_INTERVAL = 0.5 -- how often a tracked target re-checks range/blink
Scouter.SPAWN_STAGGER = 0.05 -- delay between spawning per-target threads
Scouter.MIN_BOUNTY_FOR_RED = 500 -- PLACEHOLDER: bounty system not yet ported

Scouter.COLORS = {
	NORMAL = Color3.new(1, 0.662745, 0.113725), -- yellow: normal target
	BOUNTY = Color3.fromRGB(255, 0, 0), -- PLACEHOLDER: high-bounty target
	LOCATION = Color3.fromRGB(255, 140, 0), -- orange: out-of-range arrow
	PARTY = Color3.fromRGB(0, 255, 0), -- PLACEHOLDER: party member
	BOUNTY_TARGET = Color3.fromRGB(255, 0, 0), -- PLACEHOLDER: your bounty target
}

-- Per-scouter Range (studs) and Max (the highest BP the lens reads; above it shows "Error").
-- Keyed by Humanoid.Appearance.ScouterEquipped; "None"/"" means unequipped (no scan).
export type ScouterTier = { Range: number, Max: number }

Scouter.DEFAULT_RANGE = 300
Scouter.DEFAULT_MAX = math.huge

-- TODO: replace with the real tiers + values. These are placeholders so the system runs.
local CONFIG: { [string]: ScouterTier } = {
	Basic = { Range = 300, Max = 24000 },
}

-- Folders that hold scannable rigs (the canonical entity folders + a place-side "Enemies").
local SCAN_FOLDERS = {
	Entities.Folder.Player,
	Entities.Folder.NPC,
	Entities.Folder.Shadow,
	"Enemies",
}

-- nil => not equipped. An equipped-but-unconfigured name falls back to defaults (and shows
-- everything) rather than silently failing, so a new tier "just works" before it's tuned.
function Scouter.getTier(equipped: string): ScouterTier?
	if equipped == "None" or equipped == "" then
		return nil
	end
	return CONFIG[equipped] or { Range = Scouter.DEFAULT_RANGE, Max = Scouter.DEFAULT_MAX }
end

-- 1234567 -> "1,234,567"
function Scouter.formatNumber(num: number): string
	return (tostring(num):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- The local player's equipped scouter, read off Humanoid.Appearance (StatsManager writes it).
function Scouter.getEquipped(character: Model): string
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local appearance = humanoid and humanoid:FindFirstChild("Appearance")
	local equipped = appearance and appearance:GetAttribute("ScouterEquipped")
	if typeof(equipped) == "string" then
		return equipped
	end
	return "None"
end

-- A target's BattlePower off Humanoid.Stats, or nil if it has none (skip it).
function Scouter.getBattlePower(target: Model): number?
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local stats = humanoid:FindFirstChild("Stats")
	if not stats then
		return nil
	end
	local bp = stats:GetAttribute("BattlePower")
	if typeof(bp) == "number" then
		return bp
	end
	return nil
end

-- All scannable entities, regardless of distance (Range only picks Location vs PL icon).
-- Reuses LockOn.isValidTarget so self-skip, shadow-privacy and alive checks stay consistent.
function Scouter.getTargets(localCharacter: Model?): { Model }
	local targets = {}
	for _, folderName in SCAN_FOLDERS do
		local folder = Workspace:FindFirstChild(folderName)
		if folder then
			for _, child in folder:GetChildren() do
				if child:IsA("Model") and LockOn.isValidTarget(child, localCharacter) then
					table.insert(targets, child)
				end
			end
		end
	end
	return targets
end

-- ===== PLACEHOLDER: Bounty / Party =====
-- Inert until those systems are ported. Kept so colour priority is drop-in re-enableable.

-- PLACEHOLDER: a future bounty system will set "BountyTarget" on the local character.
function Scouter.isBountyTarget(target: Model, localCharacter: Model?): boolean
	if not localCharacter then
		return false
	end
	local name = localCharacter:GetAttribute("BountyTarget")
	return typeof(name) == "string" and name ~= "" and name == target.Name
end

-- PLACEHOLDER: a future party system will set PartyOne..PartyFive on the local character.
local PARTY_SLOTS = { "PartyOne", "PartyTwo", "PartyThree", "PartyFour", "PartyFive" }
function Scouter.isPartyMember(target: Model, localCharacter: Model?): boolean
	if not localCharacter then
		return false
	end
	for _, slot in PARTY_SLOTS do
		local member = localCharacter:GetAttribute(slot)
		if typeof(member) == "string" and member ~= "NA" and member == target.Name then
			return true
		end
	end
	return false
end

-- Indicator colour by priority: bounty target > party > out-of-range > high bounty > normal.
function Scouter.getIndicatorColor(target: Model, isLocation: boolean, localCharacter: Model?): Color3
	if Scouter.isBountyTarget(target, localCharacter) then -- PLACEHOLDER
		return Scouter.COLORS.BOUNTY_TARGET
	end
	if Scouter.isPartyMember(target, localCharacter) then -- PLACEHOLDER
		return Scouter.COLORS.PARTY
	end
	if isLocation then
		return Scouter.COLORS.LOCATION
	end
	local bounty = target:GetAttribute("Bounty") -- PLACEHOLDER
	if typeof(bounty) == "number" and bounty >= Scouter.MIN_BOUNTY_FOR_RED then
		return Scouter.COLORS.BOUNTY
	end
	return Scouter.COLORS.NORMAL
end

-- ===== Indicator GUI helpers (operate on a cloned template instance) =====

-- Tints the In/Out frames when they are themselves image elements (matches the old art).
function Scouter.colorizeIndicator(indicator: Instance, color: Color3)
	for _, name in { "In", "Out" } do
		local frame = indicator:FindFirstChild(name)
		if frame and (frame:IsA("ImageLabel") or frame:IsA("ImageButton")) then
			local image = frame :: ImageLabel
			image.ImageColor3 = color
		end
	end
end

local function amountLabel(frame: Instance?): TextLabel?
	local label = frame and frame:FindFirstChild("Amount")
	if label and label:IsA("TextLabel") then
		return label
	end
	return nil
end

-- Writes the BP readout onto both In/Out "Amount" labels. Bounty targets get a flavour line
-- on the Out frame (PLACEHOLDER). "Error" replaces the number above the lens's Max.
function Scouter.updatePowerLevelDisplay(
	indicator: Instance,
	target: Model,
	textColor: Color3,
	max: number,
	localCharacter: Model?
)
	local inLabel = amountLabel(indicator:FindFirstChild("In"))
	local outLabel = amountLabel(indicator:FindFirstChild("Out"))
	if not inLabel or not outLabel then
		return
	end

	local bp = Scouter.getBattlePower(target) or 0
	local shown = if bp > max then "Error" else Scouter.formatNumber(math.floor(bp))

	inLabel.Text = shown
	if Scouter.isBountyTarget(target, localCharacter) then -- PLACEHOLDER
		outLabel.Text = "Bounty Target"
	else
		outLabel.Text = shown
	end

	inLabel.TextColor3 = textColor
	outLabel.TextColor3 = textColor
end

-- One blink step: swap which of In/Out is visible.
function Scouter.blinkIndicator(indicator: Instance)
	local inFrame = indicator:FindFirstChild("In")
	local outFrame = indicator:FindFirstChild("Out")
	if not (inFrame and inFrame:IsA("GuiObject")) then
		return
	end
	if not (outFrame and outFrame:IsA("GuiObject")) then
		return
	end
	local inVisible = inFrame.Visible
	inFrame.Visible = not inVisible
	outFrame.Visible = inVisible
end

return Scouter
