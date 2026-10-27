-- PetAnim (ModuleScript -> ReplicatedStorage)
-- Code animation for placed pets — no rigs, no animation assets. V2 pets are
-- part models, so "alive" comes from math, not keyframes:
--   - the whole model bobs and sways gently around its home CFrame
--   - the JOINTED parts (PetFactory's classic Welds: Head, Jaw, Tail,
--     TailTip, WingL/WingR) wiggle by rotating weld.C0 around the "BaseC0"
--     attribute PetFactory stored at build time — the pose can never drift
--   - dragons flap; tails wag with a phase lag toward the tip; jaws chomp
--   - Rainbow-mutated pets cycle their body palette through the rainbow
-- BaseManager owns the Heartbeat loop and calls ApplyIdle() once per frame
-- per placed pet with the pet's (possibly hover-bobbed) home CFrame.
-- Server-only in practice: it reads BaseService state through its caller.

local PetAnim = {}

-- per-pet cache of the parts worth touching (weak keys: dead pets vanish)
local cache = setmetatable({}, { __mode = "k" })

local function getInfo(pet)
	local info = cache[pet]
	if info then return info end
	info = { Joints = {}, Mutate = {}, Accents = {} }
	for _, desc in ipairs(pet:GetDescendants()) do
		if desc:IsA("Weld") and desc:GetAttribute("Joint") then
			table.insert(info.Joints, desc)
		elseif desc:IsA("BasePart") then
			if desc:GetAttribute("Mutate") then
				table.insert(info.Mutate, desc)
			end
			if desc:GetAttribute("GlowAccent") then
				table.insert(info.Accents, desc)
			end
		end
	end
	cache[pet] = info
	return info
end

-- the extra rotation for one joint kind at time t (phase = per-pet offset)
local function jointRotation(kind, t, phase)
	if kind == "Head" then
		-- slow look-around: mostly yaw, a little nod
		return CFrame.Angles(
			math.sin(t * 0.55 + phase) * 0.07,
			math.sin(t * 0.42 + phase * 2.0) * 0.16,
			0)
	elseif kind == "Jaw" then
		-- chomp: cubed sine = long rests, quick bites
		local bite = math.max(0, math.sin(t * 1.6 + phase))
		return CFrame.Angles(bite * bite * bite * 0.3, 0, 0)
	elseif kind == "Tail" then
		return CFrame.Angles(0, math.sin(t * 1.8 + phase) * 0.14, 0)
	elseif kind == "TailTip" then
		-- same wag, lagging behind the base segment
		return CFrame.Angles(0, math.sin(t * 1.8 + phase - 0.8) * 0.22, 0)
	elseif kind == "WingL" or kind == "WingR" then
		local flap = 0.12 + math.sin(t * 2.8 + phase) * 0.3
		return CFrame.Angles(0, 0, (kind == "WingL") and -flap or flap)
	end
	return CFrame.new()
end

local MUTATE_SAT = { Body = 0.55, Belly = 0.3, Dark = 0.7 }
local MUTATE_VAL = { Body = 1, Belly = 1, Dark = 0.75 }

-- ApplyIdle(pet, t, baseCFrame): pose one placed pet for this frame.
function PetAnim.ApplyIdle(pet, t, baseCFrame)
	local phase = pet:GetAttribute("HoverPhase") or 0

	-- whole-body life: a small bob + sway + a whisper of yaw drift
	local bobAmp = pet:GetAttribute("Hover") and 0.05 or 0.06
	local bob = math.sin(t * 2.1 + phase) * bobAmp
	local sway = math.sin(t * 1.25 + phase) * 0.045
	local yaw = math.sin(t * 0.7 + phase * 1.7) * 0.04
	pet:PivotTo(baseCFrame
		* CFrame.new(0, bob, 0)
		* CFrame.Angles(0, yaw, sway))

	local info = getInfo(pet)

	-- jointed parts
	for _, weld in ipairs(info.Joints) do
		local base = weld:GetAttribute("BaseC0")
		if base then
			weld.C0 = base * jointRotation(weld:GetAttribute("Joint"), t, phase)
		end
	end

	-- Rainbow mutation: cycle the palette (Golden is a static recolour,
	-- applied once by PetFactory, so it costs nothing per frame)
	if pet:GetAttribute("Mutation") == "Rainbow" then
		local hue = (t * 0.06 + phase) % 1
		for _, part in ipairs(info.Mutate) do
			local kind = part:GetAttribute("Mutate")
			part.Color = Color3.fromHSV(hue, MUTATE_SAT[kind] or 0.55, MUTATE_VAL[kind] or 1)
		end
		local accentHue = (hue + 0.5) % 1
		for _, part in ipairs(info.Accents) do
			part.Color = Color3.fromHSV(accentHue, 0.6, 1)
		end
	end
end

return PetAnim
