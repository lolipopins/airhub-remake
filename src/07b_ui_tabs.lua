--// AirHub - 07b_ui_tabs.lua
--// Visuals, Anti-Aim (Body + Desync), Movement, Settings tabs.

local H = getgenv().AirHub
if not H or not H._UI then warn("[AirHub] 07b: 07a not loaded"); return end

task.spawn(function()
    local deadline = tick() + 10
    while tick() < deadline do
        if H._UI.MovementTab and H._UI.SettingsTab then break end
        task.wait(0.1)
    end
    if not H._UI.MovementTab then warn("[AirHub] 07b: timeout waiting for tabs"); return end

    local Util             = H.Util
    local ShowError        = Util.ShowError
    local SanitizeColor    = Util.SanitizeColor
    local TeleportService  = Util.TeleportService
    local HttpService      = Util.HttpService
    local LocalPlayer      = Util.LocalPlayer

    local _missingLogged = {}
    local function noop() end
    local function orNoop(fn, label)
        if type(fn) == "function" then return fn end
        if label and not _missingLogged[label] then
            _missingLogged[label] = true
            warn("[AirHub] 07b: missing function → " .. tostring(label))
        end
        return noop
    end
    local function orTable(t, label)
        if type(t) == "table" then return t end
        if label and not _missingLogged[label] then
            _missingLogged[label] = true
            warn("[AirHub] 07b: missing module → " .. tostring(label))
        end
        return {}
    end

    local Aimbot         = orTable(H.Aimbot,         "Aimbot")
    local WallHack       = orTable(H.WallHack,       "WallHack")
    local AntiAim        = orTable(H.AntiAim,        "AntiAim")
    local ServerPosition = orTable(H.ServerPosition, "ServerPosition")
    local Fly            = orTable(H.Fly,            "Fly")
    local Bhop           = orTable(H.Bhop,           "Bhop")
    local Speed          = orTable(H.Speed,          "Speed")
    local FastStop       = orTable(H.FastStop,       "FastStop")
    local AutoStrafer    = orTable(H.AutoStrafer,    "AutoStrafer")
    local Noclip         = orTable(H.Noclip,         "Noclip")

    local CancelLock           = orNoop(Aimbot.CancelLock,           "Aimbot.CancelLock")
    local ApplyGlowToAll       = orNoop(WallHack.ApplyGlowToAll,     "WallHack.ApplyGlowToAll")
    local StartServerPosition  = orNoop(ServerPosition.Start,        "ServerPosition.Start")
    local StopServerPosition   = orNoop(ServerPosition.Stop,         "ServerPosition.Stop")
    local Fly_ClearInstances   = orNoop(Fly.ClearInstances,          "Fly.ClearInstances")
    local StopDesync           = orNoop(AntiAim.StopDesync,          "AntiAim.StopDesync")
    local StartDesync          = orNoop(AntiAim.StartDesync,         "AntiAim.StartDesync")

    WallHack.Settings        = WallHack.Settings        or {}
    WallHack.Visuals         = WallHack.Visuals         or {}
    WallHack.Visuals.BoxSettings   = WallHack.Visuals.BoxSettings   or { Enabled = false, Type = 1, Color = Color3.fromRGB(255,255,255), TargetColor = Color3.fromRGB(255,0,0), Transparency = 0.7, Thickness = 1, Filled = false, Increase = 1 }
    WallHack.Visuals.GlowSettings  = WallHack.Visuals.GlowSettings  or { Enabled = false, Color = Color3.fromRGB(0,255,255), Transparency = 0.5, Mode = "Outline" }
    WallHack.Visuals.HUDSettings   = WallHack.Visuals.HUDSettings   or { Enabled = false, Position = "TopLeft", ShowPlayers = true, ShowFPS = true, ShowPing = true, ShowSession = true }
    WallHack.Visuals.SelfESP       = WallHack.Visuals.SelfESP       or { Enabled = false, Chams = { Enabled = false, Mode = "Both", FillColor = Color3.fromRGB(90,140,255), FillTransparency = 0.4, OutlineColor = Color3.fromRGB(255,255,255), OutlineTransparency = 0, AlwaysOnTop = true }, ChinaHat = { Enabled = false, Color = Color3.fromRGB(255,60,60), Material = "Neon", Size = 4, OffsetY = 1.8, Transparency = 0, Rotation = 0 } }
    WallHack.Functions       = WallHack.Functions       or {}
    AntiAim.Settings         = AntiAim.Settings         or { Enabled = false, Mode = "Static", Method = "CFrame", Body = { Reference = "Camera", Yaw = 0, Amount = 15, Speed = 5, IgnoreMoving = false, MoveSpeedThreshold = 0.5 } }
    AntiAim.Desync           = AntiAim.Desync           or { Settings = { Enabled = false, Mode = "Default", X = 5, Y = 5, Z = 5, Random = false, UpdateInterval = 0.05, OldPosDelayEnabled = true, OldPosDelay = 0.5, VoidDepth = -1000, InPlayerOffset = 2, RefreshOnShot = false, RandomRotate = false }, Internal = {} }
    AntiAim.Desync.Settings  = AntiAim.Desync.Settings  or { Enabled = false }
    AntiAim.Functions        = AntiAim.Functions        or {}
    ServerPosition.Settings  = ServerPosition.Settings  or { Enabled = false, RGB = true, Strength = 1, MaxLimb = 6 }
    Fly.Settings             = Fly.Settings             or { Enabled = false, ToggleKey = "F", Toggle = false, Method = "BodyVelocity", Speed = 30, UpSpeed = 20, Smoothness = 0.5, UseKeys = true }
    Fly.Internal             = Fly.Internal             or { Active = false }
    Fly.Functions            = Fly.Functions            or {}
    Bhop.Settings            = Bhop.Settings            or { Enabled = false, AutoJumpKey = "Space", BypassJump = true, JumpCooldown = 0.1, Spider = { Enabled = false, Range = 2.5, RayCount = 8 } }
    Bhop.Internal            = Bhop.Internal            or { KeyHeld = false, Active = false }
    Bhop.Functions           = Bhop.Functions           or {}
    Speed.Settings           = Speed.Settings           or { Enabled = false, Method = "WalkSpeed", GroundSpeed = 30, AirSpeed = 30, UseAirSpeed = false, InAirOnly = false }
    Speed.Internal           = Speed.Internal           or { Active = false, OriginalWalkSpeed = 16 }
    Speed.Functions          = Speed.Functions          or {}
    FastStop.Settings        = FastStop.Settings        or { Enabled = false, StopY = false }
    FastStop.Internal        = FastStop.Internal        or { LastActive = false }
    FastStop.Functions       = FastStop.Functions       or {}
    AutoStrafer.Settings     = AutoStrafer.Settings     or { Enabled = false, Mode = "Legit", Key = "Space", Toggle = false, Invert = false, SpamDelay = 0.05 }
    AutoStrafer.Internal     = AutoStrafer.Internal     or { Active = false, KeyA = false, KeyD = false }
    AutoStrafer.Functions    = AutoStrafer.Functions    or {}
    Noclip.Settings          = Noclip.Settings          or { Enabled = false }
    Noclip.Internal          = Noclip.Internal          or { Active = false, Saved = {} }
    Noclip.Functions         = Noclip.Functions         or {}

    WallHack.Functions.StartHUD      = WallHack.Functions.StartHUD      or noop
    WallHack.Functions.StopHUD       = WallHack.Functions.StopHUD       or noop
    WallHack.Functions.SetHUDEnabled = WallHack.Functions.SetHUDEnabled or function() end
    WallHack.Functions.StartSelfESP  = WallHack.Functions.StartSelfESP  or noop
    WallHack.Functions.StopSelfESP   = WallHack.Functions.StopSelfESP   or noop
    WallHack.Functions.RefreshSelfESP= WallHack.Functions.RefreshSelfESP or noop

    local Library          = H._UI.Library
    local Config_Save      = (H.Config and H.Config.Save)      or function() return false, "no config" end
    local Config_Load      = (H.Config and H.Config.Load)      or function() return false, "no config" end
    local Config_Delete    = (H.Config and H.Config.Delete)    or function() return false, "no config" end
    local Config_ListFiles = (H.Config and H.Config.ListFiles) or function() return {} end

    local VisualsTab  = H._UI.VisualsTab
    local AntiTab     = H._UI.AntiTab
    local MovementTab = H._UI.MovementTab
    local SettingsTab = H._UI.SettingsTab

    local glowModes = { "Outline", "Fill", "Both", "Pulse" }

    --// VISUALS
    local vis1 = VisualsTab:CreateSection({ Name = "WallHack" })
    vis1:AddToggle({ Name = "Enabled", Value = WallHack.Settings.Enabled,
        Callback = function(v) WallHack.Settings.Enabled = v; ApplyGlowToAll() end })
    vis1:AddToggle({ Name = "Team Check", Value = WallHack.Settings.TeamCheck,
        Callback = function(v) WallHack.Settings.TeamCheck = v end })
    vis1:AddToggle({ Name = "Alive Check", Value = WallHack.Settings.AliveCheck,
        Callback = function(v) WallHack.Settings.AliveCheck = v end })

    local visBox = VisualsTab:CreateSection({ Name = "Boxes" })
    visBox:AddToggle({ Name = "Enabled", Value = WallHack.Visuals.BoxSettings.Enabled,
        Callback = function(v) WallHack.Visuals.BoxSettings.Enabled = v end })
    visBox:AddDropdown({ Name = "Type",
        Value = (WallHack.Visuals.BoxSettings.Type == 1 and "3D" or "2D"),
        List = { "3D", "2D" },
        Callback = function(v) WallHack.Visuals.BoxSettings.Type = (v == "3D") and 1 or 2 end })
    visBox:AddColorpicker({ Name = "Color", Value = WallHack.Visuals.BoxSettings.Color,
        Callback = function(v) WallHack.Visuals.BoxSettings.Color = SanitizeColor(v) end })
    visBox:AddColorpicker({ Name = "Target Color", Value = WallHack.Visuals.BoxSettings.TargetColor,
        Callback = function(v) WallHack.Visuals.BoxSettings.TargetColor = SanitizeColor(v) end })
    visBox:AddSlider({ Name = "Transparency", Value = WallHack.Visuals.BoxSettings.Transparency,
        Min = 0, Max = 1, Decimals = 2,
        Callback = function(v) WallHack.Visuals.BoxSettings.Transparency = v end })
    visBox:AddSlider({ Name = "Thickness", Value = WallHack.Visuals.BoxSettings.Thickness,
        Min = 1, Max = 5,
        Callback = function(v) WallHack.Visuals.BoxSettings.Thickness = v end })
    visBox:AddToggle({ Name = "Filled (2D)", Value = WallHack.Visuals.BoxSettings.Filled,
        Callback = function(v) WallHack.Visuals.BoxSettings.Filled = v end })
    visBox:AddSlider({ Name = "Scale (3D)", Value = WallHack.Visuals.BoxSettings.Increase,
        Min = 1, Max = 5,
        Callback = function(v) WallHack.Visuals.BoxSettings.Increase = v end })

    local hudSec = VisualsTab:CreateSection({ Name = "HUD" })
    hudSec:AddToggle({ Name = "Enable HUD", Value = WallHack.Visuals.HUDSettings.Enabled,
        Callback = function(v) WallHack.Visuals.HUDSettings.Enabled = v
            if v then WallHack.Functions.StartHUD() else WallHack.Functions.StopHUD() end end })
    hudSec:AddDropdown({ Name = "Position", Value = WallHack.Visuals.HUDSettings.Position or "TopLeft",
        List = { "TopLeft", "TopRight", "BottomLeft", "BottomRight" },
        Callback = function(v) WallHack.Visuals.HUDSettings.Position = v end })
    hudSec:AddToggle({ Name = "Show Players count", Value = WallHack.Visuals.HUDSettings.ShowPlayers ~= false,
        Callback = function(v) WallHack.Visuals.HUDSettings.ShowPlayers = v end })
    hudSec:AddToggle({ Name = "Show FPS", Value = WallHack.Visuals.HUDSettings.ShowFPS ~= false,
        Callback = function(v) WallHack.Visuals.HUDSettings.ShowFPS = v end })
    hudSec:AddToggle({ Name = "Show Ping", Value = WallHack.Visuals.HUDSettings.ShowPing ~= false,
        Callback = function(v) WallHack.Visuals.HUDSettings.ShowPing = v end })
    hudSec:AddToggle({ Name = "Show Session time", Value = WallHack.Visuals.HUDSettings.ShowSession ~= false,
        Callback = function(v) WallHack.Visuals.HUDSettings.ShowSession = v end })

    local glowSec = VisualsTab:CreateSection({ Name = "Glow", Side = "Right" })
    glowSec:AddToggle({ Name = "Enabled", Value = WallHack.Visuals.GlowSettings.Enabled,
        Callback = function(v) WallHack.Visuals.GlowSettings.Enabled = v; ApplyGlowToAll() end })
    glowSec:AddColorpicker({ Name = "Color", Value = WallHack.Visuals.GlowSettings.Color,
        Callback = function(v) WallHack.Visuals.GlowSettings.Color = SanitizeColor(v); ApplyGlowToAll() end })
    glowSec:AddSlider({ Name = "Transparency", Value = WallHack.Visuals.GlowSettings.Transparency,
        Min = 0, Max = 1, Decimals = 2,
        Callback = function(v)
            local n = tonumber(v)
            if n then WallHack.Visuals.GlowSettings.Transparency = math.clamp(n, 0, 1) end
            ApplyGlowToAll()
        end })
    glowSec:AddDropdown({ Name = "Mode", Value = WallHack.Visuals.GlowSettings.Mode or "Outline",
        List = glowModes,
        Callback = function(v)
            WallHack.Visuals.GlowSettings.Mode = type(v) == "string" and v or "Outline"
            ApplyGlowToAll()
        end })

    local seSec = VisualsTab:CreateSection({ Name = "Self ESP", Side = "Right" })
    local function refreshSelfESP() WallHack.Functions.RefreshSelfESP() end
    seSec:AddToggle({ Name = "Enable Self ESP", Value = WallHack.Visuals.SelfESP.Enabled,
        Callback = function(v)
            WallHack.Visuals.SelfESP.Enabled = v
            if v then WallHack.Functions.StartSelfESP() else WallHack.Functions.StopSelfESP() end
        end })
    seSec:AddToggle({ Name = "  Chams: Enabled", Value = WallHack.Visuals.SelfESP.Chams.Enabled,
        Callback = function(v) WallHack.Visuals.SelfESP.Chams.Enabled = v; refreshSelfESP() end })
    seSec:AddDropdown({ Name = "  Chams: Mode", Value = WallHack.Visuals.SelfESP.Chams.Mode or "Both",
        List = { "Fill", "Outline", "Both" },
        Callback = function(v) WallHack.Visuals.SelfESP.Chams.Mode = v; refreshSelfESP() end })
    seSec:AddColorpicker({ Name = "  Chams: Fill Color", Value = WallHack.Visuals.SelfESP.Chams.FillColor,
        Callback = function(v) WallHack.Visuals.SelfESP.Chams.FillColor = SanitizeColor(v); refreshSelfESP() end })
    seSec:AddSlider({ Name = "  Chams: Fill Transparency", Value = WallHack.Visuals.SelfESP.Chams.FillTransparency,
        Min = 0, Max = 1, Decimals = 2,
        Callback = function(v) WallHack.Visuals.SelfESP.Chams.FillTransparency = v; refreshSelfESP() end })
    seSec:AddColorpicker({ Name = "  Chams: Outline Color", Value = WallHack.Visuals.SelfESP.Chams.OutlineColor,
        Callback = function(v) WallHack.Visuals.SelfESP.Chams.OutlineColor = SanitizeColor(v); refreshSelfESP() end })
    seSec:AddSlider({ Name = "  Chams: Outline Transparency", Value = WallHack.Visuals.SelfESP.Chams.OutlineTransparency,
        Min = 0, Max = 1, Decimals = 2,
        Callback = function(v) WallHack.Visuals.SelfESP.Chams.OutlineTransparency = v; refreshSelfESP() end })
    seSec:AddToggle({ Name = "  Chams: Always on top", Value = WallHack.Visuals.SelfESP.Chams.AlwaysOnTop ~= false,
        Callback = function(v) WallHack.Visuals.SelfESP.Chams.AlwaysOnTop = v; refreshSelfESP() end })
    seSec:AddToggle({ Name = "  China Hat: Enabled", Value = WallHack.Visuals.SelfESP.ChinaHat.Enabled,
        Callback = function(v) WallHack.Visuals.SelfESP.ChinaHat.Enabled = v; refreshSelfESP() end })
    seSec:AddColorpicker({ Name = "  China Hat: Color", Value = WallHack.Visuals.SelfESP.ChinaHat.Color,
        Callback = function(v) WallHack.Visuals.SelfESP.ChinaHat.Color = SanitizeColor(v); refreshSelfESP() end })
    seSec:AddSlider({ Name = "  China Hat: Size", Value = WallHack.Visuals.SelfESP.ChinaHat.Size,
        Min = 1, Max = 10, Decimals = 1,
        Callback = function(v) WallHack.Visuals.SelfESP.ChinaHat.Size = v; refreshSelfESP() end })
    seSec:AddSlider({ Name = "  China Hat: Offset Y", Value = WallHack.Visuals.SelfESP.ChinaHat.OffsetY,
        Min = 0, Max = 5, Decimals = 1,
        Callback = function(v) WallHack.Visuals.SelfESP.ChinaHat.OffsetY = v; refreshSelfESP() end })
    seSec:AddSlider({ Name = "  China Hat: Rotation", Value = WallHack.Visuals.SelfESP.ChinaHat.Rotation,
        Min = 0, Max = 360,
        Callback = function(v) WallHack.Visuals.SelfESP.ChinaHat.Rotation = v; refreshSelfESP() end })
    seSec:AddSlider({ Name = "  China Hat: Transparency", Value = WallHack.Visuals.SelfESP.ChinaHat.Transparency,
        Min = 0, Max = 1, Decimals = 2,
        Callback = function(v) WallHack.Visuals.SelfESP.ChinaHat.Transparency = v; refreshSelfESP() end })
    seSec:AddDropdown({ Name = "  China Hat: Material", Value = "Neon",
        List = { "Neon", "ForceField", "Glass", "Plastic", "SmoothPlastic", "Metal" },
        Callback = function(v) WallHack.Visuals.SelfESP.ChinaHat.Material = v; refreshSelfESP() end })

    local spSec = VisualsTab:CreateSection({ Name = "Server Position (Ghost)", Side = "Right" })
    spSec:AddToggle({ Name = "Enabled", Value = ServerPosition.Settings.Enabled,
        Callback = function(v)
            ServerPosition.Settings.Enabled = v
            if v then StopServerPosition(); StartServerPosition() else StopServerPosition() end
        end })
    spSec:AddToggle({ Name = "RGB Color", Value = ServerPosition.Settings.RGB,
        Callback = function(v) ServerPosition.Settings.RGB = v end })
    spSec:AddSlider({ Name = "Strength", Value = ServerPosition.Settings.Strength,
        Min = 0, Max = 5, Decimals = 1,
        Callback = function(v) ServerPosition.Settings.Strength = v end })
    spSec:AddSlider({ Name = "Max Limb Distance", Value = ServerPosition.Settings.MaxLimb,
        Min = 1, Max = 20,
        Callback = function(v) ServerPosition.Settings.MaxLimb = v end })

    --// ANTI-AIM
    local aaModes     = { "Static", "Spin", "Jitter", "Sway" }
    local refModes    = { "Camera", "Movement", "Player" }
    local aaMethods   = { "CFrame", "BodyGyro", "Motor6D", "AlignOrientation", "AngularVelocity" }
    local desyncModes = { "Default", "OldPosition", "Void", "InPlayer" }

    local aaMain = AntiTab:CreateSection({ Name = "Body (Server)" })
    aaMain:AddToggle({ Name = "Enabled", Value = AntiAim.Settings.Enabled,
        Callback = function(v) AntiAim.Settings.Enabled = v end })
    aaMain:AddDropdown({ Name = "Mode", Value = AntiAim.Settings.Mode, List = aaModes,
        Callback = function(v) AntiAim.Settings.Mode = v end })
    aaMain:AddDropdown({ Name = "Method", Value = AntiAim.Settings.Method, List = aaMethods,
        Callback = function(v) AntiAim.Settings.Method = v end })
    aaMain:AddDropdown({ Name = "Reference", Value = AntiAim.Settings.Body.Reference, List = refModes,
        Callback = function(v) AntiAim.Settings.Body.Reference = v end })
    aaMain:AddSlider({ Name = "Yaw", Value = AntiAim.Settings.Body.Yaw, Min = -180, Max = 180,
        Callback = function(v) AntiAim.Settings.Body.Yaw = v end })
    aaMain:AddTextbox({ Name = "Amount (any number)", Value = tostring(AntiAim.Settings.Body.Amount),
        Callback = function(v)
            local n = tonumber(v)
            if n then AntiAim.Settings.Body.Amount = n end
        end })
    aaMain:AddTextbox({ Name = "Speed (any number)", Value = tostring(AntiAim.Settings.Body.Speed),
        Callback = function(v)
            local n = tonumber(v)
            if n then AntiAim.Settings.Body.Speed = n end
        end })
    aaMain:AddToggle({ Name = "Ignore when moving", Value = AntiAim.Settings.Body.IgnoreMoving,
        Callback = function(v) AntiAim.Settings.Body.IgnoreMoving = v end })
    aaMain:AddSlider({ Name = "Move speed threshold", Value = AntiAim.Settings.Body.MoveSpeedThreshold,
        Min = 0.1, Max = 5, Decimals = 2,
        Callback = function(v) AntiAim.Settings.Body.MoveSpeedThreshold = v end })

    local desyncSec = AntiTab:CreateSection({ Name = "Desync (Client)", Side = "Right" })
    desyncSec:AddToggle({ Name = "Enabled", Value = AntiAim.Desync.Settings.Enabled,
        Callback = function(v)
            AntiAim.Desync.Settings.Enabled = v
            if v then StartDesync() else StopDesync() end
        end })
    desyncSec:AddDropdown({ Name = "Mode", Value = AntiAim.Desync.Settings.Mode or "Default", List = desyncModes,
        Callback = function(v)
            AntiAim.Desync.Settings.Mode = v
            if AntiAim.Desync.Settings.Enabled then StopDesync(); task.wait(0.05); StartDesync() end
        end })
    desyncSec:AddToggle({ Name = "Random Rotate (pitch/yaw/roll)", Value = AntiAim.Desync.Settings.RandomRotate or false,
        Callback = function(v) AntiAim.Desync.Settings.RandomRotate = v end })
    desyncSec:AddTextbox({ Name = "X", Value = tostring(AntiAim.Desync.Settings.X or 5),
        Callback = function(v)
            local n = tonumber(v)
            if n then AntiAim.Desync.Settings.X = n end
        end })
    desyncSec:AddTextbox({ Name = "Y", Value = tostring(AntiAim.Desync.Settings.Y or 5),
        Callback = function(v)
            local n = tonumber(v)
            if n then AntiAim.Desync.Settings.Y = n end
        end })
    desyncSec:AddTextbox({ Name = "Z", Value = tostring(AntiAim.Desync.Settings.Z or 5),
        Callback = function(v)
            local n = tonumber(v)
            if n then AntiAim.Desync.Settings.Z = n end
        end })
    desyncSec:AddToggle({ Name = "Random (X/Y/Z = max range)", Value = AntiAim.Desync.Settings.Random or false,
        Callback = function(v) AntiAim.Desync.Settings.Random = v end })
    desyncSec:AddSlider({ Name = "Update Interval", Value = AntiAim.Desync.Settings.UpdateInterval or 0.05,
        Min = 0.01, Max = 1, Decimals = 2,
        Callback = function(v) AntiAim.Desync.Settings.UpdateInterval = v end })
    desyncSec:AddToggle({ Name = "OldPosition Delay Enabled", Value = AntiAim.Desync.Settings.OldPosDelayEnabled ~= false,
        Callback = function(v) AntiAim.Desync.Settings.OldPosDelayEnabled = v end })
    desyncSec:AddSlider({ Name = "OldPosition Delay (s)", Value = AntiAim.Desync.Settings.OldPosDelay or 0.5,
        Min = 0.01, Max = 5, Decimals = 2,
        Callback = function(v) AntiAim.Desync.Settings.OldPosDelay = v end })
    desyncSec:AddSlider({ Name = "Void Depth (Y)", Value = AntiAim.Desync.Settings.VoidDepth or -1000,
        Min = -5000, Max = -100,
        Callback = function(v) AntiAim.Desync.Settings.VoidDepth = v end })
    desyncSec:AddSlider({ Name = "InPlayer Offset (studs)", Value = AntiAim.Desync.Settings.InPlayerOffset or 2,
        Min = 0, Max = 20, Decimals = 1,
        Callback = function(v) AntiAim.Desync.Settings.InPlayerOffset = v end })
    desyncSec:AddToggle({ Name = "Refresh position on shot", Value = AntiAim.Desync.Settings.RefreshOnShot or false,
        Callback = function(v) AntiAim.Desync.Settings.RefreshOnShot = v end })
    desyncSec:AddButton({ Name = "Save Current Position",
        Callback = function()
            if AntiAim.Functions and AntiAim.Functions.SaveOldPosition then
                local ok = AntiAim.Functions.SaveOldPosition()
                if ok then ShowError("Old position saved") else ShowError("No character") end
            else
                ShowError("AntiAim function not available")
            end
        end })

    --// MOVEMENT
    local strafeModes  = { "Legit", "Spam" }
    local strafeKeys   = { "Space", "LeftShift", "LeftControl", "C", "X", "Z", "Q", "E" }
    local flyMethods   = { "BodyVelocity", "LinearVelocity", "Velocity", "CFrame" }
    local flyKeys      = { "F", "G", "H", "V", "B", "N", "Space", "LeftShift" }
    local bhopKeys     = { "Space", "LeftControl", "LeftShift", "C", "X", "Z" }
    local speedMethods = { "WalkSpeed", "CFrame", "Velocity" }

    local asSec = MovementTab:CreateSection({ Name = "AutoStrafer" })
    asSec:AddToggle({ Name = "Enabled", Value = AutoStrafer.Settings.Enabled,
        Callback = function(v)
            AutoStrafer.Settings.Enabled = v
            if not v and AutoStrafer.Functions.Stop then AutoStrafer.Functions.Stop() end
        end })
    asSec:AddDropdown({ Name = "Key", Value = AutoStrafer.Settings.Key or "Space", List = strafeKeys,
        Callback = function(v) AutoStrafer.Settings.Key = v end })
    asSec:AddToggle({ Name = "Toggle Mode", Value = AutoStrafer.Settings.Toggle or false,
        Callback = function(v) AutoStrafer.Settings.Toggle = v end })
    asSec:AddDropdown({ Name = "Mode", Value = AutoStrafer.Settings.Mode or "Legit", List = strafeModes,
        Callback = function(v) AutoStrafer.Settings.Mode = v end })
    asSec:AddToggle({ Name = "Invert", Value = AutoStrafer.Settings.Invert or false,
        Callback = function(v) AutoStrafer.Settings.Invert = v end })
    asSec:AddSlider({ Name = "Spam Delay (Spam mode)", Value = AutoStrafer.Settings.SpamDelay or 0.05,
        Min = 0.01, Max = 0.3, Decimals = 2,
        Callback = function(v) AutoStrafer.Settings.SpamDelay = v end })

    local flySec = MovementTab:CreateSection({ Name = "Fly" })
    flySec:AddToggle({ Name = "Enabled", Value = Fly.Settings.Enabled,
        Callback = function(v)
            Fly.Settings.Enabled = v
            if not v then
                Fly.Internal.Active = false
                Fly_ClearInstances()
                local char = LocalPlayer.Character
                if char then
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum then hum.PlatformStand = false end
                end
            end
        end })
    flySec:AddDropdown({ Name = "Method", Value = Fly.Settings.Method or "BodyVelocity", List = flyMethods,
        Callback = function(v) Fly.Settings.Method = v; Fly_ClearInstances() end })
    flySec:AddDropdown({ Name = "Key", Value = Fly.Settings.ToggleKey or "F", List = flyKeys,
        Callback = function(v) Fly.Settings.ToggleKey = v end })
    flySec:AddToggle({ Name = "Toggle Mode", Value = Fly.Settings.Toggle or false,
        Callback = function(v) Fly.Settings.Toggle = v end })
    flySec:AddSlider({ Name = "Speed", Value = Fly.Settings.Speed or 30, Min = 1, Max = 200,
        Callback = function(v) Fly.Settings.Speed = v end })
    flySec:AddSlider({ Name = "Up/Down Speed", Value = Fly.Settings.UpSpeed or 20, Min = 1, Max = 200,
        Callback = function(v) Fly.Settings.UpSpeed = v end })
    flySec:AddSlider({ Name = "Smoothness", Value = Fly.Settings.Smoothness or 0.5,
        Min = 0.05, Max = 1, Decimals = 2,
        Callback = function(v) Fly.Settings.Smoothness = v end })
    flySec:AddToggle({ Name = "Use WASD + Space/Ctrl", Value = Fly.Settings.UseKeys ~= false,
        Callback = function(v) Fly.Settings.UseKeys = v end })

    local bhopSec = MovementTab:CreateSection({ Name = "Bhop", Side = "Right" })
    bhopSec:AddToggle({ Name = "Enabled", Value = Bhop.Settings.Enabled,
        Callback = function(v)
            Bhop.Settings.Enabled = v
            if not v then
                Bhop.Internal.KeyHeld = false
                Bhop.Internal.Active = false
                Bhop.Internal.SpiderTouching = false
            end
        end })
    bhopSec:AddDropdown({ Name = "Jump Key", Value = Bhop.Settings.AutoJumpKey or "Space", List = bhopKeys,
        Callback = function(v) Bhop.Settings.AutoJumpKey = v end })
    bhopSec:AddToggle({ Name = "Bypass Jump Restrictions", Value = Bhop.Settings.BypassJump ~= false,
        Callback = function(v) Bhop.Settings.BypassJump = v end })
    bhopSec:AddSlider({ Name = "Jump Cooldown", Value = Bhop.Settings.JumpCooldown or 0.1,
        Min = 0.01, Max = 0.5, Decimals = 2,
        Callback = function(v) Bhop.Settings.JumpCooldown = v end })

    local spiderSec = MovementTab:CreateSection({ Name = "Spider (Bhop assist)", Side = "Right" })
    spiderSec:AddToggle({ Name = "Enabled", Value = Bhop.Settings.Spider.Enabled,
        Callback = function(v) Bhop.Settings.Spider.Enabled = v end })
    spiderSec:AddSlider({ Name = "Wall Range", Value = Bhop.Settings.Spider.Range,
        Min = 1, Max = 10, Decimals = 1,
        Callback = function(v) Bhop.Settings.Spider.Range = v end })
    spiderSec:AddSlider({ Name = "Ray Count", Value = Bhop.Settings.Spider.RayCount,
        Min = 4, Max = 24,
        Callback = function(v) Bhop.Settings.Spider.RayCount = v end })

    local speedSec = MovementTab:CreateSection({ Name = "Speed", Side = "Right" })
    speedSec:AddToggle({ Name = "Enabled", Value = Speed.Settings.Enabled,
        Callback = function(v) Speed.Settings.Enabled = v end })
    speedSec:AddDropdown({ Name = "Method", Value = Speed.Settings.Method or "WalkSpeed", List = speedMethods,
        Callback = function(v) Speed.Settings.Method = v end })
    speedSec:AddSlider({ Name = "Ground Speed", Value = Speed.Settings.GroundSpeed or 30, Min = 1, Max = 500,
        Callback = function(v) Speed.Settings.GroundSpeed = v end })
    speedSec:AddToggle({ Name = "Use Different Air Speed", Value = Speed.Settings.UseAirSpeed or false,
        Callback = function(v) Speed.Settings.UseAirSpeed = v end })
    speedSec:AddSlider({ Name = "Air Speed", Value = Speed.Settings.AirSpeed or 30, Min = 1, Max = 500,
        Callback = function(v) Speed.Settings.AirSpeed = v end })
    speedSec:AddToggle({ Name = "In Air Only", Value = Speed.Settings.InAirOnly or false,
        Callback = function(v) Speed.Settings.InAirOnly = v end })

    local fsSec = MovementTab:CreateSection({ Name = "FastStop" })
    fsSec:AddToggle({ Name = "Enabled", Value = FastStop.Settings.Enabled,
        Callback = function(v) FastStop.Settings.Enabled = v end })
    fsSec:AddToggle({ Name = "Also stop Y velocity (falling)", Value = FastStop.Settings.StopY or false,
        Callback = function(v) FastStop.Settings.StopY = v end })

    local noclipSec = MovementTab:CreateSection({ Name = "Noclip", Side = "Right" })
    noclipSec:AddToggle({ Name = "Enabled", Value = Noclip.Settings.Enabled,
        Callback = function(v) Noclip.Settings.Enabled = v end })

    --// SETTINGS
    H.Logging = H.Logging or { Enabled = true, ShowHit = true, ShowMiss = true, Duration = 1, FontSize = 18 }
    H.Sound = H.Sound or { HitsoundEnabled = false, HitsoundID = 83717596220569, HitsoundVolume = 1, KillsoundEnabled = false, KillsoundID = 83717596220569, KillsoundVolume = 1 }

    local soundIDs = {
        gamesense  = 83717596220569,
        neverlose  = 139452805868562,
        crit       = 122699784909910,
        primordial = 97511223764004,
    }

    local logSec = SettingsTab:CreateSection({ Name = "Shot Logs & Sounds" })
    logSec:AddToggle({ Name = "Logs Enabled", Value = H.Logging.Enabled,
        Callback = function(v) H.Logging.Enabled = v end })
    logSec:AddToggle({ Name = "Show Hits", Value = H.Logging.ShowHit,
        Callback = function(v) H.Logging.ShowHit = v end })
    logSec:AddToggle({ Name = "Show Misses", Value = H.Logging.ShowMiss,
        Callback = function(v) H.Logging.ShowMiss = v end })
    logSec:AddSlider({ Name = "Duration (s)", Value = H.Logging.Duration,
        Min = 0.5, Max = 5, Decimals = 1,
        Callback = function(v) H.Logging.Duration = v end })
    logSec:AddSlider({ Name = "Font Size", Value = H.Logging.FontSize,
        Min = 12, Max = 30,
        Callback = function(v) H.Logging.FontSize = v end })
    logSec:AddToggle({ Name = "Hitsound Enabled", Value = H.Sound.HitsoundEnabled,
        Callback = function(v) H.Sound.HitsoundEnabled = v end })
    logSec:AddDropdown({ Name = "Hitsound", Value = "gamesense",
        List = { "gamesense", "neverlose", "crit", "primordial" },
        Callback = function(v) H.Sound.HitsoundID = soundIDs[v] end })
    logSec:AddSlider({ Name = "Hitsound Volume", Value = H.Sound.HitsoundVolume,
        Min = 0, Max = 10, Decimals = 1,
        Callback = function(v) H.Sound.HitsoundVolume = v end })
    logSec:AddToggle({ Name = "Killsound Enabled", Value = H.Sound.KillsoundEnabled,
        Callback = function(v) H.Sound.KillsoundEnabled = v end })
    logSec:AddDropdown({ Name = "Killsound", Value = "gamesense",
        List = { "gamesense", "neverlose", "crit", "primordial" },
        Callback = function(v) H.Sound.KillsoundID = soundIDs[v] end })
    logSec:AddSlider({ Name = "Killsound Volume", Value = H.Sound.KillsoundVolume,
        Min = 0, Max = 10, Decimals = 1,
        Callback = function(v) H.Sound.KillsoundVolume = v end })

    local cfgSec = SettingsTab:CreateSection({ Name = "Configs", Side = "Right" })
    local currentConfigName = "default"
    local cfgNameBox = cfgSec:AddTextbox({
        Name = "Config Name", Value = currentConfigName,
        Callback = function(v) currentConfigName = v end,
    })
    cfgSec:AddTextbox({ Name = "Select # to Load", Value = "",
        Callback = function(v)
            local num = tonumber(v)
            if not num or num <= 0 then return end
            local list = Config_ListFiles()
            if list[num] then
                currentConfigName = list[num]
                if cfgNameBox and type(cfgNameBox.Set) == "function" then
                    pcall(function() cfgNameBox:Set(list[num]) end)
                end
                ShowError("Selected: " .. list[num])
            else
                ShowError("Index out of range (max " .. #list .. ")")
            end
        end })

    local LIST_SLOTS = 10
    local listSlots = {}
    for i = 1, LIST_SLOTS do
        listSlots[i] = cfgSec:AddTextbox({ Name = " " .. i .. ".", Value = "", Callback = function() end })
    end

    local function SetSlotText(slot, text)
        if not slot then return end
        text = text or ""
        if type(slot.Set) == "function" then pcall(function() slot:Set(text) end) end
        if type(slot.SetValue) == "function" then pcall(function() slot:SetValue(text) end) end
        pcall(function() slot.Value = text end)
    end

    local function UpdateConfigListUI()
        for i = 1, LIST_SLOTS do SetSlotText(listSlots[i], "") end
        local list  = Config_ListFiles()
        local total = #list
        for i = 1, LIST_SLOTS do
            local text = ""
            if i < LIST_SLOTS then
                if i <= total then text = list[i] end
            else
                if total > LIST_SLOTS then
                    text = "... +" .. (total - LIST_SLOTS + 1) .. " more"
                elseif i <= total then
                    text = list[i]
                end
            end
            SetSlotText(listSlots[i], text)
        end
        if total == 0 then SetSlotText(listSlots[1], "(no configs)") end
        return list
    end

    cfgSec:AddButton({ Name = "Save Config",
        Callback = function()
            if not currentConfigName or currentConfigName == "" then ShowError("Enter config name"); return end
            local ok, where = Config_Save(currentConfigName)
            if ok then
                ShowError("Saved: " .. currentConfigName .. " (" .. tostring(where) .. ")")
                UpdateConfigListUI()
            else
                ShowError("Save failed: " .. tostring(where))
            end
        end })
    cfgSec:AddButton({ Name = "Load Config",
        Callback = function()
            if not currentConfigName or currentConfigName == "" then ShowError("Enter config name"); return end
            local ok, where = Config_Load(currentConfigName)
            if ok then
                ShowError("Loaded: " .. currentConfigName)
                if H._UI.ApplyAllEnabledStates then task.defer(H._UI.ApplyAllEnabledStates) end
            else
                ShowError("Load failed: " .. tostring(where))
            end
        end })
    cfgSec:AddButton({ Name = "Delete Config",
        Callback = function()
            if not currentConfigName or currentConfigName == "" then ShowError("Enter config name"); return end
            local nameToDelete = currentConfigName
            local ok, where = Config_Delete(nameToDelete)
            if ok then
                ShowError("Deleted: " .. nameToDelete)
                currentConfigName = ""
                if cfgNameBox and type(cfgNameBox.Set) == "function" then
                    pcall(function() cfgNameBox:Set("") end)
                end
                task.defer(UpdateConfigListUI)
            else
                ShowError("Delete failed: " .. tostring(where))
            end
        end })
    cfgSec:AddButton({ Name = "Refresh List",
        Callback = function()
            local list = UpdateConfigListUI()
            ShowError("Found: " .. tostring(#list) .. " configs")
        end })

    local mainSec = SettingsTab:CreateSection({ Name = "Main" })
    mainSec:AddButton({ Name = "Reset All",
        Callback = function()
            if Aimbot.Settings then
                Aimbot.Settings.Enabled = false
                Aimbot.Settings.WallCheck = false
                Aimbot.Settings.TeamCheck = Aimbot.Settings.TeamCheck or {}
                Aimbot.Settings.TeamCheck.Enabled = true
                Aimbot.Settings.AutoShoot = Aimbot.Settings.AutoShoot or {}
                Aimbot.Settings.AutoShoot.Enabled = false
            end
            if Aimbot.FOVSettings then Aimbot.FOVSettings.Enabled = true end
            if WallHack.Functions and WallHack.Functions.ResetSettings then
                pcall(WallHack.Functions.ResetSettings)
            end
            if AntiAim.Functions and AntiAim.Functions.ResetSettings then
                pcall(AntiAim.Functions.ResetSettings)
            end
            if ServerPosition.Settings then
                ServerPosition.Settings.Enabled = false
                pcall(StopServerPosition)
            end
            if Fly.Functions and Fly.Functions.ResetSettings then pcall(Fly.Functions.ResetSettings) end
            if Bhop.Functions and Bhop.Functions.ResetSettings then pcall(Bhop.Functions.ResetSettings) end
            if Speed.Functions and Speed.Functions.ResetSettings then pcall(Speed.Functions.ResetSettings) end
            if FastStop.Functions and FastStop.Functions.ResetSettings then pcall(FastStop.Functions.ResetSettings) end
            if AutoStrafer.Functions and AutoStrafer.Functions.ResetSettings then pcall(AutoStrafer.Functions.ResetSettings) end
            if Noclip.Functions and Noclip.Functions.ResetSettings then pcall(Noclip.Functions.ResetSettings) end
            if Library and Library.ResetAll then pcall(function() Library.ResetAll() end) end
            pcall(ApplyGlowToAll)
            ShowError("All settings reset")
        end })
    mainSec:AddButton({ Name = "Rejoin",
        Callback = function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end })
    mainSec:AddButton({ Name = "Server Hop",
        Callback = function()
            local ok, data = pcall(function()
                local body
                if type(game.HttpGet) == "function" then
                    body = game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?limit=100")
                elseif type(request) == "function" then
                    body = request({ Url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?limit=100", Method = "GET" }).Body
                end
                return HttpService:JSONDecode(body or "")
            end)
            if not ok or not data then ShowError("ServerHop failed"); return end
            local servers = {}
            for _, v in ipairs(data.data or {}) do
                if v.playing and v.id ~= game.JobId then servers[#servers + 1] = v.id end
            end
            if #servers > 0 then
                TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[math.random(1, #servers)], LocalPlayer)
            else
                ShowError("No other servers")
            end
        end })
    mainSec:AddButton({ Name = "Exit (Unload All)",
        Callback = function() if H._UI.SafeUnload then H._UI.SafeUnload() end end })

    task.defer(UpdateConfigListUI)
    ShowError("AirHub UI ready")
end)
