-- StealSystem (Script -> ServerScriptService)
-- Puts a "Steal" prompt on every placed pet. Stealing works like this:
--   - press the prompt on SOMEONE ELSE's pet (their base must not be locked)
--   - the pet leaves its pad and rides above your head; you walk SLOW (10)
--   - reach your own base floor -> the pet lands on your free pad, yours now
--   - die or leave while carrying -> the pet returns to its original pad
-- The owner gets an on-screen warning the moment the steal starts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local BaseService = require(ServerScriptService:WaitForChild("BaseService"))

local collectibles = Workspace:WaitForChild("Collectibles")

local MAX_STEAL_DISTANCE = 10 -- matches the Steal prompt's MaxActivationDistance

-- F-07: a ProximityPrompt's Triggered event is client-mediated, so the
-- server re-validates the REAL distance between the thief's character
-- and the pet before honoring a steal — otherwise a modified client
-- could start a steal from anywhere on the map. The tolerance above
-- MaxActivationDistance absorbs movement during the prompt's hold
-- time, plus ping. Server position only; client claims are never read.
local DISTANCE_TOLERANCE = 4 -- studs
local function withinPromptRange(player, part, maxDistance)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not part then return false end
	return (root.Position - part.Position).Magnitude <= maxDistance + DISTANCE_TOLERANCE
end

local carries = {}     -- [thief Player] = pet Model
local petCarrier = {}  -- [pet Model] = thief Player
local returnInfo = {}  -- [pet Model] = { OwnerId = n, BaseName = s, PadName = s }

local function setWalkSpeed(player, speed)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = speed
	end
end

local function endCarry(thief)
	carries[thief] = nil
	setWalkSpeed(thief, Config.NormalWalkSpeed)
end

-- Send a carried pet back to its original owner's pad --------------------------
local function returnPet(pet)
	local info = returnInfo[pet]
	returnInfo[pet] = nil
	local thief = petCarrier[pet]
	petCarrier[pet] = nil
	if thief then endCarry(thief) end
	pet:SetAttribute("CarrierUserId", nil)
	if not pet.Parent or not info then return end

	local owner = Players:GetPlayerByUserId(info.OwnerId)
	if not owner or not BaseService.GetBaseOf(owner) then
		pet:Destroy() -- owner is gone; BaseService.ReleaseBase also cleans up
		return
	end
	local base = BaseService.GetBaseOf(owner)
	local originalPad = base and base:FindFirstChild(info.PadName)
	if originalPad and not BaseService.GetPetOnPad(originalPad) then
		BaseService.PlacePetOnPad(pet, owner, originalPad)
	else
		-- the original pad was taken meanwhile: any free pad, or the pet is lost
		if not BaseService.PlacePet(pet, owner) then
			-- F-05: go through BaseService.DestroyPet (unregister + fire
			-- OnPetsChanged) so PetSaveService drops the pet from its
			-- shadow too. A raw pet:Destroy() left the record in the
			-- save, and the "lost" pet resurrected on the next join.
			BaseService.DestroyPet(pet)
			BaseService.Notify(owner, "😢 Your stolen pet was lost — your base was full!")
			return
		end
	end
	BaseService.Notify(owner, "↩️ Your " .. (pet:GetAttribute("DisplayName") or "pet") .. " came back!")
end

local function deliverPet(thief, pet)
	petCarrier[pet] = nil
	returnInfo[pet] = nil
	endCarry(thief)
	local oldOwnerId = pet:GetAttribute("OwnerUserId")
	pet:SetAttribute("CarrierUserId", nil)
	if BaseService.PlacePet(pet, thief) then
		BaseService.Notify(thief, "✅ You stole a " .. (pet:GetAttribute("DisplayName") or "pet") .. "!")
		local oldOwner = oldOwnerId and Players:GetPlayerByUserId(oldOwnerId)
		if oldOwner then
			BaseService.Notify(oldOwner, "😱 " .. thief.DisplayName .. " stole your "
				.. (pet:GetAttribute("DisplayName") or "pet") .. "!")
		end
	else
		-- no free pad after all (filled during the run): send it back
		returnInfo[pet] = { OwnerId = oldOwnerId, BaseName = pet:GetAttribute("BaseName"), PadName = pet:GetAttribute("PadName") }
		returnPet(pet)
		BaseService.Notify(thief, "🚫 Your base filled up — the pet went back!")
	end
end

local function startSteal(thief, pet)
	local ownerId = pet:GetAttribute("OwnerUserId")
	if thief.UserId == ownerId then
		BaseService.Notify(thief, "🙂 That's your own pet!")
		return
	end
	if pet:GetAttribute("State") ~= "Placed" then return end
	-- F-07: server-side distance re-validation (see withinPromptRange)
	if not withinPromptRange(thief, pet.PrimaryPart, MAX_STEAL_DISTANCE) then return end
	if carries[thief] then
		BaseService.Notify(thief, "✋ You are already carrying a pet!")
		return
	end
	local owner = ownerId and Players:GetPlayerByUserId(ownerId)
	local ownerBase = owner and BaseService.GetBaseOf(owner)
	if not ownerBase then return end
	if BaseService.IsLocked(ownerBase) then
		BaseService.Notify(thief, "🔒 That base is locked!")
		return
	end
	if not BaseService.GetBaseOf(thief) or not BaseService.FindFreePad(thief) then
		BaseService.Notify(thief, "🚫 Your base is full! Sell a pet to make room.")
		return
	end

	-- remember the home pad BEFORE detaching, so the pet can return
	returnInfo[pet] = {
		OwnerId = ownerId,
		BaseName = pet:GetAttribute("BaseName"),
		PadName = pet:GetAttribute("PadName"),
	}
	BaseService.DetachPet(pet)
	pet:SetAttribute("State", "Carried")
	pet:SetAttribute("CarrierUserId", thief.UserId)
	carries[thief] = pet
	petCarrier[pet] = thief
	setWalkSpeed(thief, Config.StealWalkSpeed)

	-- death while carrying = the pet goes home
	local character = thief.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local connection
		connection = humanoid.Died:Connect(function()
			connection:Disconnect()
			if petCarrier[pet] == thief then
				returnPet(pet)
			end
		end)
	end

	BaseService.Notify(owner, "⚠️ " .. thief.DisplayName .. " is stealing your "
		.. (pet:GetAttribute("DisplayName") or "pet") .. "!")
	BaseService.Notify(thief, "🏃 Run! Bring it to YOUR base!")
end

-- carry loop: ride above the thief's head + check arrival at the thief's base ---
RunService.Heartbeat:Connect(function()
	for thief, pet in pairs(carries) do
		if not pet.Parent or not thief.Parent then
			-- pet destroyed (owner left) or thief left the game
			if pet.Parent then
				returnPet(pet) -- clears the carry tables + restores speed itself
			else
				-- F-06: the pet is GONE, so returnPet has nothing to send
				-- home — but the carry must still be closed out: clear the
				-- tables AND give the thief their normal speed back via
				-- endCarry. The old code cleared the tables only, leaving
				-- the thief stuck at steal speed (10) until their next
				-- respawn whenever the owner left mid-carry.
				if thief.Parent then
					endCarry(thief)
				else
					carries[thief] = nil
				end
				petCarrier[pet] = nil
				returnInfo[pet] = nil
			end
		else
			local character = thief.Character
			local head = character and character:FindFirstChild("Head")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if head and root then
				local lift = 2.0 + (pet:GetAttribute("GroundOffset") or 2) * 0.55
				local look = root.CFrame.LookVector
				local yaw = math.atan2(look.X, look.Z)
				pet:PivotTo(CFrame.new(head.Position + Vector3.new(0, lift, 0))
					* CFrame.Angles(0, yaw, 0))
				-- arrived home?
				local base = BaseService.GetBaseOf(thief)
				local floor = BaseService.GetFloor(base)
				if floor then
					local dx = math.abs(root.Position.X - floor.Position.X)
					local dz = math.abs(root.Position.Z - floor.Position.Z)
					if dx <= floor.Size.X / 2 + 2 and dz <= floor.Size.Z / 2 + 2 then
						deliverPet(thief, pet)
					end
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local pet = carries[player]
	if pet then
		returnPet(pet)
	end
end)

-- prompts -------------------------------------------------------------------------
local function watchPet(pet)
	if pet:GetAttribute("Kind") ~= "Pet" then return end
	local body = pet.PrimaryPart
	if not body then return end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StealPrompt"
	prompt.ActionText = "Steal!"
	prompt.ObjectText = pet:GetAttribute("DisplayName") or "Pet"
	prompt.HoldDuration = 0.8
	prompt.MaxActivationDistance = MAX_STEAL_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Enabled = pet:GetAttribute("State") == "Placed"
	prompt.Parent = body
	pet:GetAttributeChangedSignal("State"):Connect(function()
		prompt.Enabled = pet:GetAttribute("State") == "Placed"
	end)
	prompt.Triggered:Connect(function(player)
		startSteal(player, pet)
	end)
end

for _, child in ipairs(collectibles:GetChildren()) do
	watchPet(child)
end
collectibles.ChildAdded:Connect(watchPet)
