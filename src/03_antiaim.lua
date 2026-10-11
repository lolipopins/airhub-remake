--// ============================================================================
--// AirHub — 03_antiaim.lua
--// Anti-Aim (body) + Desync (client-side) + Animation Breaker.
--// Desync modes: Default / OldPosition / Void / InPlayer
--// Desync methods: CFrame / Position / Velocity / Motor6D / HipHeight / Network
--// Animation Breaker:
--//   Mode = None / Speed / Freeze / Jitter / Replace
--//   Replace = подменяет игровые анимации на набор из Preset
--//   Presets = Default R15 / Default R6 / Zombie / Ninja / Pirate / Robot /
--//             Toy / Levitation / Custom (пользовательские ID из UI)
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
            Mode           = "None",   -- None / Speed / Freeze / Jitter / Replace
            Preset         = "None",   -- name из AB.AnimationPresets
            Speed          = 5,        -- Speed mode (отриц. = реверс)
            FreezeFrame    = 0,        -- Freeze mode
            JitterInterval = 0.15,
            JitterMin      = 0.1,
            JitterMax      = 10,
            ApplyToServer  = true,     -- SetNetworkOwner(LocalPlayer)
            CustomIds = {
                Idle  = "",
                Walk  = "",
                Run   = "",
                Jump  = "",
                Fall  = "",
                Climb = "",
            },
        },
        Internal = {
            JitterTimer     = 0,
            JitterSpeed     = 1,
            LoadedTracks    = {},      -- [slot] = { AnimationTrack... }
            OurTracksSet    = {},      -- [track] = true
            LoadedPreset    = nil,     -- имя загруженного пресета
            AnimConnection  = nil,
            LastHRP         = nil,
            NetworkOwnerSet = false,
            LastSlot        = nil,
            LastPresetSrc   = nil,     -- "builtin" | "custom" (для перезагрузки при смене ID)
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
local AB = AntiAim.AnimationBreaker

--// ---------------------------------------------------------------------------
--// Generic helpers
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
--//
--// Built-in animation packs (Roblox catalog IDs).
--// Каждый пресет = { idle, walk, run, jump, fall, climb }.
--// Значения = массивы ID (одна анимация или несколько для idle-вариаций).
--//
AB.AnimationPresets = {
    ["None"] = {},

    ["Default R15"] = {
        idle  = {507766666, 507766951, 507766388},
        walk  = {507777826},
        run   = {507767714},
        jump  = {507765000},
        fall  = {507767968},
        climb = {507765644},
    },

    ["Default R6"] = {
        idle  = {180435571, 180435792},
        walk  = {180426354},
        run   = {180426354},
        jump  = {125750702},
        fall  = {180436148},
        climb = {180436334},
    },

    ["Zombie R15"] = {
        idle  = {616006778, 616008087, 616013216},
        walk  = {616008936},
        run   = {616010382},
        jump  = {616005621},
        fall  = {616011806},
        climb = {616003253},
    },

    ["Ninja R15"] = {
        idle  = {656117400, 656118341},
        walk  = {656121766},
        run   = {656118852},
        jump  = {656117878},
        fall  = {656115606},
        climb = {656114359},
    },

    ["Pirate R15"] = {
        idle  = {750781171},
        walk  = {750777382},
        run   = {750779262},
        jump  = {750783974},
        fall  = {750783830},
        climb = {750785693},
    },

    ["Robot R15"] = {
        idle  = {616088791},
        walk  = {616090535},
        run   = {616091379},
        jump  = {616087306},
        fall  = {616087669},
        climb = {616086359},
    },

    ["Toy R15"] = {
        idle  = {782850875, 782848174},
        walk  = {782845990},
        run   = {782846968},
        jump  = {782849141},
        fall  = {782848400},
        climb = {782846459},
    },

    ["Levitation R15"] = {
        idle  = {616006778},
        walk  = {616008936},
        run   = {616010382},
    },

    --// Специальный: читает AB.Settings.CustomIds
    ["Custom"] = nil,
}

--// ---------------------------------------------------------------------------
--// Animation Breaker helpers
--// ---------------------------------------------------------------------------
local function ParseIds(str)
    -- Принимает "507766666, 507766951" или "rbxassetid://507766666"
    local ids = {}
    if type(str) ~= "string" or str == "" then return ids end
    for num in string.gmatch(str, "%d+") do
        local n = tonumber(num)
        if n and n > 0 then ids[#ids + 1] = n end
    end
    return ids
end

local function GetAnimator(char)
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end
    return hum:FindFirstChildOfClass("Animator")
end

local function GetActiveSlot(hum)
    if not hum then return "idle" end
    local ok, state = pcall(function() return hum:GetState() end)
    if not ok then return "idle" end

    if state == Enum.HumanoidStateType.Freefall then return "fall" end
    if state == Enum.HumanoidStateType.Jumping  then return "jump" end
    if state == Enum.HumanoidStateType.Climbing then return "climb" end
    if state == Enum.HumanoidStateType.Swimming then return "run" end
    if state == Enum.HumanoidStateType.Running
       or state == Enum.HumanoidStateType.RunningNoPhysics
       or state == Enum.HumanoidStateType.Landed then
        if hum.MoveDirection.Magnitude > 0.1 then
            return "run"
        else
            return "idle"
        end
    end
    return "idle"
end

local function StopAllOurTracks()
    for _, tracks in pairs(AB.Internal.LoadedTracks) do
        for _, t in ipairs(tracks) do
            pcall(function() t:Stop(0) end)
        end
    end
    AB.Internal.LoadedTracks = {}
    AB.Internal.OurTracksSet = {}
end

local function StopGameTracks(animator)
    local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
    if not ok or not tracks then return end
    for _, t in ipairs(tracks) do
        if not AB.Internal.OurTracksSet[t] then
            pcall(function() t:Stop(0) end)
        end
    end
end

local function ResolvePresetTable()
    local presetName = AB.Settings.Preset
    if presetName == "Custom" then
        local ci = AB.Settings.CustomIds or {}
        local out = {}
        local function fill(slot, key)
            local ids = ParseIds(ci[key])
            if #ids > 0 then out[slot] = ids end
        end
        fill("idle",  "Idle")
        fill("walk",  "Walk")
        fill("run",   "Run")
        fill("jump",  "Jump")
        fill("fall",  "Fall")
        fill("climb", "Climb")
        if next(out) == nil then return nil end
        return out
    end
    return AB.AnimationPresets[presetName]
end

local function LoadPresetTracks(animator, presetTable)
    StopAllOurTracks()
    if not presetTable then return end

    local loaded = {}
    local set    = {}

    for slot, ids in pairs(presetTable) do
        local slotTracks = {}
        for _, id in ipairs(ids) do
            local anim = Instance.new("Animation")
            anim.AnimationId = "rbxassetid://" .. tostring(id)
            local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
            if ok and track then
                track.Looped   = true
                track.Priority = Enum.AnimationPriority.Action4
                slotTracks[#slotTracks + 1] = track
                set[track] = true
            end
        end
        if #slotTracks > 0 then
            loaded[slot] = slotTracks
        end
    end

    AB.Internal.LoadedTracks = loaded
    AB.Internal.OurTracksSet = set
end

local function AttachAnimHook(animator)
    if AB.Internal.AnimConnection then
        pcall(function() AB.Internal.AnimConnection:Disconnect() end)
        AB.Internal.AnimConnection = nil
    end
    AB.Internal.AnimConnection = animator.AnimationPlayed:Connect(function(track)
        if H.ShuttingDown then return end
        if not AB.Settings.Enabled then return end
        if AB.Settings.Mode ~= "Replace" then return end
        if AB.Internal.OurTracksSet[track] then return end
        pcall(function() track:Stop(0) end)
    end)
end

--// ---------------------------------------------------------------------------
--// Per-mode appliers
--// ---------------------------------------------------------------------------
local function ApplyReplaceMode(animator, hum)
    local presetName = AB.Settings.Preset
    local presetSrc
    if presetName == "Custom" then
        local ci = AB.Settings.CustomIds or {}
        presetSrc = table.concat({
            ci.Idle or "", ci.Walk or "", ci.Run or "",
            ci.Jump or "", ci.Fall or "", ci.Climb or "",
        }, "|")
    else
        presetSrc = "builtin:" .. tostring(presetName)
    end

    if AB.Internal.LoadedPreset ~= presetName
       or AB.Internal.LastPresetSrc ~= presetSrc then
        local presetTable = ResolvePresetTable()
        if not presetTable or next(presetTable) == nil then
            StopAllOurTracks()
            AB.Internal.LoadedPreset  = nil
            AB.Internal.LastPresetSrc = presetSrc
            return
        end
        LoadPresetTracks(animator, presetTable)
        AB.Internal.LoadedPreset  = presetName
        AB.Internal.LastPresetSrc = presetSrc
        AB.Internal.LastSlot      = nil
    end

    StopGameTracks(animator)

    local slot = GetActiveSlot(hum)
    local tracksForSlot = AB.Internal.LoadedTracks[slot]
    if not tracksForSlot or #tracksForSlot == 0 then
        tracksForSlot = AB.Internal.LoadedTracks.idle
        slot = "idle"
    end
    if not tracksForSlot or #tracksForSlot == 0 then return end

    local activeTrack
    if slot == "idle" and #tracksForSlot > 1 then
        if AB.Internal.LastSlot ~= "idle" or math.random() < 0.02 then
            activeTrack = tracksForSlot[math.random(1, #tracksForSlot)]
        else
            for _, t in ipairs(tracksForSlot) do
                if t.IsPlaying then activeTrack = t break end
            end
            activeTrack = activeTrack or tracksForSlot[1]
        end
    else
        activeTrack = tracksForSlot[1]
    end

    for s, slotTracks in pairs(AB.Internal.LoadedTracks) do
        for _, t in ipairs(slotTracks) do
            if t ~= activeTrack and t.IsPlaying then
                pcall(function() t:Stop(0.1) end)
            end
        end
    end

    if not activeTrack.IsPlaying then
        pcall(function() activeTrack:Play(0.1) end)
    end

    AB.Internal.LastSlot = slot
end

local function ApplySpeedMode(animator)
    local speed = tonumber(AB.Settings.Speed) or 1
    local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
    if not ok or not tracks then return end
    for _, t in ipairs(tracks) do
        pcall(function()
            if t.Speed ~= speed then t.Speed = speed end
        end)
    end
end

local function ApplyFreezeMode(animator)
    local frame = tonumber(AB.Settings.FreezeFrame) or 0
    local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
    if not ok or not tracks then return end
    for _, t in ipairs(tracks) do
        pcall(function()
            if t.Speed ~= 0 then t.Speed = 0 end
            t.TimePosition = frame
        end)
    end
end

local function ApplyJitterMode(animator, dt)
    local interval = tonumber(AB.Settings.JitterInterval) or 0.15
    if interval < 0.01 then interval = 0.01 end
    AB.Internal.JitterTimer = AB.Internal.JitterTimer + dt
    if AB.Internal.JitterTimer >= interval then
        AB.Internal.JitterTimer = 0
        local mn = tonumber(AB.Settings.JitterMin) or 0.1
        local mx = tonumber(AB.Settings.JitterMax) or 10
        if mx < mn then mx = mn end
        AB.Internal.JitterSpeed = mn + math.random() * (mx - mn)
    end
    local speed = AB.Internal.JitterSpeed
    local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
    if not ok or not tracks then return end
    for _, t in ipairs(tracks) do
        pcall(function() t.Speed = speed end)
    end
end

--// ---------------------------------------------------------------------------
--// Main entry (called from Heartbeat)
--// ---------------------------------------------------------------------------
local function ApplyAnimationBreaker(dt)
    if H.ShuttingDown then return end
    if not AB.Settings.Enabled then return end

    local char = LocalPlayer.Character
    if not char then
        StopAllOurTracks()
        AB.Internal.NetworkOwnerSet = false
        AB.Internal.LastHRP         = nil
        AB.Internal.LoadedPreset    = nil
        AB.Internal.LastPresetSrc   = nil
        return
    end

    local animator = GetAnimator(char)
    if not animator then
        AB.Internal.LoadedPreset = nil
        return
    end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp ~= AB.Internal.LastHRP then
        AB.Internal.LastHRP         = hrp
        AB.Internal.NetworkOwnerSet = false
        StopAllOurTracks()
        AB.Internal.LoadedPreset    = nil
        AB.Internal.LastPresetSrc   = nil
        AB.Internal.LastSlot        = nil
        AttachAnimHook(animator)
    end

    if AB.Settings.ApplyToServer and hrp and not AB.Internal.NetworkOwnerSet then
        pcall(function() hrp:SetNetworkOwner(LocalPlayer) end)
        AB.Internal.NetworkOwnerSet = true
    end

    local hum = char:FindFirstChildOfClass("Humanoid")
    local mode = AB.Settings.Mode or "None"

    if mode == "None" then
        if AB.Internal.LoadedPreset then
            StopAllOurTracks()
            AB.Internal.LoadedPreset  = nil
            AB.Internal.LastPresetSrc = nil
            AB.Internal.LastSlot      = nil
        end
        return
    end

    if mode == "Replace" then
        if not AB.Internal.AnimConnection then AttachAnimHook(animator) end
        ApplyReplaceMode(animator, hum)

    elseif mode == "Speed" then
        if AB.Internal.LoadedPreset then
            StopAllOurTracks()
            AB.Internal.LoadedPreset = nil
        end
        ApplySpeedMode(animator)

    elseif mode == "Freeze" then
        if AB.Internal.LoadedPreset then
            StopAllOurTracks()
            AB.Internal.LoadedPreset = nil
        end
        ApplyFreezeMode(animator)

    elseif mode == "Jitter" then
        if AB.Internal.LoadedPreset then
            StopAllOurTracks()
            AB.Internal.LoadedPreset = nil
        end
        ApplyJitterMode(animator, dt)
    end
end

local function ResetAllSpeeds()
    local char = LocalPlayer.Character
    if not char then return end
    local animator = GetAnimator(char)
    if not animator then return end
    local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
    if not ok or not tracks then return end
    for _, t in ipairs(tracks) do
        pcall(function()
            if t.Speed ~= 1 then t.Speed = 1 end
        end)
    end
end

local function StopAnimationBreaker()
    ResetAllSpeeds()
    StopAllOurTracks()
    if AB.Internal.AnimConnection then
        pcall(function() AB.Internal.AnimConnection:Disconnect() end)
        AB.Internal.AnimConnection = nil
    end
    AB.Internal.JitterTimer     = 0
    AB.Internal.JitterSpeed     = 1
    AB.Internal.LoadedPreset    = nil
    AB.Internal.LastPresetSrc   = nil
    AB.Internal.LastSlot        = nil
    AB.Internal.NetworkOwnerSet = false
    AB.Internal.LastHRP         = nil
end

local function ReloadAnimationPreset()
    StopAllOurTracks()
    AB.Internal.LoadedPreset  = nil
    AB.Internal.LastPresetSrc = nil
    AB.Internal.LastSlot      = nil
end

AB.Functions.ApplyPreset = function(name)
    if AB.AnimationPresets[name] == nil and name ~= "Custom" then return false end
    AB.Settings.Preset = name
    if AB.Settings.Enabled then
        AB.Settings.Mode = "Replace"
        ReloadAnimationPreset()
    end
    return true
end
AB.Functions.Reload = ReloadAnimationPreset
AB.Functions.Stop   = StopAnimationBreaker
AB.Functions.ListPresets = function()
    local out = {}
    for k in pairs(AB.AnimationPresets) do out[#out + 1] = k end
    table.sort(out)
    return out
end

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
        AB.Settings = {
            Enabled        = false,
            Mode           = "None",
            Preset         = "None",
            Speed          = 5,
            FreezeFrame    = 0,
            JitterInterval = 0.15,
            JitterMin      = 0.1,
            JitterMax      = 10,
            ApplyToServer  = true,
            CustomIds = {
                Idle  = "",
                Walk  = "",
                Run   = "",
                Jump  = "",
                Fall  = "",
                Climb = "",
            },
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

--// Animation Breaker public aliases
AntiAim.StartAnimationBreaker   = function() AB.Settings.Enabled = true end
AntiAim.StopAnimationBreaker    = StopAnimationBreaker
AntiAim.ReloadAnimationPreset   = ReloadAnimationPreset
AntiAim.ApplyAnimationPreset    = AB.Functions.ApplyPreset
AntiAim.AnimationPresets        = AB.AnimationPresets
AntiAim.ParseAnimationIds       = ParseIds
