-- MusicClient (LocalScript -> StarterPlayerScripts)
-- The WORLD AUDIO layer (V2 audio pass). The moment a player joins, this
-- script starts two looping sounds that belong to the place itself, not to
-- any single event: a cheerful adventure score under everything, and a soft
-- jungle ambience (birds, leaves) underneath that. Both are created on the
-- client, so every player hears them from the start of their session and
-- they never touch the server. Pure atmosphere — the game works fine if
-- this script never runs.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer

-- sounds -------------------------------------------------------------------------
-- Free Creator Store audio; every id copied from the asset's own store page:
--   Background music : "Happy Adventure"          by Yannis Dumoutiers via @APMOfficial
--   Jungle ambience  : "Jungle Ambience 4 (SFX)"  by @ProSoundEffects
local function makeLoop(name, soundId, volume)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Volume = volume
	sound.Looped = true
	sound.Parent = SoundService
	return sound
end

local music = makeLoop("WorldMusic", "rbxassetid://9047876673", 0.3)
local ambience = makeLoop("WorldAmbience", "rbxassetid://9114891619", 0.15)

pcall(function()
	music:Play()
	ambience:Play()
end)
