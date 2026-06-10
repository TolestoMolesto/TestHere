--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionConfig = require(ReplicatedStorage.Modules.ActionConfig)

export type Context = {
	character: Model,
	player: Player?,
}

type Handler = (context: Context, params: { [string]: any }) -> ()

local ActionController = {}

local handlers: { [string]: Handler } = {}

function ActionController.register(actionId: string, handler: Handler): ()
	if handlers[actionId] then
		warn(`[ActionController] Overwriting existing handler for '{actionId}'`)
	end
	handlers[actionId] = handler
end

function ActionController.isRegistered(actionId: string): boolean
	return handlers[actionId] ~= nil
end

-- Central state gate. True if any attribute in the action's blockedBy list is currently set on the
-- character. `phase` is params.phase, the value the handler branches on; teardown phases ("stop")
-- bypass the gate entirely, so releasing a Hold (Charge/Block) can never be blocked -- otherwise a
-- player CC'd mid-hold would be stuck holding it forever.
local function isBlocked(character: Model, def: ActionConfig.ActionDef, phase: any): boolean
	if phase == "stop" then
		return false
	end
	local blockedBy = def.blockedBy
	if not blockedBy then
		return false
	end
	for _, attr in blockedBy do
		if character:GetAttribute(attr) then
			return true
		end
	end
	return false
end

function ActionController.perform(character: Model, actionId: string, params: { [string]: any }?): boolean
	local handler = handlers[actionId]
	if not handler then
		warn(`[ActionController] No handler registered for '{actionId}'`)
		return false
	end

	if not character or not character.Parent then
		return false
	end

	local def = ActionConfig[actionId]
	local phase = if params then params.phase else nil

	-- Single source of truth for "can this action start right now" (see ActionConfig.blockedBy).
	if def and isBlocked(character, def, phase) then
		return false
	end

	-- Committing to an offensive action ends spawn protection ("you've done something"). Cleared
	-- before the handler runs so the shield is already down for whatever the action sets in motion.
	if def and def.dropsProtection and phase ~= "stop" and character:GetAttribute("Forcefield") then
		character:SetAttribute("Forcefield", false)
	end

	local context: Context = {
		character = character,
		player = Players:GetPlayerFromCharacter(character),
	}

	local ok, err = pcall(handler :: (Context, { [string]: any }) -> any, context, params or {})
	if not ok then
		warn(`[ActionController] '{actionId}' handler errored: {tostring(err)}`)
		return false
	end

	return true
end

return ActionController
