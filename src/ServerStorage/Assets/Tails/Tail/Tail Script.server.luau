-- 📌 Server Script placed inside the Tail model
local AC = script.Parent:WaitForChild("AnimationController")
local char = script.Parent.Parent
local hum = char:WaitForChild("Humanoid")

-- ✅ Wag Animation Setup
local Wag = script:WaitForChild("Wag")
local track = AC:LoadAnimation(Wag)

-- 🔄 Wait for character to be fully in Workspace
task.spawn(function()
	repeat
		task.wait()
	until char:IsDescendantOf(game.Workspace)
	task.wait(0.1) -- slight buffer for safety
	if not track.IsPlaying then
		track:Play()
	end
end)

-- ✅ Wrap toggle setup
local Wrapped = false
local CD = false

script.Parent:WaitForChild("Wrap").OnServerEvent:Connect(function(plr)
	-- Prevent spam toggle
	if CD then
		return
	end
	CD = true
	task.delay(1, function()
		CD = false
	end)

	-- ✅ Toggle wrap state
	Wrapped = not Wrapped

	local visibleTail = script.Parent
	local wrappedTail = char:FindFirstChild("WrappedTail")

	if not wrappedTail then
		warn("Missing WrappedTail in character")
		return
	end

	-- Set visibility
	for _, v in ipairs(visibleTail:GetChildren()) do
		if v:IsA("MeshPart") then
			v.Transparency = Wrapped and 1 or 0
		end
	end

	for _, v in ipairs(wrappedTail:GetChildren()) do
		if v:IsA("MeshPart") then
			v.Transparency = Wrapped and 0 or 1
		end
	end
end)

-- 🔄 Reset wrap state on death
hum.Died:Connect(function()
	Wrapped = false
end)
