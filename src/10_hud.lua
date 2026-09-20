--// AirHub - 10_hud.lua
--// Pretty HUD injected into the Visuals tab.

local H = getgenv().AirHub
if not H or not H._CoreLoaded then warn("[AirHub] 10_hud: core not loaded"); return end
if H.HUD then warn("[AirHub] HUD already loaded"); return end

local Util        = H.Util
local Players     = Util.Players
local RunService  = Util.RunService
local LocalPlayer = Util.LocalPlayer

local HUD_W = 230
local HUD_H = 84

H.HUD = {
    Settings = {
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
    Elements = {},
    Internal = {
        Frames       = 0,
        LastSample   = tick(),
        CurrentFps   = 0,
        SessionStart = tick(),
        Conn         = nil,
        Visible      = false,
    },
    Functions = {},
}
local HUD = H.HUD

local function newText(size, font)
    local t = Drawing.new("Text")
    t.Font = font or 2
    t.Size = size or 14
    t.Outline = true
    t.Center = false
    t.Visible = false
    return t
end

local function ensureElements()
    if HUD.Elements.bg then return true end
    local ok = pcall(function()
        local bg = Drawing.new("Square")
        bg.Filled = true
        bg.Outline = false
        bg.Color = HUD.Settings.BackColor
        bg.Transparency = HUD.Settings.BackTransparency
        pcall(function() bg.Rounding = 8 end)
        bg.Visible = false
        HUD.Elements.bg = bg

        local accent = Drawing.new("Square")
        accent.Filled = true
        accent.Outline = false
        accent.Color = HUD.Settings.AccentColor
        accent.Transparency = 0.0
        pcall(function() accent.Rounding = 4 end)
        accent.Visible = false
        HUD.Elements.accent = accent
    end)
    if not ok then return false end

    HUD.Elements.title    = newText(16, 2)
    HUD.Elements.subtitle = newText(11, 1)
    HUD.Elements.line1    = newText(13, 2)
    HUD.Elements.line2    = newText(13, 2)
    return true
end

local function hideAll()
    for _, e in pairs(HUD.Elements) do pcall(function() e.Visible = false end) end
end

local function showAll()
    for _, e in pairs(HUD.Elements) do pcall(function() e.Visible = true end) end
end

local function getPosition()
    local vp = workspace.CurrentCamera.ViewportSize
    local pos = HUD.Settings.Position or "TopLeft"
    local pad = 18
    if pos == "TopLeft" then
        return Vector2.new(pad, pad)
    elseif pos == "TopRight" then
        return Vector2.new(vp.X - HUD_W - pad, pad)
    elseif pos == "BottomLeft" then
        return Vector2.new(pad, vp.Y - HUD_H - pad)
    elseif pos == "BottomRight" then
        return Vector2.new(vp.X - HUD_W - pad, vp.Y - HUD_H - pad)
    end
    return Vector2.new(pad, pad)
end

local function fmtTime(sec)
    sec = math.floor(sec)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if h > 0 then return string.format("%dh %02dm", h, m)
    elseif m > 0 then return string.format("%dm %02ds", m, s) end
    return string.format("%ds", s)
end

local function update()
    if H.ShuttingDown then return end
    if not HUD.Settings.Enabled then
        if HUD.Internal.Visible then hideAll(); HUD.Internal.Visible = false end
        return
    end
    if not ensureElements() then return end
    if not HUD.Internal.Visible then showAll(); HUD.Internal.Visible = true end

    local pos = getPosition()
    local paddingX = 14

    local bg = HUD.Elements.bg
    bg.Size       = Vector2.new(HUD_W, HUD_H)
    bg.Position   = pos
    bg.Color      = HUD.Settings.BackColor
    bg.Transparency = HUD.Settings.BackTransparency

    local accent = HUD.Elements.accent
    accent.Size     = Vector2.new(4, HUD_H)
    accent.Position = pos
    accent.Color    = HUD.Settings.AccentColor

    local title = HUD.Elements.title
    title.Text     = "AirHub"
    title.Color    = HUD.Settings.TextColor
    title.Position = Vector2.new(pos.X + paddingX, pos.Y + 7)

    local subtitle = HUD.Elements.subtitle
    subtitle.Text     = "▸ connected"
    subtitle.Color    = HUD.Settings.MutedColor
    subtitle.Position = Vector2.new(pos.X + paddingX + 66, pos.Y + 12)

    local parts1 = {}
    if HUD.Settings.ShowPlayers then table.insert(parts1, string.format("Players  %d", #Players:GetPlayers())) end
    if HUD.Settings.ShowFPS     then table.insert(parts1, string.format("FPS  %d", HUD.Internal.CurrentFps)) end
    local line1 = HUD.Elements.line1
    line1.Text     = table.concat(parts1, "     ")
    line1.Color    = HUD.Settings.TextColor
    line1.Position = Vector2.new(pos.X + paddingX, pos.Y + 36)

    local parts2 = {}
    if HUD.Settings.ShowPing then
        local ping = math.floor(LocalPlayer:GetNetworkPing() * 1000 + 0.5)
        table.insert(parts2, string.format("Ping  %d ms", ping))
    end
    if HUD.Settings.ShowSession then
        table.insert(parts2, string.format("Session  %s", fmtTime(tick() - HUD.Internal.SessionStart)))
    end
    local line2 = HUD.Elements.line2
    line2.Text     = table.concat(parts2, "     ")
    line2.Color    = HUD.Settings.MutedColor
    line2.Position = Vector2.new(pos.X + paddingX, pos.Y + 58)

    HUD.Internal.Frames += 1
    local now = tick()
    if now - HUD.Internal.LastSample >= 1 then
        HUD.Internal.CurrentFps = math.floor(HUD.Internal.Frames / (now - HUD.Internal.LastSample) + 0.5)
        HUD.Internal.Frames = 0
        HUD.Internal.LastSample = now
    end
end

HUD.Functions.Start = function()
    if HUD.Internal.Conn then return end
    HUD.Internal.SessionStart = tick()
    HUD.Internal.Conn = RunService.RenderStepped:Connect(update)
end

HUD.Functions.Stop = function()
    if HUD.Internal.Conn then HUD.Internal.Conn:Disconnect(); HUD.Internal.Conn = nil end
    hideAll()
    HUD.Internal.Visible = false
end

HUD.Functions.SetEnabled = function(v)
    HUD.Settings.Enabled = v
    if v then HUD.Functions.Start() else HUD.Functions.Stop() end
end

--// UI — now inside Visuals tab
local function fillVisualsUI()
    local tab = H._UI and H._UI.VisualsTab
    if not tab then return false end

    local secH = tab:CreateSection({ Name = "HUD" })
    secH:AddToggle({ Name = "Enable HUD", Value = HUD.Settings.Enabled,
        Callback = function(v) HUD.Functions.SetEnabled(v) end })
    secH:AddDropdown({ Name = "Position", Value = "TopLeft",
        List = { "TopLeft", "TopRight", "BottomLeft", "BottomRight" },
        Callback = function(v) HUD.Settings.Position = v end })
    secH:AddToggle({ Name = "Show Players count", Value = HUD.Settings.ShowPlayers,
        Callback = function(v) HUD.Settings.ShowPlayers = v end })
    secH:AddToggle({ Name = "Show FPS", Value = HUD.Settings.ShowFPS,
        Callback = function(v) HUD.Settings.ShowFPS = v end })
    secH:AddToggle({ Name = "Show Ping", Value = HUD.Settings.ShowPing,
        Callback = function(v) HUD.Settings.ShowPing = v end })
    secH:AddToggle({ Name = "Show Session time", Value = HUD.Settings.ShowSession,
        Callback = function(v) HUD.Settings.ShowSession = v end })

    return true
end

if not fillVisualsUI() then
    task.spawn(function()
        for _ = 1, 60 do
            if H.ShuttingDown then return end
            if fillVisualsUI() then return end
            task.wait(0.5)
        end
        warn("[AirHub] 10_hud: VisualsTab not found after 30s")
    end)
end
