-- HatchClient (LocalScript -> StarterPlayerScripts)
-- The client half of the CINEMATIC HATCH (V2). When you buy an egg, the
-- server fires "HatchEvent" and this script plays the show on YOUR screen:
-- the egg floats in front of your camera and WOBBLES — harder and faster
-- the rarer it is — then cracks away in a flash and a big rarity banner
-- names what you got. The actual pet is already placed on your pad by the
-- server and is revealed there at the same moment; this script is pure
-- presentation and the game works fine if it never runs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local PetFactory = require(ReplicatedStorage:WaitForChild("PetFactory"))

local player = Players.LocalPlayer
local hatchEvent = ReplicatedStorage:WaitForChild("HatchEvent")

-- sounds -------------------------------------------------------------------------
-- Free Creator Store audio; every id copied from the asset's own store page:
--   Wobble (rising tension) : "Panic Rise"                   by @APMOfficial
--   Crack                   : "Crack Egg Crunchy 11 (SFX)"   by @ProSoundEffects
--   Reveal sting            : "Winner"                       by @APMOfficial
--   Buy cha-ching           : "Cash Register 2 (SFX)"        by @ProSoundEffects
--   Roar (Legendary+)       : "dinosaur roar"
local function makeSound(name, soundId)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Volume = 0.6
	sound.Parent = SoundService
	return sound
end
local WOBBLE_LENGTH = 19 -- seconds; full length of "Panic Rise"
local wobbleSound = makeSound("HatchWobbleSound", "rbxassetid://9039693959")
local crackSound = makeSound("HatchCrackSound", "rbxassetid://9113959343")
local popSound = makeSound("HatchPopSound", "rbxassetid://1844584698")
local buySound = makeSound("BuyChaChingSound", "rbxassetid://9113728049")
local roarSound = makeSound("HatchRoarSound", "rbxassetid://86547343520576")
local LEGENDARY_ORDER = Config.Rarities.Legendary.Order

-- GUI ----------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "HatchGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")

local flash = Instance.new("Frame")
flash.Name = "Flash"
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.Parent = gui

local banner = Instance.new("Frame")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.Position = UDim2.fromScale(0.5, 0.3)
banner.Size = UDim2.fromOffset(460, 130)
banner.BackgroundTransparency = 1
banner.Visible = false
banner.Parent = gui

local rarityLabel = Instance.new("TextLabel")
rarityLabel.Name = "Rarity"
rarityLabel.Size = UDim2.fromScale(1, 0.38)
rarityLabel.BackgroundTransparency = 1
rarityLabel.Font = Enum.Font.GothamBlack
rarityLabel.TextScaled = true
rarityLabel.TextStrokeTransparency = 0.2
rarityLabel.Parent = banner

local nameLabel = Instance.new("TextLabel")
nameLabel.Name = "PetName"
nameLabel.Size = UDim2.fromScale(1, 0.62)
nameLabel.Position = UDim2.fromScale(0, 0.38)
nameLabel.BackgroundTransparency = 1
nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
nameLabel.Font = Enum.Font.GothamBlack
nameLabel.TextScaled = true
nameLabel.TextStrokeTransparency = 0.2
nameLabel.Parent = banner

-- the show ------------------------------------------------------------------------
local showToken = 0

local function playHatch(speciesKey, displayName, rarityName, rarityOrder, mutation, duration)
	showToken = showToken + 1
	local myToken = showToken
	local camera = Workspace.CurrentCamera
	if not camera then return end
	duration = duration or 2
	rarityOrder = rarityOrder or 1
	local rar = Config.Rarities[rarityName]
	local accent = rar and rar.Accent or Color3.fromRGB(255, 255, 255)

	-- a private copy of the egg, floating in front of the camera
	local egg = PetFactory.BuildEgg(speciesKey)
	local info = egg:FindFirstChild("InfoGui", true)
	if info then info:Destroy() end
	egg.Parent = camera

	pcall(function()
		buySound:Play() -- cha-ching: this sequence IS the purchase moment
		-- "Panic Rise" runs 19s but the wobble is only ~2-5s: start near the
		-- end of the track so the rise peaks right at the crack.
		wobbleSound.TimePosition = math.max(0, WOBBLE_LENGTH - duration - 0.3)
		wobbleSound.PlaybackSpeed = 0.8
		wobbleSound:Play()
	end)

	-- WOBBLE: ~duration seconds, faster and wilder toward the end
	local start = time()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if myToken ~= showToken or not egg.Parent then
			connection:Disconnect()
			return
		end
		local elapsed = time() - start
		local k = math.clamp(elapsed / duration, 0, 1)
		if k >= 1 then
			connection:Disconnect()
			return
		end
		local freq = 8 + 12 * k -- the rising tension
		local amp = 0.15 + 0.3 * k -- up to the classic sin(t*18)/2.3 violence
		local wobble = math.sin(time() * freq) * amp
		local cf = camera.CFrame * CFrame.new(0, -0.2, -4.5)
			* CFrame.Angles(0, elapsed * 1.2, wobble)
		egg:PivotTo(cf)
		wobbleSound.PlaybackSpeed = 0.8 + 0.7 * k
	end)

	task.wait(duration)
	if myToken ~= showToken then
		if egg.Parent then egg:Destroy() end
		return
	end

	-- CRACK: flash, the egg swells and fades away
	pcall(function()
		wobbleSound:Stop()
		crackSound:Play()
		popSound:Play()
		if rarityOrder >= LEGENDARY_ORDER then
			roarSound:Play() -- Legendary, Mythic and Dragon reveals get a roar
		end
	end)
	flash.BackgroundTransparency = 0
	TweenService:Create(flash, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
	egg:ScaleTo(1.3)
	for _, part in ipairs(egg:GetDescendants()) do
		if part:IsA("BasePart") then
			TweenService:Create(part, TweenInfo.new(0.35), { Transparency = 1 }):Play()
		end
	end

	-- BANNER: bigger for rarer hatches
	local bannerText = string.upper(rarityName) .. "!"
	if mutation == "Rainbow" then
		bannerText = "🌈 RAINBOW!! 🌈"
	elseif mutation == "Golden" then
		bannerText = "⭐ GOLDEN " .. string.upper(rarityName) .. "! ⭐"
	end
	rarityLabel.Text = bannerText
	rarityLabel.TextColor3 = (mutation == "Rainbow") and Color3.fromRGB(255, 120, 220) or accent
	nameLabel.Text = displayName
	banner.Size = UDim2.fromOffset(400 + rarityOrder * 35, 110 + rarityOrder * 8)
	banner.Visible = true

	task.delay(0.5, function()
		if egg.Parent then egg:Destroy() end
	end)
	task.delay(2.4, function()
		if myToken == showToken then
			banner.Visible = false
		end
	end)
end

hatchEvent.OnClientEvent:Connect(function(...)
	local args = { ... }
	task.spawn(function()
		playHatch(table.unpack(args))
	end)
end)
