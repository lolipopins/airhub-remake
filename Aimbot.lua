-- Aimbot.lua – полный аимбот с Silent Aim, авто-шотом, FOV и умным Lock Part
local Aimbot = {
    Settings = {
        Enabled = false, TeamCheck = { Enabled = true, Mode = "Enemies", TreatNeutralAsEnemy = true },
        AliveCheck = true, WallCheck = false, FallbackToVisible = false,
        AimSmoothingSpeed = 6.0, AimPrediction = 0.0,
        TriggerKey = "MouseButton2", Toggle = false, LockPart = "Head",
        AimMethod = "Smooth", SilentAim = true, IgnoreFOV = false,
        CheckFromPlayerOnTP = true,
        AutoShoot = {
            Enabled = false, ShootKey = "MouseButton1", FireRate = 0.05,
            OnlyWhenAiming = true, StrictWallCheck = false,
            AutoStop = { Enabled = false, Time = 0.1 },
            FireRateMode = "Manual"
        }
    },
    FOVSettings = { Enabled = true, Visible = true, Amount = 90 },
    FOVCircle = Drawing.new("Circle"),
    Locked = nil,
    LockPartInstance = nil,
    Internal = {}
}
getgenv().AirHub.Aimbot = Aimbot

local VISIBLE_PARTS = {"Head","HumanoidRootPart","UpperTorso","LowerTorso","Torso","Left Arm","Right Arm"}

local function GetActualPartName(lockPart)
    if lockPart == "Torso" then
        return {"Torso", "UpperTorso", "LowerTorso"}
    else
        return {lockPart}
    end
end

local function IsPartVisible(origin, part)
    if not part or not part:IsA("BasePart") then return false end
    local targetCharacter = part.Parent
    if not targetCharacter then return false end
    local localCharacter = LocalPlayer.Character
    local ignoreList = {targetCharacter}
    if localCharacter then table.insert(ignoreList, localCharacter) end
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = ignoreList
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local rayResult = workspace:Raycast(origin, part.Position - origin, params)
    return rayResult == nil
end

local function GetVisiblePointOnPart(origin, part)
    if not part or not part:IsA("BasePart") then return nil end
    if IsPartVisible(origin, part) then return part.Position end
    local size = part.Size
    local cf = part.CFrame
    local half = size * 0.5
    local testPoints = {
        cf * Vector3.new(0, half.Y, 0),
        cf * Vector3.new(0, -half.Y, 0),
        cf * Vector3.new(half.X, 0, 0),
        cf * Vector3.new(-half.X, 0, 0),
        cf * Vector3.new(0, 0, half.Z),
        cf * Vector3.new(0, 0, -half.Z)
    }
    for _, point in ipairs(testPoints) do
        if IsPartVisible(origin, part) then return point end
    end
    return nil
end

local function FindVisiblePart(player, origin, preferredParts)
    local char = player.Character
    if not char then return nil end
    if preferredParts then
        for _, name in ipairs(preferredParts) do
            local part = char:FindFirstChild(name)
            if part and part:IsA("BasePart") and IsPartVisible(origin, part) then
                return part
            end
        end
    end
    for _, name in ipairs(VISIBLE_PARTS) do
        local part = char:FindFirstChild(name)
        if part and part:IsA("BasePart") and IsPartVisible(origin, part) then
            return part
        end
    end
    return nil
end

local function IsTargetValid(targetPlayer)
    if targetPlayer == LocalPlayer then return false end
    local char = targetPlayer.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if Aimbot.Settings.AliveCheck and (not hum or hum.Health <= 0) then return false end
    local tc = Aimbot.Settings.TeamCheck
    if not tc.Enabled then return true end
    local lt, tt = LocalPlayer.Team, targetPlayer.Team
    local mode = tc.Mode
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
    Aimbot.FOVCircle.Color = Color3.fromRGB(255,255,255)
    if OriginalSensitivity then UserInputService.MouseDeltaSensitivity = OriginalSensitivity end
end

local function GetClosestPlayer()
    if Aimbot.Locked then
        local target = Aimbot.Locked
        if target and target.Character then
            if not IsTargetValid(target) then CancelLock() return end
            local origin = Camera.CFrame.Position
            local lockPart = Aimbot.Settings.LockPart
            local preferred = GetActualPartName(lockPart)
            local part
            if Aimbot.Settings.FallbackToVisible then
                part = FindVisiblePart(target, origin, preferred)
            else
                for _, name in ipairs(preferred) do
                    local p = target.Character:FindFirstChild(name)
                    if p and p:IsA("BasePart") and IsPartVisible(origin, p) then
                        part = p
                        break
                    end
                end
                if not part then
                    Aimbot.LockPartInstance = nil
                    return
                end
            end
            if part then Aimbot.LockPartInstance = part else Aimbot.LockPartInstance = nil end
            return
        else
            CancelLock()
            return
        end
    end

    local ignoreFOV = Aimbot.Settings.IgnoreFOV
    local fovEnabled = Aimbot.FOVSettings.Enabled and not ignoreFOV
    local required = fovEnabled and Aimbot.FOVSettings.Amount or 999999
    local bestTarget, bestPart, bestDist = nil, nil, math.huge
    local mousePos = UserInputService:GetMouseLocation()
    local origin = Camera.CFrame.Position
    if getgenv().AirHub.ThirdPerson and getgenv().AirHub.ThirdPerson.Settings.Enabled and Aimbot.Settings.CheckFromPlayerOnTP then
        local char = LocalPlayer.Character
        if char then
            local head = char:FindFirstChild("Head")
            if head then origin = head.Position else
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp then origin = hrp.Position end
            end
        end
    end

    for _, v in pairs(Players:GetPlayers()) do
        if not IsTargetValid(v) then continue end
        local charTarget = v.Character
        if not charTarget then continue end

        local lockPart = Aimbot.Settings.LockPart
        local preferred = GetActualPartName(lockPart)
        local targetPart = nil

        if lockPart == "Nearest" then
            targetPart = FindVisiblePart(v, origin, VISIBLE_PARTS)
        else
            if Aimbot.Settings.FallbackToVisible then
                targetPart = FindVisiblePart(v, origin, preferred)
            else
                for _, name in ipairs(preferred) do
                    local p = charTarget:FindFirstChild(name)
                    if p and p:IsA("BasePart") and IsPartVisible(origin, p) then
                        targetPart = p
                        break
                    end
                end
            end
        end

        if targetPart then
            local point = targetPart.Position
            local vec, on = Camera:WorldToViewportPoint(point)
            local dist = ignoreFOV and (point - origin).Magnitude or (on and (mousePos - Vector2.new(vec.X, vec.Y)).Magnitude or math.huge)
            if dist < bestDist and (ignoreFOV or dist < required) then
                bestDist, bestTarget, bestPart = dist, v, targetPart
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

local function LogShot(targetPlayer, startHealth, hitPartName, wasVisible)
    if not targetPlayer then return end
    local char = targetPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local endHealth = hum.Health
    local hit = endHealth < startHealth

    if hit then
        if hum.Health <= 0 then PlayKillsound() else PlayHitsound() end
    end

    if not getgenv().AirHub.Logging.Enabled then return end
    if hit and not getgenv().AirHub.Logging.ShowHit then return end
    if not hit and not getgenv().AirHub.Logging.ShowMiss then return end
    local msg, color
    if hit then
        if hum.Health <= 0 then
            msg = "💀 Killed " .. targetPlayer.Name .. " (" .. hitPartName .. ")"
            color = Color3.fromRGB(255, 255, 0)
        else
            msg = "✅ Hit " .. targetPlayer.Name .. " (" .. hitPartName .. " - " .. math.floor(startHealth - endHealth) .. " dmg)"
            color = Color3.fromRGB(0, 255, 0)
        end
    else
        if not wasVisible then
            msg = "❌ Missed (wall) " .. targetPlayer.Name
        else
            msg = "❌ Missed " .. targetPlayer.Name
        end
        color = Color3.fromRGB(255, 80, 80)
    end
    AddLog(msg, color)
end

local lastDelta = tick()

local function PerformSilentShot(targetPart, btn, wasVisible)
    if not targetPart then return end
    local targetChar = targetPart.Parent
    local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
    if not targetPlayer then return end
    local hum = targetChar:FindFirstChildOfClass("Humanoid")
    if hum and Aimbot.Settings.AliveCheck and hum.Health <= 0 then return end
    local startHealth = hum and hum.Health or 0

    local origin = Camera.CFrame.Position
    if getgenv().AirHub.ThirdPerson and getgenv().AirHub.ThirdPerson.Settings.Enabled and Aimbot.Settings.CheckFromPlayerOnTP then
        local char = LocalPlayer.Character
        if char then
            local head = char:FindFirstChild("Head")
            if head then origin = head.Position else
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp then origin = hrp.Position end
            end
        end
    end
    local visiblePoint = GetVisiblePointOnPart(origin, targetPart)
    if not visiblePoint then return end
    local predPos = visiblePoint
    if Aimbot.Settings.AimPrediction > 0 then
        local vel = Vector3.new(0,0,0)
        local root = targetPart.Parent:FindFirstChild("HumanoidRootPart")
        if root then vel = root.Velocity end
        predPos = predPos + vel * Aimbot.Settings.AimPrediction
    end

    local oldCF = Camera.CFrame
    local newCF = CFrame.new(oldCF.Position, predPos)
    Camera.CFrame = newCF

    local mousePos = UserInputService:GetMouseLocation()
    VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, true, game, 1)
    task.wait(0.001)
    VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, btn, false, game, 1)

    Camera.CFrame = oldCF

    task.delay(0.15, function()
        LogShot(targetPlayer, startHealth, targetPart.Name, wasVisible)
    end)
end

local function LoadAimbot()
    OriginalSensitivity = UserInputService.MouseDeltaSensitivity

    RunService.RenderStepped:Connect(function()
        local now = tick()
        local dt = math.min(0.033, now - lastDelta)
        lastDelta = now
        if Aimbot.FOVSettings.Enabled and Aimbot.Settings.Enabled and not Aimbot.Settings.IgnoreFOV then
            Aimbot.FOVCircle.Radius = Aimbot.FOVSettings.Amount
            Aimbot.FOVCircle.Thickness = 1
            Aimbot.FOVCircle.Filled = false
            Aimbot.FOVCircle.Transparency = 0.5
            Aimbot.FOVCircle.Visible = Aimbot.FOVSettings.Visible
            Aimbot.FOVCircle.Position = UserInputService:GetMouseLocation()
        else
            Aimbot.FOVCircle.Visible = false
        end
        local shouldScan = Aimbot.Settings.Enabled and Running
        if shouldScan then
            GetClosestPlayer()
            if Aimbot.Locked then
                local targetPart = Aimbot.LockPartInstance
                if targetPart then
                    local origin = Camera.CFrame.Position
                    if getgenv().AirHub.ThirdPerson and getgenv().AirHub.ThirdPerson.Settings.Enabled and Aimbot.Settings.CheckFromPlayerOnTP then
                        local char = LocalPlayer.Character
                        if char then
                            local head = char:FindFirstChild("Head")
                            if head then origin = head.Position else
                                local hrp = char:FindFirstChild("HumanoidRootPart")
                                if hrp then origin = hrp.Position end
                            end
                        end
                    end
                    local visiblePoint = GetVisiblePointOnPart(origin, targetPart)
                    if visiblePoint then
                        local predPos = visiblePoint
                        if Aimbot.Settings.AimPrediction > 0 then
                            local vel = Vector3.new(0,0,0)
                            local root = targetPart.Parent:FindFirstChild("HumanoidRootPart")
                            if root then vel = root.Velocity end
                            predPos = predPos + vel * Aimbot.Settings.AimPrediction
                        end
                        Aimbot.FOVCircle.Color = Color3.fromRGB(255,200,70)
                    end
                end
            end
        end
    end)

    UserInputService.InputBegan:Connect(function(inp)
        if Typing then return end
        local triggerKey = Aimbot.Settings.TriggerKey
        local keyPressed = false
        if inp.UserInputType == Enum.UserInputType.Keyboard then
            keyPressed = inp.KeyCode == Enum.KeyCode[triggerKey]
        elseif inp.UserInputType == Enum.UserInputType[triggerKey] then
            keyPressed = true
        end
        if keyPressed then
            if Aimbot.Settings.Toggle then
                Running = not Running
                if not Running then CancelLock() end
            else
                Running = true
            end
        end
    end)

    UserInputService.InputEnded:Connect(function(inp)
        if Typing or Aimbot.Settings.Toggle then return end
        local triggerKey = Aimbot.Settings.TriggerKey
        local keyReleased = false
        if inp.UserInputType == Enum.UserInputType.Keyboard then
            keyReleased = inp.KeyCode == Enum.KeyCode[triggerKey]
        elseif inp.UserInputType == Enum.UserInputType[triggerKey] then
            keyReleased = true
        end
        if keyReleased then
            Running = false
            CancelLock()
        end
    end)

    UserInputService.InputBegan:Connect(function(inp)
        if Typing then return end
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
            local origin = Camera.CFrame.Position
            local wasVisible = GetVisiblePointOnPart(origin, targetPart) ~= nil
            PerformSilentShot(targetPart, btn, wasVisible)
        end
    end)

    local function GetWeaponFireRate()
        local char = LocalPlayer.Character
        if not char then return 0.05 end
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Tool") then
                local rate = child:FindFirstChild("FireRate")
                if rate and rate:IsA("NumberValue") then return math.clamp(rate.Value, 0.01, 1) end
                local attr = child:GetAttribute("FireRate")
                if attr and type(attr) == "number" then return math.clamp(attr, 0.01, 1) end
            end
        end
        return 0.05
    end

    local function ProcessAutoShoot()
        while task.wait(0.01) do
            xpcall(function()
                if not Aimbot.Settings.AutoShoot.Enabled then return end
                if Aimbot.Settings.AutoShoot.OnlyWhenAiming and not Running then return end
                if not Aimbot.Locked or not Aimbot.LockPartInstance then return end
                local nowt = tick()
                local minDelay
                local mode = Aimbot.Settings.AutoShoot.FireRateMode
                if mode == "MaxSpeed" then minDelay = 0.01
                elseif mode == "WeaponRate" then minDelay = GetWeaponFireRate()
                else minDelay = Aimbot.Settings.AutoShoot.FireRate end
                if nowt - LastShotTime < minDelay then return end
                local targetPart = Aimbot.LockPartInstance
                if not targetPart then return end
                local targetChar = targetPart.Parent
                local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
                if not targetPlayer then return end
                local hum = targetChar:FindFirstChildOfClass("Humanoid")
                if hum and Aimbot.Settings.AliveCheck and hum.Health <= 0 then CancelLock() return end
                local startHealth = hum and hum.Health or 0
                local origin = Camera.CFrame.Position
                if getgenv().AirHub.ThirdPerson and getgenv().AirHub.ThirdPerson.Settings.Enabled and Aimbot.Settings.CheckFromPlayerOnTP then
                    local char = LocalPlayer.Character
                    if char then
                        local head = char:FindFirstChild("Head")
                        if head then origin = head.Position else
                            local hrp = char:FindFirstChild("HumanoidRootPart")
                            if hrp then origin = hrp.Position end
                        end
                    end
                end
                local visiblePoint = GetVisiblePointOnPart(origin, targetPart)
                local wasVisible = visiblePoint ~= nil
                if not visiblePoint and Aimbot.Settings.AutoShoot.StrictWallCheck then return end
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
                PerformSilentShot(targetPart, shootBtn, wasVisible)
                LastShotTime = nowt
            end, HandleError)
        end
    end
    coroutine.wrap(ProcessAutoShoot)()
end

LoadAimbot()
