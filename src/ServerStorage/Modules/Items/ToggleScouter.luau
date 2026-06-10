--!strict
-- Item behavior: equips/unequips a wearable scouter on the player's ACTIVE slot. The scouter this item
-- controls is named in params.scouter -- an Accessory under ServerStorage.Assets.Items (e.g.
-- "StarterScouter", "AdminScouter"). Using the item toggles that scouter: it comes off if it is already
-- the one worn, otherwise it is worn (switching away from any other). Scouters are reusable, so
-- ItemConfig sets consumeOnUse = false and ItemState never spends a stack here.
--
-- The choice is persisted in slot.ScouterEquipped so it survives respawns (PlayerRaceBuilder re-attaches
-- the accessory in buildAppearance) and is mirrored onto Humanoid.Appearance.ScouterEquipped so the
-- client ScouterController -- which reads that attribute, not the profile -- updates live without a respawn.

local ServerStorage = game:GetService("ServerStorage")

local ItemState = require(ServerStorage.Modules.ItemState)
local Manager = require(ServerStorage.Modules.Manager)
local PlayerRaceBuilder = require(ServerStorage.Modules.PlayerRaceBuilder)

local SCOUTER_NONE = "None"

return function(context: ItemState.Context): ()
	local params: { [string]: any } = context.def.params or {}
	local scouterName = (params.scouter :: string?) or context.itemId

	local slot = Manager.getActiveSlot(context.player)
	if not slot then
		return
	end

	-- Toggle: take it off if it is the one already worn, otherwise switch to it.
	if slot.ScouterEquipped == scouterName then
		slot.ScouterEquipped = SCOUTER_NONE
	else
		slot.ScouterEquipped = scouterName
	end

	PlayerRaceBuilder.applyScouter(context.character, slot.ScouterEquipped)

	-- Mirror onto Humanoid.Appearance (StatsManager owns this attribute on spawn; we set it directly here
	-- to avoid a full StatsManager.refresh, which would also reset the player's Health).
	local humanoid = context.character:FindFirstChildOfClass("Humanoid")
	local appearance = humanoid and humanoid:FindFirstChild("Appearance")
	if appearance then
		appearance:SetAttribute("ScouterEquipped", slot.ScouterEquipped)
	end
end
