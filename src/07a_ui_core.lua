--// AirHub - 07a_ui_core.lua
--// UI library load, window, tabs, Aimbot tab.

local H = getgenv().AirHub
if not H or not H._CoreLoaded then warn("[AirHub] 07a: core not loaded"); return end

local Util = H.Util
local UserInputService = Util.UserInputService
local LocalPlayer = Util.LocalPlayer
local Track = Util.Track
local UntrackAll = Util.UntrackAll
local ShowError = Util.ShowError

local Aimbot = H.Aimbot
local WallHack = H.WallHack
local AntiAim = H.AntiAim
local ServerPosition = H.ServerPosition
local Fly = H.Fly
local Bhop = H.Bhop
local Speed = H.Speed
local FastStop = H.FastStop
local AutoStrafer = H.AutoStrafer
local Noclip = H.Noclip

local CancelLock = Aimbot.CancelLock
local RemoveRayHook = Aimbot.RemoveRayHook
local RemoveMouseHitHook = Aimbot.RemoveMouseHitHook
local RemoveGunHandlerHook = Aimbot.RemoveGunHandlerHook
local ApplyGlowToAll = WallHack.ApplyGlowToAll
local StartServerPosition = ServerPosition.Start
local StopServerPosition = ServerPosition.Stop
local Fly_ClearInstances = Fly.ClearInstances
local AS_ReleaseAll = AutoStrafer.ReleaseAll
local StopDesync = AntiAim.StopDesync
local StartDesync = AntiAim.StartDesync
local CleanupAntiAim = AntiAim.CleanupAntiAim
local AA_BIND_NAME = AntiAim.AA_BIND_NAME

local function ApplyAllEnabledStates()
    local Hg = getgenv().AirHub
    if not Hg then return end
    if WallHack.Settings.Enabled then ApplyGlowToAll() end
    if Hg.AntiAim and Hg.AntiAim.Desync.Settings.Enabled then
        StopDesync()
        task.defer(function()
            if getgenv().AirHub and getgenv().AirHub.AntiAim.Desync.Settings.Enabled then
                StartDesync()
            end
        end)
    else
        StopDesync()
    end
    if Hg.ServerPosition and Hg.ServerPosition.Settings.Enabled then
        StopServerPosition()
        task.defer(function()
            if getgenv().AirHub and getgenv().AirHub.ServerPosition.Settings.Enabled then
                StartServerPosition()
            end
        end)
    else
        StopServerPosition()
    end
    if Hg.Fly then
        Fly_ClearInstances()
        Hg.Fly.Internal.Active = Hg.Fly.Settings.Enabled and Hg.Fly.Settings.Toggle or false
    end
    if Hg.Bhop then
        Hg.Bhop.Internal.KeyHeld = false
        Hg.Bhop.Internal.Active = false
        Hg.Bhop.Internal.SpiderTouching = false
    end
    if Hg.Speed then Hg.Speed.Internal.Active = false end
    if Hg.Noclip then Hg.Noclip.Internal.Active = false end
    if Hg.AutoStrafer then
        AutoStrafer.Internal.Active = false
        AS_ReleaseAll()
    end
    if Hg.FastStop then FastStop.Internal.LastActive = false end

    if WallHack and WallHack.Functions then
        if WallHack.Visuals and WallHack.Visuals.HUDSettings then
            if WallHack.Visuals.HUDSettings.Enabled then
                WallHack.Functions.StartHUD()
            else
                WallHack.Functions.StopHUD()
            end
        end
        if WallHack.Visuals and WallHack.Visuals.SelfESP then
            if WallHack.Visuals.SelfESP.Enabled then
                WallHack.Functions.StartSelfESP()
            else
                WallHack.Functions.StopSelfESP()
            end
        end
    end

    --// Spoof Anim restore
    if Hg.AntiAim and Hg.AntiAim.SpoofAnim and Hg.AntiAim.SpoofAnim.Functions then
        if Hg.AntiAim.SpoofAnim.Settings.Enabled then
            Hg.AntiAim.SpoofAnim.Functions.Start()
        else
            Hg.AntiAim.SpoofAnim.Functions.Stop()
        end
    end
end

H._UI = H._UI or {}
H._UI.ApplyAllEnabledStates = ApplyAllEnabledStates

task.delay(math.random(1, 3), function()
    if H.ShuttingDown then return end
    local Library
    local ok, err = pcall(function()
        Library = loadstring(game:GetObjects("rbxassetid://7657867786")[1].Source)()
    end)
    if not ok or not Library then
        ShowError("UI Library failed to load")
        warn("[AirHub] UI Library failed: " .. tostring(err))
        return
    end
    H._UI.Library = Library

    local function SafeShow()
        if type(Library.Show) == "function" then pcall(function() Library:Show() end) return end
        if type(Library.Open) == "function" then pcall(function() Library:Open() end) return end
        if type(Library.Toggle) == "function" then pcall(function() Library:Toggle() end) return end
    end
    local function SafeHide()
        if type(Library.Hide) == "function" then pcall(function() Library:Hide() end) return end
        if type(Library.Close) == "function" then pcall(function() Library:Close() end) return end
    end
    local function SafeUnload()
        if type(Library.Unload) == "function" then pcall(function() Library:Unload() end) return end
        if type(Library.Destroy) == "function" then pcall(function() Library:Destroy() end) return end
    end
    H._UI.SafeShow = SafeShow
    H._UI.SafeHide = SafeHide
    H._UI.SafeUnload = SafeUnload

    H._UI.MenuVisible = true
    Track(UserInputService.InputBegan:Connect(function(inp, gpe)
        if gpe then return end
        if inp.KeyCode == Enum.KeyCode.RightShift then
            H._UI.MenuVisible = not H._UI.MenuVisible
            if H._UI.MenuVisible then SafeShow() else SafeHide() end
        end
    end))

    Library.UnloadCallback = function()
        H.ShuttingDown = true
        Aimbot.Settings.Enabled = false
        Aimbot.Settings.AutoShoot.Enabled = false
        Aimbot.FOVSettings.Enabled = false
        WallHack.Settings.Enabled = false
        WallHack.Visuals.BoxSettings.Enabled = false
        WallHack.Visuals.GlowSettings.Enabled = false
        if WallHack.Visuals.HUDSettings then WallHack.Visuals.HUDSettings.Enabled = false end
        if WallHack.Visuals.SelfESP    then WallHack.Visuals.SelfESP.Enabled    = false end
        AntiAim.Settings.Enabled = false
        AntiAim.Desync.Settings.Enabled = false
        if AntiAim.SpoofAnim and AntiAim.SpoofAnim.Settings then
            AntiAim.SpoofAnim.Settings.Enabled = false
        end
        ServerPosition.Settings.Enabled = false
        Fly.Settings.Enabled = false
        Bhop.Settings.Enabled = false
        Speed.Settings.Enabled = false
        FastStop.Settings.Enabled = false
        AutoStrafer.Settings.Enabled = false
        Noclip.Settings.Enabled = false
        Fly.Internal.Active = false
        Bhop.Internal.KeyHeld = false
        Bhop.Internal.Active = false
        AutoStrafer.Internal.Active = false
        Speed.Internal.Active = false
        Noclip.Internal.Active = false
        FastStop.Internal.LastActive = false
        pcall(function() CancelLock() end)
        pcall(function() Aimbot.FOVCircle:Remove() end)
        pcall(function() WallHack.Functions.Exit() end)
        pcall(StopServerPosition)
        pcall(StopDesync)
        pcall(Fly_ClearInstances)
        pcall(function()
            if AntiAim.SpoofAnim and AntiAim.SpoofAnim.Functions and AntiAim.SpoofAnim.Functions.Stop then
                AntiAim.SpoofAnim.Functions.Stop()
            end
        end)
        pcall(function()
            local char = LocalPlayer.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then
                    hum.PlatformStand = false
                    if hum.WalkSpeed ~= 16 then hum.WalkSpeed = 16 end
                end
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then part.CanCollide = true end
                end
            end
        end)
        pcall(function() if AutoStrafer.Internal.KeyA or AutoStrafer.Internal.KeyD then AS_ReleaseAll() end end)
        pcall(RemoveRayHook)
        pcall(RemoveMouseHitHook)
        pcall(RemoveGunHandlerHook)
        if Aimbot.RemoveRayNewHook      then pcall(Aimbot.RemoveRayNewHook)      end
        if Aimbot.RemoveVector3UnitHook then pcall(Aimbot.RemoveVector3UnitHook) end
        if Aimbot.RemoveSPRHook         then pcall(Aimbot.RemoveSPRHook)         end
        if Aimbot.RemoveFireServerHook  then pcall(Aimbot.RemoveFireServerHook)  end
        if Aimbot.RemoveMouseHook       then pcall(Aimbot.RemoveMouseHook)       end
        pcall(CleanupAntiAim)
        pcall(function() game:GetService("RunService"):UnbindFromRenderStep(AA_BIND_NAME) end)
        pcall(function()
            if H.World and H.World.Functions and H.World.Functions.Restore then
                H.World.Functions.Restore()
            end
        end)
        pcall(function()
            if H.Exploits and H.Exploits.Functions and H.Exploits.Functions.StopAll then
                H.Exploits.Functions.StopAll()
            end
        end)
        pcall(function() H.ErrorText:Remove() end)
        pcall(function() for _, log in ipairs(H.ActiveLogs) do log.text:Remove() end end)
        H.ActiveLogs = {}
        pcall(function() if H.Sounds.Hitsound then H.Sounds.Hitsound:Destroy() end end)
        pcall(function() if H.Sounds.Killsound then H.Sounds.Killsound:Destroy() end end)
        pcall(UntrackAll)
        getgenv().AirHub = nil
        pcall(function()
            local t = Drawing.new("Text")
            t.Text = "AirHub unloaded"
            t.Size = 20
            t.Color = Color3.fromRGB(255, 80, 80)
            t.Center = true
            t.Outline = true
            t.Position = workspace.CurrentCamera.ViewportSize / 2
            task.delay(2, function() t:Remove() end)
        end)
    end

    local MainFrame = Library:CreateWindow({
        Name = "AirHub",
        Themeable = {
            Image = "96742921028995",
            Info = "Strafe Helper | Silent Aim | Ghost | Fly | Configs", Credit = false,
        },
    })
    H._UI.MainFrame    = MainFrame
    H._UI.AimbotTab    = MainFrame:CreateTab({ Name = "Aimbot" })
    H._UI.VisualsTab   = MainFrame:CreateTab({ Name = "Visuals" })
    H._UI.AntiTab      = MainFrame:CreateTab({ Name = "Anti-Aim" })
    H._UI.SpoofAnimTab = MainFrame:CreateTab({ Name = "Spoof Anims" })
    H._UI.MovementTab  = MainFrame:CreateTab({ Name = "Movement" })
    H._UI.WorldTab     = MainFrame:CreateTab({ Name = "World" })
    H._UI.ExploitsTab  = MainFrame:CreateTab({ Name = "Exploits" })
    H._UI.SettingsTab  = MainFrame:CreateTab({ Name = "Settings" })

    local teamModes      = { "Enemies", "Allies", "All", "IgnoreNeutrals" }
    local wallCheckModes = { "Fast", "Perfect" }
    local silentAimModes = {
        "Camera", "Mouse", "MouseLock", "MouseHit", "MouseFull",
        "RayHook", "RayNew", "ScreenPointToRay", "Vector3Unit",
        "FireServer", "GunHandler",
    }

    --// =====================================================================
    --// AIMBOT TAB
    --// =====================================================================
    local secA = H._UI.AimbotTab:CreateSection({ Name = "Main" })
    secA:AddToggle({ Name = "Enabled", Value = Aimbot.Settings.Enabled,
        Callback = function(v) Aimbot.Settings.Enabled = v end })
    secA:AddToggle({ Name = "Toggle", Value = Aimbot.Settings.Toggle,
        Callback = function(v) Aimbot.Settings.Toggle = v end })
    secA:AddToggle({ Name = "360 Ignore FOV", Value = Aimbot.Settings.IgnoreFOV,
        Callback = function(v) Aimbot.Settings.IgnoreFOV = v end })
    secA:AddToggle({ Name = "Check visibility from player on TP", Value = Aimbot.Settings.CheckFromPlayerOnTP,
        Callback = function(v) Aimbot.Settings.CheckFromPlayerOnTP = v end })
    secA:AddDropdown({ Name = "Lock Part", Value = Aimbot.Settings.LockPart,
        List = { "Head", "Torso", "Nearest" },
        Callback = function(v) Aimbot.Settings.LockPart = v end })
    secA:AddToggle({ Name = "Fallback to visible parts", Value = Aimbot.Settings.FallbackToVisible,
        Callback = function(v) Aimbot.Settings.FallbackToVisible = v end })
    secA:AddTextbox({ Name = "Aim Key (MouseButton1/2 or KeyCode)", Value = Aimbot.Settings.TriggerKey,
        Callback = function(v) Aimbot.Settings.TriggerKey = v end })
    secA:AddDropdown({ Name = "Aim Method", Value = Aimbot.Settings.AimMethod,
        List = { "Smooth", "Instant" },
        Callback = function(v) Aimbot.Settings.AimMethod = v end })
    secA:AddSlider({ Name = "Smoothing Speed", Value = Aimbot.Settings.AimSmoothingSpeed,
        Min = 1, Max = 20,
        Callback = function(v) Aimbot.Settings.AimSmoothingSpeed = v end })

    secA:AddToggle({ Name = "Target NPCs (rigs/dummies)", Value = Aimbot.Settings.TargetNPCs,
        Callback = function(v) Aimbot.Settings.TargetNPCs = v end })
    secA:AddTextbox({ Name = "NPC name filter (optional, substring)", Value = Aimbot.Settings.NPCNameFilter or "",
        Callback = function(v) Aimbot.Settings.NPCNameFilter = v end })

    local predSec = H._UI.AimbotTab:CreateSection({ Name = "Prediction" })
    predSec:AddToggle({ Name = "Enabled", Value = Aimbot.Settings.PredictionEnabled,
        Callback = function(v) Aimbot.Settings.PredictionEnabled = v end })
    predSec:AddSlider({ Name = "Prediction X (%)", Value = Aimbot.Settings.PredictionX,
        Min = -100, Max = 100,
        Callback = function(v) Aimbot.Settings.PredictionX = v end })
    predSec:AddSlider({ Name = "Prediction Y (%)", Value = Aimbot.Settings.PredictionY,
        Min = -100, Max = 100,
        Callback = function(v) Aimbot.Settings.PredictionY = v end })
    predSec:AddSlider({ Name = "Base Time (s)", Value = Aimbot.Settings.PredictionTime,
        Min = 0.01, Max = 0.5, Decimals = 2,
        Callback = function(v) Aimbot.Settings.PredictionTime = v end })

    local secW = H._UI.AimbotTab:CreateSection({ Name = "Visibility", Side = "Right" })
    secW:AddToggle({ Name = "WallCheck", Value = Aimbot.Settings.WallCheck,
        Callback = function(v) Aimbot.Settings.WallCheck = v end })
    secW:AddDropdown({ Name = "WallCheck Mode", Value = Aimbot.Settings.WallCheckMode,
        List = wallCheckModes,
        Callback = function(v) Aimbot.Settings.WallCheckMode = v end })
    secW:AddToggle({ Name = "Delay Shot", Value = Aimbot.Settings.DelayShot,
        Callback = function(v) Aimbot.Settings.DelayShot = v end })
    secW:AddToggle({ Name = "Alive Check", Value = Aimbot.Settings.AliveCheck,
        Callback = function(v) Aimbot.Settings.AliveCheck = v end })
    secW:AddToggle({ Name = "Team Check", Value = Aimbot.Settings.TeamCheck.Enabled,
        Callback = function(v) Aimbot.Settings.TeamCheck.Enabled = v end })
    secW:AddDropdown({ Name = "Team Mode", Value = Aimbot.Settings.TeamCheck.Mode,
        List = teamModes,
        Callback = function(v) Aimbot.Settings.TeamCheck.Mode = v end })
    secW:AddToggle({ Name = "Treat Neutrals as Enemies", Value = Aimbot.Settings.TeamCheck.TreatNeutralAsEnemy,
        Callback = function(v) Aimbot.Settings.TeamCheck.TreatNeutralAsEnemy = v end })

    local secD = H._UI.AimbotTab:CreateSection({ Name = "Silent Aim", Side = "Right" })
    secD:AddToggle({ Name = "Enabled", Value = Aimbot.Settings.SilentAim,
        Callback = function(v) Aimbot.Settings.SilentAim = v end })
    secD:AddDropdown({ Name = "Mode", Value = Aimbot.Settings.SilentAimMode,
        List = silentAimModes,
        Callback = function(v)
            Aimbot.Settings.SilentAimMode = v
            if v ~= "RayHook"          and Aimbot.RemoveRayHook         then Aimbot.RemoveRayHook()         end
            if v ~= "RayNew"           and Aimbot.RemoveRayNewHook      then Aimbot.RemoveRayNewHook()      end
            if v ~= "Vector3Unit"      and Aimbot.RemoveVector3UnitHook then Aimbot.RemoveVector3UnitHook() end
            if v ~= "ScreenPointToRay" and Aimbot.RemoveSPRHook         then Aimbot.RemoveSPRHook()         end
            if v ~= "MouseHit" and v ~= "MouseFull" and Aimbot.RemoveMouseHook then Aimbot.RemoveMouseHook()   end
            if v ~= "FireServer"       and Aimbot.RemoveFireServerHook  then Aimbot.RemoveFireServerHook()  end
        end })

    local secAS = H._UI.AimbotTab:CreateSection({ Name = "Auto Shoot", Side = "Right" })
    secAS:AddToggle({ Name = "Enabled", Value = Aimbot.Settings.AutoShoot.Enabled,
        Callback = function(v) Aimbot.Settings.AutoShoot.Enabled = v end })
    secAS:AddToggle({ Name = "Only when aiming", Value = Aimbot.Settings.AutoShoot.OnlyWhenAiming,
        Callback = function(v) Aimbot.Settings.AutoShoot.OnlyWhenAiming = v end })
    secAS:AddTextbox({ Name = "Manual delay (s)", Value = tostring(Aimbot.Settings.AutoShoot.FireRate),
        Callback = function(v)
            local n = tonumber(v)
            if n then Aimbot.Settings.AutoShoot.FireRate = math.clamp(n, 0.001, 1) end
        end })
    secAS:AddDropdown({ Name = "Shoot Key", Value = "Left Click",
        List = { "Left Click", "Right Click" },
        Callback = function(v)
            Aimbot.Settings.AutoShoot.ShootKey = (v == "Left Click") and "MouseButton1" or "MouseButton2"
        end })
    secAS:AddToggle({ Name = "AutoStop", Value = Aimbot.Settings.AutoShoot.AutoStop.Enabled,
        Callback = function(v) Aimbot.Settings.AutoShoot.AutoStop.Enabled = v end })
    secAS:AddSlider({ Name = "Stop time (s)", Value = Aimbot.Settings.AutoShoot.AutoStop.Time,
        Min = 0.01, Max = 0.5, Decimals = 2,
        Callback = function(v) Aimbot.Settings.AutoShoot.AutoStop.Time = v end })

    local secE = H._UI.AimbotTab:CreateSection({ Name = "FOV" })
    secE:AddToggle({ Name = "Enabled", Value = Aimbot.FOVSettings.Enabled,
        Callback = function(v) Aimbot.FOVSettings.Enabled = v end })
    secE:AddToggle({ Name = "Visible", Value = Aimbot.FOVSettings.Visible,
        Callback = function(v) Aimbot.FOVSettings.Visible = v end })
    secE:AddSlider({ Name = "Radius", Value = Aimbot.FOVSettings.Amount,
        Min = 10, Max = 300,
        Callback = function(v) Aimbot.FOVSettings.Amount = v end })

    ShowError("AirHub UI core loaded")
end)
