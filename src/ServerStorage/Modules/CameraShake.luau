--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Modules.Remotes)

export type Intensity = number

local CameraShake = {}

CameraShake.Intensity = {
	Light = 0.5,
	Medium = 1.0,
	Heavy = 2.0,
	Extreme = 3.0,
}

function CameraShake.shakeAll(intensity: Intensity, duration: number): ()
	for _, player in Players:GetPlayers() do
		Remotes.CameraShake:FireClient(player, intensity, duration)
	end
end

function CameraShake.shakePlayer(player: Player, intensity: Intensity, duration: number): ()
	Remotes.CameraShake:FireClient(player, intensity, duration)
end

function CameraShake.shakeNear(position: Vector3, radius: number, intensity: Intensity, duration: number): ()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end

		local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then
			continue
		end

		local distance = (hrp.Position - position).Magnitude
		if distance > radius then
			continue
		end

		local scaledIntensity = intensity * (1 - distance / radius)
		Remotes.CameraShake:FireClient(player, scaledIntensity, duration)
	end
end

return CameraShake
