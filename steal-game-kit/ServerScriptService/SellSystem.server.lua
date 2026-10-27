-- SellSystem (Script -> ServerScriptService)
-- Puts a "Sell" prompt on every placed pet. Only the OWNER can use it:
-- the pet is destroyed, the pad is freed, and the owner gets back
-- 50% of the price (Config.SellBackRate) into PlayerData's Cash.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local BaseService = require(ServerScriptService:WaitForChild("BaseService"))

local collectibles = Workspace:WaitForChild("Collectibles")

local MAX_SELL_DISTANCE = 10 -- matches the Sell prompt's MaxActivationDistance

-- F-07: a ProximityPrompt's Triggered event is client-mediated, so the
-- server re-validates the REAL distance before honoring it — otherwise
-- a modified client could fire the prompt from anywhere on the map.
-- The tolerance above MaxActivationDistance absorbs movement during
-- the prompt's hold time, plus ping.
local DISTANCE_TOLERANCE = 4 -- studs
local function withinPromptRange(player, part, maxDistance)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not part then return false end
	return (root.Position - part.Position).Magnitude <= maxDistance + DISTANCE_TOLERANCE
end

local function onSell(player, pet)
	if pet:GetAttribute("State") ~= "Placed" then return end
	-- F-07: server-side distance re-validation (see withinPromptRange)
	if not withinPromptRange(player, pet.PrimaryPart, MAX_SELL_DISTANCE) then return end
	if pet:GetAttribute("OwnerUserId") ~= player.UserId then
		BaseService.Notify(player, "🙂 This is not your pet — but you could STEAL it...")
		return
	end
	local value = math.floor((pet:GetAttribute("Price") or 0) * Config.SellBackRate)
	local leaderstats = player:FindFirstChild("leaderstats")
	local cash = leaderstats and leaderstats:FindFirstChild("Cash")
	if not cash then
		-- F-12: never destroy a pet that cannot be paid for. The Cash
		-- reference is captured FIRST; the pet is removed only once the
		-- payment target is known to exist. (Previously DestroyPet ran
		-- first and a missing leaderstats meant pet gone, never paid.)
		BaseService.Notify(player, "😢 Couldn't sell right now — your pet is safe.")
		return
	end
	local name = pet:GetAttribute("DisplayName") or "pet"
	BaseService.DestroyPet(pet)
	cash.Value = cash.Value + value
	BaseService.Notify(player, "💵 Sold your " .. name .. " for " .. Config.FormatMoney(value))
end

local function watchPet(pet)
	if pet:GetAttribute("Kind") ~= "Pet" then return end
	local body = pet.PrimaryPart
	if not body then return end
	local sellValue = math.floor((pet:GetAttribute("Price") or 0) * Config.SellBackRate)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SellPrompt"
	prompt.ActionText = "Sell"
	prompt.ObjectText = (pet:GetAttribute("DisplayName") or "Pet") .. " (+" .. Config.FormatMoney(sellValue) .. ")"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = MAX_SELL_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Enabled = pet:GetAttribute("State") == "Placed"
	prompt.Parent = body
	pet:GetAttributeChangedSignal("State"):Connect(function()
		prompt.Enabled = pet:GetAttribute("State") == "Placed"
	end)
	prompt.Triggered:Connect(function(player)
		onSell(player, pet)
	end)
end

for _, child in ipairs(collectibles:GetChildren()) do
	watchPet(child)
end
collectibles.ChildAdded:Connect(watchPet)
