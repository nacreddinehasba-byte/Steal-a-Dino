-- BaseLock (Script -> ServerScriptService)
-- Each base has a "LockButton" part and a "LockWall" part in its doorway.
-- The OWNER steps on the button -> the wall becomes solid and visible for
-- Config.LockDuration seconds (nobody can steal), then Config.LockCooldown
-- seconds before it can be used again. A small loop keeps the wall and the
-- button color in sync: green = ready, red = locked, orange = cooldown.
-- V2 LOCK LASERS: while locked, three NEON beams span the doorway. They
-- are pure theatre — the invisible LockWall does the actual blocking, and
-- the wall only turns faintly visible so players can see why they stopped.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Gamepasses = require(ReplicatedStorage:WaitForChild("Gamepasses"))
local BaseService = require(ServerScriptService:WaitForChild("BaseService"))

BaseService.Init()

-- TODO (monetization hook): to sell a "longer lock" gamepass, add a line to
-- the starter kit's Gamepasses.lua like:
--     { Name = "Longer Lock", Id = 123456, Effect = "LongLock" },
-- GamepassShop will then set the "LongLock" attribute on buyers, and the
-- lock duration below doubles automatically. Nothing else to change.
local longLockPassExists = false
for _, pass in ipairs(Gamepasses) do
	if pass.Effect == "LongLock" and pass.Id and pass.Id > 0 then
		longLockPassExists = true
	end
end

local COLOR_READY = Color3.fromRGB(60, 255, 120)
local COLOR_LOCKED = Color3.fromRGB(255, 70, 70)
local COLOR_COOLDOWN = Color3.fromRGB(255, 170, 40)

-- Lock lasers: built once per base, shown/hidden with the lock state -------
local lasersByBase = {}

local function buildLasers(base)
	local wall = base:FindFirstChild("LockWall")
	if not wall then return end
	local beams = {}
	for _, dy in ipairs({ -2.2, 0, 2.2 }) do
		local beam = Instance.new("Part")
		beam.Name = "LaserBeam"
		beam.Shape = Enum.PartType.Cylinder
		beam.Size = Vector3.new(wall.Size.Z, 0.22, 0.22)
		beam.Color = Color3.fromRGB(60, 255, 120)
		beam.Material = Enum.Material.Neon
		beam.Transparency = 1
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.CanTouch = false
		-- cylinder axis is X; rotate 90° around Y so the beam spans the
		-- doorway along Z, at the wall's X, at three heights
		beam.CFrame = CFrame.new(wall.Position + Vector3.new(0, dy, 0))
			* CFrame.Angles(0, math.rad(90), 0)
		beam.Parent = base
		table.insert(beams, beam)
	end
	lasersByBase[base] = beams
end

local function setWall(base, on)
	local wall = base:FindFirstChild("LockWall")
	if wall then
		wall.CanCollide = on
		wall.Transparency = on and 0.35 or 1
	end
	local beams = lasersByBase[base]
	if beams then
		for _, beam in ipairs(beams) do
			beam.Transparency = on and 0.5 or 1
		end
	end
end

local function tryLock(player, base)
	if BaseService.GetBaseOf(player) ~= base then
		BaseService.Notify(player, "🙂 This is not your base!")
		return
	end
	if BaseService.IsLocked(base) then
		BaseService.Notify(player, "🔒 Already locked! " .. BaseService.LockSecondsLeft(base) .. "s left.")
		return
	end
	if not BaseService.CanLock(base) then
		BaseService.Notify(player, "⏳ Lock recharging: " .. BaseService.CooldownSecondsLeft(base) .. "s.")
		return
	end
	local duration = Config.LockDuration
	if longLockPassExists and player:GetAttribute("LongLock") then
		duration = duration * 2
	end
	BaseService.StartLock(base, duration)
	setWall(base, true)
	BaseService.Notify(player, "🔒 Base locked for " .. duration .. " seconds!")
end

for _, base in ipairs(BaseService.GetBases()) do
	buildLasers(base)
	local button = base:FindFirstChild("LockButton")
	if button then
		local lastTouch = {} -- [player] = tick() of their last step on this button
		button.Touched:Connect(function(hit)
			local character = hit.Parent
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not humanoid then return end
			local player = game:GetService("Players"):GetPlayerFromCharacter(character)
			if not player then return end
			-- Touched fires a lot: debounce so one step = one try.
			-- F-16: the debounce is PER PLAYER — a single shared timestamp
			-- let any stranger's step (even a refused non-owner try)
			-- swallow the owner's step within the same 0.6s window.
			local now = tick()
			if now - (lastTouch[player] or 0) < 0.6 then return end
			lastTouch[player] = now
			tryLock(player, base)
		end)
	end
end

-- visuals loop: keep walls + button colors in sync with the lock state ---------
task.spawn(function()
	while true do
		task.wait(0.25)
		for _, base in ipairs(BaseService.GetBases()) do
			local button = base:FindFirstChild("LockButton")
			if BaseService.IsLocked(base) then
				setWall(base, true)
				if button then button.Color = COLOR_LOCKED end
			else
				setWall(base, false)
				if button then
					button.Color = BaseService.CanLock(base) and COLOR_READY or COLOR_COOLDOWN
				end
			end
		end
	end
end)
