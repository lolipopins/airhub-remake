--// ============================================================================
--// AirHub — 04_wallhack.lua (bulletproof build — patched 4)
--// H.WallHack schema is created FIRST.
--//
--// Patch notes (2026-09-24):
--//   [FIX-1..16]  (see r1/r2 changelog)
--//
--// Patch notes (2026-09-24 — r3):
--//   [FIX-17] HatPart parented to workspace/AirHub_SelfESP.
--//   [FIX-18] Loop forces LocalTransparencyModifier=0 + Color + Transparency.
--//   [FIX-19] Loop self-heals stale refs.
--//   [FIX-20] Loop forces Anchored=true every frame.
--//
--// Patch notes (2026-09-24 — r4):  **ChinaHat RENDERS fix**
--//   [FIX-21] Replaced SpecialMesh.Pyramid (legacy, doesn't render on modern
--//            clients) with a native Part.Shape = Ball (squashed ellipsoid).
--//   [FIX-22] Loop forces Shape=Ball + Size every frame.
--//   [FIX-23] Added DebugHat() diagnostic helper.
--// ============================================================================
local H = getgenv().AirHub
if not H or not H._CoreLoaded then warn("[AirHub] 04_wallhack: core not loaded") return end
if H.WallHack and H.WallHack._Loaded then return end

--// ---------------------------------------------------------------------------
--// 1) Schema
--// ---------------------------------------------------------------------------
H.WallHack = H.WallHack or {}
local WallHack = H.WallHack
WallHack._Loaded = true

WallHack.Settings = WallHack.Settings or {
    Enabled    = false,
    TeamCheck  = false,
    AliveCheck = true,
}

WallHack.Visuals = WallHack.Visuals or {}
WallHack.Visuals.BoxSettings = WallHack.Visuals.BoxSettings or {
    Enabled = true, Type = 1,
    Color = Color3.fromRGB(255, 255, 255),
    TargetColor = Color3.fromRGB(255, 0, 0),
    Transparency = 0.7, Thickness = 1,
    Filled = false, Increase = 1,
}
WallHack.Visuals.GlowSettings = WallHack.Visuals.GlowSettings or {
    Enabled = true,
    Color = Color3.fromRGB(0, 255, 255),
    Transparency = 0.5,
    Mode = "Outline",
}
WallHack.Visuals.HUDSettings = WallHack.Visuals.HUDSettings or {
    Enabled = false, Position = "TopLeft",
    ShowPlayers = true, ShowFPS = true, ShowPing = true, ShowSession = true,
    AccentColor = Color3.fromRGB(90, 140, 255),
    BackColor = Color3.fromRGB(20, 20, 26),
    TextColor = Color3.fromRGB(240, 240, 245),
    MutedColor = Color3.fromRGB(150, 150, 165),
    BackTransparency = 0.15,
}
WallHack.Visuals.SelfESP = WallHack.Visuals.SelfESP or {
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
WallHack.Internal = WallHack.Internal or {
    HUD = {
        Elements = {}, Conn = nil, Frames = 0,
        LastSample = os.clock(), CurrentFps = 0,
        SessionStart = os.clock(), Visible = false,
        W = 230, H = 84,
    },
    SelfESP = {
        Highlight = nil, HatPart = nil, HatHead = nil,
        HatConn = nil, CharConn = nil, HatFolder = nil,
    },
}
WallHack.WrappedPlayers = WallHack.WrappedPlayers or {}
WallHack.Functions      = WallHack.Functions      or {}

--// Defaults
local DEFAULT_SETTINGS = { Enabled = false, TeamCheck = false, AliveCheck = true }
local DEFAULT_BOX = {
    Enabled = true, Type = 1,
    Color = Color3.fromRGB(255, 255, 255), TargetColor = Color3.fromRGB(255, 0, 0),
    Transparency = 0.7, Thickness = 1, Filled = false, Increase = 1,
}
local DEFAULT_GLOW = {
    Enabled = true, Color = Color3.fromRGB(0, 255, 255), Transparency = 0.5, Mode = "Outline",
}
local DEFAULT_HUD = {
    Enabled = false, Position = "TopLeft",
    ShowPlayers = true, ShowFPS = true, ShowPing = true, ShowSession = true,
    AccentColor = Color3.fromRGB(90, 140, 255),
    BackColor = Color3.fromRGB(20, 20, 26),
    TextColor = Color3.fromRGB(240, 240, 245),
    MutedColor = Color3.fromRGB(150, 150, 165),
    BackTransparency = 0.15,
}
local DEFAULT_SELFESP = {
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

--// ---------------------------------------------------------------------------
--// 2) Init
--// ---------------------------------------------------------------------------
local okInit, errInit = pcall(function()

    local Util = H.Util
    if not Util then error("H.Util missing") end

    local Players       = Util.Players
    local RunService    = Util.RunService
    local LocalPlayer   = Util.LocalPlayer
    local SanitizeColor = Util.SanitizeColor or function(c) return c end

    local function getPingMs()
        local ok, raw = pcall(function() return LocalPlayer:GetNetworkPing() end)
        if not ok or type(raw) ~= "number" then return 0 end
        if raw < 10 then return math.floor(raw * 1000 + 0.5) end
        return math.floor(raw + 0.5)
    end

    local function applyDefaults(target, defaults)
        for k in pairs(target) do
            if defaults[k] == nil then target[k] = nil end
        end
        for k, v in pairs(defaults) do
            if type(v) == "table" then
                target[k] = target[k] or {}
                applyDefaults(target[k], v)
            else
                target[k] = v
            end
        end
    end

    --// -----------------------------------------------------------------------
    --// HUD
    --// -----------------------------------------------------------------------
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
        if HUD.Elements.bg and HUD.Elements.accent and HUD.Elements.title
           and HUD.Elements.subtitle and HUD.Elements.line1 and HUD.Elements.line2 then
            return true
        end
        local S = WallHack.Visuals.HUDSettings
        local built = {}
        local ok = pcall(function()
            local bg = Drawing.new("Square")
            bg.Filled = true; bg.Outline = false
            bg.Color = S.BackColor
            bg.Transparency = S.BackTransparency
            pcall(function() bg.Rounding = 8 end)
            bg.Visible = false
            built.bg = bg
            local accent = Drawing.new("Square")
            accent.Filled = true; accent.Outline = false
            accent.Color = S.AccentColor
            accent.Transparency = 0
            pcall(function() accent.Rounding = 4 end)
            accent.Visible = false
            built.accent = accent
            built.title    = hudNewText(16, 2)
            built.subtitle = hudNewText(11, 1)
            built.line1    = hudNewText(13, 2)
            built.line2    = hudNewText(13, 2)
        end)
        if not ok then
            for _, e in pairs(built) do
                if e and e.Remove then pcall(function() e:Remove() end) end
            end
            return false
        end
        HUD.Elements.bg       = built.bg
        HUD.Elements.accent   = built.accent
        HUD.Elements.title    = built.title
        HUD.Elements.subtitle = built.subtitle
        HUD.Elements.line1    = built.line1
        HUD.Elements.line2    = built.line2
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

        local pos = hudGetPosition()
        local paddingX = 14
        local bg = HUD.Elements.bg
        bg.Size = Vector2.new(HUD.W, HUD.H)
        bg.Position = pos
        bg.Color = S.BackColor
        bg.Transparency = S.BackTransparency

        local accent = HUD.Elements.accent
        accent.Size = Vector2.new(4, HUD.H)
        accent.Position = pos
        accent.Color = S.AccentColor

        local title = HUD.Elements.title
        title.Text = "AirHub"
        title.Color = S.TextColor
        title.Position = Vector2.new(pos.X + paddingX, pos.Y + 7)

        local subtitle = HUD.Elements.subtitle
        subtitle.Text = "▸ connected"
        subtitle.Color = S.MutedColor
        subtitle.Position = Vector2.new(pos.X + paddingX + 66, pos.Y + 12)

        local parts1 = {}
        if S.ShowPlayers then
            table.insert(parts1, string.format("Players  %d", #Players:GetPlayers()))
        end
        if S.ShowFPS then
            table.insert(parts1, string.format("FPS  %d", HUD.CurrentFps))
        end
        local line1 = HUD.Elements.line1
        line1.Text = table.concat(parts1, "     ")
        line1.Color = S.TextColor
        line1.Position = Vector2.new(pos.X + paddingX, pos.Y + 36)

        local parts2 = {}
        if S.ShowPing then
            table.insert(parts2, string.format("Ping  %d ms", getPingMs()))
        end
        if S.ShowSession then
            table.insert(parts2,
                string.format("Session  %s", hudFmtTime(os.clock() - HUD.SessionStart)))
        end
        local line2 = HUD.Elements.line2
        line2.Text = table.concat(parts2, "     ")
        line2.Color = S.MutedColor
        line2.Position = Vector2.new(pos.X + paddingX, pos.Y + 58)

        HUD.Frames += 1
        local now = os.clock()
        if now - HUD.LastSample >= 1 then
            HUD.CurrentFps = math.floor(HUD.Frames / (now - HUD.LastSample) + 0.5)
            HUD.Frames = 0
            HUD.LastSample = now
        end
    end

    local function StartHUD()
        local HUD = WallHack.Internal.HUD
        if HUD.Conn then return end
        HUD.SessionStart = os.clock()
        HUD.LastSample   = os.clock()
        HUD.Frames       = 0
        HUD.CurrentFps   = 0
        HUD.Conn = RunService.RenderStepped:Connect(hudUpdate)
    end

    local function StopHUD()
        local HUD = WallHack.Internal.HUD
        WallHack.Visuals.HUDSettings.Enabled = false
        if HUD.Conn then
            pcall(function() HUD.Conn:Disconnect() end)
            HUD.Conn = nil
        end
        for _, e in pairs(HUD.Elements) do
            if e and e.Remove then pcall(function() e:Remove() end) end
        end
        HUD.Elements = {}
        HUD.Visible  = false
    end

    --// -----------------------------------------------------------------------
    --// Self ESP — Chams
    --// -----------------------------------------------------------------------
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

    --// -----------------------------------------------------------------------
    --// Self ESP — ChinaHat  (native Ball, no meshes)
    --// -----------------------------------------------------------------------
    local function getHatFolder()
        local Se = WallHack.Internal.SelfESP
        if Se.HatFolder and Se.HatFolder.Parent then return Se.HatFolder end
        local existing = workspace:FindFirstChild("AirHub_SelfESP")
        if not existing then
            existing = Instance.new("Folder")
            existing.Name = "AirHub_SelfESP"
            existing.Parent = workspace
        end
        Se.HatFolder = existing
        return existing
    end

    -- [FIX-21] Native Ball hat — always renders.
    local function buildHat(head)
        local C = WallHack.Visuals.SelfESP.ChinaHat
        local hat = Instance.new("Part")
        hat.Name = "AirHubChinaHat"
        hat.Shape = Enum.PartType.Ball            -- [FIX-21]
        hat.Size  = Vector3.new(C.Size * 1.6, C.Size * 0.55, C.Size * 1.6)
        hat.Anchored   = true
        hat.CanCollide = false
        hat.CanQuery   = false
        hat.CanTouch   = false
        hat.Massless   = true
        hat.CastShadow = false
        hat.Color      = C.Color
        hat.Material   = Enum.Material[C.Material] or Enum.Material.Neon
        hat.Transparency = C.Transparency
        hat.LocalTransparencyModifier = 0
        hat.CFrame = head.CFrame * CFrame.new(0, C.OffsetY, 0)
        hat.Parent = getHatFolder()
        return hat
    end

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

    -- [FIX-19/22] self-heal + force visible properties every frame
    local function startHatLoop()
        local Se = WallHack.Internal.SelfESP
        if Se.HatConn then return end
        Se.HatConn = RunService.RenderStepped:Connect(function()
            if H.ShuttingDown then return end

            -- refresh head ref
            if not Se.HatHead or not Se.HatHead.Parent then
                local char = LocalPlayer.Character
                local head = char and char:FindFirstChild("Head")
                if head then Se.HatHead = head else return end
            end

            -- rebuild if destroyed
            if not Se.HatPart or not Se.HatPart.Parent then
                Se.HatPart = buildHat(Se.HatHead)
            end

            local hat  = Se.HatPart
            local head = Se.HatHead
            local C    = WallHack.Visuals.SelfESP.ChinaHat

            -- [FIX-22] force shape & size every frame
            if hat.Shape ~= Enum.PartType.Ball then hat.Shape = Enum.PartType.Ball end
            local wantSize = Vector3.new(C.Size * 1.6, C.Size * 0.55, C.Size * 1.6)
            if hat.Size ~= wantSize then hat.Size = wantSize end

            -- [FIX-18] force visibility
            hat.LocalTransparencyModifier = 0
            hat.Transparency = C.Transparency
            hat.Color        = C.Color
            if hat.Material ~= (Enum.Material[C.Material] or Enum.Material.Neon) then
                hat.Material = Enum.Material[C.Material] or Enum.Material.Neon
            end

            -- [FIX-20] force anchored
            if not hat.Anchored then hat.Anchored = true end

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

        if Se.HatPart and Se.HatPart.Parent then
            Se.HatHead = head
            startHatLoop()
            return
        end
        if Se.HatPart then
            pcall(function() Se.HatPart:Destroy() end)
            Se.HatPart = nil
        end
        Se.HatPart = buildHat(head)
        Se.HatHead = head
        startHatLoop()
    end

    local function refreshSelfESP()
        local S = WallHack.Visuals.SelfESP
        local char = LocalPlayer.Character

        if S.Chams.Enabled or S.ChinaHat.Enabled then
            S.Enabled = true
        end

        if not char then
            removeChams()
            removeChinaHat()
            return
        end

        if S.Chams.Enabled    then applyChams(char) else removeChams()    end
        if S.ChinaHat.Enabled then applyChinaHat()  else removeChinaHat() end
    end

    local function StartSelfESP()
        local Se = WallHack.Internal.SelfESP
        if not Se.CharConn then
            Se.CharConn = LocalPlayer.CharacterAdded:Connect(function()
                task.wait(0.5)
                if H.ShuttingDown then return end
                refreshSelfESP()
            end)
        end
        refreshSelfESP()
    end

    local function StopSelfESP()
        local Se = WallHack.Internal.SelfESP
        WallHack.Visuals.SelfESP.Enabled = false
        if Se.CharConn then
            pcall(function() Se.CharConn:Disconnect() end)
            Se.CharConn = nil
        end
        removeChams()
        removeChinaHat()
    end

    -- [FIX-23] Diagnostic helper.
    local function DebugHat()
        local Se = WallHack.Internal.SelfESP
        local hat = Se.HatPart
        if not hat then print("[AirHub][Hat] no HatPart"); return end
        local cam = workspace.CurrentCamera
        print("[AirHub][Hat] Name:      ", hat.Name)
        print("[AirHub][Hat] ClassName: ", hat.ClassName)
        print("[AirHub][Hat] Shape:     ", tostring(hat.Shape))
        print("[AirHub][Hat] Size:      ", tostring(hat.Size))
        print("[AirHub][Hat] Position:  ", tostring(hat.Position))
        print("[AirHub][Hat] Parent:    ", tostring(hat.Parent))
        print("[AirHub][Hat] Visible:   ", hat.Transparency < 1 and hat.Parent ~= nil)
        print("[AirHub][Hat] Transp:    ", hat.Transparency)
        print("[AirHub][Hat] LTM:       ", hat.LocalTransparencyModifier)
        print("[AirHub][Hat] CamDist:   ", (hat.Position - cam.CFrame.Position).Magnitude)
    end

    --// -----------------------------------------------------------------------
    --// Glow
    --// -----------------------------------------------------------------------
    local function ApplyGlowForPlayer(plr)
        local data = WallHack.WrappedPlayers[plr.Name]
        if not data then return end
        local shouldShow = WallHack.Settings.Enabled and WallHack.Visuals.GlowSettings.Enabled
        if not shouldShow then
            if data.Glow then pcall(function() data.Glow:Destroy() end); data.Glow = nil end
            return
        end
        local char = plr.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if not (char and hum and hum.Health > 0) then
            if data.Glow then pcall(function() data.Glow:Destroy() end); data.Glow = nil end
            return
        end
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
            local pulse = (math.sin(os.clock() * 2) + 1) / 2
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
    end

    local function ApplyGlowToAll()
        for _, plr in pairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then ApplyGlowForPlayer(plr) end
        end
    end

    --// -----------------------------------------------------------------------
    --// Boxes
    --// -----------------------------------------------------------------------
    local function AddBox(plr)
        local t = WallHack.WrappedPlayers[plr.Name]
        if not t then return end
        local ok = pcall(function()
            t.Box = {
                Square          = Drawing.new("Square"),
                TopLeftLine     = Drawing.new("Line"),
                TopRightLine    = Drawing.new("Line"),
                BottomLeftLine  = Drawing.new("Line"),
                BottomRightLine = Drawing.new("Line"),
            }
        end)
        if not ok then t.Box = {}; return end

        t.Connections.Box = RunService.RenderStepped:Connect(function()
            if H.ShuttingDown then return end
            if not WallHack.Settings.Enabled or not WallHack.Visuals.BoxSettings.Enabled then
                for _, v in pairs(t.Box) do v.Visible = false end
                return
            end
            local char = plr.Character
            if not char
               or not char:FindFirstChild("HumanoidRootPart")
               or not char:FindFirstChild("Head") then
                for _, v in pairs(t.Box) do v.Visible = false end
                return
            end
            local vec, onScreen = workspace.CurrentCamera:WorldToViewportPoint(
                char.HumanoidRootPart.Position)
            if not onScreen or not t.Checks.Alive or not t.Checks.Team then
                for _, v in pairs(t.Box) do v.Visible = false end
                return
            end

            local isTarget = (H.Aimbot and H.Aimbot.Locked == plr)
            local boxColor = isTarget
                and SanitizeColor(WallHack.Visuals.BoxSettings.TargetColor)
                or  SanitizeColor(WallHack.Visuals.BoxSettings.Color)

            local hrpCF = char.HumanoidRootPart.CFrame
            local size  = char.HumanoidRootPart.Size * WallHack.Visuals.BoxSettings.Increase
            local cam   = workspace.CurrentCamera
            local posTL = cam:WorldToViewportPoint((hrpCF * CFrame.new( size.X,  size.Y, 0)).Position)
            local posTR = cam:WorldToViewportPoint((hrpCF * CFrame.new(-size.X,  size.Y, 0)).Position)
            local posBL = cam:WorldToViewportPoint((hrpCF * CFrame.new( size.X, -size.Y - 0.5, 0)).Position)
            local posBR = cam:WorldToViewportPoint((hrpCF * CFrame.new(-size.X, -size.Y - 0.5, 0)).Position)

            if WallHack.Visuals.BoxSettings.Type == 2 then
                t.Box.Square.Visible = true
                for k, v in pairs(t.Box) do
                    if k ~= "Square" then v.Visible = false end
                end
                t.Box.Square.Thickness    = WallHack.Visuals.BoxSettings.Thickness
                t.Box.Square.Color        = boxColor
                t.Box.Square.Transparency = WallHack.Visuals.BoxSettings.Transparency
                t.Box.Square.Filled       = WallHack.Visuals.BoxSettings.Filled
                local headY = cam:WorldToViewportPoint(
                    char.Head.Position + Vector3.new(0, 0.5, 0)).Y
                local legY  = cam:WorldToViewportPoint(
                    char.HumanoidRootPart.Position - Vector3.new(0, 3, 0)).Y
                t.Box.Square.Size     = Vector2.new(2000 / vec.Z, headY - legY)
                t.Box.Square.Position = Vector2.new(
                    vec.X - t.Box.Square.Size.X / 2,
                    vec.Y - t.Box.Square.Size.Y / 2)
            else
                t.Box.Square.Visible = false
                for _, ln in pairs({
                    "TopLeftLine", "TopRightLine",
                    "BottomLeftLine", "BottomRightLine"
                }) do
                    t.Box[ln].Visible      = true
                    t.Box[ln].Thickness    = WallHack.Visuals.BoxSettings.Thickness
                    t.Box[ln].Transparency = WallHack.Visuals.BoxSettings.Transparency
                    t.Box[ln].Color        = boxColor
                end
                t.Box.TopLeftLine.From     = Vector2.new(posTL.X, posTL.Y)
                t.Box.TopLeftLine.To       = Vector2.new(posTR.X, posTR.Y)
                t.Box.TopRightLine.From    = Vector2.new(posTR.X, posTR.Y)
                t.Box.TopRightLine.To      = Vector2.new(posBR.X, posBR.Y)
                t.Box.BottomLeftLine.From  = Vector2.new(posBL.X, posBL.Y)
                t.Box.BottomLeftLine.To    = Vector2.new(posTL.X, posTL.Y)
                t.Box.BottomRightLine.From = Vector2.new(posBR.X, posBR.Y)
                t.Box.BottomRightLine.To   = Vector2.new(posBL.X, posBL.Y)
            end
        end)
    end

    local function InitChecks(plr)
        local t = WallHack.WrappedPlayers[plr.Name]
        if not t then return end
        t.Connections.UpdateChecks = RunService.RenderStepped:Connect(function()
            if H.ShuttingDown then return end
            local char = plr.Character
            local hum  = char and char:FindFirstChildOfClass("Humanoid")
            if char and hum then
                if WallHack.Settings.AliveCheck then
                    t.Checks.Alive = hum.Health > 0
                else
                    t.Checks.Alive = true
                end
                if not WallHack.Settings.TeamCheck then
                    t.Checks.Team = true
                else
                    local a, b = LocalPlayer.Team, plr.Team
                    t.Checks.Team = (a ~= nil and b ~= nil and a ~= b) and true or false
                end
            else
                t.Checks.Alive = false
                t.Checks.Team  = false
            end
            ApplyGlowForPlayer(plr)
        end)
    end

    local MAX_RIG_ATTEMPTS = 6
    local RIG_WAIT_TIMEOUT = 15

    local function AssignRigType(plr, attempt)
        attempt = (attempt or 0) + 1
        if attempt > MAX_RIG_ATTEMPTS then return end
        local t = WallHack.WrappedPlayers[plr.Name]
        if not t then return end
        task.spawn(function()
            local waited = 0
            while waited < RIG_WAIT_TIMEOUT do
                task.wait(0.5)
                waited = waited + 0.5
                if H.ShuttingDown then return end
                if plr.Character then break end
            end
            if H.ShuttingDown then return end
            local char = plr.Character
            if not char then return end
            if char:FindFirstChild("Torso") and not char:FindFirstChild("LowerTorso") then
                t.RigType = "R6"
            elseif char:FindFirstChild("LowerTorso") then
                t.RigType = "R15"
            else
                AssignRigType(plr, attempt)
            end
        end)
    end

    local function Wrap(plr)
        if not WallHack.WrappedPlayers[plr.Name] then
            local val = {
                Name = plr.Name,
                Checks = { Alive = true, Team = true },
                Connections = {},
                Box = {},
            }
            WallHack.WrappedPlayers[plr.Name] = val
            AssignRigType(plr, 0)
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
        if v.CharacterAddedConn then
            pcall(function() v.CharacterAddedConn:Disconnect() end)
        end
        for _, b in pairs(v.Box) do
            if b and b.Remove then pcall(function() b:Remove() end) end
        end
        if v.Glow then pcall(function() v.Glow:Destroy() end) end
        WallHack.WrappedPlayers[plr.Name] = nil
    end

    local WHConnections = {}
    local ReWrapToken = 0

    local function StartReWrapLoop()
        ReWrapToken += 1
        local myToken = ReWrapToken
        task.spawn(function()
            while myToken == ReWrapToken and not H.ShuttingDown do
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

    --// -----------------------------------------------------------------------
    --// Public API
    --// -----------------------------------------------------------------------
    WallHack.Functions.Exit = function()
        ReWrapToken += 1
        for _, v in pairs(WHConnections) do
            pcall(function() v:Disconnect() end)
        end
        WHConnections = {}
        for _, v in pairs(Players:GetPlayers()) do
            if v ~= LocalPlayer then UnWrap(v) end
        end
        StopHUD()
        StopSelfESP()
    end

    WallHack.Functions.Restart = function()
        ReWrapToken += 1
        for _, v in pairs(WHConnections) do
            pcall(function() v:Disconnect() end)
        end
        WHConnections = {}
        LoadWH()
    end

    WallHack.Functions.ResetSettings = function()
        applyDefaults(WallHack.Settings,             DEFAULT_SETTINGS)
        applyDefaults(WallHack.Visuals.BoxSettings,  DEFAULT_BOX)
        applyDefaults(WallHack.Visuals.GlowSettings, DEFAULT_GLOW)
        applyDefaults(WallHack.Visuals.HUDSettings,  DEFAULT_HUD)
        applyDefaults(WallHack.Visuals.SelfESP,      DEFAULT_SELFESP)

        local HUD = WallHack.Internal.HUD
        HUD.SessionStart = os.clock()
        HUD.LastSample   = os.clock()
        HUD.Frames       = 0
        HUD.CurrentFps   = 0

        ApplyGlowToAll()
        StopHUD()
        StopSelfESP()
    end

    WallHack.Functions.StartHUD = StartHUD
    WallHack.Functions.StopHUD  = StopHUD

    WallHack.Functions.SetHUDEnabled = function(v)
        WallHack.Visuals.HUDSettings.Enabled = v and true or false
        if v then StartHUD() else StopHUD() end
    end
    WallHack.Functions.GetHUDEnabled = function()
        return WallHack.Visuals.HUDSettings.Enabled
    end

    WallHack.Functions.StartSelfESP   = StartSelfESP
    WallHack.Functions.StopSelfESP    = StopSelfESP
    WallHack.Functions.RefreshSelfESP = refreshSelfESP
    WallHack.Functions.DebugHat       = DebugHat      -- [FIX-23]

    WallHack.Functions.SetSelfESPEnabled = function(v)
        WallHack.Visuals.SelfESP.Enabled = v and true or false
        if v then StartSelfESP() else StopSelfESP() end
    end
    WallHack.Functions.SetSelfESPChamsEnabled = function(v)
        WallHack.Visuals.SelfESP.Chams.Enabled = v and true or false
        if v then WallHack.Visuals.SelfESP.Enabled = true end
        StartSelfESP()
    end
    WallHack.Functions.SetSelfESPChinaHatEnabled = function(v)
        WallHack.Visuals.SelfESP.ChinaHat.Enabled = v and true or false
        if v then WallHack.Visuals.SelfESP.Enabled = true end
        StartSelfESP()
    end
    WallHack.Functions.GetSelfESPEnabled = function()
        return WallHack.Visuals.SelfESP.Enabled
    end

    WallHack.ApplyGlowToAll     = ApplyGlowToAll
    WallHack.ApplyGlowForPlayer = ApplyGlowForPlayer
end)

--// ---------------------------------------------------------------------------
--// 3) Fallback stubs
--// ---------------------------------------------------------------------------
if not okInit then
    warn("[AirHub] 04_wallhack: init error → " .. tostring(errInit))
    local noop = function() end
    WallHack.Functions.Exit                       = WallHack.Functions.Exit                       or noop
    WallHack.Functions.Restart                    = WallHack.Functions.Restart                    or noop
    WallHack.Functions.ResetSettings              = WallHack.Functions.ResetSettings              or noop
    WallHack.Functions.StartHUD                   = WallHack.Functions.StartHUD                   or noop
    WallHack.Functions.StopHUD                    = WallHack.Functions.StopHUD                    or noop
    WallHack.Functions.SetHUDEnabled              = WallHack.Functions.SetHUDEnabled              or noop
    WallHack.Functions.GetHUDEnabled              = WallHack.Functions.GetHUDEnabled              or function() return false end
    WallHack.Functions.StartSelfESP               = WallHack.Functions.StartSelfESP               or noop
    WallHack.Functions.StopSelfESP                = WallHack.Functions.StopSelfESP                or noop
    WallHack.Functions.RefreshSelfESP             = WallHack.Functions.RefreshSelfESP             or noop
    WallHack.Functions.DebugHat                   = WallHack.Functions.DebugHat                   or noop
    WallHack.Functions.SetSelfESPEnabled          = WallHack.Functions.SetSelfESPEnabled          or noop
    WallHack.Functions.SetSelfESPChamsEnabled     = WallHack.Functions.SetSelfESPChamsEnabled     or noop
    WallHack.Functions.SetSelfESPChinaHatEnabled  = WallHack.Functions.SetSelfESPChinaHatEnabled  or noop
    WallHack.Functions.GetSelfESPEnabled          = WallHack.Functions.GetSelfESPEnabled          or function() return false end
    WallHack.ApplyGlowToAll                       = WallHack.ApplyGlowToAll                       or noop
    WallHack.ApplyGlowForPlayer                   = WallHack.ApplyGlowForPlayer                   or noop
end

if okInit then
    print("[AirHub] 04_wallhack: loaded OK")
else
    print("[AirHub] 04_wallhack: loaded in STUB mode")
end
