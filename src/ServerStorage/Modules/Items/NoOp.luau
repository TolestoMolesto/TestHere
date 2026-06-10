--!strict
-- Item behavior for usable items that intentionally do nothing for now.
-- This lets placeholder items be clicked/used without needing custom logic yet.

local ServerStorage = game:GetService("ServerStorage")

local ItemState = require(ServerStorage.Modules.ItemState)

return function(_context: ItemState.Context): ()
	-- Does nothing for now.
end
