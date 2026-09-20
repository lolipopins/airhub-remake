--// ============================================================================
--// AirHub — 04_wallhack.lua
--// WallHack boxes (3D / 2D) + Glow + HUD + Self ESP (Chams + China Hat).
--// Requires: 01_core.lua, 02_aimbot.lua (for Locked target color).
--// ============================================================================
local H = getgenv().AirHub
if not H or not H._CoreLoaded then warn("[AirHub] 04_wallhack: core not loaded") return end
if H.WallHack then warn("[AirHub] WallHack already loaded") return end

local Util          = H.Util
local Players       = Util.Players
local RunService    = Util.RunService
local LocalPlayer   = Util.LocalPlayer
local SanitizeColor = Util.SanitizeColor

H.WallHack = {
    Settings = {
        Enabled     = false,
        TeamCheck   = false,
        AliveCheck  = true,
    },
    Visuals = {
        BoxSettings = {
            Enabled      = true,
            Type         = 1,
            Color        = Color3.fromRGB(255, 255, 255),
            TargetColor  = Color3.fromRGB(255, 0, 0),
            Transparency = 0.7,
            Thickness    = 1,
            Filled       = false,
            Increase     = 1,
        },
        GlowSettings = {
            Enabled      = true,
            Color        = Color3.fromRGB(0, 255, 255),
            Transparency = 0.5,
            Mode         = "Outline",
        },
        HUDSettings = {
            Enabled          = false,
            Position         = "TopLeft",
            ShowPlayers      = true,
            ShowFPS          = true,
            ShowPing         = true,
            ShowSession      = true,
            AccentColor      = Color3.fromRGB(90, 140, 255),
            BackColor        = Color3.fromRGB(20, 20, 26),
            TextColor        = Color3.fromRGB(240, 240, 245),
            MutedColor       = Color3.fromRGB(150, 150, 165),
            BackTransparency = 0.15,
        },
        SelfESP = {
            Enabled = false,
            Chams = {
                Enabled             = false,
                Mode                = "Both",
                FillColor           = Color3.fromRGB(90, 140, 255),
                FillTransparency    = 0.4,
                OutlineColor        = Color3.fromRGB(255, 255, 255),
                OutlineTransparency = 0.0,
                AlwaysOnTop         = true,
            },
            ChinaHat = {
                Enabled      = false,
                Color        = Color3.fromRGB(255, 60, 60),
                Material     = "Neon",
                Size         = 4,
                OffsetY      = 1.8,
                Transparency = 0,
                Rotation     = 0,
            },
        },
    },
    Internal = {
        HUD = {
            Elements     = {},
            Conn         = nil,
            Frames       = 0,
            LastSample   = tick(),
            CurrentFps   = 0,
            SessionStart = tick(),
            Visible      = false,
            W            = 230,
            H            = 84,
        },
        SelfESP = {
            Highlight = nil,
            HatPart   = nil,
            HatHead   = nil,
            HatConn   = nil,
            CharConn  = nil,
        },
    },
    WrappedPlayers = {},
}
local WallHack = H.WallHack

local WHConnections = {}
local ReWrapRunning = false

--// ===========================================================================
--// Color helpers (kept as public API, but UI now uses colorpickers)
--// ===========================================================================
local function colorToHex(c)
    return string.format("#%02X%02X%02X",
        math.floor(c.R * 255 + 0.5),
        math.floor(c.G * 255 + 0.5),
        math.floor(c.B * 255 + 0.5))
end

local function parseHex(s)
    s = tostring(s or ""):gsub("^#", "")
    if #s ~= 6 then return nil end
    local r = tonumber(s:sub(1, 2), 16)
    local g = tonumber(s:sub(3, 4), 16)
    local b = tonumber(s:sub(5, 6), 16)
    if not r or not g or not b then return nil end
    return Color3.fromRGB(r, g, b)
end

--// ===========================================================================
--// HUD — helpers
--// ===========================================================================
local function hudNewText(size, font)
    local t = Drawing.new("Text")
    t.Font    = font or 2
    t.Size    = size or 14
    t.Outline = true
    t.Center  = false
    t.Visible = false
    return t
end

local function hudEnsureElements()
    local HUD = WallHack.Internal.HUD
    if HUD.Elements.bg then return true end
    local ok = pcall(function()
        local S = WallHack.Visuals.HUDSettings

        local bg = Drawing.new("Square")
        bg.Filled       = true
        bg.Outline      = false
        bg.Color        = S.BackColor
        bg.Transparency = S.BackTransparency
        pcall(function() bg.Rounding = 8 end)
        bg.Visible      = false
        HUD.Elements.bg = bg

        local accent = Drawing.new("Square")
        accent.Filled       = true
        accent.Outline      = false
        accent.Color        = S.AccentColor
        accent.Transparency = 0
        pcall(function() accent.Rounding = 4 end)
        accent.Visible      = false
        HUD.Elements.accent = accent
    end)
    if not ok then return false end

    HUD.Elements.title    = hudNewText(16, 2)
    HUD.Elements.subtitle = hudNewText(11, 1)
    HUD.Elements.line1    = hudNewText(13, 2)
    HUD.Elements.line2    = hudNewText(13, 2)
    return true
end

local function hudHideAll()
    for _, e in pairs(WallHack.Internal.HUD.Elements) do
        pcall(function() e.Visible = false end)
    end
end

local function hudShowAll()
    for _, e in pairs(WallHack.Internal.HUD.Elements) do
        pcall(function() e.Visible = true end)
    end
end

local function hudGetPosition()
    local HUD = WallHack.Internal.HUD
    local vp  = workspace.CurrentCamera.ViewportSize
    local pos = WallHack.Visuals.HUDSettings.Position or "TopLeft"
    local pad = 18
    if pos == "TopLeft"     then return Vector2.new(pad, pad) end
    if pos == "TopRight"    then return Vector2.new(vp.X - HUD.W - pad, pad) end
    if pos == "BottomLeft"  then return Vector2.new(pad, vp.Y - HUD.H - pad) end
    if pos == "BottomRight" then return Vector2.new(vp.X - HUD.W - pad, vp.Y - HUD.H - pad) end
    return Vector2.new(pad, pad)
end

local function hudFmtTime(sec)
    sec = math.floor(sec)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if h > 0 then return string.format("%dh %02dm", h, m) end
    if m > 0 then return string.format("%dm %02ds", m, s) end
    return string.format("%ds", s)
end

local function hudUpdate()
    if H.ShuttingDown then return end
    local HUD = WallHack.Internal.HUD
    local S   = WallHack.Visuals.HUDSettings

    if not S.Enabled then
        if HUD.Visible then hudHideAll(); HUD.Visible = false end
        return
    end
    if not hudEnsureElements() then return end
    if not HUD.Visible then hudShowAll(); HUD.Visible = true end

    local pos      = hudGetPosition()
    local paddingX = 14

    local bg = HUD.Elements.bg
    bg.Size         = Vector2.new(HUD.W, HUD.H)
    bg.Position     = pos
    bg.Color        = S.BackColor
    bg.Transparency = S.BackTransparency

    local accent = HUD.Elements.accent
    accent.Size     = Vector2.new(4, HUD.H)
    accent.Position = pos
    accent.Color    = S.AccentColor

    local title = HUD.Elements.title
    title.Text     = "AirHub"
    title.Color    = S.TextColor
    title.Position = Vector2.new(pos.X + paddingX, pos.Y + 7)

    local subtitle = HUD.Elements.subtitle
    subtitle.Text     = "▸ connected"
    subtitle.Color    = S.MutedColor
    subtitle.Position = Vector2.new(pos.X + paddingX + 66, pos.Y + 12)

    local parts1 = {}
    if S.ShowPlayers then table.insert(parts1, string.format("Players  %d", #Players:GetPlayers())) end
    if S.ShowFPS     then table.insert(parts1, string.format("FPS  %d", HUD.CurrentFps)) end
    local line1 = HUD.Elements.line1
    line1.Text     = table.concat(parts1, "     ")
    line1.Color    = S.TextColor
    line1.Position = Vector2.new(pos.X + paddingX, pos.Y + 36)

    local parts2 = {}
    if S.ShowPing then
        local ping = math.floor(LocalPlayer:GetNetworkPing() * 1000 + 0.5)
        table.insert(parts2, string.format("Ping  %d ms", ping))
    end
    if S.ShowSession then
        table.insert(parts2, string.format("Session  %s", hudFmtTime(tick() - HUD.SessionStart)))
    end
    local line2 = HUD.Elements.line2
    line2.Text     = table.concat(parts2, "     ")
    line2.Color    = S.MutedColor
    line2.Position = Vector2.new(pos.X + paddingX, pos.Y + 58)

    HUD.Frames += 1
    local now = tick()
    if now - HUD.LastSample >= 1 then
        HUD.CurrentFps = math.floor(HUD.Frames / (now - HUD.LastSample) + 0.5)
        HUD.Frames = 0
        HUD.LastSample = now
    end
end

local function StartHUD()
    local HUD = WallHack.Internal.HUD
    if HUD.Conn then return end
    HUD.SessionStart = tick()
    HUD.Conn = RunService.RenderStepped:Connect(hudUpdate)
end

local function StopHUD()
    local HUD = WallHack.Internal.HUD
    if HUD.Conn then
        pcall(function() HUD.Conn:Disconnect() end)
        HUD.Conn = nil
    end
    for key, e in pairs(HUD.Elements) do
        if e and e.Remove then pcall(function() e:Remove() end) end
    end
    HUD.Elements = {}
    HUD.Visible  = false
end

--// ===========================================================================
--// Self ESP — Chams + China Hat
--// ===========================================================================
local function applyChamsProps(hl)
    local C = WallHack.Visuals.SelfESP.Chams
    hl.FillColor    = C.FillColor
    hl.OutlineColor = C.OutlineColor
    local fillVisible    = (C.Mode == "Fill"    or C.Mode == "Both")
    local outlineVisible = (C.Mode == "Outline" or C.Mode == "Both")
    hl.FillTransparency    = fillVisible    and C.FillTransparency    or 1
    hl.OutlineTransparency = outlineVisible and C.OutlineTransparency or 1
    hl.DepthMode = C.AlwaysOnTop
        and Enum.HighlightDepthMode.AlwaysOnTop
        or  Enum.HighlightDepthMode.Occluded
end

local function applyChams(char)
    if not char then return end
    local Se = WallHack.Internal.SelfESP
    if Se.Highlight and Se.Highlight.Parent then
        applyChamsProps(Se.Highlight)
        Se.Highlight.Adornee = char
        return
    end
    local hl = Instance.new("Highlight")
    hl.Name    = "AirHubSelfChams"
    hl.Adornee = char
    applyChamsProps(hl)
    hl.Parent = char
    Se.Highlight = hl
end

local function removeChams()
    local Se = WallHack.Internal.SelfESP
    if Se.Highlight then
        pcall(function() Se.Highlight:Destroy() end)
        Se.Highlight = nil
    end
end

--// --- China Hat ---
--// Anchored part + RenderStepped CFrame update. Bulletproof vs weld physics.
local function stopHatLoop()
    local Se = WallHack.Internal.SelfESP
    if Se.HatConn then
        pcall(function() Se.HatConn:Disconnect() end)
        Se.HatConn = nil
    end
end

local function removeChinaHat()
    stopHatLoop()
    local Se = WallHack.Internal.SelfESP
    if Se.HatPart then
        pcall(function() Se.HatPart:Destroy() end)
        Se.HatPart = nil
    end
    Se.HatHead = nil
end

local function startHatLoop()
    local Se = WallHack.Internal.SelfESP
    if Se.HatConn then return end
    Se.HatConn = RunService.RenderStepped:Connect(function()
        if H.ShuttingDown then return end
        local hat  = Se.HatPart
        local head = Se.HatHead
        if not hat or not hat.Parent then return end
        if not head or not head.Parent then return end
        local C = WallHack.Visuals.SelfESP.ChinaHat
        local rot = CFrame.Angles(0, math.rad(C.Rotation or 0), 0)
        hat.CFrame = head.CFrame * CFrame.new(0, C.OffsetY, 0) * rot
    end)
end

local function applyChinaHat()
    local char = LocalPlayer.Character
    if not char then return end
    local head = char:FindFirstChild("Head")
    if not head then return end

    local Se = WallHack.Internal.SelfESP
    local C  = WallHack.Visuals.SelfESP.ChinaHat

    --// Update existing hat
    if Se.HatPart and Se.HatPart.Parent then
        Se.HatPart.Color        = C.Color
        Se.HatPart.Transparency = C.Transparency
        Se.HatPart.Material     = Enum.Material[C.Material] or Enum.Material.Neon
        local mesh = Se.HatPart:FindFirstChildOfClass("SpecialMesh")
        if mesh then
            mesh.Scale = Vector3.new(C.Size, C.Size * 0.7, C.Size)
        end
        Se.HatHead = head
        startHatLoop()
        return
    end

    --// Fresh creation
    local hat = Instance.new("Part")
    hat.Name        = "AirHubChinaHat"
    hat.Size        = Vector3.new(1, 1, 1)
    hat.Anchored    = true       --// prevents physics from fighting us
    hat.CanCollide  = false
    hat.CanQuery    = false
    hat.CanTouch    = false
    hat.Massless    = true
    hat.CastShadow  = false
    hat.Color       = C.Color
    hat.Material    = Enum.Material[C.Material] or Enum.Material.Neon
    hat.Transparency = C.Transparency
    hat.CFrame      = head.CFrame * CFrame.new(0, C.OffsetY, 0)

    local mesh = Instance.new("SpecialMesh")
    mesh.MeshType = Enum.MeshType.Pyramid
    mesh.Scale    = Vector3.new(C.Size, C.Size * 0.7, C.Size)
    mesh.Parent   = hat

    hat.Parent = char

    Se.HatPart = hat
    Se.HatHead = head
    startHatLoop()
end

local function refreshSelfESP()
    local char = LocalPlayer.Character
    if not char then
        removeChams()
        removeChinaHat()
        return
    end
    if WallHack.Visuals.SelfESP.Chams.Enabled    then applyChams(char) else removeChams()   end
    if WallHack.Visuals.SelfESP.ChinaHat.Enabled then applyChinaHat()  else removeChinaHat() end
end

local function StartSelfESP()
    local Se = WallHack.Internal.SelfESP
    if Se.CharConn then return end
    Se.CharConn = LocalPlayer.CharacterAdded:Connect(function()
        task.wait(0.5)
        if WallHack.Visuals.SelfESP.Enabled then refreshSelfESP() end
    end)
    refreshSelfESP()
end

local function StopSelfESP()
    local Se = WallHack.Internal.SelfESP
    if Se.CharConn then
        pcall(function() Se.CharConn:Disconnect() end)
        Se.CharConn = nil
    end
    removeChams()
    removeChinaHat()
end

--// ===========================================================================
--// Original WallHack logic (boxes + glow)
--// ===========================================================================
local function GetPlayerTable(plr)
    if not plr then return nil end
    return WallHack.WrappedPlayers[plr.Name]
end

local function ApplyGlowForPlayer(plr)
    local data = GetPlayerTable(plr)
    if not data then return end
    if WallHack.Settings.Enabled and WallHack.Visuals.GlowSettings.Enabled then
        local char = plr.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
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
            local gs        = WallHack.Visuals.GlowSettings
            local safeColor = SanitizeColor(gs.Color)
            local safeTrans = math.clamp(tonumber(gs.Transparency) or 0.5, 0, 1)
            local mode      = gs.Mode or "Outline"
            if mode == "Outline" then
                data.Glow.FillTransparency    = 1
                data.Glow.OutlineTransparency = safeTrans
                data.Glow.FillColor    = safeColor
                data.Glow.OutlineColor = safeColor
            elseif mode == "Fill" then
                data.Glow.FillTransparency    = safeTrans
                data.Glow.OutlineTransparency = 1
                data.Glow.FillColor    = safeColor
                data.Glow.OutlineColor = safeColor
            elseif mode == "Both" then
                data.Glow.FillTransparency    = safeTrans * 0.5
                data.Glow.OutlineTransparency = safeTrans * 0.5
                data.Glow.FillColor    = safeColor
                data.Glow.OutlineColor = safeColor
            elseif mode == "Pulse" then
                local pulse = (math.sin(tick() * 2) + 1) / 2
                local r = math.clamp(safeColor.R * (0.5 + pulse * 0.5), 0, 1)
                local g = math.clamp(safeColor.G * (0.5 + pulse * 0.5), 0, 1)
                local b = math.clamp(safeColor.B * (0.5 + pulse * 0.5), 0, 1)
                local pulsed = Color3.new(r, g, b)
                data.Glow.FillColor    = pulsed
                data.Glow.OutlineColor = pulsed
                data.Glow.FillTransparency    = safeTrans * (0.5 + pulse * 0.5)
                data.Glow.OutlineTransparency = safeTrans * (0.5 + pulse * 0.5)
            else
                data.Glow.FillTransparency    = 1
                data.Glow.OutlineTransparency = safeTrans
                data.Glow.FillColor    = safeColor
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
        Square          = Drawing.new("Square"),
        TopLeftLine     = Drawing.new("Line"),
        TopRightLine    = Drawing.new("Line"),
        BottomLeftLine  = Drawing.new("Line"),
        BottomRightLine = Drawing.new("Line"),
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
        local size  = char.HumanoidRootPart.Size * WallHack.Visuals.BoxSettings.Increase
        local posTL = workspace.CurrentCamera:WorldToViewportPoint((hrpCF * CFrame.new( size.X,  size.Y, 0)).Position)
        local posTR = workspace.CurrentCamera:WorldToViewportPoint((hrpCF * CFrame.new(-size.X,  size.Y, 0)).Position)
        local posBL = workspace.CurrentCamera:WorldToViewportPoint((hrpCF * CFrame.new( size.X, -size.Y - 0.5, 0)).Position)
        local posBR = workspace.CurrentCamera:WorldToViewportPoint((hrpCF * CFrame.new(-size.X, -size.Y - 0.5, 0)).Position)

        if WallHack.Visuals.BoxSettings.Type == 2 then
            t.Box.Square.Visible = true
            for k, v in pairs(t.Box) do if k ~= "Square" then v.Visible = false end end
            t.Box.Square.Thickness    = WallHack.Visuals.BoxSettings.Thickness
            t.Box.Square.Color        = boxColor
            t.Box.Square.Transparency = WallHack.Visuals.BoxSettings.Transparency
            t.Box.Square.Filled       = WallHack.Visuals.BoxSettings.Filled
            local headY = workspace.CurrentCamera:WorldToViewportPoint(char.Head.Position + Vector3.new(0, 0.5, 0)).Y
            local legY  = workspace.CurrentCamera:WorldToViewportPoint(char.HumanoidRootPart.Position - Vector3.new(0, 3, 0)).Y
            t.Box.Square.Size     = Vector2.new(2000 / vec.Z, headY - legY)
            t.Box.Square.Position = Vector2.new(vec.X - t.Box.Square.Size.X / 2, vec.Y - t.Box.Square.Size.Y / 2)
        else
            t.Box.Square.Visible = false
            for _, ln in pairs({ "TopLeftLine", "TopRightLine", "BottomLeftLine", "BottomRightLine" }) do
                t.Box[ln].Visible      = true
                t.Box[ln].Thickness    = WallHack.Visuals.BoxSettings.Thickness
                t.Box[ln].Transparency = WallHack.Visuals.BoxSettings.Transparency
                t.Box[ln].Color        = boxColor
            end
            t.Box.TopLeftLine.From,     t.Box.TopLeftLine.To     = Vector2.new(posTL.X, posTL.Y), Vector2.new(posTR.X, posTR.Y)
            t.Box.TopRightLine.From,    t.Box.TopRightLine.To    = Vector2.new(posTR.X, posTR.Y), Vector2.new(posBR.X, posBR.Y)
            t.Box.BottomLeftLine.From,  t.Box.BottomLeftLine.To  = Vector2.new(posBL.X, posBL.Y), Vector2.new(posTL.X, posTL.Y)
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
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if char and hum then
            t.Checks.Alive = WallHack.Settings.AliveCheck and hum.Health > 0 or not WallHack.Settings.AliveCheck
            t.Checks.Team  = not WallHack.Settings.TeamCheck
                or (LocalPlayer.Team and plr.Team and LocalPlayer.Team ~= plr.Team)
        else
            t.Checks.Alive = false
            t.Checks.Team  = false
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
        local val = {
            Name = plr.Name,
            Checks = { Alive = true, Team = true },
            Connections = {},
            Box = {},
        }
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
    for _, c in pairs(v.Connections) do pcall(function() c:Disconnect() end) end
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

--// ===========================================================================
--// Public API
--// ===========================================================================
WallHack.Functions = {
    Exit = function()
        ReWrapRunning = false
        for _, v in pairs(WHConnections) do pcall(function() v:Disconnect() end) end
        for _, v in pairs(Players:GetPlayers()) do
            if v ~= LocalPlayer then UnWrap(v) end
        end
        StopHUD()
        StopSelfESP()
    end,

    Restart = function()
        ReWrapRunning = false
        for _, v in pairs(WHConnections) do pcall(function() v:Disconnect() end) end
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
            Enabled = true, Color = Color3.fromRGB(0, 255, 255), Transparency = 0.5, Mode = "Outline",
        }
        WallHack.Visuals.HUDSettings = {
            Enabled = false, Position = "TopLeft",
            ShowPlayers = true, ShowFPS = true, ShowPing = true, ShowSession = true,
            AccentColor = Color3.fromRGB(90, 140, 255),
            BackColor = Color3.fromRGB(20, 20, 26),
            TextColor = Color3.fromRGB(240, 240, 245),
            MutedColor = Color3.fromRGB(150, 150, 165),
            BackTransparency = 0.15,
        }
        WallHack.Visuals.SelfESP = {
            Enabled = false,
            Chams = {
                Enabled = false, Mode = "Both",
                FillColor = Color3.fromRGB(90, 140, 255), FillTransparency = 0.4,
                OutlineColor = Color3.fromRGB(255, 255, 255), OutlineTransparency = 0.0,
                AlwaysOnTop = true,
            },
            ChinaHat = {
                Enabled = false, Color = Color3.fromRGB(255, 60, 60),
                Material = "Neon", Size = 4, OffsetY = 1.8, Transparency = 0, Rotation = 0,
            },
        }
        ApplyGlowToAll()
        StopHUD()
        StopSelfESP()
    end,

    StartHUD = StartHUD,
    StopHUD  = StopHUD,
    SetHUDEnabled = function(v)
        WallHack.Visuals.HUDSettings.Enabled = v
        if v then StartHUD() else StopHUD() end
    end,

    StartSelfESP   = StartSelfESP,
    StopSelfESP    = StopSelfESP,
    RefreshSelfESP = refreshSelfESP,

    --// Hex helpers (kept as public API even though UI uses colorpickers now)
    ParseHex   = parseHex,
    ColorToHex = colorToHex,
}

WallHack.ApplyGlowToAll     = ApplyGlowToAll
WallHack.ApplyGlowForPlayer = ApplyGlowForPlayer
