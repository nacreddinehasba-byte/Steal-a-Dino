-- PlayerData (Script -> ServerScriptService)
-- The money/save backbone. Works for ANY genre (Obby, Tycoon, Simulator...).
-- Saves Cash + Wins per player, loads them back on join, autosaves.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local AUTOSAVE_MINUTES = 5

local store = DataStoreService:GetDataStore("PlayerData_v1")

-- F-01: if a player's save FAILS to load, it must never be overwritten
-- this session — the player plays with defaults, but nothing is saved,
-- so a transient DataStore error cannot wipe real Cash/Wins with zeros.
-- Mirrors PetSaveService's safety rule.
local noSave = {} -- [UserId] = true when the load failed

local function defaultData()
	-- StarterClaimed (F-04): has the one-time starter cash been granted?
	-- Absent in pre-Phase-2 saves -> loads as false -> treated as
	-- unclaimed exactly once, then persisted.
	return { Cash = 0, Wins = 0, StarterClaimed = false }
end

-- Returns the saved data, defaultData() for a brand-new player (no save
-- exists yet), or nil if the load FAILED — that distinction is the
-- safety rule: "no save yet" may save later; "load failed" may not.
local function loadData(player)
	local ok, result = pcall(function()
		return store:GetAsync("PlayerData_v1_" .. player.UserId)
	end)
	if not ok then
		return nil
	end
	if type(result) == "table" then
		return result
	end
	return defaultData()
end

-- F-10: bounded retry with backoff for writes. A single transient
-- SetAsync failure must not silently lose a session's Cash/Wins; if
-- every attempt fails we warn loudly instead of pretending it saved.
local SAVE_ATTEMPTS = 3
local function setWithRetry(key, data)
	for attempt = 1, SAVE_ATTEMPTS do
		local ok = pcall(function()
			store:SetAsync(key, data)
		end)
		if ok then return true end
		if attempt < SAVE_ATTEMPTS then
			task.wait(0.5 * attempt) -- backoff: 0.5s, then 1s
		end
	end
	return false
end

local function saveData(player)
	if noSave[player.UserId] then return end
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end
	local cash = leaderstats:FindFirstChild("Cash")
	local wins = leaderstats:FindFirstChild("Wins")
	local claimed = player:FindFirstChild("StarterClaimed")
	local data = {
		Cash = cash and cash.Value or 0,
		Wins = wins and wins.Value or 0,
		StarterClaimed = (claimed and claimed.Value) or false,
	}
	if not setWithRetry("PlayerData_v1_" .. player.UserId, data) then
		warn("[PlayerData] save FAILED after " .. SAVE_ATTEMPTS .. " attempts for "
			.. player.Name .. " - this session's Cash/Wins were NOT saved")
	end
end

Players.PlayerAdded:Connect(function(player)
	local data = loadData(player)
	if data == nil then
		-- Load FAILED (F-01): play with in-session defaults, but mark the
		-- session no-save so the real saved Cash/Wins are never overwritten.
		noSave[player.UserId] = true
		data = defaultData()
		warn("[PlayerData] load failed for " .. player.Name .. " - saving disabled this session")
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = data.Cash or 0
	cash.Parent = leaderstats

	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Value = data.Wins or 0
	wins.Parent = leaderstats

	leaderstats.Parent = player

	-- F-04: the starter-claim flag lives as a BoolValue on the player
	-- itself (same ValueBase pattern as Cash/Wins, but NOT inside
	-- leaderstats, so it never shows as a leaderboard column).
	-- BaseManager reads/writes this value; saveData persists it.
	local starterClaimed = Instance.new("BoolValue")
	starterClaimed.Name = "StarterClaimed"
	starterClaimed.Value = data.StarterClaimed == true
	starterClaimed.Parent = player
end)

Players.PlayerRemoving:Connect(function(player)
	saveData(player)
	noSave[player.UserId] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveData(player)
	end
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_MINUTES * 60)
		for _, player in ipairs(Players:GetPlayers()) do
			saveData(player)
		end
	end
end)
