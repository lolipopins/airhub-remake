-- UI.lua – графический интерфейс, конфиги, кнопки
task.delay(math.random(1,3), function()
    local Library = loadstring(game:GetObjects("rbxassetid://7657867786")[1].Source)()
    local teamModes = {"Enemies","Allies","All","IgnoreNeutrals"}
    local dashModes = {"Camera", "Player", "Movement"}
    local aaModes = {"Static", "Spin", "Jitter", "Dynamic"}
    local refModes = {"Camera", "Movement", "Player"}
    local bhopModes = {"Auto", "Hold"}
    local teleModes = {"Single", "Stick"}
    local fireRateModes = {"Manual", "MaxSpeed", "WeaponRate"}
    local glowModes = {"Outline", "Fill", "Both", "Pulse"}
    local soundIDs = { gamesense = 83717596220569, neverlose = 139452805868562, crit = 122699784909910, primordial = 97511223764004 }

    local Aimbot = getgenv().AirHub.Aimbot
    local WallHack = getgenv().AirHub.WallHack
    local AntiAim = getgenv().AirHub.AntiAim
    local Fly = getgenv().AirHub.Fly
    local BHop = getgenv().AirHub.BunnyHop
    local BackTeleport = getgenv().AirHub.BackTeleport
    local DashTeleport = getgenv().AirHub.DashTeleport
    local ThirdPerson = getgenv().AirHub.ThirdPerson

    local function SaveConfig()
        local cfg = {
            Aimbot = Aimbot.Settings, FOV = Aimbot.FOVSettings,
            WallHack = WallHack.Settings, Box = WallHack.Visuals.BoxSettings,
            Glow = WallHack.Visuals.GlowSettings,
            AntiAim = AntiAim.Settings,
            Fly = Fly.Settings,
            BunnyHop = BHop.Settings,
            BackTeleport = BackTeleport.Settings,
            DashTeleport = DashTeleport.Settings,
            ThirdPerson = ThirdPerson.Settings,
            RTX = WallHack.RTX.Enabled,
            RTXSettings = WallHack.RTX.Settings,
            Logging = getgenv().AirHub.Logging,
            Sound = getgenv().AirHub.Sound,
            Character = getgenv().AirHub.Character,
        }
        setclipboard(HttpService:JSONEncode(cfg))
        ShowError("✅ Config saved")
    end

    local function LoadConfig()
        local json = getclipboard()
        if not json or json == "" then ShowError("❌ Clipboard empty") return end
        local ok, cfg = pcall(HttpService.JSONDecode, HttpService, json)
        if not ok then ShowError("❌ Invalid config") return end
        if cfg.Aimbot then for k, v in pairs(cfg.Aimbot) do if type(v) == "table" then for k2, v2 in pairs(v) do Aimbot.Settings[k][k2] = v2 end else Aimbot.Settings[k] = v end end end
        if cfg.FOV then for k, v in pairs(cfg.FOV) do Aimbot.FOVSettings[k] = v end end
        if cfg.WallHack then for k, v in pairs(cfg.WallHack) do WallHack.Settings[k] = v end end
        if cfg.Box then for k, v in pairs(cfg.Box) do WallHack.Visuals.BoxSettings[k] = v end end
        if cfg.Glow then for k, v in pairs(cfg.Glow) do WallHack.Visuals.GlowSettings[k] = v end end
        if cfg.AntiAim then for k, v in pairs(cfg.AntiAim) do if type(v) == "table" then for k2, v2 in pairs(v) do AntiAim.Settings[k][k2] = v2 end else AntiAim.Settings[k] = v end end end
        if cfg.Fly then for k, v in pairs(cfg.Fly) do Fly.Settings[k] = v end end
        if cfg.BunnyHop then for k, v in pairs(cfg.BunnyHop) do BHop.Settings[k] = v end end
        if cfg.BackTeleport then for k, v in pairs(cfg.BackTeleport) do BackTeleport.Settings[k] = v end end
        if cfg.DashTeleport then for k, v in pairs(cfg.DashTeleport) do DashTeleport.Settings[k] = v end end
        if cfg.ThirdPerson then for k, v in pairs(cfg.ThirdPerson) do ThirdPerson.Settings[k] = v end end
        if cfg.RTX ~= nil then
            WallHack.RTX.Enabled = cfg.RTX
            if cfg.RTX then EnableRTX() else DisableRTX() end
        end
        if cfg.RTXSettings then
            for k, v in pairs(cfg.RTXSettings) do
                if k == "ColorCorrection" or k == "Bloom" or k == "SunRays" or k == "DepthOfField" then
                    for k2, v2 in pairs(v) do WallHack.RTX.Settings[k][k2] = v2 end
                else
                    WallHack.RTX.Settings[k] = v
                end
            end
            if WallHack.RTX.Enabled then ApplyRTXSettings() end
        end
        if cfg.Logging then for k, v in pairs(cfg.Logging) do getgenv().AirHub.Logging[k] = v end end
        if cfg.Sound then for k, v in pairs(cfg.Sound) do getgenv().AirHub.Sound[k] = v end end
        if cfg.Character then
            if cfg.Character.HatESP then for k, v in pairs(cfg.Character.HatESP) do getgenv().AirHub.Character.HatESP[k] = v end end
            getgenv().AirHub.Character.Transparent = cfg.Character.Transparent
            getgenv().AirHub.Character.Transparency = cfg.Character.Transparency
        end
        if Library.ResetAll then Library.ResetAll() end
        ApplyGlowToAll()
        UpdateCharacterTransparency()
        UpdateHatESP()
        ShowError("✅ Config loaded")
    end

    local function Rejoin() TeleportService:Teleport(game.PlaceId, LocalPlayer) end
    local function ServerHop()
        local data = HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?limit=100"))
        local servers = {}
        for _, v in ipairs(data.data) do
            if v.playing and v.id ~= game.JobId then servers[#servers+1] = v.id end
        end
        if #servers > 0 then TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[math.random(1,#servers)], LocalPlayer)
        else ShowError("No other servers") end
    end

    UserInputService.InputBegan:Connect(function(inp)
        if inp.KeyCode == Enum.KeyCode.RightShift then
            MenuVisible = not MenuVisible
            if MenuVisible then Library:Show() else Library:Hide() end
        end
    end)

    Library.UnloadCallback = function()
        Aimbot.FOVCircle:Remove()
        WallHack.Functions.Exit()
        AntiAim.Functions.Exit()
        if Fly.Internal.Active then
            Fly.Internal.BodyVelocity:Destroy()
            Fly.Internal.BodyVelocity = nil
            Fly.Internal.Active = false
            local char = LocalPlayer.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then hum.PlatformStand = false end
            end
        end
        BackTeleport.Internal.Active = false
        ErrorText:Remove()
        for _, log in ipairs(ActiveLogs) do log.text:Remove() end
        ActiveLogs = {}
        if Hitsound then Hitsound:Destroy() end
        if Killsound then Killsound:Destroy() end
        for _, obj in ipairs(HatLines) do
            pcall(function() obj:Remove() end)
        end
        HatLines = {}
        getgenv().AirHub = nil
    end

    local MainFrame = Library:CreateWindow({
        Name = "AirHub",
        Themeable = { Image = "96742921028995", Info = "360° Aimbot + Sounds | Hat ESP (цилиндр) | WeaponRate | RTX | Logs | Silent Aim", Credit = false }
    })
    local AimbotTab = MainFrame:CreateTab({ Name = "Aimbot" })
    local VisualsTab = MainFrame:CreateTab({ Name = "Visuals" })
    local AntiTab = MainFrame:CreateTab({ Name = "Anti-Aim" })
    local MovementTab = MainFrame:CreateTab({ Name = "Movement" })
    local CharacterTab = MainFrame:CreateTab({ Name = "Character" })
    local RTXTab = MainFrame:CreateTab({ Name = "RTX" })
    local SettingsTab = MainFrame:CreateTab({ Name = "Settings" })

    -- Aimbot UI
    local secA = AimbotTab:CreateSection({ Name = "Main" })
    secA:AddToggle({ Name = "Enabled", Value = Aimbot.Settings.Enabled, Callback = function(v) Aimbot.Settings.Enabled = v end })
    secA:AddToggle({ Name = "Toggle", Value = Aimbot.Settings.Toggle, Callback = function(v) Aimbot.Settings.Toggle = v end })
    secA:AddToggle({ Name = "360° (Ignore FOV)", Value = Aimbot.Settings.IgnoreFOV, Callback = function(v) Aimbot.Settings.IgnoreFOV = v end })
    secA:AddToggle({ Name = "Check visibility from player on TP", Value = Aimbot.Settings.CheckFromPlayerOnTP, Callback = function(v) Aimbot.Settings.CheckFromPlayerOnTP = v end })
    secA:AddDropdown({ Name = "Lock Part", Value = Aimbot.Settings.LockPart, List = {"Head","Torso","Nearest"}, Callback = function(v) Aimbot.Settings.LockPart = v end })
    secA:AddToggle({ Name = "Fallback to visible parts", Value = Aimbot.Settings.FallbackToVisible, Callback = function(v) Aimbot.Settings.FallbackToVisible = v end })
    secA:AddTextbox({ Name = "Aim Key", Value = Aimbot.Settings.TriggerKey, Callback = function(v) Aimbot.Settings.TriggerKey = v end })
    secA:AddDropdown({ Name = "Aim Method", Value = Aimbot.Settings.AimMethod, List = {"Smooth","Instant"}, Callback = function(v) Aimbot.Settings.AimMethod = v end })
    secA:AddSlider({ Name = "Smoothing Speed", Value = Aimbot.Settings.AimSmoothingSpeed, Min = 1, Max = 20, Callback = function(v) Aimbot.Settings.AimSmoothingSpeed = v end })
    secA:AddSlider({ Name = "Prediction", Value = Aimbot.Settings.AimPrediction, Min = 0, Max = 1, Decimals = 2, Callback = function(v) Aimbot.Settings.AimPrediction = v end })

    local secW = AimbotTab:CreateSection({ Name = "Visibility", Side = "Right" })
    secW:AddToggle({ Name = "WallCheck", Value = Aimbot.Settings.WallCheck, Callback = function(v) Aimbot.Settings.WallCheck = v end })
    secW:AddToggle({ Name = "Alive Check", Value = Aimbot.Settings.AliveCheck, Callback = function(v) Aimbot.Settings.AliveCheck = v end })
    secW:AddToggle({ Name = "Team Check", Value = Aimbot.Settings.TeamCheck.Enabled, Callback = function(v) Aimbot.Settings.TeamCheck.Enabled = v end })
    secW:AddDropdown({ Name = "Team Mode", Value = Aimbot.Settings.TeamCheck.Mode, List = teamModes, Callback = function(v) Aimbot.Settings.TeamCheck.Mode = v end })
    secW:AddToggle({ Name = "Treat Neutrals as Enemies", Value = Aimbot.Settings.TeamCheck.TreatNeutralAsEnemy, Callback = function(v) Aimbot.Settings.TeamCheck.TreatNeutralAsEnemy = v end })

    local secD = AimbotTab:CreateSection({ Name = "Auto Shoot", Side = "Right" })
    secD:AddToggle({ Name = "Enabled", Value = Aimbot.Settings.AutoShoot.Enabled, Callback = function(v) Aimbot.Settings.AutoShoot.Enabled = v end })
    secD:AddToggle({ Name = "Only when aiming", Value = Aimbot.Settings.AutoShoot.OnlyWhenAiming, Callback = function(v) Aimbot.Settings.AutoShoot.OnlyWhenAiming = v end })
    secD:AddDropdown({ Name = "FireRate Mode", Value = Aimbot.Settings.AutoShoot.FireRateMode, List = fireRateModes, Callback = function(v) Aimbot.Settings.AutoShoot.FireRateMode = v end })
    secD:AddTextbox({ Name = "Manual delay (s)", Value = tostring(Aimbot.Settings.AutoShoot.FireRate), Callback = function(v) local num = tonumber(v) if num then Aimbot.Settings.AutoShoot.FireRate = math.clamp(num,0.001,1) end end })
    secD:AddDropdown({ Name = "Shoot Key", Value = "Left Click", List = {"Left Click","Right Click"}, Callback = function(v) Aimbot.Settings.AutoShoot.ShootKey = (v=="Left Click") and "MouseButton1" or "MouseButton2" end })
    secD:AddToggle({ Name = "Strict WallCheck", Value = Aimbot.Settings.AutoShoot.StrictWallCheck, Callback = function(v) Aimbot.Settings.AutoShoot.StrictWallCheck = v end })
    secD:AddToggle({ Name = "AutoStop", Value = Aimbot.Settings.AutoShoot.AutoStop.Enabled, Callback = function(v) Aimbot.Settings.AutoShoot.AutoStop.Enabled = v end })
    secD:AddSlider({ Name = "Stop time (s)", Value = Aimbot.Settings.AutoShoot.AutoStop.Time, Min = 0.01, Max = 0.5, Decimals = 2, Callback = function(v) Aimbot.Settings.AutoShoot.AutoStop.Time = v end })

    local secE = AimbotTab:CreateSection({ Name = "FOV" })
    secE:AddToggle({ Name = "Enabled", Value = Aimbot.FOVSettings.Enabled, Callback = function(v) Aimbot.FOVSettings.Enabled = v end })
    secE:AddToggle({ Name = "Visible", Value = Aimbot.FOVSettings.Visible, Callback = function(v) Aimbot.FOVSettings.Visible = v end })
    secE:AddSlider({ Name = "Radius", Value = Aimbot.FOVSettings.Amount, Min = 10, Max = 300, Callback = function(v) Aimbot.FOVSettings.Amount = v end })

    -- Visuals
    local vis1 = VisualsTab:CreateSection({ Name = "WallHack" })
    vis1:AddToggle({ Name = "Enabled", Value = WallHack.Settings.Enabled, Callback = function(v) WallHack.Settings.Enabled = v; ApplyGlowToAll() end })
    vis1:AddToggle({ Name = "Team Check", Value = WallHack.Settings.TeamCheck, Callback = function(v) WallHack.Settings.TeamCheck = v end })
    vis1:AddToggle({ Name = "Alive Check", Value = WallHack.Settings.AliveCheck, Callback = function(v) WallHack.Settings.AliveCheck = v end })

    local visBox = VisualsTab:CreateSection({ Name = "Boxes" })
    visBox:AddToggle({ Name = "Enabled", Value = WallHack.Visuals.BoxSettings.Enabled, Callback = function(v) WallHack.Visuals.BoxSettings.Enabled = v end })
    visBox:AddDropdown({ Name = "Type", Value = (WallHack.Visuals.BoxSettings.Type == 1 and "3D" or "2D"), List = {"3D","2D"}, Callback = function(v) WallHack.Visuals.BoxSettings.Type = (v == "3D") and 1 or 2 end })
    visBox:AddColorpicker({ Name = "Color", Value = WallHack.Visuals.BoxSettings.Color, Callback = function(v) WallHack.Visuals.BoxSettings.Color = v end })
    visBox:AddColorpicker({ Name = "Target Color", Value = WallHack.Visuals.BoxSettings.TargetColor, Callback = function(v) WallHack.Visuals.BoxSettings.TargetColor = v end })
    visBox:AddSlider({ Name = "Transparency", Value = WallHack.Visuals.BoxSettings.Transparency, Min = 0, Max = 1, Decimals = 2, Callback = function(v) WallHack.Visuals.BoxSettings.Transparency = v end })
    visBox:AddSlider({ Name = "Thickness", Value = WallHack.Visuals.BoxSettings.Thickness, Min = 1, Max = 5, Callback = function(v) WallHack.Visuals.BoxSettings.Thickness = v end })
    visBox:AddToggle({ Name = "Filled (2D)", Value = WallHack.Visuals.BoxSettings.Filled, Callback = function(v) WallHack.Visuals.BoxSettings.Filled = v end })
    visBox:AddSlider({ Name = "Scale (3D)", Value = WallHack.Visuals.BoxSettings.Increase, Min = 1, Max = 5, Callback = function(v) WallHack.Visuals.BoxSettings.Increase = v end })

    local glowSec = VisualsTab:CreateSection({ Name = "Glow", Side = "Right" })
    glowSec:AddToggle({ Name = "Enabled", Value = WallHack.Visuals.GlowSettings.Enabled, Callback = function(v) WallHack.Visuals.GlowSettings.Enabled = v; ApplyGlowToAll() end })
    glowSec:AddColorpicker({ Name = "Color", Value = WallHack.Visuals.GlowSettings.Color, Callback = function(v) WallHack.Visuals.GlowSettings.Color = v; ApplyGlowToAll() end })
    glowSec:AddSlider({ Name = "Transparency", Value = WallHack.Visuals.GlowSettings.Transparency, Min = 0, Max = 1, Decimals = 2, Callback = function(v) WallHack.Visuals.GlowSettings.Transparency = v; ApplyGlowToAll() end })
    glowSec:AddSlider({ Name = "Thickness", Value = WallHack.Visuals.GlowSettings.Thickness, Min = 1, Max = 10, Callback = function(v) WallHack.Visuals.GlowSettings.Thickness = v; ApplyGlowToAll() end })
    glowSec:AddDropdown({ Name = "Mode", Value = WallHack.Visuals.GlowSettings.Mode, List = glowModes, Callback = function(v) WallHack.Visuals.GlowSettings.Mode = v; ApplyGlowToAll() end })

    -- Anti-Aim UI
    local aaMain = AntiTab:CreateSection({ Name = "Body (Server)" })
    aaMain:AddToggle({ Name = "Enabled", Value = AntiAim.Settings.Enabled, Callback = function(v) AntiAim.Settings.Enabled = v end })
    aaMain:AddDropdown({ Name = "Mode", Value = AntiAim.Settings.Mode, List = aaModes, Callback = function(v) AntiAim.Settings.Mode = v end })
    aaMain:AddDropdown({ Name = "Reference", Value = AntiAim.Settings.Body.Reference, List = refModes, Callback = function(v) AntiAim.Settings.Body.Reference = v end })
    aaMain:AddSlider({ Name = "Yaw", Value = AntiAim.Settings.Body.Yaw, Min = -180, Max = 180, Callback = function(v) AntiAim.Settings.Body.Yaw = v end })
    aaMain:AddSlider({ Name = "Pitch", Value = AntiAim.Settings.Body.Pitch, Min = -90, Max = 90, Callback = function(v) AntiAim.Settings.Body.Pitch = v end })
    aaMain:AddSlider({ Name = "Roll", Value = AntiAim.Settings.Body.Roll, Min = -180, Max = 180, Callback = function(v) AntiAim.Settings.Body.Roll = v end })
    aaMain:AddSlider({ Name = "Spin Speed", Value = AntiAim.Settings.Body.SpinSpeed, Min = 0, Max = 5000, Callback = function(v) AntiAim.Settings.Body.SpinSpeed = v end })
    aaMain:AddSlider({ Name = "Jitter Amount", Value = AntiAim.Settings.Body.JitterAmount, Min = 0, Max = 30, Callback = function(v) AntiAim.Settings.Body.JitterAmount = v end })
    aaMain:AddSlider({ Name = "Jitter Speed", Value = AntiAim.Settings.Body.JitterSpeed, Min = 1, Max = 60, Callback = function(v) AntiAim.Settings.Body.JitterSpeed = v end })
    aaMain:AddToggle({ Name = "Ignore when moving", Value = AntiAim.Settings.Body.IgnoreMoving, Callback = function(v) AntiAim.Settings.Body.IgnoreMoving = v end })
    aaMain:AddSlider({ Name = "Move speed threshold", Value = AntiAim.Settings.Body.MoveSpeedThreshold, Min = 0.1, Max = 5, Decimals = 2, Callback = function(v) AntiAim.Settings.Body.MoveSpeedThreshold = v end })
    aaMain:AddSlider({ Name = "Smoothness", Value = AntiAim.Settings.Smoothness, Min = 0, Max = 30, Callback = function(v) AntiAim.Settings.Smoothness = v end })

    local aaHead = AntiTab:CreateSection({ Name = "Head (Local)", Side = "Right" })
    aaHead:AddToggle({ Name = "Enable", Value = AntiAim.Settings.Head.Enabled, Callback = function(v) AntiAim.Settings.Head.Enabled = v end })
    aaHead:AddSlider({ Name = "Yaw", Value = AntiAim.Settings.Head.Yaw, Min = -180, Max = 180, Callback = function(v) AntiAim.Settings.Head.Yaw = v end })
    aaHead:AddSlider({ Name = "Pitch", Value = AntiAim.Settings.Head.Pitch, Min = -90, Max = 90, Callback = function(v) AntiAim.Settings.Head.Pitch = v end })
    aaHead:AddSlider({ Name = "Roll", Value = AntiAim.Settings.Head.Roll, Min = -180, Max = 180, Callback = function(v) AntiAim.Settings.Head.Roll = v end })

    -- Movement UI
    local speedSec = MovementTab:CreateSection({ Name = "Speed (BunnyHop)" })
    speedSec:AddToggle({ Name = "Enabled", Value = BHop.Settings.Enabled, Callback = function(v) BHop.Settings.Enabled = v end })
    speedSec:AddDropdown({ Name = "Mode", Value = BHop.Settings.Mode, List = bhopModes, Callback = function(v) BHop.Settings.Mode = v end })
    speedSec:AddTextbox({ Name = "Key", Value = BHop.Settings.Key, Callback = function(v) BHop.Settings.Key = v end })
    speedSec:AddSlider({ Name = "Speed Multiplier", Value = BHop.Settings.SpeedMultiplier, Min = 0.5, Max = 3, Decimals = 1, Callback = function(v) BHop.Settings.SpeedMultiplier = v end })

    local dashSec = MovementTab:CreateSection({ Name = "Dash Teleport" })
    dashSec:AddToggle({ Name = "Enabled", Value = DashTeleport.Settings.Enabled, Callback = function(v) DashTeleport.Settings.Enabled = v end })
    dashSec:AddTextbox({ Name = "Key", Value = DashTeleport.Settings.Key, Callback = function(v) DashTeleport.Settings.Key = v end })
    dashSec:AddDropdown({ Name = "Direction", Value = DashTeleport.Settings.Direction, List = dashModes, Callback = function(v) DashTeleport.Settings.Direction = v end })
    dashSec:AddSlider({ Name = "Distance", Value = DashTeleport.Settings.Distance, Min = 1, Max = 30, Callback = function(v) DashTeleport.Settings.Distance = v end })
    dashSec:AddSlider({ Name = "Height Offset", Value = DashTeleport.Settings.HeightOffset, Min = -5, Max = 5, Callback = function(v) DashTeleport.Settings.HeightOffset = v end })

    local backSec = MovementTab:CreateSection({ Name = "Back Teleport" })
    backSec:AddToggle({ Name = "Enabled", Value = BackTeleport.Settings.Enabled, Callback = function(v) BackTeleport.Settings.Enabled = v end })
    backSec:AddTextbox({ Name = "Hotkey", Value = BackTeleport.Settings.Hotkey, Callback = function(v) BackTeleport.Settings.Hotkey = v end })
    backSec:AddDropdown({ Name = "Mode", Value = BackTeleport.Settings.Mode, List = teleModes, Callback = function(v) BackTeleport.Settings.Mode = v; if v == "Stick" then BackTeleport.Internal.Active = false end end })
    backSec:AddSlider({ Name = "Distance", Value = BackTeleport.Settings.Distance, Min = 1, Max = 15, Callback = function(v) BackTeleport.Settings.Distance = v end })
    backSec:AddSlider({ Name = "Height Offset", Value = BackTeleport.Settings.HeightOffset, Min = -5, Max = 5, Callback = function(v) BackTeleport.Settings.HeightOffset = v end })
    backSec:AddToggle({ Name = "Auto Aim", Value = BackTeleport.Settings.AutoAim, Callback = function(v) BackTeleport.Settings.AutoAim = v end })
    backSec:AddSlider({ Name = "Stick Interval", Value = BackTeleport.Settings.StickInterval, Min = 0.05, Max = 0.5, Decimals = 2, Callback = function(v) BackTeleport.Settings.StickInterval = v end })

    local flySec = MovementTab:CreateSection({ Name = "Fly", Side = "Right" })
    flySec:AddToggle({ Name = "Enabled (Toggle)", Value = Fly.Settings.Enabled, Callback = function(v) Fly.Settings.Enabled = v end })
    flySec:AddTextbox({ Name = "Toggle Key", Value = Fly.Settings.ToggleKey, Callback = function(v) Fly.Settings.ToggleKey = v end })
    flySec:AddSlider({ Name = "Speed", Value = Fly.Settings.Speed, Min = 1, Max = 100, Callback = function(v) Fly.Settings.Speed = v end })
    flySec:AddSlider({ Name = "Up/Down Speed", Value = Fly.Settings.UpSpeed, Min = 1, Max = 100, Callback = function(v) Fly.Settings.UpSpeed = v end })
    flySec:AddSlider({ Name = "Smoothness", Value = Fly.Settings.Smoothness, Min = 0.1, Max = 1, Decimals = 2, Callback = function(v) Fly.Settings.Smoothness = v end })
    flySec:AddToggle({ Name = "Use WASD + Space/Ctrl", Value = Fly.Settings.UseKeys, Callback = function(v) Fly.Settings.UseKeys = v end })

    local tpSec = MovementTab:CreateSection({ Name = "Third Person", Side = "Right" })
    tpSec:AddToggle({ Name = "Enabled", Value = ThirdPerson.Settings.Enabled, Callback = function(v) ThirdPerson.Settings.Enabled = v end })
    tpSec:AddTextbox({ Name = "Toggle Key", Value = ThirdPerson.Settings.ToggleKey, Callback = function(v) ThirdPerson.Settings.ToggleKey = v end })
    tpSec:AddSlider({ Name = "Distance", Value = ThirdPerson.Settings.Distance, Min = 1, Max = 30, Callback = function(v) ThirdPerson.Settings.Distance = v end })
    tpSec:AddSlider({ Name = "Height", Value = ThirdPerson.Settings.Height, Min = -5, Max = 15, Callback = function(v) ThirdPerson.Settings.Height = v end })
    tpSec:AddSlider({ Name = "Sensitivity", Value = ThirdPerson.Settings.Sensitivity, Min = 0.1, Max = 3, Decimals = 1, Callback = function(v) ThirdPerson.Settings.Sensitivity = v end })
    tpSec:AddToggle({ Name = "Invert Y", Value = ThirdPerson.Settings.InvertY, Callback = function(v) ThirdPerson.Settings.InvertY = v end })
    tpSec:AddToggle({ Name = "Lock Cursor", Value = ThirdPerson.Settings.LockCursor, Callback = function(v) ThirdPerson.Settings.LockCursor = v end })
    tpSec:AddSlider({ Name = "Smoothness", Value = ThirdPerson.Settings.Smoothness, Min = 0, Max = 1, Decimals = 2, Callback = function(v) ThirdPerson.Settings.Smoothness = v end })

    -- Character Tab
    local charSec = CharacterTab:CreateSection({ Name = "Transparency" })
    charSec:AddToggle({ Name = "Transparent", Value = getgenv().AirHub.Character.Transparent, Callback = function(v)
        getgenv().AirHub.Character.Transparent = v
        UpdateCharacterTransparency()
    end })
    charSec:AddSlider({ Name = "Transparency", Value = getgenv().AirHub.Character.Transparency, Min = 0, Max = 1, Decimals = 2, Callback = function(v)
        getgenv().AirHub.Character.Transparency = v
        if getgenv().AirHub.Character.Transparent then UpdateCharacterTransparency() end
    end })

    local hatSec = CharacterTab:CreateSection({ Name = "China Hat ESP (цилиндр)" })
    hatSec:AddToggle({ Name = "Enabled", Value = getgenv().AirHub.Character.HatESP.Enabled, Callback = function(v)
        getgenv().AirHub.Character.HatESP.Enabled = v
        UpdateHatESP()
    end })
    hatSec:AddColorpicker({ Name = "Color", Value = getgenv().AirHub.Character.HatESP.Color, Callback = function(v)
        getgenv().AirHub.Character.HatESP.Color = v
        UpdateHatESP()
    end })
    hatSec:AddSlider({ Name = "Size", Value = getgenv().AirHub.Character.HatESP.Size, Min = 0.5, Max = 3, Decimals = 1, Callback = function(v)
        getgenv().AirHub.Character.HatESP.Size = v
        UpdateHatESP()
    end })
    hatSec:AddSlider({ Name = "Height", Value = getgenv().AirHub.Character.HatESP.Height, Min = 1, Max = 4, Decimals = 1, Callback = function(v)
        getgenv().AirHub.Character.HatESP.Height = v
        UpdateHatESP()
    end })
    hatSec:AddSlider({ Name = "Segments", Value = getgenv().AirHub.Character.HatESP.Segments, Min = 4, Max = 16, Decimals = 0, Callback = function(v)
        getgenv().AirHub.Character.HatESP.Segments = math.floor(v)
        UpdateHatESP()
    end })

    -- RTX Tab
    local rtxMain = RTXTab:CreateSection({ Name = "General" })
    rtxMain:AddToggle({ Name = "RTX Enabled", Value = WallHack.RTX.Enabled, Callback = function(v) if v then EnableRTX() else DisableRTX() end end })
    rtxMain:AddToggle({ Name = "Global Shadows", Value = WallHack.RTX.Settings.GlobalShadows, Callback = function(v) WallHack.RTX.Settings.GlobalShadows = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })
    rtxMain:AddSlider({ Name = "Brightness", Value = WallHack.RTX.Settings.Brightness, Min = 0, Max = 10, Decimals = 1, Callback = function(v) WallHack.RTX.Settings.Brightness = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })
    rtxMain:AddSlider({ Name = "Exposure", Value = WallHack.RTX.Settings.ExposureCompensation, Min = -1, Max = 1, Decimals = 2, Callback = function(v) WallHack.RTX.Settings.ExposureCompensation = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })
    rtxMain:AddSlider({ Name = "Shadow Softness", Value = WallHack.RTX.Settings.ShadowSoftness, Min = 0, Max = 1, Decimals = 2, Callback = function(v) WallHack.RTX.Settings.ShadowSoftness = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })
    rtxMain:AddSlider({ Name = "Diffuse Scale", Value = WallHack.RTX.Settings.EnvironmentDiffuseScale, Min = 0, Max = 2, Decimals = 2, Callback = function(v) WallHack.RTX.Settings.EnvironmentDiffuseScale = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })
    rtxMain:AddSlider({ Name = "Specular Scale", Value = WallHack.RTX.Settings.EnvironmentSpecularScale, Min = 0, Max = 3, Decimals = 2, Callback = function(v) WallHack.RTX.Settings.EnvironmentSpecularScale = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })
    rtxMain:AddSlider({ Name = "Clock Time", Value = WallHack.RTX.Settings.ClockTime, Min = 0, Max = 24, Decimals = 1, Callback = function(v) WallHack.RTX.Settings.ClockTime = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })
    rtxMain:AddColorpicker({ Name = "Outdoor Ambient", Value = WallHack.RTX.Settings.OutdoorAmbient, Callback = function(v) WallHack.RTX.Settings.OutdoorAmbient = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })
    rtxMain:AddSlider({ Name = "Fog End", Value = WallHack.RTX.Settings.FogEnd, Min = 0, Max = 10000, Callback = function(v) WallHack.RTX.Settings.FogEnd = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })
    rtxMain:AddSlider({ Name = "Fog Start", Value = WallHack.RTX.Settings.FogStart, Min = 0, Max = 10000, Callback = function(v) WallHack.RTX.Settings.FogStart = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })
    rtxMain:AddDropdown({ Name = "Technology", Value = WallHack.RTX.Settings.Technology, List = {"Compatibility","Voxel","ShadowMap","Future"}, Callback = function(v) WallHack.RTX.Settings.Technology = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })

    local ccSec = RTXTab:CreateSection({ Name = "Color Correction" })
    ccSec:AddToggle({ Name = "Enabled", Value = WallHack.RTX.Settings.ColorCorrection.Enabled, Callback = function(v) WallHack.RTX.Settings.ColorCorrection.Enabled = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })
    ccSec:AddSlider({ Name = "Brightness", Value = WallHack.RTX.Settings.ColorCorrection.Brightness, Min = -1, Max = 1, Decimals = 2, Callback = function(v) WallHack.RTX.Settings.ColorCorrection.Brightness = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })
    ccSec:AddSlider({ Name = "Contrast", Value = WallHack.RTX.Settings.ColorCorrection.Contrast, Min = -1, Max = 1, Decimals = 2, Callback = function(v) WallHack.RTX.Settings.ColorCorrection.Contrast = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })
    ccSec:AddSlider({ Name = "Saturation", Value = WallHack.RTX.Settings.ColorCorrection.Saturation, Min = -1, Max = 1, Decimals = 2, Callback = function(v) WallHack.RTX.Settings.ColorCorrection.Saturation = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })
    ccSec:AddColorpicker({ Name = "Tint Color", Value = WallHack.RTX.Settings.ColorCorrection.TintColor, Callback = function(v) WallHack.RTX.Settings.ColorCorrection.TintColor = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })

    local bloomSec = RTXTab:CreateSection({ Name = "Bloom" })
    bloomSec:AddToggle({ Name = "Enabled", Value = WallHack.RTX.Settings.Bloom.Enabled, Callback = function(v) WallHack.RTX.Settings.Bloom.Enabled = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })
    bloomSec:AddSlider({ Name = "Intensity", Value = WallHack.RTX.Settings.Bloom.Intensity, Min = 0, Max = 10, Decimals = 1, Callback = function(v) WallHack.RTX.Settings.Bloom.Intensity = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })
    bloomSec:AddSlider({ Name = "Size", Value = WallHack.RTX.Settings.Bloom.Size, Min = 0, Max = 50, Callback = function(v) WallHack.RTX.Settings.Bloom.Size = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })
    bloomSec:AddSlider({ Name = "Threshold", Value = WallHack.RTX.Settings.Bloom.Threshold, Min = 0, Max = 1, Decimals = 2, Callback = function(v) WallHack.RTX.Settings.Bloom.Threshold = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })

    local sunSec = RTXTab:CreateSection({ Name = "SunRays" })
    sunSec:AddToggle({ Name = "Enabled", Value = WallHack.RTX.Settings.SunRays.Enabled, Callback = function(v) WallHack.RTX.Settings.SunRays.Enabled = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })
    sunSec:AddSlider({ Name = "Intensity", Value = WallHack.RTX.Settings.SunRays.Intensity, Min = 0, Max = 1, Decimals = 2, Callback = function(v) WallHack.RTX.Settings.SunRays.Intensity = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })
    sunSec:AddSlider({ Name = "Spread", Value = WallHack.RTX.Settings.SunRays.Spread, Min = 0, Max = 1, Decimals = 2, Callback = function(v) WallHack.RTX.Settings.SunRays.Spread = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })

    local dofSec = RTXTab:CreateSection({ Name = "Depth of Field" })
    dofSec:AddToggle({ Name = "Enabled", Value = WallHack.RTX.Settings.DepthOfField.Enabled, Callback = function(v) WallHack.RTX.Settings.DepthOfField.Enabled = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })
    dofSec:AddSlider({ Name = "Far Distance", Value = WallHack.RTX.Settings.DepthOfField.FarDistance, Min = 0, Max = 1000, Callback = function(v) WallHack.RTX.Settings.DepthOfField.FarDistance = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })
    dofSec:AddSlider({ Name = "Near Distance", Value = WallHack.RTX.Settings.DepthOfField.NearDistance, Min = 0, Max = 100, Callback = function(v) WallHack.RTX.Settings.DepthOfField.NearDistance = v; if WallHack.RTX.Enabled then ApplyRTXSettings() end end })

    -- Settings (Logs & Sounds)
    local logSec = SettingsTab:CreateSection({ Name = "Shot Logs & Sounds" })
    logSec:AddToggle({ Name = "Logs Enabled", Value = getgenv().AirHub.Logging.Enabled, Callback = function(v) getgenv().AirHub.Logging.Enabled = v end })
    logSec:AddToggle({ Name = "Show Hits", Value = getgenv().AirHub.Logging.ShowHit, Callback = function(v) getgenv().AirHub.Logging.ShowHit = v end })
    logSec:AddToggle({ Name = "Show Misses", Value = getgenv().AirHub.Logging.ShowMiss, Callback = function(v) getgenv().AirHub.Logging.ShowMiss = v end })
    logSec:AddSlider({ Name = "Duration (s)", Value = getgenv().AirHub.Logging.Duration, Min = 0.5, Max = 5, Decimals = 1, Callback = function(v) getgenv().AirHub.Logging.Duration = v end })
    logSec:AddSlider({ Name = "Font Size", Value = getgenv().AirHub.Logging.FontSize, Min = 12, Max = 30, Callback = function(v) getgenv().AirHub.Logging.FontSize = v end })

    logSec:AddToggle({ Name = "Hitsound Enabled", Value = getgenv().AirHub.Sound.HitsoundEnabled, Callback = function(v) getgenv().AirHub.Sound.HitsoundEnabled = v end })
    logSec:AddDropdown({ Name = "Hitsound", Value = "gamesense", List = {"gamesense","neverlose","crit","primordial"}, Callback = function(v) getgenv().AirHub.Sound.HitsoundID = soundIDs[v] end })
    logSec:AddSlider({ Name = "Hitsound Volume", Value = getgenv().AirHub.Sound.HitsoundVolume, Min = 0, Max = 10, Decimals = 1, Callback = function(v) getgenv().AirHub.Sound.HitsoundVolume = v end })

    logSec:AddToggle({ Name = "Killsound Enabled", Value = getgenv().AirHub.Sound.KillsoundEnabled, Callback = function(v) getgenv().AirHub.Sound.KillsoundEnabled = v end })
    logSec:AddDropdown({ Name = "Killsound", Value = "gamesense", List = {"gamesense","neverlose","crit","primordial"}, Callback = function(v) getgenv().AirHub.Sound.KillsoundID = soundIDs[v] end })
    logSec:AddSlider({ Name = "Killsound Volume", Value = getgenv().AirHub.Sound.KillsoundVolume, Min = 0, Max = 10, Decimals = 1, Callback = function(v) getgenv().AirHub.Sound.KillsoundVolume = v end })

    local cfgSec = SettingsTab:CreateSection({ Name = "Config" })
    cfgSec:AddButton({ Name = "Save Config", Callback = SaveConfig })
    cfgSec:AddButton({ Name = "Load Config", Callback = LoadConfig })
    cfgSec:AddButton({ Name = "Reset All", Callback = function()
        Aimbot.Settings = {
            Enabled = false, TeamCheck = {Enabled = true, Mode = "Enemies", TreatNeutralAsEnemy = true},
            AliveCheck = true, WallCheck = false, FallbackToVisible = false,
            AimSmoothingSpeed = 6, AimPrediction = 0,
            TriggerKey = "MouseButton2", Toggle = false, LockPart = "Head", AimMethod = "Smooth",
            SilentAim = true, IgnoreFOV = false, CheckFromPlayerOnTP = true,
            AutoShoot = {Enabled = false, ShootKey = "MouseButton1", FireRate = 0.05, OnlyWhenAiming = true, StrictWallCheck = false, AutoStop = {Enabled = false, Time = 0.1}, FireRateMode = "Manual"}
        }
        Aimbot.FOVSettings = {Enabled = true, Visible = true, Amount = 90}
        WallHack.Functions.ResetSettings()
        AntiAim.Functions.ResetSettings()
        Fly.Functions.ResetSettings()
        BHop.Functions.ResetSettings()
        BackTeleport.Functions.ResetSettings()
        DashTeleport.Functions.ResetSettings()
        ThirdPerson.Functions.ResetSettings()
        getgenv().AirHub.Logging = {Enabled = true, ShowHit = true, ShowMiss = true, Duration = 1, FontSize = 18}
        getgenv().AirHub.Sound = {HitsoundEnabled = false, HitsoundID = 83717596220569, HitsoundVolume = 1, KillsoundEnabled = false, KillsoundID = 83717596220569, KillsoundVolume = 1}
        getgenv().AirHub.Character = {Transparent = false, Transparency = 0.5, HatESP = {Enabled = false, Color = Color3.fromRGB(255,223,0), Size = 1.5, Height = 2.5, Segments = 8}}
        if Library.ResetAll then Library.ResetAll() end
        UpdateCharacterTransparency()
        UpdateHatESP()
        ShowError("All settings reset")
    end })
    cfgSec:AddButton({ Name = "Rejoin", Callback = Rejoin })
    cfgSec:AddButton({ Name = "Server Hop", Callback = ServerHop })
    cfgSec:AddButton({ Name = "Exit", Callback = Library.Unload })

    ShowError("AirHub | Silent Aim (Camera) | Smart Lock Parts | Glow Modes | Hat ESP (цилиндр)")
end)
