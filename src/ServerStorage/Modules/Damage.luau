--!strict
local Players = game:GetService("Players")

export type DamageCause = "Physical" | "Ki"

-- Universal damage floor: any landed hit deals at least this much (guarantees chip damage).
local MIN_DAMAGE = 1

local Damage = {}

local function getStatAttr(character: Model, attr: string): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return 0
	end
	local folder = humanoid:FindFirstChild("Stats")
	if not folder then
		return 0
	end
	return (folder:GetAttribute(attr) :: number?) or 0
end

function Damage.apply(
	targetCharacter: Model,
	attackingCharacter: Model?,
	baseDamage: number,
	cause: DamageCause
): number?
	if typeof(baseDamage) ~= "number" then
		return
	end

	-- Spawn protection / intangibility: a Forcefield target takes no damage at all. Return 0 -- a
	-- whiff, like a dodge -- so every caller skips its on-hit reactions; never nil, which the melee/ki
	-- callers read as "hit landed". (Scan/lock-on paths already exclude them; this is the backstop.)
	if targetCharacter:GetAttribute("Forcefield") then
		return 0
	end

	-- Dodge returns 0 (never the MIN_DAMAGE floor) so callers can detect a whiff and skip
	-- their on-hit reactions; a landed hit always returns >= MIN_DAMAGE.
	local dodgePct = getStatAttr(targetCharacter, "Dodge")
	if math.random() < dodgePct then
		return 0
	end

	local damageStat = if attackingCharacter then getStatAttr(attackingCharacter, "Damage") else 1
	if damageStat <= 0 then
		damageStat = 1
	end

	local typeBonus = if attackingCharacter
		then (if cause == "Physical"
			then getStatAttr(attackingCharacter, "PhysicalDamage")
			else getStatAttr(attackingCharacter, "KiDamage"))
		else 0

	-- The move's flat Base Damage stacks on top of the attacker's Damage stat (+ type bonus).
	local damage = damageStat + typeBonus + baseDamage

	if cause == "Physical" then
		damage *= 1 - getStatAttr(targetCharacter, "PhysicalResistancePct")
	elseif cause == "Ki" then
		damage *= 1 - getStatAttr(targetCharacter, "KiResistancePct")
	end

	damage *= 1 - getStatAttr(targetCharacter, "AllDamageReduction")

	-- Floor AFTER reductions so a landed hit always deals >= MIN_DAMAGE; flooring
	-- earlier let resistance round low hits to 0 (combat tag + knockback but no damage).
	damage = math.max(math.floor(damage), MIN_DAMAGE)

	if attackingCharacter and targetCharacter:GetAttribute("IsShadow") ~= true then
		local attackerPlayer = Players:GetPlayerFromCharacter(attackingCharacter)
		if attackerPlayer then
			targetCharacter:SetAttribute("LastAttacker", attackerPlayer.Name)
		end
	end

	local humanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Never land the killing blow: leave >= 1 HP so the knockout system (StateBinders)
		-- takes over with a ragdoll/revive instead of Humanoid.Died racing it.
		local survivable = math.max(humanoid.Health - 1, 0)
		humanoid:TakeDamage(math.min(damage, survivable))
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
