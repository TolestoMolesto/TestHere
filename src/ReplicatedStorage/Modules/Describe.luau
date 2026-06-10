--!strict
-- Shared, client-safe formatter that renders a curated ability/item descriptor into the game's
-- standard tooltip text block (the "Type: … / Note: … / summary / Effects:" layout). Forms, Skills,
-- and Items all funnel through this so their tooltips read identically. Lives in ReplicatedStorage
-- on purpose: the SERVER builds the finished string from a server-only config and ships only that
-- curated string to clients -- raw balance numbers (stats / strength / kiCost) never replicate.
--
-- Layout (matches the design's reference Form tooltip):
--   Type: <type>
--   Rarity: <rarity>            -- only when present (Items)
--   Note: <note>                -- only when present
--                               (blank line)
--   <summary>
--                               (blank line)
--   Effects:
--   <effects[1]>
--   …
--   Duration: <duration> seconds  -- only when present
--   Cooldown: <cooldown> seconds  -- only when present

export type Descriptor = {
	type: string, -- the unified sort key: "Form" | "Technique" | "Skill" | "Consumable" | "Key" | …
	rarity: string?, -- Items only; rendered under Type
	note: string?, -- optional caveat line (e.g. "Cannot be stacked with other Forms.")
	summary: string, -- flavor paragraph(s)
	effects: { string }, -- curated, player-facing effect lines (e.g. "Ki Boost: +75%")
	duration: number?, -- appended to the Effects block as "Duration: N seconds"
	cooldown: number?, -- appended to the Effects block as "Cooldown: N seconds"
}

local Describe = {}

function Describe.format(d: Descriptor): string
	local lines: { string } = {}

	table.insert(lines, `Type: {d.type}`)
	if d.rarity then
		table.insert(lines, `Rarity: {d.rarity}`)
	end
	if d.note and d.note ~= "" then
		table.insert(lines, `Note: {d.note}`)
	end

	if d.summary and d.summary ~= "" then
		table.insert(lines, "")
		table.insert(lines, d.summary)
	end

	-- Effects block: the curated lines first, then any Duration / Cooldown the server derived from
	-- the real (server-only) config, so those numbers can never drift from balance.
	local effects: { string } = {}
	for _, line in d.effects do
		table.insert(effects, line)
	end
	if d.duration then
		table.insert(effects, `Duration: {d.duration} seconds`)
	end
	if d.cooldown then
		table.insert(effects, `Cooldown: {d.cooldown} seconds`)
	end
	if #effects > 0 then
		table.insert(lines, "")
		table.insert(lines, "Effects:")
		for _, line in effects do
			table.insert(lines, line)
		end
	end

	return table.concat(lines, "\n")
end

return Describe
