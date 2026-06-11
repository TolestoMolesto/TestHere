--!strict
-- Consensual 1v1 spar ("training duel"): a bout between two players that is deliberately
-- consequence-free. It never combat-tags the fighters, and it never kills -- a blow that would down
-- your partner ends the bout with a FULL restore (first down wins). The two interrupting rules live
-- here too: an outside player or NPC landing a hit on a fighter CANCELS the bout and reverts BOTH to
-- their pre-spar Health/Ki/Stamina (Spar.interfere, called from Damage.apply), and a fighter dying,
-- straying too far, or entering a safe zone ends it cleanly (the leash watchdog). State is in-memory
-- and per-server. Spar hits still feed the passive Train system -- that happens naturally through the
-- attack modules' existing Train hooks, so there's nothing to do here for it.
--
-- This module is required eagerly by SparServer (which starts the watchdog) and lazily by Damage
-- (the interference + knockout-to-restore hooks). It must NOT require Damage, to keep that one-way.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CombatTag = require(ServerStorage.Modules.CombatTag)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local SPAR_REQUEST_RANGE = 60 -- studs the fighters must be within to start a bout
local SPAR_LEASH_RANGE = 250 -- studs apart before an active bout ends on its own
local LEASH_CHECK_INTERVAL = 1 -- seconds between watchdog sweeps
local REQUEST_TTL = 20 -- seconds a pending challenge stays open

type Snapshot = { health: number, ki: number, stamina: number }
type Request = { from: Player, expires: number }

export type Session = {
	id: string,
	a: Player,
	b: Player,
	snapshots: { [Player]: Snapshot },
}

local Spar = {}

local sessions: { [string]: Session } = {}
local sparOf: { [Player]: string } = {} -- player -> active session id
local pending: { [Player]: Request } = {} -- invitee -> the challenge they were sent

local nextId = 0
local function newId(): string
	nextId += 1
	return `spar_{nextId}`
end

local function rootOf(character: Model): BasePart?
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- The player's character only if it exists and is alive (nil otherwise).
local function aliveCharacter(player: Player): Model?
	local character = player.Character
	if not character or not character.Parent then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character
end

local function snapshot(character: Model): Snapshot
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return {
		health = if humanoid then humanoid.Health else 0,
		ki = (character:GetAttribute("Ki") :: number?) or 0,
		stamina = (character:GetAttribute("Stamina") :: number?) or 0,
	}
end

-- Write a remembered snapshot back (the interference revert). Clamps to current maxima in case a
-- transformation changed them mid-bout.
local function restoreSnapshot(character: Model, snap: Snapshot): ()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = math.min(snap.health, humanoid.MaxHealth)
	end
	local maxKi = (character:GetAttribute("MaxKi") :: number?) or snap.ki
	local maxStamina = (character:GetAttribute("MaxStamina") :: number?) or snap.stamina
	character:SetAttribute("Ki", math.min(snap.ki, maxKi))
	character:SetAttribute("Stamina", math.min(snap.stamina, maxStamina))
end

-- Top off Health/Ki/Stamina (the clean-end / knockdown restore).
local function fullRestore(character: Model): ()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
	end
	character:SetAttribute("Ki", (character:GetAttribute("MaxKi") :: number?) or 0)
	character:SetAttribute("Stamina", (character:GetAttribute("MaxStamina") :: number?) or 0)
end

-- Shared eligibility for starting (or re-validating) a bout. Returns ok + a short reason.
local function canEngage(a: Player, b: Player): (boolean, string?)
	local ca, cb = aliveCharacter(a), aliveCharacter(b)
	if not ca or not cb then
		return false, "Both fighters must be alive."
	end
	if sparOf[a] or sparOf[b] then
		return false, "Someone is already sparring."
	end
	-- Gate spar-start behind "not in combat" so it can't be used as a free heal mid-fight.
	if CombatTag.isInCombat(ca) or CombatTag.isInCombat(cb) then
		return false, "Can't spar while in combat."
	end
	local ra, rb = rootOf(ca), rootOf(cb)
	if not ra or not rb or (ra.Position - rb.Position).Magnitude > SPAR_REQUEST_RANGE then
		return false, "Get closer to spar."
	end
	return true
end

local function sessionFromChar(character: Model): Session?
	local id = character:GetAttribute("InSpar")
	if type(id) ~= "string" or id == "" then
		return nil
	end
	return sessions[id]
end

-- Tear a bout down exactly once: clear InSpar + registry for both fighters, restore each per
-- `restoreMode` ("full" | "snapshot" | "none"), and tell each present client the outcome string.
local function endSession(session: Session, restoreMode: { [Player]: string }, result: { [Player]: string }): ()
	if sessions[session.id] == nil then
		return -- already ended
	end
	sessions[session.id] = nil
	for _, player in { session.a, session.b } do
		sparOf[player] = nil
		local character = player.Character
		if character and character:GetAttribute("InSpar") == session.id then
			character:SetAttribute("InSpar", "")
			local mode = restoreMode[player]
			if mode == "full" then
				fullRestore(character)
			elseif mode == "snapshot" then
				restoreSnapshot(character, session.snapshots[player])
			end
		end
		if player.Parent then
			Remotes.SparEnded:FireClient(player, result[player] or "ended")
		end
	end
end

-- Send a challenge. Both must be alive, near each other, out of combat, and free of any current bout.
function Spar.request(from: Player, target: Player): (boolean, string?)
	if from == target then
		return false, "You can't spar yourself."
	end
	local ok, reason = canEngage(from, target)
	if not ok then
		return false, reason
	end
	pending[target] = { from = from, expires = os.time() + REQUEST_TTL }
	return true
end

-- Resolve the player's pending challenge into a live bout. Re-validates eligibility (state can change
-- between challenge and accept), snapshots both fighters, marks them, and returns the opponent so the
-- server can announce the start to both. Returns nil + reason on failure.
function Spar.accept(player: Player): (Player?, string?)
	local req = pending[player]
	pending[player] = nil
	if not req or os.time() > req.expires then
		return nil, "That challenge expired."
	end
	local from = req.from
	local ok, reason = canEngage(from, player)
	if not ok then
		return nil, reason
	end
	local ca, cb = aliveCharacter(from), aliveCharacter(player)
	if not ca or not cb then
		return nil, "Both fighters must be alive."
	end

	local id = newId()
	sessions[id] = {
		id = id,
		a = from,
		b = player,
		snapshots = { [from] = snapshot(ca), [player] = snapshot(cb) },
	}
	sparOf[from] = id
	sparOf[player] = id
	ca:SetAttribute("InSpar", id)
	cb:SetAttribute("InSpar", id)
	return from
end

function Spar.decline(player: Player): ()
	pending[player] = nil
end

-- A partner's blow downed `loserChar` (called from Damage.apply). First down wins: full-restore both
-- and end the bout. The winner is simply the other side of the session.
function Spar.onDown(loserChar: Model): ()
	local session = sessionFromChar(loserChar)
	if not session then
		return
	end
	local loser = if session.a.Character == loserChar then session.a else session.b
	local winner = if loser == session.a then session.b else session.a
	endSession(session, { [session.a] = "full", [session.b] = "full" }, { [loser] = "loss", [winner] = "win" })
end

-- An outsider (player or NPC) hit a fighter (called from Damage.apply). Cancel the bout and revert
-- BOTH to their pre-spar Health/Ki/Stamina; the interrupting hit then lands as normal combat.
function Spar.interfere(victimChar: Model): ()
	local session = sessionFromChar(victimChar)
	if not session then
		return
	end
	endSession(
		session,
		{ [session.a] = "snapshot", [session.b] = "snapshot" },
		{ [session.a] = "interrupted", [session.b] = "interrupted" }
	)
end

-- A fighter ended the bout themselves. Clean end: full-restore both, no winner.
function Spar.forfeit(player: Player): ()
	local id = sparOf[player]
	if not id then
		return
	end
	local session = sessions[id]
	if not session then
		sparOf[player] = nil
		return
	end
	endSession(
		session,
		{ [session.a] = "full", [session.b] = "full" },
		{ [session.a] = "ended", [session.b] = "ended" }
	)
end

-- Disconnect cleanup: drop challenges to/from the player and end any active bout (the survivor is
-- full-restored; the leaver needs nothing).
function Spar.playerLeaving(player: Player): ()
	pending[player] = nil
	local toClear: { Player } = {}
	for invitee, req in pending do
		if req.from == player then
			table.insert(toClear, invitee)
		end
	end
	for _, invitee in toClear do
		pending[invitee] = nil
	end

	local id = sparOf[player]
	if not id then
		return
	end
	local session = sessions[id]
	if not session then
		sparOf[player] = nil
		return
	end
	local other = if session.a == player then session.b else session.a
	endSession(session, { [player] = "none", [other] = "full" }, { [other] = "ended" })
end

-- Leash watchdog: end any bout whose fighters die, separate beyond SPAR_LEASH_RANGE, or step into a
-- safe zone. Clean end (full-restore both, no winner). Runs for the life of the server.
task.spawn(function()
	while true do
		task.wait(LEASH_CHECK_INTERVAL)
		local toEnd: { Session } = {}
		for _, session in sessions do
			local ca, cb = aliveCharacter(session.a), aliveCharacter(session.b)
			if not ca or not cb then
				table.insert(toEnd, session)
			else
				local ra, rb = rootOf(ca), rootOf(cb)
				local tooFar = not ra or not rb or (ra.Position - rb.Position).Magnitude > SPAR_LEASH_RANGE
				local inSafeZone = ca:GetAttribute("InSafeZone") or cb:GetAttribute("InSafeZone")
				if tooFar or inSafeZone then
					table.insert(toEnd, session)
				end
			end
		end
		for _, session in toEnd do
			endSession(
				session,
				{ [session.a] = "full", [session.b] = "full" },
				{ [session.a] = "ended", [session.b] = "ended" }
			)
		end
	end
end)

return Spar
