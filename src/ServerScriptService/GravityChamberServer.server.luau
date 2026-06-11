--!strict
-- The Gravity Chamber dial + ownership (model B): in the Gravity Chamber world ONLY, ONE player at a
-- time -- the "owner" -- drives the SERVER-WIDE Workspace.Gravity through an on-screen panel
-- (GravityChamberController). Everyone in the server feels each change physically; GravityServer reads
-- the live Workspace.Gravity for movement/bleed/acclimation.
--
-- Ownership is first-come (mirrors the Party leader pattern): the earliest player in the server owns the
-- dial and it auto-passes to the next-longest-present player when the owner leaves -- or to whoever the
-- owner hands it to. Gravity is set in "x Earth" multiples, floored at MIN_MULT and otherwise
-- effectively UNCAPPED (a finite MAX only so Workspace.Gravity never becomes inf/NaN) -- crank it to
-- absurd, lethal values on purpose if you like.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Gravity = require(ServerStorage.Modules.Gravity)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local ServerSettings = require(ServerStorage.Modules.ServerSettings)

local MAX_MULT = 1e9 -- finite only so gravity stays a real number; far above any value anyone reaches

type ChamberState = { multiplier: number, ownerUserId: number, baseMultiplier: number }

-- Only the Gravity Chamber place runs a live chamber; elsewhere the remotes return nil / ignore so
-- GravityChamberController hides its panel.
local world = ServerSettings.getCurrentWorld()
local isChamber = world == "GravityChamber"

-- The dial floors at the PLACE's own base gravity (its ServerSettings env) -- you crank UP from the
-- planet's natural pull and never below it. Reset returns here; uncapped above (bar the finite MAX).
local FLOOR_MULT = 1
do
	local env = if world then ServerSettings.getEnvironment(world) else nil
	if env then
		FLOOR_MULT = env.gravity / Gravity.DEFAULT_GRAVITY
	end
end

-- Join-order list (earliest first) decides who inherits the dial; `owner` is the current controller.
local order: { Player } = {}
local owner: Player? = nil

local function currentMult(): number
	return Workspace.Gravity / Gravity.DEFAULT_GRAVITY
end

local function stateFor(): ChamberState
	return {
		multiplier = currentMult(),
		ownerUserId = if owner then owner.UserId else 0,
		baseMultiplier = FLOOR_MULT,
	}
end

local function broadcast(): ()
	local state = stateFor()
	for _, p in Players:GetPlayers() do
		Remotes.ChamberStateChanged:FireClient(p, state)
	end
end

local function indexOf(player: Player): number?
	for i, p in order do
		if p == player then
			return i
		end
	end
	return nil
end

local function addPlayer(player: Player): ()
	if not indexOf(player) then
		table.insert(order, player)
	end
	if owner == nil then
		owner = player
	end
	broadcast()
end

local function removePlayer(player: Player): ()
	local idx = indexOf(player)
	if idx then
		table.remove(order, idx)
	end
	if owner == player then
		owner = order[1] -- next-longest-present, or nil once the room empties
	end
	broadcast()
end

Remotes.GetChamberState.OnServerInvoke = function(_player: Player): ChamberState?
	return if isChamber then stateFor() else nil
end

Remotes.RequestChamberGravity.OnServerEvent:Connect(function(player: Player, targetValue: any)
	if not isChamber or player ~= owner or typeof(targetValue) ~= "number" then
		return
	end
	if targetValue ~= targetValue then -- reject NaN; +inf clamps to MAX below
		return
	end
	Workspace.Gravity = math.clamp(targetValue, FLOOR_MULT, MAX_MULT) * Gravity.DEFAULT_GRAVITY
	broadcast()
end)

Remotes.TransferChamberOwner.OnServerEvent:Connect(function(player: Player, targetValue: any)
	if not isChamber or player ~= owner then
		return
	end
	if typeof(targetValue) ~= "Instance" or not targetValue:IsA("Player") then
		return
	end
	local target = targetValue :: Player
	if target ~= player and indexOf(target) then
		owner = target
		broadcast()
	end
end)

if isChamber then
	for _, p in Players:GetPlayers() do
		addPlayer(p)
	end
	Players.PlayerAdded:Connect(addPlayer)
	Players.PlayerRemoving:Connect(removePlayer)
end
