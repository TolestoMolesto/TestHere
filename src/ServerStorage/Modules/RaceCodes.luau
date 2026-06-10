--!strict
-- Redeem codes that grant Race Roller rolls. Server-authoritative: the catalogue lives here and
-- never reaches the client, redemption is one-time per account (tracked in Shared.RedeemedCodes),
-- and codes are matched case-insensitively with whitespace stripped. To add a code, add a row to
-- CODES; to retire one, set active = false (kept around so already-redeemed players aren't affected).

local ServerStorage = game:GetService("ServerStorage")

local Manager = require(ServerStorage.Modules.Manager)

type Code = {
	rolls: number,
	active: boolean,
}

-- Keys MUST be the normalised (UPPERCASE, no spaces) form -- redeem() normalises input the same way.
local CODES: { [string]: Code } = {
	WELCOME = { rolls = 10, active = true },
	RELEASE = { rolls = 25, active = true },
	PONCHO = { rolls = 5, active = true },
}

local RaceCodes = {}

local function normalize(code: string): string
	return (code:gsub("%s+", "")):upper()
end

-- Returns (ok, message, rollsGranted?). message is player-facing for a toast either way.
function RaceCodes.redeem(player: Player, raw: any): (boolean, string, number?)
	if typeof(raw) ~= "string" then
		return false, "Invalid code", nil
	end
	local code = normalize(raw)
	if code == "" then
		return false, "Enter a code", nil
	end

	local entry = CODES[code]
	if not entry or not entry.active then
		return false, "Invalid or expired code", nil
	end

	local shared = Manager.getShared(player)
	if not shared then
		return false, "Profile not loaded", nil
	end
	if shared.RedeemedCodes[code] then
		return false, "Code already redeemed", nil
	end

	shared.RedeemedCodes[code] = true
	shared.Spins += entry.rolls
	return true, `Redeemed: +{entry.rolls} Rolls!`, entry.rolls
end

return RaceCodes
