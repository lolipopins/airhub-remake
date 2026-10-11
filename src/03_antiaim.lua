--// ============================================================================
--// AirHub — 03_antiaim.lua
--// Anti-Aim (body) + Desync (client-side) + Animation Breaker.
--// Desync modes: Default / OldPosition / Void / InPlayer
--// Desync methods: CFrame / Position / Velocity / Motor6D / HipHeight / Network
--// Animation Breaker modes: None / Speed / Freeze / Jitter / Custom
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
            Amount             = 15,
            Speed              = 5,
            IgnoreMoving       = false,
            MoveSpeedThreshold = 0.5,
        },
    },
    Desync = {
        Settings = {
            Enabled            = false,
            Mode               = "Default",
            Method             = "CFrame",
            X                  = 5,
            Y                  = 5,
            Z                  = 5,
            Random             = false,
            UpdateInterval     = 0.05,
            OldPosDelayEnabled = true,
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
            NetworkClaimed   = false,
        },
    },
    --// ---- Animation Breaker ------------------------------------------------
    AnimationBreaker = {
        Settings = {
            Enabled        = false,
            Preset         = "None",
            Mode           = "None",       -- None / Speed / Freeze / Jitter / Custom
            Speed          = 5,            -- multiplier (negative = reverse)
            FreezeFrame    = 0,            -- seconds into the animation
            JitterInterval = 0.15,         -- seconds between random speed picks
            JitterMin      = 0.1,
            JitterMax      = 10,
            ApplyToServer  = true,         -- SetNetworkOwner(LocalPlayer)
            CustomId       = "",           -- rbxassetid://...
        },
        Internal = {
            JitterTimer        = 0,
            CurrentJitterSpeed = 1,
            CustomTrack        = nil,
            CustomTrackId      = "",
            NetworkOwnerSet    = false,
            LastHRP            = nil,
        },
        Functions = {},
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

local function GetRootJoint(hrp)
    if not hrp then return nil end
    for _, child in ipairs(hrp:GetChildren()) do
        if child:IsA("Motor6D") then return child end
    end
    return nil
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
    desync.Internal.NetworkClaimed  = false

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
        local hum = char:FindFirstChildOfClass("Humanoid")

        local oldcf     = hrp.CFrame
        local oldvel    = hrp.Velocity
        local oldrotvel = hrp.RotVelocity
        local oldPos    = oldcf.Position

        desync.Internal.RealCFrame      = oldcf
        desync.Internal.RealVelocity    = oldvel
        desync.Internal.RealRotVelocity = oldrotvel

        local S = desync.Settings
        local mode   = S.Mode
        local method = S.Method or "CFrame"
        local interval = tonumber(S.UpdateInterval) or 0.05
        if interval < 0.01 then interval = 0.01 end

        local rootJoint   = GetRootJoint(hrp)
        local oldRootC0   = rootJoint and rootJoint.C0
        local oldHipH     = hum and hum.HipHeight

        local targetCF

        if mode == "OldPosition" then
            if not desync.Internal.SavedCFrame then
                desync.Internal.SavedCFrame = oldcf
            end
            if desync.Internal.PendingRefresh then
                desync.Internal.PendingRefresh = false
                desync.Internal.SavedCFrame = oldcf
                desync.Internal.OldPosTimer = 0
            end
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

        elseif mode == "Void" then
            local voidY = tonumber(S.VoidDepth) or -1000
            targetCF = CFrame.new(oldcf.X, voidY, oldcf.Z)

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

        else
            desync.Internal.Acc = desync.Internal.Acc + dt
            if desync.Internal.Acc >= interval then
                desync.Internal.Acc = 0
                desync.Internal.TargetOffset = BuildDefaultOffset(S)
            end
            targetCF = oldcf * CFrame.new(desync.Internal.TargetOffset)
        end

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

        local applied = false
        if method == "CFrame" then
            hrp.CFrame = targetCF
            applied = true

        elseif method == "Position" then
            hrp.Position = targetCF.Position
            applied = true

        elseif method == "Velocity" then
            local diff = targetCF.Position - oldPos
            local mag  = diff.Magnitude
            if mag > 0.001 then
                local speed = math.min(mag / math.max(dt, 0.001), 1000)
                hrp.Velocity = diff.Unit * speed
            else
                hrp.Velocity = Vector3.new(0, 0, 0)
            end
            applied = true

        elseif method == "Motor6D" then
            if rootJoint and oldRootC0 then
                local offset = targetCF.Position - oldPos
                pcall(function()
                    rootJoint.C0 = oldRootC0 + offset
                end)
                applied = true
            end

        elseif method == "HipHeight" then
            if hum and oldHipH then
                local yOff = targetCF.Position.Y - oldPos.Y
                pcall(function()
                    hum.HipHeight = oldHipH + yOff
                end)
                applied = true
            end

        elseif method == "Network" then
            if not desync.Internal.NetworkClaimed then
                pcall(function() hrp:SetNetworkOwner(LocalPlayer) end)
                desync.Internal.NetworkClaimed = true
            end
            hrp.CFrame = targetCF
            applied = true
        end

        if applied then
            RunService:BindToRenderStep(desync.Internal.RenderBindName, 101, function()
                pcall(function()
                    hrp.CFrame      = oldcf
                    hrp.Velocity    = oldvel
                    hrp.RotVelocity = oldrotvel
                end)
                if rootJoint and oldRootC0 then
                    pcall(function() rootJoint.C0 = oldRootC0 end)
                end
                if hum and oldHipH then
                    pcall(function() hum.HipHeight = oldHipH end)
                end
                RunService:UnbindFromRenderStep(desync.Internal.RenderBindName)
            end)
        end
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
    desync.Internal.NetworkClaimed   = false
end

--// ===========================================================================
--// Animation Breaker
--// ===========================================================================
local AB = AntiAim.AnimationBreaker

--// Behavior presets. Applied by name from UI / external code.
AB.Presets = {
    ["None"]                    = { Mode = "None" },
    ["Frozen (frame 0)"]        = { Mode = "Freeze", FreezeFrame = 0 },
    ["Frozen (frame 0.5s)"]     = { Mode = "Freeze", FreezeFrame = 0.5 },
    ["Super Fast (10x)"]        = { Mode = "Speed",  Speed = 10 },
    ["Very Fast (5x)"]          = { Mode = "Speed",  Speed = 5 },
    ["Super Slow (0.1x)"]       = { Mode = "Speed",  Speed = 0.1 },
    ["Reverse (-1x)"]           = { Mode = "Speed",  Speed = -1 },
    ["Zero Speed"]              = { Mode = "Speed",  Speed = 0 },
    ["Jitter (chaos)"]          = { Mode = "Jitter", JitterMin = 0.05, JitterMax = 15, JitterInterval = 0.1 },
    ["Jitter (subtle)"]         = { Mode = "Jitter", JitterMin = 0.5,  JitterMax = 2,  JitterInterval = 0.3 },
    ["Custom Animation"]        = { Mode = "Custom" },
}

local function GetAnimator(char)
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end
    return hum:FindFirstChildOfClass("Animator")
end

local function StopCustomTrack()
    if AB.Internal.CustomTrack then
        pcall(function() AB.Internal.CustomTrack:Stop(0) end)
        AB.Internal.CustomTrack   = nil
        AB.Internal.CustomTrackId = ""
    end
end

local function ResetAllSpeeds()
    local char = LocalPlayer.Character
    if not char then return end
    local animator = GetAnimator(char)
    if not animator then return end
    local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
    if not ok or not tracks then return end
    for _, track in ipairs(tracks) do
        pcall(function()
            if track.Speed ~= 1 then track.Speed = 1 end
        end)
    end
end

local function ApplyAnimationBreaker(dt)
    if H.ShuttingDown then return end
    if not AB.Settings.Enabled then return end

    local char = LocalPlayer.Character
    if not char then
        StopCustomTrack()
        AB.Internal.NetworkOwnerSet = false
        AB.Internal.LastHRP         = nil
        return
    end

    local animator = GetAnimator(char)
    if not animator then return end

    --// HRP change → reset network flag + custom track (respawn)
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp ~= AB.Internal.LastHRP then
        AB.Internal.LastHRP         = hrp
        AB.Internal.NetworkOwnerSet = false
        StopCustomTrack()
    end

    --// Apply to server (may fail if game locks ownership)
    if AB.Settings.ApplyToServer and hrp and not AB.Internal.NetworkOwnerSet then
        pcall(function() hrp:SetNetworkOwner(LocalPlayer) end)
        AB.Internal.NetworkOwnerSet = true
    end

    local mode = AB.Settings.Mode or "None"
    if mode == "None" then
        -- edge case: enabled but no mode → restore speeds
        ResetAllSpeeds()
        return
    end

    local okTracks, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
    if not okTracks or not tracks then return end

    --// ---- Custom mode ---------------------------------------------------
    if mode == "Custom" then
        local customId = AB.Settings.CustomId
        if not customId or customId == "" then return end

        -- Stop game tracks (leave our custom one)
        for _, track in ipairs(tracks) do
            if track ~= AB.Internal.CustomTrack then
                pcall(function() track:Stop(0) end)
            end
        end

        if AB.Internal.CustomTrackId ~= customId then
            StopCustomTrack()
            local anim = Instance.new("Animation")
            anim.AnimationId = customId
            local ok, newTrack = pcall(function() return animator:LoadAnimation(anim) end)
            if ok and newTrack then
                newTrack.Looped   = true
                newTrack.Priority = Enum.AnimationPriority.Action4
                pcall(function() newTrack:Play(0.1) end)
                AB.Internal.CustomTrack   = newTrack
                AB.Internal.CustomTrackId = customId
            end
        elseif AB.Internal.CustomTrack and not AB.Internal.CustomTrack.IsPlaying then
            pcall(function() AB.Internal.CustomTrack:Play(0.1) end)
        end
        return
    end

    --// ---- Speed-based modes --------------------------------------------
    local speed
    if mode == "Speed" then
        speed = tonumber(AB.Settings.Speed) or 1

    elseif mode == "Freeze" then
        speed = 0

    elseif mode == "Jitter" then
        local interval = tonumber(AB.Settings.JitterInterval) or 0.15
        if interval < 0.01 then interval = 0.01 end
        AB.Internal.JitterTimer = AB.Internal.JitterTimer + dt
        if AB.Internal.JitterTimer >= interval then
            AB.Internal.JitterTimer = 0
            local mn = tonumber(AB.Settings.JitterMin) or 0.1
            local mx = tonumber(AB.Settings.JitterMax) or 10
            if mx < mn then mx = mn end
            AB.Internal.CurrentJitterSpeed = mn + math.random() * (mx - mn)
        end
        speed = AB.Internal.CurrentJitterSpeed
    end

    if speed then
        local freezeFrame = tonumber(AB.Settings.FreezeFrame) or 0
        for _, track in ipairs(tracks) do
            pcall(function()
                track.Speed = speed
                if mode == "Freeze" then
                    track.TimePosition = freezeFrame
                end
            end)
        end
    end
end

local function StartAnimationBreaker()
    AB.Internal.JitterTimer        = 0
    AB.Internal.CurrentJitterSpeed = 1
    AB.Internal.NetworkOwnerSet    = false
    AB.Internal.LastHRP            = nil
    StopCustomTrack()
end

local function StopAnimationBreaker()
    ResetAllSpeeds()
    StopCustomTrack()
    AB.Internal.JitterTimer        = 0
    AB.Internal.CurrentJitterSpeed = 1
    AB.Internal.NetworkOwnerSet    = false
    AB.Internal.LastHRP            = nil
end

local function ApplyAnimPreset(name)
    local preset = AB.Presets[name]
    if not preset then return false end
    local S = AB.Settings
    for k, v in pairs(preset) do
        S[k] = v
    end
    S.Preset = name
    return true
end

AB.Functions.Apply         = ApplyAnimationBreaker
AB.Functions.ApplyPreset   = ApplyAnimPreset
AB.Functions.Start         = StartAnimationBreaker
AB.Functions.Stop          = StopAnimationBreaker
AB.Functions.ListPresets   = function()
    local out = {}
    for k in pairs(AB.Presets) do out[#out + 1] = k end
    table.sort(out)
    return out
end

--// Persistent heartbeat (early-outs when disabled)
RunService.Heartbeat:Connect(function(dt)
    if H.ShuttingDown then return end
    if not AB.Settings.Enabled then return end
    xpcall(function() ApplyAnimationBreaker(dt) end, HandleError)
end)

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
            Method = "CFrame",
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
        --// Reset Animation Breaker
        AB.Settings = {
            Enabled        = false,
            Preset         = "None",
            Mode           = "None",
            Speed          = 5,
            FreezeFrame    = 0,
            JitterInterval = 0.15,
            JitterMin      = 0.1,
            JitterMax      = 10,
            ApplyToServer  = true,
            CustomId       = "",
        }
        pcall(StopAnimationBreaker)

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
        AntiAim.Desync.Internal.NetworkClaimed  = false
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

--// Animation Breaker public API
AntiAim.StartAnimationBreaker = StartAnimationBreaker
AntiAim.StopAnimationBreaker  = StopAnimationBreaker
AntiAim.ApplyAnimationPreset  = ApplyAnimPreset
AntiAim.AnimationPresets      = AB.Presets
