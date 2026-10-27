-- BaseService (ModuleScript -> ServerScriptService)
-- The shared brain used by every system in the steal game:
--   - which player owns which base (Workspace.Bases / Base1..Base6)
--   - which pet sits on which pad
--   - base lock state (locked until / cooldown until)
--   - sending on-screen notifications to a player (NotifyEvent)
-- It owns NO leaderstats: Cash always comes from PlayerData (starter kit).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local BaseService = {}

local bases = {}          -- array of base folders, sorted Base1..Base6
local playerBase = {}     -- [UserId] = base folder
local baseOwner = {}      -- [base folder] = player
local padPet = {}         -- [pad Part] = pet Model
local petPad = {}         -- [pet Model] = pad Part
local petHome = {}        -- [pet Model] = resting CFrame on its pad
local petsOf = {}         -- [UserId] = { [pet Model] = true }
local lockUntil = {}      -- [base folder] = tick() when the lock ends
local cooldownUntil = {}  -- [base folder] = tick() when the lock can be used again
local notifyEvent = nil
local hatchEvent = nil
local initialized = false
local petsChangedListeners = {} -- functions fn(UserId), fired when a player's pet set changes
local suppressPetsChanged = false -- true while ReleaseBase destroys a leaving player's pets

-- Init: scan Workspace.Bases and create the NotifyEvent (once) -------------------
function BaseService.Init()
	if initialized then return end
	initialized = true
	local folder = Workspace:WaitForChild("Bases")
	bases = folder:GetChildren()
	table.sort(bases, function(a, b) return a.Name < b.Name end)
	notifyEvent = ReplicatedStorage:FindFirstChild("NotifyEvent")
	if not notifyEvent then
		notifyEvent = Instance.new("RemoteEvent")
		notifyEvent.Name = "NotifyEvent"
		notifyEvent.Parent = ReplicatedStorage
	end
	hatchEvent = ReplicatedStorage:FindFirstChild("HatchEvent")
	if not hatchEvent then
		hatchEvent = Instance.new("RemoteEvent")
		hatchEvent.Name = "HatchEvent"
		hatchEvent.Parent = ReplicatedStorage
	end
end

local function ensureInit()
	if not initialized then BaseService.Init() end
end

-- Notifications ------------------------------------------------------------------
function BaseService.Notify(player, text)
	ensureInit()
	if player and notifyEvent then
		notifyEvent:FireClient(player, text)
	end
end

-- Tell one player's client to play the cinematic hatch sequence (V2).
-- Presentation only: the server-side hatch is already authoritative.
function BaseService.FireHatch(player, ...)
	ensureInit()
	if player and hatchEvent then
		hatchEvent:FireClient(player, ...)
	end
end

-- Server-wide announcement for the big moments (Legendary+ hatches, any
-- Rainbow mutation). Tries a real chat system message first (TextChatService),
-- pcall-guarded; falls back to the big banner on every screen.
function BaseService.Announce(text)
	ensureInit()
	local sent = false
	pcall(function()
		local TextChatService = game:GetService("TextChatService")
		local channels = TextChatService:FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral")
		if general then
			general:SendSystemMessage("📣 " .. text)
			sent = true
		end
	end)
	if not sent and notifyEvent then
		notifyEvent:FireAllClients("📣 " .. text)
	end
end

-- Bases ----------------------------------------------------------------------------
function BaseService.GetBases()
	ensureInit()
	return bases
end

function BaseService.GetBaseByName(name)
	ensureInit()
	for _, base in ipairs(bases) do
		if base.Name == name then return base end
	end
	return nil
end

-- Give the player the first free base. Returns the base folder or nil.
function BaseService.AssignBase(player)
	ensureInit()
	if playerBase[player.UserId] then
		return playerBase[player.UserId]
	end
	for _, base in ipairs(bases) do
		if not baseOwner[base] then
			baseOwner[base] = player
			playerBase[player.UserId] = base
			return base
		end
	end
	return nil
end

function BaseService.GetBaseOf(player)
	ensureInit()
	if not player then return nil end
	return playerBase[player.UserId]
end

function BaseService.GetOwnerOfBase(base)
	return baseOwner[base]
end

-- The part the player spawns on / steals are delivered to.
function BaseService.GetFloor(base)
	return base and base:FindFirstChild("Floor") or nil
end

-- Free the player's base: destroy their pets, clear pads and lock state.
function BaseService.ReleaseBase(player)
	ensureInit()
	local base = playerBase[player.UserId]
	if not base then return end
	-- The pets are destroyed because the player is LEAVING, not because the
	-- collection changed: PetSaveService must still save the full set as-is.
	suppressPetsChanged = true
	local owned = petsOf[player.UserId]
	if owned then
		local list = {}
		for pet in pairs(owned) do table.insert(list, pet) end
		for _, pet in ipairs(list) do
			BaseService.DestroyPet(pet)
		end
	end
	petsOf[player.UserId] = nil
	suppressPetsChanged = false
	playerBase[player.UserId] = nil
	baseOwner[base] = nil
	lockUntil[base] = nil
	cooldownUntil[base] = nil
end

-- Pads -------------------------------------------------------------------------------
function BaseService.GetPads(base)
	local pads = {}
	if not base then return pads end
	for i = 1, 12 do
		local pad = base:FindFirstChild("Pad" .. i)
		if pad then table.insert(pads, pad) end
	end
	return pads
end

function BaseService.FindFreePad(player)
	local base = BaseService.GetBaseOf(player)
	if not base then return nil end
	for _, pad in ipairs(BaseService.GetPads(base)) do
		if not padPet[pad] then
			return pad
		end
	end
	return nil
end

function BaseService.GetPetOnPad(pad)
	return padPet[pad]
end

function BaseService.GetPadOf(pet)
	return petPad[pet]
end

function BaseService.GetHomeCFrame(pet)
	return petHome[pet]
end

-- Pets ---------------------------------------------------------------------------------
-- Change hook: PetSaveService listens here so it can save the collection
-- whenever it changes (buy/hatch, steal delivered, sell, restore).
local function firePetsChanged(userId)
	if suppressPetsChanged or not userId then return end
	for _, fn in ipairs(petsChangedListeners) do
		fn(userId)
	end
end

function BaseService.OnPetsChanged(fn)
	table.insert(petsChangedListeners, fn)
end

local function registerPet(pet, player)
	if not petsOf[player.UserId] then
		petsOf[player.UserId] = {}
	end
	petsOf[player.UserId][pet] = true
	firePetsChanged(player.UserId)
end

local function unregisterPet(pet)
	local ownerId = pet:GetAttribute("OwnerUserId")
	if ownerId and petsOf[ownerId] and petsOf[ownerId][pet] then
		petsOf[ownerId][pet] = nil
		firePetsChanged(ownerId)
	end
end

-- All pets currently owned by the player (dead entries are cleaned up).
function BaseService.GetPets(player)
	local result = {}
	local owned = petsOf[player.UserId]
	if owned then
		for pet in pairs(owned) do
			if pet.Parent then
				table.insert(result, pet)
			else
				owned[pet] = nil
			end
		end
	end
	return result
end

-- Every placed pet in the game (used by the dragon hover loop).
function BaseService.GetAllPlacedPets()
	local result = {}
	for _, owned in pairs(petsOf) do
		for pet in pairs(owned) do
			if pet.Parent and pet:GetAttribute("State") == "Placed" then
				table.insert(result, pet)
			end
		end
	end
	return result
end

local function facingCFrame(position, faceTarget)
	local flat = Vector3.new(faceTarget.X, position.Y, faceTarget.Z)
	local dir = flat - position
	if dir.Magnitude < 0.01 then
		return CFrame.new(position)
	end
	dir = dir.Unit
	return CFrame.new(position) * CFrame.Angles(0, math.atan2(dir.X, dir.Z), 0)
end

-- Put a pet on a SPECIFIC pad for a player: sets ownership attributes,
-- occupies the pad, positions the pet (facing the belt), registers it.
function BaseService.PlacePetOnPad(pet, player, pad)
	local base = BaseService.GetBaseOf(player)
	if not base or not pad then return false end
	-- F-11: never trust the caller blindly — the pad must belong to THIS
	-- player's base and currently be empty. Otherwise two pets could
	-- share one pad and the first pet's padPet mapping would be silently
	-- overwritten while it still believed it was placed. (All current
	-- callers already pass safe pads; this makes the API itself safe.)
	if pad.Parent ~= base then return false end
	if padPet[pad] then return false end
	local prevOwnerId = pet:GetAttribute("OwnerUserId")
	if prevOwnerId and prevOwnerId ~= player.UserId then
		-- a delivered steal: the pet leaves the previous owner's set first,
		-- so the old owner stops earning (and saving) it
		unregisterPet(pet)
	end
	padPet[pad] = pet
	petPad[pet] = pad
	local groundOffset = pet:GetAttribute("GroundOffset") or 2
	local pos = pad.Position + Vector3.new(0, pad.Size.Y / 2 + groundOffset, 0)
	local home = facingCFrame(pos, Vector3.new(0, pos.Y, pad.Position.Z))
	petHome[pet] = home
	pet:PivotTo(home)
	pet:SetAttribute("OwnerUserId", player.UserId)
	pet:SetAttribute("BaseName", base.Name)
	pet:SetAttribute("PadName", pad.Name)
	pet:SetAttribute("State", "Placed")
	registerPet(pet, player)
	return true
end

-- Put a pet on the first free pad of the player's base.
function BaseService.PlacePet(pet, player)
	local pad = BaseService.FindFreePad(player)
	if not pad then return false end
	return BaseService.PlacePetOnPad(pet, player, pad)
end

-- Remove a pet from its pad (the pet itself survives: used when a steal starts).
function BaseService.DetachPet(pet)
	local pad = petPad[pet]
	if pad then
		padPet[pad] = nil
		petPad[pet] = nil
	end
	petHome[pet] = nil
end

-- Fully remove a pet from the game (sold, or owner left).
function BaseService.DestroyPet(pet)
	BaseService.DetachPet(pet)
	unregisterPet(pet)
	if pet.Parent then
		pet:Destroy()
	end
end

-- Lock state ----------------------------------------------------------------------------
function BaseService.StartLock(base, duration)
	lockUntil[base] = tick() + duration
	cooldownUntil[base] = lockUntil[base] + Config.LockCooldown
end

function BaseService.IsLocked(base)
	if not base then return false end
	return tick() < (lockUntil[base] or 0)
end

function BaseService.LockSecondsLeft(base)
	return math.max(0, math.ceil((lockUntil[base] or 0) - tick()))
end

function BaseService.CooldownSecondsLeft(base)
	return math.max(0, math.ceil((cooldownUntil[base] or 0) - tick()))
end

function BaseService.CanLock(base)
	return not BaseService.IsLocked(base) and BaseService.CooldownSecondsLeft(base) == 0
end

return BaseService
