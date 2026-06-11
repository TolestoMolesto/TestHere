-- Server entry for the redeem-code system, mirroring MailServer/ItemServer. Wires the RedeemCode remote
-- to Codes.redeem and nothing else: the catalogue, requirement checks, one-time-per-account dedupe, and
-- reward delivery (instant Spins/Passes; Items via mail) all live in Codes.luau. This file only sanitises
-- the request shape and forwards the `source` ("MainMenu" | "Settings") so race-gated codes can be kept to
-- the in-game Settings box. The catalogue never leaves the server -- only the result { ok, message } crosses.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Codes = require(ServerStorage.Modules.Codes)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

Remotes.RedeemCode.OnServerInvoke = function(player: Player, code: any, source: any)
	local ok, message = Codes.redeem(player, code, source)
	return { ok = ok, message = message }
end
