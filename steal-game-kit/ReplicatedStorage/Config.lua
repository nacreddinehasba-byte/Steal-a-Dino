-- Config (ModuleScript -> ReplicatedStorage)
-- ALL the numbers of the game live here: rarities, species, prices,
-- income, spawn chances, belt speed, lock times.
-- Change a value here and every script follows. Nothing else hardcodes prices.

local Config = {}

-- General tuning --------------------------------------------------------------
Config.MaxEggsOnBelt   = 9     -- eggs traveling on the belt at the same time
Config.SpawnInterval   = 3     -- seconds between egg spawns
Config.BeltSpeed       = 7     -- studs per second on the belt
Config.StarterCash     = 100   -- one-time session grant so a new player can buy a first egg
Config.SellBackRate    = 0.5   -- selling a pet gives back 50% of its price
Config.LockDuration    = 60    -- seconds a base stays locked (genre standard)
Config.LockCooldown    = 60    -- seconds before the lock can be used again
Config.StealWalkSpeed  = 10    -- walkspeed while carrying a stolen pet (default is 16)
Config.NormalWalkSpeed = 16

-- Rarity colors & glow ---------------------------------------------------------
-- Color  = main body color. Accent = the NEON glow color (eyes, stripes, edges).
-- LightBrightness / LightRange = the PointLight carried by pets of this tier
-- (0 = no light; lights start at Epic to keep performance sane).
Config.Rarities = {
	Common    = { Order = 1, Color = Color3.fromRGB(122, 140, 104), Accent = Color3.fromRGB(170, 255, 150), LightBrightness = 0,   LightRange = 0 },
	Rare      = { Order = 2, Color = Color3.fromRGB(64, 116, 205),  Accent = Color3.fromRGB(80, 220, 255),  LightBrightness = 0,   LightRange = 0 },
	Epic      = { Order = 3, Color = Color3.fromRGB(128, 62, 196),  Accent = Color3.fromRGB(232, 120, 255), LightBrightness = 1.2, LightRange = 11 },
	Legendary = { Order = 4, Color = Color3.fromRGB(226, 92, 32),   Accent = Color3.fromRGB(255, 176, 66),  LightBrightness = 1.6, LightRange = 13 },
	Mythic    = { Order = 5, Color = Color3.fromRGB(255, 190, 40),  Accent = Color3.fromRGB(255, 228, 130), LightBrightness = 3,   LightRange = 18 },
	Dragon    = { Order = 6, Color = Color3.fromRGB(40, 40, 48),    Accent = Color3.fromRGB(255, 120, 60),  LightBrightness = 2.5, LightRange = 16 },
}

-- Spawn chances per tier (must add up to 100) ----------------------------------
-- Dragon = 1% of all eggs. That rarity is the whole point of the tier.
Config.TierWeights = {
	Common = 52,
	Rare = 28,
	Epic = 12,
	Legendary = 5,
	Mythic = 2,
	Dragon = 1,
}

-- Species ----------------------------------------------------------------------
-- Weight = chance INSIDE the tier (only Dragon has several species).
-- Legs   = 2 (biped: Compy, Raptor, T-Rex, dragons) or 4 (Triceratops, Spino).
-- Extra flags switch on the special body parts in PetFactory.
Config.Species = {
	Compy = {
		DisplayName = "Compy", Rarity = "Common",
		Price = 50, Income = 1, Scale = 0.55, Legs = 2,
	},
	Velociraptor = {
		DisplayName = "Velociraptor", Rarity = "Rare",
		Price = 250, Income = 6, Scale = 0.8, Legs = 2, SickleClaws = true, SnOut = true,
	},
	Triceratops = {
		DisplayName = "Triceratops", Rarity = "Epic",
		Price = 1200, Income = 30, Scale = 1.15, Legs = 4, Frill = true, Horns = true,
	},
	Spinosaurus = {
		DisplayName = "Spinosaurus", Rarity = "Legendary",
		Price = 6000, Income = 160, Scale = 1.3, Legs = 4, Sail = true, SnOut = true,
	},
	GoldenTRex = {
		DisplayName = "Golden T-Rex", Rarity = "Mythic",
		Price = 30000, Income = 850, Scale = 1.5, Legs = 2, BigJaw = true, TinyArms = true,
	},
	-- DRAGONS: the supreme breed, above every dinosaur. Wings + hover.
	FireDragon = {
		DisplayName = "Fire Dragon", Rarity = "Dragon", Variant = "Fire", Weight = 45,
		Price = 200000, Income = 5500, Scale = 1.35, Legs = 2, Wings = true, Hover = true,
		Color = Color3.fromRGB(122, 34, 24), Accent = Color3.fromRGB(255, 122, 40),
	},
	IceDragon = {
		DisplayName = "Ice Dragon", Rarity = "Dragon", Variant = "Ice", Weight = 45,
		Price = 200000, Income = 5500, Scale = 1.35, Legs = 2, Wings = true, Hover = true,
		Color = Color3.fromRGB(196, 232, 246), Accent = Color3.fromRGB(120, 242, 255),
	},
	VoidDragon = {
		DisplayName = "Void Dragon", Rarity = "Dragon", Variant = "Void", Weight = 10,
		Price = 500000, Income = 15000, Scale = 1.5, Legs = 2, Wings = true, Hover = true,
		Color = Color3.fromRGB(20, 12, 34), Accent = Color3.fromRGB(178, 92, 255),
	},
}

-- Mutations (V2) -----------------------------------------------------------------
-- Rolled on every hatch, ON TOP of the species rarity. A mutation is pure
-- data: PetFactory recolours the pet and multiplies its IncomePerSec and
-- sell Price by Mult. Golden is uncommon; Rainbow is the server event.
Config.Mutations = {
	Golden  = { Chance = 8,   Mult = 3, Prefix = "Golden",
		Body = Color3.fromRGB(255, 201, 66), Belly = Color3.fromRGB(255, 230, 150),
		Dark = Color3.fromRGB(199, 152, 44) },
	Rainbow = { Chance = 1.5, Mult = 6, Prefix = "Rainbow" },
}

-- RollMutation() -> "Golden" | "Rainbow" | nil -----------------------------------
function Config.RollMutation()
	local roll = math.random() * 100
	if roll <= Config.Mutations.Rainbow.Chance then
		return "Rainbow"
	end
	if roll <= Config.Mutations.Rainbow.Chance + Config.Mutations.Golden.Chance then
		return "Golden"
	end
	return nil
end

-- Money formatting: $950 -> "$950", $1200 -> "$1.2K", $1500000 -> "$1.5M" --------
function Config.FormatMoney(amount)
	amount = math.floor(amount or 0)
	local function trim(x)
		local text = string.format("%.1f", x)
		return (text:gsub("%.0$", ""))
	end
	if amount >= 1e9 then
		return "$" .. trim(amount / 1e9) .. "B"
	elseif amount >= 1e6 then
		return "$" .. trim(amount / 1e6) .. "M"
	elseif amount >= 1e3 then
		return "$" .. trim(amount / 1e3) .. "K"
	end
	return "$" .. amount
end

-- Hatch cinematic length in seconds: rarer eggs wobble longer --------------------
function Config.HatchDuration(rarityName, mutation)
	local rar = Config.Rarities[rarityName]
	local order = rar and rar.Order or 1
	local duration = 1.7 + order * 0.45
	if mutation == "Rainbow" then
		duration = duration + 1.0
	elseif mutation == "Golden" then
		duration = duration + 0.5
	end
	return duration
end

-- The cheapest egg price (used for the starter-cash check) ----------------------
Config.CheapestPrice = math.huge
for _, sp in pairs(Config.Species) do
	if sp.Price < Config.CheapestPrice then
		Config.CheapestPrice = sp.Price
	end
end

-- RollSpecies() -> species key, using TierWeights then the in-tier Weight -------
function Config.RollSpecies()
	-- 1) roll the tier
	local total = 0
	for _, w in pairs(Config.TierWeights) do total = total + w end
	local roll = math.random() * total
	local acc = 0
	local tier = "Common"
	for name, w in pairs(Config.TierWeights) do
		acc = acc + w
		if roll <= acc then
			tier = name
			break
		end
	end
	-- 2) roll the species inside the tier
	local poolTotal = 0
	for _, sp in pairs(Config.Species) do
		if sp.Rarity == tier then
			poolTotal = poolTotal + (sp.Weight or 100)
		end
	end
	local roll2 = math.random() * poolTotal
	local acc2 = 0
	for key, sp in pairs(Config.Species) do
		if sp.Rarity == tier then
			acc2 = acc2 + (sp.Weight or 100)
			if roll2 <= acc2 then
				return key
			end
		end
	end
	return "Compy" -- fallback, should never happen
end

return Config
