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
	assert(
		inst and inst:IsA("BindableFunction"),
		`Remotes.{name} never appeared on the client (or was the wrong class)`
	)
	return inst
end

local Remotes = {
	ProfileLoaded = declareEvent("ProfileLoaded"),
	PlayEmote = declareBindable("PlayEmote"),

	-- Settings: client pulls its saved (global) blob on load, pushes one key per change.
	GetSettings = declareFunction("GetSettings"),
	UpdateSetting = declareEvent("UpdateSetting"),

	-- Keybinds: same shape -- pull saved overrides on load, push one action id per rebind.
	GetKeybinds = declareFunction("GetKeybinds"),
	UpdateKeybind = declareEvent("UpdateKeybind"),

	-- Power output (Ki suppression): client pushes the desired output % (1-100) on a bracket-key step
	-- or the Settings slider; the server clamps, gates on the PowerSuppression passive, writes the slot,
	-- and re-derives Humanoid.Stats. The reduced readout replicates back through the Stats attributes
	-- (DisplayedBattlePower / PowerOutput / CanSuppress), so no echo remote is needed.
	SetPowerOutput = declareEvent("SetPowerOutput"),

	-- Skill loadout UI: pull the active slot's sanitised catalogue + current 1-5 loadout, push one
	-- (index, skillId) per equip/unequip. Skill balance data stays server-side (SkillConfig).
	GetSkillLoadout = declareFunction("GetSkillLoadout"),
	SetSkillLoadout = declareEvent("SetSkillLoadout"),

	-- Inventory (per-slot Items): pull the active slot's sanitised item list on open + after any
	-- change, push UseItem(itemId) to consume one. InventoryChanged carries the fresh list so the bag
	-- UI live-updates after a use/grant. Item balance/config stays server-side (ItemConfig); only the
	-- curated list (counts + display + the description string) crosses.
	GetInventory = declareFunction("GetInventory"),
	UseItem = declareEvent("UseItem"),
	InventoryChanged = declareEvent("InventoryChanged"),
	-- Passives shown in the inventory's Skills tab: pull the active slot's applicable (race-driven +
	-- universal) passives. Read-only info; no slot, no use.
	GetPassives = declareFunction("GetPassives"),

	-- Action-bar HUD: pull the race's 6-0 ability line (names/cooldowns) for the form slots. Skill
	-- slot labels come from GetSkillLoadout; live cooldown/duration state is read from attributes.
	GetFormBar = declareFunction("GetFormBar"),

	-- Mail (account-wide inbox; MailServer + Mail). GetMail pulls the sanitised list (rewards resolved to
	-- display info -- item config never crosses). ClaimMail is a RemoteFunction so the client gets back
	-- { ok, reason, mail } (a claim can fail, e.g. the active slot is full). DeleteMail/MarkMailRead push
	-- one mail id. MailChanged carries the fresh list (+ drives the unread badge) after any change/grant.
	GetMail = declareFunction("GetMail"),
	ClaimMail = declareFunction("ClaimMail"),
	DeleteMail = declareEvent("DeleteMail"),
	MarkMailRead = declareEvent("MarkMailRead"),
	MailChanged = declareEvent("MailChanged"),

	-- Form/Technique loadout (keys 6-0), the Forms counterpart to the Skill loadout: pull the race's
	-- sanitised catalogue + the active slot's current 6-0 loadout, push one (index, formId) per change.
	-- FormLoadoutChanged pokes the client (ActionBar + inventory) to re-pull after a change.
	GetFormLoadout = declareFunction("GetFormLoadout"),
	SetFormLoadout = declareEvent("SetFormLoadout"),
	FormLoadoutChanged = declareEvent("FormLoadoutChanged"),

	-- Race Roller. All RemoteFunctions because the client needs the result/validation back.
	-- GetRollState: pull everything the panel shows on open (rolls, total, pity, races, globals).
	-- RollSlot(confirmed): reroll the active slot; returns the new race, or a needs-confirmation flag
	-- when it would destroy a held global. PickRace: resolve a pending global into a base race.
	-- (Code redemption is a separate system -- see RedeemCode below / CodesServer.)
	GetRollState = declareFunction("GetRollState"),
	RollSlot = declareFunction("RollSlot"),
	PickRace = declareFunction("PickRace"),

	-- Redeem codes (CodesServer + Codes). RemoteFunction: the client sends (code, source) -- source is
	-- "MainMenu" or "Settings" so the server can keep race-gated codes to the in-game Settings box -- and
	-- gets back { ok, message } to toast. The catalogue + one-time-per-account dedupe + reward delivery
	-- (instant Spins/Passes, Items via mail) all stay server-side in Codes; only the result string crosses.
	RedeemCode = declareFunction("RedeemCode"),

	-- Main Menu (Play + Slots panel; MenuServer). All RemoteFunctions -- the client needs the result.
	-- GetSlots: pull the slot roster (per-slot index/race/BattlePower/planet) + ActiveSlot + the buyable-
	-- slot economy (slots bought, max buyable, the Slot product id the client prompts). SelectSlot(index):
	-- set the active slot the Play button launches. RequestPlay(): travel to the ACTIVE slot's Planet
	-- (server reads + validates it; the client never names a place). Buying a slot is a normal Dev Product
	-- purchase (Monetization "SlotPurchase") -- no remote; new slots auto-roll a race free on first Play.
	GetSlots = declareFunction("GetSlots"),
	SelectSlot = declareFunction("SelectSlot"),
	RequestPlay = declareFunction("RequestPlay"),

	CameraShake = declareEvent("CameraShake"),
	CombatTagged = declareEvent("CombatTagged"),
	CombatTagEnded = declareEvent("CombatTagEnded"),
	-- Owner-only shadow hit FX: the server routes a shadow's hit/block sparks here so only its owner
	-- renders them -- the shadow is invisible to everyone else (see ShadowFXController).
	ShadowFX = declareEvent("ShadowFX"),
	UpdateFlightPosition = declareEvent("UpdateFlightPosition"),
	ClashShockwaves = declareEvent("ClashShockwaves"),
	Shockwaves = declareEvent("Shockwaves"),
	-- FlyOn must be a RemoteFunction: ParryHandler uses :InvokeClient (server -> client invoke).
	FlyOn = declareFunction("FlyOn"),

	PerformAction = declareEvent("PerformAction"),
	SetLockOnTarget = declareEvent("SetLockOnTarget"),

	-- Travel: client asks to hop to a named place (validated + gated server-side in TeleportServer);
	-- server fires TeleportDenied back with a reason when a gate or guard rejects the request.
	RequestTeleport = declareEvent("RequestTeleport"),
	TeleportDenied = declareEvent("TeleportDenied"),

	-- AFK system (AntiIdleController / AntiIdleServer): client pings this on the player's first input
	-- after each spawn so the server drops the spawn ForceField. No input -> the shield stays, which is
	-- what keeps an AFK player (herded to the Main Menu) protected. Ignored server-side in the Main Menu.
	PlayerActive = declareEvent("PlayerActive"),

	-- Monetization gifting: a recipient-picker fires this with (recipientUserId, passKey); the server
	-- records the recipient and prompts the buyer to pay for the matching "Gift X" product (Monetization).
	RequestGift = declareEvent("RequestGift"),

	-- Party (a Leader + up to 5 others, 6 max; PartyServer + PartyState). In-server only, never
	-- persisted. GetParty pulls the caller's current roster (nil when party-less). PartyUpdated pushes
	-- the fresh roster (or nil) to every affected member after any change; PartyInviteReceived shows the
	-- accept/decline prompt (fromDisplayName, fromUserId); PartyNotice carries a short toast string
	-- (invite failures, joins, kicks, disband). The client sends a target Player for invite/kick/promote.
	GetParty = declareFunction("GetParty"),
	PartyUpdated = declareEvent("PartyUpdated"),
	PartyNotice = declareEvent("PartyNotice"),
	PartyInviteReceived = declareEvent("PartyInviteReceived"),
	RequestPartyInvite = declareEvent("RequestPartyInvite"),
	RespondPartyInvite = declareEvent("RespondPartyInvite"),
	LeaveParty = declareEvent("LeaveParty"),
	KickFromParty = declareEvent("KickFromParty"),
	PromoteLeader = declareEvent("PromoteLeader"),
	DisbandParty = declareEvent("DisbandParty"),

	-- Spar (consensual 1v1 "training duel"; SparServer + Spar). The client sends a target Player to
	-- RequestSpar (challenge) and a boolean to RespondSpar (accept/decline); EndSpar forfeits the
	-- caller's bout. Server -> client: SparInvite shows the challenge prompt (fromDisplayName,
	-- fromUserId); SparStarted opens the bout HUD (opponentDisplayName, opponentUserId); SparEnded
	-- closes it with a result string ("win" | "loss" | "interrupted" | "ended"); SparNotice is a short
	-- toast (challenge failures). The bout never combat-tags the fighters and never kills.
	RequestSpar = declareEvent("RequestSpar"),
	RespondSpar = declareEvent("RespondSpar"),
	EndSpar = declareEvent("EndSpar"),
	SparInvite = declareEvent("SparInvite"),
	SparStarted = declareEvent("SparStarted"),
	SparEnded = declareEvent("SparEnded"),
	SparNotice = declareEvent("SparNotice"),

	-- Gravity Chamber (GravityChamberServer + GravityChamberController). Only the GravityChamber place
	-- runs a live chamber; GetChamberState returns nil elsewhere so the client hides its panel. State =
	-- { multiplier, ownerUserId }. The owner (first in, auto-reassigned on leave) is the only one whose
	-- RequestChamberGravity (an absolute x-Earth target; server floors it, no real ceiling) is honoured;
	-- TransferChamberOwner hands control to another player. ChamberStateChanged pushes fresh state to all.
	GetChamberState = declareFunction("GetChamberState"),
	ChamberStateChanged = declareEvent("ChamberStateChanged"),
	RequestChamberGravity = declareEvent("RequestChamberGravity"),
	TransferChamberOwner = declareEvent("TransferChamberOwner"),

	-- Kai-only weight granting (WeightsServer + the Party panel's "Gravity" tab). GetWeightGrant tells the
	-- client whether the local player's active slot is a Kai and their tonnage ceiling (gravity mastery);
	-- SetMemberWeight(targetPlayer, tonnage) asks the server to equip/clear a party member's weights
	-- (validated: caller is a Kai, target is in their party, tonnage clamped to [0.25, mastery]).
	GetWeightGrant = declareFunction("GetWeightGrant"),
	SetMemberWeight = declareEvent("SetMemberWeight"),
}

return Remotes
