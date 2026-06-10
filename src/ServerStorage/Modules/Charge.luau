--!strict
local Charge = {}

local KI_REGEN_PER_SECOND = 25
local TICK = 0.1

local generation = setmetatable({} :: { [Model]: number }, { __mode = "k" })
local watchers = setmetatable({} :: { [Model]: { RBXScriptConnection } }, { __mode = "k" })

local function disconnectWatchers(character: Model): ()
	local conns = watchers[character]
	if conns then
		for _, c in conns do
			c:Disconnect()
		end
		watchers[character] = nil
	end
end

local function interrupted(character: Model): boolean
	return character:GetAttribute("Stunned") == true or character:GetAttribute("HitByKnockBack") == true
end

local function canCharge(character: Model): boolean
	if character:GetAttribute("Charging") then
		return false
	end
	return not (
		interrupted(character)
		or character:GetAttribute("Attacking")
		or character:GetAttribute("Blocking")
		or character:GetAttribute("BlockBroken")
		or character:GetAttribute("ToggleRagdoll")
		or character:GetAttribute("InCustomization")
	)
end

function Charge.start(character: Model): ()
	if not character or not character.Parent or not canCharge(character) then
		return
	end

	character:SetAttribute("Charging", true)
	character:SetAttribute("CanBlock", false)

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		hrp.Anchored = true
	end

	local gen = (generation[character] or 0) + 1
	generation[character] = gen

	-- Re-check interrupted() in the handler so the flags clearing (stun/knockback ending) is ignored.
	disconnectWatchers(character)
	local function onInterrupt(): ()
		if interrupted(character) then
			Charge.stop(character)
		end
	end
	watchers[character] = {
		character:GetAttributeChangedSignal("Stunned"):Connect(onInterrupt),
		character:GetAttributeChangedSignal("HitByKnockBack"):Connect(onInterrupt),
	}

	-- Generation guard retires this loop if a newer charge starts.
	task.spawn(function(): ()
		while character.Parent and character:GetAttribute("Charging") and generation[character] == gen do
			local ki = (character:GetAttribute("Ki") :: number?) or 0
			local maxKi = (character:GetAttribute("MaxKi") :: number?) or 0
			if ki < maxKi then
				character:SetAttribute("Ki", math.min(maxKi, ki + KI_REGEN_PER_SECOND * TICK))
			end
			task.wait(TICK)
		end
	end)
end

function Charge.stop(character: Model): ()
	if not character:GetAttribute("Charging") then
		return
	end

	generation[character] = (generation[character] or 0) + 1
	disconnectWatchers(character)

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		hrp.Anchored = false
	end

	character:SetAttribute("Charging", false)
	character:SetAttribute("CanBlock", true)
end

return Charge
