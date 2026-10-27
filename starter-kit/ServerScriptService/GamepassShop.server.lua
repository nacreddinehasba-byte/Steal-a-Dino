-- GamepassShop (Script -> ServerScriptService)
-- Handles gamepass purchases defined in the Gamepasses module.
-- Granting = setting an attribute on the player; the genre code
-- reads that attribute to apply the effect (double cash, VIP, ...).

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gamepasses = require(ReplicatedStorage:WaitForChild("Gamepasses"))

local idToEffect = {}
for _, pass in ipairs(Gamepasses) do
	if pass.Id and pass.Id > 0 then
		idToEffect[pass.Id] = pass.Effect
	end
end

-- Call this from a shop button to ask the player to buy:
--   MarketplaceService:PromptGamePassPurchase(player, gamePassId)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if not wasPurchased then return end
	local effect = idToEffect[gamePassId]
	if not effect then return end
	player:SetAttribute(effect, true)
	print(player.Name .. " bought gamepass " .. gamePassId .. " -> " .. effect)
end)

-- Re-grant owned passes on join (effects survive rejoin)
Players.PlayerAdded:Connect(function(player)
	for gamePassId, effect in pairs(idToEffect) do
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
		end)
		if ok and owns then
			player:SetAttribute(effect, true)
		end
	end
end)
