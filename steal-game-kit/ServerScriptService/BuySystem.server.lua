-- BuySystem (Script -> ServerScriptService)
-- Puts a "Buy" ProximityPrompt on every egg riding the belt.
-- On buy: check Cash (PlayerData leaderstats) -> deduct -> roll a mutation
-- -> the pet is placed on a free pad of the buyer's base in "Hatching"
-- state while the buyer's client plays the CINEMATIC HATCH (HatchClient):
-- the egg wobbles in front of the camera, longer for rarer eggs.
-- When the timer ends, the server reveals the pet on its pad: a sparkle
-- burst, a flash, one full spin — then it goes live ("Placed").
-- The server flow is authoritative and complete on its own: if the client
-- script is missing or errors, the pet still appears on schedule (v1
-- fallback), it just skips the show on that player's screen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local PetFactory = require(ReplicatedStorage:WaitForChild("PetFactory"))
local BaseService = require(ServerScriptService:WaitForChild("BaseService"))

local collectibles = Workspace:WaitForChild("Collectibles")

local MAX_BUY_DISTANCE = 12 -- matches the Buy prompt's MaxActivationDistance

-- F-07: a ProximityPrompt's Triggered event is client-mediated, so the
-- server re-validates the REAL distance before honoring it — otherwise
-- a modified client could fire the prompt from anywhere on the map.
-- The tolerance above MaxActivationDistance absorbs the movement a
-- player makes during the prompt's hold time, plus ping.
local DISTANCE_TOLERANCE = 4 -- studs
local function withinPromptRange(player, part, maxDistance)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not part then return false end
	return (root.Position - part.Position).Magnitude <= maxDistance + DISTANCE_TOLERANCE
end

local function getCash(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local cash = leaderstats and leaderstats:FindFirstChild("Cash")
	return cash
end

-- The reveal: burst + flash + one spin on the pad, then the pet goes live.
local function revealPet(player, pet)
	if not pet.Parent then return end
	if pet:GetAttribute("State") ~= "Hatching" then return end
	local body = pet.PrimaryPart
	local home = BaseService.GetHomeCFrame(pet)

	if body then
		local burst = body:FindFirstChild("HatchBurst")
		if burst then
			burst:Emit(30)
		end
		-- a quick flash of light in the pet's glow color
		local rar = Config.Rarities[pet:GetAttribute("Rarity")]
		local flash = Instance.new("PointLight")
		flash.Color = (pet:GetAttribute("Mutation") == "Rainbow") and Color3.fromRGB(255, 120, 220)
			or (rar and rar.Accent) or Color3.fromRGB(255, 255, 255)
		flash.Brightness = 4
		flash.Range = 14
		flash.Parent = body
		task.delay(0.5, function()
			if flash.Parent then flash:Destroy() end
		end)
	end

	-- one full spin, easing onto the home CFrame (PetAnim takes over after)
	if home then
		local steps = 14
		for i = 1, steps do
			if not pet.Parent then return end
			local angle = math.rad(360) * (i / steps)
			pet:PivotTo(home * CFrame.Angles(0, angle, 0))
			task.wait(0.03)
		end
		pet:PivotTo(home)
	end
	if not pet.Parent then return end

	pet:SetAttribute("State", "Placed")
	local displayName = pet:GetAttribute("DisplayName") or "pet"
	local mutation = pet:GetAttribute("Mutation")
	BaseService.Notify(player, "🥚 Your egg hatched into a " .. displayName .. "!")

	-- the moments the whole server hears about
	local rar = Config.Rarities[pet:GetAttribute("Rarity")]
	if mutation == "Rainbow" then
		local sp = Config.Species[pet:GetAttribute("Species")]
		BaseService.Announce(player.DisplayName .. " hatched a RAINBOW " .. (sp and sp.DisplayName or displayName) .. "!! 🌈")
	elseif rar and rar.Order >= 4 then
		BaseService.Announce(player.DisplayName .. " hatched a " .. string.upper(pet:GetAttribute("Rarity")) .. " " .. displayName .. "!")
	end
end

local function onBuy(player, egg)
	if egg:GetAttribute("State") ~= "Belt" then return end
	-- F-07: server-side distance re-validation (see withinPromptRange)
	if not withinPromptRange(player, egg.PrimaryPart, MAX_BUY_DISTANCE) then return end
	-- claim the egg first so two players can't buy it in the same instant
	egg:SetAttribute("State", "Buying")

	local price = egg:GetAttribute("Price") or 0
	local speciesKey = egg:GetAttribute("Species")

	local cash = getCash(player)
	if not cash then
		egg:SetAttribute("State", "Belt")
		return
	end
	if cash.Value < price then
		BaseService.Notify(player, "💰 Not enough Cash! This egg costs " .. Config.FormatMoney(price))
		egg:SetAttribute("State", "Belt")
		return
	end
	if not BaseService.GetBaseOf(player) then
		BaseService.Notify(player, "⏳ You don't have a base yet...")
		egg:SetAttribute("State", "Belt")
		return
	end
	if not BaseService.FindFreePad(player) then
		BaseService.Notify(player, "🚫 Your base is full! Sell a pet to make room.")
		egg:SetAttribute("State", "Belt")
		return
	end

	-- F-09: build the pet BEFORE any money moves, and guard the build.
	-- If BuildPet ever errors (a future species-definition typo is
	-- enough — it indexes Config.Species unguarded), the player keeps
	-- their cash and the egg goes back on the belt: never charged for
	-- a pet that does not exist. (Previously cash was deducted and the
	-- egg destroyed first, with no pcall anywhere in the flow.)
	local mutation = Config.RollMutation()
	local buildOk, pet = pcall(PetFactory.BuildPet, speciesKey, mutation)
	if not buildOk or not pet then
		warn("[BuySystem] BuildPet failed for " .. tostring(speciesKey) .. ": " .. tostring(pet))
		egg:SetAttribute("State", "Belt")
		BaseService.Notify(player, "😢 That egg glitched — you were not charged.")
		return
	end
	pet.Parent = collectibles

	-- pay, consume the egg, place (hidden in "Hatching" state). The pad
	-- was checked above and nothing in this block yields, so the pad
	-- cannot be taken between the check and the placement.
	cash.Value = cash.Value - price
	egg:Destroy()
	local placeOk, placed = pcall(function()
		return BaseService.PlacePet(pet, player)
	end)
	if placeOk and placed then
		-- CINEMATIC HATCH: the pad is reserved and the pet is already saved;
		-- only its public reveal waits for the show to finish.
		pet:SetAttribute("State", "Hatching")
		local sp = Config.Species[speciesKey]
		local rar = Config.Rarities[sp.Rarity]
		local duration = Config.HatchDuration(sp.Rarity, mutation)
		BaseService.FireHatch(player, speciesKey,
			pet:GetAttribute("DisplayName"), sp.Rarity, rar.Order,
			mutation or "", duration)
		task.delay(duration, function()
			revealPet(player, pet)
		end)
	else
		-- the pad vanished in a race: refund and clean up
		cash.Value = cash.Value + price
		pet:Destroy()
		BaseService.Notify(player, "🚫 Your base is full! Sell a pet to make room.")
	end
end

local function watchEgg(egg)
	if egg:GetAttribute("Kind") ~= "Egg" then return end
	local shell = egg.PrimaryPart
	if not shell then return end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPrompt"
	prompt.ActionText = "Buy"
	prompt.ObjectText = (egg:GetAttribute("DisplayName") or "Mystery") .. " Egg - " .. Config.FormatMoney(egg:GetAttribute("Price") or 0)
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = MAX_BUY_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = shell
	prompt.Triggered:Connect(function(player)
		onBuy(player, egg)
	end)
end

for _, child in ipairs(collectibles:GetChildren()) do
	watchEgg(child)
end
collectibles.ChildAdded:Connect(watchEgg)
