-- Core.lua – общие настройки, логи, звуки, обработка ошибок
if getgenv().AirHub then return end
getgenv().AirHub = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local VirtualInputManager = game:GetService("VirtualInputManager")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Lighting = game:GetService("Lighting")

-- Error handling
local ErrorText = Drawing.new("Text")
ErrorText.Visible = false
ErrorText.Size = 16
ErrorText.Color = Color3.fromRGB(255,0,0)
ErrorText.Position = Vector2.new(20,20)
local function ShowError(msg) ErrorText.Text = tostring(msg) ErrorText.Visible = true task.delay(3, function() ErrorText.Visible = false end) end
local function HandleError(err) ShowError("⚠️ " .. tostring(err)) end

-- Logs
local ActiveLogs = {}
local function AddLog(msg, color)
    local settings = getgenv().AirHub.Logging
    local text = Drawing.new("Text")
    text.Text = msg
    text.Size = settings.FontSize or 18
    text.Color = color or Color3.fromRGB(255,255,255)
    text.Center = true
    text.Outline = true
    text.Visible = true
    text.Transparency = 0
    local viewport = workspace.CurrentCamera.ViewportSize
    local startX, startY = viewport.X/2, viewport.Y/2 + 60
    for _, log in ipairs(ActiveLogs) do
        log.text.Position = Vector2.new(log.text.Position.X, log.text.Position.Y - 24)
    end
    text.Position = Vector2.new(startX, startY)
    table.insert(ActiveLogs, {text = text, created = tick(), duration = settings.Duration or 1})
end

-- Sounds
local Hitsound, Killsound
local function LoadSound(id, volume)
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://" .. tostring(id)
    sound.Volume = volume
    sound.Parent = Camera
    return sound
end
local function PlayHitsound()
    local s = getgenv().AirHub.Sound
    if not s.HitsoundEnabled then return end
    if not Hitsound or Hitsound.SoundId ~= "rbxassetid://"..s.HitsoundID then
        if Hitsound then Hitsound:Destroy() end
        Hitsound = LoadSound(s.HitsoundID, s.HitsoundVolume)
    else
        Hitsound.Volume = s.HitsoundVolume
    end
    Hitsound:Play()
end
local function PlayKillsound()
    local s = getgenv().AirHub.Sound
    if not s.KillsoundEnabled then return end
    if not Killsound or Killsound.SoundId ~= "rbxassetid://"..s.KillsoundID then
        if Killsound then Killsound:Destroy() end
        Killsound = LoadSound(s.KillsoundID, s.KillsoundVolume)
    else
        Killsound.Volume = s.KillsoundVolume
    end
    Killsound:Play()
end

-- Clean logs
RunService.Heartbeat:Connect(function()
    local now = tick()
    for i = #ActiveLogs, 1, -1 do
        local log = ActiveLogs[i]
        if now - log.created >= log.duration then
            log.text:Remove()
            table.remove(ActiveLogs, i)
        end
    end
end)

-- Global variables
Running, Typing, LastShotTime = false, false, 0
OriginalSensitivity, MenuVisible = nil, true

-- Default settings
getgenv().AirHub.Logging = {
    Enabled = true, ShowHit = true, ShowMiss = true, Duration = 1, FontSize = 18
}
getgenv().AirHub.Sound = {
    HitsoundEnabled = false, HitsoundID = 83717596220569, HitsoundVolume = 1,
    KillsoundEnabled = false, KillsoundID = 83717596220569, KillsoundVolume = 1
}
getgenv().AirHub.Character = {
    Transparent = false, Transparency = 0.5,
    HatESP = { Enabled = false, Color = Color3.fromRGB(255,223,0), Size = 1.5, Height = 2.5, Segments = 8 }
}

UserInputService.TextBoxFocused:Connect(function() Typing = true end)
UserInputService.TextBoxFocusReleased:Connect(function() Typing = false end)
