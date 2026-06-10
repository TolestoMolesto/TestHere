--!strict
-- Pure stat overlay for active abilities. Reads the active-ability attributes (ActiveForm +
-- ActiveTechnique) and returns a virtual slot (a shallow copy with each ability's stat deltas
-- merged in) so the real, persisted slot is NEVER mutated by a temporary buff. A Form and a
-- Technique stack: their Multi deltas combine multiplicatively, Add deltas additively. Used
-- only by StatsManager.

local ServerStorage = game:GetService("ServerStorage")

local FormConfig = require(ServerStorage.Modules.FormConfig)

local ACTIVE_ATTRS = { "ActiveForm", "ActiveTechnique" }

local FormOverlay = {}

-- Copies a StatData (Base/Flat/Add/Multi) or ModStat (Flat/Add/Multi; Base is nil and unused).
local function cloneStat(s: any): any
	return { Base = s.Base, Flat = s.Flat, Add = s.Add, Multi = s.Multi }
end

-- Returns `slot` unchanged when nothing is active; otherwise a shallow-merged virtual copy.
function FormOverlay.apply(character: Model?, slot: any): any
	if not character then
		return slot
	end

	local defs: { any } = {}
	for _, attr in ACTIVE_ATTRS do
		local name = character:GetAttribute(attr)
		if type(name) == "string" and name ~= "" then
			local def = FormConfig.get(name)
			if def then
				table.insert(defs, def)
			end
		end
	end
	if #defs == 0 then
		return slot
	end

	-- Shallow copy: identity/appearance/untouched stats pass through by reference; only the
	-- stat sub-tables an ability changes are cloned-then-modified, so `slot` stays pristine.
	-- (writeValues writes BattlePower onto the copy, so the saved slot's BP also stays base.)
	local virtual: { [string]: any } = table.clone(slot)
	local cloned: { [string]: boolean } = {}
	local function ensure(statName: string): any
		if not cloned[statName] then
			virtual[statName] = cloneStat(slot[statName])
			cloned[statName] = true
		end
		return virtual[statName]
	end

	for _, def in defs do
		for statName, delta in def.stats do
			if slot[statName] then
				local c = ensure(statName)
				c.Add += delta.Add or 0
				-- Multiplicative across abilities: SSJ (x1.5) then Kaioken (x1.5) = x2.25.
				c.Multi *= 1 + (delta.Multi or 0)
			end
		end
		if def.kiPack then
			ensure("Ki").Add += def.kiPack
		end
		if def.staminaPack then
			ensure("Stamina").Add += def.staminaPack
		end
		if def.healthPack then
			ensure("Health").Add += def.healthPack
		end
	end

	return virtual
end

return FormOverlay
