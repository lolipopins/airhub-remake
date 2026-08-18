-- Movement.lua – Fly, Speed (BunnyHop), BackTeleport, DashTeleport, ThirdPerson
-- Fly
local Fly = {
    Settings = {Enabled = false, ToggleKey = "F", Speed = 30, UpSpeed = 20, Smoothness = 0.5, UseKeys = true},
    Internal = {BodyVelocity = nil, Active = false}
}
getgenv().AirHub.Fly = Fly
local function CreateFlyBody()
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    if not Fly.Internal.BodyVelocity then
        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(4000,4000,4000)
        bv.Velocity = Vector3.new(0,0,0)
        bv.Parent = hrp
        Fly.Internal.BodyVelocity = bv
    end
    Fly.Internal.Active = true
end
local function RemoveFlyBody()
    if Fly.Internal.BodyVelocity then Fly.Internal.BodyVelocity:Destroy(); Fly.Internal.BodyVelocity = nil end
    Fly.Internal.Active = false
end
local function UpdateFly()
    if not Fly.Settings.Enabled then
        if Fly.Internal.Active then RemoveFlyBody() end
        return
    end
    local char = LocalPlayer.Character
    if not char then if Fly.Internal.Active then RemoveFlyBody() end return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then if Fly.Internal.Active then RemoveFlyBody() end return end
    if not Fly.Internal.BodyVelocity then CreateFlyBody() end
    local moveDir = Vector3.new(0,0,0)
    if Fly.Settings.UseKeys then
        local forward = Camera.CFrame.LookVector
        local right = Camera.CFrame.RightVector
        local up = Vector3.new(0,1,0)
        local forwardFlat = Vector3.new(forward.X,0,forward.Z).Unit
        local rightFlat = Vector3.new(right.X,0,right.Z).Unit
        local w = UserInputService:IsKeyDown(Enum.KeyCode.W)
        local s = UserInputService:IsKeyDown(Enum.KeyCode.S)
        local a = UserInputService:IsKeyDown(Enum.KeyCode.A)
        local d = UserInputService:IsKeyDown(Enum.KeyCode.D)
        local space = UserInputService:IsKeyDown(Enum.KeyCode.Space)
        local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
        if w then moveDir = moveDir + forwardFlat end
        if s then moveDir = moveDir - forwardFlat end
        if a then moveDir = moveDir - rightFlat end
        if d then moveDir = moveDir + rightFlat end
        if space then moveDir = moveDir + up end
        if ctrl then moveDir = moveDir - up end
    end
    if moveDir.Magnitude > 0 then moveDir = moveDir.Unit end
    local targetVel = moveDir * Fly.Settings.Speed
    if moveDir.Y ~= 0 then targetVel = Vector3.new(targetVel.X, moveDir.Y * Fly.Settings.UpSpeed, targetVel.Z)
    else targetVel = Vector3.new(targetVel.X,0,targetVel.Z) end
    local currentVel = Fly.Internal.BodyVelocity.Velocity
    local newVel = currentVel:Lerp(targetVel, Fly.Settings.Smoothness)
    Fly.Internal.BodyVelocity.Velocity = newVel
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then hum.PlatformStand = true end
end
RunService.RenderStepped:Connect(function() xpcall(UpdateFly, HandleError) end)
UserInputService.InputBegan:Connect(function(inp)
    if Typing then return end
    if inp.UserInputType == Enum.UserInputType.Keyboard and inp.KeyCode == Enum.KeyCode[Fly.Settings.ToggleKey] then
        Fly.Settings.Enabled = not Fly.Settings.Enabled
        ShowError("Fly: " .. (Fly.Settings.Enabled and "ON" or "OFF"))
        if not Fly.Settings.Enabled and Fly.Internal.Active then
            RemoveFlyBody()
            local char = LocalPlayer.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then hum.PlatformStand = false end
            end
        end
    end
end)
Fly.Functions = {
    ResetSettings = function()
        Fly.Settings = {Enabled = false, ToggleKey = "F", Speed = 30, UpSpeed = 20, Smoothness = 0.5, UseKeys = true}
        if Fly.Internal.Active then RemoveFlyBody() end
    end
}

-- Speed (BunnyHop)
local BHop = {
    Settings = {Enabled = false, Mode = "Auto", Key = "Space", SpeedMultiplier = 1.0},
    Internal = {KeyHeld = false, LastJumpTime = 0, Active = false, WasGrounded = false, OriginalWalkSpeed = 16}
}
getgenv().AirHub.BunnyHop = BHop
local function IsGrounded(character)
    if not character then return false end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local hum = character:FindFirstChildOfClass("Humanoid")
    if hum and hum.FloorMaterial ~= Enum.Material.Air then return true end
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {character}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local ray = workspace:Raycast(hrp.Position, Vector3.new(0,-2.2,0), params)
    return ray ~= nil
end
local function BHopLoop()
    while task.wait(0.033) do
        if not BHop.Settings.Enabled then
            if BHop.Internal.Active then
                BHop.Internal.Active = false
                local char = LocalPlayer.Character
                if char then
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum and hum.WalkSpeed ~= BHop.Internal.OriginalWalkSpeed then hum.WalkSpeed = BHop.Internal.OriginalWalkSpeed end
                end
            end
            continue
        end
        local char = LocalPlayer.Character
        if not char then continue end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum then continue end
        if BHop.Internal.OriginalWalkSpeed == 16 and hum.WalkSpeed ~= 16 then BHop.Internal.OriginalWalkSpeed = hum.WalkSpeed end
        local grounded = IsGrounded(char)
        local now = tick()
        local keyHeld = BHop.Internal.KeyHeld
        local mult = BHop.Settings.SpeedMultiplier
        local targetSpeed = BHop.Internal.OriginalWalkSpeed * mult
        if hum.WalkSpeed ~= targetSpeed and mult ~= 1 then hum.WalkSpeed = targetSpeed end
        local shouldJump = false
        if BHop.Settings.Mode == "Auto" or BHop.Settings.Mode == "Hold" then
            shouldJump = keyHeld and grounded and (now - BHop.Internal.LastJumpTime >= (0.05 + math.random() * 0.07))
        end
        if shouldJump and math.random() < 0.08 then shouldJump = false end
        if shouldJump and hum:GetState() ~= Enum.HumanoidStateType.Jumping then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
            BHop.Internal.LastJumpTime = now
        end
        BHop.Internal.WasGrounded = grounded
        BHop.Internal.Active = true
    end
end
UserInputService.InputBegan:Connect(function(inp)
    if Typing then return end
    if inp.UserInputType == Enum.UserInputType.Keyboard and inp.KeyCode == Enum.KeyCode[BHop.Settings.Key] then BHop.Internal.KeyHeld = true end
end)
UserInputService.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.Keyboard and inp.KeyCode == Enum.KeyCode[BHop.Settings.Key] then BHop.Internal.KeyHeld = false end
end)
coroutine.wrap(BHopLoop)()
BHop.Functions = {
    ResetSettings = function()
        BHop.Settings = {Enabled = false, Mode = "Auto", Key = "Space", SpeedMultiplier = 1.0}
        BHop.Internal = {KeyHeld = false, LastJumpTime = 0, Active = false, WasGrounded = false, OriginalWalkSpeed = 16}
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum and hum.WalkSpeed ~= 16 then hum.WalkSpeed = 16 end
        end
    end
}

-- BackTeleport
local BackTeleport = {
    Settings = {Enabled = false, Hotkey = "T", Distance = 4, HeightOffset = 1, AutoAim = true, Mode = "Single", StickInterval = 0.1},
    Internal = {Active = false, Coroutine = nil}
}
getgenv().AirHub.BackTeleport = BackTeleport
local function PerformBackTeleport(target)
    if not target or not target.Character then return false end
    local root = target.Character:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local behind = root.Position - root.CFrame.LookVector * BackTeleport.Settings.Distance
    behind = behind + Vector3.new(0, BackTeleport.Settings.HeightOffset, 0)
    hrp.CFrame = CFrame.new(behind, root.Position)
    if BackTeleport.Settings.AutoAim then
        local head = target.Character:FindFirstChild("Head")
        if head then Camera.CFrame = CFrame.new(Camera.CFrame.Position, head.Position) end
    end
    return true
end
local function GetTarget()
    if getgenv().AirHub.Aimbot and getgenv().AirHub.Aimbot.Locked and getgenv().AirHub.Aimbot.Locked.Character then
        return getgenv().AirHub.Aimbot.Locked
    end
    local bestDist = math.huge
    local bestTarget = nil
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
            if (function() -- проверка IsTargetValid из Aimbot (если доступен)
                if not getgenv().AirHub.Aimbot then return true end
                local settings = getgenv().AirHub.Aimbot.Settings
                if settings.AliveCheck then
                    local hum = plr.Character:FindFirstChildOfClass("Humanoid")
                    if not hum or hum.Health <= 0 then return false end
                end
                local tc = settings.TeamCheck
                if not tc.Enabled then return true end
                local lt, tt = LocalPlayer.Team, plr.Team
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
            end)() then
                local dist = (plr.Character.HumanoidRootPart.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude
                if dist < bestDist then bestDist = dist; bestTarget = plr end
            end
        end
    end
    return bestTarget
end
local function StickLoop()
    while BackTeleport.Internal.Active do
        local target = GetTarget()
        if target then PerformBackTeleport(target) end
        task.wait(BackTeleport.Settings.StickInterval)
    end
end
UserInputService.InputBegan:Connect(function(inp)
    if Typing then return end
    if not BackTeleport.Settings.Enabled then return end
    if inp.UserInputType == Enum.UserInputType.Keyboard and inp.KeyCode == Enum.KeyCode[BackTeleport.Settings.Hotkey] then
        if BackTeleport.Settings.Mode == "Single" then
            local target = GetTarget()
            if target then PerformBackTeleport(target) else ShowError("No target found") end
        elseif BackTeleport.Settings.Mode == "Stick" then
            BackTeleport.Internal.Active = not BackTeleport.Internal.Active
            ShowError("Stick mode " .. (BackTeleport.Internal.Active and "ON" or "OFF"))
            if BackTeleport.Internal.Active then
                BackTeleport.Internal.Coroutine = coroutine.wrap(StickLoop)
                BackTeleport.Internal.Coroutine()
            end
        end
    end
end)
BackTeleport.Functions = {
    ResetSettings = function()
        BackTeleport.Settings = {Enabled = false, Hotkey = "T", Distance = 4, HeightOffset = 1, AutoAim = true, Mode = "Single", StickInterval = 0.1}
        BackTeleport.Internal.Active = false
        BackTeleport.Internal.Coroutine = nil
    end
}

-- DashTeleport
local DashTeleport = {
    Settings = {Enabled = false, Key = "Q", Distance = 10, HeightOffset = 0, Direction = "Camera"}
}
getgenv().AirHub.DashTeleport = DashTeleport
UserInputService.InputBegan:Connect(function(inp)
    if Typing then return end
    if not DashTeleport.Settings.Enabled then return end
    if inp.UserInputType == Enum.UserInputType.Keyboard and inp.KeyCode == Enum.KeyCode[DashTeleport.Settings.Key] then
        local char = LocalPlayer.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local dir = Vector3.new(0,0,0)
        local mode = DashTeleport.Settings.Direction
        if mode == "Camera" then dir = Camera.CFrame.LookVector
        elseif mode == "Player" then dir = hrp.CFrame.LookVector
        elseif mode == "Movement" then
            local vel = hrp.Velocity
            if vel.Magnitude > 0.5 then dir = vel.Unit else dir = Camera.CFrame.LookVector end
        end
        local newPos = hrp.Position + dir * DashTeleport.Settings.Distance
        newPos = newPos + Vector3.new(0, DashTeleport.Settings.HeightOffset, 0)
        hrp.CFrame = CFrame.new(newPos)
    end
end)
DashTeleport.Functions = {
    ResetSettings = function()
        DashTeleport.Settings = {Enabled = false, Key = "Q", Distance = 10, HeightOffset = 0, Direction = "Camera"}
    end
}

-- ThirdPerson
local ThirdPerson = {
    Settings = {Enabled = false, ToggleKey = "V", Distance = 8, Height = 2, Sensitivity = 0.5, InvertY = false, LockCursor = true, Smoothness = 0.1},
    Internal = {Active = false, Yaw = 0, Pitch = -20, TargetYaw = 0, TargetPitch = -20, LastMousePos = nil, IsRotating = false, OriginalCameraType = Enum.CameraType.Custom}
}
getgenv().AirHub.ThirdPerson = ThirdPerson
local function UpdateThirdPerson()
    if not ThirdPerson.Settings.Enabled then
        if ThirdPerson.Internal.Active then
            Camera.CameraType = ThirdPerson.Internal.OriginalCameraType
            ThirdPerson.Internal.Active = false
        end
        return
    end
    local char = LocalPlayer.Character
    if not char then
        if ThirdPerson.Internal.Active then Camera.CameraType = ThirdPerson.Internal.OriginalCameraType; ThirdPerson.Internal.Active = false end
        return
    end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        if ThirdPerson.Internal.Active then Camera.CameraType = ThirdPerson.Internal.OriginalCameraType; ThirdPerson.Internal.Active = false end
        return
    end
    if not ThirdPerson.Internal.Active then
        ThirdPerson.Internal.OriginalCameraType = Camera.CameraType
        Camera.CameraType = Enum.CameraType.Scriptable
        ThirdPerson.Internal.Active = true
    end
    local smooth = ThirdPerson.Settings.Smoothness
    if smooth > 0 then
        ThirdPerson.Internal.Yaw = ThirdPerson.Internal.Yaw + (ThirdPerson.Internal.TargetYaw - ThirdPerson.Internal.Yaw) * math.min(1, smooth * 2)
        ThirdPerson.Internal.Pitch = ThirdPerson.Internal.Pitch + (ThirdPerson.Internal.TargetPitch - ThirdPerson.Internal.Pitch) * math.min(1, smooth * 2)
    else
        ThirdPerson.Internal.Yaw = ThirdPerson.Internal.TargetYaw
        ThirdPerson.Internal.Pitch = ThirdPerson.Internal.TargetPitch
    end
    ThirdPerson.Internal.Pitch = math.clamp(ThirdPerson.Internal.Pitch, -80, 80)
    local dist = ThirdPerson.Settings.Distance
    local height = ThirdPerson.Settings.Height
    local pitchRad = math.rad(ThirdPerson.Internal.Pitch)
    local yawRad = math.rad(ThirdPerson.Internal.Yaw)
    local offset = Vector3.new(math.sin(yawRad)*math.cos(pitchRad)*dist, math.sin(pitchRad)*dist + height, -math.cos(yawRad)*math.cos(pitchRad)*dist)
    local targetPos = hrp.Position + offset
    local lookAt = hrp.Position + Vector3.new(0, height, 0)
    Camera.CFrame = CFrame.new(targetPos, lookAt)
end
UserInputService.InputBegan:Connect(function(inp)
    if Typing then return end
    if not ThirdPerson.Settings.Enabled then return end
    if inp.UserInputType == Enum.UserInputType.MouseButton2 then
        ThirdPerson.Internal.IsRotating = true
        ThirdPerson.Internal.LastMousePos = UserInputService:GetMouseLocation()
        if ThirdPerson.Settings.LockCursor then UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition end
    elseif inp.UserInputType == Enum.UserInputType.MouseWheel then
        local zoom = inp.Position.Z
        ThirdPerson.Settings.Distance = math.clamp(ThirdPerson.Settings.Distance - zoom, 1, 30)
    elseif inp.UserInputType == Enum.UserInputType.Keyboard and inp.KeyCode == Enum.KeyCode[ThirdPerson.Settings.ToggleKey] then
        ThirdPerson.Settings.Enabled = not ThirdPerson.Settings.Enabled
        ShowError("Third Person: " .. (ThirdPerson.Settings.Enabled and "ON" or "OFF"))
        if not ThirdPerson.Settings.Enabled then
            if ThirdPerson.Internal.Active then Camera.CameraType = ThirdPerson.Internal.OriginalCameraType; ThirdPerson.Internal.Active = false end
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        end
    end
end)
UserInputService.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton2 then
        ThirdPerson.Internal.IsRotating = false
        if ThirdPerson.Settings.LockCursor then UserInputService.MouseBehavior = Enum.MouseBehavior.Default end
    end
end)
UserInputService.InputChanged:Connect(function(inp)
    if not ThirdPerson.Settings.Enabled or not ThirdPerson.Internal.IsRotating then return end
    if inp.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    local delta = inp.Delta
    local sens = ThirdPerson.Settings.Sensitivity
    local invert = ThirdPerson.Settings.InvertY and -1 or 1
    ThirdPerson.Internal.TargetYaw = ThirdPerson.Internal.TargetYaw + delta.X * sens * 0.5
    ThirdPerson.Internal.TargetPitch = ThirdPerson.Internal.TargetPitch + delta.Y * sens * 0.5 * invert
end)
RunService.RenderStepped:Connect(function() xpcall(UpdateThirdPerson, HandleError) end)
ThirdPerson.Functions = {
    ResetSettings = function()
        ThirdPerson.Settings = {Enabled = false, ToggleKey = "V", Distance = 8, Height = 2, Sensitivity = 0.5, InvertY = false, LockCursor = true, Smoothness = 0.1}
        ThirdPerson.Internal = {Active = false, Yaw = 0, Pitch = -20, TargetYaw = 0, TargetPitch = -20, LastMousePos = nil, IsRotating = false, OriginalCameraType = Enum.CameraType.Custom}
        if Camera.CameraType ~= Enum.CameraType.Custom then Camera.CameraType = Enum.CameraType.Custom end
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    end
}
