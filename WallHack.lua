-- WallHack.lua – боксы, глоу (4 режима), RTX-эффекты
local WallHack = {
    Settings = {Enabled = false, TeamCheck = false, AliveCheck = true},
    Visuals = {
        BoxSettings = {Enabled = true, Type = 1, Color = Color3.fromRGB(255,255,255), TargetColor = Color3.fromRGB(255,0,0), Transparency = 0.7, Thickness = 1, Filled = false, Increase = 1},
        GlowSettings = {Enabled = true, Color = Color3.fromRGB(0,255,255), Transparency = 0.5, Thickness = 2, Mode = "Outline"}
    },
    RTX = {
        Enabled = false,
        Settings = {
            GlobalShadows = true, EnvironmentDiffuseScale = 1.2, EnvironmentSpecularScale = 1.5, Brightness = 3, ExposureCompensation = 0.2, ShadowSoftness = 0.3,
            ClockTime = 14, OutdoorAmbient = Color3.fromRGB(100,100,120), FogEnd = 1000, FogStart = 0, Technology = "Compatibility",
            ColorCorrection = {Enabled = false, Brightness = 0, Contrast = 0, Saturation = 0, TintColor = Color3.fromRGB(255,255,255)},
            Bloom = {Enabled = false, Intensity = 1, Size = 24, Threshold = 0.9},
            SunRays = {Enabled = false, Intensity = 0.5, Spread = 0.5},
            DepthOfField = {Enabled = false, FarDistance = 100, NearDistance = 0}
        },
        OriginalLighting = {}, Objects = {}
    },
    WrappedPlayers = {}
}
getgenv().AirHub.WallHack = WallHack

local WHConnections = {}
local function GetPlayerTable(plr)
    for _, v in pairs(WallHack.WrappedPlayers) do if v.Name == plr.Name then return v end end
end

local function ApplyGlowForPlayer(plr)
    local data = GetPlayerTable(plr)
    if not data then return end
    if WallHack.Settings.Enabled and WallHack.Visuals.GlowSettings.Enabled then
        local char = plr.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if char and hum and hum.Health > 0 then
            if not data.Glow then
                local highlight = Instance.new("Highlight")
                highlight.Name = "AirHub_Glow"
                highlight.Adornee = char
                highlight.Parent = char
                highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                data.Glow = highlight
            end
            data.Glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            local gs = WallHack.Visuals.GlowSettings
            local mode = gs.Mode or "Outline"
            if mode == "Outline" then
                data.Glow.FillTransparency = 1
                data.Glow.OutlineTransparency = gs.Transparency
                data.Glow.OutlineThickness = gs.Thickness
                data.Glow.FillColor = gs.Color
                data.Glow.OutlineColor = gs.Color
            elseif mode == "Fill" then
                data.Glow.FillTransparency = gs.Transparency
                data.Glow.OutlineTransparency = 1
                data.Glow.OutlineThickness = 0
                data.Glow.FillColor = gs.Color
                data.Glow.OutlineColor = gs.Color
            elseif mode == "Both" then
                data.Glow.FillTransparency = gs.Transparency * 0.5
                data.Glow.OutlineTransparency = gs.Transparency * 0.5
                data.Glow.OutlineThickness = gs.Thickness
                data.Glow.FillColor = gs.Color
                data.Glow.OutlineColor = gs.Color
            elseif mode == "Pulse" then
                local pulse = (math.sin(tick() * 2) + 1) / 2
                local color = gs.Color
                local r = color.R * (0.5 + pulse * 0.5)
                local g = color.G * (0.5 + pulse * 0.5)
                local b = color.B * (0.5 + pulse * 0.5)
                data.Glow.FillColor = Color3.fromRGB(r*255, g*255, b*255)
                data.Glow.OutlineColor = data.Glow.FillColor
                data.Glow.FillTransparency = gs.Transparency * (0.5 + pulse * 0.5)
                data.Glow.OutlineTransparency = gs.Transparency * (0.5 + pulse * 0.5)
                data.Glow.OutlineThickness = gs.Thickness
            end
        elseif data.Glow then
            data.Glow:Destroy()
            data.Glow = nil
        end
    elseif data.Glow then
        data.Glow:Destroy()
        data.Glow = nil
    end
end

local function ApplyGlowToAll()
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then ApplyGlowForPlayer(plr) end
    end
end

local function ApplyRTXEffects()
    local s = WallHack.RTX.Settings
    local objs = WallHack.RTX.Objects
    if s.ColorCorrection.Enabled then
        if not objs.ColorCorrection then objs.ColorCorrection = Instance.new("ColorCorrectionEffect") objs.ColorCorrection.Parent = Lighting end
        objs.ColorCorrection.Brightness = s.ColorCorrection.Brightness
        objs.ColorCorrection.Contrast = s.ColorCorrection.Contrast
        objs.ColorCorrection.Saturation = s.ColorCorrection.Saturation
        objs.ColorCorrection.TintColor = s.ColorCorrection.TintColor
    elseif objs.ColorCorrection then objs.ColorCorrection:Destroy(); objs.ColorCorrection = nil end
    if s.Bloom.Enabled then
        if not objs.Bloom then objs.Bloom = Instance.new("BloomEffect") objs.Bloom.Parent = Lighting end
        objs.Bloom.Intensity = s.Bloom.Intensity
        objs.Bloom.Size = s.Bloom.Size
        objs.Bloom.Threshold = s.Bloom.Threshold
    elseif objs.Bloom then objs.Bloom:Destroy(); objs.Bloom = nil end
    if s.SunRays.Enabled then
        if not objs.SunRays then objs.SunRays = Instance.new("SunRaysEffect") objs.SunRays.Parent = Lighting end
        objs.SunRays.Intensity = s.SunRays.Intensity
        objs.SunRays.Spread = s.SunRays.Spread
    elseif objs.SunRays then objs.SunRays:Destroy(); objs.SunRays = nil end
    if s.DepthOfField.Enabled then
        if not objs.DepthOfField then objs.DepthOfField = Instance.new("DepthOfFieldEffect") objs.DepthOfField.Parent = Lighting end
        objs.DepthOfField.FarDistance = s.DepthOfField.FarDistance
        objs.DepthOfField.NearDistance = s.DepthOfField.NearDistance
    elseif objs.DepthOfField then objs.DepthOfField:Destroy(); objs.DepthOfField = nil end
end

local function ApplyRTXSettings()
    if WallHack.RTX.Enabled then
        local s = WallHack.RTX.Settings
        Lighting.GlobalShadows = s.GlobalShadows
        Lighting.EnvironmentDiffuseScale = s.EnvironmentDiffuseScale
        Lighting.EnvironmentSpecularScale = s.EnvironmentSpecularScale
        Lighting.Brightness = s.Brightness
        Lighting.ExposureCompensation = s.ExposureCompensation
        Lighting.ShadowSoftness = s.ShadowSoftness
        Lighting.ClockTime = s.ClockTime
        Lighting.OutdoorAmbient = s.OutdoorAmbient
        Lighting.FogEnd = s.FogEnd
        Lighting.FogStart = s.FogStart
        if s.Technology then
            local tech = Enum.Technology[s.Technology]
            if tech then Lighting.Technology = tech end
        end
        ApplyRTXEffects()
    end
end

local function EnableRTX()
    if WallHack.RTX.Enabled then return end
    WallHack.RTX.OriginalLighting = {
        GlobalShadows = Lighting.GlobalShadows, EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale, EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
        Brightness = Lighting.Brightness, ExposureCompensation = Lighting.ExposureCompensation, ShadowSoftness = Lighting.ShadowSoftness,
        ClockTime = Lighting.ClockTime, OutdoorAmbient = Lighting.OutdoorAmbient, FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart,
        Technology = tostring(Lighting.Technology)
    }
    WallHack.RTX.Enabled = true
    ApplyRTXSettings()
end

local function DisableRTX()
    if not WallHack.RTX.Enabled then return end
    for k, v in pairs(WallHack.RTX.OriginalLighting) do
        if k == "Technology" then
            local tech = Enum.Technology[v]
            if tech then Lighting.Technology = tech end
        else
            Lighting[k] = v
        end
    end
    for _, obj in pairs(WallHack.RTX.Objects) do if obj then obj:Destroy() end end
    WallHack.RTX.Objects = {}
    WallHack.RTX.Enabled = false
end

local function AddBox(plr)
    local t = GetPlayerTable(plr)
    t.Box = {
        Square = Drawing.new("Square"),
        TopLeftLine = Drawing.new("Line"), TopRightLine = Drawing.new("Line"),
        BottomLeftLine = Drawing.new("Line"), BottomRightLine = Drawing.new("Line")
    }
    t.Connections.Box = RunService.RenderStepped:Connect(function()
        if not WallHack.Settings.Enabled or not WallHack.Visuals.BoxSettings.Enabled then
            for _, v in pairs(t.Box) do v.Visible = false end
            return
        end
        local char = plr.Character
        if not char or not char:FindFirstChild("HumanoidRootPart") or not char:FindFirstChild("Head") then
            for _, v in pairs(t.Box) do v.Visible = false end
            return
        end
        local vec, onScreen = Camera:WorldToViewportPoint(char.HumanoidRootPart.Position)
        if not onScreen or not t.Checks.Alive or not t.Checks.Team then
            for _, v in pairs(t.Box) do v.Visible = false end
            return
        end
        local isTarget = (getgenv().AirHub.Aimbot and getgenv().AirHub.Aimbot.Locked == plr)
        local boxColor = isTarget and WallHack.Visuals.BoxSettings.TargetColor or WallHack.Visuals.BoxSettings.Color
        local hrpCF = char.HumanoidRootPart.CFrame
        local size = char.HumanoidRootPart.Size * WallHack.Visuals.BoxSettings.Increase
        local posTL = Camera:WorldToViewportPoint((hrpCF * CFrame.new(size.X, size.Y, 0)).Position)
        local posTR = Camera:WorldToViewportPoint((hrpCF * CFrame.new(-size.X, size.Y, 0)).Position)
        local posBL = Camera:WorldToViewportPoint((hrpCF * CFrame.new(size.X, -size.Y - 0.5, 0)).Position)
        local posBR = Camera:WorldToViewportPoint((hrpCF * CFrame.new(-size.X, -size.Y - 0.5, 0)).Position)
        if WallHack.Visuals.BoxSettings.Type == 2 then
            t.Box.Square.Visible = true
            for k, v in pairs(t.Box) do if k ~= "Square" then v.Visible = false end end
            t.Box.Square.Thickness = WallHack.Visuals.BoxSettings.Thickness
            t.Box.Square.Color = boxColor
            t.Box.Square.Transparency = WallHack.Visuals.BoxSettings.Transparency
            t.Box.Square.Filled = WallHack.Visuals.BoxSettings.Filled
            local headY = Camera:WorldToViewportPoint(char.Head.Position + Vector3.new(0, 0.5, 0)).Y
            local legY = Camera:WorldToViewportPoint(char.HumanoidRootPart.Position - Vector3.new(0, 3, 0)).Y
            t.Box.Square.Size = Vector2.new(2000 / vec.Z, headY - legY)
            t.Box.Square.Position = Vector2.new(vec.X - t.Box.Square.Size.X / 2, vec.Y - t.Box.Square.Size.Y / 2)
        else
            t.Box.Square.Visible = false
            for _, ln in pairs({"TopLeftLine","TopRightLine","BottomLeftLine","BottomRightLine"}) do
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
    t.Connections.UpdateChecks = RunService.RenderStepped:Connect(function()
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
    task.wait()
    repeat task.wait() until plr.Character
    if plr.Character:FindFirstChild("Torso") and not plr.Character:FindFirstChild("LowerTorso") then
        t.RigType = "R6"
    elseif plr.Character:FindFirstChild("LowerTorso") then
        t.RigType = "R15"
    else
        AssignRigType(plr)
    end
end

local function Wrap(plr)
    if not GetPlayerTable(plr) then
        local val = { Name = plr.Name, Checks = { Alive = true, Team = true }, Connections = {}, Box = {} }
        WallHack.WrappedPlayers[#WallHack.WrappedPlayers + 1] = val
        AssignRigType(plr)
        InitChecks(plr)
        AddBox(plr)
        ApplyGlowForPlayer(plr)
        plr.CharacterAdded:Connect(function() ApplyGlowForPlayer(plr) end)
    end
end

local function UnWrap(plr)
    for i, v in pairs(WallHack.WrappedPlayers) do
        if v.Name == plr.Name then
            for _, c in pairs(v.Connections) do c:Disconnect() end
            for _, b in pairs(v.Box) do if b and b.Remove then b:Remove() end end
            if v.Glow then v.Glow:Destroy() end
            WallHack.WrappedPlayers[i] = nil
            break
        end
    end
end

local function LoadWH()
    WHConnections.PlayerAdded = Players.PlayerAdded:Connect(Wrap)
    WHConnections.PlayerRemoving = Players.PlayerRemoving:Connect(UnWrap)
    WHConnections.ReWrap = RunService.RenderStepped:Connect(function()
        for _, v in pairs(Players:GetPlayers()) do if v ~= LocalPlayer then Wrap(v) end end
        task.wait(30)
    end)
end
LoadWH()

WallHack.Functions = {
    Exit = function()
        for _, v in pairs(WHConnections) do v:Disconnect() end
        for _, v in pairs(Players:GetPlayers()) do if v ~= LocalPlayer then UnWrap(v) end end
        DisableRTX()
    end,
    Restart = function() for _, v in pairs(WHConnections) do v:Disconnect() end LoadWH() end,
    ResetSettings = function()
        WallHack.Settings = {Enabled = false, TeamCheck = false, AliveCheck = true}
        WallHack.Visuals.BoxSettings = {Enabled = true, Type = 1, Color = Color3.fromRGB(255,255,255), TargetColor = Color3.fromRGB(255,0,0), Transparency = 0.7, Thickness = 1, Filled = false, Increase = 1}
        WallHack.Visuals.GlowSettings = {Enabled = true, Color = Color3.fromRGB(0,255,255), Transparency = 0.5, Thickness = 2, Mode = "Outline"}
        DisableRTX()
        WallHack.RTX.Settings = {
            GlobalShadows = true, EnvironmentDiffuseScale = 1.2, EnvironmentSpecularScale = 1.5, Brightness = 3,
            ExposureCompensation = 0.2, ShadowSoftness = 0.3, ClockTime = 14, OutdoorAmbient = Color3.fromRGB(100,100,120),
            FogEnd = 1000, FogStart = 0, Technology = "Compatibility",
            ColorCorrection = {Enabled = false, Brightness = 0, Contrast = 0, Saturation = 0, TintColor = Color3.fromRGB(255,255,255)},
            Bloom = {Enabled = false, Intensity = 1, Size = 24, Threshold = 0.9},
            SunRays = {Enabled = false, Intensity = 0.5, Spread = 0.5},
            DepthOfField = {Enabled = false, FarDistance = 100, NearDistance = 0}
        }
        ApplyGlowToAll()
    end
}
