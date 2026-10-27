-- BaseManager (Script -> ServerScriptService)
-- The conductor: gives each player a base, teleports them to it,
-- grants the one-time starter cash, pays pad income every second,
-- and poses every placed pet each frame via PetAnim (dragons hover).
-- Cash itself lives in PlayerData (starter kit) — this only adds to it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local PetAnim = require(ReplicatedStorage:WaitForChild("PetAnim"))
local BaseService = require(ServerScriptService:WaitForChild("BaseService"))

BaseService.Init()

local starterGranted = {} -- [UserId] = true, per server session (second lock;
-- the authoritative once-ever lock is PlayerData's persisted
-- StarterClaimed flag — F-04)

local function teleportToBase(player)
	local base = BaseService.GetBaseOf(player)
	local floor = BaseService.GetFloor(base)
	local character = player.Character
	if not floor or not character then return end
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if root then
		root.CFrame = CFrame.new(floor.Position + Vector3.new(0, 4, 0))
			* CFrame.Angles(0, math.atan2(-floor.Position.X, 0.001), 0)
	end
end

Players.PlayerAdded:Connect(function(player)
	-- Starter cash: PlayerData starts everyone at 0, and the cheapest egg
	-- costs money — grant ONCE per player, ever, so the first egg is
	-- reachable. F-04: the grant is gated by PlayerData's persisted
	-- StarterClaimed flag (a BoolValue on the player); the old
	-- per-session table remains only as a second lock.
	task.spawn(function()
		local leaderstats = player:WaitForChild("leaderstats", 15)
		if not leaderstats then return end
		local cash = leaderstats:FindFirstChild("Cash")
		local claimed = player:WaitForChild("StarterClaimed", 15)
		if cash and claimed and not claimed.Value
			and not starterGranted[player.UserId]
			and cash.Value < Config.CheapestPrice then
			starterGranted[player.UserId] = true
			claimed.Value = true -- persisted by PlayerData on the next save
			cash.Value = Config.StarterCash
		end
	end)

	player.CharacterAdded:Connect(function()
		task.wait(0.2)
		if not BaseService.GetBaseOf(player) then
			BaseService.AssignBase(player)
		end
		teleportToBase(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	BaseService.ReleaseBase(player)
	starterGranted[player.UserId] = nil
end)

-- INCOME TICK: every second, each placed pet pays its owner ---------------------
-- The starter kit's "DoubleCash" gamepass attribute doubles the payout.
task.spawn(function()
	while true do
		task.wait(1)
		for _, player in ipairs(Players:GetPlayers()) do
			local total = 0
			for _, pet in ipairs(BaseService.GetPets(player)) do
				if pet:GetAttribute("State") == "Placed" then
					total = total + (pet:GetAttribute("IncomePerSec") or 0)
				end
			end
			if total > 0 then
				if player:GetAttribute("DoubleCash") then
					total = total * 2
				end
				local leaderstats = player:FindFirstChild("leaderstats")
				local cash = leaderstats and leaderstats:FindFirstChild("Cash")
				if cash then
					cash.Value = cash.Value + total
				end
			end
		end
	end
end)

-- IDLE LIFE (V2): every placed pet is posed by PetAnim each frame — bob,
-- sway, wagging tails, turning heads, chomping jaws, flapping wings.
-- Dragons additionally HOVER: their home CFrame gets a bigger bob here,
-- and PetAnim layers the wing flap on top.
RunService.Heartbeat:Connect(function()
	local t = tick()
	for _, pet in ipairs(BaseService.GetAllPlacedPets()) do
		local home = BaseService.GetHomeCFrame(pet)
		if home then
			local cf = home
			if pet:GetAttribute("Hover") then
				local phase = pet:GetAttribute("HoverPhase") or 0
				local bob = math.sin(t * 1.8 + phase) * 0.35
				cf = home * CFrame.new(0, bob, 0)
			end
			PetAnim.ApplyIdle(pet, t, cf)
		end
	end
end)
