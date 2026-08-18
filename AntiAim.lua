-- AntiAim.lua – управление телом и головой (горизонтальный референс)
local AntiAim = {
    Settings = {
        Enabled = false, Mode = "Static",
        Body = {Reference = "Camera", Yaw = 0, Pitch = 0, Roll = 0, SpinSpeed = 0, JitterAmount = 5, JitterSpeed = 10, IgnoreMoving = false, MoveSpeedThreshold = 0.5},
        Head = {Enabled = false, Yaw = 0, Pitch = 0, Roll = 0},
        Smoothness = 10
    },
    Internal = {BodyCurrentCF = nil, BodyLastUpdate = 0, BodyJitterTime = 0, BodyJitterOffset = {0,0,0}, NeckMotor = nil, OriginalC0 = nil}
}
getgenv().AirHub.AntiAim = AntiAim

local function GetBaseAngles(reference, char)
    if reference == "Camera" then
        local look = Camera.CFrame.LookVector
        local flat = Vector3.new(look.X, 0, look.Z)
        if flat.Magnitude > 0.001 then return math.atan2(flat.X, flat.Z), 0 else return 0,0 end
    elseif reference == "Movement" then
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local vel = hrp.Velocity
            local horizontal = Vector3.new(vel.X, 0, vel.Z)
            if horizontal.Magnitude > 0.5 then return math.atan2(horizontal.X, horizontal.Z), 0 end
        end
        local look = Camera.CFrame.LookVector
        local flat = Vector3.new(look.X, 0, look.Z)
        if flat.Magnitude > 0.001 then return math.atan2(flat.X, flat.Z), 0 else return 0,0 end
    elseif reference == "Player" then
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local look = hrp.CFrame.LookVector
            local flat = Vector3.new(look.X, 0, look.Z)
            if flat.Magnitude > 0.001 then return math.atan2(flat.X, flat.Z), math.atan2(look.Y, flat.Magnitude) end
        end
        return 0,0
    end
    return 0,0
end

local function ApplyAntiAim()
    if not AntiAim.Settings.Enabled then
        if AntiAim.Internal.NeckMotor and AntiAim.Internal.OriginalC0 then
            AntiAim.Internal.NeckMotor.C0 = AntiAim.Internal.OriginalC0
            AntiAim.Internal.NeckMotor = nil
            AntiAim.Internal.OriginalC0 = nil
        end
        return
    end
    local char = LocalPlayer.Character
    if not char then return end
    local now = tick()
    local dt = math.min(0.033, now - AntiAim.Internal.BodyLastUpdate)
    AntiAim.Internal.BodyLastUpdate = now
    if AntiAim.Settings.Head.Enabled then
        local neck = char:FindFirstChild("Neck")
        if not neck or not neck:IsA("Motor6D") then
            for _, v in pairs(char:GetDescendants()) do
                if v:IsA("Motor6D") and v.Name:lower():find("neck") then neck = v; break end
            end
        end
        if neck then
            if not AntiAim.Internal.OriginalC0 then AntiAim.Internal.OriginalC0 = neck.C0 end
            AntiAim.Internal.NeckMotor = neck
            local headSet = AntiAim.Settings.Head
            neck.C0 = AntiAim.Internal.OriginalC0 * CFrame.Angles(math.rad(headSet.Pitch), math.rad(headSet.Yaw), math.rad(headSet.Roll))
        end
    else
        if AntiAim.Internal.NeckMotor and AntiAim.Internal.OriginalC0 then
            AntiAim.Internal.NeckMotor.C0 = AntiAim.Internal.OriginalC0
            AntiAim.Internal.NeckMotor = nil
            AntiAim.Internal.OriginalC0 = nil
        end
    end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local bodySet = AntiAim.Settings.Body
    local mode = AntiAim.Settings.Mode
    local shouldApply = true
    if bodySet.IgnoreMoving then
        local vel = root.Velocity
        if vel.Magnitude > bodySet.MoveSpeedThreshold then shouldApply = false; AntiAim.Internal.BodyCurrentCF = nil end
    end
    if shouldApply then
        local baseYaw, basePitch = GetBaseAngles(bodySet.Reference, char)
        local yaw, pitch, roll = 0,0,0
        if mode == "Static" then
            yaw = baseYaw + math.rad(bodySet.Yaw)
            pitch = basePitch + math.rad(bodySet.Pitch)
            roll = math.rad(bodySet.Roll)
        elseif mode == "Spin" then
            local angle = (now * bodySet.SpinSpeed) % 360
            yaw = baseYaw + math.rad(angle + bodySet.Yaw)
            pitch = basePitch + math.rad(bodySet.Pitch)
            roll = math.rad(bodySet.Roll)
        elseif mode == "Jitter" then
            if now - AntiAim.Internal.BodyJitterTime > 1 / bodySet.JitterSpeed then
                AntiAim.Internal.BodyJitterTime = now
                AntiAim.Internal.BodyJitterOffset = { (math.random()-0.5)*2*bodySet.JitterAmount, (math.random()-0.5)*2*bodySet.JitterAmount, (math.random()-0.5)*2*bodySet.JitterAmount }
            end
            yaw = baseYaw + math.rad(bodySet.Yaw + AntiAim.Internal.BodyJitterOffset[1])
            pitch = basePitch + math.rad(bodySet.Pitch + AntiAim.Internal.BodyJitterOffset[2])
            roll = math.rad(bodySet.Roll + AntiAim.Internal.BodyJitterOffset[3])
        elseif mode == "Dynamic" then
            yaw = baseYaw + math.rad(bodySet.Yaw + 45 * math.sin(now * 0.5))
            pitch = basePitch + math.rad(bodySet.Pitch + 30 * math.sin(now * 0.7 + 1))
            roll = math.rad(bodySet.Roll + 20 * math.sin(now * 0.3 + 2))
        end
        local rotation = CFrame.Angles(pitch, yaw, roll)
        local targetCF = CFrame.new(root.Position) * rotation
        local smooth = AntiAim.Settings.Smoothness
        if smooth > 0 and AntiAim.Internal.BodyCurrentCF then
            local factor = 1 - math.exp(-smooth * dt)
            root.CFrame = AntiAim.Internal.BodyCurrentCF:Lerp(targetCF, factor)
            AntiAim.Internal.BodyCurrentCF = root.CFrame
        else
            root.CFrame = targetCF
            AntiAim.Internal.BodyCurrentCF = targetCF
        end
    else
        AntiAim.Internal.BodyCurrentCF = nil
    end
end
RunService.RenderStepped:Connect(function() xpcall(ApplyAntiAim, HandleError) end)

AntiAim.Functions = {
    Exit = function() if AntiAim.Internal.NeckMotor and AntiAim.Internal.OriginalC0 then AntiAim.Internal.NeckMotor.C0 = AntiAim.Internal.OriginalC0 end end,
    ResetSettings = function()
        AntiAim.Settings = {
            Enabled = false, Mode = "Static",
            Body = {Reference = "Camera", Yaw = 0, Pitch = 0, Roll = 0, SpinSpeed = 0, JitterAmount = 5, JitterSpeed = 10, IgnoreMoving = false, MoveSpeedThreshold = 0.5},
            Head = {Enabled = false, Yaw = 0, Pitch = 0, Roll = 0},
            Smoothness = 10
        }
        if AntiAim.Internal.NeckMotor and AntiAim.Internal.OriginalC0 then AntiAim.Internal.NeckMotor.C0 = AntiAim.Internal.OriginalC0 end
        AntiAim.Internal = {BodyCurrentCF = nil, BodyLastUpdate = 0, BodyJitterTime = 0, BodyJitterOffset = {0,0,0}, NeckMotor = nil, OriginalC0 = nil}
    end
}
