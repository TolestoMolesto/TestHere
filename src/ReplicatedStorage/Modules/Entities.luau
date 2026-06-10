--!strict
-- Single source of truth for "who/what is this character". Every combat entity's Model is
-- tagged (CollectionService) and parked in a tidy Workspace folder, so any system -- now or
-- later -- can identify and enumerate entities without name-parsing or guessing from
-- Players:GetPlayerFromCharacter.
--
-- Tags (applied to the character Model, not the Humanoid -- all other state in this codebase
-- lives on the Model):
--   Player  -- a real player's character
--   NPC     -- any server-controlled rig
--   Shadow  -- a training clone; ALSO carries NPC, because a Shadow is a kind of NPC
--
-- The mutating helpers (ensureFolders / getFolder / register) are SERVER-ONLY. The constants
-- and predicates are safe to read from the client (e.g. LockOn).

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Entities = {}

export type Kind = "Player" | "NPC" | "Shadow"

Entities.Tag = {
	Player = "Player",
	NPC = "NPC",
	Shadow = "Shadow",
}

Entities.Folder = {
	Player = "Players",
	NPC = "NPCs",
	Shadow = "Shadows",
}

local ALL_TAGS = { Entities.Tag.Player, Entities.Tag.NPC, Entities.Tag.Shadow }

-- Tags each kind stamps. A Shadow is an NPC too, so it gets both. Explicit branches rather than
-- a `[kind]` lookup so the string-literal union stays type-checkable under --!strict.
local function tagsFor(kind: Kind): { string }
	if kind == "Player" then
		return { Entities.Tag.Player }
	elseif kind == "NPC" then
		return { Entities.Tag.NPC }
	end
	return { Entities.Tag.NPC, Entities.Tag.Shadow }
end

local function folderName(kind: Kind): string
	if kind == "Player" then
		return Entities.Folder.Player
	elseif kind == "NPC" then
		return Entities.Folder.NPC
	end
	return Entities.Folder.Shadow
end

-- SERVER-ONLY. Find (or create) the Workspace folder for a kind. Reuses an existing folder of
-- that name (e.g. a place-side "NPCs") so we never clobber hand-placed rigs.
function Entities.getFolder(kind: Kind): Folder
	local name = folderName(kind)
	local existing = Workspace:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = Workspace
	return folder
end

-- SERVER-ONLY. Create all three folders up-front so nothing ever references a missing instance.
function Entities.ensureFolders(): ()
	Entities.getFolder("Player")
	Entities.getFolder("NPC")
	Entities.getFolder("Shadow")
end

-- SERVER-ONLY. Tag `model` as `kind` and move it into the matching folder. Idempotent.
-- Clears conflicting entity tags first (a Shadow cloned from a player inherits the Player tag).
function Entities.register(model: Model, kind: Kind): ()
	local wanted = tagsFor(kind)
	for _, tag in ALL_TAGS do
		if not table.find(wanted, tag) and CollectionService:HasTag(model, tag) then
			CollectionService:RemoveTag(model, tag)
		end
	end
	for _, tag in wanted do
		if not CollectionService:HasTag(model, tag) then
			CollectionService:AddTag(model, tag)
		end
	end
	model.Parent = Entities.getFolder(kind)
end

function Entities.isPlayer(model: Instance): boolean
	return CollectionService:HasTag(model, Entities.Tag.Player)
end

function Entities.isNPC(model: Instance): boolean
	return CollectionService:HasTag(model, Entities.Tag.NPC)
end

function Entities.isShadow(model: Instance): boolean
	return CollectionService:HasTag(model, Entities.Tag.Shadow)
end

return Entities
