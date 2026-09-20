--// ============================================================================
--// AirHub — 03_antiaim.lua
--// Anti-Aim (body) + Desync (client-side).
--// Requires: 01_core.lua
--// Modes: Random / OldPosition / Void / VoidRandom
--// ============================================================================
local H = getgenv().AirHub
if not H or not H._CoreLoaded then warn("[AirHub] 03_antiaim: core not loaded") return end
if H.AntiAim then warn("[AirHub] AntiAim already loaded") return end

local Util        = H.Util
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
            SpinSpeed          = 0,
            JitterAmount       = 5,
            JitterSpeed        = 10,
            SwayAmount         = 30,
            SwaySpeed          = 2,
            IgnoreMoving       = false,
            MoveSpeedThreshold = 0.5,
        },
    },
    Desync = {
        Settings = {
            Enabled            = false,
            Mode               = "Random",   -- Random / OldPosition / Void / VoidRandom
            RadiusX            = 5,
            RadiusY            = 5,
            RadiusZ            = 5,
            UpdateInterval     = 0.05,
            Smoothness         = 0.2,
            OnlyInAir          = false,
            NotInAir           = false,
            FreezeOldPos       = true,
            RandomDelayEnabled = false,
            AutoUpdateMin      = 0.2,
            AutoUpdateMax      = 1.0,
            RefreshOnShot      = false,
            --// NEW: Void mode
            VoidDepth          = -1000,   -- Y coordinate for Void mode
            --// NEW: VoidRandom mode
            VoidRadiusX        = 300,
            VoidRadiusY        = 300,
            VoidRadiusZ        = 300,
        },
        Internal = {
            Connection     = nil,
            RenderBindName = "AirHubDesyncRestore",
            Acc            = 0,
            CurrentOffset  = Vector3.new(0, 0, 0),
            TargetOffset   = Vector3.new(0, 0, 0),
            SavedCFrame    = nil,
            OriginalPos    = nil,   -- NEW: pre-desync CFrame for Void / VoidRandom
            OldPosTimer    = 0,
            NextUpdate     = 0,
            PendingRefresh = false,
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

local function RandomOffset(radius)
    if radius == 0 then return 0 end
    if radius > 0 then return math.random(1, radius) else return -math.random(1, -radius) end
end

local function PickNextDelay(settings)
    local minV = tonumber(settings.AutoUpdateMin) or 0.2
    local maxV = tonumber(settings.AutoUpdateMax) or 1.0
    if minV < 0 then minV = 0 end
    if maxV < minV then maxV = minV end
    if maxV - minV < 0.001 then return minV end
    return minV + math.random() * (maxV - minV)
end

--// ---------------------------------------------------------------------------
--// Desync
--// ---------------------------------------------------------------------------
local function GetCurrentHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

--// Restore helper — used by StopDesync to put player back before disabling
local function RestorePlayerCFrame()
    local hrp = GetCurrentHRP()
    if not hrp then return end
    local d = AntiAim.Desync
    local restore = d.Internal.SavedCFrame or d.Internal.OriginalPos
    if restore then
        pcall(function() hrp.CFrame = restore end)
    end
end

local function StartDesync()
    local desync = AntiAim.Desync
    if desync.Internal.Connection then return end

    --// Reset runtime state
    desync.Internal.Acc           = 0
    desync.Internal.CurrentOffset = Vector3.new(0, 0, 0)
    desync.Internal.TargetOffset  = Vector3.new(0, 0, 0)
    desync.Internal.OriginalPos   = nil
    desync.Internal.PendingRefresh = false

    if desync.Settings.Mode == "OldPosition" then
        local hrp = GetCurrentHRP()
        if hrp then desync.Internal.SavedCFrame = hrp.CFrame end
        desync.Internal.OldPosTimer = 0
        desync.Internal.NextUpdate  = PickNextDelay(desync.Settings)
    end

    desync.Internal.Connection = RunService.Heartbeat:Connect(function(dt)
        if H.ShuttingDown then return end
        local char = LocalPlayer.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local inAir = hum and hum.FloorMaterial == Enum.Material.Air

        if desync.Settings.OnlyInAir and not inAir then return end
        if desync.Settings.NotInAir and inAir and desync.Settings.Mode ~= "OldPosition" then return end

        local oldcf     = hrp.CFrame
        local oldvel    = hrp.Velocity
        local oldrotvel = hrp.RotVelocity
        local targetCF

        --// ======================= OldPosition =========================
        if desync.Settings.Mode == "OldPosition" then
            if not desync.Internal.SavedCFrame then desync.Internal.SavedCFrame = oldcf end
            local canRefresh = true
            if desync.Settings.NotInAir and inAir then canRefresh = false end

            if canRefresh and desync.Internal.PendingRefresh then
                desync.Internal.PendingRefresh = false
                desync.Internal.SavedCFrame = oldcf
                desync.Internal.OldPosTimer = 0
                desync.Internal.NextUpdate  = PickNextDelay(desync.Settings)
            end

            if canRefresh and desync.Settings.RandomDelayEnabled and not desync.Settings.FreezeOldPos then
                desync.Internal.OldPosTimer = (desync.Internal.OldPosTimer or 0) + dt
                if desync.Internal.OldPosTimer >= (desync.Internal.NextUpdate or 0) then
                    desync.Internal.SavedCFrame = oldcf
                    desync.Internal.OldPosTimer = 0
                    desync.Internal.NextUpdate  = PickNextDelay(desync.Settings)
                end
            elseif not canRefresh then
                if desync.Settings.RandomDelayEnabled and not desync.Settings.FreezeOldPos then
                    desync.Internal.OldPosTimer = (desync.Internal.OldPosTimer or 0) + dt
                    if desync.Internal.OldPosTimer >= (desync.Internal.NextUpdate or 0) then
                        desync.Internal.PendingRefresh = true
                    end
                elseif not desync.Settings.FreezeOldPos and not desync.Settings.RandomDelayEnabled then
                    desync.Internal.PendingRefresh = true
                end
            end

            if canRefresh and not desync.Settings.FreezeOldPos and not desync.Settings.RandomDelayEnabled then
                desync.Internal.SavedCFrame = oldcf
            end

            targetCF = desync.Internal.SavedCFrame

        --// ======================= Void =================================
        --// Server sees player teleported deep into the void at constant Y.
        --// Visual stays normal (render step restores CFrame).
        elseif desync.Settings.Mode == "Void" then
            if not desync.Internal.OriginalPos then
                desync.Internal.OriginalPos = oldcf
            end
            local voidY = tonumber(desync.Settings.VoidDepth) or -1000
            targetCF = CFrame.new(oldcf.X, voidY, oldcf.Z)

        --// ======================= VoidRandom ===========================
        --// Random teleports around a base position (usually up in the sky / void).
        elseif desync.Settings.Mode == "VoidRandom" then
            if not desync.Internal.OriginalPos then
                desync.Internal.OriginalPos = oldcf
            end
            desync.Internal.Acc = desync.Internal.Acc + dt
            if desync.Internal.Acc >= desync.Settings.UpdateInterval then
                desync.Internal.Acc = 0
                desync.Internal.TargetOffset = Vector3.new(
                    RandomOffset(desync.Settings.VoidRadiusX or 300),
                    RandomOffset(desync.Settings.VoidRadiusY or 300),
                    RandomOffset(desync.Settings.VoidRadiusZ or 300)
                )
            end
            local lerpFactor = math.clamp(dt / desync.Settings.Smoothness, 0, 1)
            desync.Internal.CurrentOffset = desync.Internal.CurrentOffset:Lerp(desync.Internal.TargetOffset, lerpFactor)
            local base = desync.Internal.OriginalPos.Position
            targetCF = CFrame.new(base + desync.Internal.CurrentOffset)

        --// ======================= Random (default) =====================
        else
            desync.Internal.Acc = desync.Internal.Acc + dt
            if desync.Internal.Acc >= desync.Settings.UpdateInterval then
                desync.Internal.Acc = 0
                desync.Internal.TargetOffset = Vector3.new(
                    RandomOffset(desync.Settings.RadiusX),
                    RandomOffset(desync.Settings.RadiusY),
                    RandomOffset(desync.Settings.RadiusZ)
                )
            end
            local lerpFactor = math.clamp(dt / desync.Settings.Smoothness, 0, 1)
            desync.Internal.CurrentOffset = desync.Internal.CurrentOffset:Lerp(desync.Internal.TargetOffset, lerpFactor)
            targetCF = oldcf * CFrame.new(desync.Internal.CurrentOffset)
        end

        --// Apply desync CFrame (physics), visual restores to oldcf next render step
        hrp.CFrame = targetCF
        RunService:BindToRenderStep(desync.Internal.RenderBindName, 101, function()
            hrp.CFrame     = oldcf
            hrp.Velocity   = oldvel
            hrp.RotVelocity = oldrotvel
            RunService:UnbindFromRenderStep(desync.Internal.RenderBindName)
        end)
    end)
end

--// ---------------------------------------------------------------------------
--// StopDesync — CFrame restored FIRST, then connections killed
--// ---------------------------------------------------------------------------
local function StopDesync()
    local desync = AntiAim.Desync

    --// STEP 1 — return player to their proper CFrame BEFORE disabling
    RestorePlayerCFrame()

    --// STEP 2 — disconnect the update loop
    if desync.Internal.Connection then
        pcall(function() desync.Internal.Connection:Disconnect() end)
        desync.Internal.Connection = nil
    end

    --// STEP 3 — remove any pending render restore
    pcall(function() RunService:UnbindFromRenderStep(desync.Internal.RenderBindName) end)

    --// STEP 4 — reset state
    desync.Internal.SavedCFrame    = nil
    desync.Internal.OriginalPos    = nil
    desync.Internal.OldPosTimer    = 0
    desync.Internal.NextUpdate     = 0
    desync.Internal.PendingRefresh = false
    desync.Internal.Acc            = 0
    desync.Internal.CurrentOffset  = Vector3.new(0, 0, 0)
    desync.Internal.TargetOffset   = Vector3.new(0, 0, 0)
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
        local yaw = 0
        if mode == "Static" then
            yaw = baseYaw + math.rad(bodySet.Yaw)
        elseif mode == "Spin" then
            yaw = baseYaw + math.rad((now * bodySet.SpinSpeed) % 360 + bodySet.Yaw)
        elseif mode == "Jitter" then
            if now - AntiAim.Internal.BodyJitterTime > 1 / bodySet.JitterSpeed then
                AntiAim.Internal.BodyJitterTime = now
                AntiAim.Internal.BodyJitterOffset = (math.random() - 0.5) * 2 * bodySet.JitterAmount
            end
            yaw = baseYaw + math.rad(bodySet.Yaw + AntiAim.Internal.BodyJitterOffset)
        elseif mode == "Sway" then
            yaw = baseYaw + math.rad(bodySet.Yaw + math.sin(now * bodySet.SwaySpeed) * bodySet.SwayAmount)
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
            local spinSpeed = (mode == "Spin") and math.rad(bodySet.SpinSpeed) or 0
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
--// Public functions
--// ---------------------------------------------------------------------------
AntiAim.Functions = {
    ResetSettings = function()
        AntiAim.Settings = {
            Enabled = false,
            Mode = "Static",
            Method = "CFrame",
            Body = {
                Reference = "Camera", Yaw = 0, SpinSpeed = 0,
                JitterAmount = 5, JitterSpeed = 10,
                SwayAmount = 30, SwaySpeed = 2,
                IgnoreMoving = false, MoveSpeedThreshold = 0.5,
            },
        }
        AntiAim.Desync.Settings = {
            Enabled = false, Mode = "Random",
            RadiusX = 5, RadiusY = 5, RadiusZ = 5,
            UpdateInterval = 0.05, Smoothness = 0.2,
            OnlyInAir = false, NotInAir = false,
            FreezeOldPos = true,
            RandomDelayEnabled = false,
            AutoUpdateMin = 0.2, AutoUpdateMax = 1.0,
            RefreshOnShot = false,
            VoidDepth = -1000,
            VoidRadiusX = 300, VoidRadiusY = 300, VoidRadiusZ = 300,
        }
        AntiAim.Internal = {
            BodyLastUpdate = 0, BodyJitterTime = 0, BodyJitterOffset = 0,
            BodyGyro = nil, AlignOrientation = nil,
            Attachment = nil, AngularVelocity = nil,
            CurrentMotor = nil, OriginalC0 = nil,
        }
        AntiAim.Desync.Internal.SavedCFrame    = nil
        AntiAim.Desync.Internal.OriginalPos    = nil
        AntiAim.Desync.Internal.OldPosTimer    = 0
        AntiAim.Desync.Internal.NextUpdate     = 0
        AntiAim.Desync.Internal.PendingRefresh = false
        CleanupAntiAim()
        StopDesync()
    end,

    SaveOldPosition = function()
        local hrp = GetCurrentHRP()
        if hrp then
            AntiAim.Desync.Internal.SavedCFrame    = hrp.CFrame
            AntiAim.Desync.Internal.OldPosTimer    = 0
            AntiAim.Desync.Internal.NextUpdate     = PickNextDelay(AntiAim.Desync.Settings)
            AntiAim.Desync.Internal.PendingRefresh = false
            return true
        end
        return false
    end,

    --// Explicit user-facing helper for "return to player"
    RestorePlayer = RestorePlayerCFrame,
}

AntiAim.StartDesync    = StartDesync
AntiAim.StopDesync     = StopDesync
AntiAim.CleanupAntiAim = CleanupAntiAim
AntiAim.PickNextDelay  = PickNextDelay
