--// AirHub - 06b_movement_speed_strafer.lua
--// Speed + FastStop + AutoStrafer + Noclip.

local H = getgenv().AirHub
if not H or not H._CoreLoaded then warn("[AirHub] 06b: core not loaded"); return end

local Util = H.Util
local RunService = Util.RunService
local UserInputService = Util.UserInputService
local VirtualInputManager = Util.VirtualInputManager
local LocalPlayer = Util.LocalPlayer
local Track = Util.Track
local HandleError = Util.HandleError
local SafeKeyCode = Util.SafeKeyCode
local RAY_FILTER = Util.RAY_FILTER

H.Speed = {
    Settings = {
        Enabled = false,
        Method = "WalkSpeed",
        GroundSpeed = 30,
        AirSpeed = 30,
        UseAirSpeed = false,
        InAirOnly = false,
    },
    Internal = { Active = false, OriginalWalkSpeed = 16, LastClock = 0 },
}
local Speed = H.Speed

local function IsGrounded(character)
    if not character then return false end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local hum = character:FindFirstChildOfClass("Humanoid")
    if hum then
        if hum.FloorMaterial ~= Enum.Material.Air then return true end
    end
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = { character }
    params.FilterType = RAY_FILTER
    return workspace:Raycast(hrp.Position, Vector3.new(0, -2.2, 0), params) ~= nil
end

local function GetMoveDirection()
    local char = LocalPlayer.Character
    if not char then return Vector3.new(0, 0, 0) end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return Vector3.new(0, 0, 0) end
    local w = UserInputService:IsKeyDown(Enum.KeyCode.W)
    local s = UserInputService:IsKeyDown(Enum.KeyCode.S)
    local a = UserInputService:IsKeyDown(Enum.KeyCode.A)
    local d = UserInputService:IsKeyDown(Enum.KeyCode.D)
    if not (w or s or a or d) then return Vector3.new(0, 0, 0) end
    local camForward = workspace.CurrentCamera.CFrame.LookVector
    local camRight = workspace.CurrentCamera.CFrame.RightVector
    local forward = Vector3.new(camForward.X, 0, camForward.Z).Unit
    local right = Vector3.new(camRight.X, 0, camRight.Z).Unit
    local dir = Vector3.new(0, 0, 0)
    if w then dir = dir + forward end
    if s then dir = dir - forward end
    if a then dir = dir - right end
    if d then dir = dir + right end
    if dir.Magnitude > 0 then dir = dir.Unit end
    return dir
end

task.spawn(function()
    Speed.Internal.LastClock = os.clock()
    while not H.ShuttingDown and task.wait(0.016) do
        local nowClock = os.clock()
        local dt = nowClock - Speed.Internal.LastClock
        Speed.Internal.LastClock = nowClock
        if dt <= 0 or dt > 0.5 then dt = 0.016 end
        if not Speed.Settings.Enabled then
            if Speed.Internal.Active then
                Speed.Internal.Active = false
                local char = LocalPlayer.Character
                if char then
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum and hum.WalkSpeed ~= Speed.Internal.OriginalWalkSpeed then
                        hum.WalkSpeed = Speed.Internal.OriginalWalkSpeed
                    end
                end
            end
            continue
        end
        local char = LocalPlayer.Character
        if not char then continue end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hum or not hrp then continue end
        if not Speed.Internal.Active then
            Speed.Internal.OriginalWalkSpeed = hum.WalkSpeed
            Speed.Internal.Active = true
        end
        local method = Speed.Settings.Method
        local grounded = IsGrounded(char)
        local spd
        if Speed.Settings.UseAirSpeed and not grounded then
            spd = Speed.Settings.AirSpeed
        else
            spd = Speed.Settings.GroundSpeed
        end
        if Speed.Settings.InAirOnly then
            if grounded then
                if method == "WalkSpeed" and hum.WalkSpeed ~= Speed.Internal.OriginalWalkSpeed then
                    hum.WalkSpeed = Speed.Internal.OriginalWalkSpeed
                end
                continue
            end
        end
        if method == "WalkSpeed" then
            if hum.WalkSpeed ~= spd then hum.WalkSpeed = spd end
        elseif method == "CFrame" then
            local dir = GetMoveDirection()
            if dir.Magnitude > 0 then hrp.CFrame = hrp.CFrame + dir * spd * dt end
        elseif method == "Velocity" then
            local dir = GetMoveDirection()
            if dir.Magnitude > 0 then
                hrp.Velocity = Vector3.new(dir.X * spd, hrp.Velocity.Y, dir.Z * spd)
            end
        end
    end
end)

Speed.Functions = {
    ResetSettings = function()
        Speed.Settings = {
            Enabled = false, Method = "WalkSpeed", GroundSpeed = 30, AirSpeed = 30,
            UseAirSpeed = false, InAirOnly = false,
        }
        Speed.Internal = { Active = false, OriginalWalkSpeed = 16, LastClock = 0 }
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum and hum.WalkSpeed ~= 16 then hum.WalkSpeed = 16 end
        end
    end,
}

H.FastStop = {
    Settings = { Enabled = false, StopY = false },
    Internal = { LastActive = false },
}
local FastStop = H.FastStop

local function FS_AnyMoveHeld()
    return UserInputService:IsKeyDown(Enum.KeyCode.W)
        or UserInputService:IsKeyDown(Enum.KeyCode.A)
        or UserInputService:IsKeyDown(Enum.KeyCode.S)
        or UserInputService:IsKeyDown(Enum.KeyCode.D)
end

task.spawn(function()
    while not H.ShuttingDown and task.wait(0.01) do
        if not FastStop.Settings.Enabled then
            FastStop.Internal.LastActive = false
            continue
        end
        if FS_AnyMoveHeld() then
            FastStop.Internal.LastActive = false
            continue
        end
        local char = LocalPlayer.Character
        if not char then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum then continue end
        if hum.Health <= 0 then continue end
        if FastStop.Settings.StopY then
            hrp.Velocity = Vector3.new(0, 0, 0)
        else
            hrp.Velocity = Vector3.new(0, hrp.Velocity.Y, 0)
        end
        FastStop.Internal.LastActive = true
    end
end)

FastStop.Functions = {
    ResetSettings = function()
        FastStop.Settings = { Enabled = false, StopY = false }
        FastStop.Internal = { LastActive = false }
    end,
}

H.AutoStrafer = {
    Settings = { Enabled = false, Mode = "Legit", Key = "Space", Toggle = false, Invert = false, SpamDelay = 0.05 },
    Internal = { Active = false, LastYaw = nil, KeyA = false, KeyD = false, SpamDir = -1, LastSpam = 0 },
}
local AutoStrafer = H.AutoStrafer

local function AS_IsTyping() return UserInputService:GetFocusedTextBox() ~= nil end
local function AS_GetCameraYaw()
    local look = workspace.CurrentCamera.CFrame.LookVector
    return math.atan2(look.X, look.Z)
end
local function AS_WrapAngle(d)
    while d > math.pi do d = d - math.pi * 2 end
    while d < -math.pi do d = d + math.pi * 2 end
    return d
end

local function AS_PressA()
    if AutoStrafer.Internal.KeyA then return end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then return end
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.A, false, game)
    AutoStrafer.Internal.KeyA = true
end
local function AS_ReleaseA()
    if not AutoStrafer.Internal.KeyA then return end
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.A, false, game)
    AutoStrafer.Internal.KeyA = false
end
local function AS_PressD()
    if AutoStrafer.Internal.KeyD then return end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then return end
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.D, false, game)
    AutoStrafer.Internal.KeyD = true
end
local function AS_ReleaseD()
    if not AutoStrafer.Internal.KeyD then return end
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.D, false, game)
    AutoStrafer.Internal.KeyD = false
end
local function AS_ReleaseAll() AS_ReleaseA(); AS_ReleaseD() end

local function AS_Update()
    if H.ShuttingDown then return end
    local S = AutoStrafer.Settings
    local I = AutoStrafer.Internal
    if not S.Enabled or not I.Active then AS_ReleaseAll() return end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then AS_ReleaseAll() return end
    if S.Mode == "Spam" then
        local now = tick()
        if now - I.LastSpam >= S.SpamDelay then
            I.LastSpam = now
            I.SpamDir = -I.SpamDir
            if I.SpamDir == -1 then
                AS_PressA()
                AS_ReleaseD()
            else
                AS_PressD()
                AS_ReleaseA()
            end
        end
        return
    end
    local yaw = AS_GetCameraYaw()
    if I.LastYaw == nil then I.LastYaw = yaw return end
    local delta = AS_WrapAngle(yaw - I.LastYaw)
    I.LastYaw = yaw
    if delta == 0 then AS_ReleaseAll() return end
    local turningRight = delta > 0
    if S.Invert then turningRight = not turningRight end
    if turningRight then
        AS_PressA()
        AS_ReleaseD()
    else
        AS_PressD()
        AS_ReleaseA()
    end
end

Track(RunService.RenderStepped:Connect(function() xpcall(AS_Update, HandleError) end))

Track(UserInputService.InputBegan:Connect(function(inp, gpe)
    if gpe or AS_IsTyping() then return end
    if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if not AutoStrafer.Settings.Enabled then return end
    local kc = SafeKeyCode(AutoStrafer.Settings.Key)
    if not kc or inp.KeyCode ~= kc then return end
    if AutoStrafer.Settings.Toggle then
        AutoStrafer.Internal.Active = not AutoStrafer.Internal.Active
        if not AutoStrafer.Internal.Active then AS_ReleaseAll() end
    else
        AutoStrafer.Internal.Active = true
    end
end))

Track(UserInputService.InputEnded:Connect(function(inp)
    if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
    local kc = SafeKeyCode(AutoStrafer.Settings.Key)
    if not kc or inp.KeyCode ~= kc then return end
    if not AutoStrafer.Settings.Toggle then
        AutoStrafer.Internal.Active = false
        AS_ReleaseAll()
    end
end))

Track(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    if H.ShuttingDown then return end
    AS_ReleaseAll()
    AutoStrafer.Internal.Active = false
    AutoStrafer.Internal.LastYaw = nil
end))

AutoStrafer.Functions = {
    ResetSettings = function()
        AS_ReleaseAll()
        AutoStrafer.Settings = {
            Enabled = false, Mode = "Legit", Key = "Space", Toggle = false,
            Invert = false, SpamDelay = 0.05,
        }
        AutoStrafer.Internal = {
            Active = false, LastYaw = nil, KeyA = false, KeyD = false,
            SpamDir = -1, LastSpam = 0,
        }
    end,
    Stop = function()
        AutoStrafer.Settings.Enabled = false
        AutoStrafer.Internal.Active = false
        AS_ReleaseAll()
    end,
}
AutoStrafer.ReleaseAll = AS_ReleaseAll

--// ---------------------------------------------------------------------------
--// Noclip
--// FIXED: now snapshots each part's original CanCollide value and restores
--// it correctly (previously all parts were blindly set to CanCollide = true,
--// which broke accessories/decor that were intentionally non-collidable).
--// ---------------------------------------------------------------------------
H.Noclip = {
    Settings = { Enabled = false },
    Internal = { Active = false, Saved = {} },
}
local Noclip = H.Noclip

task.spawn(function()
    while not H.ShuttingDown and task.wait(0.1) do
        if not Noclip.Settings.Enabled then
            if Noclip.Internal.Active then
                Noclip.Internal.Active = false
                for part, orig in pairs(Noclip.Internal.Saved) do
                    if part and part.Parent then
                        pcall(function() part.CanCollide = orig end)
                    end
                end
                Noclip.Internal.Saved = {}
            end
            continue
        end
        Noclip.Internal.Active = true
        local char = LocalPlayer.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    if Noclip.Internal.Saved[part] == nil then
                        Noclip.Internal.Saved[part] = part.CanCollide
                    end
                    if part.CanCollide then part.CanCollide = false end
                end
            end
        end
    end
end)

Track(LocalPlayer.CharacterAdded:Connect(function()
    Noclip.Internal.Saved = {}
    Noclip.Internal.Active = false
end))

Noclip.Functions = {
    ResetSettings = function()
        for part, orig in pairs(Noclip.Internal.Saved) do
            if part and part.Parent then
                pcall(function() part.CanCollide = orig end)
            end
        end
        Noclip.Settings = { Enabled = false }
        Noclip.Internal = { Active = false, Saved = {} }
    end,
}
