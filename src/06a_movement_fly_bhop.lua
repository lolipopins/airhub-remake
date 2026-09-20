--// AirHub - 06a_movement_fly_bhop.lua
--// Fly + Bhop + Spider.

local H = getgenv().AirHub
if not H or not H._CoreLoaded then warn("[AirHub] 06a: core not loaded"); return end

local Util = H.Util
local RunService = Util.RunService
local UserInputService = Util.UserInputService
local LocalPlayer = Util.LocalPlayer
local Track = Util.Track
local HandleError = Util.HandleError
local SafeKeyCode = Util.SafeKeyCode
local RAY_FILTER = Util.RAY_FILTER

H.Fly = {
    Settings = {
        Enabled = false, ToggleKey = "F", Toggle = false,
        Method = "BodyVelocity", Speed = 30, UpSpeed = 20,
        Smoothness = 0.5, UseKeys = true,
    },
    Internal = {
        BodyVelocity = nil, LinearVelocity = nil, Attachment = nil,
        Active = false, LastUpdate = 0,
    },
}
local Fly = H.Fly

local function Fly_ClearInstances()
    if Fly.Internal.BodyVelocity then
        pcall(function() Fly.Internal.BodyVelocity:Destroy() end)
        Fly.Internal.BodyVelocity = nil
    end
    if Fly.Internal.LinearVelocity then
        pcall(function() Fly.Internal.LinearVelocity:Destroy() end)
        Fly.Internal.LinearVelocity = nil
    end
    if Fly.Internal.Attachment then
        pcall(function() Fly.Internal.Attachment:Destroy() end)
        Fly.Internal.Attachment = nil
    end
end

local function Fly_GetHRP()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

local function Fly_EnsureInstance(hrp)
    local method = Fly.Settings.Method
    if method == "BodyVelocity" then
        if Fly.Internal.LinearVelocity or Fly.Internal.Attachment then Fly_ClearInstances() end
        if not Fly.Internal.BodyVelocity or not Fly.Internal.BodyVelocity.Parent then
            local bv = Instance.new("BodyVelocity")
            bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            bv.Velocity = Vector3.new(0, 0, 0)
            bv.Parent = hrp
            Fly.Internal.BodyVelocity = bv
        end
    elseif method == "LinearVelocity" then
        if Fly.Internal.BodyVelocity then Fly_ClearInstances() end
        if not Fly.Internal.Attachment or not Fly.Internal.Attachment.Parent then
            local att = Instance.new("Attachment")
            att.Parent = hrp
            Fly.Internal.Attachment = att
            Fly.Internal.LinearVelocity = nil
        end
        if not Fly.Internal.LinearVelocity or not Fly.Internal.LinearVelocity.Parent then
            local lv = Instance.new("LinearVelocity")
            lv.MaxForce = 9e9
            --// FIXED: removed invalid `lv.VectorVectorVelocity` assignment
            lv.VectorVelocity = Vector3.new(0, 0, 0)
            lv.Attachment0 = Fly.Internal.Attachment
            lv.Parent = hrp
            Fly.Internal.LinearVelocity = lv
        end
    else
        Fly_ClearInstances()
    end
end

local function Fly_GetMoveDir()
    local moveDir = Vector3.new(0, 0, 0)
    if not Fly.Settings.UseKeys then return moveDir end
    local forward = workspace.CurrentCamera.CFrame.LookVector
    local right = workspace.CurrentCamera.CFrame.RightVector
    local up = Vector3.new(0, 1, 0)
    local forwardFlat = Vector3.new(forward.X, 0, forward.Z)
    local rightFlat = Vector3.new(right.X, 0, right.Z)
    if forwardFlat.Magnitude > 0.001 then forwardFlat = forwardFlat.Unit end
    if rightFlat.Magnitude > 0.001 then rightFlat = rightFlat.Unit end
    local w = UserInputService:IsKeyDown(Enum.KeyCode.W)
    local s = UserInputService:IsKeyDown(Enum.KeyCode.S)
    local a = UserInputService:IsKeyDown(Enum.KeyCode.A)
    local d = UserInputService:IsKeyDown(Enum.KeyCode.D)
    local sp = UserInputService:IsKeyDown(Enum.KeyCode.Space)
    local ct = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
    if w then moveDir = moveDir + forwardFlat end
    if s then moveDir = moveDir - forwardFlat end
    if a then moveDir = moveDir - rightFlat end
    if d then moveDir = moveDir + rightFlat end
    if sp then moveDir = moveDir + up end
    if ct then moveDir = moveDir - up end
    if moveDir.Magnitude > 0 then moveDir = moveDir.Unit end
    return moveDir
end

local function Fly_Update()
    if H.ShuttingDown then return end
    local S = Fly.Settings
    local I = Fly.Internal
    if not S.Enabled or not I.Active then
        if I.BodyVelocity or I.LinearVelocity or I.Attachment then Fly_ClearInstances() end
        if I.Active and not S.Enabled then I.Active = false end
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum and hum.PlatformStand then hum.PlatformStand = false end
        end
        return
    end
    local hrp = Fly_GetHRP()
    if not hrp then
        Fly_ClearInstances()
        return
    end
    Fly_EnsureInstance(hrp)
    local moveDir = Fly_GetMoveDir()
    local targetVel
    if moveDir.Y ~= 0 then
        targetVel = Vector3.new(moveDir.X * S.Speed, moveDir.Y * S.UpSpeed, moveDir.Z * S.Speed)
    else
        targetVel = Vector3.new(moveDir.X * S.Speed, 0, moveDir.Z * S.Speed)
    end
    local now = tick()
    local dt = now - I.LastUpdate
    if dt <= 0 or dt > 0.5 then dt = 1 / 60 end
    I.LastUpdate = now
    if S.Method == "BodyVelocity" then
        if I.BodyVelocity then
            I.BodyVelocity.Velocity = I.BodyVelocity.Velocity:Lerp(targetVel, math.clamp(S.Smoothness, 0.01, 1))
        end
    elseif S.Method == "LinearVelocity" then
        if I.LinearVelocity then
            I.LinearVelocity.VectorVelocity = I.LinearVelocity.VectorVelocity:Lerp(targetVel, math.clamp(S.Smoothness, 0.01, 1))
        end
    elseif S.Method == "Velocity" then
        hrp.Velocity = targetVel
    elseif S.Method == "CFrame" then
        hrp.CFrame = hrp.CFrame + (moveDir * S.Speed * dt)
    end
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum.PlatformStand = true end
end

Track(RunService.RenderStepped:Connect(function() xpcall(Fly_Update, HandleError) end))

Track(UserInputService.InputBegan:Connect(function(inp, gpe)
    if gpe then return end
    if UserInputService:GetFocusedTextBox() then return end
    if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if not Fly.Settings.Enabled then return end
    local kc = SafeKeyCode(Fly.Settings.ToggleKey)
    if not kc or inp.KeyCode ~= kc then return end
    if Fly.Settings.Toggle then
        Fly.Internal.Active = not Fly.Internal.Active
        if not Fly.Internal.Active then
            Fly_ClearInstances()
            local char = LocalPlayer.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then hum.PlatformStand = false end
            end
        end
    else
        Fly.Internal.Active = true
    end
end))

Track(UserInputService.InputEnded:Connect(function(inp)
    if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
    local kc = SafeKeyCode(Fly.Settings.ToggleKey)
    if not kc or inp.KeyCode ~= kc then return end
    if not Fly.Settings.Toggle then
        Fly.Internal.Active = false
        Fly_ClearInstances()
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then hum.PlatformStand = false end
        end
    end
end))

Track(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.3)
    if H.ShuttingDown then return end
    Fly_ClearInstances()
    Fly.Internal.Active = false
    Fly.Internal.LastUpdate = 0
end))

Fly.Functions = {
    ResetSettings = function()
        Fly.Settings = {
            Enabled = false, ToggleKey = "F", Toggle = false, Method = "BodyVelocity",
            Speed = 30, UpSpeed = 20, Smoothness = 0.5, UseKeys = true,
        }
        Fly_ClearInstances()
        Fly.Internal.Active = false
        Fly.Internal.LastUpdate = 0
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then hum.PlatformStand = false end
        end
    end,
}
Fly.ClearInstances = Fly_ClearInstances

H.Bhop = {
    Settings = {
        Enabled = false,
        AutoJumpKey = "Space",
        BypassJump = true,
        JumpCooldown = 0.1,
        Spider = { Enabled = false, Range = 2.5, RayCount = 8 },
    },
    Internal = {
        KeyHeld = false, LastJumpTime = 0, Active = false,
        SpiderTouching = false, WallNormal = nil,
    },
}
local Bhop = H.Bhop

Track(UserInputService.InputBegan:Connect(function(inp, gpe)
    if gpe then return end
    if UserInputService:GetFocusedTextBox() then return end
    if not Bhop.Settings.Enabled then return end
    local kc = SafeKeyCode(Bhop.Settings.AutoJumpKey)
    if inp.UserInputType == Enum.UserInputType.Keyboard and kc and inp.KeyCode == kc then
        Bhop.Internal.KeyHeld = true
    end
end))

Track(UserInputService.InputEnded:Connect(function(inp)
    local kc = SafeKeyCode(Bhop.Settings.AutoJumpKey)
    if inp.UserInputType == Enum.UserInputType.Keyboard and kc and inp.KeyCode == kc then
        Bhop.Internal.KeyHeld = false
    end
end))

Track(LocalPlayer.CharacterAdded:Connect(function()
    Bhop.Internal.KeyHeld = false
    Bhop.Internal.Active = false
    Bhop.Internal.SpiderTouching = false
end))

local function Spider_DetectWall(char, hrp)
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = { char }
    rayParams.FilterType = RAY_FILTER
    rayParams.IgnoreWater = true
    local range = Bhop.Settings.Spider.Range
    local rayCount = math.max(4, Bhop.Settings.Spider.RayCount or 8)
    local step = (math.pi * 2) / rayCount
    local heights = { -1.2, 0, 1.2 }
    for _, hOffset in ipairs(heights) do
        local origin = hrp.Position + Vector3.new(0, hOffset, 0)
        for i = 0, rayCount - 1 do
            local angle = i * step
            local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
            local result = workspace:Raycast(origin, dir * range, rayParams)
            if result and result.Instance and result.Instance.CanCollide then
                Bhop.Internal.WallNormal = result.Normal
                return true
            end
        end
    end
    Bhop.Internal.WallNormal = nil
    return false
end

task.spawn(function()
    while not H.ShuttingDown and task.wait(0.01) do
        if not Bhop.Settings.Enabled then
            Bhop.Internal.Active = false
            Bhop.Internal.SpiderTouching = false
            continue
        end
        local char = LocalPlayer.Character
        if not char then continue end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hum or not hrp then continue end
        Bhop.Internal.Active = true
        Bhop.Internal.SpiderTouching = false
        if Bhop.Settings.Spider.Enabled then
            Bhop.Internal.SpiderTouching = Spider_DetectWall(char, hrp)
        end
        if Bhop.Internal.KeyHeld then
            local now = tick()
            if now - Bhop.Internal.LastJumpTime >= Bhop.Settings.JumpCooldown then
                local bypass = Bhop.Settings.BypassJump
                if Bhop.Internal.SpiderTouching then bypass = true end
                if bypass then
                    hum:ChangeState(Enum.HumanoidStateType.Jumping)
                    Bhop.Internal.LastJumpTime = now
                else
                    if hum.FloorMaterial ~= Enum.Material.Air then
                        hum:ChangeState(Enum.HumanoidStateType.Jumping)
                        Bhop.Internal.LastJumpTime = now
                    end
                end
            end
        end
    end
end)

Bhop.Functions = {
    ResetSettings = function()
        Bhop.Settings = {
            Enabled = false, AutoJumpKey = "Space", BypassJump = true, JumpCooldown = 0.1,
            Spider = { Enabled = false, Range = 2.5, RayCount = 8 },
        }
        Bhop.Internal = {
            KeyHeld = false, LastJumpTime = 0, Active = false,
            SpiderTouching = false, WallNormal = nil,
        }
    end,
}
