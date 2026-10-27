-- PetSaveService (Script -> ServerScriptService)
-- Saves each player's owned dinos/dragons so the collection survives
-- between sessions, the way Cash does in PlayerData (starter kit).
--
-- HOW IT WORKS:
--   - Its own DataStore ("StealDinoPets_v1") stores the ordered list of
--     owned pets as records: { Species = key, Mutation = name or absent }.
--     V1 saves stored bare species strings ("Compy") — the loader accepts
--     both, so old collections migrate silently on first load.
--   - A SHADOW list per player mirrors the real collection (pets on pads
--     + pets in storage). BaseService fires OnPetsChanged whenever the
--     registry changes -> the shadow is re-synced and a save is queued.
--   - Saving therefore never reads the live registry at leave time, so
--     it cannot be fooled by BaseService.ReleaseBase destroying the pets
--     of a player who is on their way out.
--   - SAFETY RULE: if the save file FAILS to load, it is never overwritten
--     this session (the player plays, but nothing is saved) — a failed
--     load must never wipe a real collection with an empty list.
--   - F-03: records naming a species that is NOT in the current Config
--     (renamed/removed species, or a save from a newer place version)
--     are never dropped: they are preserved verbatim in the payload's
--     reserved Held section and written back unchanged on every save.
--   - OVERFLOW: a base has fewer pads than a big collection. On return,
--     the most valuable pets (highest income) take the pads; the rest
--     wait in storage and are placed automatically when a pad frees.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local PetFactory = require(ReplicatedStorage:WaitForChild("PetFactory"))
local BaseService = require(ServerScriptService:WaitForChild("BaseService"))

local AUTOSAVE_SECONDS = 180 -- autosave changed collections every ~3 minutes
local MAX_SAVED_PETS = 200   -- sanity cap on a save file

local store = DataStoreService:GetDataStore("StealDinoPets_v1")

local collectibles = Workspace:WaitForChild("Collectibles")

local loaded = {}            -- [UserId] = true once the save file was read (new players count as read-empty)
local noSave = {}            -- [UserId] = true if the load FAILED: never write this session
local restoring = {}         -- [UserId] = true while saved pets are being placed on join
local changedBeforeLoad = {} -- [UserId] = true if the registry changed before the load landed
local shadow = {}            -- [UserId] = { record, ... } full collection: placed + storage
local held = {}              -- [UserId] = { rawEntry, ... } records with species missing from Config, kept verbatim (F-03)
local reserve = {}           -- [UserId] = { record, ... } owned but not placed (base full), best first
local dirty = {}             -- [UserId] = true when the shadow is newer than the last successful save
local saveQueued = {}        -- [UserId] = true while a debounced save is pending
local filling = {}           -- [UserId] = true while storage pets are being placed (re-entry guard)

-- A record is { Species = key, Mutation = "Golden"|"Rainbow"|nil } --------------
local function recordIncome(rec)
	local sp = Config.Species[rec.Species]
	if not sp then return 0 end
	local def = rec.Mutation and Config.Mutations[rec.Mutation]
	return sp.Income * (def and def.Mult or 1)
end

local function sortByValue(list)
	table.sort(list, function(a, b) return recordIncome(a) > recordIncome(b) end)
end

-- The records of the pets currently in the player's registry ---------------------
local function placedRecords(player)
	local list = {}
	for _, pet in ipairs(BaseService.GetPets(player)) do
		local key = pet:GetAttribute("Species")
		if key and Config.Species[key] then
			local mutation = pet:GetAttribute("Mutation")
			if mutation == "" or not Config.Mutations[mutation] then
				mutation = nil
			end
			table.insert(list, { Species = key, Mutation = mutation })
		end
	end
	return list
end

local function syncShadow(player)
	local userId = player.UserId
	local full = placedRecords(player)
	for _, rec in ipairs(reserve[userId] or {}) do
		table.insert(full, rec)
	end
	shadow[userId] = full
end

-- Saving -------------------------------------------------------------------------
-- F-10: bounded retry with backoff for writes. A failed save keeps the
-- player dirty (the save is retried on the next autosave/leave), and the
-- retry loop gives a transient DataStore hiccup three chances before
-- that ever becomes necessary.
local SAVE_ATTEMPTS = 3
local function setWithRetry(key, payload)
	for attempt = 1, SAVE_ATTEMPTS do
		local ok = pcall(function()
			store:SetAsync(key, payload)
		end)
		if ok then return true end
		if attempt < SAVE_ATTEMPTS then
			task.wait(0.5 * attempt) -- backoff: 0.5s, then 1s
		end
	end
	return false
end

local function savePlayer(player)
	local userId = player.UserId
	if not loaded[userId] or noSave[userId] then return end
	if not dirty[userId] then return end
	local list = {}
	for _, rec in ipairs(shadow[userId] or {}) do
		-- store plain data only: { Species = ..., Mutation = ... or absent }
		local entry = { Species = rec.Species }
		if rec.Mutation then
			entry.Mutation = rec.Mutation
		end
		table.insert(list, entry)
	end
	local payload = { Pets = list }
	-- F-03: records the loader could not recognize ride along verbatim in
	-- their reserved section, so no save can ever delete them.
	if held[userId] and #held[userId] > 0 then
		payload.Held = held[userId]
	end
	local ok = setWithRetry("StealDinoPets_v1_" .. userId, payload)
	if ok then
		dirty[userId] = false
	else
		warn("[PetSaveService] save failed for " .. player.Name .. " after " .. SAVE_ATTEMPTS
			.. " attempts - still marked dirty, will retry on autosave/leave")
	end
end

-- Changes come in bursts (a hatch, a steal, a restore): wait a moment,
-- then save once with the final state.
local function queueSave(player)
	local userId = player.UserId
	if saveQueued[userId] then return end
	saveQueued[userId] = true
	task.delay(1.5, function()
		saveQueued[userId] = nil
		if player.Parent then
			savePlayer(player)
		end
	end)
end

-- Storage: place waiting pets on pads that freed up -------------------------------
local function fillReserve(player)
	local userId = player.UserId
	if filling[userId] then return end
	local list = reserve[userId]
	if not list or #list == 0 then return end
	if not BaseService.GetBaseOf(player) then return end
	filling[userId] = true
	while #list > 0 and BaseService.FindFreePad(player) do
		local rec = table.remove(list, 1) -- the list is sorted: best pet first
		local pet = PetFactory.BuildPet(rec.Species, rec.Mutation)
		pet.Parent = collectibles
		if BaseService.PlacePet(pet, player) then
			BaseService.Notify(player, "📦 A " .. pet:GetAttribute("DisplayName") .. " came out of storage!")
		else
			pet:Destroy()
			table.insert(list, 1, rec)
			break
		end
	end
	filling[userId] = nil
	syncShadow(player)
end

-- The registry changed for someone: keep the shadow true, save, refill pads ------
BaseService.OnPetsChanged(function(userId)
	local player = Players:GetPlayerByUserId(userId)
	if not player then return end
	if restoring[userId] then
		syncShadow(player) -- the restore pass sets dirty/storage itself at the end
		return
	end
	if not loaded[userId] then
		changedBeforeLoad[userId] = true -- merged when the load lands (see below)
		return
	end
	syncShadow(player)
	dirty[userId] = true
	fillReserve(player)
	queueSave(player)
end)

-- Loading --------------------------------------------------------------------------
-- Returns (validList, heldList), or nil if the load FAILED (that
-- distinction is the safety rule). An empty validList means a new player.
-- Accepts V2 records ({ Species = ..., Mutation = ... }) and V1 bare
-- species strings, which migrate to mutation-less records.
-- F-03: entries whose species is missing from the current Config go to
-- heldList VERBATIM (never dropped); both the Pets and Held sections of
-- the payload are re-classified on every load, so a species that returns
-- to Config restores its pets normally again. The MAX_SAVED_PETS cap
-- still applies to the valid list exactly as before.
local function loadList(player)
	local ok, result = pcall(function()
		return store:GetAsync("StealDinoPets_v1_" .. player.UserId)
	end)
	if not ok then
		return nil
	end
	local list = {}
	local heldList = {}
	if type(result) == "table" then
		for _, section in ipairs({ result.Pets, result.Held }) do
			if type(section) == "table" then
				for _, entry in ipairs(section) do
					if type(entry) == "string" and Config.Species[entry] then
						if #list < MAX_SAVED_PETS then
							table.insert(list, { Species = entry }) -- V1 record
						end
						-- valid records past the cap are dropped, as before
					elseif type(entry) == "table" and type(entry.Species) == "string"
						and Config.Species[entry.Species] then
						if #list < MAX_SAVED_PETS then
							local mutation = entry.Mutation
							if type(mutation) ~= "string" or not Config.Mutations[mutation] then
								mutation = nil
							end
							table.insert(list, { Species = entry.Species, Mutation = mutation })
						end
					else
						-- unknown species / unrecognized shape: preserve verbatim
						table.insert(heldList, entry)
					end
				end
			end
		end
	end
	if #heldList > 0 then
		warn("[PetSaveService] " .. #heldList .. " saved pet record(s) for " .. player.Name
			.. " name species missing from the current Config - held in the save file,"
			.. " NOT deleted (F-03)")
	end
	return list, heldList
end

local function restorePlayer(player, savedList)
	local userId = player.UserId
	restoring[userId] = true
	reserve[userId] = {}
	sortByValue(savedList) -- the most valuable pets get the pads
	for _, rec in ipairs(savedList) do
		local placedOk = false
		if BaseService.FindFreePad(player) then
			local pet = PetFactory.BuildPet(rec.Species, rec.Mutation)
			pet.Parent = collectibles
			placedOk = BaseService.PlacePet(pet, player)
			if not placedOk then
				pet:Destroy()
			end
		end
		if not placedOk then
			table.insert(reserve[userId], rec)
		end
	end
	sortByValue(reserve[userId])
	restoring[userId] = nil
	syncShadow(player)
	if changedBeforeLoad[userId] then
		-- the player gained a pet before the load landed: the shadow is
		-- already the union of both, so it must be saved back
		changedBeforeLoad[userId] = nil
		dirty[userId] = true
		queueSave(player)
	end
	if #reserve[userId] > 0 then
		BaseService.Notify(player, "📦 " .. #reserve[userId]
			.. " pet(s) are in storage - sell a pet and they will come out!")
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		local savedList, heldList = loadList(player)
		if not player.Parent then return end -- left before the load landed
		if savedList == nil then
			-- load FAILED: protect the real save file, save nothing today
			noSave[player.UserId] = true
			loaded[player.UserId] = true
			warn("[PetSaveService] load failed for " .. player.Name .. " - saving disabled this session")
			return
		end
		loaded[player.UserId] = true
		held[player.UserId] = heldList -- F-03: rides along verbatim on every save
		-- wait for BaseManager to hand the player a base
		local waited = 0
		while player.Parent and not BaseService.GetBaseOf(player) and waited < 30 do
			task.wait(0.25)
			waited = waited + 0.25
		end
		if not player.Parent then return end
		if BaseService.GetBaseOf(player) then
			restorePlayer(player, savedList)
		else
			-- no free base (server full): keep the collection as storage in
			-- the shadow, untouched, so it can never be lost by a later save
			reserve[player.UserId] = savedList
			syncShadow(player)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	-- The shadow is authoritative even if ReleaseBase already destroyed
	-- the pets: saving here can never write a half-emptied list.
	savePlayer(player)
	local userId = player.UserId
	loaded[userId] = nil
	noSave[userId] = nil
	restoring[userId] = nil
	changedBeforeLoad[userId] = nil
	shadow[userId] = nil
	held[userId] = nil
	reserve[userId] = nil
	dirty[userId] = nil
	saveQueued[userId] = nil
	filling[userId] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		savePlayer(player)
	end
end)

-- AUTOSAVE: every ~3 minutes, save whoever changed --------------------------------
task.spawn(function()
	while true do
		task.wait(AUTOSAVE_SECONDS)
		for _, player in ipairs(Players:GetPlayers()) do
			savePlayer(player)
		end
	end
end)
