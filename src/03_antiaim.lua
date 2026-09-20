--// ============================================================================
--// AirHub — 03_antiaim.lua
--// Anti-Aim (body) + Desync (client-side) + Spoof Animations.
--// Desync modes: Default / OldPosition / Void / InPlayer
--// ============================================================================
local H = getgenv().AirHub
if not H or not H._CoreLoaded then warn("[AirHub] 03_antiaim: core not loaded") return end
if H.AntiAim then warn("[AirHub] AntiAim already loaded") return end

local Util        = H.Util
local Players     = Util.Players
local RunService  = Util.RunService
local LocalPlayer = Util.LocalPlayer
local Track       = Util.Track
local HandleError = Util.HandleError

H.AntiAim = {
    Settings = {
        Enabled = false,
        Mode    = "Static",
        Method  = "CFrame",
        Body = {
            Reference          = "Camera",
            Yaw                = 0,
            Amount             = 15,       -- any number (textbox in UI)
            Speed              = 5,        -- any number (textbox in UI)
            IgnoreMoving       = false,
            MoveSpeedThreshold = 0.5,
        },
    },
    Desync = {
        Settings = {
            Enabled            = false,
            Mode               = "Default",   -- Default / OldPosition / Void / InPlayer
            X                  = 5,
            Y                  = 5,
            Z                  = 5,
            Random             = false,
            UpdateInterval     = 0.05,
            OldPosDelayEnabled = true,        -- NEW
            OldPosDelay        = 0.5,
            VoidDepth          = -1000,
            InPlayerOffset     = 2,
            RefreshOnShot      = false,
            RandomRotate       = false,
        },
        Internal = {
            Connection       = nil,
            RenderBindName   = "AirHubDesyncRestore",
            Acc              = 0,
            CurrentOffset    = Vector3.new(0, 0, 0),
            TargetOffset     = Vector3.new(0, 0, 0),
            SavedCFrame      = nil,
            RealCFrame       = nil,
            RealVelocity     = nil,
            RealRotVelocity  = nil,
            OldPosTimer      = 0,
            PendingRefresh   = false,
            RotAcc           = 0,
            RotPitch         = 0,
            RotYaw           = 0,
            RotRoll          = 0,
        },
    },
    Internal = {
        BodyLastUpdate    = 0,
        BodyJitterTime    = 0,
        BodyJitterOffset  = 0,
        BodyGyro          = nil,
        AlignOrientation  = nil,
        Attachment        = nil,
        AngularVelocity   = nil,
        CurrentMotor      = nil,
        OriginalC0        = nil,
    },
    SpoofAnim = {
        Settings = {
            Enabled      = false,
            AnimationId  = "rbxassetid://0",
            Speed        = 1,
            Looped       = true,
            StopOnMove   = false,
            Priority     = "Action",
        },
        Internal = {
            Track   = nil,
            Anim    = nil,
            LoadedId = nil,
            Conn    = nil,
        },
        Functions = {},
    },
}
local AntiAim = H.AntiAim

--// ---------------------------------------------------------------------------
--// Helpers
--// ---------------------------------------------------------------------------
local function GetBaseYaw(reference, char)
    if reference == "Camera" then
        local look = workspace.CurrentCamera.CFrame.LookVector
        local flat = Vector3.new(look.X, 0, look.Z)
        if flat.Magnitude > 0.001 then return math.atan2(flat.X, flat.Z) else return 0 end
    elseif reference == "Movement" then
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local vel = hrp.Velocity
            local horizontal = Vector3.new(vel.X, 0, vel.Z)
            if horizontal.Magnitude > 0.5 then return math.atan2(horizontal.X, horizontal.Z) end
        end
        local look = workspace.CurrentCamera.CFrame.LookVector
        local flat = Vector3.new(look.X, 0, look.Z)
        if flat.Magnitude > 0.001 then return math.atan2(flat.X, flat.Z) else return 0 end
    elseif reference == "Player" then
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local look = hrp.CFrame.LookVector
            local flat = Vector3.new(look.X, 0, look.Z)
            if flat.Magnitude > 0.001 then return math.atan2(flat.X, flat.Z) else return 0 end
        end
        return 0
    end
    return 0
end

local function GetCurrentHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function BuildDefaultOffset(settings)
    local X = tonumber(settings.X) or 0
    local Y = tonumber(settings.Y) or 0
    local Z = tonumber(settings.Z) or 0
    if settings.Random then
        local rx = (math.random() * 2 - 1) * X
        local ry = (math.random() * 2 - 1) * Y
        local rz = (math.random() * 2 - 1) * Z
        return Vector3.new(rx, ry, rz)
    end
    return Vector3.new(X, Y, Z)
end

local function GetNearestPlayerHRP(myPos)
    if not myPos then return nil end
    local nearest, nearestDist = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            local hum = plr.Character:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                local d = (hrp.Position - myPos).Magnitude
                if d < nearestDist then
                    nearestDist = d
                    nearest = hrp
                end
            end
        end
    end
    return nearest
end

--// ---------------------------------------------------------------------------
--// Desync
--// ---------------------------------------------------------------------------
local function StartDesync()
    local desync = AntiAim.Desync
    if desync.Internal.Connection then return end

    desync.Internal.Acc             = 0
    desync.Internal.CurrentOffset   = Vector3.new(0, 0, 0)
    desync.Internal.TargetOffset    = Vector3.new(0, 0, 0)
    desync.Internal.PendingRefresh  = false
    desync.Internal.RealCFrame      = nil
    desync.Internal.RealVelocity    = nil
    desync.Internal.RealRotVelocity = nil
    desync.Internal.RotAcc          = 0
    desync.Internal.RotPitch        = 0
    desync.Internal.RotYaw          = 0
    desync.Internal.RotRoll         = 0

    if desync.Settings.Mode == "OldPosition" then
        local hrp = GetCurrentHRP()
        if hrp then desync.Internal.SavedCFrame = hrp.CFrame end
        desync.Internal.OldPosTimer = 0
    end

    desync.Internal.Connection = RunService.Heartbeat:Connect(function(dt)
        if H.ShuttingDown then return end
        local char = LocalPlayer.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local oldcf     = hrp.CFrame
        local oldvel    = hrp.Velocity
        local oldrotvel = hrp.RotVelocity

        desync.Internal.RealCFrame      = oldcf
        desync.Internal.RealVelocity    = oldvel
        desync.Internal.RealRotVelocity = oldrotvel

        local S = desync.Settings
        local mode = S.Mode
        local interval = tonumber(S.UpdateInterval) or 0.05
        if interval < 0.01 then interval = 0.01 end

        local targetCF

        --// ===================== OldPosition =========================
        if mode == "OldPosition" then
            if not desync.Internal.SavedCFrame then
                desync.Internal.SavedCFrame = oldcf
            end

            if desync.Internal.PendingRefresh then
                desync.Internal.PendingRefresh = false
                desync.Internal.SavedCFrame = oldcf
                desync.Internal.OldPosTimer = 0
            end

            --// Only re-capture position if OldPosDelay is enabled
            if S.OldPosDelayEnabled then
                local delay = tonumber(S.OldPosDelay) or 0.5
                if delay < 0.01 then delay = 0.01 end
                desync.Internal.OldPosTimer = desync.Internal.OldPosTimer + dt
                if desync.Internal.OldPosTimer >= delay then
                    desync.Internal.SavedCFrame = oldcf
                    desync.Internal.OldPosTimer = 0
                end
            end

            targetCF = desync.Internal.SavedCFrame

        --// ===================== Void ================================
        elseif mode == "Void" then
            local voidY = tonumber(S.VoidDepth) or -1000
            targetCF = CFrame.new(oldcf.X, voidY, oldcf.Z)

        --// ===================== InPlayer ============================
        elseif mode == "InPlayer" then
            local targetHrp = GetNearestPlayerHRP(oldcf.Position)
            if targetHrp then
                local offset = tonumber(S.InPlayerOffset) or 0
                local look = targetHrp.CFrame.LookVector
                local flatLook = Vector3.new(look.X, 0, look.Z)
                if flatLook.Magnitude < 0.001 then
                    targetCF = targetHrp.CFrame
                else
                    targetCF = targetHrp.CFrame - flatLook.Unit * offset
                end
            else
                targetCF = oldcf
            end

        --// ===================== Default =============================
        else
            desync.Internal.Acc = desync.Internal.Acc + dt
            if desync.Internal.Acc >= interval then
                desync.Internal.Acc = 0
                desync.Internal.TargetOffset = BuildDefaultOffset(S)
            end
            targetCF = oldcf * CFrame.new(desync.Internal.TargetOffset)
        end

        --// RandomRotate
        if S.RandomRotate then
            desync.Internal.RotAcc = desync.Internal.RotAcc + dt
            if desync.Internal.RotAcc >= interval then
                desync.Internal.RotAcc = 0
                desync.Internal.RotPitch = (math.random() * 2 - 1) * math.pi
                desync.Internal.RotYaw   = (math.random() * 2 - 1) * math.pi
                desync.Internal.RotRoll  = (math.random() * 2 - 1) * math.pi
            end
            targetCF = targetCF * CFrame.Angles(
                desync.Internal.RotPitch,
                desync.Internal.RotYaw,
                desync.Internal.RotRoll
            )
        end

        hrp.CFrame = targetCF
        RunService:BindToRenderStep(desync.Internal.RenderBindName, 101, function()
            hrp.CFrame      = oldcf
            hrp.Velocity    = oldvel
            hrp.RotVelocity = oldrotvel
            RunService:UnbindFromRenderStep(desync.Internal.RenderBindName)
        end)
    end)
end

local function StopDesync()
    local desync = AntiAim.Desync

    local hrp = GetCurrentHRP()
    if hrp then
        local realCF = desync.Internal.RealCFrame
        if realCF then
            pcall(function()
                hrp.CFrame = realCF
                if desync.Internal.RealVelocity    then hrp.Velocity    = desync.Internal.RealVelocity    end
                if desync.Internal.RealRotVelocity then hrp.RotVelocity = desync.Internal.RealRotVelocity end
            end)
        end
    end

    if desync.Internal.Connection then
        pcall(function() desync.Internal.Connection:Disconnect() end)
        desync.Internal.Connection = nil
    end

    pcall(function() RunService:UnbindFromRenderStep(desync.Internal.RenderBindName) end)

    desync.Internal.SavedCFrame      = nil
    desync.Internal.RealCFrame       = nil
    desync.Internal.RealVelocity     = nil
    desync.Internal.RealRotVelocity  = nil
    desync.Internal.OldPosTimer      = 0
    desync.Internal.PendingRefresh   = false
    desync.Internal.Acc              = 0
    desync.Internal.CurrentOffset    = Vector3.new(0, 0, 0)
    desync.Internal.TargetOffset     = Vector3.new(0, 0, 0)
    desync.Internal.RotAcc           = 0
    desync.Internal.RotPitch         = 0
    desync.Internal.RotYaw           = 0
    desync.Internal.RotRoll          = 0
end

--// ---------------------------------------------------------------------------
--// Anti-Aim body
--// ---------------------------------------------------------------------------
local function CleanupAntiAim()
    if AntiAim.Internal.BodyGyro then
        pcall(function() AntiAim.Internal.BodyGyro:Destroy() end)
        AntiAim.Internal.BodyGyro = nil
    end
    if AntiAim.Internal.AlignOrientation then
        pcall(function() AntiAim.Internal.AlignOrientation:Destroy() end)
        AntiAim.Internal.AlignOrientation = nil
    end
    if AntiAim.Internal.Attachment then
        pcall(function() AntiAim.Internal.Attachment:Destroy() end)
        AntiAim.Internal.Attachment = nil
    end
    if AntiAim.Internal.AngularVelocity then
        pcall(function() AntiAim.Internal.AngularVelocity:Destroy() end)
        AntiAim.Internal.AngularVelocity = nil
    end
    if AntiAim.Internal.CurrentMotor then
        local motor = AntiAim.Internal.CurrentMotor
        local orig  = AntiAim.Internal.OriginalC0
        if motor.Parent and orig then
            pcall(function() motor.C0 = orig end)
        end
        AntiAim.Internal.CurrentMotor = nil
        AntiAim.Internal.OriginalC0   = nil
    end
end

local function ApplyAntiAim()
    if H.ShuttingDown then return end
    if not AntiAim.Settings.Enabled then CleanupAntiAim() return end

    local char = LocalPlayer.Character
    if not char then CleanupAntiAim() return end

    local now = tick()
    AntiAim.Internal.BodyLastUpdate = now

    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local bodySet = AntiAim.Settings.Body
    local mode    = AntiAim.Settings.Mode
    local method  = AntiAim.Settings.Method

    local shouldApply = true
    if bodySet.IgnoreMoving then
        if root.Velocity.Magnitude > bodySet.MoveSpeedThreshold then
            shouldApply = false
        end
    end

    if shouldApply then
        local baseYaw = GetBaseYaw(bodySet.Reference, char)
        local amount  = tonumber(bodySet.Amount) or 15
        local speed   = tonumber(bodySet.Speed) or 5
        if speed <= 0 then speed = 0.01 end
        local yaw = 0

        if mode == "Static" then
            yaw = baseYaw + math.rad(bodySet.Yaw + amount)
        elseif mode == "Spin" then
            yaw = baseYaw + math.rad((now * speed) % 360 + bodySet.Yaw)
        elseif mode == "Jitter" then
            if now - AntiAim.Internal.BodyJitterTime > 1 / speed then
                AntiAim.Internal.BodyJitterTime = now
                AntiAim.Internal.BodyJitterOffset = (math.random() - 0.5) * 2 * amount
            end
            yaw = baseYaw + math.rad(bodySet.Yaw + AntiAim.Internal.BodyJitterOffset)
        elseif mode == "Sway" then
            yaw = baseYaw + math.rad(bodySet.Yaw + math.sin(now * speed) * amount)
        end

        if method == "CFrame" then
            CleanupAntiAim()
            root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
        elseif method == "BodyGyro" then
            if AntiAim.Internal.AlignOrientation or AntiAim.Internal.AngularVelocity or AntiAim.Internal.CurrentMotor then
                CleanupAntiAim()
            end
            if not AntiAim.Internal.BodyGyro or not AntiAim.Internal.BodyGyro.Parent then
                local bg = Instance.new("BodyGyro")
                bg.MaxTorque = Vector3.new(0, 4000, 0)
                bg.P = 10000
                bg.D = 100
                bg.Parent = root
                AntiAim.Internal.BodyGyro = bg
            end
            AntiAim.Internal.BodyGyro.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
        elseif method == "Motor6D" then
            if AntiAim.Internal.BodyGyro or AntiAim.Internal.AlignOrientation or AntiAim.Internal.AngularVelocity then
                CleanupAntiAim()
            end
            local motor
            for _, child in ipairs(char:GetDescendants()) do
                if child:IsA("Motor6D") and (
                    child.Name == "Neck" or child.Name == "Waist"
                    or child.Name:lower():find("neck") or child.Name:lower():find("waist")
                ) then
                    motor = child
                    break
                end
            end
            if motor then
                if not AntiAim.Internal.CurrentMotor or AntiAim.Internal.CurrentMotor ~= motor
                   or not AntiAim.Internal.CurrentMotor.Parent then
                    if AntiAim.Internal.CurrentMotor and AntiAim.Internal.OriginalC0 then
                        local oldMotor = AntiAim.Internal.CurrentMotor
                        local oldC0    = AntiAim.Internal.OriginalC0
                        if oldMotor.Parent then pcall(function() oldMotor.C0 = oldC0 end) end
                    end
                    AntiAim.Internal.CurrentMotor = motor
                    AntiAim.Internal.OriginalC0   = motor.C0
                end
                if AntiAim.Internal.CurrentMotor.Parent then
                    pcall(function()
                        AntiAim.Internal.CurrentMotor.C0 = AntiAim.Internal.OriginalC0 * CFrame.Angles(0, yaw, 0)
                    end)
                end
            else
                CleanupAntiAim()
            end
        elseif method == "AlignOrientation" then
            if AntiAim.Internal.BodyGyro or AntiAim.Internal.AngularVelocity or AntiAim.Internal.CurrentMotor then
                CleanupAntiAim()
            end
            if not AntiAim.Internal.Attachment or not AntiAim.Internal.Attachment.Parent then
                local attachment = Instance.new("Attachment")
                attachment.Parent = root
                AntiAim.Internal.Attachment = attachment
                AntiAim.Internal.AlignOrientation = nil
            end
            if not AntiAim.Internal.AlignOrientation or not AntiAim.Internal.AlignOrientation.Parent then
                local align = Instance.new("AlignOrientation")
                align.MaxTorque = 4000
                align.MaxAngularVelocity = math.huge
                align.Responsiveness = 50
                align.Parent = root
                align.Attachment0 = AntiAim.Internal.Attachment
                align.RigidityEnabled = false
                AntiAim.Internal.AlignOrientation = align
            end
            AntiAim.Internal.AlignOrientation.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
            AntiAim.Internal.AlignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
            AntiAim.Internal.AlignOrientation.RigidityEnabled = false
        elseif method == "AngularVelocity" then
            if AntiAim.Internal.BodyGyro or AntiAim.Internal.AlignOrientation or AntiAim.Internal.CurrentMotor then
                CleanupAntiAim()
            end
            if not AntiAim.Internal.AngularVelocity or not AntiAim.Internal.AngularVelocity.Parent then
                local av = Instance.new("AngularVelocity")
                av.MaxTorque = Vector3.new(0, 4000, 0)
                av.AngularVelocity = Vector3.new(0, 0, 0)
                av.Parent = root
                AntiAim.Internal.AngularVelocity = av
            end
            local spinSpeed = (mode == "Spin") and math.rad(speed) or 0
            AntiAim.Internal.AngularVelocity.AngularVelocity = Vector3.new(0, spinSpeed, 0)
        end
    else
        CleanupAntiAim()
    end
end

local AA_BIND_NAME = "AirHubAntiAim"
AntiAim.AA_BIND_NAME = AA_BIND_NAME
pcall(function() RunService:UnbindFromRenderStep(AA_BIND_NAME) end)
RunService:BindToRenderStep(AA_BIND_NAME, 201, function()
    xpcall(ApplyAntiAim, HandleError)
end)

--// ---------------------------------------------------------------------------
--// Spoof Animations
--// ---------------------------------------------------------------------------
local function StopSpoofAnimInternal()
    local SA = AntiAim.SpoofAnim
    if SA.Internal.Track then
        pcall(function() SA.Internal.Track:Stop() end)
        SA.Internal.Track = nil
    end
    if SA.Internal.Anim then
        pcall(function() SA.Internal.Anim:Destroy() end)
        SA.Internal.Anim = nil
    end
    SA.Internal.LoadedId = nil
    if SA.Internal.Conn then
        pcall(function() SA.Internal.Conn:Disconnect() end)
        SA.Internal.Conn = nil
    end
end

local function GetAnimator()
    local char = LocalPlayer.Character
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = hum
    end
    return animator
end

local function PlaySpoofAnim()
    local SA = AntiAim.SpoofAnim
    local S  = SA.Settings
    if not S.Enabled then return end

    local animator = GetAnimator()
    if not animator then return end

    local id = S.AnimationId
    if not id or id == "" then return end

    --// Load new animation if changed
    if SA.Internal.LoadedId ~= id then
        if SA.Internal.Track then
            pcall(function() SA.Internal.Track:Stop() end)
            SA.Internal.Track = nil
        end
        if SA.Internal.Anim then
            pcall(function() SA.Internal.Anim:Destroy() end)
            SA.Internal.Anim = nil
        end

        local anim = Instance.new("Animation")
        anim.AnimationId = id
        local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
        if not ok or not track then
            anim:Destroy()
            return
        end
        SA.Internal.Anim = anim
        SA.Internal.Track = track
        SA.Internal.LoadedId = id
    end

    local track = SA.Internal.Track
    if not track then return end

    track.Looped = S.Looped and true or false
    local prio = Enum.AnimationPriority[S.Priority or "Action"] or Enum.AnimationPriority.Action
    pcall(function() track.Priority = prio end)
    local spd = tonumber(S.Speed) or 1
    pcall(function() track:AdjustSpeed(spd) end)
    if not track.IsPlaying then
        pcall(function() track:Play(0.1, 1, spd) end)
    end

    --// Stop on move
    if S.StopOnMove then
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum and hum.MoveDirection.Magnitude > 0.05 then
            pcall(function() track:Stop() end)
        end
    end
end

AntiAim.SpoofAnim.Functions.Start = function()
    local SA = AntiAim.SpoofAnim
    if SA.Internal.Conn then return end
    PlaySpoofAnim()
    SA.Internal.Conn = RunService.Heartbeat:Connect(function()
        if H.ShuttingDown then return end
        if not SA.Settings.Enabled then return end
        PlaySpoofAnim()
    end)
end

AntiAim.SpoofAnim.Functions.Stop = function()
    StopSpoofAnimInternal()
end

AntiAim.SpoofAnim.Functions.Restart = function()
    StopSpoofAnimInternal()
    if AntiAim.SpoofAnim.Settings.Enabled then
        AntiAim.SpoofAnim.Functions.Start()
    end
end

--// Stop spoof anim on character respawn
Track(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    if H.ShuttingDown then return end
    if AntiAim.SpoofAnim.Settings.Enabled then
        AntiAim.SpoofAnim.Functions.Restart()
    end
end))

--// ---------------------------------------------------------------------------
--// Public functions
--// ---------------------------------------------------------------------------
AntiAim.Functions = {
    ResetSettings = function()
        AntiAim.Settings = {
            Enabled = false,
            Mode = "Static",
            Method = "CFrame",
            Body = {
                Reference = "Camera",
                Yaw = 0,
                Amount = 15,
                Speed = 5,
                IgnoreMoving = false,
                MoveSpeedThreshold = 0.5,
            },
        }
        AntiAim.Desync.Settings = {
            Enabled = false,
            Mode = "Default",
            X = 5, Y = 5, Z = 5,
            Random = false,
            UpdateInterval = 0.05,
            OldPosDelayEnabled = true,
            OldPosDelay = 0.5,
            VoidDepth = -1000,
            InPlayerOffset = 2,
            RefreshOnShot = false,
            RandomRotate = false,
        }
        AntiAim.Internal = {
            BodyLastUpdate = 0, BodyJitterTime = 0, BodyJitterOffset = 0,
            BodyGyro = nil, AlignOrientation = nil,
            Attachment = nil, AngularVelocity = nil,
            CurrentMotor = nil, OriginalC0 = nil,
        }
        AntiAim.Desync.Internal.SavedCFrame     = nil
        AntiAim.Desync.Internal.RealCFrame      = nil
        AntiAim.Desync.Internal.RealVelocity    = nil
        AntiAim.Desync.Internal.RealRotVelocity = nil
        AntiAim.Desync.Internal.OldPosTimer     = 0
        AntiAim.Desync.Internal.PendingRefresh  = false
        AntiAim.Desync.Internal.RotAcc          = 0
        AntiAim.SpoofAnim.Settings = {
            Enabled = false,
            AnimationId = "rbxassetid://0",
            Speed = 1,
            Looped = true,
            StopOnMove = false,
            Priority = "Action",
        }
        StopSpoofAnimInternal()
        CleanupAntiAim()
        StopDesync()
    end,

    SaveOldPosition = function()
        local hrp = GetCurrentHRP()
        if hrp then
            AntiAim.Desync.Internal.SavedCFrame    = hrp.CFrame
            AntiAim.Desync.Internal.OldPosTimer    = 0
            AntiAim.Desync.Internal.PendingRefresh = false
            return true
        end
        return false
    end,

    RestorePlayer = function()
        local hrp = GetCurrentHRP()
        local realCF = AntiAim.Desync.Internal.RealCFrame
        if hrp and realCF then
            pcall(function() hrp.CFrame = realCF end)
        end
    end,
}

AntiAim.StartDesync    = StartDesync
AntiAim.StopDesync     = StopDesync
AntiAim.CleanupAntiAim = CleanupAntiAim
