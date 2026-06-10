--!strict
-- Solar Flare: a blinding flash. Deals no damage -- it sets a server-authoritative BlindUntil
-- timestamp on every nearby enemy (compared against workspace:GetServerTimeNow() by the Phase 3
-- client white-out) and plays a cosmetic radial flash. Ported from GlobalSkillSet; the old
-- SolarFlareBlind remote becomes the attribute-driven blind read in Phase 3.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = require(ServerStorage.Modules.Skills.Shared)
local SkillState = require(ServerStorage.Modules.SkillState)

local RANGE = 50
local BLIND_DURATION = 5
local CAST_TIME = 0.5

return function(context: SkillState.Context): ()
	local character = context.character
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	Shared.playAnim(character, "SolarFlare")
	character:SetAttribute("Casting", true)

	-- Cosmetic radial flash (guarded).
	local template = Shared.skillAsset("Solar Flare")
	if template and template:IsA("BasePart") then
		local flash = template:Clone()
		flash.Anchored = true
		flash.CanCollide = false
		flash.CFrame = root.CFrame
		flash.Size = Vector3.new(1, 1, 1)
		flash.Parent = Shared.effectsFolder()
		TweenService:Create(flash, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(RANGE * 2, RANGE * 2, RANGE * 2),
			Transparency = 1,
		}):Play()
		Debris:AddItem(flash, 0.4)
	end

	-- Blind every player in range (not the caster). Server sets the state; the client reads it.
	local origin = root.Position
	local blindUntil = Workspace:GetServerTimeNow() + BLIND_DURATION
	for _, other in Players:GetPlayers() do
		local otherChar = other.Character
		local otherRoot = otherChar and otherChar:FindFirstChild("HumanoidRootPart") :: BasePart?
		if otherChar and otherChar ~= character and otherRoot and (otherRoot.Position - origin).Magnitude <= RANGE then
			otherChar:SetAttribute("BlindUntil", blindUntil)
		end
	end

	task.wait(CAST_TIME)

	character:SetAttribute("Casting", false)
	Shared.stopAnim(character, "SolarFlare")
end
