--// ============================================================================
--// AirHub — 04_wallhack.lua
--//  WallHack boxes (3D / 2D) + Glow (Highlight).
--//  Requires: 01_core.lua, 02_aimbot.lua (for Locked target color).
--// ============================================================================

local H = getgenv().AirHub
if not H or not H._CoreLoaded then
    warn("[AirHub] 04_wallhack: core not loaded")
    return
end
if H.WallHack then
    warn("[AirHub] WallHack already loaded")
    return
end

local Util = H.Util
local Players = Util.Players
local RunService = Util.RunService
local LocalPlayer = Util.LocalPlayer
local SanitizeColor = Util.SanitizeColor

H.WallHack = {
    Settings = { Enabled = false, TeamCheck = false, AliveCheck = true },
    Visuals = {
        BoxSettings = {
            Enabled = true, Type = 1,
            Color = Color3.fromRGB(255, 255, 255), TargetColor = Color3.fromRGB(255, 0, 0),
            Transparency = 0.7, Thickness = 1, Filled = false, Increase = 1,
        },
        GlowSettings = {
            Enabled = true, Color = Color3.fromRGB(0, 255, 255),
            Transparency = 0.5, Mode = "Outline",
        },
    },
    WrappedPlayers = {},
}

local WallHack = H.WallHack

local WHConnections = {}
local ReWrapRunning = false

local function GetPlayerTable(plr)
    if not plr then return nil end
    return WallHack.WrappedPlayers[plr.Name]
end

local function ApplyGlowForPlayer(plr)
    local data = GetPlayerTable(plr)
    if not data then return end
    if WallHack.Settings.Enabled and WallHack.Visuals.GlowSettings.Enabled then
        local char = plr.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if char and hum and hum.Health > 0 then
            if not data.Glow or not data.Glow.Parent then
                if data.Glow then pcall(function() data.Glow:Destroy() end) end
                local highlight = Instance.new("Highlight")
                highlight.Name = "AirHub_Glow"
                highlight.Adornee = char
                highlight.Parent = char
                highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                data.Glow = highlight
            end
            data.Glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

            local gs = WallHack.Visuals.GlowSettings
            local safeColor = SanitizeColor(gs.Color)
            local safeTrans = math.clamp(tonumber(gs.Transparency) or 0.5, 0, 1)
            local mode = gs.Mode or "Outline"

            if mode == "Outline" then
                data.Glow.FillTransparency = 1
                data.Glow.OutlineTransparency = safeTrans
                data.Glow.FillColor = safeColor
                data.Glow.OutlineColor = safeColor
            elseif mode == "Fill" then
                data.Glow.FillTransparency = safeTrans
                data.Glow.OutlineTransparency = 1
                data.Glow.FillColor = safeColor
                data.Glow.OutlineColor = safeColor
            elseif mode == "Both" then
                data.Glow.FillTransparency = safeTrans * 0.5
                data.Glow.OutlineTransparency = safeTrans * 0.5
                data.Glow.FillColor = safeColor
                data.Glow.OutlineColor = safeColor
            elseif mode == "Pulse" then
                local pulse = (math.sin(tick() * 2) + 1) / 2
                local r = math.clamp(safeColor.R * (0.5 + pulse * 0.5), 0, 1)
                local g = math.clamp(safeColor.G * (0.5 + pulse * 0.5), 0, 1)
                local b = math.clamp(safeColor.B * (0.5 + pulse * 0.5), 0, 1)
                local pulsed = Color3.new(r, g, b)
                data.Glow.FillColor = pulsed
                data.Glow.OutlineColor = pulsed
                data.Glow.FillTransparency = safeTrans * (0.5 + pulse * 0.5)
                data.Glow.OutlineTransparency = safeTrans * (0.5 + pulse * 0.5)
            else
                data.Glow.FillTransparency = 1
                data.Glow.OutlineTransparency = safeTrans
                data.Glow.FillColor = safeColor
                data.Glow.OutlineColor = safeColor
            end
        elseif data.Glow then
            pcall(function() data.Glow:Destroy() end)
            data.Glow = nil
        end
    elseif data.Glow then
        pcall(function() data.Glow:Destroy() end)
        data.Glow = nil
    end
end

local function ApplyGlowToAll()
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then ApplyGlowForPlayer(plr) end
    end
end

local function AddBox(plr)
    local t = GetPlayerTable(plr)
    if not t then return end
    t.Box = {
        Square = Drawing.new("Square"),
        TopLeftLine = Drawing.new("Line"), TopRightLine = Drawing.new("Line"),
        BottomLeftLine = Drawing.new("Line"), BottomRightLine = Drawing.new("Line"),
    }
    t.Connections.Box = RunService.RenderStepped:Connect(function()
        if H.ShuttingDown then return end
        if not WallHack.Settings.Enabled or not WallHack.Visuals.BoxSettings.Enabled then
            for _, v in pairs(t.Box) do v.Visible = false end
            return
        end
        local char = plr.Character
        if not char or not char:FindFirstChild("HumanoidRootPart") or not char:FindFirstChild("Head") then
            for _, v in pairs(t.Box) do v.Visible = false end
            return
        end
        local vec, onScreen = workspace.CurrentCamera:WorldToViewportPoint(char.HumanoidRootPart.Position)
        if not onScreen or not t.Checks.Alive or not t.Checks.Team then
            for _, v in pairs(t.Box) do v.Visible = false end
            return
        end
        local isTarget = (H.Aimbot and H.Aimbot.Locked == plr)
        local boxColor = isTarget and SanitizeColor(WallHack.Visuals.BoxSettings.TargetColor)
            or SanitizeColor(WallHack.Visuals.BoxSettings.Color)
        local hrpCF = char.HumanoidRootPart.CFrame
        local size = char.HumanoidRootPart.Size * WallHack.Visuals.BoxSettings.Increase
        local posTL = workspace.CurrentCamera:WorldToViewportPoint((hrpCF * CFrame.new(size.X, size.Y, 0)).Position)
        local posTR = workspace.CurrentCamera:WorldToViewportPoint((hrpCF * CFrame.new(-size.X, size.Y, 0)).Position)
        local posBL = workspace.CurrentCamera:WorldToViewportPoint((hrpCF * CFrame.new(size.X, -size.Y - 0.5, 0)).Position)
        local posBR = workspace.CurrentCamera:WorldToViewportPoint((hrpCF * CFrame.new(-size.X, -size.Y - 0.5, 0)).Position)
        if WallHack.Visuals.BoxSettings.Type == 2 then
            t.Box.Square.Visible = true
            for k, v in pairs(t.Box) do if k ~= "Square" then v.Visible = false end end
            t.Box.Square.Thickness = WallHack.Visuals.BoxSettings.Thickness
            t.Box.Square.Color = boxColor
            t.Box.Square.Transparency = WallHack.Visuals.BoxSettings.Transparency
            t.Box.Square.Filled = WallHack.Visuals.BoxSettings.Filled
            local headY = workspace.CurrentCamera:WorldToViewportPoint(char.Head.Position + Vector3.new(0, 0.5, 0)).Y
            local legY = workspace.CurrentCamera:WorldToViewportPoint(char.HumanoidRootPart.Position - Vector3.new(0, 3, 0)).Y
            t.Box.Square.Size = Vector2.new(2000 / vec.Z, headY - legY)
            t.Box.Square.Position = Vector2.new(vec.X - t.Box.Square.Size.X / 2, vec.Y - t.Box.Square.Size.Y / 2)
        else
            t.Box.Square.Visible = false
            for _, ln in pairs({ "TopLeftLine", "TopRightLine", "BottomLeftLine", "BottomRightLine" }) do
                t.Box[ln].Visible = true
                t.Box[ln].Thickness = WallHack.Visuals.BoxSettings.Thickness
                t.Box[ln].Transparency = WallHack.Visuals.BoxSettings.Transparency
                t.Box[ln].Color = boxColor
            end
            t.Box.TopLeftLine.From, t.Box.TopLeftLine.To = Vector2.new(posTL.X, posTL.Y), Vector2.new(posTR.X, posTR.Y)
            t.Box.TopRightLine.From, t.Box.TopRightLine.To = Vector2.new(posTR.X, posTR.Y), Vector2.new(posBR.X, posBR.Y)
            t.Box.BottomLeftLine.From, t.Box.BottomLeftLine.To = Vector2.new(posBL.X, posBL.Y), Vector2.new(posTL.X, posTL.Y)
            t.Box.BottomRightLine.From, t.Box.BottomRightLine.To = Vector2.new(posBR.X, posBR.Y), Vector2.new(posBL.X, posBL.Y)
        end
    end)
end

local function InitChecks(plr)
    local t = GetPlayerTable(plr)
    if not t then return end
    t.Connections.UpdateChecks = RunService.RenderStepped:Connect(function()
        if H.ShuttingDown then return end
        local char = plr.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if char and hum then
            t.Checks.Alive = WallHack.Settings.AliveCheck and hum.Health > 0 or not WallHack.Settings.AliveCheck
            t.Checks.Team = not WallHack.Settings.TeamCheck or (LocalPlayer.Team and plr.Team and LocalPlayer.Team ~= plr.Team)
        else
            t.Checks.Alive = false
            t.Checks.Team = false
        end
        ApplyGlowForPlayer(plr)
    end)
end

local function AssignRigType(plr)
    local t = GetPlayerTable(plr)
    if not t then return end
    task.spawn(function()
        repeat task.wait() until H.ShuttingDown or plr.Character
        if H.ShuttingDown then return end
        local char = plr.Character
        if char:FindFirstChild("Torso") and not char:FindFirstChild("LowerTorso") then
            t.RigType = "R6"
        elseif char:FindFirstChild("LowerTorso") then
            t.RigType = "R15"
        else
            AssignRigType(plr)
        end
    end)
end

local function Wrap(plr)
    if not GetPlayerTable(plr) then
        local val = { Name = plr.Name, Checks = { Alive = true, Team = true }, Connections = {}, Box = {} }
        WallHack.WrappedPlayers[plr.Name] = val
        AssignRigType(plr)
        InitChecks(plr)
        AddBox(plr)
        ApplyGlowForPlayer(plr)
        val.CharacterAddedConn = plr.CharacterAdded:Connect(function()
            if H.ShuttingDown then return end
            ApplyGlowForPlayer(plr)
        end)
    end
end

local function UnWrap(plr)
    local v = WallHack.WrappedPlayers[plr.Name]
    if not v then return end
    for _, c in pairs(v.Connections) do
        pcall(function() c:Disconnect() end)
    end
    if v.CharacterAddedConn then pcall(function() v.CharacterAddedConn:Disconnect() end) end
    for _, b in pairs(v.Box) do
        if b and b.Remove then pcall(function() b:Remove() end) end
    end
    if v.Glow then pcall(function() v.Glow:Destroy() end) end
    WallHack.WrappedPlayers[plr.Name] = nil
end

local function StartReWrapLoop()
    if ReWrapRunning then return end
    ReWrapRunning = true
    task.spawn(function()
        while ReWrapRunning and not H.ShuttingDown do
            for _, v in pairs(Players:GetPlayers()) do
                if v ~= LocalPlayer then Wrap(v) end
            end
            task.wait(30)
        end
    end)
end

local function LoadWH()
    WHConnections.PlayerAdded = Players.PlayerAdded:Connect(function(plr)
        if not H.ShuttingDown then Wrap(plr) end
    end)
    WHConnections.PlayerRemoving = Players.PlayerRemoving:Connect(function(plr)
        if not H.ShuttingDown then UnWrap(plr) end
    end)
    StartReWrapLoop()
end
LoadWH()

WallHack.Functions = {
    Exit = function()
        ReWrapRunning = false
        for _, v in pairs(WHConnections) do
            pcall(function() v:Disconnect() end)
        end
        for _, v in pairs(Players:GetPlayers()) do
            if v ~= LocalPlayer then UnWrap(v) end
        end
    end,
    Restart = function()
        ReWrapRunning = false
        for _, v in pairs(WHConnections) do
            pcall(function() v:Disconnect() end)
        end
        LoadWH()
    end,
    ResetSettings = function()
        WallHack.Settings = { Enabled = false, TeamCheck = false, AliveCheck = true }
        WallHack.Visuals.BoxSettings = {
            Enabled = true, Type = 1,
            Color = Color3.fromRGB(255, 255, 255), TargetColor = Color3.fromRGB(255, 0, 0),
            Transparency = 0.7, Thickness = 1, Filled = false, Increase = 1,
        }
        WallHack.Visuals.GlowSettings = {
            Enabled = true, Color = Color3.fromRGB(0, 255, 255),
            Transparency = 0.5, Mode = "Outline",
        }
        ApplyGlowToAll()
    end,
}

WallHack.ApplyGlowToAll = ApplyGlowToAll
WallHack.ApplyGlowForPlayer = ApplyGlowForPlayer
