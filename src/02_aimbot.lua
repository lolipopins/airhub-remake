local H = getgenv().AirHub
if not H or not H._CoreLoaded then
    warn("[AirHub] 02_aimbot: core not loaded")
    return
end
if H.Aimbot then
    warn("[AirHub] Aimbot already loaded")
    return
end

local Util              = H.Util
local Players           = Util.Players
local RunService        = Util.RunService
local UserInputService  = Util.UserInputService
local VirtualInputManager = Util.VirtualInputManager
local ReplicatedStorage = Util.ReplicatedStorage
local LocalPlayer       = Util.LocalPlayer
local Track             = Util.Track
local HandleError       = Util.HandleError
local AddLog            = Util.AddLog
local RAY_FILTER        = Util.RAY_FILTER

--// Local executor helper (mirrors loader's getExec)
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

--// ---------------------------------------------------------------------------
--// Aimbot state
--// ---------------------------------------------------------------------------
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
        --// Modes:
        --//   Camera          — temporary camera rotate
        --//   Mouse           — physical cursor move + click + restore
        --//   MouseLock       — unlock cursor, move, click, relock
        --//   MouseHit        — spoof Mouse.Hit only
        --//   MouseFull       — spoof Mouse.Hit / UnitRay / Target / TargetSurface
        --//   RayHook         — Ray.__index hook
        --//   RayNew          — Ray.new constructor hook
        --//   ScreenPointToRay— Camera:ScreenPointToRay hook
        --//   Vector3Unit     — Vector3.Unit getter spoof
        --//   FireServer      — RemoteEvent FireServer arg rewrite
        --//   GunHandler      — module Shoot function hook
        SilentAimMode = "Camera",
        IgnoreFOV = false,
        CheckFromPlayerOnTP = true,
        PredictionEnabled = false,
        PredictionX = 0,
        PredictionY = 0,
        PredictionTime = 0.15,

        --// NPC targeting
        TargetNPCs    = false,
        NPCNameFilter = "",

        AutoShoot = {
            Enabled = false,
            ShootKey = "MouseButton1",
            FireRate = 0.05,
            OnlyWhenAiming = true,
            AutoStop = { Enabled = false, Time = 0.1 },
        },
    },
    FOVSettings = { Enabled = true, Visible = true, Amount = 90 },
    FOVCircle   = Drawing.new("Circle"),
    Locked      = nil,
    LockPartInstance = nil,
    Internal    = {},
}
local Aimbot = H.Aimbot

local Running       = false
local Typing        = false
local LastShotTime  = 0
local lastDelta     = tick()

--// ---------------------------------------------------------------------------
--// Helpers
--// ---------------------------------------------------------------------------
local VISIBLE_PARTS = {
    "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso",
    "Torso", "Left Arm", "Right Arm",
}

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

--// ---------------------------------------------------------------------------
--// NPC discovery
--// ---------------------------------------------------------------------------
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

--// ---------------------------------------------------------------------------
--// Multipoint sampling
--// ---------------------------------------------------------------------------
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
        if part then Aimbot.LockPartInstance = part else CancelLock() end
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
    if not H.Logging.Enabled then return end
    if hit and not H.Logging.ShowHit then return end
    if not hit and not H.Logging.ShowMiss then return end

    local displayName = targetName or targetChar.Name
    local msg, color
    if hit then
        if hum.Health <= 0 then
            msg = "💀 Killed " .. displayName .. " (" .. hitPartName .. ")"
            color = Color3.fromRGB(255, 255, 0)
        else
            msg = "✅ Hit " .. displayName .. " (" .. hitPartName .. " - " .. math.floor(startHealth - endHealth) .. " dmg)"
            color = Color3.fromRGB(0, 255, 0)
        end
    else
        msg = wasVisible and ("❌ Missed " .. displayName) or ("❌ Missed (wall) " .. displayName)
        color = Color3.fromRGB(255, 80, 80)
    end
    AddLog(msg, color)
end

--// ---------------------------------------------------------------------------
--// OldPosition refresh
--// ---------------------------------------------------------------------------
local function RefreshOldPositionIfNeeded()
    local Hg = getgenv().AirHub
    if not Hg or not Hg.AntiAim then return end
    local d = Hg.AntiAim.Desync
    if not d or not d.Settings then return end
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

--// ---------------------------------------------------------------------------
--// Delay Shot
--// ---------------------------------------------------------------------------
local function WaitForShotPoint(targetPart)
    if not targetPart then return nil, false end
    if not Aimbot.Settings.WallCheck then
        return PredictPartPosition(targetPart), true
    end
    local origin = GetCheckOrigin()
    local pt = GetVisiblePointOnPart(origin, targetPart)
    if pt then return pt, true end
    if not Aimbot.Settings.DelayShot then return nil, false end
    local deadline = tick() + H.DELAY_SHOT_TIMEOUT
    while tick() < deadline and not H.ShuttingDown do
        task.wait(0.005)
        pt = GetVisiblePointOnPart(GetCheckOrigin(), targetPart)
        if pt then return pt, true end
    end
    return nil, false
end

--// ---------------------------------------------------------------------------
--// Mouse helpers
--// ---------------------------------------------------------------------------
local function WorldToMouseVIM(worldPos)
    local screenPos, onScreen = workspace.CurrentCamera:WorldToViewportPoint(worldPos)
    if not onScreen then return nil end
    return math.floor(screenPos.X), math.floor(screenPos.Y + 36)
end

local function MoveMouseAbs(x, y)
    if type(mousemoveabs) == "function" then
        if pcall(mousemoveabs, x, y) then return true end
    end
    if type(mousemoverel) == "function" then
        local cur = UserInputService:GetMouseLocation()
        local dx = x - math.floor(cur.X)
        local dy = y - math.floor(cur.Y)
        if pcall(mousemoverel, dx, dy) then return true end
    end
    local vimOk = pcall(function()
        VirtualInputManager:SendMouseMoveEvent(x, y, game)
    end)
    return vimOk
end

--// ---------------------------------------------------------------------------
--// Silent shot dispatcher
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

    RefreshOldPositionIfNeeded()

    local checkPoint, nowVisible = WaitForShotPoint(targetPart)
    if Aimbot.Settings.WallCheck and not checkPoint then return end
    if nowVisible ~= nil then wasVisible = nowVisible end

    local mode = Aimbot.Settings.SilentAimMode

    --// ===== MouseLock — unlock cursor, move, click, relock =====
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

        -- Unlock mouse so cursor can move freely
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

        -- Restore original mouse behavior
        pcall(function()
            UserInputService.MouseBehavior    = oldBehavior
            UserInputService.MouseIconEnabled = oldIcon
        end)

        task.delay(0.15, function()
            LogShot(targetChar, displayName, startHealth, targetPart.Name, wasVisible)
        end)
        return
    end

    --// ===== Mouse — physical cursor move + click + restore =====
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

    --// ===== Hook-based modes (spoofed value used by game) =====
    if mode == "GunHandler" or mode == "RayHook" or mode == "RayNew"
       or mode == "MouseHit" or mode == "MouseFull"
       or mode == "Vector3Unit" or mode == "ScreenPointToRay"
       or mode == "FireServer" then
        local mousePos = UserInputService:GetMouseLocation()
        VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, true,  game, 1)
        task.wait(0.001)
        VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, false, game, 1)
        task.delay(0.15, function()
            LogShot(targetChar, displayName, startHealth, targetPart.Name, wasVisible)
        end)
        return
    end

    --// ===== Default: Camera mode =====
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
    if not ok then HandleError("Silent shot input failed") end

    task.delay(0.15, function()
        LogShot(targetChar, displayName, startHealth, targetPart.Name, wasVisible)
    end)
end

--// ---------------------------------------------------------------------------
--// Helper: active-mode check for hooks
--// ---------------------------------------------------------------------------
local function IsModeActive(mode)
    return Aimbot.Settings.Enabled
       and Aimbot.Settings.SilentAim
       and Aimbot.Settings.SilentAimMode == mode
       and Running
end

--// ---------------------------------------------------------------------------
--// RayHook — Ray.__index
--// ---------------------------------------------------------------------------
local RayHookActive = false
local oldRayIndex = nil

local function GetClosestTargetRay()
    local target, dist = nil, math.huge
    local mousePos = GetMousePos()
    local candidates = {}
    for _, player in next, Players:GetPlayers() do
        if player ~= LocalPlayer and player.Character then
            local sameTeam
            if LocalPlayer.Team and player.Team then
                sameTeam = (LocalPlayer.Team == player.Team)
            else
                sameTeam = (LocalPlayer:GetAttribute('Team') == player:GetAttribute('Team'))
            end
            if not sameTeam then table.insert(candidates, player.Character) end
        end
    end
    if Aimbot.Settings.TargetNPCs then
        for _, npc in ipairs(GetNPCCharacters()) do table.insert(candidates, npc) end
    end
    for _, char in ipairs(candidates) do
        local head = char:FindFirstChild('Head')
        local hum  = char:FindFirstChildOfClass('Humanoid')
        if head and hum and hum.Health > 0 then
            local sp, on = workspace.CurrentCamera:WorldToViewportPoint(head.Position)
            if on then
                local hp = Vector2.new(sp.X, sp.Y)
                local mag = (mousePos - hp).magnitude
                if mag < dist then dist = mag; target = head end
            end
        end
    end
    return target
end

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
        if k == 'Direction' and not H.ShuttingDown and IsModeActive("RayHook") then
            local target = GetClosestTargetRay()
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

--// ---------------------------------------------------------------------------
--// RayNew — Ray.new constructor hook
--// ---------------------------------------------------------------------------
local RayNewActive = false
local RayNewOriginal = nil

local function SetupRayNewHook()
    if RayNewActive then return end
    if type(Ray) ~= "table" then return end
    local old = Ray.new
    if type(old) ~= "function" then return end
    RayNewOriginal = old

    local newc = getExec("newcclosure")
    local checkC = getExec("checkcaller")

    local function handler(origin, direction)
        if not H.ShuttingDown and IsModeActive("RayNew") then
            if not (checkC and not checkC()) then
                local target = Aimbot.LockPartInstance or GetClosestTargetRay()
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

--// ---------------------------------------------------------------------------
--// Vector3Unit — Vector3.Unit getter spoof (only when vector is ~unit length)
--// ---------------------------------------------------------------------------
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
        if k == "Unit" and not H.ShuttingDown and IsModeActive("Vector3Unit") then
            local mag = math.sqrt(self.X*self.X + self.Y*self.Y + self.Z*self.Z)
            -- only spoof unit-ish direction vectors (avoid breaking unrelated math)
            if math.abs(mag - 1) < 0.25 then
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

--// ---------------------------------------------------------------------------
--// ScreenPointToRay — Camera:ScreenPointToRay(x, y) hook
--// ---------------------------------------------------------------------------
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
        if not H.ShuttingDown and IsModeActive("ScreenPointToRay") then
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

--// ---------------------------------------------------------------------------
--// MouseHit / MouseFull — LocalPlayer:GetMouse() spoof
--// ---------------------------------------------------------------------------
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
        originalGetMouse = LocalPlayer.GetMouse
        getgenv().__AirHubMouseHitRestore = originalGetMouse
    end

    LocalPlayer.GetMouse = function()
        local realMouse = originalGetMouse(LocalPlayer)
        return setmetatable({}, {
            __index = function(t, k)
                if not H.ShuttingDown then
                    local isHit  = (k == "Hit")  and IsModeActive("MouseHit")
                    local isFull = (k == "Hit" or k == "UnitRay" or k == "Target" or k == "TargetSurface")
                                   and IsModeActive("MouseFull")
                    if isHit or isFull then
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

--// ---------------------------------------------------------------------------
--// FireServer — remote arg rewrite via __namecall
--// ---------------------------------------------------------------------------
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
        if method == "FireServer" and not H.ShuttingDown and IsModeActive("FireServer") then
            if not (checkC and checkC()) then
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
                            -- unit-length direction vectors → replace with correct direction
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

--// ---------------------------------------------------------------------------
--// GunHandler hook
--// ---------------------------------------------------------------------------
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
        if Hg and Hg.Aimbot and IsModeActive("GunHandler")
           and Hg.Aimbot.Locked and Hg.Aimbot.LockPartInstance then
            if p1 == LocalPlayer then
                RefreshOldPositionIfNeeded()
                local pt = WaitForShotPoint(Hg.Aimbot.LockPartInstance)
                if pt then p4 = pt
                elseif not Hg.Aimbot.Settings.WallCheck then
                    p4 = PredictPartPosition(Hg.Aimbot.LockPartInstance)
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

task.spawn(function()
    for _ = 1, 20 do
        if H.ShuttingDown then return end
        SetupGunHandlerHook()
        if GunHandlerHooked then return end
        task.wait(0.5)
    end
end)

--// ---------------------------------------------------------------------------
--// Aimbot driver
--// ---------------------------------------------------------------------------
local function ManageHooks()
    if IsModeActive("RayHook")            then SetupRayHook()            else RemoveRayHook()            end
    if IsModeActive("RayNew")             then SetupRayNewHook()         else RemoveRayNewHook()         end
    if IsModeActive("Vector3Unit")        then SetupVector3UnitHook()    else RemoveVector3UnitHook()    end
    if IsModeActive("ScreenPointToRay")   then SetupScreenPointToRayHook() else RemoveScreenPointToRayHook() end
    if IsModeActive("MouseHit") or IsModeActive("MouseFull")
                                          then SetupMouseHook()          else RemoveMouseHook()          end
    if IsModeActive("FireServer")         then SetupFireServerHook()     else RemoveFireServerHook()     end
end

local function LoadAimbot()
    Track(RunService.RenderStepped:Connect(function()
        if H.ShuttingDown then return end
        local now = tick()
        local dt = math.min(0.033, now - lastDelta)
        lastDelta = now

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
                            local smoothFactor = 1 - math.exp(-Aimbot.Settings.AimSmoothingSpeed * dt)
                            workspace.CurrentCamera.CFrame = workspace.CurrentCamera.CFrame:Lerp(targetCF, smoothFactor)
                        end
                    end
                end
            end
        end

        ManageHooks()
    end))

    Track(UserInputService.InputBegan:Connect(function(inp, gpe)
        if gpe or Typing then return end
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
                if Aimbot.Settings.WallCheck then
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
                if Aimbot.Settings.WallCheck and not visiblePoint then CancelLock() return end

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

LoadAimbot()

--// Expose API
Aimbot.CancelLock            = CancelLock
Aimbot.RemoveRayHook         = RemoveRayHook
Aimbot.RemoveRayNewHook      = RemoveRayNewHook
Aimbot.RemoveVector3UnitHook = RemoveVector3UnitHook
Aimbot.RemoveSPRHook         = RemoveScreenPointToRayHook
Aimbot.RemoveMouseHook       = RemoveMouseHook
Aimbot.RemoveFireServerHook  = RemoveFireServerHook
Aimbot.RemoveMouseHitHook    = RemoveMouseHook     -- backwards compat alias
Aimbot.RemoveGunHandlerHook  = RemoveGunHandlerHook
Aimbot.GetVisiblePointOnPart = GetVisiblePointOnPart
Aimbot.GetMousePos           = GetMousePos
Aimbot.PredictPartPosition   = PredictPartPosition
Aimbot.MoveMouseAbs          = MoveMouseAbs
Aimbot.WorldToMouseVIM       = WorldToMouseVIM
Aimbot.GetNPCCharacters      = GetNPCCharacters
Aimbot.GetLockedCharacter    = GetLockedCharacter
