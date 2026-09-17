if getgenv().AirHub and getgenv().AirHub._CoreLoaded then
    warn("[AirHub] Core already loaded")
    return
end

--// ---------------------------------------------------------------------------
--// Global state
--// ---------------------------------------------------------------------------
getgenv().AirHub = getgenv().AirHub or {}
local H = getgenv().AirHub
H._CoreLoaded = true
H.ShuttingDown = false
H.DELAY_SHOT_TIMEOUT = 0.8

--// ---------------------------------------------------------------------------
--// Error display
--// ---------------------------------------------------------------------------
local ErrorText = Drawing.new("Text")
ErrorText.Visible = false
ErrorText.Size = 16
ErrorText.Color = Color3.fromRGB(255, 0, 0)
ErrorText.Position = Vector2.new(20, 20)
H.ErrorText = ErrorText

local ErrorToken = 0
local function ShowError(msg)
    ErrorToken = ErrorToken + 1
    local myToken = ErrorToken
    ErrorText.Text = tostring(msg)
    ErrorText.Visible = true
    task.delay(3, function()
        if ErrorToken == myToken then ErrorText.Visible = false end
    end)
end

local function HandleError(err)
    ShowError("⚠️ " .. tostring(err))
    warn("[AirHub] " .. tostring(err))
end

--// ---------------------------------------------------------------------------
--// Safe enum helpers
--// ---------------------------------------------------------------------------
local function SafeKeyCode(name)
    if type(name) ~= "string" then return nil end
    local ok, kc = pcall(function() return Enum.KeyCode[name] end)
    if ok and kc then return kc end
    return nil
end

local function SafeUserInputType(name)
    if type(name) ~= "string" then return nil end
    local ok, uit = pcall(function() return Enum.UserInputType[name] end)
    if ok and uit then return uit end
    return nil
end

local function SanitizeColor(c)
    if typeof(c) == "Color3" then return c end
    return Color3.fromRGB(255, 255, 255)
end

local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = DeepCopy(v) end
    return out
end

local RAY_FILTER
pcall(function() RAY_FILTER = Enum.RaycastFilterType.Exclude end)
if not RAY_FILTER then RAY_FILTER = Enum.RaycastFilterType.Blacklist end

--// ---------------------------------------------------------------------------
--// Connection tracking
--// ---------------------------------------------------------------------------
local TrackedConnections = {}
local function Track(c)
    if c then table.insert(TrackedConnections, c) end
    return c
end
local function UntrackAll()
    for _, c in ipairs(TrackedConnections) do
        pcall(function() c:Disconnect() end)
    end
    TrackedConnections = {}
end

--// ---------------------------------------------------------------------------
--// Services
--// ---------------------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

--// ---------------------------------------------------------------------------
--// Active logs (Drawing text stack)
--// ---------------------------------------------------------------------------
H.ActiveLogs = H.ActiveLogs or {}
local MAX_LOGS = 8

local function AddLog(msg, color)
    local settings = H.Logging or { FontSize = 18, Duration = 1 }
    local text = Drawing.new("Text")
    text.Text = msg
    text.Size = settings.FontSize or 18
    text.Color = color or Color3.fromRGB(255, 255, 255)
    text.Center = true
    text.Outline = true
    text.Visible = true
    text.Transparency = 0
    local viewport = workspace.CurrentCamera.ViewportSize
    local startX, startY = viewport.X / 2, viewport.Y / 2 + 60
    for _, log in ipairs(H.ActiveLogs) do
        log.text.Position = Vector2.new(log.text.Position.X, log.text.Position.Y - 24)
    end
    text.Position = Vector2.new(startX, startY)
    table.insert(H.ActiveLogs, { text = text, created = tick(), duration = settings.Duration or 1 })
    while #H.ActiveLogs > MAX_LOGS do
        local oldest = table.remove(H.ActiveLogs, 1)
        if oldest and oldest.text then pcall(function() oldest.text:Remove() end) end
    end
end

Track(RunService.Heartbeat:Connect(function()
    local now = tick()
    for i = #H.ActiveLogs, 1, -1 do
        local log = H.ActiveLogs[i]
        if now - log.created >= log.duration then
            pcall(function() log.text:Remove() end)
            table.remove(H.ActiveLogs, i)
        end
    end
end))

--// ---------------------------------------------------------------------------
--// Sounds
--// ---------------------------------------------------------------------------
H.Sounds = H.Sounds or { Hitsound = nil, Killsound = nil }

local function LoadSound(id, volume)
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://" .. tostring(id)
    sound.Volume = volume
    sound.Parent = workspace.CurrentCamera
    return sound
end

local function PlayHitsound()
    local s = H.Sound
    if not s or not s.HitsoundEnabled then return end
    if not H.Sounds.Hitsound or H.Sounds.Hitsound.SoundId ~= "rbxassetid://" .. s.HitsoundID then
        if H.Sounds.Hitsound then H.Sounds.Hitsound:Destroy() end
        H.Sounds.Hitsound = LoadSound(s.HitsoundID, s.HitsoundVolume)
    else
        H.Sounds.Hitsound.Volume = s.HitsoundVolume
    end
    H.Sounds.Hitsound:Play()
end

local function PlayKillsound()
    local s = H.Sound
    if not s or not s.KillsoundEnabled then return end
    if not H.Sounds.Killsound or H.Sounds.Killsound.SoundId ~= "rbxassetid://" .. s.KillsoundID then
        if H.Sounds.Killsound then H.Sounds.Killsound:Destroy() end
        H.Sounds.Killsound = LoadSound(s.KillsoundID, s.KillsoundVolume)
    else
        H.Sounds.Killsound.Volume = s.KillsoundVolume
    end
    H.Sounds.Killsound:Play()
end

--// ---------------------------------------------------------------------------
--// Default settings
--// ---------------------------------------------------------------------------
H.Logging = H.Logging or { Enabled = true, ShowHit = true, ShowMiss = true, Duration = 1, FontSize = 18 }
H.Sound = H.Sound or {
    HitsoundEnabled = false, HitsoundID = 83717596220569, HitsoundVolume = 1,
    KillsoundEnabled = false, KillsoundID = 83717596220569, KillsoundVolume = 1,
}

--// ---------------------------------------------------------------------------
--// Config system
--// ---------------------------------------------------------------------------
local CONFIG_FOLDER = "AirHub/Configs"
local IN_MEMORY_CONFIGS = {}

local function Config_HasFS()
    return type(writefile) == "function" and type(readfile) == "function"
end

local function Config_SanitizeName(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("[\\/%.%*%?%:%%\"%<%>%|]", "")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or name == "." or name == ".." then return nil end
    if #name > 64 then name = name:sub(1, 64) end
    return name
end

pcall(function()
    if type(makefolder) == "function" then
        if type(isfolder) == "function" then
            if not isfolder("AirHub") then makefolder("AirHub") end
            if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
        else
            pcall(makefolder, "AirHub")
            pcall(makefolder, CONFIG_FOLDER)
        end
    end
end)

local function Config_Encode(value)
    local t = type(value)
    if t == "number" or t == "string" or t == "boolean" then
        return value
    elseif t == "table" then
        if type(value.R) == "number" and type(value.G) == "number" and type(value.B) == "number"
            and value.X == nil then
            return { __t = "Color3", R = value.R, G = value.G, B = value.B }
        elseif type(value.X) == "number" and type(value.Y) == "number" and type(value.Z) == "number"
            and value.R == nil then
            return { __t = "Vector3", X = value.X, Y = value.Y, Z = value.Z }
        elseif type(value.X) == "number" and type(value.Y) == "number" and value.Z == nil then
            return { __t = "Vector2", X = value.X, Y = value.Y }
        else
            local out = {}
            for k, v in pairs(value) do
                local enc = Config_Encode(v)
                if enc ~= nil then out[k] = enc end
            end
            return out
        end
    end
    return nil
end

local function Config_Decode(value)
    if type(value) ~= "table" then return value end
    if value.__t == "Color3" then return Color3.new(value.R, value.G, value.B)
    elseif value.__t == "Vector3" then return Vector3.new(value.X, value.Y, value.Z)
    elseif value.__t == "Vector2" then return Vector2.new(value.X, value.Y)
    else
        local out = {}
        for k, v in pairs(value) do out[k] = Config_Decode(v) end
        return out
    end
end

local function Config_ListFiles()
    local list, seen = {}, {}
    for name in pairs(IN_MEMORY_CONFIGS) do
        if not seen[name] then seen[name] = true; table.insert(list, name) end
    end
    if type(listfiles) == "function" then
        local ok, files = pcall(listfiles, CONFIG_FOLDER)
        if ok and type(files) == "table" then
            for _, path in ipairs(files) do
                local name = path:match("([^/\\]+)%.json$")
                if name and not seen[name] then
                    seen[name] = true; table.insert(list, name)
                end
            end
        end
    end
    table.sort(list)
    return list
end

local function Config_Serialize()
    local Hg = getgenv().AirHub
    if not Hg then return {} end
    local data = { Version = 4 }
    if Hg.Aimbot then
        data.Aimbot = Config_Encode(Hg.Aimbot.Settings)
        data.FOVSettings = Config_Encode(Hg.Aimbot.FOVSettings)
    end
    if Hg.WallHack then
        data.WallHack = Config_Encode(Hg.WallHack.Settings)
        data.BoxSettings = Config_Encode(Hg.WallHack.Visuals.BoxSettings)
        data.GlowSettings = Config_Encode(Hg.WallHack.Visuals.GlowSettings)
    end
    if Hg.AntiAim then
        data.AntiAim = Config_Encode(Hg.AntiAim.Settings)
        data.Desync = Config_Encode(Hg.AntiAim.Desync.Settings)
    end
    if Hg.ServerPosition then data.ServerPosition = Config_Encode(Hg.ServerPosition.Settings) end
    if Hg.Fly then data.Fly = Config_Encode(Hg.Fly.Settings) end
    if Hg.Bhop then data.Bhop = Config_Encode(Hg.Bhop.Settings) end
    if Hg.Speed then data.Speed = Config_Encode(Hg.Speed.Settings) end
    if Hg.FastStop then data.FastStop = Config_Encode(Hg.FastStop.Settings) end
    if Hg.AutoStrafer then data.AutoStrafer = Config_Encode(Hg.AutoStrafer.Settings) end
    if Hg.Noclip then data.Noclip = Config_Encode(Hg.Noclip.Settings) end
    data.Logging = Config_Encode(Hg.Logging)
    data.Sound = Config_Encode(Hg.Sound)
    return data
end

local function Config_Apply(data)
    if type(data) ~= "table" then return false end
    local Hg = getgenv().AirHub
    if not Hg then return false end

    if data.Aimbot and Hg.Aimbot then
        local d = Config_Decode(data.Aimbot)
        if type(d) ~= "table" then d = {} end
        if type(d.TeamCheck) ~= "table" then d.TeamCheck = {} end
        if d.TeamCheck.Enabled == nil then d.TeamCheck.Enabled = true end
        if d.TeamCheck.Mode == nil then d.TeamCheck.Mode = "Enemies" end
        if d.TeamCheck.TreatNeutralAsEnemy == nil then d.TeamCheck.TreatNeutralAsEnemy = true end
        if d.AliveCheck == nil then d.AliveCheck = true end
        if d.WallCheck == nil then d.WallCheck = false end
        if d.FallbackToVisible == nil then d.FallbackToVisible = false end
        if d.WallCheckMode == nil then d.WallCheckMode = "Perfect" end
        if d.DelayShot == nil then
            local oldDelay = d.WallCheckDelay
            if type(oldDelay) == "number" then
                d.DelayShot = oldDelay > 0
            else
                d.DelayShot = true
            end
        end
        if type(d.DelayShot) ~= "boolean" then
            d.DelayShot = (tonumber(d.DelayShot) or 1) > 0
        end
        d.WallCheckDelay = nil
        if d.AimSmoothingSpeed == nil then d.AimSmoothingSpeed = 6 end
        if d.TriggerKey == nil then d.TriggerKey = "MouseButton2" end
        if d.Toggle == nil then d.Toggle = false end
        if d.LockPart == nil then d.LockPart = "Head" end
        if d.AimMethod == nil then d.AimMethod = "Smooth" end
        if d.SilentAim == nil then d.SilentAim = true end
        if d.SilentAimMode == nil then d.SilentAimMode = "Camera" end
        if d.IgnoreFOV == nil then d.IgnoreFOV = false end
        if d.CheckFromPlayerOnTP == nil then d.CheckFromPlayerOnTP = true end
        if d.PredictionEnabled == nil then d.PredictionEnabled = false end
        if d.PredictionX == nil then d.PredictionX = 0 end
        if d.PredictionY == nil then d.PredictionY = 0 end
        if d.PredictionTime == nil then d.PredictionTime = 0.15 end
        if type(d.AutoShoot) ~= "table" then d.AutoShoot = {} end
        if d.AutoShoot.Enabled == nil then d.AutoShoot.Enabled = false end
        if d.AutoShoot.ShootKey == nil then d.AutoShoot.ShootKey = "MouseButton1" end
        if d.AutoShoot.FireRate == nil then d.AutoShoot.FireRate = 0.05 end
        if d.AutoShoot.OnlyWhenAiming == nil then d.AutoShoot.OnlyWhenAiming = true end
        if type(d.AutoShoot.AutoStop) ~= "table" then d.AutoShoot.AutoStop = {} end
        if d.AutoShoot.AutoStop.Enabled == nil then d.AutoShoot.AutoStop.Enabled = false end
        if d.AutoShoot.AutoStop.Time == nil then d.AutoShoot.AutoStop.Time = 0.1 end
        Hg.Aimbot.Settings = d
        Hg.Aimbot.Locked = nil
        Hg.Aimbot.LockPartInstance = nil
    end

    if data.FOVSettings and Hg.Aimbot then
        local f = Config_Decode(data.FOVSettings)
        if type(f) == "table" then
            if f.Enabled == nil then f.Enabled = true end
            if f.Visible == nil then f.Visible = true end
            if f.Amount == nil then f.Amount = 90 end
            Hg.Aimbot.FOVSettings = f
        end
    end

    if data.WallHack and Hg.WallHack then
        local w = Config_Decode(data.WallHack)
        if type(w) == "table" then
            if w.Enabled == nil then w.Enabled = false end
            if w.TeamCheck == nil then w.TeamCheck = false end
            if w.AliveCheck == nil then w.AliveCheck = true end
            Hg.WallHack.Settings = w
        end
    end

    if data.BoxSettings and Hg.WallHack then
        local b = Config_Decode(data.BoxSettings)
        if type(b) == "table" then
            b.Color = SanitizeColor(b.Color)
            b.TargetColor = SanitizeColor(b.TargetColor)
            if b.Type == nil then b.Type = 1 end
            if b.Transparency == nil then b.Transparency = 0.7 end
            if b.Thickness == nil then b.Thickness = 1 end
            if b.Filled == nil then b.Filled = false end
            if b.Increase == nil then b.Increase = 1 end
            Hg.WallHack.Visuals.BoxSettings = b
        end
    end

    if data.GlowSettings and Hg.WallHack then
        local g = Config_Decode(data.GlowSettings)
        if type(g) == "table" then
            g.Color = SanitizeColor(g.Color)
            if g.Enabled == nil then g.Enabled = true end
            if g.Transparency == nil then g.Transparency = 0.5 end
            if g.Mode == nil then g.Mode = "Outline" end
            Hg.WallHack.Visuals.GlowSettings = g
        end
    end

    if data.AntiAim and Hg.AntiAim then
        local a = Config_Decode(data.AntiAim)
        if type(a) == "table" then
            if a.Enabled == nil then a.Enabled = false end
            if a.Mode == nil then a.Mode = "Static" end
            if a.Method == nil then a.Method = "CFrame" end
            if type(a.Body) ~= "table" then a.Body = {} end
            if a.Body.Reference == nil then a.Body.Reference = "Camera" end
            if a.Body.Yaw == nil then a.Body.Yaw = 0 end
            if a.Body.SpinSpeed == nil then a.Body.SpinSpeed = 0 end
            if a.Body.JitterAmount == nil then a.Body.JitterAmount = 5 end
            if a.Body.JitterSpeed == nil then a.Body.JitterSpeed = 10 end
            if a.Body.SwayAmount == nil then a.Body.SwayAmount = 30 end
            if a.Body.SwaySpeed == nil then a.Body.SwaySpeed = 2 end
            if a.Body.IgnoreMoving == nil then a.Body.IgnoreMoving = false end
            if a.Body.MoveSpeedThreshold == nil then a.Body.MoveSpeedThreshold = 0.5 end
            Hg.AntiAim.Settings = a
        end
    end

    if data.Desync and Hg.AntiAim then
        local d = Config_Decode(data.Desync)
        if type(d) == "table" then
            if d.Enabled == nil then d.Enabled = false end
            if d.Mode == nil then d.Mode = "Random" end
            if d.RadiusX == nil then d.RadiusX = 5 end
            if d.RadiusY == nil then d.RadiusY = 5 end
            if d.RadiusZ == nil then d.RadiusZ = 5 end
            if d.UpdateInterval == nil then d.UpdateInterval = 0.05 end
            if d.Smoothness == nil then d.Smoothness = 0.2 end
            if d.OnlyInAir == nil then d.OnlyInAir = false end
            if d.NotInAir == nil then d.NotInAir = false end
            if d.FreezeOldPos == nil then d.FreezeOldPos = true end
            if d.RandomDelayEnabled == nil then d.RandomDelayEnabled = false end
            if d.AutoUpdateMin == nil then d.AutoUpdateMin = 0.2 end
            if d.AutoUpdateMax == nil then d.AutoUpdateMax = 1.0 end
            if d.RefreshOnShot == nil then d.RefreshOnShot = false end
            Hg.AntiAim.Desync.Settings = d
        end
    end

    if data.ServerPosition and Hg.ServerPosition then
        local s = Config_Decode(data.ServerPosition)
        if type(s) == "table" then
            if s.Enabled == nil then s.Enabled = false end
            if s.RGB == nil then s.RGB = true end
            if s.Strength == nil then s.Strength = 1 end
            if s.MaxLimb == nil then s.MaxLimb = 6 end
            Hg.ServerPosition.Settings = s
        end
    end

    if data.Fly and Hg.Fly then
        local f = Config_Decode(data.Fly)
        if type(f) == "table" then
            if f.Enabled == nil then f.Enabled = false end
            if f.ToggleKey == nil then f.ToggleKey = "F" end
            if f.Toggle == nil then f.Toggle = false end
            if f.Method == nil then f.Method = "BodyVelocity" end
            if f.Speed == nil then f.Speed = 30 end
            if f.UpSpeed == nil then f.UpSpeed = 20 end
            if f.Smoothness == nil then f.Smoothness = 0.5 end
            if f.UseKeys == nil then f.UseKeys = true end
            Hg.Fly.Settings = f
            Hg.Fly.Internal.Active = false
        end
    end

    if data.Bhop and Hg.Bhop then
        local b = Config_Decode(data.Bhop)
        if type(b) == "table" then
            if b.Enabled == nil then b.Enabled = false end
            if b.AutoJumpKey == nil then b.AutoJumpKey = "Space" end
            if b.BypassJump == nil then b.BypassJump = true end
            if b.JumpCooldown == nil then b.JumpCooldown = 0.1 end
            if type(b.Spider) ~= "table" then b.Spider = {} end
            if b.Spider.Enabled == nil then b.Spider.Enabled = false end
            if b.Spider.Range == nil then b.Spider.Range = 2.5 end
            if b.Spider.RayCount == nil then b.Spider.RayCount = 8 end
            Hg.Bhop.Settings = b
            Hg.Bhop.Internal.KeyHeld = false
            Hg.Bhop.Internal.Active = false
        end
    end

    if data.Speed and Hg.Speed then
        local s = Config_Decode(data.Speed)
        if type(s) == "table" then
            if s.Enabled == nil then s.Enabled = false end
            if s.Method == nil then s.Method = "WalkSpeed" end
            if s.GroundSpeed == nil then s.GroundSpeed = 30 end
            if s.AirSpeed == nil then s.AirSpeed = 30 end
            if s.UseAirSpeed == nil then s.UseAirSpeed = false end
            if s.InAirOnly == nil then s.InAirOnly = false end
            Hg.Speed.Settings = s
        end
    end

    if data.FastStop and Hg.FastStop then
        local s = Config_Decode(data.FastStop)
        if type(s) == "table" then
            if s.Enabled == nil then s.Enabled = false end
            if s.StopY == nil then s.StopY = false end
            Hg.FastStop.Settings = s
        end
    end

    if data.AutoStrafer and Hg.AutoStrafer then
        local s = Config_Decode(data.AutoStrafer)
        if type(s) == "table" then
            if s.Enabled == nil then s.Enabled = false end
            if s.Mode == nil then s.Mode = "Legit" end
            if s.Key == nil then s.Key = "Space" end
            if s.Toggle == nil then s.Toggle = false end
            if s.Invert == nil then s.Invert = false end
            if s.SpamDelay == nil then s.SpamDelay = 0.05 end
            Hg.AutoStrafer.Settings = s
            Hg.AutoStrafer.Internal.Active = false
            Hg.AutoStrafer.Internal.KeyA = false
            Hg.AutoStrafer.Internal.KeyD = false
        end
    end

    if data.Noclip and Hg.Noclip then
        local s = Config_Decode(data.Noclip)
        if type(s) == "table" then
            if s.Enabled == nil then s.Enabled = false end
            Hg.Noclip.Settings = s
        end
    end

    if data.Logging then
        local l = Config_Decode(data.Logging)
        if type(l) == "table" then Hg.Logging = l end
    end

    if data.Sound then
        local s = Config_Decode(data.Sound)
        if type(s) == "table" then Hg.Sound = s end
    end

    return true
end

local function Config_Save(name)
    name = Config_SanitizeName(name)
    if not name then return false, "invalid name" end
    local data = Config_Serialize()
    if Config_HasFS() and type(HttpService.JSONEncode) == "function" then
        local ok, encoded = pcall(function() return HttpService:JSONEncode(data) end)
        if ok and encoded then
            local path1 = CONFIG_FOLDER .. "/" .. name .. ".json"
            local path2 = CONFIG_FOLDER .. "\\" .. name .. ".json"
            local wok = pcall(writefile, path1, encoded)
            if not wok then wok = pcall(writefile, path2, encoded) end
            if wok then return true, "file" end
        end
    end
    IN_MEMORY_CONFIGS[name] = DeepCopy(data)
    return true, "memory"
end

local function Config_Load(name)
    name = Config_SanitizeName(name)
    if not name then return false, "invalid name" end
    if IN_MEMORY_CONFIGS[name] then
        Config_Apply(DeepCopy(IN_MEMORY_CONFIGS[name]))
        return true, "memory"
    end
    if Config_HasFS() and type(readfile) == "function" then
        local content
        local ok1, c1 = pcall(readfile, CONFIG_FOLDER .. "/" .. name .. ".json")
        if ok1 and c1 and c1 ~= "" then
            content = c1
        else
            local ok2, c2 = pcall(readfile, CONFIG_FOLDER .. "\\" .. name .. ".json")
            if ok2 and c2 and c2 ~= "" then content = c2 end
        end
        if content then
            local decode_ok, decoded = pcall(function() return HttpService:JSONDecode(content) end)
            if decode_ok and decoded then
                Config_Apply(decoded)
                return true, "file"
            end
        end
    end
    return false, "not found"
end

local function Config_Delete(name)
    name = Config_SanitizeName(name)
    if not name then return false, "invalid name" end
    local deleted = false
    if IN_MEMORY_CONFIGS[name] then
        IN_MEMORY_CONFIGS[name] = nil
        deleted = true
    end
    if type(delfile) == "function" then
        local ok1 = pcall(delfile, CONFIG_FOLDER .. "/" .. name .. ".json")
        local ok2 = pcall(delfile, CONFIG_FOLDER .. "\\" .. name .. ".json")
        if ok1 or ok2 then deleted = true end
    end
    return deleted, deleted and "deleted" or "not found"
end

--// ---------------------------------------------------------------------------
--// Expose shared utilities
--// ---------------------------------------------------------------------------
H.Util = {
    -- services
    Players = Players,
    RunService = RunService,
    UserInputService = UserInputService,
    VirtualInputManager = VirtualInputManager,
    HttpService = HttpService,
    TeleportService = TeleportService,
    ReplicatedStorage = ReplicatedStorage,
    LocalPlayer = LocalPlayer,

    -- helpers
    Track = Track,
    UntrackAll = UntrackAll,
    ShowError = ShowError,
    HandleError = HandleError,
    SafeKeyCode = SafeKeyCode,
    SafeUserInputType = SafeUserInputType,
    SanitizeColor = SanitizeColor,
    DeepCopy = DeepCopy,
    AddLog = AddLog,
    RAY_FILTER = RAY_FILTER,

    -- sounds
    PlayHitsound = PlayHitsound,
    PlayKillsound = PlayKillsound,
}

H.Config = {
    Save = Config_Save,
    Load = Config_Load,
    Delete = Config_Delete,
    ListFiles = Config_ListFiles,
    SanitizeName = Config_SanitizeName,
}

H.PlayHitsound = PlayHitsound
H.PlayKillsound = PlayKillsound
