-- NotifyClient (LocalScript -> StarterPlayerScripts)
-- Shows the messages the server sends through the "NotifyEvent" RemoteEvent
-- (steal warnings, "not enough cash", lock info...) as a big label at the
-- top of the screen for a few seconds. Nothing else to configure.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local event = ReplicatedStorage:WaitForChild("NotifyEvent")

local gui = Instance.new("ScreenGui")
gui.Name = "NotifyGui"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.Name = "Message"
label.Size = UDim2.fromOffset(720, 56)
label.Position = UDim2.new(0.5, -360, 0, 18)
label.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
label.BackgroundTransparency = 0.25
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.TextStrokeTransparency = 0.5
label.Font = Enum.Font.GothamBold
label.TextScaled = true
label.Visible = false
label.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = label

local hideToken = 0
event.OnClientEvent:Connect(function(text)
	hideToken = hideToken + 1
	local myToken = hideToken
	label.Text = text
	label.Visible = true
	task.delay(3.4, function()
		if hideToken == myToken then
			label.Visible = false
		end
	end)
end)
