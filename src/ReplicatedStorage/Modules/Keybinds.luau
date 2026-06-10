--!strict
-- CLIENT-ONLY mutable singleton (like Settings -- requiring on the server would share one player's
-- binds across everyone). Holds the active key per rebindable action, pushes each change to the
-- server, and notifies listeners so controllers re-read live. Catalogue + defaults live in KeybindConfig.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local KeybindConfig = require(ReplicatedStorage.Modules.KeybindConfig)

local Keybinds = {}

export type Bind = KeybindConfig.Bind

-- A bind is a keyboard KeyCode or a mouse UserInputType. Persisted as "<K|U>:<EnumItemName>".
local function serialize(bind: Bind): string
	local item = bind :: any
	if item.EnumType == Enum.KeyCode then
		return "K:" .. item.Name
	end
	return "U:" .. item.Name
end

local function deserialize(str: string): Bind?
	local kind, name = string.match(str, "^(%a):(.+)$")
	if not name then
		return nil
	end
	local ok, item = pcall(function(): any
		if kind == "K" then
			return (Enum.KeyCode :: any)[name]
		elseif kind == "U" then
			return (Enum.UserInputType :: any)[name]
		end
		return nil
	end)
	return if ok then item else nil
end

local active: { [string]: Bind } = {}
for id, entry in KeybindConfig do
	active[id] = entry.default
end

local listeners: { (action: string, bind: Bind) -> () } = {}

local function fireChanged(action: string, bind: Bind): ()
	for _, fn in listeners do
		task.spawn(fn, action, bind)
	end
end

local function push(action: string, bind: Bind): ()
	if not RunService:IsClient() then
		return
	end
	local Remotes = require(ReplicatedStorage.Modules.Remotes)
	Remotes.UpdateKeybind:FireServer(action, serialize(bind))
end

function Keybinds.get(action: string): Bind?
	return active[action]
end

-- The bind-equivalent of a raw input: its KeyCode (keyboard) or UserInputType (mouse button), or nil
-- for input we never bind. Stored the same way a bind is, so `fromInput(i) == get(a)` just works.
function Keybinds.fromInput(input: InputObject): Bind?
	if input.UserInputType == Enum.UserInputType.Keyboard then
		return input.KeyCode
	elseif
		input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.MouseButton2
		or input.UserInputType == Enum.UserInputType.MouseButton3
	then
		return input.UserInputType
	end
	return nil
end

-- True when a raw input is the bind for `action`. Use this instead of `fromInput(i) == get(a)` --
-- comparing the KeyCode|UserInputType union with == trips strict-mode type checking.
function Keybinds.matches(input: InputObject, action: string): boolean
	local bind = Keybinds.fromInput(input)
	return bind ~= nil and (bind :: any) == active[action]
end

-- Held-state poll that works for a key or a mouse button (held actions like flight ascend/descend).
function Keybinds.isDown(action: string): boolean
	local bind: Bind? = active[action]
	if bind == nil then
		return false
	end
	local item = bind :: any
	if item.EnumType == Enum.KeyCode then
		return UserInputService:IsKeyDown(item)
	end
	return UserInputService:IsMouseButtonPressed(item)
end

-- Assign `bind` to `action`. If another action holds it, the two swap so nothing is left unbound.
function Keybinds.set(action: string, bind: Bind): boolean
	if KeybindConfig[action] == nil then
		return false
	end
	local previous = active[action]
	if (previous :: any) == bind then
		return true
	end
	for otherId, otherBind in active do
		if otherId ~= action and (otherBind :: any) == bind then
			active[otherId] = previous
			fireChanged(otherId, previous)
			push(otherId, previous)
			break
		end
	end
	active[action] = bind
	fireChanged(action, bind)
	push(action, bind)
	return true
end

function Keybinds.resetDefaults(): ()
	for id, entry in KeybindConfig do
		if (active[id] :: any) ~= entry.default then
			active[id] = entry.default
			fireChanged(id, entry.default)
			push(id, entry.default)
		end
	end
end

-- Apply the saved blob (action -> serialized string) over the defaults, without echoing back.
function Keybinds.hydrate(blob: { [string]: any }?): ()
	if typeof(blob) ~= "table" then
		return
	end
	for action, str in blob do
		if KeybindConfig[action] ~= nil and typeof(str) == "string" then
			local bind = deserialize(str)
			if bind then
				active[action] = bind
				fireChanged(action, bind)
			end
		end
	end
end

function Keybinds.onChanged(fn: (action: string, bind: Bind) -> ()): () -> ()
	table.insert(listeners, fn)
	return function()
		local index = table.find(listeners, fn)
		if index then
			table.remove(listeners, index)
		end
	end
end

return Keybinds
