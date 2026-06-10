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
	-- (Code redemption is a separate system, not wired here.)
	GetRollState = declareFunction("GetRollState"),
	RollSlot = declareFunction("RollSlot"),
	PickRace = declareFunction("PickRace"),

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
}

return Remotes
