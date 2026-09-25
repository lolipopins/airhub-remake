--// AirHub - 02_aimbot.lua
--// v14 (2026-09-26):
--//   * Debug post-shot logging (Settings.Debug = true by default)
--//   * Safe namecall wrapper — any error inside our handler is caught,
--//     logged, and we fall through to the original without patching.
--//   * Strict Instance check — non-Instance self is passed straight through.
--//   * Default SilentAimMode = "Raycast".

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
        SilentAimMode = "Raycast",
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
        Debug = true,   -- post-shot logging

        AutoShoot = {
            Enabled = false,
            ShootKey = "MouseButton1",
            FireRate = 0.05,
            OnlyWhenAiming = true,
            AutoStop = { Enabled = false, Time = 0.1 },
        },

        WallbangEnabled  = false,
        WallbangMethod   = "RemotePatch",
        WallbangDistance = 500,
        WallbangHoldTime = 0.1,

        TPAimEnabled     = false,
        TPAimMethod      = "MagicBullet",
        TPAimKey         = "E",
        TPAimDistance    = 5,
        TPAimReturnOnKill = true,

        UseBacktrack     = false,
        BacktrackAimAtGhost = false,

        HookWatchdogInterval = 2.0,
        ModeCacheTTL         = 60.0,
    },
    FOVSettings = { Enabled = true, Visible = true, Amount = 90 },
    FOVCircle   = Drawing.new("Circle"),
    Locked      = nil,
    LockPartInstance = nil,
    Internal    = {
        TargetAccum  = 0,
        FovAccum     = 0,
        LastManageKey = nil,
        LockedGhost  = nil,
        WatchdogAccum = 0,
        ModeCache    = {},
        RaycastRedirectActive = false,
        LastShotInfo = nil,
        HookHandlers = {
            RayNew      = nil, RayNewOrig  = nil,
            V3New       = nil, V3NewOrig   = nil,
            RayHook     = nil, RayHookOrig = nil,
            V3Unit      = nil, V3UnitOrig  = nil,
            SPR         = nil, SPR_Orig    = nil,
        },
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

local function DebugPrint(...)
    if Aimbot.Settings.Debug then
        warn("[AirHub][Shot]", ...)
    end
end

local function DebugHookPrint(...)
    if Aimbot.Settings.Debug then
        warn("[AirHub][Hook]", ...)
    end
end

local WB = {
    HoldUntil = 0,
}

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

local function IsAlive(inst)
    if not inst then return false end
    local ok, parent = pcall(function() return inst.Parent end)
    return ok and parent ~= nil
end

local function ResolveOwnerCharacter(character)
    if not character then return nil end
    if character:GetAttribute("AirHub_Ghost") then
        local pv = character:FindFirstChild("Player")
        if pv and pv.Value and pv.Value.Character then
            return pv.Value.Character
        end
        return nil
    end
    return character
end

local function ResolveOwnerPlayer(character)
    if not character then return nil end
    if character:GetAttribute("AirHub_Ghost") then
        local pv = character:FindFirstChild("Player")
        if pv and pv.Value then return pv.Value end
        return nil
    end
    return Players:GetPlayerFromCharacter(character)
end

local function GetBacktrackGhostTargets()
    if not Aimbot.Settings.UseBacktrack then return {} end
    if not Aimbot.Settings.BacktrackAimAtGhost then return {} end
    if not IsBacktrackEnabled() then return {} end
    if not H.Exploits.Internal or not H.Exploits.Internal.BacktrackGhosts then return {} end

    local out = {}
    for owner, ghost in pairs(H.Exploits.Internal.BacktrackGhosts) do
        if ghost and ghost.Parent and ghost:GetAttribute("AirHub_Ghost") then
            local hum = ghost:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local ownerRealChar = owner.Character
                local ownerHum = ownerRealChar and ownerRealChar:FindFirstChildOfClass("Humanoid")
                if ownerHum and ownerHum.Health > 0 then
                    table.insert(out, {
                        character = ghost,
                        player = owner,
                        isGhost = true,
                    })
                end
            end
        end
    end
    return out
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
    if not IsAlive(part) then return Vector3.new(0, 0, 0) end

    if part.Parent:GetAttribute("AirHub_Ghost") then
        return part.Position
    end

    if Aimbot.Settings.UseBacktrack
       and Aimbot.Settings.BacktrackAimAtGhost
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
            if btCF then return btCF.Position end
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
    if typeof(L) == "Instance" and L:IsA("Player") then
        if Aimbot.Internal.LockedGhost and IsAlive(Aimbot.Internal.LockedGhost) then
            return Aimbot.Internal.LockedGhost
        end
        if Aimbot.Internal.LockedGhost then Aimbot.Internal.LockedGhost = nil end
        return L.Character
    end
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
    if not IsAlive(part) then return nil end
    local params = BuildRayParams(part.Parent)
    local predicted = PredictPartPosition(part)
    if IsPointVisible(origin, predicted, params) then return predicted end
    if IsPointVisible(origin, part.Position, params) then return part.Position end
    return nil
end

local function GetVisiblePointOnPart(origin, part)
    if not part or not part:IsA("BasePart") or not IsAlive(part) then return nil end

    local aimPos = PredictPartPosition(part)

    if not Aimbot.Settings.WallCheck or ShouldBypassWallCheck() then
        return aimPos
    end

    local params = BuildRayParams(part.Parent)
    local size = part.Size
    local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
    local cf = CFrame.new(aimPos)

    local isNearest = (Aimbot.Settings.LockPart == "Nearest")
    local isPerfect = (Aimbot.Settings.WallCheckMode == "Perfect")

    if isPerfect then
        local pts = {
            aimPos,
            (cf * CFrame.new( hx,  hy,  hz)).Position,
            (cf * CFrame.new(-hx,  hy,  hz)).Position,
            (cf * CFrame.new( hx, -hy,  hz)).Position,
            (cf * CFrame.new(-hx, -hy,  hz)).Position,
            (cf * CFrame.new( hx,  hy, -hz)).Position,
            (cf * CFrame.new(-hx,  hy, -hz)).Position,
            (cf * CFrame.new( hx, -hy, -hz)).Position,
            (cf * CFrame.new(-hx, -hy, -hz)).Position,
        }
        for _, pt in ipairs(pts) do
            if not IsPointVisible(origin, pt, params) then return nil end
        end
        if isNearest then
            local mousePos = GetMousePos()
            local bestPt, bestDist = aimPos, math.huge
            for _, pt in ipairs(pts) do
                local screen, on = workspace.CurrentCamera:WorldToViewportPoint(pt)
                if on then
                    local d = (mousePos - Vector2.new(screen.X, screen.Y)).Magnitude
                    if d < bestDist then bestDist = d; bestPt = pt end
                end
            end
            return bestPt
        end
        return aimPos
    end

    if IsPointVisible(origin, aimPos, params) then
        return aimPos
    end
    return nil
end

local function TryGetVisiblePointOnPart(origin, part)
    if not part or not part:IsA("BasePart") or not IsAlive(part) then return nil end
    local aimPos = PredictPartPosition(part)
    if not Aimbot.Settings.WallCheck or ShouldBypassWallCheck() then
        return aimPos
    end
    local params = BuildRayParams(part.Parent)
    if IsPointVisible(origin, aimPos, params) then return aimPos end
    if IsPointVisible(origin, part.Position, params) then return part.Position end
    return nil
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
    if not IsAlive(character) then return false end

    local isGhost = character:GetAttribute("AirHub_Ghost") == true

    if isGhost and not player then
        local pv = character:FindFirstChild("Player")
        if pv and pv.Value then player = pv.Value end
    end

    local hum = character:FindFirstChildOfClass("Humanoid")
    if Aimbot.Settings.AliveCheck and (not hum or hum.Health <= 0) then return false end

    if isGhost and player then
        local ownerChar = player.Character
        if not ownerChar then return false end
        local ownerHum = ownerChar:FindFirstChildOfClass("Humanoid")
        if not ownerHum or ownerHum.Health <= 0 then return false end
    end

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
    Aimbot.Internal.LockedGhost = nil
    Aimbot.FOVCircle.Color = Color3.fromRGB(255, 255, 255)
end

local function LockedTargetStillInFOV()
    if Aimbot.Settings.IgnoreFOV then return true end
    if not Aimbot.FOVSettings.Enabled then return true end
    local part = Aimbot.LockPartInstance
    if not part or not IsAlive(part) then return true end
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
        local targetPlayer = ResolveOwnerPlayer(targetChar) or Players:GetPlayerFromCharacter(targetChar)
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
    for _, ghostInfo in ipairs(GetBacktrackGhostTargets()) do
        table.insert(candidates, {
            character = ghostInfo.character,
            player = ghostInfo.player,
            isGhost = true,
        })
    end

    local ignoreFOV = Aimbot.Settings.IgnoreFOV
    local fovEnabled = Aimbot.FOVSettings.Enabled and not ignoreFOV
    local required = fovEnabled and Aimbot.FOVSettings.Amount or 999999
    local bestTarget, bestPart, bestDist = nil, nil, math.huge
    local bestGhostChar = nil
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
            if targetPart and IsAlive(targetPart) then
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
                    bestGhostChar = cand.isGhost and charTarget or nil
                end
            end
        end
    end

    if bestTarget and bestPart then
        Aimbot.Locked = bestTarget
        Aimbot.LockPartInstance = bestPart
        Aimbot.Internal.LockedGhost = bestGhostChar
    else
        CancelLock()
    end
end

local function LogShot(targetChar, targetName, startHealth, hitPartName, wasVisible)
    if not targetChar then return end

    local realChar = targetChar
    if targetChar:GetAttribute("AirHub_Ghost") then
        local pv = targetChar:FindFirstChild("Player")
        if pv and pv.Value and pv.Value.Character then
            realChar = pv.Value.Character
            targetName = pv.Value.Name
        else
            return
        end
    end

    local hum = realChar:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local endHealth = hum.Health
    local hit = endHealth < startHealth

    if hit then
        if hum.Health <= 0 then Util.PlayKillsound() else Util.PlayHitsound() end
    end
    if not H.Logging or not H.Logging.Enabled then return end
    if hit and not H.Logging.ShowHit then return end
    if not hit and not H.Logging.ShowMiss then return end

    local displayName = targetName or realChar.Name
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

local function DisableDesyncDuringShot()
    local Hg = getgenv().AirHub
    if not Hg or not Hg.AntiAim or not Hg.AntiAim.Desync then return nil end
    local D = Hg.AntiAim.Desync
    local S = D.Settings
    if not S then return nil end

    local saved = {
        WasEnabled    = S.Enabled,
        Mode          = S.Mode,
        RefreshOnShot = S.RefreshOnShot,
    }

    if S.Enabled then
        S.Enabled = false
        if Hg.AntiAim.StopDesync then
            pcall(Hg.AntiAim.StopDesync)
        end
    end

    local restored = false
    return function()
        if restored then return end
        restored = true

        local Hg2 = getgenv().AirHub
        if not Hg2 or not Hg2.AntiAim or not Hg2.AntiAim.Desync then return end
        local D2 = Hg2.AntiAim.Desync
        local S2 = D2.Settings
        if not S2 then return end

        S2.Enabled = saved.WasEnabled
        if saved.Mode          ~= nil then S2.Mode          = saved.Mode          end
        if saved.RefreshOnShot ~= nil then S2.RefreshOnShot = saved.RefreshOnShot end

        if saved.WasEnabled and Hg2.AntiAim.StartDesync then
            pcall(Hg2.AntiAim.StartDesync)
        end
    end
end

local function WaitForShotPoint(targetPart)
    if not targetPart or not IsAlive(targetPart) then return nil, false end
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
        if not IsAlive(targetPart) then return nil, false end
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

--// ---------------------------------------------------------------------------
--// PatchShotArgs
--// ---------------------------------------------------------------------------
local function PatchValueRecursive(v, camPos, aimPos, dirUnit, correctCF, depth)
    if depth > 4 then return v, 0 end
    local t = typeof(v)
    if t == "Vector3" then
        local vm = v.Magnitude
        if math.abs(vm - 1) < 0.4 then
            return dirUnit, 1
        elseif vm > 5 then
            return aimPos, 1
        end
        return v, 0
    elseif t == "CFrame" then
        return correctCF, 1
    elseif t == "Ray" then
        local ok, r = pcall(Ray.new, camPos, dirUnit)
        if ok and r then return r, 1 end
        return v, 0
    elseif t == "table" then
        local newT = {}
        local n = 0
        for k, subv in pairs(v) do
            local sv, sn = PatchValueRecursive(subv, camPos, aimPos, dirUnit, correctCF, depth + 1)
            newT[k] = sv
            n = n + sn
        end
        return newT, n
    end
    return v, 0
end

local function PatchShotArgs(args, camPos, aimPos)
    local cam = workspace.CurrentCamera
    local camPos2 = camPos or (cam and cam.CFrame.Position)
    if not camPos2 then return 0 end

    local toTarget = aimPos - camPos2
    if toTarget.Magnitude < 0.001 then return 0 end
    local dirUnit = toTarget.Unit
    local correctCF = CFrame.lookAt(camPos2, aimPos)

    local v3Indices = {}
    for i = 1, args.n do
        if typeof(args[i]) == "Vector3" then
            table.insert(v3Indices, { idx = i, mag = args[i].Magnitude })
        end
    end

    local dirIdx, posIdx
    if #v3Indices >= 2 then
        table.sort(v3Indices, function(a, b) return a.mag < b.mag end)
        dirIdx = v3Indices[1].idx
        posIdx = v3Indices[#v3Indices].idx
        if v3Indices[#v3Indices].mag < 5 then posIdx = nil end
        if math.abs(v3Indices[1].mag - 1) > 0.4 then
            if posIdx then dirIdx = nil
            else dirIdx = nil posIdx = nil end
        end
    end

    local totalPatched = 0
    for i = 1, args.n do
        local v = args[i]
        local t = typeof(v)
        if t == "Vector3" then
            if i == dirIdx then
                args[i] = dirUnit
                totalPatched = totalPatched + 1
            elseif i == posIdx then
                args[i] = aimPos
                totalPatched = totalPatched + 1
            else
                local vm = v.Magnitude
                if math.abs(vm - 1) < 0.4 then
                    args[i] = dirUnit
                    totalPatched = totalPatched + 1
                elseif vm > 5 then
                    args[i] = aimPos
                    totalPatched = totalPatched + 1
                end
            end
        elseif t == "CFrame" then
            args[i] = correctCF
            totalPatched = totalPatched + 1
        elseif t == "Ray" then
            local ok, r = pcall(Ray.new, camPos2, dirUnit)
            if ok and r then
                args[i] = r
                totalPatched = totalPatched + 1
            end
        elseif t == "table" then
            local newT, n = PatchValueRecursive(v, camPos2, aimPos, dirUnit, correctCF, 1)
            args[i] = newT
            totalPatched = totalPatched + n
        end
    end

    return totalPatched
end

--// ---------------------------------------------------------------------------
--// Mode availability cache
--// ---------------------------------------------------------------------------
local function CacheGet(key)
    local c = Aimbot.Internal.ModeCache[key]
    if not c then return nil end
    if tick() - c.t > (Aimbot.Settings.ModeCacheTTL or 60) then
        Aimbot.Internal.ModeCache[key] = nil
        return nil
    end
    return c.available, c.reason
end

local function CacheSet(key, available, reason)
    Aimbot.Internal.ModeCache[key] = {
        available = available,
        reason    = reason,
        t         = tick(),
    }
end

local function ComputeModeAvailability(mode)
    if mode == "RayHook" then
        local ok, mt = pcall(getrawmetatable, Ray.new(Vector3.zero, Vector3.zero))
        return (ok and mt ~= nil), "no Ray metatable"
    elseif mode == "RayNew" then
        if type(Ray) ~= "table" or type(Ray.new) ~= "function" then
            return false, "Ray.new unavailable"
        end
        return true
    elseif mode == "Raycast" then
        local ws = workspace
        if type(ws.Raycast) ~= "function" then
            return false, "workspace.Raycast missing"
        end
        local hookf = getExec("hookmetamethod")
        local getMethod = getExec("getnamecallmethod")
        if not hookf or not getMethod then
            return false, "no hookmetamethod"
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

local function IsModeAvailable(mode)
    local cached, reason = CacheGet(mode)
    if cached ~= nil then return cached, reason end
    local available, r = ComputeModeAvailability(mode)
    CacheSet(mode, available, r)
    return available, r
end

local function InvalidateModeCache()
    Aimbot.Internal.ModeCache = {}
end

local function GetEffectiveMode()
    return Aimbot.Settings.SilentAimMode
end

local function IsModeHooked(mode)
    return Aimbot.Settings.Enabled
       and Aimbot.Settings.SilentAim
       and Aimbot.Settings.SilentAimMode == mode
end

local function ShouldRedirect(mode)
    return IsModeHooked(mode) and Running
end

--// ---------------------------------------------------------------------------
--// Autowork
--// ---------------------------------------------------------------------------
local ALL_METHODS = {
    "Raycast",
    "RayNew", "RayHook", "ScreenPointToRay", "Vector3Unit",
    "MouseFull", "MouseHit", "GunHandler", "FireServer",
    "MouseLock", "Mouse", "CFrameHook", "Vector3New",
}

local function GetWorkingMethods()
    local list = {}
    for _, mode in ipairs(ALL_METHODS) do
        local ok = IsModeAvailable(mode)
        if ok then
            table.insert(list, mode)
        end
    end
    return list
end

local function CycleAutowork(direction)
    direction = tonumber(direction) or 1
    local list = GetWorkingMethods()
    if #list == 0 then
        return nil, list
    end

    local current = Aimbot.Settings.SilentAimMode
    local pos = 1
    for i, m in ipairs(list) do
        if m == current then pos = i; break end
    end

    pos = pos + direction
    if pos < 1 then pos = #list end
    if pos > #list then pos = 1 end

    local newMode = list[pos]
    Aimbot.Settings.SilentAimMode = newMode
    Aimbot.Internal.LastManageKey = nil

    DebugPrint(string.format("autowork -> %s (of %d working methods)", tostring(newMode), #list))

    return newMode, list
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

local function FireClick(btn)
    local mousePos = UserInputService:GetMouseLocation()
    VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, true,  game, 1)
    task.wait(0.001)
    VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, false, game, 1)
end

local function FireClickNoDesync(btn, restoreDelay)
    local restore = DisableDesyncDuringShot()
    FireClick(btn)
    if restore then
        task.delay(restoreDelay or 0.25, restore)
    end
end

local function ScheduleHookRemoval(restoreFn, holdTime)
    task.delay((holdTime or Aimbot.Settings.WallbangHoldTime or 0.1) + 0.05, function()
        pcall(restoreFn)
    end)
end

--// ==== WALLBANG MODES ====
local function PerformWallbang_RemotePatch(targetPart, btn)
    local hookf     = getExec("hookmetamethod")
    local getMethod = getExec("getnamecallmethod")
    local newc      = getExec("newcclosure")
    local checkC    = getExec("checkcaller")
    if not hookf or not getMethod or not newc then return false end

    local aimPos   = PredictPartPosition(targetPart)
    local holdTime = Aimbot.Settings.WallbangHoldTime or 0.1
    WB.HoldUntil = tick() + holdTime

    local original
    original = hookf(game, "__namecall", newc(function(self, ...)
        local method = getMethod()
        if method == "FireServer"
           and not (checkC and checkC())
           and tick() < WB.HoldUntil then
            local args = table.pack(...)
            local cam = workspace.CurrentCamera
            local cPos = cam and cam.CFrame.Position or GetCheckOrigin()
            local patched = PatchShotArgs(args, cPos, aimPos)
            if patched > 0 then
                return original(self, table.unpack(args, 1, args.n))
            end
        end
        return original(self, ...)
    end))

    FireClickNoDesync(btn, holdTime + 0.05)
    ScheduleHookRemoval(function() hookf(game, "__namecall", original) end, holdTime)
    return true
end

local function PerformWallbang_RemotePatchFull(targetPart, btn)
    local hookf     = getExec("hookmetamethod")
    local getMethod = getExec("getnamecallmethod")
    local newc      = getExec("newcclosure")
    local checkC    = getExec("checkcaller")
    if not hookf or not getMethod or not newc then return false end

    local aimPos   = PredictPartPosition(targetPart)
    local holdTime = Aimbot.Settings.WallbangHoldTime or 0.1
    WB.HoldUntil = tick() + holdTime

    local function rewriteValue(v, depth)
        depth = depth or 0
        if depth > 4 then return v end
        local t = typeof(v)
        if t == "Vector3" then
            local vm = v.Magnitude
            if math.abs(vm - 1) < 0.15 then
                local cPos = workspace.CurrentCamera.CFrame.Position
                return (aimPos - cPos).Unit
            elseif vm > 5 then
                local dir = (aimPos - v)
                if dir.Magnitude > 0.001 then
                    return aimPos - dir.Unit * 2
                end
            end
            return v
        elseif t == "CFrame" then
            return CFrame.lookAt(v.Position, aimPos)
        elseif t == "table" then
            local newT = {}
            for k, subv in pairs(v) do
                newT[k] = rewriteValue(subv, depth + 1)
            end
            return newT
        end
        return v
    end

    local original
    original = hookf(game, "__namecall", newc(function(self, ...)
        local method = getMethod()
        if method == "FireServer"
           and not (checkC and checkC())
           and tick() < WB.HoldUntil then
            local args = { ... }
            for i = 1, #args do
                args[i] = rewriteValue(args[i], 0)
            end
            return original(self, table.unpack(args, 1, #args))
        end
        return original(self, ...)
    end))

    FireClickNoDesync(btn, holdTime + 0.05)
    ScheduleHookRemoval(function() hookf(game, "__namecall", original) end, holdTime)
    return true
end

local function PerformWallbang_RayIgnore(targetPart, btn)
    local hookf     = getExec("hookmetamethod")
    local getMethod = getExec("getnamecallmethod")
    local newc      = getExec("newcclosure")
    local checkC    = getExec("checkcaller")
    if not hookf or not getMethod or not newc then return false end

    local holdTime = Aimbot.Settings.WallbangHoldTime or 0.1
    WB.HoldUntil = tick() + holdTime

    local original
    original = hookf(game, "__namecall", newc(function(self, ...)
        local method = getMethod()
        if method == "Raycast"
           and not (checkC and checkC())
           and tick() < WB.HoldUntil then
            local args = { ... }
            local params = args[3]
            if typeof(params) == "Instance" and params:IsA("RaycastParams") then
                local current = params.FilterDescendantsInstances
                local extended = {}
                if type(current) == "table" then
                    for _, v in ipairs(current) do
                        extended[#extended + 1] = v
                    end
                end
                extended[#extended + 1] = workspace
                pcall(function()
                    params.FilterType = Enum.RaycastFilterType.Exclude
                    params.FilterDescendantsInstances = extended
                end)
            end
            return original(self, table.unpack(args, 1, #args))
        end
        return original(self, ...)
    end))

    FireClickNoDesync(btn, holdTime + 0.05)
    ScheduleHookRemoval(function() hookf(game, "__namecall", original) end, holdTime)
    return true
end

local function PerformWallbang_RayNewHook(targetPart, btn)
    if type(Ray) ~= "table" or type(Ray.new) ~= "function" then return false end
    local old = Ray.new
    local aimPos   = PredictPartPosition(targetPart)
    local holdTime = Aimbot.Settings.WallbangHoldTime or 0.1
    WB.HoldUntil = tick() + holdTime

    local newc = getExec("newcclosure")
    local function handler(origin, direction)
        if tick() < WB.HoldUntil
           and typeof(origin) == "Vector3"
           and typeof(direction) == "Vector3" then
            local dir = aimPos - origin
            local dm = dir.Magnitude
            if dm > 0.0001 then
                local dirUnit = dir / dm
                local origMag = direction.Magnitude
                if origMag < 0.0001 then
                    return old(origin, dirUnit)
                elseif origMag > 50 then
                    return old(origin, dir)
                else
                    return old(origin, dirUnit * origMag)
                end
            end
        end
        return old(origin, direction)
    end
    if newc then pcall(function() handler = newc(handler) end) end

    local ok = pcall(function() Ray.new = handler end)
    if not ok then return false end

    FireClickNoDesync(btn, holdTime + 0.05)
    ScheduleHookRemoval(function() Ray.new = old end, holdTime)
    return true
end

local function PerformWallbang_MuzzleTeleport(targetPart, btn)
    local hookf     = getExec("hookmetamethod")
    local getMethod = getExec("getnamecallmethod")
    local newc      = getExec("newcclosure")
    local checkC    = getExec("checkcaller")
    if not hookf or not getMethod or not newc then return false end

    local aimPos   = PredictPartPosition(targetPart)
    local holdTime = Aimbot.Settings.WallbangHoldTime or 0.1
    WB.HoldUntil = tick() + holdTime

    local original
    original = hookf(game, "__namecall", newc(function(self, ...)
        local method = getMethod()
        if method == "FireServer"
           and not (checkC and checkC())
           and tick() < WB.HoldUntil then
            local args = { ... }
            local patchedOrigin = false
            local cPos = workspace.CurrentCamera.CFrame.Position
            for i, v in ipairs(args) do
                if typeof(v) == "Vector3" then
                    local vm = v.Magnitude
                    if vm > 5 and not patchedOrigin then
                        local dir = (aimPos - v)
                        if dir.Magnitude > 0.001 then
                            args[i] = aimPos - dir.Unit * 2
                            patchedOrigin = true
                        end
                    elseif math.abs(vm - 1) < 0.15 then
                        args[i] = (aimPos - cPos).Unit
                    end
                end
            end
            return original(self, table.unpack(args, 1, #args))
        end
        return original(self, ...)
    end))

    FireClickNoDesync(btn, holdTime + 0.05)
    ScheduleHookRemoval(function() hookf(game, "__namecall", original) end, holdTime)
    return true
end

local function PerformWallbang_MouseHit(targetPart, btn)
    local oldGetMouse = LocalPlayer.GetMouse
    if type(oldGetMouse) ~= "function" then
        warn("[AirHub] Wallbang MouseHit: LocalPlayer.GetMouse is not a function")
        return false
    end

    local aimPos   = PredictPartPosition(targetPart)
    local holdTime = Aimbot.Settings.WallbangHoldTime or 0.1
    WB.HoldUntil = tick() + holdTime

    local function fakeGetMouse()
        local realMouse = oldGetMouse(LocalPlayer)
        return setmetatable({}, {
            __index = function(_, k)
                if tick() < WB.HoldUntil then
                    if k == "Hit" then return aimPos end
                    if k == "Target" then return targetPart end
                    if k == "TargetSurface" then return Vector3.new(0, 1, 0) end
                    if k == "UnitRay" then
                        local camPos = workspace.CurrentCamera.CFrame.Position
                        return Ray.new(camPos, (aimPos - camPos).Unit)
                    end
                end
                return realMouse[k]
            end,
        })
    end

    pcall(function() LocalPlayer.GetMouse = fakeGetMouse end)
    FireClickNoDesync(btn, holdTime + 0.05)
    ScheduleHookRemoval(function() pcall(function() LocalPlayer.GetMouse = oldGetMouse end) end, holdTime)
    return true
end

local function PerformWallbang_ScreenPointToRay(targetPart, btn)
    local cam = workspace.CurrentCamera
    if not cam then return false end
    local old = cam.ScreenPointToRay
    if type(old) ~= "function" then return false end

    local aimPos   = PredictPartPosition(targetPart)
    local holdTime = Aimbot.Settings.WallbangHoldTime or 0.1
    WB.HoldUntil = tick() + holdTime

    local newc = getExec("newcclosure")
    local function handler(self, x, y)
        if tick() < WB.HoldUntil then
            local camPos = self.CFrame.Position
            local dir = aimPos - camPos
            if dir.Magnitude > 0.001 then
                return Ray.new(camPos, dir.Unit)
            end
        end
        return old(self, x, y)
    end
    if newc then pcall(function() handler = newc(handler) end) end

    local ok = pcall(function() cam.ScreenPointToRay = handler end)
    if not ok then return false end

    FireClickNoDesync(btn, holdTime + 0.05)
    ScheduleHookRemoval(function() pcall(function() cam.ScreenPointToRay = old end) end, holdTime)
    return true
end

local function PerformWallbang_CameraTP(targetPart, btn)
    local cam = workspace.CurrentCamera
    if not cam then return false end
    local aimPos   = PredictPartPosition(targetPart)
    local oldCF    = cam.CFrame
    local holdTime = Aimbot.Settings.WallbangHoldTime or 0.1

    cam.CFrame = CFrame.lookAt(cam.CFrame.Position, aimPos)
    FireClickNoDesync(btn, holdTime + 0.05)
    task.wait(math.min(holdTime, 0.05))
    cam.CFrame = oldCF
    return true
end

local function PerformWallbang(targetPart, btn)
    if not Aimbot.Settings.WallbangEnabled then return false end
    if not targetPart or not IsAlive(targetPart) then return false end

    local method = Aimbot.Settings.WallbangMethod
    local char = targetPart.Parent
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local startHealth = hum and hum.Health or 0

    local ok = false
    if method == "RemotePatch" then
        ok = PerformWallbang_RemotePatch(targetPart, btn)
    elseif method == "RemotePatchFull" then
        ok = PerformWallbang_RemotePatchFull(targetPart, btn)
    elseif method == "RayIgnore" then
        ok = PerformWallbang_RayIgnore(targetPart, btn)
    elseif method == "RayNewHook" then
        ok = PerformWallbang_RayNewHook(targetPart, btn)
    elseif method == "MuzzleTeleport" then
        ok = PerformWallbang_MuzzleTeleport(targetPart, btn)
    elseif method == "MouseHit" then
        ok = PerformWallbang_MouseHit(targetPart, btn)
    elseif method == "ScreenPointToRay" then
        ok = PerformWallbang_ScreenPointToRay(targetPart, btn)
    elseif method == "CameraTP" then
        ok = PerformWallbang_CameraTP(targetPart, btn)
    end

    if ok then
        task.delay(0.2, function()
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
    local desyncWasEnabled   = false
    local desyncSavedMode    = nil
    local desyncSavedRefresh = nil
    if Hg and Hg.AntiAim and Hg.AntiAim.Desync and Hg.AntiAim.Desync.Settings then
        local S = Hg.AntiAim.Desync.Settings
        desyncWasEnabled   = S.Enabled
        desyncSavedMode    = S.Mode
        desyncSavedRefresh = S.RefreshOnShot
        if not desyncWasEnabled then
            S.Enabled = true
            S.Mode = "OldPosition"
            S.RefreshOnShot = true
            if Hg.AntiAim.StartDesync then Hg.AntiAim.StartDesync() end
        end
    end

    TeleportToTarget(targetPart)
    task.wait(0.01)

    FireClick(btn)

    task.wait(0.02)
    RestoreCurrentCFrame()

    if Hg and Hg.AntiAim and Hg.AntiAim.Desync and Hg.AntiAim.Desync.Settings and not desyncWasEnabled then
        local S = Hg.AntiAim.Desync.Settings
        S.Enabled = false
        if desyncSavedMode    ~= nil then S.Mode = desyncSavedMode end
        if desyncSavedRefresh ~= nil then S.RefreshOnShot = desyncSavedRefresh end
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
    if not targetPart or not IsAlive(targetPart) then return end

    local targetChar = targetPart.Parent
    if not targetChar then return end

    local isGhost = targetChar:GetAttribute("AirHub_Ghost") == true

    local targetPlayer
    local realCharForHealth = targetChar
    if isGhost then
        local pv = targetChar:FindFirstChild("Player")
        if pv and pv.Value then
            targetPlayer = pv.Value
            realCharForHealth = pv.Value.Character or targetChar
        end
    else
        targetPlayer = Players:GetPlayerFromCharacter(targetChar)
    end

    local displayName = targetPlayer and targetPlayer.Name or targetChar.Name

    local hum = realCharForHealth:FindFirstChildOfClass("Humanoid")
    if hum and Aimbot.Settings.AliveCheck and hum.Health <= 0 then return end
    local startHealth = hum and hum.Health or 0

    local mode = GetEffectiveMode()
    DebugPrint(string.format("shot start | mode=%s target=%s part=%s btn=%d visible=%s",
        tostring(mode),
        tostring(displayName),
        tostring(targetPart.Name),
        btn or -1,
        tostring(wasVisible)))

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

    local restoreDesync = DisableDesyncDuringShot()
    if restoreDesync then
        task.delay(0.25, restoreDesync)
    end

    local checkPoint, nowVisible = WaitForShotPoint(targetPart)
    if Aimbot.Settings.WallCheck and not checkPoint then
        DebugPrint("abort: wall check failed")
        if restoreDesync then restoreDesync() end
        return
    end
    if nowVisible ~= nil then wasVisible = nowVisible end

    if mode == "MouseLock" then
        local visiblePoint = checkPoint
        if not visiblePoint then
            local origin = workspace.CurrentCamera.CFrame.Position
            visiblePoint = GetVisiblePointOnPart(origin, targetPart)
        end
        if not visiblePoint then
            if restoreDesync then restoreDesync() end
            return
        end

        local targetX, targetY = WorldToMouseVIM(visiblePoint)
        if not targetX then
            if restoreDesync then restoreDesync() end
            return
        end

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

        DebugPrint("shot fired (MouseLock)")
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
        if not visiblePoint then
            if restoreDesync then restoreDesync() end
            return
        end

        local targetX, targetY = WorldToMouseVIM(visiblePoint)
        if not targetX then
            if restoreDesync then restoreDesync() end
            return
        end
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

        DebugPrint("shot fired (Mouse)")
        task.delay(0.15, function()
            LogShot(targetChar, displayName, startHealth, targetPart.Name, wasVisible)
        end)
        return
    end

    if mode == "GunHandler" or mode == "RayHook" or mode == "RayNew"
       or mode == "MouseHit" or mode == "MouseFull"
       or mode == "Vector3Unit" or mode == "ScreenPointToRay"
       or mode == "FireServer" or mode == "Raycast"
       or mode == "CFrameHook" or mode == "Vector3New" then
        FireClickNoDesync(btn, 0.25)
        DebugPrint("shot fired (hook mode=" .. tostring(mode) .. ")")
        task.delay(0.15, function()
            LogShot(targetChar, displayName, startHealth, targetPart.Name, wasVisible)
        end)
        return
    end

    local origin = workspace.CurrentCamera.CFrame.Position
    local visiblePoint = checkPoint or GetVisiblePointOnPart(origin, targetPart)
    if not visiblePoint then
        if restoreDesync then restoreDesync() end
        return
    end
    local oldCF = workspace.CurrentCamera.CFrame
    workspace.CurrentCamera.CFrame = CFrame.new(oldCF.Position, visiblePoint)

    local ok = pcall(function()
        FireClickNoDesync(btn, 0.25)
    end)
    workspace.CurrentCamera.CFrame = oldCF
    if not ok then HandleError("Camera silent shot input failed") end

    DebugPrint("shot fired (Camera fallback)")
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

    local handler = function(t, k)
        if k == 'Direction' and not H.ShuttingDown and IsModeHooked("RayHook") then
            if not ShouldRedirect("RayHook") then
                return oldRayIndex(t, k)
            end
            local target = Aimbot.LockPartInstance
            if target and IsAlive(target) then
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

    mt.__index = handler
    RayHookActive = true

    Aimbot.Internal.HookHandlers.RayHook     = handler
    Aimbot.Internal.HookHandlers.RayHookOrig = savedOriginal
end

local function RemoveRayHook()
    if not RayHookActive then return end
    local success, mt = pcall(getrawmetatable, Ray.new(Vector3.zero, Vector3.zero))
    if success and mt and oldRayIndex then mt.__index = oldRayIndex end
    RayHookActive = false
    Aimbot.Internal.HookHandlers.RayHook = nil
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
            if not (checkC and checkC()) then
                if not ShouldRedirect("RayNew") then
                    return RayNewOriginal(origin, direction)
                end
                local target = Aimbot.LockPartInstance
                if target and IsAlive(target) then
                    local aimPos = PredictPartPosition(target)
                    local dir = aimPos - origin
                    local dm = dir.Magnitude
                    if dm > 0.0001 then
                        local dirUnit = dir / dm
                        if type(direction) == "Vector3" then
                            local origMag = direction.Magnitude
                            if origMag < 0.0001 then
                                return RayNewOriginal(origin, dirUnit)
                            elseif origMag > 50 then
                                return RayNewOriginal(origin, dir)
                            else
                                return RayNewOriginal(origin, dirUnit * origMag)
                            end
                        else
                            return RayNewOriginal(origin, dirUnit)
                        end
                    end
                end
            end
        end
        return RayNewOriginal(origin, direction)
    end
    if newc then pcall(function() handler = newc(handler) end) end

    local ok = pcall(function() Ray.new = handler end)
    if ok then
        RayNewActive = true
        Aimbot.Internal.HookHandlers.RayNew     = handler
        Aimbot.Internal.HookHandlers.RayNewOrig = RayNewOriginal
    end
end

local function RemoveRayNewHook()
    if not RayNewActive then return end
    pcall(function() Ray.new = RayNewOriginal end)
    RayNewActive = false
    RayNewOriginal = nil
    Aimbot.Internal.HookHandlers.RayNew = nil
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

    local handler = function(self, k)
        if k == "Unit" and not H.ShuttingDown and IsModeHooked("Vector3Unit") then
            local mag = math.sqrt(self.X*self.X + self.Y*self.Y + self.Z*self.Z)
            if math.abs(mag - 1) < 0.25 and mag > 0.0001 then
                if not ShouldRedirect("Vector3Unit") then
                    return V3_oldIndex(self, k)
                end
                local target = Aimbot.LockPartInstance
                if target and IsAlive(target) then
                    local aimPos = PredictPartPosition(target)
                    local camPos = workspace.CurrentCamera.CFrame.Position
                    local dir = aimPos - camPos
                    local dm = dir.Magnitude
                    if dm > 0.0001 then
                        return Vector3.new(dir.X/dm, dir.Y/dm, dir.Z/dm)
                    end
                end
            end
        end
        return V3_oldIndex(self, k)
    end

    mt.__index = handler
    V3UnitActive = true
    Aimbot.Internal.HookHandlers.V3Unit     = handler
    Aimbot.Internal.HookHandlers.V3UnitOrig = savedOriginal
end

local function RemoveVector3UnitHook()
    if not V3UnitActive then return end
    local ok, mt = pcall(getrawmetatable, Vector3.new(1, 0, 0))
    if ok and mt and V3_oldIndex then mt.__index = V3_oldIndex end
    V3UnitActive = false
    Aimbot.Internal.HookHandlers.V3Unit = nil
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
            if not ShouldRedirect("ScreenPointToRay") then
                return SPR_Original(self, x, y)
            end
            local target = Aimbot.LockPartInstance
            if target and IsAlive(target) and self and self.CFrame then
                local aimPos = PredictPartPosition(target)
                local camPos = self.CFrame.Position
                local dir = aimPos - camPos
                if dir.Magnitude > 0.0001 then
                    local okRay, ray = pcall(Ray.new, camPos, dir.Unit)
                    if okRay and ray then return ray end
                end
            end
        end
        return SPR_Original(self, x, y)
    end
    if newc then pcall(function() handler = newc(handler) end) end

    local ok = pcall(function() cam.ScreenPointToRay = handler end)
    if ok then
        SPR_Active = true
        Aimbot.Internal.HookHandlers.SPR      = handler
        Aimbot.Internal.HookHandlers.SPR_Orig = old
    end
end

local function RemoveScreenPointToRayHook()
    if not SPR_Active then return end
    local cam = workspace.CurrentCamera
    if cam and SPR_Original then
        pcall(function() cam.ScreenPointToRay = SPR_Original end)
    end
    SPR_Active = false
    SPR_Original = nil
    Aimbot.Internal.HookHandlers.SPR = nil
end

local MouseHooked = false
local originalGetMouse = nil

local function GetMouseSpoof()
    local target = Aimbot.LockPartInstance
    if not target or not IsAlive(target) then return nil end
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
                        local mode = isHit and "MouseHit" or "MouseFull"
                        if not ShouldRedirect(mode) then
                            return realMouse[k]
                        end
                        local target = Aimbot.LockPartInstance
                        if target and IsAlive(target) then
                            local aimPos = GetMouseSpoof() or PredictPartPosition(target)
                            if k == "Hit" then return aimPos end
                            if k == "UnitRay" then
                                local camPos = workspace.CurrentCamera.CFrame.Position
                                local dir = aimPos - camPos
                                if dir.Magnitude > 0.0001 then
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
--// Namecall hook — wrapped in pcall for safety
--// ---------------------------------------------------------------------------
local FS_Active = false
local FS_Original = nil

local function NamecallImpl(self, ...)
    local method = getExec("getnamecallmethod") and getExec("getnamecallmethod")() or nil
    if type(method) ~= "string" then
        return FS_Original(self, ...)
    end

    local checkC = getExec("checkcaller")

    --// ====================== Raycast ======================
    if method == "Raycast"
       and not H.ShuttingDown
       and typeof(self) == "Instance"
       and self == workspace
       and not (checkC and checkC())
       and not Aimbot.Internal.RaycastRedirectActive then
        if IsModeHooked("Raycast") and ShouldRedirect("Raycast") then
            local args = table.pack(...)
            if args.n >= 3
               and typeof(args[1]) == "Vector3"
               and typeof(args[2]) == "Vector3"
               and typeof(args[3]) == "RaycastParams" then
                local target = Aimbot.LockPartInstance
                if target and IsAlive(target) then
                    local aimPos = PredictPartPosition(target)
                    local origin = args[1]
                    local origDir = args[2]
                    local dm = (aimPos - origin).Magnitude
                    if dm > 0.0001 then
                        local dirUnit = (aimPos - origin) / dm
                        local origLen = origDir.Magnitude
                        if origLen < 0.0001 then origLen = 1000 end
                        args[2] = dirUnit * origLen
                        DebugHookPrint(string.format(
                            "Raycast patched | origin=(%.1f,%.1f,%.1f) target=%s len=%.1f",
                            origin.X, origin.Y, origin.Z,
                            tostring(target), origLen))
                        return FS_Original(self, table.unpack(args, 1, args.n))
                    end
                end
            end
        end
        return FS_Original(self, ...)
    end

    --// ====================== FireServer / InvokeServer ======================
    local isShot = (method == "FireServer" or method == "InvokeServer")
    if isShot
       and not H.ShuttingDown
       and typeof(self) == "Instance"
       and IsModeHooked("FireServer")
       and not (checkC and checkC())
       and ShouldRedirect("FireServer") then
        local target = Aimbot.LockPartInstance
        if target and IsAlive(target) then
            local aimPos = GetMouseSpoof() or PredictPartPosition(target)
            local cam = workspace.CurrentCamera
            local camPos = cam and cam.CFrame.Position or GetCheckOrigin()

            if (aimPos - camPos).Magnitude > 0.1 then
                local args = table.pack(...)
                local patched = PatchShotArgs(args, camPos, aimPos)
                if patched > 0 then
                    DebugHookPrint(string.format(
                        "FireServer patched %d args | remote=%s target=%s",
                        patched, tostring(self), tostring(target)))
                    return FS_Original(self, table.unpack(args, 1, args.n))
                end
            end
        end
    end

    return FS_Original(self, ...)
end

local function SetupFireServerHook()
    if FS_Active then return end
    local hookf = getExec("hookmetamethod")
    local newc  = getExec("newcclosure")
    if not hookf then return end

    local safeHandler = function(self, ...)
        if Aimbot.Internal.RaycastRedirectActive then
            return FS_Original(self, ...)
        end

        local ok, err = pcall(NamecallImpl, self, ...)
        if not ok then
            DebugHookPrint("namecall error: " .. tostring(err))
            if FS_Original then
                return FS_Original(self, ...)
            end
            return
        end
        return err
    end
    if newc then pcall(function() safeHandler = newc(safeHandler) end) end

    local ok = pcall(function()
        FS_Original = hookf(game, "__namecall", safeHandler)
    end)
    if ok and FS_Original then
        FS_Active = true
    end
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
            if not ShouldRedirect("GunHandler") then
                return GunHandlerOldShoot(p1, p2, p3, p4, p5, p6, p7, p8)
            end
            if Hg.Aimbot.Locked and Hg.Aimbot.LockPartInstance
               and IsAlive(Hg.Aimbot.LockPartInstance) then
                if p1 == LocalPlayer then
                    RefreshOldPositionIfNeeded()
                    local origin = workspace.CurrentCamera.CFrame.Position
                    local pt = TryGetVisiblePointOnPart(origin, Hg.Aimbot.LockPartInstance)
                    if pt then
                        p4 = pt
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
            if not (checkC and checkC()) then
                if not ShouldRedirect("CFrameHook") then
                    return CFrameHookOriginal(at, lookAt, up)
                end
                local target = Aimbot.LockPartInstance
                if target and IsAlive(target) and typeof(at) == "Vector3" then
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
            if not (checkC and checkC()) then
                if type(x) == "number" and type(y) == "number" and type(z) == "number" then
                    local mag = math.sqrt(x*x + y*y + z*z)
                    if math.abs(mag - 1) < 0.25 and mag > 0.0001 then
                        if not ShouldRedirect("Vector3New") then
                            return Vector3NewOriginal(x, y, z)
                        end
                        local target = Aimbot.LockPartInstance
                        if target and IsAlive(target) then
                            local aimPos = PredictPartPosition(target)
                            local camPos = workspace.CurrentCamera.CFrame.Position
                            local dir = aimPos - camPos
                            local dm = dir.Magnitude
                            if dm > 0.0001 then
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
    if ok then
        Vector3NewActive = true
        Aimbot.Internal.HookHandlers.V3New     = handler
        Aimbot.Internal.HookHandlers.V3NewOrig = Vector3NewOriginal
    end
end

local function RemoveVector3NewHook()
    if not Vector3NewActive then return end
    pcall(function() Vector3.new = Vector3NewOriginal end)
    Vector3NewActive = false
    Vector3NewOriginal = nil
    Aimbot.Internal.HookHandlers.V3New = nil
end

task.spawn(function()
    for _ = 1, 20 do
        if H.ShuttingDown then return end
        SetupGunHandlerHook()
        if GunHandlerHooked then return end
        task.wait(0.5)
    end
end)

local function VerifyAndFixHooks()
    if H.ShuttingDown then return end
    local Hh = Aimbot.Internal.HookHandlers

    if RayNewActive and Hh.RayNew then
        local ok, cur = pcall(function() return Ray.new end)
        if ok and cur ~= Hh.RayNew then
            warn("[AirHub] Hook watchdog: RayNew was overwritten — reinstalling")
            RayNewActive = false
            if IsModeHooked("RayNew") then SetupRayNewHook() end
        end
    end

    if Vector3NewActive and Hh.V3New then
        local ok, cur = pcall(function() return Vector3.new end)
        if ok and cur ~= Hh.V3New then
            warn("[AirHub] Hook watchdog: Vector3New was overwritten — reinstalling")
            Vector3NewActive = false
            if IsModeHooked("Vector3New") then SetupVector3NewHook() end
        end
    end

    if RayHookActive and Hh.RayHook and Hh.RayHookOrig then
        local ok, mt = pcall(getrawmetatable, Ray.new(Vector3.zero, Vector3.zero))
        if ok and mt and mt.__index ~= Hh.RayHook then
            warn("[AirHub] Hook watchdog: RayHook __index was overwritten — reinstalling")
            RayHookActive = false
            if IsModeHooked("RayHook") then SetupRayHook() end
        end
    end

    if V3UnitActive and Hh.V3Unit and Hh.V3UnitOrig then
        local ok, mt = pcall(getrawmetatable, Vector3.new(1, 0, 0))
        if ok and mt and mt.__index ~= Hh.V3Unit then
            warn("[AirHub] Hook watchdog: Vector3Unit __index was overwritten — reinstalling")
            V3UnitActive = false
            if IsModeHooked("Vector3Unit") then SetupVector3UnitHook() end
        end
    end

    if SPR_Active and Hh.SPR then
        local cam = workspace.CurrentCamera
        if cam then
            local ok, cur = pcall(function() return cam.ScreenPointToRay end)
            if ok and cur ~= Hh.SPR then
                warn("[AirHub] Hook watchdog: ScreenPointToRay was overwritten — reinstalling")
                SPR_Active = false
                if IsModeHooked("ScreenPointToRay") then SetupScreenPointToRayHook() end
            end
        end
    end
end

local function ManageHooks()
    local desired = {}

    local function want(name)
        return IsModeHooked(name)
    end

    desired.RayHook          = want("RayHook")
    desired.RayNew           = want("RayNew")
    desired.Vector3Unit      = want("Vector3Unit")
    desired.ScreenPointToRay = want("ScreenPointToRay")
    desired.Mouse            = want("MouseHit") or want("MouseFull")
    desired.FireServer       = want("FireServer") or want("Raycast")
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

    if Aimbot.Internal.LastManageKey == key then return end
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

--// ---------------------------------------------------------------------------
--// LoadAimbot
--// ---------------------------------------------------------------------------
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
                Aimbot.FOVCircle.Position = GetMousePos()
            else
                Aimbot.FOVCircle.Visible = false
            end
        end

        Aimbot.Internal.WatchdogAccum = (Aimbot.Internal.WatchdogAccum or 0) + dt
        if Aimbot.Internal.WatchdogAccum >= (Aimbot.Settings.HookWatchdogInterval or 2.0) then
            Aimbot.Internal.WatchdogAccum = 0
            pcall(VerifyAndFixHooks)
        end

        local hz = math.max(30, math.min(1000, Aimbot.Settings.AimbotHz or 120))
        local interval = 1 / hz
        Aimbot.Internal.TargetAccum = Aimbot.Internal.TargetAccum + dt
        if Aimbot.Internal.TargetAccum >= interval then
            Aimbot.Internal.TargetAccum = 0

            if Aimbot.Settings.Enabled and Running then
                GetClosestPlayer()
                Aimbot.FOVCircle.Color = Color3.fromRGB(255, 255, 255)
                if Aimbot.Locked and Aimbot.LockPartInstance and IsAlive(Aimbot.LockPartInstance) then
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
        if targetPart and IsAlive(targetPart) then
            if Aimbot.Settings.SilentAim then
                PerformSilentShot(targetPart, btn, nil)
            else
                if Aimbot.Settings.WallCheck
                   and not ShouldBypassWallCheck() then
                    local vp = WaitForShotPoint(targetPart)
                    if not vp then return end
                end
                RefreshOldPositionIfNeeded()
                FireClickNoDesync(btn, 0.25)
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
                if not targetPart or not IsAlive(targetPart) then CancelLock() return end
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
                    FireClickNoDesync(shootBtn, 0.25)
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
        if Aimbot.LockPartInstance and IsAlive(Aimbot.LockPartInstance) then
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

--// ---------------------------------------------------------------------------
--// Public exports
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
Aimbot.PatchShotArgs         = PatchShotArgs
Aimbot.PatchValueRecursive   = PatchValueRecursive
Aimbot.VerifyAndFixHooks     = VerifyAndFixHooks
Aimbot.InvalidateModeCache   = InvalidateModeCache
Aimbot.GetWorkingMethods     = GetWorkingMethods
Aimbot.CycleAutowork         = CycleAutowork
Aimbot.GetNPCCharacters      = GetNPCCharacters
Aimbot.GetLockedCharacter    = GetLockedCharacter
Aimbot.IsModeAvailable       = IsModeAvailable
Aimbot.ShouldBypassWallCheck = ShouldBypassWallCheck
Aimbot.IsBacktrackEnabled    = IsBacktrackEnabled
Aimbot.IsModeHooked          = IsModeHooked
Aimbot.ShouldRedirect        = ShouldRedirect
Aimbot.GetBacktrackGhostTargets = GetBacktrackGhostTargets
Aimbot.ResolveOwnerCharacter = ResolveOwnerCharacter
Aimbot.ResolveOwnerPlayer    = ResolveOwnerPlayer
Aimbot.DebugPrint            = DebugPrint

Aimbot.PerformWallbang          = PerformWallbang
Aimbot.PerformMagicBullet       = PerformMagicBullet
Aimbot.PerformInfiniteTP        = PerformInfiniteTP
Aimbot.DisableDesyncDuringShot  = DisableDesyncDuringShot
Aimbot.FireClickNoDesync        = FireClickNoDesync

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

    InvalidateModeCache()
    if Aimbot.IsModeAvailable then
        local modes = { "Raycast", "RayHook", "RayNew", "Vector3Unit", "ScreenPointToRay",
                        "MouseHit", "MouseFull", "GunHandler", "FireServer",
                        "MouseLock", "Mouse", "Camera", "CFrameHook", "Vector3New" }
        for _, m in ipairs(modes) do
            local ok, reason = Aimbot.IsModeAvailable(m)
            T(ok, "hook: " .. m, reason)
        end
    end

    local exports = { "CancelLock", "GetVisiblePointOnPart", "PredictPartPosition",
                      "IsModeAvailable", "ShouldBypassWallCheck",
                      "IsBacktrackEnabled", "IsModeHooked", "ShouldRedirect",
                      "GetBacktrackGhostTargets", "ResolveOwnerCharacter", "ResolveOwnerPlayer",
                      "PerformWallbang", "PerformMagicBullet", "PerformInfiniteTP",
                      "DisableDesyncDuringShot", "FireClickNoDesync",
                      "PatchShotArgs", "PatchValueRecursive",
                      "VerifyAndFixHooks", "InvalidateModeCache",
                      "GetWorkingMethods", "CycleAutowork", "DebugPrint" }
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
