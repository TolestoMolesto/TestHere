--!strict
-- Ki-suppression output dial (client input half; PowerOutputServer is the authority). The bracket keys
-- (RaisePower / LowerPower, default ] and [) step the slot's shown power output by 10%, between 1 and
-- 100. State is read live off Humanoid.Stats -- CanSuppress gates the dial, PowerOutput is the current
-- value -- and the target % is pushed via SetPowerOutput; the reduced readout returns as replicated
-- attributes (no echo). Does nothing unless the slot owns the passive (the HUD likewise hides the
-- readout then). The Settings panel exposes the same dial as a slider.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Keybinds = require(ReplicatedStorage.Modules.Keybinds)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local player = Players.LocalPlayer :: Player

local STEP = 10
local MIN_OUTPUT = 1
local MAX_OUTPUT = 100

-- The local character's Humanoid.Stats folder, resolved live so respawns need no rebinding.
local function getStats(): Folder?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local stats = humanoid and humanoid:FindFirstChild("Stats")
	return if stats and stats:IsA("Folder") then stats else nil
end

-- Snap to the 10-grid in the direction pressed, clamped to [1,100]. Lowering from 10 lands on the 1%
-- floor; raising from 1 lands on 10.
local function step(current: number, dir: number): number
	local target: number
	if dir > 0 then
		target = math.floor(current / STEP) * STEP + STEP
	else
		target = math.ceil(current / STEP) * STEP - STEP
	end
	return math.clamp(target, MIN_OUTPUT, MAX_OUTPUT)
end

local function adjust(dir: number): ()
	local stats = getStats()
	if not stats then
		return
	end
	-- No passive -> the dial is inert (and the HUD readout is hidden).
	if stats:GetAttribute("CanSuppress") ~= true then
		return
	end
	local raw = stats:GetAttribute("PowerOutput")
	local current = if typeof(raw) == "number" then raw else MAX_OUTPUT
	local target = step(current, dir)
	if target ~= current then
		Remotes.SetPowerOutput:FireServer(target)
	end
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean): ()
	if gameProcessed then
		return
	end
	if Keybinds.matches(input, "RaisePower") then
		adjust(1)
	elseif Keybinds.matches(input, "LowerPower") then
		adjust(-1)
	end
end)
