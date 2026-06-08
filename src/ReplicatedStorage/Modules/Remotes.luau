-- ─────────────────────────────────────────────
-- Remotes.luau
-- Single registry for every RemoteEvent / RemoteFunction.
--
-- Server: creates each remote once at module-load, no find-or-create.
--   If something with the same name already exists, that's a real bug
--   and we want to know about it -- callers should never accidentally
--   shadow another script's remote.
--
-- Client: WaitForChild's each one with a timeout. If a remote never
--   appears we error loudly -- that means the server registry didn't
--   run, not that a consumer missed the lookup.
--
-- To add a remote, add one line to the table at the bottom.
-- Consumers: `local Remotes = require(ReplicatedStorage.Modules.Remotes)`
-- then `Remotes.ProfileLoaded:FireClient(player)`.
-- ─────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()
local WAIT_TIMEOUT = 10
local FOLDER_NAME = "Remotes"

local folder: Folder
if IS_SERVER then
	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = ReplicatedStorage
else
	local found = ReplicatedStorage:WaitForChild(FOLDER_NAME, WAIT_TIMEOUT)
	assert(found and found:IsA("Folder"), `Remotes folder never appeared in ReplicatedStorage`)
	folder = found
end

local function declareEvent(name: string): RemoteEvent
	if IS_SERVER then
		local ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = folder
		return ev
	end
	local inst = folder:WaitForChild(name, WAIT_TIMEOUT)
	assert(inst and inst:IsA("RemoteEvent"), `Remotes.{name} never appeared on the client (or was the wrong class)`)
	return inst
end

local function declareFunction(name: string): RemoteFunction
	if IS_SERVER then
		local fn = Instance.new("RemoteFunction")
		fn.Name = name
		fn.Parent = folder
		return fn
	end
	local inst = folder:WaitForChild(name, WAIT_TIMEOUT)
	assert(inst and inst:IsA("RemoteFunction"), `Remotes.{name} never appeared on the client (or was the wrong class)`)
	return inst
end

local function declareBindable(name: string): BindableFunction
	if IS_SERVER then
		local fn = Instance.new("BindableFunction")
		fn.Name = name
		fn.Parent = folder
		return fn
	end
	local inst = folder:WaitForChild(name, WAIT_TIMEOUT)
	assert(inst and inst:IsA("BindableFunction"), `Remotes.{name} never appeared on the client (or was the wrong class)`)
	return inst
end

local Remotes = {
	ProfileLoaded = declareEvent("ProfileLoaded"),
	PlayEmote = declareBindable("PlayEmote"),
}

return Remotes
