local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ActionConfig = require(ReplicatedStorage.Modules.ActionConfig)
local ActionController = require(ServerStorage.Modules.ActionController)
local Charge = require(ServerStorage.Modules.Charge)
local Flight = require(ReplicatedStorage.Modules.Flight)
local FormConfig = require(ServerStorage.Modules.FormConfig)
local FormState = require(ServerStorage.Modules.FormState)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Rest = require(ServerStorage.Modules.Rest)
local ShadowSpawner = require(ServerStorage.Modules.ShadowSpawner)
local TargetLock = require(ServerStorage.Modules.TargetLock)

local MAX_REQUESTS_PER_SECOND = 25

-- Lazy-required: top-level require would hang boot if place-side Hitbox templates are missing.
ActionController.register("LightAttack", function(context, params)
	local cframe = if typeof(params.cframe) == "CFrame" then params.cframe else nil
	require(ServerStorage.Modules.LightAttack)(context.character, cframe)
end)

ActionController.register("HeavyAttack", function(context, params)
	local cframe = if typeof(params.cframe) == "CFrame" then params.cframe else nil
	require(ServerStorage.Modules.HeavyAttack)(context.character, cframe)
end)

-- K summons your shadow -- but only on a full Ki bar, which it drains to 0. Press again to dismiss
-- it (free). Only ever one at a time.
ActionController.register("SpawnShadow", function(context)
	local player = context.player
	if not player then
		return
	end
	if ShadowSpawner.isActive(player) then
		ShadowSpawner.despawn(player)
		return
	end
	local character = context.character
	local ki = (character:GetAttribute("Ki") :: number?) or 0
	local maxKi = (character:GetAttribute("MaxKi") :: number?) or 0
	if maxKi <= 0 or ki < maxKi then
		return -- needs a full Ki bar to summon
	end
	if ShadowSpawner.spawn(player) then
		character:SetAttribute("Ki", 0)
	end
end)

-- CanRecover is set server-side ~0.5s into knockback and cannot be spoofed by the client.
ActionController.register("Recover", function(context)
	local character = context.character
	if not character:GetAttribute("HitByKnockBack") or not character:GetAttribute("CanRecover") then
		return
	end
	require(ServerStorage.Modules.Knockback).cancel(character)
end)

ActionController.register("Vanish", function(context)
	require(ServerStorage.Modules.Vanish)(context.character)
end)

ActionController.register("Block", function(context, params)
	local Block = require(ServerStorage.Modules.Block)
	if params.phase == "stop" then
		Block.stop(context.character)
	else
		Block.start(context.character)
	end
end)

ActionController.register("Charge", function(context, params)
	if params.phase == "stop" then
		Charge.stop(context.character)
	else
		Charge.start(context.character)
	end
end)

ActionController.register("Rest", function(context)
	Rest.toggle(context.character)
end)

ActionController.register("KiBlast", function(context)
	require(ServerStorage.Modules.KiBlast)(context.character)
end)

ActionController.register("Flight", function(context, params)
	local character = context.character
	if params.phase == "boost" then
		Flight.setBoost(character, params.value == true)
	elseif params.phase == "stop" then
		Flight.setEnabled(character, false)
	else -- "toggle" (default)
		Flight.setEnabled(character, not character:GetAttribute("Flying"))
	end
end)

ActionController.register("Transform", function(context, params)
	local slot = params.slot
	if type(slot) == "number" then
		FormState.toggleByIndex(context.character, slot)
	end
end)

-- Lazy-required (mirrors the combat handlers above): SkillState pulls in SkillConfig + behaviors,
-- some of which reference place-side VFX, so deferring keeps boot resilient.
ActionController.register("Skill", function(context, params)
	local slot = params.slot
	if type(slot) ~= "number" then
		return
	end
	local aim = if typeof(params.cframe) == "CFrame" then params.cframe else nil
	require(ServerStorage.Modules.SkillState).useByIndex(context.character, slot, aim)
end)

-- Action-bar HUD label source: the player's race ability line (names/cooldowns). Runtime state
-- (active/cooldown/expiry) the HUD reads from character attributes, not here.
Remotes.GetFormBar.OnServerInvoke = function(player: Player)
	local character = player.Character
	if not character then
		return {}
	end
	return FormState.getBar(character)
end

type Window = { count: number, windowStart: number }
local windows: { [Player]: Window } = {}

local function rateLimited(player: Player): boolean
	local now = os.clock()
	local window = windows[player]
	if not window or now - window.windowStart >= 1 then
		windows[player] = { count = 1, windowStart = now }
		return false
	end
	window.count += 1
	return window.count > MAX_REQUESTS_PER_SECOND
end

Players.PlayerRemoving:Connect(function(player)
	windows[player] = nil
end)

Remotes.PerformAction.OnServerEvent:Connect(function(player: Player, actionId: any, params: any)
	-- Only accept known, client-triggerable action ids.
	if type(actionId) ~= "string" or not ActionConfig[actionId] then
		return
	end
	if not ActionController.isRegistered(actionId) then
		return
	end
	if rateLimited(player) then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local safeParams = if type(params) == "table" then params else {}
	ActionController.perform(character, actionId, safeParams)
end)

-- TargetLock.set sanitises the untrusted `target` argument before recording it.
Remotes.SetLockOnTarget.OnServerEvent:Connect(function(player: Player, target: any)
	if rateLimited(player) then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	if target == nil then
		TargetLock.clear(character)
	else
		TargetLock.set(character, target)
	end
end)

-- Combat FX live in the .rbxl place (not Rojo-synced) and are cosmetic-only; warn once
-- at boot if any are missing so they're not silently absent. Add entries as new FX are wired.
local function resolvePath(root: Instance, path: { string }): Instance?
	local node: Instance? = root
	for _, name in path do
		if not node then
			return nil
		end
		node = (node :: Instance):FindFirstChild(name)
	end
	return node
end

local EXPECTED_ASSETS = {
	{ root = ServerStorage, path = { "Assets", "VFX" }, why = "VFX folder (hit/knockback/parry particle templates)" },
	{ root = ServerStorage, path = { "Assets", "VFX", "HitFXTemplate" }, why = "LightAttack hit particles (HitFX)" },
	{
		root = ServerStorage,
		path = { "Assets", "VFX", "ChargeVFX" },
		why = "sustained charge aura particles (ChargeFX)",
	},
	{
		root = ServerStorage,
		path = { "Assets", "VFX", "KnockbackFXTemplate" },
		why = "knockback trail particles (Knockback)",
	},
	{
		root = ServerStorage,
		path = { "Assets", "VFX", "ParryFXTemplate" },
		why = "block/parry particles (HitFX + ParryHandler)",
	},
	{ root = ServerStorage, path = { "Assets", "VFX", "Tele" }, why = "vanish teleport puff + sound (Vanish)" },
}

local function auditCombatAssets(): ()
	local missing = {}
	for _, entry in EXPECTED_ASSETS do
		if not resolvePath(entry.root, entry.path) then
			table.insert(missing, `  - {entry.root.Name}.{table.concat(entry.path, ".")}  --  {entry.why}`)
		end
	end
	if #missing > 0 then
		warn(
			`[CombatServer] {#missing} place-side combat FX asset(s) MISSING. These are cosmetic`
				.. ` -- hits still land without them -- but create them in Studio if you want the effects`
				.. ` (they don't sync from Rojo, so this won't auto-fix):\n`
				.. table.concat(missing, "\n")
		)
	end
end

auditCombatAssets()

-- Ability aura templates (FormConfig.auraTemplate) are place-side too; warn at boot for any
-- that are missing or misnamed so they don't silently fail to appear via FormFX.
local function auditFormAuras(): ()
	local vfx = resolvePath(ServerStorage, { "Assets", "VFX" })
	if not vfx then
		return -- auditCombatAssets already warned about a missing VFX folder.
	end
	local missing = {}
	local seen = {}
	for _, def in FormConfig.forms do
		local name = def.auraTemplate
		if not seen[name] then
			seen[name] = true
			if not vfx:FindFirstChild(name) then
				table.insert(missing, `  - ServerStorage.Assets.VFX.{name}  --  {def.displayName}`)
			end
		end
	end
	if #missing > 0 then
		warn(
			`[CombatServer] {#missing} ability aura template(s) MISSING/misnamed under`
				.. ` ServerStorage.Assets.VFX. The ability still works; FormFX just shows no aura.`
				.. ` Names must match FormConfig.auraTemplate exactly:\n`
				.. table.concat(missing, "\n")
		)
	end
end

auditFormAuras()
