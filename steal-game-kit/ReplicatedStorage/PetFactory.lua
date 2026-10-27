-- PetFactory (ModuleScript -> ReplicatedStorage)
-- Builds EVERYTHING out of plain parts in code: the eggs on the belt and the
-- pets they hatch into. No models, no meshes, no toolbox needed.
--
-- V2 MODELS: every pet is an ARTICULATED part model — body, belly, neck,
-- jointed head (it turns), jointed jaw (it chomps), 2- or 4-legs with feet,
-- a two-segment jointed tail (it wags), plus one signature feature per
-- species. Proportions are deliberately cute: a head almost as tall as the
-- body, big glowing eyes with a white highlight sparkle.
-- The Head/Jaw/Tail/TailTip/Wing joints are classic Welds whose C0 PetAnim
-- wiggles every frame; everything else is WeldConstraint-rigid.
--
-- THE GLOW SYSTEM (visual identity of the game):
--   - every pet has NEON accent parts in its rarity color (eyes, back
--     stripe, frill edge, sail edge, wing membranes, dragon horns...)
--   - pets of Epic tier and above carry a PointLight in that color
--   - eggs carry a small light and NEON spots; dragon eggs are dark shells
--     with NEON CRACKS. BeltSpawner pulses the egg lights (needs a
--     BloomEffect in Lighting!)
--
-- MUTATIONS (V2): BuildPet(speciesKey, "Golden" | "Rainbow" | nil).
-- Body-palette parts carry a "Mutate" attribute ("Body"/"Belly"/"Dark"):
-- Golden recolours them gold once; Rainbow's hue cycle is driven per-frame
-- by PetAnim. Accent/neon parts carry "GlowAccent" for the same cycle.
--
-- Body plan (local space, built around the Body part at the origin):
--   forward = +Z (head at +Z), up = +Y. The Body is anchored and is the
--   PrimaryPart, so systems move pets with Model:PivotTo().

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local PetFactory = {}

local BONE = Color3.fromRGB(242, 236, 220)
local WHITE = Color3.fromRGB(255, 255, 255)

-- small helpers -----------------------------------------------------------------

local function newPart(name, size, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- rigid attach: weld a part to any anchor part of the model (WeldConstraint)
local function attachTo(model, anchor, part, cframe)
	part.CFrame = cframe
	part.Anchored = false
	part.CanCollide = false
	part.Massless = true
	part.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = anchor
	weld.Part1 = part
	weld.Parent = anchor
	return part
end

-- attach to the model's primary part (the common case)
local function attach(model, primary, part, cframe)
	return attachTo(model, primary, part, cframe)
end

-- ANIMATED attach: a classic Weld whose C0 PetAnim rotates every frame.
-- The un-animated C0 is stored in a "BaseC0" attribute on the weld itself,
-- so the pose can never drift no matter who else moves the model.
local function joint(model, anchor, part, cframe, kind)
	part.CFrame = cframe
	part.Anchored = false
	part.CanCollide = false
	part.Massless = true
	part.Parent = model
	local weld = Instance.new("Weld")
	weld.Name = "Joint_" .. kind
	weld.Part0 = anchor
	weld.Part1 = part
	weld.C0 = anchor.CFrame:Inverse() * cframe
	weld.C1 = CFrame.new()
	weld:SetAttribute("Joint", kind)
	weld:SetAttribute("BaseC0", weld.C0)
	weld.Parent = anchor
	return part
end

local function neon(name, size, color)
	local part = newPart(name, size, color, Enum.Material.Neon)
	part:SetAttribute("GlowAccent", true)
	return part
end

-- mark a body-palette part for mutation recolouring ("Body"/"Belly"/"Dark")
local function mutate(part, kind)
	part:SetAttribute("Mutate", kind)
	return part
end

-- 3-line billboard: title / line2 / line3 (name, rarity, money)
local function addBillboard(adornee, offsetY, title, titleColor, line2, line2Color, line3, line3Color)
	local gui = Instance.new("BillboardGui")
	gui.Name = "InfoGui"
	gui.Size = UDim2.fromOffset(200, 88)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = true
	gui.Parent = adornee

	local function makeLabel(name, y, h, text, color)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.Size = UDim2.fromScale(1, h)
		label.Position = UDim2.fromScale(0, y)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextColor3 = color
		label.TextStrokeTransparency = 0.35
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Parent = gui
		return label
	end

	makeLabel("Title", 0, 0.42, title, titleColor)
	makeLabel("Info", 0.42, 0.29, line2, line2Color or WHITE)
	makeLabel("Info2", 0.71, 0.29, line3, line3Color or Color3.fromRGB(255, 235, 170))
	return gui
end

local function addLight(parentPart, color, brightness, range)
	local light = Instance.new("PointLight")
	light.Name = "GlowLight"
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Parent = parentPart
	return light
end

local function setCommonAttributes(model, speciesKey, sp)
	model:SetAttribute("Species", speciesKey)
	model:SetAttribute("DisplayName", sp.DisplayName)
	model:SetAttribute("Rarity", sp.Rarity)
	model:SetAttribute("Variant", sp.Variant or "")
	model:SetAttribute("Price", sp.Price)
	model:SetAttribute("IncomePerSec", sp.Income)
	model:SetAttribute("Mutation", "")
end

-- Apply a mutation to a freshly built pet: recolour + value multipliers +
-- sparkles. The DisplayName gains the prefix ("Rainbow Golden T-Rex").
local function applyMutation(model, body, mutation, sp, accent)
	local def = Config.Mutations[mutation]
	if not def then return end
	model:SetAttribute("Mutation", mutation)
	model:SetAttribute("IncomePerSec", sp.Income * def.Mult)
	model:SetAttribute("Price", sp.Price * def.Mult)
	if not (mutation == "Golden" and sp.DisplayName == "Golden T-Rex") then
		model:SetAttribute("DisplayName", def.Prefix .. " " .. sp.DisplayName)
	end

	if mutation == "Golden" then
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				local kind = part:GetAttribute("Mutate")
				if kind == "Body" then
					part.Color = def.Body
					part.Material = Enum.Material.Metal
				elseif kind == "Belly" then
					part.Color = def.Belly
				elseif kind == "Dark" then
					part.Color = def.Dark
				end
			end
		end
	end

	-- both mutations sparkle; Rainbow's colors are animated by PetAnim
	local sparkles = Instance.new("Sparkles")
	sparkles.Name = "MutationSparkles"
	sparkles.SparkleColor = (mutation == "Golden") and def.Body or accent
	sparkles.Parent = body
end

-- =================================================================================
-- EGGS
-- =================================================================================

-- preset directions for spots / cracks on the shell (unit-ish vectors)
local SPOT_DIRS = {
	Vector3.new(0.85, 0.35, 0.45), Vector3.new(-0.8, 0.6, -0.3),
	Vector3.new(0.3, 0.9, -0.75), Vector3.new(-0.45, -0.2, 0.85),
	Vector3.new(0.15, -0.75, -0.8), Vector3.new(-0.9, -0.45, 0.2),
}

local CRACK_ANGLES = {
	Vector3.new(15, 20, 30), Vector3.new(-25, 110, -15),
	Vector3.new(40, 200, 10), Vector3.new(-10, 300, 45),
}

function PetFactory.BuildEgg(speciesKey)
	local sp = Config.Species[speciesKey]
	local rar = Config.Rarities[sp.Rarity]
	local accent = sp.Accent or rar.Accent
	local isDragon = sp.Rarity == "Dragon"

	local model = Instance.new("Model")
	model.Name = sp.DisplayName .. " Egg"

	-- shell: a ball stretched clearly taller than wide = an egg silhouette
	local shell = Instance.new("Part")
	shell.Name = "Shell"
	shell.Shape = Enum.PartType.Ball
	shell.Size = isDragon and Vector3.new(2.7, 3.9, 2.7) or Vector3.new(2.2, 3.1, 2.2)
	-- dragon eggs are DARK shells; normal eggs wear their rarity color
	shell.Color = isDragon and Color3.fromRGB(24, 20, 34) or (sp.Color or rar.Color)
	shell.Material = Enum.Material.SmoothPlastic
	shell.TopSurface = Enum.SurfaceType.Smooth
	shell.BottomSurface = Enum.SurfaceType.Smooth
	shell.Anchored = true
	shell.CanCollide = false
	shell.Parent = model
	model.PrimaryPart = shell

	local radii = shell.Size / 2

	if isDragon then
		-- GLOWING CRACKS: thin neon shards stuck on the dark shell
		for i, dir in ipairs(SPOT_DIRS) do
			if i <= 4 then
				local crack = neon("Accent", Vector3.new(0.16, 1.5, 0.36), accent)
				local pos = dir * radii * 0.92
				local a = CRACK_ANGLES[i]
				attach(model, shell, crack, CFrame.new(pos) * CFrame.Angles(math.rad(a.X), math.rad(a.Y), math.rad(a.Z)))
			end
		end
	else
		-- spots: Epic+ spots are neon, Common/Rare spots are a lighter shell tint
		for _, dir in ipairs(SPOT_DIRS) do
			local spot
			if rar.Order >= 3 then
				spot = neon("Accent", Vector3.new(0.55, 0.55, 0.55), accent)
			else
				spot = newPart("Spot", Vector3.new(0.55, 0.55, 0.55), accent:Lerp(WHITE, 0.35))
				spot.Name = "Accent"
			end
			attach(model, shell, spot, CFrame.new(dir * radii * 0.94))
		end
	end

	-- every egg glows a little; BeltSpawner pulses this light
	addLight(shell, accent, isDragon and 1.7 or 0.9, isDragon and 11 or 8)

	addBillboard(shell, radii.Y + 1.6,
		sp.DisplayName .. " Egg",
		accent,
		sp.Rarity,
		accent,
		Config.FormatMoney(sp.Price) .. "  ·  " .. Config.FormatMoney(sp.Income) .. "/s")

	setCommonAttributes(model, speciesKey, sp)
	model:SetAttribute("Kind", "Egg")
	model:SetAttribute("State", "New") -- BeltSpawner sets "Belt"
	model:SetAttribute("EggHalfHeight", radii.Y)
	model:SetAttribute("PulseBase", isDragon and 1.7 or 0.9)
	model:SetAttribute("PulseAmp", isDragon and 1.1 or 0.5)
	model:SetAttribute("PulsePhase", math.random() * math.pi * 2)
	return model
end

-- =================================================================================
-- PETS (dinosaurs + dragons) — V2 articulated builds
-- =================================================================================

function PetFactory.BuildPet(speciesKey, mutation)
	local sp = Config.Species[speciesKey]
	local rar = Config.Rarities[sp.Rarity]
	local bodyColor = sp.Color or rar.Color
	local accent = sp.Accent or rar.Accent
	local darkColor = bodyColor:Lerp(Color3.fromRGB(0, 0, 0), 0.25)
	local bellyColor = bodyColor:Lerp(WHITE, 0.38)
	local bodyMaterial = (speciesKey == "GoldenTRex") and Enum.Material.Metal or Enum.Material.SmoothPlastic
	local s = sp.Scale
	local isDragon = sp.Rarity == "Dragon"
	local isQuad = sp.Legs == 4

	local model = Instance.new("Model")
	model.Name = sp.DisplayName

	-- BODY (primary part) ---------------------------------------------------------
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(2.3, 1.85, 3.3) * s
	body.Color = bodyColor
	body.Material = bodyMaterial
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Anchored = true
	body.CanCollide = false
	body.Parent = model
	model.PrimaryPart = body
	mutate(body, "Body")

	local bodyHalfY = body.Size.Y / 2

	-- BELLY: a soft lighter underside (part of the cute read) ----------------------
	local belly = mutate(newPart("Belly", Vector3.new(1.85, 1.25, 2.7) * s, bellyColor), "Belly")
	attach(model, body, belly, CFrame.new(0, -0.5 * s, 0.3 * s))

	-- LEGS + FEET -------------------------------------------------------------------
	local legLen = (sp.BigJaw and 1.3 or 1.05) * s
	local legY = -(bodyHalfY + legLen / 2 - 0.25 * s)
	local footBottomY = legY - legLen / 2 -- == -(bodyHalfY + legLen - 0.25s)
	if isQuad then
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local leg = mutate(newPart("Leg", Vector3.new(0.52 * s, legLen, 0.52 * s), darkColor), "Dark")
				attach(model, body, leg, CFrame.new(sx * 0.8 * s, legY, sz * 1.05 * s))
				local foot = mutate(newPart("Foot", Vector3.new(0.58 * s, 0.22 * s, 0.85 * s), darkColor), "Dark")
				attach(model, body, foot, CFrame.new(sx * 0.8 * s, footBottomY + 0.11 * s, sz * 1.05 * s + 0.08 * s))
			end
		end
	else
		for _, sx in ipairs({ -1, 1 }) do
			local leg = mutate(newPart("Leg", Vector3.new(0.6 * s, legLen, 0.6 * s), darkColor), "Dark")
			attach(model, body, leg, CFrame.new(sx * 0.58 * s, legY, -0.1 * s))
			local foot = mutate(newPart("Foot", Vector3.new(0.62 * s, 0.24 * s, 1.05 * s), darkColor), "Dark")
			attach(model, body, foot, CFrame.new(sx * 0.58 * s, footBottomY + 0.12 * s, 0.18 * s))
			-- toe claws on the fighters
			if sp.SickleClaws or sp.BigJaw then
				for _, tx in ipairs({ -0.18, 0.18 }) do
					local toe = newPart("ToeClaw", Vector3.new(0.14 * s, 0.18 * s, 0.3 * s), BONE)
					attach(model, body, toe, CFrame.new(sx * 0.58 * s + tx * s, footBottomY + 0.1 * s, 0.72 * s))
				end
			end
			if sp.SickleClaws then
				-- the raptor's famous curved claw, raised off the ground
				local claw = Instance.new("WedgePart")
				claw.Name = "Claw"
				claw.Size = Vector3.new(0.16 * s, 0.45 * s, 0.16 * s)
				claw.Color = BONE
				claw.Material = Enum.Material.SmoothPlastic
				attach(model, body, claw, CFrame.new(sx * 0.58 * s, footBottomY + 0.32 * s, 0.5 * s)
					* CFrame.Angles(math.rad(-30), 0, 0))
			end
		end
		-- ARMS: raptors get clawed arms, the T-Rex gets its ridiculous tiny ones
		if speciesKey == "Velociraptor" then
			for _, sx in ipairs({ -1, 1 }) do
				local arm = mutate(newPart("Arm", Vector3.new(0.22 * s, 0.6 * s, 0.22 * s), darkColor), "Dark")
				attach(model, body, arm, CFrame.new(sx * 1.0 * s, -0.15 * s, 1.3 * s)
					* CFrame.Angles(math.rad(25), 0, 0))
				local claw = newPart("ArmClaw", Vector3.new(0.1 * s, 0.24 * s, 0.1 * s), BONE)
				attach(model, body, claw, CFrame.new(sx * 1.05 * s, -0.48 * s, 1.48 * s)
					* CFrame.Angles(math.rad(40), 0, 0))
			end
		elseif sp.TinyArms then
			for _, sx in ipairs({ -1, 1 }) do
				local arm = mutate(newPart("TinyArm", Vector3.new(0.18 * s, 0.45 * s, 0.18 * s), darkColor), "Dark")
				attach(model, body, arm, CFrame.new(sx * 0.85 * s, -0.3 * s, 1.45 * s)
					* CFrame.Angles(math.rad(25), 0, 0))
			end
		end
	end

	-- NECK ----------------------------------------------------------------------------
	local headPos
	if isDragon then
		local neck = mutate(newPart("Neck", Vector3.new(0.85 * s, 1.8 * s, 0.85 * s), bodyColor), "Body")
		attach(model, body, neck, CFrame.new(0, 1.2 * s, 1.8 * s) * CFrame.Angles(math.rad(28), 0, 0))
		headPos = Vector3.new(0, 2.15 * s, 2.55 * s)
	elseif isQuad then
		local neck = mutate(newPart("Neck", Vector3.new(1.15 * s, 1.15 * s, 1.7 * s), bodyColor), "Body")
		neck.Shape = Enum.PartType.Ball
		attach(model, body, neck, CFrame.new(0, 0.5 * s, 1.85 * s) * CFrame.Angles(math.rad(-15), 0, 0))
		headPos = Vector3.new(0, 0.95 * s, 2.7 * s)
	else
		local neck = mutate(newPart("Neck", Vector3.new(1.0 * s, 1.1 * s, 1.3 * s), bodyColor), "Body")
		neck.Shape = Enum.PartType.Ball
		attach(model, body, neck, CFrame.new(0, 0.8 * s, 1.7 * s))
		headPos = Vector3.new(0, 1.5 * s, 2.15 * s)
	end

	-- HEAD (JOINTED: PetAnim turns it) ---------------------------------------------------
	local headScale = sp.BigJaw and 1.2 or (speciesKey == "Compy" and 1.15 or 1)
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.95, 1.65, sp.SnOut and 2.3 or 2.0) * s * headScale
	head.Color = bodyColor
	head.Material = bodyMaterial
	head.TopSurface = Enum.SurfaceType.Smooth
	head.BottomSurface = Enum.SurfaceType.Smooth
	mutate(head, "Body")
	joint(model, body, head, CFrame.new(headPos), "Head")

	-- snout block for the long-faced species (raptor, spino), rides the head
	if sp.SnOut then
		local snout = mutate(newPart("Snout", Vector3.new(1.1, 0.62, 1.15) * s * headScale, bodyColor), "Body")
		attachTo(model, head, snout, CFrame.new(headPos + Vector3.new(0, -0.18 * s, 1.0 * s * headScale)))
	end

	-- JAW (JOINTED to the head: PetAnim chomps it) ----------------------------------------
	local jawSize = sp.BigJaw and (Vector3.new(1.25, 0.6, 1.5) * headScale)
		or (sp.SnOut and Vector3.new(1.0, 0.45, 1.85) or Vector3.new(1.15, 0.5, 1.3))
	local jaw = mutate(newPart("Jaw", jawSize * s, darkColor), "Dark")
	joint(model, head, jaw, CFrame.new(headPos + Vector3.new(0, -0.62 * s * headScale, (sp.SnOut and 0.75 or 0.55) * s)), "Jaw")

	-- teeth: upper row hangs from the head, T-Rex and dragons only
	if sp.BigJaw or isDragon then
		for i = -1, 1 do
			local tooth = Instance.new("WedgePart")
			tooth.Name = "Tooth"
			tooth.Size = Vector3.new(0.17 * s, 0.34 * s, 0.17 * s)
			tooth.Color = BONE
			tooth.Material = Enum.Material.SmoothPlastic
			attachTo(model, head, tooth, CFrame.new(headPos + Vector3.new(i * 0.36 * s, -0.52 * s * headScale, 0.98 * s * headScale))
				* CFrame.Angles(math.rad(180), 0, 0))
		end
	end

	-- EYES: big, neon, with a white highlight sparkle (the cute read) ----------------------
	local eyeScale = (speciesKey == "Compy") and 1.6 or 1
	for _, sx in ipairs({ -1, 1 }) do
		local eyePos = headPos + Vector3.new(sx * 0.7 * s * headScale, 0.32 * s, 0.72 * s * headScale)
		local eye = neon("Eye", Vector3.new(0.42, 0.42, 0.42) * s * eyeScale, accent)
		eye.Shape = Enum.PartType.Ball
		attachTo(model, head, eye, CFrame.new(eyePos))
		local shine = neon("EyeShine", Vector3.new(0.14, 0.14, 0.14) * s * eyeScale, WHITE)
		shine.Shape = Enum.PartType.Ball
		attachTo(model, head, shine, CFrame.new(eyePos + Vector3.new(sx * 0.08 * s, 0.12 * s, 0.14 * s)))
	end

	-- T-REX: heavy brow ridges over the eyes ------------------------------------------------
	if sp.BigJaw then
		for _, sx in ipairs({ -1, 1 }) do
			local brow = mutate(newPart("Brow", Vector3.new(0.55 * s, 0.18 * s, 0.3 * s), darkColor), "Dark")
			attachTo(model, head, brow, CFrame.new(headPos + Vector3.new(sx * 0.55 * s, 0.62 * s, 0.6 * s))
				* CFrame.Angles(0, 0, sx * math.rad(-10)))
		end
	end

	-- COMPY: a tiny neon crest tuft (its signature) --------------------------------------------
	if speciesKey == "Compy" then
		for i = -1, 1 do
			local tuft = neon("CrestTuft", Vector3.new(0.1 * s, 0.38 * s, 0.1 * s), accent)
			attachTo(model, head, tuft, CFrame.new(headPos + Vector3.new(i * 0.16 * s, 0.85 * s, -0.1 * s))
				* CFrame.Angles(math.rad(-12), 0, i * math.rad(14)))
		end
	end

	-- SPINOSAURUS: the little head crest -------------------------------------------------------
	if sp.Sail then
		local crest = neon("HeadCrest", Vector3.new(0.16 * s, 0.55 * s, 0.5 * s), accent)
		attachTo(model, head, crest, CFrame.new(headPos + Vector3.new(0, 0.78 * s, 0.35 * s))
			* CFrame.Angles(math.rad(-20), 0, 0))
	end

	-- TRICERATOPS: frill + neon edge + three horns + beak, all riding the head -------------------
	if sp.Frill then
		local frill = mutate(newPart("Frill", Vector3.new(0.3 * s, 3.6 * s, 3.6 * s), bodyColor), "Body")
		frill.Shape = Enum.PartType.Cylinder
		attachTo(model, head, frill, CFrame.new(headPos + Vector3.new(0, 0.3 * s, -0.8 * s)) * CFrame.Angles(0, math.rad(90), 0))
		local ring = neon("FrillEdge", Vector3.new(0.18 * s, 3.9 * s, 3.9 * s), accent)
		ring.Shape = Enum.PartType.Cylinder
		attachTo(model, head, ring, CFrame.new(headPos + Vector3.new(0, 0.3 * s, -0.97 * s)) * CFrame.Angles(0, math.rad(90), 0))
		local beak = mutate(newPart("Beak", Vector3.new(0.75 * s, 0.5 * s, 0.7 * s), darkColor), "Dark")
		beak.Shape = Enum.PartType.Ball
		attachTo(model, head, beak, CFrame.new(headPos + Vector3.new(0, -0.32 * s, 1.0 * s)))
	end
	if sp.Horns then
		for _, sx in ipairs({ -1, 1 }) do
			local horn = Instance.new("WedgePart")
			horn.Name = "Horn"
			horn.Size = Vector3.new(0.3 * s, 1.2 * s, 0.3 * s)
			horn.Color = BONE
			horn.Material = Enum.Material.SmoothPlastic
			attachTo(model, head, horn, CFrame.new(headPos + Vector3.new(sx * 0.52 * s, 0.6 * s, 0.75 * s))
				* CFrame.Angles(math.rad(65), 0, 0))
		end
		local noseHorn = Instance.new("WedgePart")
		noseHorn.Name = "Horn"
		noseHorn.Size = Vector3.new(0.26 * s, 0.75 * s, 0.26 * s)
		noseHorn.Color = BONE
		noseHorn.Material = Enum.Material.SmoothPlastic
		attachTo(model, head, noseHorn, CFrame.new(headPos + Vector3.new(0, 0.1 * s, 1.05 * s))
			* CFrame.Angles(math.rad(65), 0, 0))
	end

	-- TAIL: two JOINTED tapering wedges (PetAnim wags them with a phase lag) ---------------------
	local tail1 = mutate(Instance.new("WedgePart"), "Body")
	tail1.Name = "Tail"
	tail1.Size = Vector3.new(0.8 * s, 0.9 * s, 2.4 * s)
	tail1.Color = bodyColor
	tail1.Material = bodyMaterial
	joint(model, body, tail1, CFrame.new(0, 0.02 * s, -2.55 * s) * CFrame.Angles(math.rad(180), math.rad(180), 0), "Tail")
	local tail2 = mutate(Instance.new("WedgePart"), "Dark")
	tail2.Name = "TailTip"
	tail2.Size = Vector3.new(0.42 * s, 0.48 * s, 2.1 * s)
	tail2.Color = darkColor
	tail2.Material = bodyMaterial
	joint(model, body, tail2, CFrame.new(0, -0.14 * s, -4.35 * s) * CFrame.Angles(math.rad(180), math.rad(180), 0), "TailTip")

	-- SPINOSAURUS: paddle fin on the tail tip ------------------------------------------------------
	if sp.Sail then
		local fin = mutate(newPart("TailFin", Vector3.new(0.15 * s, 0.8 * s, 1.6 * s), darkColor), "Dark")
		attachTo(model, tail2, fin, CFrame.new(0, 0.5 * s, -4.35 * s))
	end

	-- NEON BACK STRIPE on every pet; cute back spots on the two small species -------------------------
	local stripe = neon("BackStripe", Vector3.new(0.45 * s, 0.16 * s, 2.5 * s), accent)
	attach(model, body, stripe, CFrame.new(0, bodyHalfY + 0.03 * s, -0.3 * s))
	if speciesKey == "Compy" or speciesKey == "Velociraptor" then
		for _, bz in ipairs({ 0.6, -0.3, -1.1 }) do
			local spot = neon("BackSpot", Vector3.new(0.3, 0.3, 0.3) * s, accent)
			spot.Shape = Enum.PartType.Ball
			attach(model, body, spot, CFrame.new(0, bodyHalfY + 0.08 * s, bz * s))
		end
	end

	-- SPINOSAURUS: the great sail, with a neon top edge ------------------------------------------------
	if sp.Sail then
		local sail = mutate(newPart("Sail", Vector3.new(0.35 * s, 2.2 * s, 2.8 * s), darkColor), "Dark")
		sail.Shape = Enum.PartType.Ball
		attach(model, body, sail, CFrame.new(0, bodyHalfY + 0.8 * s, -0.2 * s))
		local edge = neon("SailEdge", Vector3.new(0.15 * s, 0.24 * s, 2.5 * s), accent)
		attach(model, body, edge, CFrame.new(0, bodyHalfY + 1.85 * s, -0.2 * s))
	end

	-- DRAGONS: neon horns, back spikes, tail spikes + spade, JOINTED wings --------------------------------
	if isDragon then
		for _, sx in ipairs({ -1, 1 }) do
			local horn = Instance.new("WedgePart")
			horn.Name = "Horn"
			horn.Size = Vector3.new(0.24 * s, 1.0 * s, 0.24 * s)
			horn.Color = accent
			horn.Material = Enum.Material.Neon
			horn:SetAttribute("GlowAccent", true)
			attachTo(model, head, horn, CFrame.new(headPos + Vector3.new(sx * 0.42 * s, 0.62 * s, -0.3 * s))
				* CFrame.Angles(math.rad(-35), 0, sx * math.rad(-12)))
			-- wing arm: JOINTED so PetAnim can flap it
			local side = (sx < 0) and "WingL" or "WingR"
			local wingArm = mutate(newPart("WingArm", Vector3.new(2.9 * s, 0.16 * s, 0.5 * s), darkColor), "Dark")
			joint(model, body, wingArm, CFrame.new(sx * 2.0 * s, 1.35 * s, -0.2 * s)
				* CFrame.Angles(0, 0, sx * math.rad(-24)), side)
			-- a finger bone riding the arm
			local finger = mutate(newPart("WingFinger", Vector3.new(1.8 * s, 0.1 * s, 0.28 * s), darkColor), "Dark")
			attachTo(model, wingArm, finger, CFrame.new(sx * 2.65 * s, 1.02 * s, -0.55 * s)
				* CFrame.Angles(0, 0, sx * math.rad(-38)))
			-- wing membrane: translucent NEON, rides the arm so it follows the flap
			local membrane = neon("WingMembrane", Vector3.new(2.3 * s, 0.07 * s, 1.7 * s), accent)
			membrane.Transparency = 0.3
			attachTo(model, wingArm, membrane, CFrame.new(sx * 1.85 * s, 0.85 * s, -0.35 * s)
				* CFrame.Angles(0, 0, sx * math.rad(-16)))
		end
		-- glowing spikes down the back
		for i = 0, 2 do
			local spikeW = Instance.new("WedgePart")
			spikeW.Name = "BackSpike"
			spikeW.Size = Vector3.new(0.28 * s, 0.65 * s, 0.28 * s)
			spikeW.Color = accent
			spikeW.Material = Enum.Material.Neon
			spikeW:SetAttribute("GlowAccent", true)
			attach(model, body, spikeW, CFrame.new(0, bodyHalfY + 0.32 * s, (0.8 - i * 0.85) * s))
		end
		-- tail spikes + a spade tip, riding the tail segments
		local tspike = Instance.new("WedgePart")
		tspike.Name = "TailSpike"
		tspike.Size = Vector3.new(0.24 * s, 0.5 * s, 0.24 * s)
		tspike.Color = accent
		tspike.Material = Enum.Material.Neon
		tspike:SetAttribute("GlowAccent", true)
		attachTo(model, tail1, tspike, CFrame.new(0, 0.6 * s, -2.9 * s))
		local spade = neon("TailSpade", Vector3.new(0.7 * s, 0.9 * s, 0.25 * s), accent)
		attachTo(model, tail2, spade, CFrame.new(0, -0.2 * s, -5.5 * s))
	end

	-- LIGHT: Epic and above (dragons included) -------------------------------------------
	if rar.LightBrightness > 0 then
		addLight(body, accent, rar.LightBrightness, rar.LightRange)
	end

	-- HATCH BURST emitter: BuySystem fires this when the cinematic hatch reveals
	local burst = Instance.new("ParticleEmitter")
	burst.Name = "HatchBurst"
	burst.Color = ColorSequence.new(accent)
	burst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	burst.Lifetime = NumberRange.new(0.5, 0.9)
	burst.Speed = NumberRange.new(7, 12)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.LightEmission = 1
	burst.Rate = 0
	burst.Enabled = false
	burst.Parent = body

	-- ATTRIBUTES ---------------------------------------------------------------------------
	setCommonAttributes(model, speciesKey, sp)
	if mutation and Config.Mutations[mutation] then
		applyMutation(model, body, mutation, sp, accent)
	end
	model:SetAttribute("Kind", "Pet")
	model:SetAttribute("State", "New") -- BaseService sets "Placed"
	model:SetAttribute("Hover", sp.Hover == true)
	-- distance from the Body's center down to the ground (dragons hover above it)
	local groundOffset = bodyHalfY + legLen - 0.25 * s
	if sp.Hover then
		groundOffset = groundOffset + 2.3
	end
	model:SetAttribute("GroundOffset", groundOffset)
	model:SetAttribute("HoverPhase", math.random() * math.pi * 2)

	-- BILLBOARD: name (with mutation prefix) / rarity / income per second --------------------
	addBillboard(body, bodyHalfY + (isDragon and 3.4 or 2.6) * s,
		model:GetAttribute("DisplayName"),
		accent,
		sp.Rarity,
		accent,
		Config.FormatMoney(model:GetAttribute("IncomePerSec")) .. "/s",
		Color3.fromRGB(170, 255, 170))
	return model
end

return PetFactory
