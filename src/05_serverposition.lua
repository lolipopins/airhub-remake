--// ============================================================================
--// AirHub — 05_serverposition.lua
--//  Server Position ghost visualization.
--//  Requires: 01_core.lua
--// ============================================================================

local H = getgenv().AirHub
if not H or not H._CoreLoaded then
    warn("[AirHub] 05_serverposition: core not loaded")
    return
end
if H.ServerPosition then
    warn("[AirHub] ServerPosition already loaded")
    return
end

local Util = H.Util
local RunService = Util.RunService
local LocalPlayer = Util.LocalPlayer
local Track = Util.Track

H.ServerPosition = {
    Settings = { Enabled = false, RGB = true, Strength = 1, MaxLimb = 6 },
    Internal = { Connection = nil, Ghosts = {} },
}
local ServerPosition = H.ServerPosition

local part_names = {
    "HumanoidRootPart", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg",
    "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm",
    "LeftHand", "RightHand", "LeftUpperLeg", "RightUpperLeg",
    "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot",
}

local function rgb(t) return Color3.fromHSV((t % 5) / 5, 1, 1) end

local function make_ghost(real)
    local g = Instance.new("Part")
    g.Name = real.Name .. "_ghost"
    g.Size = real.Size
    g.Anchored = true
    g.CanCollide = false
    g.CanQuery = false
    g.CanTouch = false
    g.Transparency = 1
    g.CFrame = real.CFrame
    g.Parent = workspace
    local b = Instance.new("SelectionBox")
    b.Adornee = g
    b.LineThickness = 0.04
    b.Parent = g
    return { real = real, ghost = g, box = b }
end

local function is_replicate(p) return p and not p.Anchored end
local function is_owner(p) return p and p.ReceiveAge == 0 end

local function StartServerPosition()
    if ServerPosition.Internal.Connection then return end
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildWhichIsA("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then return end
    for _, g in pairs(ServerPosition.Internal.Ghosts) do
        if g.ghost then pcall(function() g.ghost:Destroy() end) end
    end
    ServerPosition.Internal.Ghosts = {}
    for _, n in ipairs(part_names) do
        local p = char:FindFirstChild(n)
        if p and p:IsA("BasePart") then ServerPosition.Internal.Ghosts[n] = make_ghost(p) end
    end
    local server_cf = hrp.CFrame
    local lin_vel = Vector3.new(0, 0, 0)
    local last = os.clock()
    local acc = 0
    local frames = {}
    ServerPosition.Internal.Connection = RunService.Heartbeat:Connect(function(dt)
        if H.ShuttingDown then return end
        if not hrp or not hrp.Parent then
            for _, g in pairs(ServerPosition.Internal.Ghosts) do
                if g.ghost then pcall(function() g.ghost:Destroy() end) end
            end
            ServerPosition.Internal.Ghosts = {}
            if ServerPosition.Internal.Connection then
                ServerPosition.Internal.Connection:Disconnect()
                ServerPosition.Internal.Connection = nil
            end
            return
        end
        local now = os.clock()
        local delta = now - last
        last = now
        local ping = LocalPlayer.GetNetworkPing and LocalPlayer:GetNetworkPing() or 0.08
        if is_replicate(hrp) then
            if is_owner(hrp) then lin_vel = hrp.AssemblyLinearVelocity
            else lin_vel = -hrp.AssemblyLinearVelocity end
            if acc >= ping then
                server_cf = hrp.CFrame
                acc = 0
            else
                acc = acc + delta
            end
        end
        local hrp_cf = server_cf
        local rel = {}
        for n, g in pairs(ServerPosition.Internal.Ghosts) do
            if g.real and g.real.Parent then
                rel[n] = hrp_cf:ToObjectSpace(g.real.CFrame)
            end
        end
        table.insert(frames, { t = now, cf = hrp_cf, pos = hrp_cf.Position, vel = lin_vel, rel = rel })
        if #frames > 240 then
            for i = 1, 60 do table.remove(frames, 1) end
        end
        local target_t = now - ping
        local f
        for i = #frames, 1, -1 do
            if frames[i].t <= target_t then f = frames[i]; break end
        end
        if not f then f = frames[1] end
        if not f then return end
        local td = math.min(target_t - f.t, 0.06)
        local pred_pos = f.pos + f.vel * td * ServerPosition.Settings.Strength
        local pred_cf = CFrame.new(pred_pos) * (f.cf - f.cf.Position)
        for n, g in pairs(ServerPosition.Internal.Ghosts) do
            local ghost = g.ghost
            local box = g.box
            if ghost and ghost.Parent then
                local r = f.rel[n]
                local tgt = r and pred_cf * r or (g.real and g.real.CFrame or ghost.CFrame)
                local d = (tgt.Position - pred_cf.Position).Magnitude
                if d > ServerPosition.Settings.MaxLimb then
                    local dir = (tgt.Position - pred_cf.Position).Unit
                    local p = pred_cf.Position + dir * ServerPosition.Settings.MaxLimb
                    local rx, ry, rz = tgt:ToEulerAnglesXYZ()
                    tgt = CFrame.new(p) * CFrame.Angles(rx, ry, rz)
                end
                ghost.CFrame = ghost.CFrame:Lerp(tgt, math.min(delta * 18, 1))
                if ServerPosition.Settings.RGB then
                    box.Color3 = rgb(now)
                else
                    box.Color3 = Color3.new(1, 1, 1)
                end
            end
        end
    end)
end

local function StopServerPosition()
    if ServerPosition.Internal.Connection then
        ServerPosition.Internal.Connection:Disconnect()
        ServerPosition.Internal.Connection = nil
    end
    for _, g in pairs(ServerPosition.Internal.Ghosts) do
        if g.ghost then pcall(function() g.ghost:Destroy() end) end
    end
    ServerPosition.Internal.Ghosts = {}
end

Track(LocalPlayer.CharacterAdded:Connect(function()
    if ServerPosition.Settings.Enabled then
        task.wait(0.2)
        if H.ShuttingDown then return end
        StopServerPosition()
        StartServerPosition()
    end
end))

ServerPosition.Start = StartServerPosition
ServerPosition.Stop = StopServerPosition
