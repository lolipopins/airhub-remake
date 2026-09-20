--// AirHub - 07b_ui_tabs.lua
--// Visuals, Anti-Aim, Spoof Anims, Movement, Settings tabs.

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

    local Aimbot         = H.Aimbot
    local WallHack       = H.WallHack
    local AntiAim        = H.AntiAim
    local ServerPosition = H.ServerPosition
    local Fly            = H.Fly
    local Bhop           = H.Bhop
    local Speed          = H.Speed
    local FastStop       = H.FastStop
    local AutoStrafer    = H.AutoStrafer
    local Noclip         = H.Noclip

    local CancelLock          = Aimbot.CancelLock
    local ApplyGlowToAll      = WallHack.ApplyGlowToAll
    local StartServerPosition = ServerPosition.Start
    local StopServerPosition  = ServerPosition.Stop
    local Fly_ClearInstances  = Fly.ClearInstances
    local StopDesync          = AntiAim.StopDesync
    local StartDesync         = AntiAim.StartDesync

    local Library          = H._UI.Library
    local Config_Save      = H.Config.Save
    local Config_Load      = H.Config.Load
    local Config_Delete    = H.Config.Delete
    local Config_ListFiles = H.Config.ListFiles

    local VisualsTab   = H._UI.VisualsTab
    local AntiTab      = H._UI.AntiTab
    local SpoofAnimTab = H._UI.SpoofAnimTab
    local MovementTab  = H._UI.MovementTab
    local SettingsTab  = H._UI.SettingsTab

    local glowModes = { "Outline", "Fill", "Both", "Pulse" }

    --// =====================================================================
    --// VISUALS TAB
    --// =====================================================================
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
        Callback = function(v) WallHack.Functions.SetHUDEnabled(v) end })
    hudSec:AddDropdown({ Name = "Position", Value = "TopLeft",
        List = { "TopLeft", "TopRight", "BottomLeft", "BottomRight" },
        Callback = function(v) WallHack.Visuals.HUDSettings.Position = v end })
    hudSec:AddToggle({ Name = "Show Players count", Value = WallHack.Visuals.HUDSettings.ShowPlayers,
        Callback = function(v) WallHack.Visuals.HUDSettings.ShowPlayers = v end })
    hudSec:AddToggle({ Name = "Show FPS", Value = WallHack.Visuals.HUDSettings.ShowFPS,
        Callback = function(v) WallHack.Visuals.HUDSettings.ShowFPS = v end })
    hudSec:AddToggle({ Name = "Show Ping", Value = WallHack.Visuals.HUDSettings.ShowPing,
        Callback = function(v) WallHack.Visuals.HUDSettings.ShowPing = v end })
    hudSec:AddToggle({ Name = "Show Session time", Value = WallHack.Visuals.HUDSettings.ShowSession,
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
    glowSec:AddDropdown({ Name = "Mode", Value = WallHack.Visuals.GlowSettings.Mode,
        List = glowModes,
        Callback = function(v)
            WallHack.Visuals.GlowSettings.Mode = type(v) == "string" and v or "Outline"
            ApplyGlowToAll()
        end })

    local seSec = VisualsTab:CreateSection({ Name = "Self ESP", Side = "Right" })
    seSec:AddToggle({ Name = "Enable Self ESP", Value = WallHack.Visuals.SelfESP.Enabled,
        Callback = function(v)
            WallHack.Visuals.SelfESP.Enabled = v
            if v then WallHack.Functions.StartSelfESP() else WallHack.Functions.StopSelfESP() end
        end })

    seSec:AddToggle({ Name = "  Chams: Enabled", Value = WallHack.Visuals.SelfESP.Chams.Enabled,
        Callback = function(v)
            WallHack.Visuals.SelfESP.Chams.Enabled = v
            WallHack.Functions.RefreshSelfESP()
        end })
    seSec:AddDropdown({ Name = "  Chams: Mode", Value = "Both",
        List = { "Fill", "Outline", "Both" },
        Callback = function(v)
            WallHack.Visuals.SelfESP.Chams.Mode = v
            WallHack.Functions.RefreshSelfESP()
        end })
    seSec:AddColorpicker({ Name = "  Chams: Fill Color",
        Value = WallHack.Visuals.SelfESP.Chams.FillColor,
        Callback = function(v)
            WallHack.Visuals.SelfESP.Chams.FillColor = SanitizeColor(v)
            WallHack.Functions.RefreshSelfESP()
        end })
    seSec:AddSlider({ Name = "  Chams: Fill Transparency",
        Value = WallHack.Visuals.SelfESP.Chams.FillTransparency,
        Min = 0, Max = 1, Decimals = 2,
        Callback = function(v)
            WallHack.Visuals.SelfESP.Chams.FillTransparency = v
            WallHack.Functions.RefreshSelfESP()
        end })
    seSec:AddColorpicker({ Name = "  Chams: Outline Color",
        Value = WallHack.Visuals.SelfESP.Chams.OutlineColor,
        Callback = function(v)
            WallHack.Visuals.SelfESP.Chams.OutlineColor = SanitizeColor(v)
            WallHack.Functions.RefreshSelfESP()
        end })
    seSec:AddSlider({ Name = "  Chams: Outline Transparency",
        Value = WallHack.Visuals.SelfESP.Chams.OutlineTransparency,
        Min = 0, Max = 1, Decimals = 2,
        Callback = function(v)
            WallHack.Visuals.SelfESP.Chams.OutlineTransparency = v
            WallHack.Functions.RefreshSelfESP()
        end })
    seSec:AddToggle({ Name = "  Chams: Always on top",
        Value = WallHack.Visuals.SelfESP.Chams.AlwaysOnTop,
        Callback = function(v)
            WallHack.Visuals.SelfESP.Chams.AlwaysOnTop = v
            WallHack.Functions.RefreshSelfESP()
        end })

    seSec:AddToggle({ Name = "  China Hat: Enabled", Value = WallHack.Visuals.SelfESP.ChinaHat.Enabled,
        Callback = function(v)
            WallHack.Visuals.SelfESP.ChinaHat.Enabled = v
            WallHack.Functions.RefreshSelfESP()
        end })
    seSec:AddColorpicker({ Name = "  China Hat: Color",
        Value = WallHack.Visuals.SelfESP.ChinaHat.Color,
        Callback = function(v)
            WallHack.Visuals.SelfESP.ChinaHat.Color = SanitizeColor(v)
            WallHack.Functions.RefreshSelfESP()
        end })
    seSec:AddSlider({ Name = "  China Hat: Size", Value = WallHack.Visuals.SelfESP.ChinaHat.Size,
        Min = 1, Max = 10, Decimals = 1,
        Callback = function(v)
            WallHack.Visuals.SelfESP.ChinaHat.Size = v
            WallHack.Functions.RefreshSelfESP()
        end })
    seSec:AddSlider({ Name = "  China Hat: Offset Y", Value = WallHack.Visuals.SelfESP.ChinaHat.OffsetY,
        Min = 0, Max = 5, Decimals = 1,
        Callback = function(v)
            WallHack.Visuals.SelfESP.ChinaHat.OffsetY = v
            WallHack.Functions.RefreshSelfESP()
        end })
    seSec:AddSlider({ Name = "  China Hat: Rotation",
        Value = WallHack.Visuals.SelfESP.ChinaHat.Rotation,
        Min = 0, Max = 360,
        Callback = function(v)
            WallHack.Visuals.SelfESP.ChinaHat.Rotation = v
            WallHack.Functions.RefreshSelfESP()
        end })
    seSec:AddSlider({ Name = "  China Hat: Transparency", Value = WallHack.Visuals.SelfESP.ChinaHat.Transparency,
        Min = 0, Max = 1, Decimals = 2,
        Callback = function(v)
            WallHack.Visuals.SelfESP.ChinaHat.Transparency = v
            WallHack.Functions.RefreshSelfESP()
        end })
    seSec:AddDropdown({ Name = "  China Hat: Material", Value = "Neon",
        List = { "Neon", "ForceField", "Glass", "Plastic", "SmoothPlastic", "Metal" },
        Callback = function(v)
            WallHack.Visuals.SelfESP.ChinaHat.Material = v
            WallHack.Functions.RefreshSelfESP()
        end })

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

    --// =====================================================================
    --// ANTI-AIM TAB
    --// =====================================================================
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

    --// Amount and Speed as textboxes → any number
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
    desyncSec:AddDropdown({ Name = "Mode", Value = AntiAim.Desync.Settings.Mode, List = desyncModes,
        Callback = function(v)
            AntiAim.Desync.Settings.Mode = v
            if AntiAim.Desync.Settings.Enabled then StopDesync(); task.wait(0.05); StartDesync() end
        end })

    desyncSec:AddToggle({ Name = "Random Rotate (pitch/yaw/roll)", Value = AntiAim.Desync.Settings.RandomRotate,
        Callback = function(v) AntiAim.Desync.Settings.RandomRotate = v end })

    desyncSec:AddTextbox({ Name = "X", Value = tostring(AntiAim.Desync.Settings.X),
        Callback = function(v)
            local n = tonumber(v)
            if n then AntiAim.Desync.Settings.X = n end
        end })
    desyncSec:AddTextbox({ Name = "Y", Value = tostring(AntiAim.Desync.Settings.Y),
        Callback = function(v)
            local n = tonumber(v)
            if n then AntiAim.Desync.Settings.Y = n end
        end })
    desyncSec:AddTextbox({ Name = "Z", Value = tostring(AntiAim.Desync.Settings.Z),
        Callback = function(v)
            local n = tonumber(v)
            if n then AntiAim.Desync.Settings.Z = n end
        end })
    desyncSec:AddToggle({ Name = "Random (X/Y/Z = max range)", Value = AntiAim.Desync.Settings.Random,
        Callback = function(v) AntiAim.Desync.Settings.Random = v end })
    desyncSec:AddSlider({ Name = "Update Interval", Value = AntiAim.Desync.Settings.UpdateInterval,
        Min = 0.01, Max = 1, Decimals = 2,
        Callback = function(v) AntiAim.Desync.Settings.UpdateInterval = v end })

    --// OldPosition
    desyncSec:AddToggle({ Name = "OldPosition Delay Enabled", Value = AntiAim.Desync.Settings.OldPosDelayEnabled,
        Callback = function(v) AntiAim.Desync.Settings.OldPosDelayEnabled = v end })
    desyncSec:AddSlider({ Name = "OldPosition Delay (s)", Value = AntiAim.Desync.Settings.OldPosDelay,
        Min = 0.01, Max = 5, Decimals = 2,
        Callback = function(v) AntiAim.Desync.Settings.OldPosDelay = v end })

    --// Void
    desyncSec:AddSlider({ Name = "Void Depth (Y)", Value = AntiAim.Desync.Settings.VoidDepth,
        Min = -5000, Max = -100,
        Callback = function(v) AntiAim.Desync.Settings.VoidDepth = v end })

    --// InPlayer
    desyncSec:AddSlider({ Name = "InPlayer Offset (studs)", Value = AntiAim.Desync.Settings.InPlayerOffset,
        Min = 0, Max = 20, Decimals = 1,
        Callback = function(v) AntiAim.Desync.Settings.InPlayerOffset = v end })

    desyncSec:AddToggle({ Name = "Refresh position on shot", Value = AntiAim.Desync.Settings.RefreshOnShot,
        Callback = function(v) AntiAim.Desync.Settings.RefreshOnShot = v end })
    desyncSec:AddButton({ Name = "Save Current Position",
        Callback = function()
            local ok = AntiAim.Functions.SaveOldPosition()
            if ok then ShowError("Old position saved") else ShowError("No character") end
        end })

    --// =====================================================================
    --// SPOOF ANIMATIONS TAB
    --// =====================================================================
    local animPriorities = {
        "Core", "Idle", "Movement", "Action", "Action2", "Action3", "Action4",
    }

    local saMain = SpoofAnimTab:CreateSection({ Name = "Spoof Animation" })
    saMain:AddToggle({ Name = "Enabled", Value = AntiAim.SpoofAnim.Settings.Enabled,
        Callback = function(v)
            AntiAim.SpoofAnim.Settings.Enabled = v
            if v then AntiAim.SpoofAnim.Functions.Start() else AntiAim.SpoofAnim.Functions.Stop() end
        end })

    --// ID box + quick buttons
    local animIdBox = saMain:AddTextbox({
        Name = "Animation ID",
        Value = AntiAim.SpoofAnim.Settings.AnimationId,
        Callback = function(v)
            AntiAim.SpoofAnim.Settings.AnimationId = v
            AntiAim.SpoofAnim.Functions.Restart()
        end,
    })

    saMain:AddButton({ Name = "Play Spoof",
        Callback = function()
            AntiAim.SpoofAnim.Functions.Restart()
            ShowError("Spoof animation reloaded")
        end })
    saMain:AddButton({ Name = "Stop Spoof",
        Callback = function()
            AntiAim.SpoofAnim.Functions.Stop()
            ShowError("Spoof animation stopped")
        end })

    saMain:AddTextbox({ Name = "Speed (any number)", Value = tostring(AntiAim.SpoofAnim.Settings.Speed),
        Callback = function(v)
            local n = tonumber(v)
            if n then
                AntiAim.SpoofAnim.Settings.Speed = n
                AntiAim.SpoofAnim.Functions.Restart()
            end
        end })
    saMain:AddToggle({ Name = "Looped", Value = AntiAim.SpoofAnim.Settings.Looped,
        Callback = function(v)
            AntiAim.SpoofAnim.Settings.Looped = v
            local tr = AntiAim.SpoofAnim.Internal.Track
            if tr then pcall(function() tr.Looped = v end) end
        end })
    saMain:AddToggle({ Name = "Stop when moving", Value = AntiAim.SpoofAnim.Settings.StopOnMove,
        Callback = function(v) AntiAim.SpoofAnim.Settings.StopOnMove = v end })
    saMain:AddDropdown({ Name = "Priority", Value = AntiAim.SpoofAnim.Settings.Priority, List = animPriorities,
        Callback = function(v)
            AntiAim.SpoofAnim.Settings.Priority = v
            AntiAim.SpoofAnim.Functions.Restart()
        end })

    --// Presets (right column)
    local saPresets = SpoofAnimTab:CreateSection({ Name = "Presets", Side = "Right" })

    local PRESETS = {
        { name = "Dance (Floss)",     id = "rbxassetid://10407164740" },
        { name = "Dab",               id = "rbxassetid://4673728251" },
        { name = "Russian Dance",     id = "rbxassetid://4690431229" },
        { name = "Gangnam Style",     id = "rbxassetid://4609414737" },
        { name = "Default Idle",      id = "rbxassetid://507766666" },
        { name = "Default Walk",      id = "rbxassetid://507777826" },
        { name = "R6 Fall",           id = "rbxassetid://180436148" },
        { name = "R6 Climb",          id = "rbxassetid://180436334" },
    }

    for _, p in ipairs(PRESETS) do
        saPresets:AddButton({
            Name = p.name,
            Callback = function()
                AntiAim.SpoofAnim.Settings.AnimationId = p.id
                if animIdBox and type(animIdBox.Set) == "function" then
                    pcall(function() animIdBox:Set(p.id) end)
                end
                AntiAim.SpoofAnim.Functions.Restart()
                ShowError("Preset loaded: " .. p.name)
            end,
        })
    end

    --// =====================================================================
    --// MOVEMENT TAB
    --// =====================================================================
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
            if not v then AutoStrafer.Functions.Stop() end
        end })
    asSec:AddDropdown({ Name = "Key", Value = AutoStrafer.Settings.Key, List = strafeKeys,
        Callback = function(v) AutoStrafer.Settings.Key = v end })
    asSec:AddToggle({ Name = "Toggle Mode", Value = AutoStrafer.Settings.Toggle,
        Callback = function(v) AutoStrafer.Settings.Toggle = v end })
    asSec:AddDropdown({ Name = "Mode", Value = AutoStrafer.Settings.Mode, List = strafeModes,
        Callback = function(v) AutoStrafer.Settings.Mode = v end })
    asSec:AddToggle({ Name = "Invert", Value = AutoStrafer.Settings.Invert,
        Callback = function(v) AutoStrafer.Settings.Invert = v end })
    asSec:AddSlider({ Name = "Spam Delay (Spam mode)", Value = AutoStrafer.Settings.SpamDelay,
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
    flySec:AddDropdown({ Name = "Method", Value = Fly.Settings.Method, List = flyMethods,
        Callback = function(v) Fly.Settings.Method = v; Fly_ClearInstances() end })
    flySec:AddDropdown({ Name = "Key", Value = Fly.Settings.ToggleKey, List = flyKeys,
        Callback = function(v) Fly.Settings.ToggleKey = v end })
    flySec:AddToggle({ Name = "Toggle Mode", Value = Fly.Settings.Toggle,
        Callback = function(v) Fly.Settings.Toggle = v end })
    flySec:AddSlider({ Name = "Speed", Value = Fly.Settings.Speed, Min = 1, Max = 200,
        Callback = function(v) Fly.Settings.Speed = v end })
    flySec:AddSlider({ Name = "Up/Down Speed", Value = Fly.Settings.UpSpeed, Min = 1, Max = 200,
        Callback = function(v) Fly.Settings.UpSpeed = v end })
    flySec:AddSlider({ Name = "Smoothness", Value = Fly.Settings.Smoothness,
        Min = 0.05, Max = 1, Decimals = 2,
        Callback = function(v) Fly.Settings.Smoothness = v end })
    flySec:AddToggle({ Name = "Use WASD + Space/Ctrl", Value = Fly.Settings.UseKeys,
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
    bhopSec:AddDropdown({ Name = "Jump Key", Value = Bhop.Settings.AutoJumpKey, List = bhopKeys,
        Callback = function(v) Bhop.Settings.AutoJumpKey = v end })
    bhopSec:AddToggle({ Name = "Bypass Jump Restrictions", Value = Bhop.Settings.BypassJump,
        Callback = function(v) Bhop.Settings.BypassJump = v end })
    bhopSec:AddSlider({ Name = "Jump Cooldown", Value = Bhop.Settings.JumpCooldown,
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
    speedSec:AddDropdown({ Name = "Method", Value = Speed.Settings.Method, List = speedMethods,
        Callback = function(v) Speed.Settings.Method = v end })
    speedSec:AddSlider({ Name = "Ground Speed", Value = Speed.Settings.GroundSpeed, Min = 1, Max = 500,
        Callback = function(v) Speed.Settings.GroundSpeed = v end })
    speedSec:AddToggle({ Name = "Use Different Air Speed", Value = Speed.Settings.UseAirSpeed,
        Callback = function(v) Speed.Settings.UseAirSpeed = v end })
    speedSec:AddSlider({ Name = "Air Speed", Value = Speed.Settings.AirSpeed, Min = 1, Max = 500,
        Callback = function(v) Speed.Settings.AirSpeed = v end })
    speedSec:AddToggle({ Name = "In Air Only", Value = Speed.Settings.InAirOnly,
        Callback = function(v) Speed.Settings.InAirOnly = v end })

    local fsSec = MovementTab:CreateSection({ Name = "FastStop" })
    fsSec:AddToggle({ Name = "Enabled", Value = FastStop.Settings.Enabled,
        Callback = function(v) FastStop.Settings.Enabled = v end })
    fsSec:AddToggle({ Name = "Also stop Y velocity (falling)", Value = FastStop.Settings.StopY,
        Callback = function(v) FastStop.Settings.StopY = v end })

    local noclipSec = MovementTab:CreateSection({ Name = "Noclip", Side = "Right" })
    noclipSec:AddToggle({ Name = "Enabled", Value = Noclip.Settings.Enabled,
        Callback = function(v) Noclip.Settings.Enabled = v end })

    --// =====================================================================
    --// SETTINGS TAB
    --// =====================================================================
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
        Name = "Config Name",
        Value = currentConfigName,
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
            Aimbot.Settings = {
                Enabled = false,
                TeamCheck = { Enabled = true, Mode = "Enemies", TreatNeutralAsEnemy = true },
                AliveCheck = true,
                WallCheck = false,
                FallbackToVisible = false,
                WallCheckMode = "Perfect",
                DelayShot = true,
                AimSmoothingSpeed = 6,
                TriggerKey = "MouseButton2",
                Toggle = false,
                LockPart = "Head",
                AimMethod = "Smooth",
                SilentAim = true,
                SilentAimMode = "Camera",
                IgnoreFOV = false,
                CheckFromPlayerOnTP = true,
                PredictionEnabled = false,
                PredictionX = 0,
                PredictionY = 0,
                PredictionTime = 0.15,
                TargetNPCs = false,
                NPCNameFilter = "",
                AutoShoot = {
                    Enabled = false,
                    ShootKey = "MouseButton1",
                    FireRate = 0.05,
                    OnlyWhenAiming = true,
                    AutoStop = { Enabled = false, Time = 0.1 },
                },
            }
            Aimbot.FOVSettings = { Enabled = true, Visible = true, Amount = 90 }
            pcall(CancelLock)
            WallHack.Functions.ResetSettings()
            AntiAim.Functions.ResetSettings()
            ServerPosition.Settings = { Enabled = false, RGB = true, Strength = 1, MaxLimb = 6 }
            StopServerPosition()
            Fly.Functions.ResetSettings()
            Bhop.Functions.ResetSettings()
            Speed.Functions.ResetSettings()
            FastStop.Functions.ResetSettings()
            AutoStrafer.Functions.ResetSettings()
            Noclip.Functions.ResetSettings()
            H.Logging = { Enabled = true, ShowHit = true, ShowMiss = true, Duration = 1, FontSize = 18 }
            H.Sound = {
                HitsoundEnabled = false, HitsoundID = 83717596220569, HitsoundVolume = 1,
                KillsoundEnabled = false, KillsoundID = 83717596220569, KillsoundVolume = 1,
            }
            if Library and Library.ResetAll then pcall(function() Library.ResetAll() end) end
            ApplyGlowToAll()
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
