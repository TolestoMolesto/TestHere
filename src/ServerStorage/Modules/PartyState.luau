--!strict
-- In-memory party registry: a Leader + up to 5 others (6 max). Parties live only for the life of the
-- server -- nothing is persisted to the profile; this is "just a roster" with hooks for perks later.
-- This module owns the data and every mutation. Mutations return the list of players whose roster
-- view changed (including anyone who just left, so their UI clears) -- PartyServer broadcasts the
-- fresh roster to each. Invites are single-pending per invitee (a newer invite replaces an older one).

local MAX_MEMBERS = 6
local INVITE_TTL = 30 -- seconds a pending invite stays valid

export type Party = {
	id: string,
	leader: Player,
	members: { Player }, -- includes the leader; order is stable
}

type Invite = {
	partyId: string,
	from: Player,
	expires: number,
}

export type RosterMember = { userId: number, name: string, displayName: string }
export type Roster = { id: string, leaderUserId: number, members: { RosterMember } }

local PartyState = {}

local parties: { [string]: Party } = {}
local partyOf: { [Player]: string } = {}
local invites: { [Player]: Invite } = {}

local nextId = 0
local function newId(): string
	nextId += 1
	return `party_{nextId}`
end

local function indexOf(list: { Player }, player: Player): number?
	for i, p in list do
		if p == player then
			return i
		end
	end
	return nil
end

function PartyState.getParty(player: Player): Party?
	local id = partyOf[player]
	return if id then parties[id] else nil
end

-- Pull the player's pending invite, lazily dropping it if it expired or its party is gone.
function PartyState.getInvite(player: Player): Invite?
	local invite = invites[player]
	if not invite then
		return nil
	end
	if os.time() > invite.expires or not parties[invite.partyId] then
		invites[player] = nil
		return nil
	end
	return invite
end

-- The inviter must be solo or the leader of a not-full party; the target must be a different,
-- party-less player. A solo inviter spins up a fresh party (themselves as leader) on the fly.
-- Returns ok + a short reason on failure (surfaced to the inviter's client).
function PartyState.invite(from: Player, target: Player): (boolean, string?)
	if target == from then
		return false, "You can't invite yourself."
	end
	if PartyState.getParty(target) then
		return false, "They're already in a party."
	end

	local existing = PartyState.getParty(from)
	local party: Party
	if existing then
		if existing.leader ~= from then
			return false, "Only the leader can invite."
		end
		if #existing.members >= MAX_MEMBERS then
			return false, "Your party is full."
		end
		party = existing
	else
		-- Inviter is solo: spin up a fresh party with them as leader.
		party = {
			id = newId(),
			leader = from,
			members = { from },
		}
		parties[party.id] = party
		partyOf[from] = party.id
	end

	invites[target] = {
		partyId = party.id,
		from = from,
		expires = os.time() + INVITE_TTL,
	}
	return true
end

-- Resolve the player's pending invite. Re-validates (party still exists + has room) since both can
-- change between invite and accept. Returns the joined party, or nil + reason.
function PartyState.acceptInvite(player: Player): (Party?, string?)
	if PartyState.getParty(player) then
		return nil, "You're already in a party."
	end
	local invite = PartyState.getInvite(player)
	if not invite then
		return nil, "That invite expired."
	end
	invites[player] = nil
	local party = parties[invite.partyId]
	if not party then
		return nil, "That party no longer exists."
	end
	if #party.members >= MAX_MEMBERS then
		return nil, "That party is full."
	end
	table.insert(party.members, player)
	partyOf[player] = party.id
	return party
end

function PartyState.declineInvite(player: Player): ()
	invites[player] = nil
end

-- Detach a player from a party, promoting a new leader if the leader left and disbanding the party
-- once the last member is gone.
local function detach(player: Player, party: Party): ()
	partyOf[player] = nil
	local idx = indexOf(party.members, player)
	if idx then
		table.remove(party.members, idx)
	end
	if #party.members == 0 then
		parties[party.id] = nil
	elseif party.leader == player then
		party.leader = party.members[1]
	end
end

function PartyState.leave(player: Player): { Player }
	local party = PartyState.getParty(player)
	if not party then
		return {}
	end
	local affected = table.clone(party.members) -- snapshot before removal (includes the leaver)
	detach(player, party)
	return affected
end

-- Leader removes another member. Returns affected players (empty when not allowed).
function PartyState.kick(leader: Player, target: Player): { Player }
	local party = PartyState.getParty(leader)
	if not party or party.leader ~= leader then
		return {}
	end
	if target == leader or PartyState.getParty(target) ~= party then
		return {}
	end
	local affected = table.clone(party.members)
	detach(target, party)
	return affected
end

-- Leader dissolves the whole party. Returns every ex-member to refresh (their UIs clear).
function PartyState.disband(leader: Player): { Player }
	local party = PartyState.getParty(leader)
	if not party or party.leader ~= leader then
		return {}
	end
	local affected = table.clone(party.members)
	for _, member in affected do
		partyOf[member] = nil
	end
	parties[party.id] = nil
	return affected
end

-- Leader hands leadership to another member of the same party.
function PartyState.promote(leader: Player, target: Player): { Player }
	local party = PartyState.getParty(leader)
	if not party or party.leader ~= leader then
		return {}
	end
	if target == leader or PartyState.getParty(target) ~= party then
		return {}
	end
	party.leader = target
	return table.clone(party.members)
end

-- Disconnect cleanup: drop the player from any party and clear invites to/from them.
function PartyState.playerLeaving(player: Player): { Player }
	invites[player] = nil
	local toClear: { Player } = {}
	for invitee, invite in invites do
		if invite.from == player then
			table.insert(toClear, invitee)
		end
	end
	for _, invitee in toClear do
		invites[invitee] = nil
	end
	return PartyState.leave(player)
end

-- Client-safe snapshot of a player's current party (nil when party-less). Names only -- "just a
-- roster"; live stats (BP/HP) are read by the client off each member's character if it wants them.
function PartyState.rosterFor(player: Player): Roster?
	local party = PartyState.getParty(player)
	if not party then
		return nil
	end
	local members: { RosterMember } = {}
	for _, member in party.members do
		table.insert(members, {
			userId = member.UserId,
			name = member.Name,
			displayName = member.DisplayName,
		})
	end
	return {
		id = party.id,
		leaderUserId = party.leader.UserId,
		members = members,
	}
end

return PartyState
