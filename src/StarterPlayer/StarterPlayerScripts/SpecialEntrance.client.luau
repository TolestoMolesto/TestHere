--!strict
-- Plays an entrance fanfare for EVERYONE in the server when the special person joins. Purely
-- cosmetic and client-side (an SFX one-shot): other players hear it via PlayerAdded, and the
-- special person hears their own on load, since a client never catches its own PlayerAdded.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Audio = require(ReplicatedStorage.Modules.Audio)

local SPECIAL_USER_ID = 4304799360

local function playEntrance(): ()
	Audio.play(Audio.SFX.SpecialJoin)
end

-- Already in the server when this runs? Then it's the special person's own join -- play it.
if Players.LocalPlayer.UserId == SPECIAL_USER_ID then
	playEntrance()
end

Players.PlayerAdded:Connect(function(player: Player): ()
	if player.UserId == SPECIAL_USER_ID then
		playEntrance()
	end
end)
