--// AirHub - 02_aimbot.lua
--// Aimbot: silent aim, prediction, auto-detect, Wallbang, TP Aim, Backtrack, diagnostics.

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
        AimbotHz = 120,
        IgnoreGameProcessed = true,

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

        WallbangEnabled  = false,
        WallbangMethod   = "RemotePatch",
        WallbangDistance = 500,

        TPAimEnabled     = false,
        TPAimMethod      = "MagicBullet",
        TPAimKey         = "E",
        TPAimDistance    = 5,
        TPAimReturnOnKill = true,

        UseBacktrack     = false,
    },
    FOVSettings = { Enabled = true, Visible = true, Amount = 90 },
    FOVCircle   = Drawing.new("Circle"),
    Locked      = nil,
    LockPartInstance = nil,
    Internal    = {
        TargetAccum  = 0,
        FovAccum     = 0,
        LastManageKey = nil,
    },

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

local function ShouldBypassWallCheck()
    return Aimbot.Settings.TPAimEnabled or Aimbot.Settings.WallbangEnabled
end

local function IsBacktrackEnabled()
    if not Aimbot.Settings.UseBacktrack then return false end
    if not H.Exploits then return false end
    if not H.Exploits.Settings or not H.Exploits.Settings.BacktrackEnabled then return false end
    if not H.Exploits.Functions then return false end
    if not H.Exploits.Functions.GetBacktrackCFrame
       and not H.Exploits.Functions.GetBacktrackCFrameSmart then
        return false
    end
    return true
end

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

    if Aimbot.Settings.UseBacktrack
       and H.Exploits
       and H.Exploits.Settings
       and H.Exploits.Settings.BacktrackEnabled
       and H.Exploits.Functions then
        local pl = Players:GetPlayerFromCharacter(part.Parent)
        if pl then
            local hitboxGuess = math.max(part.Size.X, part.Size.Y, part.Size.Z) * 0.5
            local btCF = nil
            if H.Exploits.Functions.GetBacktrackCFrameSmart then
                btCF = H.Exploits.Functions.GetBacktrackCFrameSmart(
                    pl,
                    H.Exploits.Settings.BacktrackTime,
                    hitboxGuess
                )
            elseif H.Exploits.Functions.GetBacktrackCFrame then
                btCF = H.Exploits.Functions.GetBacktrackCFrame(
                    pl,
                    H.Exploits.Settings.BacktrackTime
                )
            end
            if btCF then
                return btCF.Position
            end
        end
    end

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
    --// ignore backtrack ghost models so our wallcheck doesn't see them
    if Hg and Hg.Exploits and Hg.Exploits.Internal and Hg.Exploits.Internal.BacktrackGhosts then
        for _, ghost in pairs(Hg.Exploits.Internal.BacktrackGhosts) do
            if ghost and ghost.Parent then table.insert(ignoreList, ghost) end
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
        if obj:GetAttribute("AirHub_Ghost") then return end
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

    --// NOTE: backtrack NO LONGER bypasses wallcheck.
    --// If backtrack is enabled, PredictPartPosition returns the old position,
    --// and wallcheck runs against that old position (from origin to that point).
    --// This means: walls still block shots, but the shot goes to the OLD spot.

    if not Aimbot.Settings.WallCheck or ShouldBypassWallCheck() then
        return PredictPartPosition(part)
    end

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
    if character:GetAttribute("AirHub_Ghost") then return false end

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
    --// NOTE: backtrack NO LONGER bypasses wallcheck here either.
    if not Aimbot.Settings.WallCheck or ShouldBypassWallCheck() then
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

local function IsModeHooked(mode)
    if Aimbot.AutoDetect.Active and Aimbot.AutoDetect.TestMode == mode then
        return Aimbot.Settings.Enabled and Aimbot.Settings.SilentAim
    end
    return Aimbot.Settings.Enabled
       and Aimbot.Settings.SilentAim
       and GetEffectiveMode() == mode
end

local function ShouldRedirect(mode)
    if Aimbot.AutoDetect.Active and Aimbot.AutoDetect.TestMode == mode then
        return true
    end
    return IsModeHooked(mode) and Running
end

local function IsModeActive(mode)
    return IsModeHooked(mode)
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

    local cam = workspace.CurrentCamera
    if cam and targetPart.Parent then
        local aimPos = PredictPartPosition(targetPart)
        local camPos = cam.CFrame.Position
        if (aimPos - camPos).Magnitude > 0.001 then
            cam.CFrame = CFrame.lookAt(camPos, aimPos)
        end
    end
    return true
end

local function PerformWallbang_RemotePatch(targetPart, btn)
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
    local mousePos = UserInputService:GetMouseLocation()
    VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, true, game, 1)
    task.wait(0.001)
    VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, false, game, 1)
    task.delay(0.05, function()
        pcall(function() hookf(game, "__namecall", original) end)
    end)
    return true
end

local function PerformWallbang_RayIgnore(targetPart, btn)
    local hookf     = getExec("hookmetamethod")
    local getMethod = getExec("getnamecallmethod")
    local newc      = getExec("newcclosure")
    local checkC    = getExec("checkcaller")
    if not hookf or not getMethod then return false end

    local original
    original = hookf(game, "__namecall", newc(function(self, ...)
        local method = getMethod()
        if method == "Raycast" and not checkC() then
            local args = { ... }
            local params = args[3]
            if typeof(params) == "Instance" and params:IsA("RaycastParams") then
                pcall(function()
                    params.FilterType = Enum.RaycastFilterType.Exclude
                    params.FilterDescendantsInstances = { workspace.CurrentCamera }
                end)
            end
            return original(self, table.unpack(args, 1, #args))
        end
        return original(self, ...)
    end))

    local mousePos = UserInputService:GetMouseLocation()
    VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, true,  game, 1)
    task.wait(0.001)
    VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, false, game, 1)

    task.delay(0.05, function()
        pcall(function() hookf(game, "__namecall", original) end)
    end)
    return true
end

local function PerformWallbang_BulletTeleport(targetPart, btn)
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
    local hum = char:FindFirstChildOfClass("Humanoid")
    local startHealth = hum and hum.Health or 0

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
            local h2 = char:FindFirstChildOfClass("Humanoid")
            if h2 then
                LogShot(char, char.Name, startHealth, targetPart.Name, false)
            end
        end)
    end
    return ok
end

local function PerformMagicBullet(targetPart, btn)
    if not Aimbot.Settings.TPAimEnabled or Aimbot.Settings.TPAimMethod ~= "MagicBullet" then return end
    if not targetPart then return end

    SaveCurrentCFrame()

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

    TeleportToTarget(targetPart)
    task.wait(0.01)

    local mousePos = UserInputService:GetMouseLocation()
    VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, true, game, 1)
    task.wait(0.001)
    VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, false, game, 1)

    task.wait(0.02)
    RestoreCurrentCFrame()

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

    SaveCurrentCFrame()

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
    if Aimbot.Settings.WallCheck and not checkPoint then
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

--// ---------------------------------------------------------------------------
--// Hooks
--// ---------------------------------------------------------------------------

local RayHookActive = false
local oldRayIndex = nil

local function SetupRayHook()
    if RayHookActive then return end
    local success, mt = pcall(getrawmetatable, Ray.new(Vector3.zero, Vector3.zero))
    if not success or not mt then return end
    local savedOriginal = getgenv().__AirHubRayIndexOriginal
    if not savedOriginal then
        savedOriginal = mt.__index
        getgenv().__AirHubRayIndexOriginal = savedOriginal
    end
    oldRayIndex = savedOriginal
    mt.__index = function(t, k)
        if k == 'Direction' and not H.ShuttingDown and IsModeHooked("RayHook") then
            if InScanFor("RayHook") then
                ReportHookCall("RayHook")
                return oldRayIndex(t, k)
            end
            if not ShouldRedirect("RayHook") then
                return oldRayIndex(t, k)
            end
            local target = Aimbot.LockPartInstance
            if target then
                local origin = oldRayIndex(t, 'Origin')
                local vp = GetVisiblePointOnPart(origin, target)
                if vp then return (vp - origin).Unit
                elseif not Aimbot.Settings.WallCheck then
                    return (PredictPartPosition(target) - origin).Unit
                end
            end
        end
        return oldRayIndex(t, k)
    end
    RayHookActive = true
end

local function RemoveRayHook()
    if not RayHookActive then return end
    local success, mt = pcall(getrawmetatable, Ray.new(Vector3.zero, Vector3.zero))
    if success and mt and oldRayIndex then mt.__index = oldRayIndex end
    RayHookActive = false
end

local RayNewActive = false
local RayNewOriginal = nil

local function SetupRayNewHook()
    if RayNewActive then return end
    if type(Ray) ~= "table" then return end
    local old = Ray.new
    if type(old) ~= "function" then return end
    RayNewOriginal = old

    local newc   = getExec("newcclosure")
    local checkC = getExec("checkcaller")

    local function handler(origin, direction)
        if not H.ShuttingDown and IsModeHooked("RayNew") then
            if not (checkC and not checkC()) then
                if InScanFor("RayNew") then
                    ReportHookCall("RayNew")
                    return RayNewOriginal(origin, direction)
                end
                if not ShouldRedirect("RayNew") then
                    return RayNewOriginal(origin, direction)
                end
                local target = Aimbot.LockPartInstance
                if target then
                    local aimPos = PredictPartPosition(target)
                    local dir = aimPos - origin
                    if dir.Magnitude > 0.001 then
                        if type(direction) == "Vector3" then
                            return RayNewOriginal(origin, dir.Unit * direction.Magnitude)
                        else
                            return RayNewOriginal(origin, dir.Unit)
                        end
                    end
                end
            end
        end
        return RayNewOriginal(origin, direction)
    end
    if newc then pcall(function() handler = newc(handler) end) end

    local ok = pcall(function() Ray.new = handler end)
    if ok then RayNewActive = true end
end

local function RemoveRayNewHook()
    if not RayNewActive then return end
    pcall(function() Ray.new = RayNewOriginal end)
    RayNewActive = false
    RayNewOriginal = nil
end

local V3UnitActive = false
local V3_oldIndex = nil

local function SetupVector3UnitHook()
    if V3UnitActive then return end
    local v3Sample = Vector3.new(1, 0, 0)
    local ok, mt = pcall(getrawmetatable, v3Sample)
    if not ok or not mt then return end
    local savedOriginal = getgenv().__AirHubV3IndexOriginal
    if not savedOriginal then
        savedOriginal = mt.__index
        getgenv().__AirHubV3IndexOriginal = savedOriginal
    end
    V3_oldIndex = savedOriginal

    mt.__index = function(self, k)
        if k == "Unit" and not H.ShuttingDown and IsModeHooked("Vector3Unit") then
            local mag = math.sqrt(self.X*self.X + self.Y*self.Y + self.Z*self.Z)
            if math.abs(mag - 1) < 0.25 then
                if InScanFor("Vector3Unit") then
                    ReportHookCall("Vector3Unit")
                    return V3_oldIndex(self, k)
                end
                if not ShouldRedirect("Vector3Unit") then
                    return V3_oldIndex(self, k)
                end
                local target = Aimbot.LockPartInstance
                if target then
                    local aimPos = PredictPartPosition(target)
                    local camPos = workspace.CurrentCamera.CFrame.Position
                    local dir = aimPos - camPos
                    local dm = dir.Magnitude
                    if dm > 0.001 then
                        return Vector3.new(dir.X/dm, dir.Y/dm, dir.Z/dm)
                    end
                end
            end
        end
        return V3_oldIndex(self, k)
    end
    V3UnitActive = true
end

local function RemoveVector3UnitHook()
    if not V3UnitActive then return end
    local ok, mt = pcall(getrawmetatable, Vector3.new(1, 0, 0))
    if ok and mt and V3_oldIndex then mt.__index = V3_oldIndex end
    V3UnitActive = false
end

local SPR_Active = false
local SPR_Original = nil

local function SetupScreenPointToRayHook()
    if SPR_Active then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    local old = cam.ScreenPointToRay
    if type(old) ~= "function" then return end
    SPR_Original = old

    local newc = getExec("newcclosure")
    local function handler(self, x, y)
        if not H.ShuttingDown and IsModeHooked("ScreenPointToRay") then
            if InScanFor("ScreenPointToRay") then
                ReportHookCall("ScreenPointToRay")
                return SPR_Original(self, x, y)
            end
            if not ShouldRedirect("ScreenPointToRay") then
                return SPR_Original(self, x, y)
            end
            local target = Aimbot.LockPartInstance
            if target then
                local aimPos = PredictPartPosition(target)
                local camPos = self.CFrame.Position
                local dir = aimPos - camPos
                if dir.Magnitude > 0.001 then
                    return Ray.new(camPos, dir.Unit)
                end
            end
        end
        return SPR_Original(self, x, y)
    end
    if newc then pcall(function() handler = newc(handler) end) end

    local ok = pcall(function() cam.ScreenPointToRay = handler end)
    if ok then SPR_Active = true end
end

local function RemoveScreenPointToRayHook()
    if not SPR_Active then return end
    local cam = workspace.CurrentCamera
    if cam and SPR_Original then
        pcall(function() cam.ScreenPointToRay = SPR_Original end)
    end
    SPR_Active = false
    SPR_Original = nil
end

local MouseHooked = false
local originalGetMouse = nil

local function GetMouseSpoof()
    local target = Aimbot.LockPartInstance
    if not target then return nil end
    local origin = GetCheckOrigin()
    local vp = GetVisiblePointOnPart(origin, target)
    if vp then return vp end
    if not Aimbot.Settings.WallCheck then return PredictPartPosition(target) end
    return nil
end

local function SetupMouseHook()
    if MouseHooked then return end
    local prevRestore = getgenv().__AirHubMouseHitRestore
    if prevRestore then
        originalGetMouse = prevRestore
    else
        local current = LocalPlayer.GetMouse
        if current == nil then return end
        originalGetMouse = current
        getgenv().__AirHubMouseHitRestore = current
    end

    LocalPlayer.GetMouse = function()
        local realMouse = originalGetMouse(LocalPlayer)
        return setmetatable({}, {
            __index = function(t, k)
                if not H.ShuttingDown then
                    local isHit  = (k == "Hit")  and IsModeHooked("MouseHit")
                    local isFull = (k == "Hit" or k == "UnitRay" or k == "Target" or k == "TargetSurface")
                                   and IsModeHooked("MouseFull")
                    if isHit or isFull then
                        if InScanFor("MouseHit") and k == "Hit" then
                            ReportHookCall("MouseHit")
                            return realMouse.Hit
                        end
                        if InScanFor("MouseFull") and (k == "Hit" or k == "UnitRay" or k == "Target") then
                            ReportHookCall("MouseFull")
                            return realMouse[k]
                        end
                        local mode = isHit and "MouseHit" or "MouseFull"
                        if not ShouldRedirect(mode) then
                            return realMouse[k]
                        end
                        local target = Aimbot.LockPartInstance
                        if target then
                            local aimPos = GetMouseSpoof() or PredictPartPosition(target)
                            if k == "Hit" then return aimPos end
                            if k == "UnitRay" then
                                local camPos = workspace.CurrentCamera.CFrame.Position
                                local dir = aimPos - camPos
                                if dir.Magnitude > 0.001 then
                                    return Ray.new(camPos, dir.Unit)
                                end
                            end
                            if k == "Target" then return target end
                            if k == "TargetSurface" then return Vector3.new(0, 1, 0) end
                        end
                    end
                end
                return realMouse[k]
            end,
            __newindex = function(t, k, v) realMouse[k] = v end,
        })
    end
    MouseHooked = true
end

local function RemoveMouseHook()
    if not MouseHooked then return end
    local restore = getgenv().__AirHubMouseHitRestore
    if restore then
        pcall(function() LocalPlayer.GetMouse = restore end)
        getgenv().__AirHubMouseHitRestore = nil
    end
    MouseHooked = false
end

local FS_Active = false
local FS_Original = nil

local function SetupFireServerHook()
    if FS_Active then return end
    local hookf     = getExec("hookmetamethod")
    local getMethod = getExec("getnamecallmethod")
    local newc      = getExec("newcclosure")
    local checkC    = getExec("checkcaller")
    if not hookf or not getMethod then return end

    local function handler(self, ...)
        local method = getMethod()
        if method == "FireServer" and not H.ShuttingDown and IsModeHooked("FireServer") then
            if not (checkC and checkC()) then
                if InScanFor("FireServer") then
                    if typeof(self) == "Instance"
                       and (self:IsA("RemoteEvent") or self:IsA("UnreliableRemoteEvent")) then
                        ReportHookCall("FireServer")
                    end
                    return FS_Original(self, ...)
                end
                if not ShouldRedirect("FireServer") then
                    return FS_Original(self, ...)
                end

                local target = Aimbot.LockPartInstance
                if target then
                    local aimPos = GetMouseSpoof() or PredictPartPosition(target)
                    local camPos = workspace.CurrentCamera.CFrame.Position
                    local correctDir = (aimPos - camPos)
                    if correctDir.Magnitude > 0.001 then
                        correctDir = correctDir.Unit
                    end
                    local args = { ... }
                    local patched = false
                    for i, v in ipairs(args) do
                        if typeof(v) == "Vector3" then
                            local vm = v.Magnitude
                            if math.abs(vm - 1) < 0.3 and not patched then
                                args[i] = correctDir
                                patched = true
                            end
                        end
                    end
                    return FS_Original(self, table.unpack(args, 1, #args))
                end
            end
        end
        return FS_Original(self, ...)
    end
    if newc then pcall(function() handler = newc(handler) end) end

    local ok = pcall(function()
        FS_Original = hookf(game, "__namecall", handler)
    end)
    if ok and FS_Original then FS_Active = true end
end

local function RemoveFireServerHook()
    if not FS_Active then return end
    local hookf = getExec("hookmetamethod")
    if hookf and FS_Original then
        pcall(function() hookf(game, "__namecall", FS_Original) end)
    end
    FS_Active = false
    FS_Original = nil
end

local GunHandlerHooked = false
local GunHandlerRef = nil
local GunHandlerOldShoot = nil

local function SetupGunHandlerHook()
    if GunHandlerHooked then return end
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    if not modules then return end
    local guns = modules:FindFirstChild("Guns")
    if not guns then return end
    local gunHandlerModule = guns:FindFirstChild("GunHandler")
    if not gunHandlerModule then return end
    local success, GunHandler = pcall(require, gunHandlerModule)
    if not success or not GunHandler or not GunHandler.Shoot then return end

    GunHandlerRef = GunHandler
    GunHandlerOldShoot = GunHandler.Shoot
    GunHandler.Shoot = function(p1, p2, p3, p4, p5, p6, p7, p8)
        local Hg = getgenv().AirHub
        if Hg and Hg.Aimbot and IsModeHooked("GunHandler") then
            if InScanFor("GunHandler") then
                if p1 == LocalPlayer then
                    ReportHookCall("GunHandler")
                end
                return GunHandlerOldShoot(p1, p2, p3, p4, p5, p6, p7, p8)
            end
            if not ShouldRedirect("GunHandler") then
                return GunHandlerOldShoot(p1, p2, p3, p4, p5, p6, p7, p8)
            end
            if Hg.Aimbot.Locked and Hg.Aimbot.LockPartInstance then
                if p1 == LocalPlayer then
                    RefreshOldPositionIfNeeded()
                    local pt = WaitForShotPoint(Hg.Aimbot.LockPartInstance)
                    if pt then p4 = pt
                    elseif not Hg.Aimbot.Settings.WallCheck then
                        p4 = PredictPartPosition(Hg.Aimbot.LockPartInstance)
                    end
                end
            end
        end
        return GunHandlerOldShoot(p1, p2, p3, p4, p5, p6, p7, p8)
    end
    GunHandlerHooked = true
end

local function RemoveGunHandlerHook()
    if not GunHandlerHooked then return end
    if GunHandlerRef and GunHandlerOldShoot then
        pcall(function() GunHandlerRef.Shoot = GunHandlerOldShoot end)
    end
    GunHandlerHooked = false
    GunHandlerRef = nil
    GunHandlerOldShoot = nil
end

local CFrameHookActive = false
local CFrameHookOriginal = nil

local function SetupCFrameHook()
    if CFrameHookActive then return end
    if type(CFrame) ~= "table" then return end
    local old = CFrame.lookAt
    if type(old) ~= "function" then return end
    CFrameHookOriginal = old

    local newc   = getExec("newcclosure")
    local checkC = getExec("checkcaller")

    local function handler(at, lookAt, up)
        if not H.ShuttingDown and IsModeHooked("CFrameHook") then
            if not (checkC and not checkC()) then
                if InScanFor("CFrameHook") then
                    if typeof(at) == "Vector3" and typeof(lookAt) == "Vector3" then
                        ReportHookCall("CFrameHook")
                    end
                    return CFrameHookOriginal(at, lookAt, up)
                end
                if not ShouldRedirect("CFrameHook") then
                    return CFrameHookOriginal(at, lookAt, up)
                end
                local target = Aimbot.LockPartInstance
                if target and typeof(at) == "Vector3" then
                    local aimPos = PredictPartPosition(target)
                    if typeof(up) == "Vector3" then
                        return CFrameHookOriginal(at, aimPos, up)
                    else
                        return CFrameHookOriginal(at, aimPos)
                    end
                end
            end
        end
        return CFrameHookOriginal(at, lookAt, up)
    end
    if newc then pcall(function() handler = newc(handler) end) end

    local ok = pcall(function() CFrame.lookAt = handler end)
    if ok then CFrameHookActive = true end
end

local function RemoveCFrameHook()
    if not CFrameHookActive then return end
    pcall(function() CFrame.lookAt = CFrameHookOriginal end)
    CFrameHookActive = false
    CFrameHookOriginal = nil
end

local Vector3NewActive = false
local Vector3NewOriginal = nil

local function SetupVector3NewHook()
    if Vector3NewActive then return end
    if type(Vector3) ~= "table" then return end
    local old = Vector3.new
    if type(old) ~= "function" then return end
    Vector3NewOriginal = old

    local newc   = getExec("newcclosure")
    local checkC = getExec("checkcaller")

    local function handler(x, y, z)
        if not H.ShuttingDown and IsModeHooked("Vector3New") then
            if not (checkC and not checkC()) then
                if type(x) == "number" and type(y) == "number" and type(z) == "number" then
                    local mag = math.sqrt(x*x + y*y + z*z)
                    if math.abs(mag - 1) < 0.25 then
                        if InScanFor("Vector3New") then
                            ReportHookCall("Vector3New")
                            return Vector3NewOriginal(x, y, z)
                        end
                        if not ShouldRedirect("Vector3New") then
                            return Vector3NewOriginal(x, y, z)
                        end
                        local target = Aimbot.LockPartInstance
                        if target then
                            local aimPos = PredictPartPosition(target)
                            local camPos = workspace.CurrentCamera.CFrame.Position
                            local dir = aimPos - camPos
                            local dm = dir.Magnitude
                            if dm > 0.001 then
                                return Vector3NewOriginal(dir.X/dm, dir.Y/dm, dir.Z/dm)
                            end
                        end
                    end
                end
            end
        end
        return Vector3NewOriginal(x, y, z)
    end
    if newc then pcall(function() handler = newc(handler) end) end

    local ok = pcall(function() Vector3.new = handler end)
    if ok then Vector3NewActive = true end
end

local function RemoveVector3NewHook()
    if not Vector3NewActive then return end
    pcall(function() Vector3.new = Vector3NewOriginal end)
    Vector3NewActive = false
    Vector3NewOriginal = nil
end

task.spawn(function()
    for _ = 1, 20 do
        if H.ShuttingDown then return end
        SetupGunHandlerHook()
        if GunHandlerHooked then return end
        task.wait(0.5)
    end
end)

local function ManageHooks()
    local autoScanMode = Aimbot.AutoDetect.Active and Aimbot.AutoDetect.TestMode or nil
    local desired = {}

    local function want(name)
        return IsModeHooked(name) or (autoScanMode == name)
    end

    desired.RayHook          = want("RayHook")
    desired.RayNew           = want("RayNew")
    desired.Vector3Unit      = want("Vector3Unit")
    desired.ScreenPointToRay = want("ScreenPointToRay")
    desired.Mouse            = want("MouseHit") or want("MouseFull")
    desired.FireServer       = want("FireServer")
    desired.CFrameHook       = want("CFrameHook")
    desired.Vector3New       = want("Vector3New")

    local key = table.concat({
        tostring(desired.RayHook),
        tostring(desired.RayNew),
        tostring(desired.Vector3Unit),
        tostring(desired.ScreenPointToRay),
        tostring(desired.Mouse),
        tostring(desired.FireServer),
        tostring(desired.CFrameHook),
        tostring(desired.Vector3New),
    }, "|")

    if Aimbot.Internal.LastManageKey == key then
        return
    end
    Aimbot.Internal.LastManageKey = key

    if desired.RayHook          then SetupRayHook()            else RemoveRayHook()            end
    if desired.RayNew           then SetupRayNewHook()         else RemoveRayNewHook()         end
    if desired.Vector3Unit      then SetupVector3UnitHook()    else RemoveVector3UnitHook()    end
    if desired.ScreenPointToRay then SetupScreenPointToRayHook() else RemoveScreenPointToRayHook() end
    if desired.Mouse            then SetupMouseHook()          else RemoveMouseHook()          end
    if desired.FireServer       then SetupFireServerHook()     else RemoveFireServerHook()     end
    if desired.CFrameHook       then SetupCFrameHook()         else RemoveCFrameHook()         end
    if desired.Vector3New       then SetupVector3NewHook()     else RemoveVector3NewHook()     end
end

local function RunAutoScan()
    if Aimbot.AutoDetect.Active then return end
    Aimbot.AutoDetect.Active   = true
    Aimbot.AutoDetect.SelectedMethod = nil
    Aimbot.AutoDetect.Results  = {}
    Aimbot.AutoDetect.LastScanTime = tick()

    warn("========================================")
    warn("[AutoScan] Starting silent aim method detection...")
    warn("========================================")

    task.spawn(function()
        local order = Aimbot.Settings.AutoPriorityOrder
        local selected = nil

        for _, mode in ipairs(order) do
            if not Aimbot.AutoDetect.Active then break end
            if H.ShuttingDown then break end

            if Aimbot.Settings.AutoEnabledMethods[mode] == false then
                Aimbot.AutoDetect.Results[mode] = { available = false, reason = "disabled", calls = 0 }
                warn("[AutoScan] " .. mode .. " -> SKIPPED (disabled by user)")
            else
                local available, reason = IsModeAvailable(mode)
                if not available then
                    Aimbot.AutoDetect.Results[mode] = { available = false, reason = reason, calls = 0 }
                    warn("[AutoScan] " .. mode .. " -> UNAVAILABLE: " .. tostring(reason))
                else
                    warn("[AutoScan] Testing " .. mode .. " (" .. tostring(Aimbot.Settings.AutoTestDuration) .. "s)...")
                    Aimbot.AutoDetect.TestMode      = mode
                    Aimbot.AutoDetect.HookCallCount = 0
                    Aimbot.Internal.LastManageKey = nil

                    task.wait(0.15)

                    local deadline = tick() + (Aimbot.Settings.AutoTestDuration or 4)
                    while tick() < deadline
                          and Aimbot.AutoDetect.Active
                          and Aimbot.AutoDetect.TestMode == mode
                          and not H.ShuttingDown do
                        task.wait(0.05)
                    end

                    local calls = Aimbot.AutoDetect.HookCallCount
                    Aimbot.AutoDetect.Results[mode] = { available = true, calls = calls }

                    if calls >= (Aimbot.Settings.AutoMinHookCalls or 3) then
                        selected = mode
                        warn("[AutoScan] " .. mode .. " -> OK (" .. calls .. " game hook calls) -> SELECTED")
                        Aimbot.AutoDetect.TestMode = nil
                        Aimbot.Internal.LastManageKey = nil
                        task.wait(0.1)
                        break
                    else
                        warn("[AutoScan] " .. mode .. " -> FAIL (" .. calls .. " game hook calls, need " .. tostring(Aimbot.Settings.AutoMinHookCalls or 3) .. ")")
                        Aimbot.AutoDetect.TestMode = nil
                        Aimbot.Internal.LastManageKey = nil
                        task.wait(0.1)
                    end
                end
            end
        end

        Aimbot.AutoDetect.SelectedMethod = selected or Aimbot.Settings.AutoFallback or "Camera"
        Aimbot.AutoDetect.Active = false
        Aimbot.AutoDetect.TestMode = nil
        Aimbot.Internal.LastManageKey = nil

        warn("========================================")
        if selected then
            warn("[AutoScan] RESULT: Silent Aim mode set to " .. tostring(selected))
        else
            warn("[AutoScan] RESULT: No hook detected. Falling back to " .. tostring(Aimbot.AutoDetect.SelectedMethod))
        end
        warn("========================================")
    end)
end

local function CancelAutoScan()
    if Aimbot.AutoDetect.Active then
        warn("[AutoScan] Cancelled by user.")
    end
    Aimbot.AutoDetect.Active = false
    Aimbot.AutoDetect.TestMode = nil
    Aimbot.Internal.LastManageKey = nil
end

local function LoadAimbot()
    Track(RunService.RenderStepped:Connect(function()
        if H.ShuttingDown then return end
        local now = tick()
        local dt = math.min(0.033, now - lastDelta)
        lastDelta = now

        if type(Aimbot.Internal.FovAccum) ~= "number" then Aimbot.Internal.FovAccum = 0 end
        if type(Aimbot.Internal.TargetAccum) ~= "number" then Aimbot.Internal.TargetAccum = 0 end

        Aimbot.Internal.FovAccum = Aimbot.Internal.FovAccum + dt
        if Aimbot.Internal.FovAccum >= (1 / 60) then
            Aimbot.Internal.FovAccum = 0
            if Aimbot.Settings.Enabled and Aimbot.FOVSettings.Enabled and not Aimbot.Settings.IgnoreFOV then
                Aimbot.FOVCircle.Radius = Aimbot.FOVSettings.Amount
                Aimbot.FOVCircle.Thickness = 1
                Aimbot.FOVCircle.Filled = false
                Aimbot.FOVCircle.Transparency = 0.5
                Aimbot.FOVCircle.Visible = Aimbot.FOVSettings.Visible
                Aimbot.FOVCircle.Position = UserInputService:GetMouseLocation()
            else
                Aimbot.FOVCircle.Visible = false
            end
        end

        local hz = math.max(30, math.min(1000, Aimbot.Settings.AimbotHz or 120))
        local interval = 1 / hz
        Aimbot.Internal.TargetAccum = Aimbot.Internal.TargetAccum + dt
        if Aimbot.Internal.TargetAccum >= interval then
            Aimbot.Internal.TargetAccum = 0

            if Aimbot.Settings.Enabled and Running then
                GetClosestPlayer()
                Aimbot.FOVCircle.Color = Color3.fromRGB(255, 255, 255)
                if Aimbot.Locked and Aimbot.LockPartInstance then
                    local targetPart = Aimbot.LockPartInstance
                    local origin = GetCheckOrigin()
                    local visiblePoint = GetVisiblePointOnPart(origin, targetPart)
                    if visiblePoint then
                        Aimbot.FOVCircle.Color = Color3.fromRGB(255, 200, 70)
                        if not Aimbot.Settings.SilentAim then
                            local targetPos = visiblePoint
                            if Aimbot.Settings.AimMethod == "Instant" then
                                workspace.CurrentCamera.CFrame = CFrame.new(workspace.CurrentCamera.CFrame.Position, targetPos)
                            else
                                local targetCF = CFrame.new(workspace.CurrentCamera.CFrame.Position, targetPos)
                                local smoothFactor = 1 - math.exp(-Aimbot.Settings.AimSmoothingSpeed * interval)
                                workspace.CurrentCamera.CFrame = workspace.CurrentCamera.CFrame:Lerp(targetCF, smoothFactor)
                            end
                        end
                    end
                end
            end
        end

        ManageHooks()
    end))

    Track(UserInputService.InputBegan:Connect(function(inp, gpe)
        if Typing then return end
        if not Aimbot.Settings.IgnoreGameProcessed and gpe then return end

        local triggerKey = Aimbot.Settings.TriggerKey
        local keyPressed = false
        if inp.UserInputType == Enum.UserInputType.Keyboard then
            local kc = Util.SafeKeyCode(triggerKey)
            if kc and inp.KeyCode == kc then keyPressed = true end
        else
            local uit = Util.SafeUserInputType(triggerKey)
            if uit and inp.UserInputType == uit then keyPressed = true end
        end
        if keyPressed then
            if Aimbot.Settings.Toggle then
                Running = not Running
                if not Running then CancelLock() end
            else
                Running = true
            end
            Aimbot.Internal.TargetAccum = 999
        end
    end))

    Track(UserInputService.InputEnded:Connect(function(inp)
        if Typing or Aimbot.Settings.Toggle then return end
        local triggerKey = Aimbot.Settings.TriggerKey
        local keyReleased = false
        if inp.UserInputType == Enum.UserInputType.Keyboard then
            local kc = Util.SafeKeyCode(triggerKey)
            if kc and inp.KeyCode == kc then keyReleased = true end
        else
            local uit = Util.SafeUserInputType(triggerKey)
            if uit and inp.UserInputType == uit then keyReleased = true end
        end
        if keyReleased then
            Running = false
            CancelLock()
        end
    end))

    Track(UserInputService.InputBegan:Connect(function(inp, gpe)
        if gpe or Typing then return end
        if not Aimbot.Settings.Enabled then return end
        if not Running or not Aimbot.Locked then return end

        local btn = nil
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then btn = 0
        elseif inp.UserInputType == Enum.UserInputType.MouseButton2 then btn = 1 end
        if btn == nil then return end
        if btn == 1 and Aimbot.Settings.TriggerKey == "MouseButton2" then return end
        if Aimbot.Settings.AutoShoot.Enabled then return end

        local targetPart = Aimbot.LockPartInstance
        if targetPart then
            if Aimbot.Settings.SilentAim then
                PerformSilentShot(targetPart, btn, nil)
            else
                if Aimbot.Settings.WallCheck
                   and not ShouldBypassWallCheck() then
                    local vp = WaitForShotPoint(targetPart)
                    if not vp then return end
                end
                RefreshOldPositionIfNeeded()
                local mousePos = UserInputService:GetMouseLocation()
                VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, true,  game, 1)
                task.wait(0.001)
                VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, false, game, 1)
            end
        end
    end))

    task.spawn(function()
        while not H.ShuttingDown and task.wait(0.01) do
            xpcall(function()
                if not Aimbot.Settings.AutoShoot.Enabled then return end
                if Aimbot.Settings.AutoShoot.OnlyWhenAiming and not Running then return end
                if not Aimbot.Locked or not Aimbot.LockPartInstance then return end

                local nowt = tick()
                if nowt - LastShotTime < Aimbot.Settings.AutoShoot.FireRate then return end

                local targetPart = Aimbot.LockPartInstance
                if not targetPart then return end
                local targetChar = targetPart.Parent
                if not targetChar then return end
                local hum = targetChar:FindFirstChildOfClass("Humanoid")
                if hum and Aimbot.Settings.AliveCheck and hum.Health <= 0 then CancelLock() return end

                local visiblePoint, nowVisible = WaitForShotPoint(targetPart)
                if Aimbot.Settings.WallCheck and not visiblePoint
                   and not ShouldBypassWallCheck() then
                    CancelLock()
                    return
                end

                if Aimbot.Settings.AutoShoot.AutoStop.Enabled then
                    local char = LocalPlayer.Character
                    if char then
                        local humObj = char:FindFirstChildOfClass("Humanoid")
                        if humObj then
                            local savedSpeed = humObj.WalkSpeed
                            humObj.WalkSpeed = 0
                            task.wait(Aimbot.Settings.AutoShoot.AutoStop.Time)
                            humObj.WalkSpeed = savedSpeed
                        end
                    end
                end

                local shootBtn = Aimbot.Settings.AutoShoot.ShootKey == "MouseButton1" and 0 or 1
                if Aimbot.Settings.SilentAim then
                    PerformSilentShot(targetPart, shootBtn, nowVisible)
                else
                    RefreshOldPositionIfNeeded()
                    local mousePos = UserInputService:GetMouseLocation()
                    VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, shootBtn, true,  game, 1)
                    task.wait(0.001)
                    VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, shootBtn, false, game, 1)
                end
                LastShotTime = nowt
            end, HandleError)
        end
    end)
end

Track(UserInputService.TextBoxFocused:Connect(function() Typing = true end))
Track(UserInputService.TextBoxFocusReleased:Connect(function() Typing = false end))

Track(UserInputService.InputBegan:Connect(function(inp, gpe)
    if Typing then return end
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

LoadAimbot()

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
Aimbot.ShouldBypassWallCheck = ShouldBypassWallCheck
Aimbot.IsBacktrackEnabled    = IsBacktrackEnabled
Aimbot.IsModeHooked          = IsModeHooked
Aimbot.ShouldRedirect        = ShouldRedirect

Aimbot.PerformWallbang       = PerformWallbang
Aimbot.PerformMagicBullet    = PerformMagicBullet
Aimbot.PerformInfiniteTP     = PerformInfiniteTP

--// ---------------------------------------------------------------------------
--// DIAGNOSTICS
--// ---------------------------------------------------------------------------

local function Check(cond, label, detail)
    local mark = cond and "[OK]  " or "[FAIL]"
    local line = mark .. " " .. label
    if detail then line = line .. " — " .. tostring(detail) end
    warn(line)
    return cond and 1 or 0
end

local function Diagnose()
    local passed, failed = 0, 0
    local function T(cond, label, detail)
        if Check(cond, label, detail) == 1 then
            passed = passed + 1
        else
            failed = failed + 1
        end
    end

    warn("==========================================================")
    warn("          AirHub Aimbot - DIAGNOSTICS")
    warn("==========================================================")

    T(H ~= nil, "H (AirHub) exists")
    T(Util ~= nil, "Util module present")
    T(Players ~= nil, "Players service")
    T(RunService ~= nil, "RunService")
    T(UserInputService ~= nil, "UserInputService")
    T(VirtualInputManager ~= nil, "VirtualInputManager")
    T(ReplicatedStorage ~= nil, "ReplicatedStorage")
    T(LocalPlayer ~= nil, "LocalPlayer")
    T(workspace.CurrentCamera ~= nil, "CurrentCamera")

    local drawingOK = pcall(function() local d = Drawing.new("Circle"); d:Remove() end)
    T(drawingOK, "Drawing.new available")

    local execs = { "hookmetamethod", "hookfunction", "newcclosure", "checkcaller",
                    "getrawmetatable", "getnamecallmethod", "mousemoverel", "mousemoveabs" }
    for _, name in ipairs(execs) do
        T(getExec(name) ~= nil, "executor: " .. name)
    end

    if Aimbot.IsModeAvailable then
        local modes = { "RayHook", "RayNew", "Vector3Unit", "ScreenPointToRay",
                        "MouseHit", "MouseFull", "GunHandler", "FireServer",
                        "MouseLock", "Mouse", "Camera", "CFrameHook", "Vector3New" }
        for _, m in ipairs(modes) do
            local ok, reason = Aimbot.IsModeAvailable(m)
            T(ok, "hook: " .. m, reason)
        end
    end

    local exports = { "CancelLock", "GetVisiblePointOnPart", "PredictPartPosition",
                      "RunAutoScan", "IsModeAvailable", "ShouldBypassWallCheck",
                      "IsBacktrackEnabled", "IsModeHooked", "ShouldRedirect",
                      "PerformWallbang", "PerformMagicBullet", "PerformInfiniteTP" }
    for _, name in ipairs(exports) do
        T(type(Aimbot[name]) == "function", "export: Aimbot." .. name)
    end

    warn("==========================================================")
    warn(string.format("  RESULT: %d passed, %d failed", passed, failed))
    warn("==========================================================")

    return passed, failed
end

Aimbot.Diagnose = Diagnose

task.delay(1, function()
    if H.ShuttingDown then return end
    pcall(Diagnose)
end)

if Aimbot.Settings.AutoRunOnLoad and Aimbot.Settings.SilentAimMode == "Auto" then
    task.delay(3, function()
        if H.Aimbot and H.Aimbot.RunAutoScan then
            H.Aimbot.RunAutoScan()
        end
    end)
end
