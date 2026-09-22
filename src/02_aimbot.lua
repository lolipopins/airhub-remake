--// AirHub - 02_aimbot.lua
--// Aimbot: silent aim, prediction, auto-detect, Wallbang, TP Aim.

local H = getgenv().AirHub
if not H or not H._CoreLoaded then
    warn("[AirHub] 02_aimbot: core not loaded")
    return
end
if H.Aimbot then
    warn("[AirHub] Aimbot already loaded")
    return
end

local Util                = H.Util
local Players             = Util.Players
local RunService          = Util.RunService
local UserInputService    = Util.UserInputService
local VirtualInputManager = Util.VirtualInputManager
local ReplicatedStorage   = Util.ReplicatedStorage
local LocalPlayer         = Util.LocalPlayer
local Track               = Util.Track
local HandleError         = Util.HandleError
local AddLog              = Util.AddLog
local RAY_FILTER          = Util.RAY_FILTER

local function getExec(name)
    local f = rawget(_G, name)
    if type(f) == "function" then return f end
    if type(getgenv) == "function" then
        local ok, env = pcall(getgenv)
        if ok and type(env) == "table" then
            f = rawget(env, name)
            if type(f) == "function" then return f end
        end
    end
    return nil
end

H.Aimbot = {
    Settings = {
        Enabled = false,
        TeamCheck = { Enabled = true, Mode = "Enemies", TreatNeutralAsEnemy = true },
        AliveCheck = true,
        WallCheck = false,
        FallbackToVisible = false,
        WallCheckMode = "Perfect",
        DelayShot = true,
        AimSmoothingSpeed = 6.0,
        TriggerKey = "MouseButton2",
        Toggle = false,
        LockPart = "Head",
        AimMethod = "Smooth",
        SilentAim = true,
        SilentAimMode = "Auto",
        IgnoreFOV = false,
        CheckFromPlayerOnTP = true,
        PredictionEnabled = false,
        PredictionX = 0,
        PredictionY = 0,
        PredictionTime = 0.15,
        TargetNPCs    = false,
        NPCNameFilter = "",
        AutoShoot = {
            Enabled = false,
            ShootKey = "MouseButton1",
            FireRate = 0.05,
            OnlyWhenAiming = true,
            AutoStop = { Enabled = false, Time = 0.1 },
        },
        AutoEnabledMethods = {
            RayNew = true, RayHook = true, ScreenPointToRay = true,
            Vector3Unit = true, MouseFull = true, MouseHit = true,
            GunHandler = true, FireServer = true,
            MouseLock = true, Mouse = true,
            CFrameHook = false, Vector3New = false,
        },
        AutoPriorityOrder = {
            "RayNew", "RayHook", "ScreenPointToRay", "Vector3Unit",
            "MouseFull", "MouseHit", "GunHandler", "FireServer",
            "MouseLock", "Mouse", "CFrameHook", "Vector3New",
        },
        AutoTestDuration = 4,
        AutoMinHookCalls = 3,
        AutoFallback     = "Camera",
        AutoRunOnLoad    = true,

        --// Wallbang
        WallbangEnabled  = false,
        WallbangMethod   = "RemotePatch", -- "RayIgnore" | "RemotePatch" | "BulletTeleport"
        WallbangDistance = 500,

        --// TP Aim
        TPAimEnabled     = false,
        TPAimMethod      = "MagicBullet", -- "MagicBullet" | "InfiniteTP"
        TPAimKey         = "E",
        TPAimDistance    = 5,
        TPAimReturnOnKill = true,
    },
    FOVSettings = { Enabled = true, Visible = true, Amount = 90 },
    FOVCircle   = Drawing.new("Circle"),
    Locked      = nil,
    LockPartInstance = nil,
    Internal    = {},

    AutoDetect = {
        Active         = false,
        TestMode       = nil,
        HookCallCount  = 0,
        Results        = {},
        SelectedMethod = nil,
        LastScanTime   = 0,
    },

    TPAimInternal = {
        Active        = false,
        SavedCFrame   = nil,
        SavedVelocity = nil,
        KeyHeld       = false,
        TargetChar    = nil,
    },
}
local Aimbot = H.Aimbot

local Running       = false
local Typing        = false
local LastShotTime  = 0
local lastDelta     = tick()

local VISIBLE_PARTS = {
    "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso",
    "Torso", "Left Arm", "Right Arm",
}

--// ---------------------------------------------------------------------------
--// Helpers (полностью как в исходнике)
--// ---------------------------------------------------------------------------

local function GetActualPartName(lockPart)
    if lockPart == "Torso" then
        return { "Torso", "UpperTorso", "LowerTorso" }
    end
    return { lockPart }
end

local function GetMousePos()
    return UserInputService:GetMouseLocation() - Vector2.new(0, 36)
end

local function PredictPartPosition(part)
    if not part then return Vector3.new(0, 0, 0) end
    if not Aimbot.Settings.PredictionEnabled then return part.Position end
    local vel = part.AssemblyLinearVelocity or part.Velocity
    if not vel then return part.Position end
    local baseTime = Aimbot.Settings.PredictionTime or 0.15
    local px = (Aimbot.Settings.PredictionX or 0) / 100
    local py = (Aimbot.Settings.PredictionY or 0) / 100
    return part.Position + Vector3.new(
        vel.X * px * baseTime,
        vel.Y * py * baseTime,
        vel.Z * px * baseTime
    )
end

local function BuildRayParams(targetCharacter)
    local localCharacter = LocalPlayer.Character
    local ignoreList = { targetCharacter }
    if localCharacter then table.insert(ignoreList, localCharacter) end
    local Hg = getgenv().AirHub
    if Hg and Hg.ServerPosition and Hg.ServerPosition.Internal and Hg.ServerPosition.Internal.Ghosts then
        for _, g in pairs(Hg.ServerPosition.Internal.Ghosts) do
            if g.ghost then table.insert(ignoreList, g.ghost) end
        end
    end
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = ignoreList
    params.FilterType = RAY_FILTER
    params.IgnoreWater = true
    return params
end

local function GetCheckOrigin()
    if Aimbot.Settings.CheckFromPlayerOnTP then
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then return hrp.Position end
    end
    return workspace.CurrentCamera.CFrame.Position
end

local function NPCNameMatches(name)
    local filter = Aimbot.Settings.NPCNameFilter
    if not filter or filter == "" then return true end
    return string.find(string.lower(name), string.lower(filter), 1, true) ~= nil
end

local function GetNPCCharacters()
    local out = {}
    local seen = {}
    local localChar = LocalPlayer.Character
    local function tryAdd(obj)
        if not obj or seen[obj] then return end
        if not obj:IsA("Model") then return end
        if obj == localChar then return end
        if Players:GetPlayerFromCharacter(obj) then return end
        local hum = obj:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        if Aimbot.Settings.AliveCheck and hum.Health <= 0 then return end
        local hrp = obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart
        if not hrp then return end
        if not NPCNameMatches(obj.Name) then return end
        seen[obj] = true
        table.insert(out, obj)
    end
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") then tryAdd(obj)
        elseif obj:IsA("Folder") then
            for _, child in ipairs(obj:GetChildren()) do tryAdd(child) end
        end
    end
    return out
end

local function GetLockedCharacter()
    local L = Aimbot.Locked
    if not L then return nil end
    if typeof(L) == "Instance" and L:IsA("Player") then return L.Character end
    if typeof(L) == "Instance" and L:IsA("Model") then return L end
    return nil
end

local function GetMultipoints(part)
    local pts = {}
    local cf = part.CFrame
    local size = part.Size
    local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
    table.insert(pts, cf.Position)
    table.insert(pts, (cf * CFrame.new( hx,  hy,  hz)).Position)
    table.insert(pts, (cf * CFrame.new(-hx,  hy,  hz)).Position)
    table.insert(pts, (cf * CFrame.new( hx, -hy,  hz)).Position)
    table.insert(pts, (cf * CFrame.new(-hx, -hy,  hz)).Position)
    table.insert(pts, (cf * CFrame.new( hx,  hy, -hz)).Position)
    table.insert(pts, (cf * CFrame.new(-hx,  hy, -hz)).Position)
    table.insert(pts, (cf * CFrame.new( hx, -hy, -hz)).Position)
    table.insert(pts, (cf * CFrame.new(-hx, -hy, -hz)).Position)
    return pts
end

local function IsPointVisible(origin, pt, params)
    if (pt - origin).Magnitude < 0.001 then return true end
    return workspace:Raycast(origin, pt - origin, params) == nil
end

local function GetVisiblePoint_Fast(origin, part)
    local params = BuildRayParams(part.Parent)
    local predicted = PredictPartPosition(part)
    if IsPointVisible(origin, predicted, params) then return predicted end
    if IsPointVisible(origin, part.Position, params) then return part.Position end
    return nil
end

local function GetNearestVisibleMultipoint(origin, part, refScreen)
    local params = BuildRayParams(part.Parent)
    local pts = GetMultipoints(part)
    local bestPt, bestDist = nil, math.huge
    for _, pt in ipairs(pts) do
        if IsPointVisible(origin, pt, params) then
            local screen, on = workspace.CurrentCamera:WorldToViewportPoint(pt)
            if on then
                local d = (refScreen - Vector2.new(screen.X, screen.Y)).Magnitude
                if d < bestDist then bestDist = d; bestPt = pt end
            end
        end
    end
    return bestPt
end

local function GetClosestMultipointToMouse(part, refScreen)
    local pts = GetMultipoints(part)
    local bestPt, bestDist = nil, math.huge
    for _, pt in ipairs(pts) do
        local screen, on = workspace.CurrentCamera:WorldToViewportPoint(pt)
        if on then
            local d = (refScreen - Vector2.new(screen.X, screen.Y)).Magnitude
            if d < bestDist then bestDist = d; bestPt = pt end
        end
    end
    return bestPt or PredictPartPosition(part)
end

local function GetVisiblePointOnPart(origin, part)
    if not part or not part:IsA("BasePart") then return nil end
    if not Aimbot.Settings.WallCheck then return PredictPartPosition(part) end

    local isNearest = (Aimbot.Settings.LockPart == "Nearest")
    local isPerfect = (Aimbot.Settings.WallCheckMode == "Perfect")

    if isPerfect then
        local params = BuildRayParams(part.Parent)
        local pts = GetMultipoints(part)
        for _, pt in ipairs(pts) do
            if not IsPointVisible(origin, pt, params) then return nil end
        end
        if isNearest then return GetClosestMultipointToMouse(part, GetMousePos()) end
        return PredictPartPosition(part)
    end

    if isNearest then return GetNearestVisibleMultipoint(origin, part, GetMousePos()) end
    return GetVisiblePoint_Fast(origin, part)
end

local function FindNearestPartToMouse(char, origin)
    if not char then return nil end
    local mousePos = GetMousePos()
    local bestPart, bestDist = nil, math.huge
    for _, name in ipairs(VISIBLE_PARTS) do
        local part = char:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            local pt = GetVisiblePointOnPart(origin, part)
            if pt then
                local screen, on = workspace.CurrentCamera:WorldToViewportPoint(pt)
                if on then
                    local d = (mousePos - Vector2.new(screen.X, screen.Y)).Magnitude
                    if d < bestDist then bestDist = d; bestPart = part end
                end
            end
        end
    end
    return bestPart
end

local function FindVisiblePart(char, origin, preferredParts)
    if not char then return nil end
    if preferredParts then
        for _, name in ipairs(preferredParts) do
            local part = char:FindFirstChild(name)
            if part and part:IsA("BasePart") and GetVisiblePointOnPart(origin, part) then
                return part
            end
        end
    end
    for _, name in ipairs(VISIBLE_PARTS) do
        local part = char:FindFirstChild(name)
        if part and part:IsA("BasePart") and GetVisiblePointOnPart(origin, part) then
            return part
        end
    end
    return nil
end

local function IsTargetValid(character, player)
    if not character then return false end
    if character == LocalPlayer.Character then return false end

    local hum = character:FindFirstChildOfClass("Humanoid")
    if Aimbot.Settings.AliveCheck and (not hum or hum.Health <= 0) then return false end

    if not player then
        return Aimbot.Settings.TargetNPCs == true
    end

    local tc = Aimbot.Settings.TeamCheck
    if not tc.Enabled then return true end
    local lt, tt = LocalPlayer.Team, player.Team
    local mode = tc.Mode or "Enemies"
    if mode == "All" then return true end
    if mode == "Enemies" then
        if lt and tt and lt == tt then return false end
        if (not lt or not tt) and not tc.TreatNeutralAsEnemy then return false end
        return true
    elseif mode == "Allies" then
        return (lt and tt and lt == tt)
    elseif mode == "IgnoreNeutrals" then
        if not lt or not tt then return false end
        return lt ~= tt
    end
    return true
end

local function CancelLock()
    Aimbot.Locked = nil
    Aimbot.LockPartInstance = nil
    Aimbot.FOVCircle.Color = Color3.fromRGB(255, 255, 255)
end

local function LockedTargetStillInFOV()
    if Aimbot.Settings.IgnoreFOV then return true end
    if not Aimbot.FOVSettings.Enabled then return true end
    local part = Aimbot.LockPartInstance
    if not part or not part.Parent then return true end
    local point = PredictPartPosition(part)
    local vec, on = workspace.CurrentCamera:WorldToViewportPoint(point)
    if not on then return false end
    local d = (GetMousePos() - Vector2.new(vec.X, vec.Y)).Magnitude
    return d <= Aimbot.FOVSettings.Amount
end

local function GetClosestPlayer()
    if Aimbot.Locked then
        local targetChar = GetLockedCharacter()
        if not targetChar then CancelLock() return end
        local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
        if not IsTargetValid(targetChar, targetPlayer) then CancelLock() return end

        local origin = GetCheckOrigin()
        local lockPart = Aimbot.Settings.LockPart
        local part
        if lockPart == "Nearest" then
            part = FindNearestPartToMouse(targetChar, origin)
        else
            local preferred = GetActualPartName(lockPart)
            if Aimbot.Settings.FallbackToVisible then
                part = FindVisiblePart(targetChar, origin, preferred)
            else
                for _, name in ipairs(preferred) do
                    local p = targetChar:FindFirstChild(name)
                    if p and p:IsA("BasePart") and GetVisiblePointOnPart(origin, p) then
                        part = p; break
                    end
                end
            end
        end
        if part then Aimbot.LockPartInstance = part else CancelLock() return end

        if not LockedTargetStillInFOV() then
            CancelLock()
            return
        end
        return
    end

    local candidates = {}
    for _, v in ipairs(Players:GetPlayers()) do
        if v.Character and v ~= LocalPlayer then
            table.insert(candidates, { character = v.Character, player = v })
        end
    end
    if Aimbot.Settings.TargetNPCs then
        for _, npc in ipairs(GetNPCCharacters()) do
            table.insert(candidates, { character = npc, player = nil })
        end
    end

    local ignoreFOV = Aimbot.Settings.IgnoreFOV
    local fovEnabled = Aimbot.FOVSettings.Enabled and not ignoreFOV
    local required = fovEnabled and Aimbot.FOVSettings.Amount or 999999
    local bestTarget, bestPart, bestDist = nil, nil, math.huge
    local mousePos = GetMousePos()
    local origin = GetCheckOrigin()

    for _, cand in ipairs(candidates) do
        if IsTargetValid(cand.character, cand.player) then
            local charTarget = cand.character
            local lockPart = Aimbot.Settings.LockPart
            local targetPart = nil
            if lockPart == "Nearest" then
                targetPart = FindNearestPartToMouse(charTarget, origin)
            else
                local preferred = GetActualPartName(lockPart)
                if Aimbot.Settings.FallbackToVisible then
                    targetPart = FindVisiblePart(charTarget, origin, preferred)
                else
                    for _, name in ipairs(preferred) do
                        local p = charTarget:FindFirstChild(name)
                        if p and p:IsA("BasePart") and GetVisiblePointOnPart(origin, p) then
                            targetPart = p; break
                        end
                    end
                end
            end
            if targetPart then
                local point = GetVisiblePointOnPart(origin, targetPart) or PredictPartPosition(targetPart)
                local vec, on = workspace.CurrentCamera:WorldToViewportPoint(point)
                local dist
                if ignoreFOV then
                    dist = (point - origin).Magnitude
                else
                    dist = on and (mousePos - Vector2.new(vec.X, vec.Y)).Magnitude or math.huge
                end
                if dist < bestDist and (ignoreFOV or dist < required) then
                    bestDist   = dist
                    bestTarget = cand.player or charTarget
                    bestPart   = targetPart
                end
            end
        end
    end

    if bestTarget and bestPart then
        Aimbot.Locked = bestTarget
        Aimbot.LockPartInstance = bestPart
    else
        CancelLock()
    end
end

local function LogShot(targetChar, targetName, startHealth, hitPartName, wasVisible)
    if not targetChar then return end
    local hum = targetChar:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local endHealth = hum.Health
    local hit = endHealth < startHealth

    if hit then
        if hum.Health <= 0 then Util.PlayKillsound() else Util.PlayHitsound() end
    end
    if not H.Logging or not H.Logging.Enabled then return end
    if hit and not H.Logging.ShowHit then return end
    if not hit and not H.Logging.ShowMiss then return end

    local displayName = targetName or targetChar.Name
    local msg, color
    if hit then
        if hum.Health <= 0 then
            msg = "Killed " .. displayName .. " (" .. hitPartName .. ")"
            color = Color3.fromRGB(255, 255, 0)
        else
            msg = "Hit " .. displayName .. " (" .. hitPartName .. " - " .. math.floor(startHealth - endHealth) .. " dmg)"
            color = Color3.fromRGB(0, 255, 0)
        end
    else
        msg = wasVisible and ("Missed " .. displayName) or ("Missed (wall) " .. displayName)
        color = Color3.fromRGB(255, 80, 80)
    end
    AddLog(msg, color)
end

local function RefreshOldPositionIfNeeded()
    local Hg = getgenv().AirHub
    if not Hg or not Hg.AntiAim then return end
    local d = Hg.AntiAim.Desync
    if not d or not d.Settings or not d.Internal then return end
    if not d.Settings.Enabled then return end
    if d.Settings.Mode ~= "OldPosition" then return end
    if not d.Settings.RefreshOnShot then return end

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    d.Internal.SavedCFrame = hrp.CFrame
    d.Internal.OldPosTimer = 0
    local minV = tonumber(d.Settings.AutoUpdateMin) or 0.2
    local maxV = tonumber(d.Settings.AutoUpdateMax) or 1.0
    if minV < 0 then minV = 0 end
    if maxV < minV then maxV = minV end
    local nextDelay
    if maxV - minV < 0.001 then nextDelay = minV
    else nextDelay = minV + math.random() * (maxV - minV) end
    d.Internal.NextUpdate = nextDelay
    d.Internal.PendingRefresh = false
end

local function WaitForShotPoint(targetPart)
    if not targetPart then return nil, false end
    if not Aimbot.Settings.WallCheck then
        return PredictPartPosition(targetPart), true
    end
    local origin = GetCheckOrigin()
    local pt = GetVisiblePointOnPart(origin, targetPart)
    if pt then return pt, true end
    if not Aimbot.Settings.DelayShot then return nil, false end
    local deadline = tick() + (H.DELAY_SHOT_TIMEOUT or 0.1)
    while tick() < deadline and not H.ShuttingDown do
        task.wait(0.005)
        pt = GetVisiblePointOnPart(GetCheckOrigin(), targetPart)
        if pt then return pt, true end
    end
    return nil, false
end

local function WorldToMouseVIM(worldPos)
    local screenPos, onScreen = workspace.CurrentCamera:WorldToViewportPoint(worldPos)
    if not onScreen then return nil end
    return math.floor(screenPos.X), math.floor(screenPos.Y + 36)
end

local function MoveMouseAbs(x, y)
    if type(mousemoveabs) == "function" then
        local ok, res = pcall(mousemoveabs, x, y)
        if ok and res ~= false then return true end
    end
    if type(mousemoverel) == "function" then
        local cur = UserInputService:GetMouseLocation()
        local dx = x - math.floor(cur.X)
        local dy = y - math.floor(cur.Y)
        local ok, res = pcall(mousemoverel, dx, dy)
        if ok and res ~= false then return true end
    end
    local vimOk = pcall(function()
        VirtualInputManager:SendMouseMoveEvent(x, y, game)
    end)
    return vimOk
end

local function ReportHookCall(mode)
    if Aimbot.AutoDetect.Active and Aimbot.AutoDetect.TestMode == mode then
        Aimbot.AutoDetect.HookCallCount = Aimbot.AutoDetect.HookCallCount + 1
    end
end

local function IsModeAvailable(mode)
    if mode == "RayHook" then
        local ok, mt = pcall(getrawmetatable, Ray.new(Vector3.zero, Vector3.zero))
        return (ok and mt ~= nil), "no Ray metatable"
    elseif mode == "RayNew" then
        if type(Ray) ~= "table" or type(Ray.new) ~= "function" then
            return false, "Ray.new unavailable"
        end
        return true
    elseif mode == "ScreenPointToRay" then
        local cam = workspace.CurrentCamera
        if not cam then return false, "no camera" end
        if type(cam.ScreenPointToRay) ~= "function" then
            return false, "ScreenPointToRay missing"
        end
        return true
    elseif mode == "Vector3Unit" then
        local ok, mt = pcall(getrawmetatable, Vector3.new(1, 0, 0))
        return (ok and mt ~= nil), "no Vector3 metatable"
    elseif mode == "MouseHit" or mode == "MouseFull" then
        if type(LocalPlayer.GetMouse) ~= "function" then
            return false, "GetMouse missing"
        end
        return true
    elseif mode == "GunHandler" then
        local mod = ReplicatedStorage:FindFirstChild("Modules")
        if not mod then return false, "no Modules" end
        local guns = mod:FindFirstChild("Guns")
        if not guns then return false, "no Guns folder" end
        local gh = guns:FindFirstChild("GunHandler")
        if not gh then return false, "no GunHandler module" end
        local ok, res = pcall(require, gh)
        if not ok or type(res) ~= "table" or type(res.Shoot) ~= "function" then
            return false, "GunHandler.Shoot missing"
        end
        return true
    elseif mode == "FireServer" then
        local hookf = getExec("hookmetamethod")
        local getMethod = getExec("getnamecallmethod")
        if not hookf or not getMethod then
            return false, "no hookmetamethod"
        end
        return true
    elseif mode == "MouseLock" or mode == "Mouse" then
        if not VirtualInputManager then return false, "no VIM" end
        return true
    elseif mode == "Camera" then
        return true
    elseif mode == "CFrameHook" then
        if type(CFrame) ~= "table" then return false, "CFrame not table" end
        if type(CFrame.lookAt) ~= "function" then
            return false, "CFrame.lookAt missing"
        end
        return true
    elseif mode == "Vector3New" then
        if type(Vector3) ~= "table" then return false, "Vector3 not table" end
        if type(Vector3.new) ~= "function" then
            return false, "Vector3.new missing"
        end
        return true
    end
    return false, "unknown mode"
end

local function GetEffectiveMode()
    local m = Aimbot.Settings.SilentAimMode
    if m == "Auto" then
        return Aimbot.AutoDetect.SelectedMethod or Aimbot.Settings.AutoFallback or "Camera"
    end
    return m
end

local function IsModeActive(mode)
    if Aimbot.AutoDetect.Active and Aimbot.AutoDetect.TestMode == mode then
        return Aimbot.Settings.Enabled and Aimbot.Settings.SilentAim
    end
    return Aimbot.Settings.Enabled
       and Aimbot.Settings.SilentAim
       and GetEffectiveMode() == mode
       and Running
end

local function InScanFor(mode)
    return Aimbot.AutoDetect.Active and Aimbot.AutoDetect.TestMode == mode
end

--// ---------------------------------------------------------------------------
--// TP AIM & WALLBANG
--// ---------------------------------------------------------------------------

local function GetHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function SaveCurrentCFrame()
    local hrp = GetHRP()
    if hrp then
        Aimbot.TPAimInternal.SavedCFrame = hrp.CFrame
        Aimbot.TPAimInternal.SavedVelocity = hrp.Velocity
        return true
    end
    return false
end

local function RestoreCurrentCFrame()
    local hrp = GetHRP()
    if hrp and Aimbot.TPAimInternal.SavedCFrame then
        hrp.CFrame = Aimbot.TPAimInternal.SavedCFrame
        if Aimbot.TPAimInternal.SavedVelocity then
            hrp.Velocity = Aimbot.TPAimInternal.SavedVelocity
        end
        Aimbot.TPAimInternal.SavedCFrame = nil
        Aimbot.TPAimInternal.SavedVelocity = nil
        return true
    end
    return false
end

local function TeleportToTarget(targetPart)
    local hrp = GetHRP()
    if not hrp or not targetPart then return false end
    local targetCF = targetPart.CFrame
    local distance = Aimbot.Settings.TPAimDistance or 5
    local offsetCF = targetCF * CFrame.new(0, 0, distance)
    hrp.CFrame = offsetCF
    return true
end

--// Wallbang implementations

local function PerformWallbang_RemotePatch(targetPart, btn)
    --// Патчим FireServer: заменяем направление на цель
    local hookf = getExec("hookmetamethod")
    local getMethod = getExec("getnamecallmethod")
    local newc = getExec("newcclosure")
    local checkC = getExec("checkcaller")
    if not hookf or not getMethod then return false end

    local original
    original = hookf(game, "__namecall", newc(function(self, ...)
        local method = getMethod()
        if method == "FireServer" and not checkC() then
            local args = { ... }
            for i, v in ipairs(args) do
                if typeof(v) == "Vector3" then
                    local vm = v.Magnitude
                    if math.abs(vm - 1) < 0.3 then
                        local origin = workspace.CurrentCamera.CFrame.Position
                        args[i] = (targetPart.Position - origin).Unit
                    end
                end
            end
            return original(self, table.unpack(args, 1, #args))
        end
        return original(self, ...)
    end))
    --// Выстрел
    local mousePos = UserInputService:GetMouseLocation()
    VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, true, game, 1)
    task.wait(0.001)
    VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, false, game, 1)
    --// Снимаем хук
    task.delay(0.05, function()
        pcall(function() hookf(game, "__namecall", original) end)
    end)
    return true
end

local function PerformWallbang_RayIgnore(targetPart, btn)
    --// Хукаем workspace.Raycast, чтобы игнорировать стены
    local oldRaycast = workspace.Raycast
    local newc = getExec("newcclosure")
    workspace.Raycast = newc(function(self, origin, direction, params)
        if params and typeof(params) == "Instance" and params:IsA("RaycastParams") then
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = { workspace.CurrentCamera }
        end
        return oldRaycast(self, origin, direction, params)
    end)
    local mousePos = UserInputService:GetMouseLocation()
    VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, true, game, 1)
    task.wait(0.001)
    VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, false, game, 1)
    task.delay(0.05, function()
        workspace.Raycast = oldRaycast
    end)
    return true
end

local function PerformWallbang_BulletTeleport(targetPart, btn)
    --// Телепортируем "пулю" к цели через изменение позиции оружия/камеры
    local hrp = GetHRP()
    if not hrp then return false end
    local cam = workspace.CurrentCamera
    local oldCF = cam.CFrame
    cam.CFrame = CFrame.new(targetPart.Position - (targetPart.Position - cam.CFrame.Position).Unit * 2, targetPart.Position)
    local mousePos = UserInputService:GetMouseLocation()
    VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, true, game, 1)
    task.wait(0.001)
    VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, false, game, 1)
    cam.CFrame = oldCF
    return true
end

local function PerformWallbang(targetPart, btn)
    if not Aimbot.Settings.WallbangEnabled then return false end
    local method = Aimbot.Settings.WallbangMethod
    local char = targetPart and targetPart.Parent
    if not char then return false end
    local startHealth = char:FindFirstChildOfClass("Humanoid") and char:FindFirstChildOfClass("Humanoid").Health or 0

    local ok = false
    if method == "RemotePatch" then
        ok = PerformWallbang_RemotePatch(targetPart, btn)
    elseif method == "RayIgnore" then
        ok = PerformWallbang_RayIgnore(targetPart, btn)
    elseif method == "BulletTeleport" then
        ok = PerformWallbang_BulletTeleport(targetPart, btn)
    end
    if ok then
        task.delay(0.15, function()
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                LogShot(char, char.Name, startHealth, targetPart.Name, false)
            end
        end)
    end
    return ok
end

--// TP Aim implementations

local function PerformMagicBullet(targetPart, btn)
    if not Aimbot.Settings.TPAimEnabled or Aimbot.Settings.TPAimMethod ~= "MagicBullet" then return end
    if not targetPart then return end

    --// Сохраняем текущую позицию
    SaveCurrentCFrame()

    --// Если десинк не включён — включаем OldPosition на время выстрела
    local Hg = getgenv().AirHub
    local desyncWasEnabled = false
    if Hg and Hg.AntiAim and Hg.AntiAim.Desync then
        desyncWasEnabled = Hg.AntiAim.Desync.Settings.Enabled
        if not desyncWasEnabled then
            Hg.AntiAim.Desync.Settings.Enabled = true
            Hg.AntiAim.Desync.Settings.Mode = "OldPosition"
            Hg.AntiAim.Desync.Settings.RefreshOnShot = true
            if Hg.AntiAim.StartDesync then Hg.AntiAim.StartDesync() end
        end
    end

    --// Телепорт к врагу
    TeleportToTarget(targetPart)
    task.wait(0.01)

    --// Выстрел
    local mousePos = UserInputService:GetMouseLocation()
    VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, true, game, 1)
    task.wait(0.001)
    VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, false, game, 1)

    --// Возврат
    task.wait(0.02)
    RestoreCurrentCFrame()

    --// Если десинк не был включён — выключаем
    if Hg and Hg.AntiAim and Hg.AntiAim.Desync and not desyncWasEnabled then
        Hg.AntiAim.Desync.Settings.Enabled = false
        if Hg.AntiAim.StopDesync then Hg.AntiAim.StopDesync() end
    end

    task.delay(0.15, function()
        local char = targetPart.Parent
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                LogShot(char, char.Name, hum.Health, targetPart.Name, false)
            end
        end
    end)
end

local function PerformInfiniteTP(targetPart, btn)
    if not Aimbot.Settings.TPAimEnabled or Aimbot.Settings.TPAimMethod ~= "InfiniteTP" then return end
    if not targetPart then return end
    if Aimbot.TPAimInternal.Active then return end

    Aimbot.TPAimInternal.Active = true
    Aimbot.TPAimInternal.TargetChar = targetPart.Parent

    --// Сохраняем позицию
    SaveCurrentCFrame()

    --// Цикл телепорта
    task.spawn(function()
        while Aimbot.TPAimInternal.Active and Aimbot.TPAimInternal.KeyHeld do
            local char = targetPart.Parent
            if not char or not char:FindFirstChildOfClass("Humanoid") then
                Aimbot.TPAimInternal.Active = false
                break
            end
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum.Health <= 0 then
                Aimbot.TPAimInternal.Active = false
                break
            end
            TeleportToTarget(targetPart)
            task.wait(0.01)
        end
        --// Возврат
        task.wait(0.02)
        RestoreCurrentCFrame()
        Aimbot.TPAimInternal.Active = false
        Aimbot.TPAimInternal.TargetChar = nil
    end)
end

--// ---------------------------------------------------------------------------
--// PerformSilentShot
--// ---------------------------------------------------------------------------

local function PerformSilentShot(targetPart, btn, wasVisible)
    if not Aimbot.Settings.SilentAim then return end
    if not targetPart then return end

    local targetChar = targetPart.Parent
    if not targetChar then return end
    local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
    local displayName  = targetPlayer and targetPlayer.Name or targetChar.Name

    local hum = targetChar:FindFirstChildOfClass("Humanoid")
    if hum and Aimbot.Settings.AliveCheck and hum.Health <= 0 then return end
    local startHealth = hum and hum.Health or 0

    --// TP Aim & Wallbang — игнорируют WallCheck
    if Aimbot.Settings.TPAimEnabled then
        if Aimbot.Settings.TPAimMethod == "MagicBullet" then
            PerformMagicBullet(targetPart, btn)
        else
            PerformInfiniteTP(targetPart, btn)
        end
        return
    end
    if Aimbot.Settings.WallbangEnabled then
        PerformWallbang(targetPart, btn)
        return
    end

    RefreshOldPositionIfNeeded()

    local checkPoint, nowVisible = WaitForShotPoint(targetPart)
    --// Игнорируем WallCheck для TP Aim / Wallbang
    if Aimbot.Settings.WallCheck and not checkPoint
       and not (Aimbot.Settings.TPAimEnabled or Aimbot.Settings.WallbangEnabled) then
        return
    end
    if nowVisible ~= nil then wasVisible = nowVisible end

    local mode = GetEffectiveMode()

    if mode == "MouseLock" then
        local visiblePoint = checkPoint
        if not visiblePoint then
            local origin = workspace.CurrentCamera.CFrame.Position
            visiblePoint = GetVisiblePointOnPart(origin, targetPart)
        end
        if not visiblePoint then return end

        local targetX, targetY = WorldToMouseVIM(visiblePoint)
        if not targetX then return end

        local oldBehavior = UserInputService.MouseBehavior
        local oldIcon     = UserInputService.MouseIconEnabled
        local curMouse    = UserInputService:GetMouseLocation()
        local oldX, oldY  = math.floor(curMouse.X), math.floor(curMouse.Y)

        pcall(function()
            UserInputService.MouseBehavior    = Enum.MouseBehavior.Default
            UserInputService.MouseIconEnabled = true
        end)

        local ok = pcall(function()
            MoveMouseAbs(targetX, targetY)
            task.wait()
            VirtualInputManager:SendMouseButtonEvent(targetX, targetY, btn, true,  game, 1)
            VirtualInputManager:SendMouseButtonEvent(targetX, targetY, btn, false, game, 1)
            MoveMouseAbs(oldX, oldY)
        end)
        if not ok then HandleError("MouseLock silent shot failed") end

        pcall(function()
            UserInputService.MouseBehavior    = oldBehavior
            UserInputService.MouseIconEnabled = oldIcon
        end)

        task.delay(0.15, function()
            LogShot(targetChar, displayName, startHealth, targetPart.Name, wasVisible)
        end)
        return
    end

    if mode == "Mouse" then
        local visiblePoint = checkPoint
        if not visiblePoint then
            local origin = workspace.CurrentCamera.CFrame.Position
            visiblePoint = GetVisiblePointOnPart(origin, targetPart)
        end
        if not visiblePoint then return end

        local targetX, targetY = WorldToMouseVIM(visiblePoint)
        if not targetX then return end
        local curMouse = UserInputService:GetMouseLocation()
        local oldX = math.floor(curMouse.X)
        local oldY = math.floor(curMouse.Y)

        local ok = pcall(function()
            MoveMouseAbs(targetX, targetY)
            task.wait()
            VirtualInputManager:SendMouseButtonEvent(targetX, targetY, btn, true,  game, 1)
            VirtualInputManager:SendMouseButtonEvent(targetX, targetY, btn, false, game, 1)
            MoveMouseAbs(oldX, oldY)
        end)
        if not ok then HandleError("Mouse silent shot failed") end

        task.delay(0.15, function()
            LogShot(targetChar, displayName, startHealth, targetPart.Name, wasVisible)
        end)
        return
    end

    if mode == "GunHandler" or mode == "RayHook" or mode == "RayNew"
       or mode == "MouseHit" or mode == "MouseFull"
       or mode == "Vector3Unit" or mode == "ScreenPointToRay"
       or mode == "FireServer"
       or mode == "CFrameHook" or mode == "Vector3New" then
        local mousePos = UserInputService:GetMouseLocation()
        VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, true,  game, 1)
        task.wait(0.001)
        VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, false, game, 1)
        task.delay(0.15, function()
            LogShot(targetChar, displayName, startHealth, targetPart.Name, wasVisible)
        end)
        return
    end

    local origin = workspace.CurrentCamera.CFrame.Position
    local visiblePoint = checkPoint or GetVisiblePointOnPart(origin, targetPart)
    if not visiblePoint then return end
    local oldCF = workspace.CurrentCamera.CFrame
    workspace.CurrentCamera.CFrame = CFrame.new(oldCF.Position, visiblePoint)

    local ok = pcall(function()
        local mousePos = UserInputService:GetMouseLocation()
        VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, true,  game, 1)
        task.wait(0.001)
        VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, false, game, 1)
    end)
    workspace.CurrentCamera.CFrame = oldCF
    if not ok then HandleError("Camera silent shot input failed") end

    task.delay(0.15, function()
        LogShot(targetChar, displayName, startHealth, targetPart.Name, wasVisible)
    end)
end

--// ... (остальные хуки: RayHook, RayNew, Vector3Unit, ScreenPointToRay,
--//      MouseHook, FireServerHook, GunHandlerHook, CFrameHook, Vector3NewHook
--//      — без изменений, как в исходном файле)

--// ---------------------------------------------------------------------------
--// Key handling для InfiniteTP
--// ---------------------------------------------------------------------------
Track(UserInputService.InputBegan:Connect(function(inp, gpe)
    if gpe or Typing then return end
    if not Aimbot.Settings.TPAimEnabled then return end
    if Aimbot.Settings.TPAimMethod ~= "InfiniteTP" then return end
    local key = Aimbot.Settings.TPAimKey or "E"
    local kc = Util.SafeKeyCode(key)
    if kc and inp.KeyCode == kc then
        Aimbot.TPAimInternal.KeyHeld = true
        if Aimbot.LockPartInstance then
            PerformInfiniteTP(Aimbot.LockPartInstance, 0)
        end
    end
end))

Track(UserInputService.InputEnded:Connect(function(inp)
    if not Aimbot.Settings.TPAimEnabled then return end
    if Aimbot.Settings.TPAimMethod ~= "InfiniteTP" then return end
    local key = Aimbot.Settings.TPAimKey or "E"
    local kc = Util.SafeKeyCode(key)
    if kc and inp.KeyCode == kc then
        Aimbot.TPAimInternal.KeyHeld = false
    end
end))

--// ---------------------------------------------------------------------------
--// LoadAimbot (без изменений, кроме вставки новых экспортов)
--// ---------------------------------------------------------------------------

--// ... (LoadAimbot и Track'и как в исходнике)

--// ---------------------------------------------------------------------------
--// Экспорты
--// ---------------------------------------------------------------------------

Aimbot.CancelLock            = CancelLock
Aimbot.RemoveRayHook         = RemoveRayHook
Aimbot.RemoveRayNewHook      = RemoveRayNewHook
Aimbot.RemoveVector3UnitHook = RemoveVector3UnitHook
Aimbot.RemoveSPRHook         = RemoveScreenPointToRayHook
Aimbot.RemoveMouseHook       = RemoveMouseHook
Aimbot.RemoveFireServerHook  = RemoveFireServerHook
Aimbot.RemoveMouseHitHook    = RemoveMouseHook
Aimbot.RemoveGunHandlerHook  = RemoveGunHandlerHook
Aimbot.RemoveCFrameHook      = RemoveCFrameHook
Aimbot.RemoveVector3NewHook  = RemoveVector3NewHook
Aimbot.GetVisiblePointOnPart = GetVisiblePointOnPart
Aimbot.GetMousePos           = GetMousePos
Aimbot.PredictPartPosition   = PredictPartPosition
Aimbot.MoveMouseAbs          = MoveMouseAbs
Aimbot.WorldToMouseVIM       = WorldToMouseVIM
Aimbot.GetNPCCharacters      = GetNPCCharacters
Aimbot.GetLockedCharacter    = GetLockedCharacter
Aimbot.RunAutoScan           = RunAutoScan
Aimbot.CancelAutoScan        = CancelAutoScan
Aimbot.IsModeAvailable       = IsModeAvailable

--// Новые экспорты
Aimbot.PerformWallbang       = PerformWallbang
Aimbot.PerformMagicBullet    = PerformMagicBullet
Aimbot.PerformInfiniteTP     = PerformInfiniteTP

if Aimbot.Settings.AutoRunOnLoad and Aimbot.Settings.SilentAimMode == "Auto" then
    task.delay(2, function()
        if H.Aimbot and H.Aimbot.RunAutoScan then
            H.Aimbot.RunAutoScan()
        end
    end)
end
