-- BeltSpawner (Script -> ServerScriptService)
-- Eggs are born at BeltStart, ride the belt to BeltEnd, and despawn there.
-- Needs in Workspace: folder "Belt" with parts "BeltStart" and "BeltEnd",
-- and an (empty) folder "Collectibles" where eggs and pets live.
-- The PULSE: every egg's glow light breathes (brighter/dimmer, stronger for
-- dragon eggs) and the egg swells slightly — rare eggs read from far away.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local PetFactory = require(ReplicatedStorage:WaitForChild("PetFactory"))

local beltFolder = Workspace:WaitForChild("Belt")
local startPart = beltFolder:WaitForChild("BeltStart")
local endPart = beltFolder:WaitForChild("BeltEnd")
local collectibles = Workspace:WaitForChild("Collectibles")

local startPos = startPart.Position
local endPos = endPart.Position
local beltVector = endPos - startPos
local beltLength = beltVector.Magnitude
local beltDir = beltVector.Unit

local active = {} -- list of { Model = model, Dist = studs traveled, Accents = {parts}, Light = PointLight }

local function collectAccents(egg)
	local accents = {}
	for _, child in ipairs(egg:GetDescendants()) do
		if child:IsA("BasePart") and child.Name == "Accent" then
			table.insert(accents, child)
		end
	end
	return accents
end

local function spawnEgg()
	local speciesKey = Config.RollSpecies()
	local egg = PetFactory.BuildEgg(speciesKey)
	egg:SetAttribute("State", "Belt")
	egg.Parent = collectibles
	local shell = egg.PrimaryPart
	egg:PivotTo(CFrame.new(startPos + Vector3.new(0, egg:GetAttribute("EggHalfHeight"), 0)))
	table.insert(active, {
		Model = egg,
		Dist = 0,
		Accents = collectAccents(egg),
		Light = shell and shell:FindFirstChild("GlowLight") or nil,
	})
end

-- spawn loop ---------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(Config.SpawnInterval)
		local count = 0
		for _, entry in ipairs(active) do
			if entry.Model.Parent then count = count + 1 end
		end
		if count < Config.MaxEggsOnBelt then
			spawnEgg()
		end
	end
end)

-- movement + pulse loop ------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt)
	local t = tick()
	for i = #active, 1, -1 do
		local entry = active[i]
		local egg = entry.Model
		if not egg.Parent or egg:GetAttribute("State") ~= "Belt" then
			-- bought (destroyed by BuySystem) or otherwise gone: stop tracking
			table.remove(active, i)
		else
			entry.Dist = entry.Dist + Config.BeltSpeed * dt
			if entry.Dist >= beltLength then
				egg:Destroy()
				table.remove(active, i)
			else
				local phase = egg:GetAttribute("PulsePhase") or 0
				-- a gentle bob + rock while riding, so the eggs feel alive
				local bobY = math.sin(t * 2.3 + phase) * 0.1
				local rock = math.sin(t * 1.9 + phase) * 0.05
				local pos = startPos + beltDir * entry.Dist
					+ Vector3.new(0, egg:GetAttribute("EggHalfHeight") + bobY, 0)
				-- ride + a slow spin so the spots/cracks catch the light
				egg:PivotTo(CFrame.new(pos) * CFrame.Angles(0, entry.Dist * 0.12, rock))
				-- pulse the glow
				local base = egg:GetAttribute("PulseBase") or 0.9
				local amp = egg:GetAttribute("PulseAmp") or 0.5
				local wave = math.sin(t * 3.2 + phase)
				if entry.Light then
					entry.Light.Brightness = base + wave * amp
				end
				for _, accentPart in ipairs(entry.Accents) do
					accentPart.Transparency = 0.15 + 0.15 * wave
				end
				egg:ScaleTo(1 + 0.04 * wave)
			end
		end
	end
end)
