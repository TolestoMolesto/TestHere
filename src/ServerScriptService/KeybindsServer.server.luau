--!strict
-- Persists player Keybinds to GLOBAL profile data (PlayerData.Keybinds, action id -> serialized
-- bind). Clients pull their saved overrides via GetKeybinds on load and push one action per rebind
-- via UpdateKeybind. Every value is re-validated here -- the client is never trusted.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local KeybindConfig = require(ReplicatedStorage.Modules.KeybindConfig)
local Manager = require(ServerStorage.Modules.Manager)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

-- A valid serialized bind: "K:<KeyCodeName>" naming a real KeyCode, or "U:<MouseButtonN>".
local function validBind(value: any): boolean
	if typeof(value) ~= "string" then
		return false
	end
	local kind, name = string.match(value, "^(%a):(.+)$")
	if not name then
		return false
	end
	if kind == "K" then
		local ok = pcall(function()
			return (Enum.KeyCode :: any)[name]
		end)
		return ok
	elseif kind == "U" then
		return name == "MouseButton1" or name == "MouseButton2" or name == "MouseButton3"
	end
	return false
end

Remotes.GetKeybinds.OnServerInvoke = function(player: Player): any
	local profile = Manager.getProfile(player)
	return if profile then profile.Data.Keybinds else nil
end

Remotes.UpdateKeybind.OnServerEvent:Connect(function(player: Player, action: any, value: any)
	if typeof(action) ~= "string" or KeybindConfig[action] == nil then
		return
	end
	if not validBind(value) then
		return
	end
	local profile = Manager.getProfile(player)
	if not profile then
		return
	end
	local binds = profile.Data.Keybinds :: any
	if typeof(binds) == "table" then
		binds[action] = value
	end
end)
