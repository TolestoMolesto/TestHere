--!strict
-- ─────────────────────────────────────────────
-- Damage.luau
-- All damage and healing flows through here.
-- Stats are read exclusively from the Humanoid.Stats folder attributes
-- written by StatsManager — no profile or TemporaryStats access.
--
-- Damage types: "Physical" | "Ki"
--
-- Formula:
--   raw   = (Damage + PhysicalDamage or KiDamage) * coefficient
--   raw   = max(raw, minimumDamage)
--   raw  *= 1 - PhysicalResistancePct  (Physical)
--        or 1 - KiResistancePct        (Ki)
--   raw  *= 1 - AllDamageReduction
--   final = floor(raw), clamped >= 0
--
-- Dodge is rolled first; a successful proc returns 0 without
-- calling TakeDamage.
-- ─────────────────────────────────────────────
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

export type DamageCause = "Physical" | "Ki"

local Damage = {}

-- ── Helpers ───────────────────────────────────────────────────────────

local function getStatAttr(character: Model, attr: string): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return 0 end
	local folder = humanoid:FindFirstChild("Stats")
	if not folder then return 0 end
	return (folder:GetAttribute(attr) :: number?) or 0
end

-- ── Public API ────────────────────────────────────────────────────────

-- Apply scaled damage to targetCharacter.
-- attackingCharacter may be nil (e.g. environmental damage).
-- Returns the final damage dealt, or 0 on a dodge / safe zone, or nil
-- if minimumDamage is not a number.
function Damage.apply(
	targetCharacter: Model,
	attackingCharacter: Model?,
	minimumDamage: number,
	cause: DamageCause,
	coefficient: number?
): number?
	if typeof(minimumDamage) ~= "number" then return end

	-- Dodge check
	local dodgePct = getStatAttr(targetCharacter, "Dodge")
	if math.random() < dodgePct then return 0 end

	-- Attacker Damage stat drives all damage output
	local damageStat = if attackingCharacter then getStatAttr(attackingCharacter, "Damage") else 1
	if damageStat <= 0 then damageStat = 1 end

	local typeBonus = if attackingCharacter
		then (if cause == "Physical"
			then getStatAttr(attackingCharacter, "PhysicalDamage")
			else getStatAttr(attackingCharacter, "KiDamage"))
		else 0

	local damage = math.max((damageStat + typeBonus) * (coefficient or 1), minimumDamage)

	-- Type-specific resistance
	if cause == "Physical" then
		damage *= 1 - getStatAttr(targetCharacter, "PhysicalResistancePct")
	elseif cause == "Ki" then
		damage *= 1 - getStatAttr(targetCharacter, "KiResistancePct")
	end

	-- Universal damage reduction
	damage *= 1 - getStatAttr(targetCharacter, "AllDamageReduction")

	damage = math.max(math.floor(damage), 0)

	-- Record last attacker for kill credit
	if attackingCharacter and targetCharacter:GetAttribute("IsShadow") ~= true then
		local attackerPlayer = Players:GetPlayerFromCharacter(attackingCharacter)
		if attackerPlayer then
			targetCharacter:SetAttribute("LastAttacker", attackerPlayer.Name)
		end
	end

	local humanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:TakeDamage(damage)
	end

	return damage
end

function Damage.getLastAttacker(character: Model): Player?
	local attackerName = character:GetAttribute("LastAttacker")
	if attackerName then
		return Players:FindFirstChild(attackerName) :: Player?
	end
	return nil
end

function Damage.heal(character: Model, amount: number): ()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = math.min(humanoid.Health + amount, humanoid.MaxHealth)
	end
end

return Damage
