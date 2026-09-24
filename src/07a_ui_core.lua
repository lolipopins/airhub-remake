--// AirHub - 07a_ui_core.lua
--// UI library load, window, tabs, Aimbot tab + Wallbang + TP Aim sections.

local H = getgenv().AirHub
if not H or not H._CoreLoaded then warn("[AirHub] 07a: core not loaded"); return end

local Util             = H.Util
local UserInputService = Util.UserInputService
local LocalPlayer      = Util.LocalPlayer
local Track            = Util.Track
local UntrackAll       = Util.UntrackAll
local ShowError        = Util.ShowError

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

local _missingLogged = {}
local function noop() end
local function orNoop(fn, label)
    if type(fn) == "function" then return fn end
    if label and not _missingLogged[label] then
        _missingLogged[label] = true
        warn("[AirHub] 07a: missing function -> " .. tostring(label))
    end
    return noop
end
local function orTable(t, label)
    if type(t) == "table" then return t end
    if label and not _missingLogged[label] then
        _missingLogged[label] = true
        warn("[AirHub] 07a: missing module -> " .. tostring(label))
    end
    return {}
end

Aimbot         = orTable(Aimbot,         "Aimbot")
WallHack       = orTable(WallHack,       "WallHack")
AntiAim        = orTable(AntiAim,        "AntiAim")
ServerPosition = orTable(ServerPosition, "ServerPosition")
Fly            = orTable(Fly,            "Fly")
Bhop           = orTable(Bhop,           "Bhop")
Speed          = orTable(Speed,          "Speed")
FastStop       = orTable(FastStop,       "FastStop")
AutoStrafer    = orTable(AutoStrafer,    "AutoStrafer")
Noclip         = orTable(Noclip,         "Noclip")

local CancelLock           = orNoop(Aimbot.CancelLock,                "Aimbot.CancelLock")
local RemoveRayHook        = orNoop(Aimbot.RemoveRayHook,             "Aimbot.RemoveRayHook")
local RemoveMouseHitHook   = orNoop(Aimbot.RemoveMouseHitHook,        "Aimbot.RemoveMouseHitHook")
local RemoveGunHandlerHook = orNoop(Aimbot.RemoveGunHandlerHook,      "Aimbot.RemoveGunHandlerHook")
local RemoveCFrameHook     = orNoop(Aimbot.RemoveCFrameHook,          "Aimbot.RemoveCFrameHook")
local RemoveVector3NewHook = orNoop(Aimbot.RemoveVector3NewHook,      "Aimbot.RemoveVector3NewHook")
local ApplyGlowToAll       = orNoop(WallHack.ApplyGlowToAll,          "WallHack.ApplyGlowToAll")
local StartServerPosition  = orNoop(ServerPosition.Start,             "ServerPosition.Start")
local StopServerPosition   = orNoop(ServerPosition.Stop,              "ServerPosition.Stop")
local Fly_ClearInstances   = orNoop(Fly.ClearInstances,               "Fly.ClearInstances")
local AS_ReleaseAll        = orNoop(AutoStrafer.ReleaseAll,           "AutoStrafer.ReleaseAll")
local StopDesync           = orNoop(AntiAim.StopDesync,               "AntiAim.StopDesync")
local StartDesync          = orNoop(AntiAim.StartDesync,              "AntiAim.StartDesync")
local CleanupAntiAim       = orNoop(AntiAim.CleanupAntiAim,           "AntiAim.CleanupAntiAim")
local AA_BIND_NAME         = AntiAim.AA_BIND_NAME or "AirHubAntiAim"

local function ApplyAllEnabledStates()
    local Hg = getgenv().AirHub
    if not Hg then return end

    if WallHack.Settings and WallHack.Settings.Enabled then ApplyGlowToAll() end

    if Hg.AntiAim and Hg.AntiAim.Desync and Hg.AntiAim.Desync.Settings
       and Hg.AntiAim.Desync.Settings.Enabled then
        StopDesync()
        task.defer(function()
            if getgenv().AirHub and getgenv().AirHub.AntiAim
               and getgenv().AirHub.AntiAim.Desync.Settings.Enabled then
                StartDesync()
            end
        end)
    else
        StopDesync()
    end

    if Hg.ServerPosition and Hg.ServerPosition.Settings
       and Hg.ServerPosition.Settings.Enabled then
        StopServerPosition()
        task.defer(function()
            if getgenv().AirHub and getgenv().AirHub.ServerPosition
               and getgenv().AirHub.ServerPosition.Settings.Enabled then
                StartServerPosition()
            end
        end)
    else
        StopServerPosition()
    end

    if Hg.Fly and Hg.Fly.Settings and Hg.Fly.Internal then
        Fly_ClearInstances()
        Hg.Fly.Internal.Active = Hg.Fly.Settings.Enabled and Hg.Fly.Settings.Toggle or false
    end
    if Hg.Bhop and Hg.Bhop.Internal then
        Hg.Bhop.Internal.KeyHeld = false
        Hg.Bhop.Internal.Active = false
        Hg.Bhop.Internal.SpiderTouching = false
    end
    if Hg.Speed and Hg.Speed.Internal then Hg.Speed.Internal.Active = false end
    if Hg.Noclip and Hg.Noclip.Internal then Hg.Noclip.Internal.Active = false end
    if Hg.AutoStrafer and Hg.AutoStrafer.Internal then
        Hg.AutoStrafer.Internal.Active = false
        AS_ReleaseAll()
    end
    if Hg.FastStop and Hg.FastStop.Internal then Hg.FastStop.Internal.LastActive = false end

    if WallHack and WallHack.Functions then
        if WallHack.Visuals and WallHack.Visuals.HUDSettings then
            if WallHack.Visuals.HUDSettings.Enabled then
                if WallHack.Functions.StartHUD then WallHack.Functions.StartHUD() end
            else
                if WallHack.Functions.StopHUD then WallHack.Functions.StopHUD() end
            end
        end
        if WallHack.Visuals and WallHack.Visuals.SelfESP then
            if WallHack.Visuals.SelfESP.Enabled then
                if WallHack.Functions.StartSelfESP then WallHack.Functions.StartSelfESP() end
            else
                if WallHack.Functions.StopSelfESP then WallHack.Functions.StopSelfESP() end
            end
        end
    end
end

H._UI = H._UI or {}
H._UI.ApplyAllEnabledStates = ApplyAllEnabledStates

--// ---------------------------------------------------------------------------
--// UI bootstrap
--// ---------------------------------------------------------------------------
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
    H._UI.SafeShow   = SafeShow
    H._UI.SafeHide   = SafeHide
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

        if Aimbot.Settings then
            Aimbot.Settings.Enabled = false
            if Aimbot.Settings.AutoShoot then Aimbot.Settings.AutoShoot.Enabled = false end
            Aimbot.Settings.TPAimEnabled = false
            Aimbot.Settings.WallbangEnabled = false
        end
        if Aimbot.FOVSettings then Aimbot.FOVSettings.Enabled = false end
        if Aimbot.CancelAutoScan then pcall(Aimbot.CancelAutoScan) end
        if Aimbot.TPAimInternal then Aimbot.TPAimInternal.Active = false end

        if WallHack.Settings then WallHack.Settings.Enabled = false end
        if WallHack.Visuals then
            if WallHack.Visuals.BoxSettings then WallHack.Visuals.BoxSettings.Enabled = false end
            if WallHack.Visuals.GlowSettings then WallHack.Visuals.GlowSettings.Enabled = false end
            if WallHack.Visuals.HUDSettings then WallHack.Visuals.HUDSettings.Enabled = false end
            if WallHack.Visuals.SelfESP then WallHack.Visuals.SelfESP.Enabled = false end
        end

        if AntiAim.Settings then AntiAim.Settings.Enabled = false end
        if AntiAim.Desync and AntiAim.Desync.Settings then
            AntiAim.Desync.Settings.Enabled = false
        end

        if ServerPosition.Settings then ServerPosition.Settings.Enabled = false end
        if Fly.Settings then Fly.Settings.Enabled = false end
        if Bhop.Settings then Bhop.Settings.Enabled = false end
        if Speed.Settings then Speed.Settings.Enabled = false end
        if FastStop.Settings then FastStop.Settings.Enabled = false end
        if AutoStrafer.Settings then AutoStrafer.Settings.Enabled = false end
        if Noclip.Settings then Noclip.Settings.Enabled = false end

        if Fly.Internal then Fly.Internal.Active = false end
        if Bhop.Internal then
            Bhop.Internal.KeyHeld = false
            Bhop.Internal.Active = false
        end
        if AutoStrafer.Internal then AutoStrafer.Internal.Active = false end
        if Speed.Internal then Speed.Internal.Active = false end
        if Noclip.Internal then Noclip.Internal.Active = false end
        if FastStop.Internal then FastStop.Internal.LastActive = false end

        pcall(function() CancelLock() end)
        pcall(function() if Aimbot.FOVCircle then Aimbot.FOVCircle:Remove() end end)
        pcall(function()
            if WallHack.Functions and WallHack.Functions.Exit then WallHack.Functions.Exit() end
        end)
        pcall(function() StopServerPosition() end)
        pcall(function() StopDesync() end)
        pcall(function() Fly_ClearInstances() end)

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

        pcall(function() AS_ReleaseAll() end)
        pcall(function() RemoveRayHook() end)
        pcall(function() RemoveMouseHitHook() end)
        pcall(function() RemoveGunHandlerHook() end)
        pcall(function() RemoveCFrameHook() end)
        pcall(function() RemoveVector3NewHook() end)
        if Aimbot.RemoveRayNewHook      then pcall(Aimbot.RemoveRayNewHook)      end
        if Aimbot.RemoveVector3UnitHook then pcall(Aimbot.RemoveVector3UnitHook) end
        if Aimbot.RemoveSPRHook         then pcall(Aimbot.RemoveSPRHook)         end
        if Aimbot.RemoveFireServerHook  then pcall(Aimbot.RemoveFireServerHook)  end
        if Aimbot.RemoveMouseHook       then pcall(Aimbot.RemoveMouseHook)       end
        pcall(function() CleanupAntiAim() end)
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

        pcall(function() if H.ErrorText then H.ErrorText:Remove() end end)
        pcall(function()
            if H.ActiveLogs then
                for _, log in ipairs(H.ActiveLogs) do
                    if log.text then log.text:Remove() end
                end
            end
        end)
        H.ActiveLogs = {}
        pcall(function() if H.Sounds and H.Sounds.Hitsound then H.Sounds.Hitsound:Destroy() end end)
        pcall(function() if H.Sounds and H.Sounds.Killsound then H.Sounds.Killsound:Destroy() end end)
        pcall(UntrackAll)
        getgenv().AirHub = nil
        pcall(function()
            local t = Drawing.new("Text")
            t.Text    = "AirHub unloaded"
            t.Size    = 20
            t.Color   = Color3.fromRGB(255, 80, 80)
            t.Center  = true
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
    H._UI.MainFrame   = MainFrame
    H._UI.AimbotTab   = MainFrame:CreateTab({ Name = "Aimbot" })
    H._UI.VisualsTab  = MainFrame:CreateTab({ Name = "Visuals" })
    H._UI.AntiTab     = MainFrame:CreateTab({ Name = "Anti-Aim" })
    H._UI.MovementTab = MainFrame:CreateTab({ Name = "Movement" })
    H._UI.WorldTab    = MainFrame:CreateTab({ Name = "World" })
    H._UI.ExploitsTab = MainFrame:CreateTab({ Name = "Exploits" })
    H._UI.SettingsTab = MainFrame:CreateTab({ Name = "Settings" })

    local teamModes      = { "Enemies", "Allies", "All", "IgnoreNeutrals" }
    local wallCheckModes = { "Fast", "Perfect" }

    local silentAimModes = {
        "Auto",
        "Camera",
        "Mouse", "MouseLock",
        "MouseHit", "MouseFull",
        "RayHook", "RayNew",
        "ScreenPointToRay",
        "Vector3Unit", "Vector3New",
        "FireServer", "GunHandler",
        "CFrameHook",
    }

    local wallbangModes = {
        "RemotePatch",
        "RemotePatchFull",
        "RayIgnore",
        "RayNewHook",
        "MuzzleTeleport",
        "MouseHit",
        "ScreenPointToRay",
        "CameraTP",
    }

    local AS = (Aimbot and Aimbot.Settings) or {}
    local function aSet(key, val) if Aimbot.Settings then Aimbot.Settings[key] = val end end
    local function aSetTeam(key, val)
        if Aimbot.Settings and Aimbot.Settings.TeamCheck then
            Aimbot.Settings.TeamCheck[key] = val
        end
    end
    local function aSetAS(key, val)
        if Aimbot.Settings and Aimbot.Settings.AutoShoot then
            Aimbot.Settings.AutoShoot[key] = val
        end
    end
    local function aSetFov(key, val)
        if Aimbot.FOVSettings then Aimbot.FOVSettings[key] = val end
    end

    --// ==== Main ====
    local secA = H._UI.AimbotTab:CreateSection({ Name = "Main" })
    secA:AddToggle({ Name = "Enabled", Value = AS.Enabled or false,
        Callback = function(v) aSet("Enabled", v) end })
    secA:AddToggle({ Name = "Toggle", Value = AS.Toggle or false,
        Callback = function(v) aSet("Toggle", v) end })
    secA:AddToggle({ Name = "360 Ignore FOV", Value = AS.IgnoreFOV or false,
        Callback = function(v) aSet("IgnoreFOV", v) end })
    secA:AddToggle({ Name = "Check visibility from player on TP", Value = AS.CheckFromPlayerOnTP ~= false,
        Callback = function(v) aSet("CheckFromPlayerOnTP", v) end })
    secA:AddDropdown({ Name = "Lock Part", Value = AS.LockPart or "Head",
        List = { "Head", "Torso", "Nearest" },
        Callback = function(v) aSet("LockPart", v) end })
    secA:AddToggle({ Name = "Fallback to visible parts", Value = AS.FallbackToVisible or false,
        Callback = function(v) aSet("FallbackToVisible", v) end })
    secA:AddTextbox({ Name = "Aim Key (MouseButton1/2 or KeyCode)", Value = AS.TriggerKey or "MouseButton2",
        Callback = function(v) aSet("TriggerKey", v) end })
    secA:AddDropdown({ Name = "Aim Method", Value = AS.AimMethod or "Smooth",
        List = { "Smooth", "Instant" },
        Callback = function(v) aSet("AimMethod", v) end })
    secA:AddSlider({ Name = "Smoothing Speed", Value = AS.AimSmoothingSpeed or 6,
        Min = 1, Max = 20,
        Callback = function(v) aSet("AimSmoothingSpeed", v) end })
    secA:AddSlider({ Name = "Aimbot Update Rate (Hz)", Value = AS.AimbotHz or 120,
        Min = 30, Max = 500,
        Callback = function(v) aSet("AimbotHz", v) end })
    secA:AddToggle({ Name = "Target NPCs (rigs/dummies)", Value = AS.TargetNPCs or false,
        Callback = function(v) aSet("TargetNPCs", v) end })
    secA:AddTextbox({ Name = "NPC name filter (optional, substring)", Value = AS.NPCNameFilter or "",
        Callback = function(v) aSet("NPCNameFilter", v) end })

    --// ==== Prediction ====
    local predSec = H._UI.AimbotTab:CreateSection({ Name = "Prediction" })
    predSec:AddToggle({ Name = "Enabled", Value = AS.PredictionEnabled or false,
        Callback = function(v) aSet("PredictionEnabled", v) end })
    predSec:AddSlider({ Name = "Prediction X (%)", Value = AS.PredictionX or 0,
        Min = -100, Max = 100,
        Callback = function(v) aSet("PredictionX", v) end })
    predSec:AddSlider({ Name = "Prediction Y (%)", Value = AS.PredictionY or 0,
        Min = -100, Max = 100,
        Callback = function(v) aSet("PredictionY", v) end })
    predSec:AddSlider({ Name = "Base Time (s)", Value = AS.PredictionTime or 0.15,
        Min = 0.01, Max = 0.5, Decimals = 2,
        Callback = function(v) aSet("PredictionTime", v) end })

    --// ==== Visibility ====
    local secW = H._UI.AimbotTab:CreateSection({ Name = "Visibility", Side = "Right" })
    secW:AddToggle({ Name = "WallCheck", Value = AS.WallCheck or false,
        Callback = function(v) aSet("WallCheck", v) end })
    secW:AddDropdown({ Name = "WallCheck Mode", Value = AS.WallCheckMode or "Perfect",
        List = wallCheckModes,
        Callback = function(v) aSet("WallCheckMode", v) end })
    secW:AddToggle({ Name = "Delay Shot", Value = AS.DelayShot ~= false,
        Callback = function(v) aSet("DelayShot", v) end })
    secW:AddToggle({ Name = "Alive Check", Value = AS.AliveCheck ~= false,
        Callback = function(v) aSet("AliveCheck", v) end })
    secW:AddToggle({ Name = "Team Check",
        Value = (AS.TeamCheck and AS.TeamCheck.Enabled) ~= false,
        Callback = function(v) aSetTeam("Enabled", v) end })
    secW:AddDropdown({ Name = "Team Mode",
        Value = (AS.TeamCheck and AS.TeamCheck.Mode) or "Enemies",
        List = teamModes,
        Callback = function(v) aSetTeam("Mode", v) end })
    secW:AddToggle({ Name = "Treat Neutrals as Enemies",
        Value = (AS.TeamCheck and AS.TeamCheck.TreatNeutralAsEnemy) ~= false,
        Callback = function(v) aSetTeam("TreatNeutralAsEnemy", v) end })

    --// ==== Silent Aim ====
    local secD = H._UI.AimbotTab:CreateSection({ Name = "Silent Aim", Side = "Right" })
    secD:AddToggle({ Name = "Enabled", Value = AS.SilentAim ~= false,
        Callback = function(v) aSet("SilentAim", v) end })

    local modeStatusLabel = nil
    local function refreshModeLabel()
        if not modeStatusLabel then return end
        local A = Aimbot.AutoDetect
        local txt
        if A and A.Active then
            txt = "Scanning: " .. tostring(A.TestMode) .. " (" .. tostring(A.HookCallCount) .. ")"
        elseif A and A.SelectedMethod then
            txt = "Auto -> " .. tostring(A.SelectedMethod)
        else
            txt = "Mode: " .. tostring(AS.SilentAimMode or "Auto")
        end
        pcall(function() modeStatusLabel:SetLabel(txt) end)
    end

    secD:AddDropdown({ Name = "Mode", Value = AS.SilentAimMode or "Auto",
        List = silentAimModes,
        Callback = function(v)
            aSet("SilentAimMode", v)
            if Aimbot.Internal then Aimbot.Internal.LastManageKey = nil end

            if v ~= "RayHook"          and Aimbot.RemoveRayHook         then pcall(Aimbot.RemoveRayHook)         end
            if v ~= "RayNew"           and Aimbot.RemoveRayNewHook      then pcall(Aimbot.RemoveRayNewHook)      end
            if v ~= "Vector3Unit"      and Aimbot.RemoveVector3UnitHook then pcall(Aimbot.RemoveVector3UnitHook) end
            if v ~= "ScreenPointToRay" and Aimbot.RemoveSPRHook         then pcall(Aimbot.RemoveSPRHook)         end
            if v ~= "MouseHit" and v ~= "MouseFull" and Aimbot.RemoveMouseHook then pcall(Aimbot.RemoveMouseHook)   end
            if v ~= "FireServer"       and Aimbot.RemoveFireServerHook  then pcall(Aimbot.RemoveFireServerHook)  end
            if v ~= "CFrameHook"       and Aimbot.RemoveCFrameHook      then pcall(Aimbot.RemoveCFrameHook)      end
            if v ~= "Vector3New"       and Aimbot.RemoveVector3NewHook  then pcall(Aimbot.RemoveVector3NewHook)  end

            if v ~= "Auto" and Aimbot.CancelAutoScan then pcall(Aimbot.CancelAutoScan) end
            refreshModeLabel()
        end })

    --// Use Backtrack — стрельба в ghost-позицию (экспериментально)
    secD:AddToggle({ Name = "Use Backtrack", Value = AS.UseBacktrack or false,
        Callback = function(v)
            aSet("UseBacktrack", v)
            if v then
                local ok = H.Exploits
                    and H.Exploits.Settings
                    and H.Exploits.Settings.BacktrackEnabled
                if not ok then
                    warn("[AirHub] Use Backtrack: H.Exploits не загружен или Backtrack не включён в Exploits tab.")
                end
            end
        end })

    --// Aim at ghost — если выключено, стреляем в реального игрока (kills работают)
    secD:AddToggle({ Name = "Aim At Ghost (experimental)", Value = AS.BacktrackAimAtGhost or false,
        Callback = function(v) aSet("BacktrackAimAtGhost", v) end })

    do
        local okLabel = pcall(function()
            modeStatusLabel = secD:AddLabel({ Name = "Mode Status", Text = "Mode: " .. tostring(AS.SilentAimMode or "Auto") })
        end)
        if not okLabel then modeStatusLabel = nil end
    end

    secD:AddButton({ Name = "Run Auto-Scan", Callback = function()
        if Aimbot.RunAutoScan then
            Aimbot.RunAutoScan()
            refreshModeLabel()
        end
    end })
    secD:AddButton({ Name = "Cancel Auto-Scan", Callback = function()
        if Aimbot.CancelAutoScan then
            Aimbot.CancelAutoScan()
            refreshModeLabel()
        end
    end })

    task.spawn(function()
        while not H.ShuttingDown do
            refreshModeLabel()
            task.wait(0.2)
        end
    end)

    --// ==== Wallbang ====
    local secWB = H._UI.AimbotTab:CreateSection({ Name = "Wallbang", Side = "Right" })

    local function aSetWB(key, val)
        if Aimbot.Settings then Aimbot.Settings[key] = val end
    end

    secWB:AddToggle({ Name = "Enabled",
        Value = AS.WallbangEnabled or false,
        Callback = function(v) aSetWB("WallbangEnabled", v) end })

    secWB:AddDropdown({ Name = "Method",
        Value = AS.WallbangMethod or "RemotePatch",
        List = wallbangModes,
        Callback = function(v) aSetWB("WallbangMethod", v) end })

    secWB:AddTextbox({ Name = "Hold Time (s) — 0.05-0.5",
        Value = tostring(AS.WallbangHoldTime or 0.1),
        Callback = function(v)
            local n = tonumber(v)
            if n then aSetWB("WallbangHoldTime", math.clamp(n, 0.05, 0.5)) end
        end })

    secWB:AddTextbox({ Name = "Max Distance (studs)",
        Value = tostring(AS.WallbangDistance or 500),
        Callback = function(v)
            local n = tonumber(v)
            if n and n > 0 then aSetWB("WallbangDistance", math.floor(n)) end
        end })

    --// ==== TP Aim ====
    local secTP = H._UI.AimbotTab:CreateSection({ Name = "TP Aim", Side = "Right" })

    local function aSetTP(key, val)
        if Aimbot.Settings then Aimbot.Settings[key] = val end
    end

    secTP:AddToggle({ Name = "Enabled",
        Value = AS.TPAimEnabled or false,
        Callback = function(v) aSetTP("TPAimEnabled", v) end })

    secTP:AddDropdown({ Name = "Method",
        Value = AS.TPAimMethod or "MagicBullet",
        List = { "MagicBullet", "InfiniteTP" },
        Callback = function(v) aSetTP("TPAimMethod", v) end })

    secTP:AddTextbox({ Name = "InfiniteTP Key (KeyCode)",
        Value = AS.TPAimKey or "E",
        Callback = function(v)
            if v and v ~= "" then aSetTP("TPAimKey", v) end
        end })

    secTP:AddTextbox({ Name = "TP Distance (studs)",
        Value = tostring(AS.TPAimDistance or 5),
        Callback = function(v)
            local n = tonumber(v)
            if n and n > 0 then aSetTP("TPAimDistance", n) end
        end })

    secTP:AddToggle({ Name = "Return on kill (MagicBullet)",
        Value = AS.TPAimReturnOnKill ~= false,
        Callback = function(v) aSetTP("TPAimReturnOnKill", v) end })

    --// ==== Auto Shoot ====
    local secAS = H._UI.AimbotTab:CreateSection({ Name = "Auto Shoot", Side = "Right" })
    secAS:AddToggle({ Name = "Enabled", Value = (AS.AutoShoot and AS.AutoShoot.Enabled) or false,
        Callback = function(v) aSetAS("Enabled", v) end })
    secAS:AddToggle({ Name = "Only when aiming", Value = (AS.AutoShoot and AS.AutoShoot.OnlyWhenAiming) ~= false,
        Callback = function(v) aSetAS("OnlyWhenAiming", v) end })
    secAS:AddTextbox({ Name = "Manual delay (s)",
        Value = tostring((AS.AutoShoot and AS.AutoShoot.FireRate) or 0.05),
        Callback = function(v)
            local n = tonumber(v)
            if n then aSetAS("FireRate", math.clamp(n, 0.001, 1)) end
        end })
    secAS:AddDropdown({ Name = "Shoot Key", Value = "Left Click",
        List = { "Left Click", "Right Click" },
        Callback = function(v)
            aSetAS("ShootKey", (v == "Left Click") and "MouseButton1" or "MouseButton2")
        end })
    secAS:AddToggle({ Name = "AutoStop",
        Value = (AS.AutoShoot and AS.AutoShoot.AutoStop and AS.AutoShoot.AutoStop.Enabled) or false,
        Callback = function(v)
            if Aimbot.Settings and Aimbot.Settings.AutoShoot and Aimbot.Settings.AutoShoot.AutoStop then
                Aimbot.Settings.AutoShoot.AutoStop.Enabled = v
            end
        end })
    secAS:AddSlider({ Name = "Stop time (s)",
        Value = (AS.AutoShoot and AS.AutoShoot.AutoStop and AS.AutoShoot.AutoStop.Time) or 0.1,
        Min = 0.01, Max = 0.5, Decimals = 2,
        Callback = function(v)
            if Aimbot.Settings and Aimbot.Settings.AutoShoot and Aimbot.Settings.AutoShoot.AutoStop then
                Aimbot.Settings.AutoShoot.AutoStop.Time = v
            end
        end })

    --// ==== FOV ====
    local secE = H._UI.AimbotTab:CreateSection({ Name = "FOV" })
    secE:AddToggle({ Name = "Enabled", Value = (Aimbot.FOVSettings and Aimbot.FOVSettings.Enabled) ~= false,
        Callback = function(v) aSetFov("Enabled", v) end })
    secE:AddToggle({ Name = "Visible", Value = (Aimbot.FOVSettings and Aimbot.FOVSettings.Visible) ~= false,
        Callback = function(v) aSetFov("Visible", v) end })
    secE:AddSlider({ Name = "Radius", Value = (Aimbot.FOVSettings and Aimbot.FOVSettings.Amount) or 90,
        Min = 10, Max = 300,
        Callback = function(v) aSetFov("Amount", v) end })

    ShowError("AirHub UI core loaded")
end)
