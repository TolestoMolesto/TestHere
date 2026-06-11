local Animations = {}

Animations.NAMES = {
	idle = { { id = "rbxassetid://103139523367236", weight = 10 } },
	walk = { { id = "http://www.roblox.com/asset/?id=180426354", weight = 10 } },
	run = { { id = "rbxassetid://86498415666677", weight = 10 } },
	jump = { { id = "http://www.roblox.com/asset/?id=125750702", weight = 10 } },
	fall = { { id = "rbxassetid://133118459102032", weight = 10 } },
	climb = { { id = "http://www.roblox.com/asset/?id=180436334", weight = 10 } },
	sit = { { id = "http://www.roblox.com/asset/?id=178130996", weight = 10 } },
	toolnone = { { id = "http://www.roblox.com/asset/?id=182393478", weight = 10 } },
	toolslash = { { id = "http://www.roblox.com/asset/?id=129967390", weight = 10 } },
	toollunge = { { id = "http://www.roblox.com/asset/?id=129967478", weight = 10 } },

	wave = { { id = "http://www.roblox.com/asset/?id=128777973", weight = 10 } },
	point = { { id = "http://www.roblox.com/asset/?id=128853357", weight = 10 } },
	dance1 = {
		{ id = "http://www.roblox.com/asset/?id=182435998", weight = 10 },
		{ id = "http://www.roblox.com/asset/?id=182491037", weight = 10 },
		{ id = "http://www.roblox.com/asset/?id=182491065", weight = 10 },
	},
	dance2 = {
		{ id = "http://www.roblox.com/asset/?id=182436842", weight = 10 },
		{ id = "http://www.roblox.com/asset/?id=182491248", weight = 10 },
		{ id = "http://www.roblox.com/asset/?id=182491277", weight = 10 },
	},
	dance3 = {
		{ id = "http://www.roblox.com/asset/?id=182436935", weight = 10 },
		{ id = "http://www.roblox.com/asset/?id=182491368", weight = 10 },
		{ id = "http://www.roblox.com/asset/?id=182491423", weight = 10 },
	},
	laugh = { { id = "http://www.roblox.com/asset/?id=129423131", weight = 10 } },
	cheer = { { id = "http://www.roblox.com/asset/?id=129423030", weight = 10 } },

	attack1 = { { id = "rbxassetid://73060838886715", weight = 10 } },
	attack2 = { { id = "rbxassetid://135569688272045", weight = 10 } },
	attack3 = { { id = "rbxassetid://112595157386589", weight = 10 } },
	attack4 = { { id = "rbxassetid://80005786128027", weight = 10 } },
	heavyattack = { { id = "rbxassetid://117917287062164", weight = 10 } },
	heavyattackdown = { { id = "rbxassetid://71304216065261", weight = 10 } },
	heavyattackup = { { id = "rbxassetid://118086731493724", weight = 10 } },
	block = { { id = "rbxassetid://115194572570887", weight = 10 } },
	blockduringkb = { { id = "rbxassetid://124443176016389", weight = 10 } },
	knockback = { { id = "rbxassetid://82247533092047", weight = 10 } },
	recover = { { id = "rbxassetid://139543423482244", weight = 10 } },
	hit1 = { { id = "rbxassetid://136813239852641", weight = 10 } },
	hit2 = { { id = "rbxassetid://109816671003785", weight = 10 } },
	hit3 = { { id = "rbxassetid://112152345528474", weight = 10 } },
	hit4 = { { id = "rbxassetid://138160091821745", weight = 10 } },
	hit5 = { { id = "rbxassetid://124412357054387", weight = 10 } },
	kiblastleft = { { id = "rbxassetid://128096467742894", weight = 10 } },
	kiblastright = { { id = "rbxassetid://116115922974989", weight = 10 } },

	ascend = { { id = "rbxassetid://95613385147552", weight = 10 } },
	descend = { { id = "rbxassetid://133118459102032", weight = 10 } },
	boost = { { id = "rbxassetid://80398445675397", weight = 10 } },
	charge = { { id = "rbxassetid://137650138664215", weight = 10 } },
	fightingstance = { { id = "rbxassetid://89933019860019", weight = 10 } },
	idlestance = { { id = "rbxassetid://103139523367236", weight = 10 } },
	flybackwards = { { id = "rbxassetid://122835447516160", weight = 10 } },
	flyforwards = { { id = "rbxassetid://75243753815489", weight = 10 } },
	flyidle = { { id = "rbxassetid://117728257451085", weight = 10 } },
	flyleft = { { id = "rbxassetid://96047558113892", weight = 10 } },
	flyright = { { id = "rbxassetid://72656562830193", weight = 10 } },
	lockedonboost = { { id = "rbxassetid://128819010878760", weight = 10 } },
	gripped = { { id = "rbxassetid://78069186980168", weight = 10 } },
	gripping = { { id = "rbxassetid://118609100407851", weight = 10 } },
	scouterread = { { id = "rbxassetid://83326593995138", weight = 10 } },
	rest = { { id = "rbxassetid://70667321130064", weight = 10 } },
}

Animations.LIGHT_ATTACK = {
	Animations.NAMES.attack1[1].id,
	Animations.NAMES.attack2[1].id,
	Animations.NAMES.attack3[1].id,
	Animations.NAMES.attack4[1].id,
}
Animations.LIGHT_ATTACK_COUNT = #Animations.LIGHT_ATTACK

-- Flinch reactions cycled in order on each successive hit (see bindHitReactionAnimation).
Animations.HIT_REACTION = {
	Animations.NAMES.hit1[1].id,
	Animations.NAMES.hit2[1].id,
	Animations.NAMES.hit3[1].id,
	Animations.NAMES.hit4[1].id,
	Animations.NAMES.hit5[1].id,
}
Animations.HIT_REACTION_COUNT = #Animations.HIT_REACTION

local animationCache: { [string]: Animation } = {}
local tracksByAnimator = setmetatable({}, { __mode = "k" }) -- animator -> { [id]: track }
local nameByAnimator = setmetatable({}, { __mode = "k" }) -- animator -> { [name]: track }
local heldConnections = setmetatable({}, { __mode = "k" }) -- animator -> { [name]: marker conn }

local function getAnimation(id: string): Animation
	local animation = animationCache[id]
	if not animation then
		animation = Instance.new("Animation")
		animation.AnimationId = id
		animationCache[id] = animation
	end
	return animation
end

local function getAnimator(character: Model): Animator?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator
end

local function getTrack(animator: Animator, id: string, priority: Enum.AnimationPriority?): AnimationTrack
	local cache = tracksByAnimator[animator]
	if not cache then
		cache = {}
		tracksByAnimator[animator] = cache
	end
	local track = cache[id]
	if not track then
		track = animator:LoadAnimation(getAnimation(id))
		track.Priority = priority or Enum.AnimationPriority.Action -- Action reads over Movement locomotion
		cache[id] = track
	end
	return track
end

-- 1.0 is authored speed; AttackSpeed is a soft-capped bonus on top (StatsManager wires it from the
-- Speed stat). No AttackSpeed attribute (e.g. AI, or before stats apply) => exactly authored speed.
function Animations.attackSpeed(character: Model): number
	return 1 + ((character:GetAttribute("AttackSpeed") :: number?) or 0)
end

function Animations.playLightAttack(character: Model, comboIndex: number, speed: number?): AnimationTrack?
	local animator = getAnimator(character)
	if not animator then
		return nil
	end

	local index = ((comboIndex - 1) % Animations.LIGHT_ATTACK_COUNT) + 1
	local track = getTrack(animator, Animations.LIGHT_ATTACK[index])

	-- Only stop other combo tracks; iterating the full cache would kill block/charge/locomotion.
	local cache = tracksByAnimator[animator]
	for _, comboId in Animations.LIGHT_ATTACK do
		local other = cache[comboId]
		if other and other ~= track and other.IsPlaying then
			other:Stop(0.1)
		end
	end

	track:Play(0.1, nil, speed or 1)
	return track
end

local MOVEMENT_ANIMS: { [string]: boolean } = {
	idle = true,
	walk = true,
	run = true,
	jump = true,
	fall = true,
	climb = true,
	sit = true,
	idlestance = true,
	fightingstance = true,
	flyidle = true,
	flyforwards = true,
	flybackwards = true,
	flyleft = true,
	flyright = true,
}

local function priorityFor(name: string): Enum.AnimationPriority
	return if MOVEMENT_ANIMS[name] then Enum.AnimationPriority.Movement else Enum.AnimationPriority.Action
end

local function pickVariant(variants: { { id: string, weight: number } }): string
	if #variants == 1 then
		return variants[1].id
	end
	local total = 0
	for _, v in variants do
		total += v.weight
	end
	local roll = math.random() * total
	local cumulative = 0
	for _, v in variants do
		cumulative += v.weight
		if roll <= cumulative then
			return v.id
		end
	end
	return variants[1].id
end

function Animations.play(
	character: Model,
	name: string,
	fadeTime: number?,
	weight: number?,
	speed: number?
): AnimationTrack?
	local variants = Animations.NAMES[name]
	if not variants then
		warn(`[Animations] No animation named '{name}'`)
		return nil
	end
	local animator = getAnimator(character)
	if not animator then
		return nil
	end

	local track = getTrack(animator, pickVariant(variants), priorityFor(name))

	local byName = nameByAnimator[animator]
	if not byName then
		byName = {}
		nameByAnimator[animator] = byName
	end
	byName[name] = track

	track:Play(fadeTime or 0.1, weight, speed)
	return track
end

function Animations.stop(character: Model, name: string, fadeTime: number?): ()
	local animator = getAnimator(character)
	if not animator then
		return
	end
	local conns = heldConnections[animator]
	if conns and conns[name] then
		conns[name]:Disconnect()
		conns[name] = nil
	end
	local byName = nameByAnimator[animator]
	local track = byName and byName[name]
	if track then
		track:Stop(fadeTime or 0.1)
		byName[name] = nil
	end
end

-- Plays once then freezes at `holdMarker` via AdjustSpeed(0) so the pose holds until stop()'d.
function Animations.playHeld(character: Model, name: string, holdMarker: string, fadeTime: number?): AnimationTrack?
	local variants = Animations.NAMES[name]
	if not variants then
		warn(`[Animations] No animation named '{name}'`)
		return nil
	end
	local animator = getAnimator(character)
	if not animator then
		return nil
	end

	local track = getTrack(animator, pickVariant(variants), priorityFor(name))
	track.Looped = false

	local byName = nameByAnimator[animator]
	if not byName then
		byName = {}
		nameByAnimator[animator] = byName
	end
	byName[name] = track

	local conns = heldConnections[animator]
	if not conns then
		conns = {}
		heldConnections[animator] = conns
	end
	if conns[name] then
		conns[name]:Disconnect()
	end
	conns[name] = track:GetMarkerReachedSignal(holdMarker):Connect(function()
		track:AdjustSpeed(0)
	end)

	track:Play(fadeTime or 0.1)
	track:AdjustSpeed(1)
	return track
end

local LOCOMOTION_RUN_SPEED = 20 -- horizontal studs/s at/above which it runs

function Animations.bindLocomotion(character: Model): () -> ()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return function() end
	end

	local current: string? = nil
	local alive = true
	local connections: { RBXScriptConnection } = {}

	local function set(name: string)
		if not alive or current == name then
			return
		end
		if current then
			Animations.stop(character, current, 0.15)
		end
		current = name
		Animations.play(character, name, 0.15)
	end

	local function update(speed: number)
		if speed < 0.5 then
			set("idle")
		elseif speed >= LOCOMOTION_RUN_SPEED then
			set("run")
		else
			set("walk")
		end
	end

	table.insert(connections, humanoid.Running:Connect(update))
	set("idle")

	return function()
		alive = false
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
		if current then
			Animations.stop(character, current, 0.1)
		end
	end
end

function Animations.bindKnockbackAnimation(character: Model): () -> ()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return function() end
	end

	local connections: { RBXScriptConnection } = {}

	local function onChange()
		if character:GetAttribute("HitByKnockBack") then
			Animations.stop(character, "recover", 0)
			local track = Animations.play(character, "knockback", 0.1)
			if track then
				track.Looped = true -- knockback can last several seconds; loop holds the pose
			end
		else
			Animations.stop(character, "knockback", 0.1)
			local track = Animations.play(character, "recover", 0.1)
			if track then
				track.Looped = false
			end
		end
	end

	table.insert(connections, character:GetAttributeChangedSignal("HitByKnockBack"):Connect(onChange))

	return function()
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
		Animations.stop(character, "knockback", 0.1)
		Animations.stop(character, "recover", 0.1)
	end
end

-- One-shot flinch when struck. HitStun.apply bumps the HitReaction counter on the victim (a counter,
-- not a flag, so consecutive hits inside the stun window each re-fire the change signal). The reactions
-- cycle hit1..hit5 in order for variety. Bound on the owning side -- the player's client and the
-- server for shadows -- so the played track replicates, exactly like the knockback binding above.
function Animations.bindHitReactionAnimation(character: Model): () -> ()
	local connections: { RBXScriptConnection } = {}
	local currentName: string? = nil

	local function onChange()
		local counter = character:GetAttribute("HitReaction") :: number?
		if not counter or counter <= 0 then
			return
		end
		if currentName then
			Animations.stop(character, currentName, 0.05)
		end
		local index = ((counter - 1) % Animations.HIT_REACTION_COUNT) + 1
		local name = "hit" .. index
		currentName = name
		local track = Animations.play(character, name, 0.1)
		if track then
			track.Looped = false
		end
	end

	table.insert(connections, character:GetAttributeChangedSignal("HitReaction"):Connect(onChange))

	return function()
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
		if currentName then
			Animations.stop(character, currentName, 0.1)
		end
	end
end

function Animations.bindBlockAnimation(character: Model): () -> ()
	local connections: { RBXScriptConnection } = {}

	local function onChange()
		if character:GetAttribute("Blocking") then
			Animations.playHeld(character, "block", "StartBlock", 0.1)
		else
			Animations.stop(character, "block", 0.1)
		end
	end

	table.insert(connections, character:GetAttributeChangedSignal("Blocking"):Connect(onChange))

	return function()
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
		Animations.stop(character, "block", 0.1)
	end
end

function Animations.bindChargeAnimation(character: Model): () -> ()
	local connections: { RBXScriptConnection } = {}

	local function onChange()
		if character:GetAttribute("Charging") then
			local track = Animations.play(character, "charge", 0.1)
			if track then
				track.Looped = true
			end
		else
			Animations.stop(character, "charge", 0.1)
		end
	end

	table.insert(connections, character:GetAttributeChangedSignal("Charging"):Connect(onChange))

	return function()
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
		Animations.stop(character, "charge", 0.1)
	end
end

function Animations.bindRestAnimation(character: Model): () -> ()
	local connections: { RBXScriptConnection } = {}

	local function onChange()
		if character:GetAttribute("Resting") then
			local track = Animations.play(character, "rest", 0.2)
			if track then
				track.Looped = true
			end
		else
			Animations.stop(character, "rest", 0.2)
		end
	end

	table.insert(connections, character:GetAttributeChangedSignal("Resting"):Connect(onChange))

	return function()
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
		Animations.stop(character, "rest", 0.2)
	end
end

return Animations
