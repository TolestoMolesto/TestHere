--!strict
-- Shared building blocks for Skill behaviors (the offensive 1-5 bucket). The legacy GlobalSkillSet
-- hand-rolled damage, knockback, combo, aiming and VFX inside every move and duplicated the whole
-- damage block twice; this collapses all of it onto the rework's modules:
--   * damage   -> Damage.apply(target, caster, strength, "Ki"|"Physical")  (0 return = dodge)
--   * hits     -> Hitbox.scanBox / scanRadius  (query-based; no physical hitbox parts anymore)
--   * aim      -> TargetLock.get  (lock-on) then the client's mouse CFrame, then look vector
--   * reactions-> Knockback / HitFX / CombatTag / Train
-- VFX assets are place-side (not Rojo-synced) and cosmetic: every behavior must still deal damage
-- when its template is missing, so all asset access here is guarded.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Animations = require(ReplicatedStorage.Modules.Animations)
local CombatTag = require(ServerStorage.Modules.CombatTag)
local Damage = require(ServerStorage.Modules.Damage)
local HitFX = require(ServerStorage.Modules.HitFX)
local Hitbox = require(ServerStorage.Modules.Hitbox)
local Knockback = require(ServerStorage.Modules.Knockback)
local TargetLock = require(ServerStorage.Modules.TargetLock)
local Train = require(ServerStorage.Modules.Train)

local DEFAULT_KI_COLOUR = Color3.fromRGB(255, 255, 255)

local Shared = {}

export type HitOptions = {
	knockback: number?, -- force passed to Knockback.apply (0/nil = no knockback)
	customFX: { [string]: number }?, -- emit counts for HitFX.spawnOnCharacterCustom (else default FX)
}

export type BeamConfig = {
	length: number, -- studs the damage lane reaches
	width: number, -- studs (square cross-section)
	strength: number, -- per-hit base damage (def.strength)
	duration: number, -- seconds the lane stays live
	knockback: number?, -- knockback force on hit
	tick: number?, -- scan interval (default 0.1s); each target is hit once per beam
}

export type ProjectileConfig = {
	speed: number, -- studs/s
	lifetime: number, -- seconds before it expires harmlessly
	radius: number, -- hit-scan radius around the projectile
	strength: number, -- base damage on hit
	knockback: number?,
	homing: boolean?, -- steer toward the lock-on target each frame
	explodeOnly: boolean?, -- skip the single-target hit; let onExpire deal AoE at the impact point
	onHit: ((target: Model, hitPosition: Vector3) -> ())?, -- e.g. spawn an explosion
	onExpire: ((part: BasePart) -> ())?, -- runs on contact OR lifetime end, at the part's final spot
}

-- The shared cosmetic-effects bucket (Workspace.Ignore), created on demand.
function Shared.effectsFolder(): Folder
	local folder = Workspace:FindFirstChild("Ignore")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Ignore"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

-- Resolves a caster's Ki colour from the Humanoid.Appearance attributes StatsManager writes
-- (mirrors KiBlast). Falls back to white when unset.
function Shared.kiColour(character: Model): Color3
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local appearance = humanoid and humanoid:FindFirstChild("Appearance")
	if appearance then
		local r = appearance:GetAttribute("KiColorR") :: number?
		local g = appearance:GetAttribute("KiColorG") :: number?
		local b = appearance:GetAttribute("KiColorB") :: number?
		if r and g and b and r >= 0 and g >= 0 and b >= 0 then
			return Color3.fromRGB(r, g, b)
		end
	end
	return DEFAULT_KI_COLOUR
end

-- Tints a part and any Trails/ParticleEmitters/Beams under it (best-effort cosmetic).
function Shared.tint(instance: Instance, colour: Color3): ()
	if instance:IsA("BasePart") then
		instance.Color = colour
	end
	local sequence = ColorSequence.new(colour)
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("Trail") or descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") then
			(descendant :: any).Color = sequence
		end
	end
end

-- Emits every ParticleEmitter under an instance (one-shot burst).
function Shared.emitAll(instance: Instance, count: number): ()
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			descendant:Emit(count)
		end
	end
end

local warnedAssets: { [string]: boolean } = {}

-- Looks up a place-side skill VFX template under ServerStorage.Assets.Skills.<name>. Warns once
-- per missing name (cosmetic only -- the move still works), so behaviors can clone defensively.
function Shared.skillAsset(name: string): Instance?
	local assets = ServerStorage:FindFirstChild("Assets")
	local skills = assets and assets:FindFirstChild("Skills")
	local template = skills and skills:FindFirstChild(name)
	if not template then
		if not warnedAssets[name] then
			warnedAssets[name] = true
			warn(`[Skills] VFX template ServerStorage.Assets.Skills.{name} missing -- {name} runs without it.`)
		end
		return nil
	end
	return template
end

-- Plays a character animation only if it's been registered in Animations.NAMES under `key` (skill
-- anim ids are place-side and may not exist yet); no warning when absent. Add `key` to
-- Animations.NAMES to light it up.
function Shared.playAnim(character: Model, key: string, fadeTime: number?): AnimationTrack?
	if (Animations.NAMES :: { [string]: any })[key] then
		return Animations.play(character, key, fadeTime)
	end
	return nil
end

function Shared.stopAnim(character: Model, key: string, fadeTime: number?): ()
	if (Animations.NAMES :: { [string]: any })[key] then
		Animations.stop(character, key, fadeTime)
	end
end

-- Resolves the aim direction (unit vector): lock-on target first, then the client's mouse-hit
-- CFrame, then the caster's own look vector. The single source of truth for "where does it go".
function Shared.aimDirection(character: Model, aim: CFrame?): Vector3
	local origin = character:GetPivot().Position
	local target = TargetLock.get(character)
	if target then
		local root = target:FindFirstChild("HumanoidRootPart") :: BasePart?
		local targetPos = if root then root.Position else target:GetPivot().Position
		local delta = targetPos - origin
		if delta.Magnitude > 0.05 then
			return delta.Unit
		end
	end
	if aim then
		local delta = aim.Position - origin
		if delta.Magnitude > 0.05 then
			return delta.Unit
		end
	end
	return character:GetPivot().LookVector
end

-- The single on-hit path (replaces the duplicated damage blocks in TriggerKiMoveDamage): deal
-- damage, then -- only on a landed hit -- spawn FX, combat-tag, knock back, and award training.
-- Returns the damage dealt (0 = dodged, nil = invalid target / no humanoid / safe zone).
function Shared.applyHit(
	target: Model,
	caster: Model,
	strength: number,
	cause: Damage.DamageCause,
	direction: Vector3?,
	options: HitOptions?
): number?
	if target == caster then
		return nil
	end
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	if target:GetAttribute("InSafeZone") then
		return nil
	end

	local dealt = Damage.apply(target, caster, strength, cause)
	if dealt == nil then
		return nil
	end

	local root = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	if dealt == 0 then
		Train.dodged(target, caster) -- whiffed: no FX/knockback, but it still trains evasion
		return 0
	end

	local opts: HitOptions = options or {}
	if opts.customFX then
		HitFX.spawnOnCharacterCustom(target, root and root.Position, opts.customFX)
	else
		HitFX.spawnOnCharacter(target, root and root.Position)
	end
	CombatTag.applyCombatTag(caster, target)
	if direction and opts.knockback and opts.knockback > 0 then
		Knockback.apply(target, direction, opts.knockback)
	end
	if cause == "Physical" then
		Train.landedHeavy(caster, target)
	else
		Train.landedKiBlast(caster, target)
	end
	return dealt
end

-- Radial Ki burst: hits every fighter within `radius` of `position` once, knocking each outward
-- from the blast centre. Used by explosive projectiles (Big Bang / Spirit Bomb) on impact.
function Shared.aoeDamage(caster: Model, position: Vector3, radius: number, strength: number, knockback: number?): ()
	for _, target in Hitbox.scanRadius(position, radius, { caster }) do
		local flat = (target:GetPivot().Position - position) * Vector3.new(1, 0, 1)
		local outward = if flat.Magnitude > 0.05 then flat.Unit else caster:GetPivot().LookVector
		Shared.applyHit(target, caster, strength, "Ki", outward, { knockback = knockback })
	end
end

-- A single melee box in front of `caster` (forward by `reach`), hitting each caught fighter once
-- with Physical damage. Returns the fighters struck, so a combo can react (finisher, etc.).
function Shared.meleeHit(
	caster: Model,
	size: Vector3,
	reach: number,
	strength: number,
	knockback: number?,
	customFX: { [string]: number }?
): { Model }
	local root = caster:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return {}
	end
	local region = root.CFrame * CFrame.new(0, 0, -reach)
	local struck: { Model } = {}
	for _, target in Hitbox.scanBox(region, size, { caster }) do
		local dealt = Shared.applyHit(target, caster, strength, "Physical", root.CFrame.LookVector, {
			knockback = knockback,
			customFX = customFX,
		})
		if dealt and dealt > 0 then
			table.insert(struck, target)
		end
	end
	return struck
end

-- A straight damage lane. Box-scans from `origin` along `direction` for `duration`, hitting each
-- target at most once. The cosmetic beam is the behavior's concern; this is purely the hitbox.
-- Returns a stop() to cut the lane early.
function Shared.beamDamage(caster: Model, origin: Vector3, direction: Vector3, config: BeamConfig): () -> ()
	local hitSet: { [Model]: boolean } = {}
	local half = config.length / 2
	local centre = origin + direction * half
	local region = CFrame.lookAt(centre, centre + direction)
	local size = Vector3.new(config.width, config.width, config.length)
	local alive = true

	task.spawn(function()
		local elapsed = 0
		local tickRate = config.tick or 0.1
		while alive and elapsed < config.duration and caster.Parent do
			for _, target in Hitbox.scanBox(region, size, { caster }) do
				if not hitSet[target] then
					hitSet[target] = true
					Shared.applyHit(target, caster, config.strength, "Ki", direction, { knockback = config.knockback })
				end
			end
			task.wait(tickRate)
			elapsed += tickRate
		end
	end)

	return function()
		alive = false
	end
end

-- Builds a ready-to-fly projectile part at `position`: a tinted clone of the place-side template
-- when it exists, else an invisible carrier so the hit still resolves. Always returns a part.
function Shared.makeProjectile(caster: Model, templateName: string, position: Vector3, size: Vector3?): BasePart
	local template = Shared.skillAsset(templateName)
	if template and template:IsA("BasePart") then
		local clone = template:Clone()
		Shared.tint(clone, Shared.kiColour(caster))
		Shared.emitAll(clone, 10)
		clone.Anchored = true
		clone.CanCollide = false
		clone.CFrame = CFrame.new(position)
		clone.Parent = Shared.effectsFolder()
		return clone
	end
	local carrier = Instance.new("Part")
	carrier.Transparency = 1
	carrier.Size = size or Vector3.new(1, 1, 1)
	carrier.Anchored = true
	carrier.CanCollide = false
	carrier.CFrame = CFrame.new(position)
	carrier.Parent = Shared.effectsFolder()
	return carrier
end

-- Launches an already-positioned, already-parented cosmetic `part` along `direction`, moving it by
-- hand each frame (optionally homing toward the lock-on target) and radius-scanning for the first
-- valid fighter. On contact it applies the hit, fires onHit, and cleans up; otherwise it expires
-- after `lifetime`. Modeled on KiBlast.
function Shared.launchProjectile(caster: Model, part: BasePart, direction: Vector3, config: ProjectileConfig): ()
	part.CanCollide = false
	part.CFrame = CFrame.lookAt(part.Position, part.Position + direction)

	local startClock = os.clock()
	local finished = false
	local connection: RBXScriptConnection? = nil

	local function cleanup()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		if config.onExpire then
			config.onExpire(part)
		end
		if part.Parent then
			part:Destroy()
		end
	end

	connection = RunService.Heartbeat:Connect(function(dt: number)
		if finished or not part.Parent or os.clock() - startClock > config.lifetime then
			finished = true
			cleanup()
			return
		end

		if config.homing then
			local target = TargetLock.get(caster)
			local root = target and target:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local step = (root.Position - part.Position)
				local distance = step.Magnitude
				if distance > 0.05 then
					part.CFrame = CFrame.new(part.Position + step.Unit * config.speed * dt, root.Position)
				end
			else
				part.CFrame += part.CFrame.LookVector * config.speed * dt
			end
		else
			part.CFrame += part.CFrame.LookVector * config.speed * dt
		end

		for _, target in Hitbox.scanRadius(part.Position, config.radius, { caster }) do
			local humanoid = target:FindFirstChildOfClass("Humanoid")
			if target ~= caster and humanoid and humanoid.Health > 0 then
				finished = true
				local hitPosition = part.Position
				-- explodeOnly projectiles deal no single-target hit -- onExpire's AoE covers everyone,
				-- including the struck target, so it isn't double-hit.
				if not config.explodeOnly then
					Shared.applyHit(target, caster, config.strength, "Ki", part.CFrame.LookVector, {
						knockback = config.knockback,
					})
				end
				if config.onHit then
					config.onHit(target, hitPosition)
				end
				cleanup()
				return
			end
		end
	end)
end

-- Spawns an expanding, fading explosion VFX clone (if the template exists) at a position. Cosmetic
-- helper for projectile impacts; safe to call with a missing template.
function Shared.spawnExplosion(templateName: string, position: Vector3, finalSize: Vector3, growTime: number): ()
	local template = Shared.skillAsset(templateName)
	if not template or not template:IsA("BasePart") then
		return
	end
	local explosion = template:Clone()
	explosion.Anchored = true
	explosion.CanCollide = false
	explosion.CFrame = CFrame.new(position)
	explosion.Parent = Shared.effectsFolder()
	Shared.emitAll(explosion, 30)
	game:GetService("TweenService")
		:Create(explosion, TweenInfo.new(growTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = finalSize,
			Transparency = 1,
		})
		:Play()
	Debris:AddItem(explosion, growTime + 0.2)
end

return Shared
