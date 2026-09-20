--// ============================================================================
--// AirHub — 08_world.lua
--// World tab: Lighting / Fog / Atmosphere / Post-FX (RTX) / Sky / Cleanup.
--// All modified properties are snapshotted and can be restored via Presets →
--// "Restore All World Settings" or by toggling the individual feature off.
--// ============================================================================
local H = getgenv().AirHub
if not H or not H._CoreLoaded then warn("[AirHub] 08_world: core not loaded"); return end
if H.World then warn("[AirHub] World already loaded"); return end

local Util     = H.Util
local Track    = Util.Track
local Lighting = game:GetService("Lighting")

--// ---------------------------------------------------------------------------
--// Low-level helpers
--// ---------------------------------------------------------------------------
local function safeSet(obj, prop, value)
    pcall(function() obj[prop] = value end)
end

local function getOrCreate(class, name)
    local fx = Lighting:FindFirstChild(name)
    if fx and fx.ClassName == class then return fx, false end
    fx = Lighting:FindFirstChildOfClass(class)
    if fx then return fx, false end
    fx = Instance.new(class)
    fx.Name = name
    fx.Enabled = false
    pcall(function() fx.Parent = Lighting end)
    return fx, true
end

--// ---------------------------------------------------------------------------
--// Original state snapshots
--// ---------------------------------------------------------------------------
local OrigLighting = {
    Brightness              = Lighting.Brightness,
    ClockTime               = Lighting.ClockTime,
    Ambient                 = Lighting.Ambient,
    OutdoorAmbient          = Lighting.OutdoorAmbient,
    EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
    EnvironmentSpecularScale= Lighting.EnvironmentSpecularScale,
    ExposureCompensation    = Lighting.ExposureCompensation,
    GlobalShadows           = Lighting.GlobalShadows,
    ShadowSoftness          = Lighting.ShadowSoftness,
    FogColor                = Lighting.FogColor,
    FogStart                = Lighting.FogStart,
    FogEnd                  = Lighting.FogEnd,
}

local OrigAtmosphere = nil
do
    local atm = Lighting:FindFirstChildOfClass("Atmosphere")
    if atm then
        OrigAtmosphere = {
            instance = atm,
            Density  = atm.Density,
            Offset   = atm.Offset,
            Color    = atm.Color,
            Decay    = atm.Decay,
            Glare    = atm.Glare,
            Haze     = atm.Haze,
        }
    end
end

local OrigSky = Lighting:FindFirstChildOfClass("Sky")
local OrigSkyProps = nil
if OrigSky then
    OrigSkyProps = {
        StarCount        = OrigSky.StarCount,
        SunAngularSize   = OrigSky.SunAngularSize,
        MoonAngularSize  = OrigSky.MoonAngularSize,
    }
end

--// Snapshot any post-FX of given class that already exists in Lighting.
local FX_PROPS = {
    "Enabled", "Intensity", "Size", "Threshold",
    "Brightness", "Contrast", "Saturation", "TintColor",
    "FarIntensity", "FocusDistance", "InFocusRadius", "NearIntensity",
    "Spread",
}
local function snapshotFx(class)
    local fx = Lighting:FindFirstChildOfClass(class)
    if not fx then return nil end
    local snap = { instance = fx, properties = {} }
    for _, p in ipairs(FX_PROPS) do
        local ok, val = pcall(function() return fx[p] end)
        if ok then snap.properties[p] = val end
    end
    return snap
end

local OrigFX = {
    Bloom  = snapshotFx("BloomEffect"),
    CC     = snapshotFx("ColorCorrectionEffect"),
    DOF    = snapshotFx("DepthOfFieldEffect"),
    Sun    = snapshotFx("SunRaysEffect"),
    Blur   = snapshotFx("BlurEffect"),
}

--// ---------------------------------------------------------------------------
--// Module state
--// ---------------------------------------------------------------------------
H.World = {
    Settings = {
        -- Core / cleanup
        Fullbright      = false,
        NoShadows       = false,
        RemoveFog       = false,
        RemoveTextures  = false,
        RemoveParticles = false,
        RemoveGrass     = false,
        RemoveSky       = false,

        -- Custom Lighting (RTX core)
        CustomLighting          = false,
        Brightness              = 2,
        ClockTime               = 14,
        ExposureCompensation    = 0,
        AmbientColor            = Color3.fromRGB(70, 70, 70),
        OutdoorAmbientColor     = Color3.fromRGB(128, 128, 128),
        EnvironmentDiffuseScale = 0.5,
        EnvironmentSpecularScale= 0.5,
        ShadowSoftness          = 0.2,
        Technology              = "Future",

        -- Custom Fog
        CustomFog  = false,
        FogStart   = 0,
        FogEnd     = 100000,
        FogColor   = Color3.fromRGB(192, 192, 192),

        -- Atmosphere
        AtmosphereEnabled = false,
        AtmosphereDensity = 0.30,
        AtmosphereOffset  = 0,
        AtmosphereGlare   = 0,
        AtmosphereHaze    = 1.5,
        AtmosphereColor   = Color3.fromRGB(199, 199, 199),
        AtmosphereDecay   = Color3.fromRGB(106, 112, 125),

        -- Bloom
        BloomEnabled   = false,
        BloomIntensity = 0.8,
        BloomSize      = 24,
        BloomThreshold = 2,

        -- Color Correction
        CCEnabled    = false,
        CCBrightness = 0,
        CCContrast   = 0.10,
        CCSaturation = 0.10,
        CCTintColor  = Color3.fromRGB(255, 255, 255),

        -- Depth of Field
        DOFEnabled       = false,
        DOFFarIntensity  = 0.1,
        DOFFocusDistance = 20,
        DOFInFocusRadius = 30,
        DOFNearIntensity = 0.5,

        -- Sun Rays
        SunRaysEnabled   = false,
        SunRaysIntensity = 0.1,
        SunRaysSpread    = 1,

        -- Blur
        BlurEnabled = false,
        BlurSize    = 0,

        -- Sky (custom star/sun/moon sizes — does not replace skybox)
        CustomSky         = false,
        SkyStarCount      = 3000,
        SkySunAngularSize = 21,
        SkyMoonAngularSize= 11,
    },
    Internal = {
        Original = {
            Lighting   = OrigLighting,
            Atmosphere = OrigAtmosphere,
            Sky        = OrigSky,
            SkyProps   = OrigSkyProps,
            FX         = OrigFX,
        },
        Created = {},   -- [Instance] = true if WE created it (destroy on restore)
        Saved   = {},   -- for textures/particles cleanup
        Conns   = {},
    },
    Functions = {},
}
local World = H.World

--// ---------------------------------------------------------------------------
--// Lighting — individual features
--// ---------------------------------------------------------------------------
local function ApplyFullbright()
    safeSet(Lighting, "Brightness", 3)
    safeSet(Lighting, "ClockTime", 14)
    safeSet(Lighting, "Ambient", Color3.fromRGB(180, 180, 180))
    safeSet(Lighting, "OutdoorAmbient", Color3.fromRGB(180, 180, 180))
    safeSet(Lighting, "ExposureCompensation", 0.5)
end
local function RemoveFullbright()
    local O = World.Internal.Original.Lighting
    safeSet(Lighting, "Brightness", O.Brightness)
    safeSet(Lighting, "ClockTime", O.ClockTime)
    safeSet(Lighting, "Ambient", O.Ambient)
    safeSet(Lighting, "OutdoorAmbient", O.OutdoorAmbient)
    safeSet(Lighting, "ExposureCompensation", O.ExposureCompensation)
end

local function ApplyCustomLighting()
    local S = World.Settings
    safeSet(Lighting, "Brightness", S.Brightness)
    safeSet(Lighting, "ClockTime", S.ClockTime)
    safeSet(Lighting, "ExposureCompensation", S.ExposureCompensation)
    safeSet(Lighting, "Ambient", S.AmbientColor)
    safeSet(Lighting, "OutdoorAmbient", S.OutdoorAmbientColor)
    safeSet(Lighting, "EnvironmentDiffuseScale", S.EnvironmentDiffuseScale)
    safeSet(Lighting, "EnvironmentSpecularScale", S.EnvironmentSpecularScale)
    safeSet(Lighting, "ShadowSoftness", S.ShadowSoftness)
    local tech = Enum.Technology and Enum.Technology[S.Technology]
    if tech then pcall(function() Lighting.Technology = tech end) end
end
local function RemoveCustomLighting()
    local O = World.Internal.Original.Lighting
    safeSet(Lighting, "Brightness", O.Brightness)
    safeSet(Lighting, "ClockTime", O.ClockTime)
    safeSet(Lighting, "ExposureCompensation", O.ExposureCompensation)
    safeSet(Lighting, "Ambient", O.Ambient)
    safeSet(Lighting, "OutdoorAmbient", O.OutdoorAmbient)
    safeSet(Lighting, "EnvironmentDiffuseScale", O.EnvironmentDiffuseScale)
    safeSet(Lighting, "EnvironmentSpecularScale", O.EnvironmentSpecularScale)
    safeSet(Lighting, "ShadowSoftness", O.ShadowSoftness)
end

local function ApplyNoShadows() safeSet(Lighting, "GlobalShadows", false) end
local function RemoveNoShadows()
    safeSet(Lighting, "GlobalShadows", World.Internal.Original.Lighting.GlobalShadows)
end

--// ---------------------------------------------------------------------------
--// Fog
--// ---------------------------------------------------------------------------
local function ApplyNoFog()
    safeSet(Lighting, "FogEnd", 1e6)
    safeSet(Lighting, "FogStart", 1e6)
end
local function RemoveNoFog()
    local O = World.Internal.Original.Lighting
    safeSet(Lighting, "FogEnd", O.FogEnd)
    safeSet(Lighting, "FogStart", O.FogStart)
end

local function ApplyCustomFog()
    local S = World.Settings
    safeSet(Lighting, "FogStart", S.FogStart)
    safeSet(Lighting, "FogEnd", S.FogEnd)
    safeSet(Lighting, "FogColor", S.FogColor)
end
local function RemoveCustomFog()
    local O = World.Internal.Original.Lighting
    safeSet(Lighting, "FogStart", O.FogStart)
    safeSet(Lighting, "FogEnd", O.FogEnd)
    safeSet(Lighting, "FogColor", O.FogColor)
end

--// ---------------------------------------------------------------------------
--// Atmosphere
--// ---------------------------------------------------------------------------
local function GetAtmosphere()
    local atm = Lighting:FindFirstChildOfClass("Atmosphere")
    if atm then return atm, false end
    atm = Instance.new("Atmosphere")
    pcall(function() atm.Parent = Lighting end)
    World.Internal.Created[atm] = true
    return atm, true
end

local function ApplyAtmosphere()
    local S = World.Settings
    local atm = GetAtmosphere()
    safeSet(atm, "Density", S.AtmosphereDensity)
    safeSet(atm, "Offset",  S.AtmosphereOffset)
    safeSet(atm, "Glare",   S.AtmosphereGlare)
    safeSet(atm, "Haze",    S.AtmosphereHaze)
    safeSet(atm, "Color",   S.AtmosphereColor)
    safeSet(atm, "Decay",   S.AtmosphereDecay)
end
local function RemoveAtmosphere()
    local atm = Lighting:FindFirstChildOfClass("Atmosphere")
    if not atm then return end
    if World.Internal.Created[atm] then
        pcall(function() atm:Destroy() end)
        World.Internal.Created[atm] = nil
        return
    end
    local O = World.Internal.Original.Atmosphere
    if O and O.instance == atm then
        safeSet(atm, "Density", O.Density)
        safeSet(atm, "Offset",  O.Offset)
        safeSet(atm, "Color",   O.Color)
        safeSet(atm, "Decay",   O.Decay)
        safeSet(atm, "Glare",   O.Glare)
        safeSet(atm, "Haze",    O.Haze)
    end
end

--// ---------------------------------------------------------------------------
--// Post-FX (RTX)
--// ---------------------------------------------------------------------------
local function ApplyBloom()
    local S = World.Settings
    local fx, created = getOrCreate("BloomEffect", "AirHub_Bloom")
    if created then World.Internal.Created[fx] = true end
    safeSet(fx, "Enabled",   S.BloomEnabled)
    safeSet(fx, "Intensity", S.BloomIntensity)
    safeSet(fx, "Size",      S.BloomSize)
    safeSet(fx, "Threshold", S.BloomThreshold)
end
local function RestoreBloom()
    local fx = Lighting:FindFirstChildOfClass("BloomEffect")
    if not fx then return end
    if World.Internal.Created[fx] then
        pcall(function() fx:Destroy() end)
        World.Internal.Created[fx] = nil
        return
    end
    local snap = World.Internal.Original.FX.Bloom
    if snap and snap.instance == fx then
        for k, v in pairs(snap.properties) do safeSet(fx, k, v) end
    else
        safeSet(fx, "Enabled", false)
    end
end

local function ApplyCC()
    local S = World.Settings
    local fx, created = getOrCreate("ColorCorrectionEffect", "AirHub_ColorCorrection")
    if created then World.Internal.Created[fx] = true end
    safeSet(fx, "Enabled",    S.CCEnabled)
    safeSet(fx, "Brightness", S.CCBrightness)
    safeSet(fx, "Contrast",   S.CCContrast)
    safeSet(fx, "Saturation", S.CCSaturation)
    safeSet(fx, "TintColor",  S.CCTintColor)
end
local function RestoreCC()
    local fx = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
    if not fx then return end
    if World.Internal.Created[fx] then
        pcall(function() fx:Destroy() end)
        World.Internal.Created[fx] = nil
        return
    end
    local snap = World.Internal.Original.FX.CC
    if snap and snap.instance == fx then
        for k, v in pairs(snap.properties) do safeSet(fx, k, v) end
    else
        safeSet(fx, "Enabled", false)
    end
end

local function ApplyDOF()
    local S = World.Settings
    local fx, created = getOrCreate("DepthOfFieldEffect", "AirHub_DepthOfField")
    if created then World.Internal.Created[fx] = true end
    safeSet(fx, "Enabled",       S.DOFEnabled)
    safeSet(fx, "FarIntensity",  S.DOFFarIntensity)
    safeSet(fx, "FocusDistance", S.DOFFocusDistance)
    safeSet(fx, "InFocusRadius", S.DOFInFocusRadius)
    safeSet(fx, "NearIntensity", S.DOFNearIntensity)
end
local function RestoreDOF()
    local fx = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
    if not fx then return end
    if World.Internal.Created[fx] then
        pcall(function() fx:Destroy() end)
        World.Internal.Created[fx] = nil
        return
    end
    local snap = World.Internal.Original.FX.DOF
    if snap and snap.instance == fx then
        for k, v in pairs(snap.properties) do safeSet(fx, k, v) end
    else
        safeSet(fx, "Enabled", false)
    end
end

local function ApplySunRays()
    local S = World.Settings
    local fx, created = getOrCreate("SunRaysEffect", "AirHub_SunRays")
    if created then World.Internal.Created[fx] = true end
    safeSet(fx, "Enabled",   S.SunRaysEnabled)
    safeSet(fx, "Intensity", S.SunRaysIntensity)
    safeSet(fx, "Spread",    S.SunRaysSpread)
end
local function RestoreSunRays()
    local fx = Lighting:FindFirstChildOfClass("SunRaysEffect")
    if not fx then return end
    if World.Internal.Created[fx] then
        pcall(function() fx:Destroy() end)
        World.Internal.Created[fx] = nil
        return
    end
    local snap = World.Internal.Original.FX.Sun
    if snap and snap.instance == fx then
        for k, v in pairs(snap.properties) do safeSet(fx, k, v) end
    else
        safeSet(fx, "Enabled", false)
    end
end

local function ApplyBlur()
    local S = World.Settings
    local fx, created = getOrCreate("BlurEffect", "AirHub_Blur")
    if created then World.Internal.Created[fx] = true end
    safeSet(fx, "Enabled", S.BlurEnabled)
    safeSet(fx, "Size",    S.BlurSize)
end
local function RestoreBlur()
    local fx = Lighting:FindFirstChildOfClass("BlurEffect")
    if not fx then return end
    if World.Internal.Created[fx] then
        pcall(function() fx:Destroy() end)
        World.Internal.Created[fx] = nil
        return
    end
    local snap = World.Internal.Original.FX.Blur
    if snap and snap.instance == fx then
        for k, v in pairs(snap.properties) do safeSet(fx, k, v) end
    else
        safeSet(fx, "Enabled", false)
    end
end

--// ---------------------------------------------------------------------------
--// Sky (star / sun / moon size — does NOT replace skybox)
--// ---------------------------------------------------------------------------
local function ApplySky()
    local S = World.Settings
    local sky = Lighting:FindFirstChildOfClass("Sky")
    if not sky then
        sky = Instance.new("Sky")
        pcall(function() sky.Parent = Lighting end)
        World.Internal.Created[sky] = true
    end
    safeSet(sky, "StarCount",       S.SkyStarCount)
    safeSet(sky, "SunAngularSize",  S.SkySunAngularSize)
    safeSet(sky, "MoonAngularSize", S.SkyMoonAngularSize)
end
local function RemoveSkyCustom()
    local sky = Lighting:FindFirstChildOfClass("Sky")
    if not sky then return end
    if World.Internal.Created[sky] then
        pcall(function() sky:Destroy() end)
        World.Internal.Created[sky] = nil
        return
    end
    local O = World.Internal.Original.SkyProps
    if O then
        safeSet(sky, "StarCount",       O.StarCount)
        safeSet(sky, "SunAngularSize",  O.SunAngularSize)
        safeSet(sky, "MoonAngularSize", O.MoonAngularSize)
    end
end

--// ---------------------------------------------------------------------------
--// Textures / Particles / Grass / Sky removal (Cleanup section)
--// ---------------------------------------------------------------------------
local function stripTextures(obj)
    if obj:IsA("BasePart") then
        for _, d in ipairs(obj:GetChildren()) do
            if d:IsA("Decal") or d:IsA("Texture") then
                if not World.Internal.Saved[d] then
                    World.Internal.Saved[d] = { kind = "decal", value = d.Transparency }
                end
                safeSet(d, "Transparency", 1)
            end
        end
    elseif obj:IsA("Decal") or obj:IsA("Texture") then
        if not World.Internal.Saved[obj] then
            World.Internal.Saved[obj] = { kind = "decal", value = obj.Transparency }
        end
        safeSet(obj, "Transparency", 1)
    end
end
local function ApplyRemoveTextures()
    for _, obj in ipairs(workspace:GetDescendants()) do
        stripTextures(obj)
    end
    if not World.Internal.Conns.tex then
        World.Internal.Conns.tex = workspace.DescendantAdded:Connect(function(obj)
            if World.Settings.RemoveTextures then stripTextures(obj) end
        end)
    end
end
local function RemoveRemoveTextures()
    local toRemove = {}
    for obj, data in pairs(World.Internal.Saved) do
        if data.kind == "decal" then
            safeSet(obj, "Transparency", data.value)
            table.insert(toRemove, obj)
        end
    end
    for _, obj in ipairs(toRemove) do
        World.Internal.Saved[obj] = nil
    end
    if World.Internal.Conns.tex then
        World.Internal.Conns.tex:Disconnect()
        World.Internal.Conns.tex = nil
    end
end

local PARTICLE_CLASSES = { "ParticleEmitter", "Trail", "Beam", "Fire", "Smoke", "Sparkles" }
local function isParticle(obj)
    for _, c in ipairs(PARTICLE_CLASSES) do
        if obj:IsA(c) then return true end
    end
    return false
end
local function ApplyRemoveParticles()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if isParticle(obj) then
            if not World.Internal.Saved[obj] then
                World.Internal.Saved[obj] = { kind = "particle", value = obj.Enabled }
            end
            safeSet(obj, "Enabled", false)
        end
    end
end
local function RemoveRemoveParticles()
    local toRemove = {}
    for obj, data in pairs(World.Internal.Saved) do
        if data.kind == "particle" then
            safeSet(obj, "Enabled", data.value)
            table.insert(toRemove, obj)
        end
    end
    for _, obj in ipairs(toRemove) do
        World.Internal.Saved[obj] = nil
    end
end

local function ApplyRemoveGrass()
    local terrain = workspace:FindFirstChildOfClass("Terrain")
    if terrain then safeSet(terrain, "Decoration", false) end
end
local function RemoveRemoveGrass()
    local terrain = workspace:FindFirstChildOfClass("Terrain")
    if terrain then safeSet(terrain, "Decoration", true) end
end

local function ApplyRemoveSky()
    local sky = Lighting:FindFirstChildOfClass("Sky")
    if sky then
        World.Internal.Original.Sky = sky
        safeSet(sky, "Parent", nil)
    end
end
local function RemoveRemoveSky()
    local O = World.Internal.Original.Sky
    if O and not O.Parent then
        safeSet(O, "Parent", Lighting)
    end
end

--// ---------------------------------------------------------------------------
--// Master apply — read Settings, reset, then apply active features
--// ---------------------------------------------------------------------------
local function ApplyLook()
    -- 1) Reset everything we might have touched
    RemoveFullbright()
    RemoveCustomLighting()
    RemoveNoFog()
    RemoveCustomFog()
    RemoveNoShadows()
    RemoveAtmosphere()
    RemoveSkyCustom()

    -- 2) Apply active features
    local S = World.Settings
    if S.Fullbright      then ApplyFullbright()      end
    if S.CustomLighting  then ApplyCustomLighting()  end
    if S.RemoveFog       then ApplyNoFog()           end
    if S.CustomFog       then ApplyCustomFog()       end
    if S.NoShadows       then ApplyNoShadows()       end
    if S.AtmosphereEnabled then ApplyAtmosphere()    end
    if S.CustomSky       then ApplySky()             end

    -- 3) Post-FX — the apply functions set Enabled from settings
    ApplyBloom()
    ApplyCC()
    ApplyDOF()
    ApplySunRays()
    ApplyBlur()
end
World.ApplyLook = ApplyLook

--// ---------------------------------------------------------------------------
--// Restore everything
--// ---------------------------------------------------------------------------
World.Functions.Restore = function()
    RemoveFullbright()
    RemoveCustomLighting()
    RemoveNoFog()
    RemoveCustomFog()
    RemoveNoShadows()
    RemoveAtmosphere()
    RemoveSkyCustom()
    RemoveRemoveTextures()
    RemoveRemoveParticles()
    RemoveRemoveGrass()
    RemoveRemoveSky()
    RestoreBloom()
    RestoreCC()
    RestoreDOF()
    RestoreSunRays()
    RestoreBlur()

    -- reset all feature toggles
    local S = World.Settings
    S.Fullbright = false
    S.NoShadows = false
    S.RemoveFog = false
    S.CustomLighting = false
    S.CustomFog = false
    S.AtmosphereEnabled = false
    S.CustomSky = false
    S.BloomEnabled = false
    S.CCEnabled = false
    S.DOFEnabled = false
    S.SunRaysEnabled = false
    S.BlurEnabled = false
    S.RemoveTextures = false
    S.RemoveParticles = false
    S.RemoveGrass = false
    S.RemoveSky = false
end

--// ---------------------------------------------------------------------------
--// Presets
--// ---------------------------------------------------------------------------
local function Preset_RTXUltra()
    local S = World.Settings
    S.CustomLighting = true
    S.Brightness = 2
    S.ClockTime = 14
    S.ExposureCompensation = 0.15
    S.AmbientColor = Color3.fromRGB(70, 70, 70)
    S.OutdoorAmbientColor = Color3.fromRGB(128, 128, 128)
    S.EnvironmentDiffuseScale = 1
    S.EnvironmentSpecularScale = 1
    S.ShadowSoftness = 0.15
    S.Technology = "Future"

    S.CustomFog = false
    S.RemoveFog = false

    S.AtmosphereEnabled = true
    S.AtmosphereDensity = 0.25
    S.AtmosphereOffset = 0
    S.AtmosphereGlare = 0.2
    S.AtmosphereHaze = 1.2
    S.AtmosphereColor = Color3.fromRGB(199, 199, 199)
    S.AtmosphereDecay = Color3.fromRGB(106, 112, 125)

    S.BloomEnabled = true
    S.BloomIntensity = 1.2
    S.BloomSize = 24
    S.BloomThreshold = 1.5

    S.CCEnabled = true
    S.CCBrightness = 0
    S.CCContrast = 0.15
    S.CCSaturation = 0.15
    S.CCTintColor = Color3.fromRGB(255, 255, 255)

    S.SunRaysEnabled = true
    S.SunRaysIntensity = 0.15
    S.SunRaysSpread = 1

    S.DOFEnabled = false
    S.BlurEnabled = false

    ApplyLook()
end

local function Preset_Cinematic()
    local S = World.Settings
    S.CustomLighting = true
    S.Brightness = 1.8
    S.ClockTime = 17.5
    S.ExposureCompensation = -0.1
    S.AmbientColor = Color3.fromRGB(60, 60, 70)
    S.OutdoorAmbientColor = Color3.fromRGB(110, 110, 130)
    S.EnvironmentDiffuseScale = 0.8
    S.EnvironmentSpecularScale = 1
    S.ShadowSoftness = 0.3
    S.Technology = "Future"

    S.AtmosphereEnabled = true
    S.AtmosphereDensity = 0.35
    S.AtmosphereGlare = 0.4
    S.AtmosphereHaze = 2.0
    S.AtmosphereColor = Color3.fromRGB(220, 200, 190)

    S.BloomEnabled = true
    S.BloomIntensity = 0.8
    S.BloomSize = 32
    S.BloomThreshold = 2

    S.CCEnabled = true
    S.CCBrightness = -0.02
    S.CCContrast = 0.2
    S.CCSaturation = -0.05
    S.CCTintColor = Color3.fromRGB(230, 235, 255)

    S.DOFEnabled = true
    S.DOFFarIntensity = 0.5
    S.DOFFocusDistance = 25
    S.DOFInFocusRadius = 18
    S.DOFNearIntensity = 0.3

    S.SunRaysEnabled = true
    S.SunRaysIntensity = 0.2
    S.SunRaysSpread = 0.9

    ApplyLook()
end

local function Preset_Clean()
    local S = World.Settings
    S.CustomLighting = false
    S.CustomFog = false
    S.AtmosphereEnabled = false
    S.CustomSky = false
    S.BloomEnabled = false
    S.CCEnabled = false
    S.DOFEnabled = false
    S.SunRaysEnabled = false
    S.BlurEnabled = false

    S.Fullbright = true
    S.RemoveFog = true
    S.NoShadows = true

    ApplyLook()
end

--// ---------------------------------------------------------------------------
--// UI
--// ---------------------------------------------------------------------------
local refs = {}   -- control references for preset sync

local function setRef(key, ctrl) refs[key] = ctrl end
local function syncRef(key, value)
    local c = refs[key]
    if not c then return end
    if type(c.Set) == "function" then pcall(function() c:Set(value) end) end
end

local function SyncPresetUI()
    local S = World.Settings
    syncRef("CustomLighting", S.CustomLighting)
    syncRef("Brightness", S.Brightness)
    syncRef("ClockTime", S.ClockTime)
    syncRef("ExposureCompensation", S.ExposureCompensation)
    syncRef("EnvironmentDiffuseScale", S.EnvironmentDiffuseScale)
    syncRef("EnvironmentSpecularScale", S.EnvironmentSpecularScale)
    syncRef("ShadowSoftness", S.ShadowSoftness)

    syncRef("AtmosphereEnabled", S.AtmosphereEnabled)
    syncRef("AtmosphereDensity", S.AtmosphereDensity)
    syncRef("AtmosphereGlare", S.AtmosphereGlare)
    syncRef("AtmosphereHaze", S.AtmosphereHaze)

    syncRef("BloomEnabled", S.BloomEnabled)
    syncRef("BloomIntensity", S.BloomIntensity)
    syncRef("BloomSize", S.BloomSize)
    syncRef("BloomThreshold", S.BloomThreshold)

    syncRef("CCEnabled", S.CCEnabled)
    syncRef("CCBrightness", S.CCBrightness)
    syncRef("CCContrast", S.CCContrast)
    syncRef("CCSaturation", S.CCSaturation)

    syncRef("DOFEnabled", S.DOFEnabled)
    syncRef("DOFFarIntensity", S.DOFFarIntensity)
    syncRef("DOFFocusDistance", S.DOFFocusDistance)
    syncRef("DOFInFocusRadius", S.DOFInFocusRadius)
    syncRef("DOFNearIntensity", S.DOFNearIntensity)

    syncRef("SunRaysEnabled", S.SunRaysEnabled)
    syncRef("SunRaysIntensity", S.SunRaysIntensity)
    syncRef("SunRaysSpread", S.SunRaysSpread)

    syncRef("Fullbright", S.Fullbright)
    syncRef("RemoveFog", S.RemoveFog)
    syncRef("NoShadows", S.NoShadows)
end

local function FillUI()
    local tab = H._UI and H._UI.WorldTab
    if not tab then return false end

    local S = World.Settings

    -- =====================================================================
    -- LEFT: Lighting
    -- =====================================================================
    local secL = tab:CreateSection({ Name = "Lighting" })

    setRef("Fullbright", secL:AddToggle({
        Name = "Fullbright", Value = S.Fullbright,
        Callback = function(v)
            S.Fullbright = v
            if v then S.CustomLighting = false; syncRef("CustomLighting", false) end
            ApplyLook()
        end,
    }))

    setRef("CustomLighting", secL:AddToggle({
        Name = "Custom Lighting (RTX)", Value = S.CustomLighting,
        Callback = function(v)
            S.CustomLighting = v
            if v then S.Fullbright = false; syncRef("Fullbright", false) end
            ApplyLook()
        end,
    }))

    setRef("Brightness", secL:AddSlider({
        Name = "Brightness", Value = S.Brightness, Min = 0, Max = 10, Decimals = 2,
        Callback = function(v) S.Brightness = v ApplyLook() end,
    }))
    setRef("ClockTime", secL:AddSlider({
        Name = "Clock Time (h)", Value = S.ClockTime, Min = 0, Max = 24, Decimals = 2,
        Callback = function(v) S.ClockTime = v ApplyLook() end,
    }))
    setRef("ExposureCompensation", secL:AddSlider({
        Name = "Exposure Compensation", Value = S.ExposureCompensation,
        Min = -3, Max = 3, Decimals = 2,
        Callback = function(v) S.ExposureCompensation = v ApplyLook() end,
    }))
    secL:AddColorpicker({
        Name = "Ambient Color", Value = S.AmbientColor,
        Callback = function(v) S.AmbientColor = v ApplyLook() end,
    })
    secL:AddColorpicker({
        Name = "Outdoor Ambient Color", Value = S.OutdoorAmbientColor,
        Callback = function(v) S.OutdoorAmbientColor = v ApplyLook() end,
    })
    setRef("EnvironmentDiffuseScale", secL:AddSlider({
        Name = "Env Diffuse Scale (soft light)", Value = S.EnvironmentDiffuseScale,
        Min = 0, Max = 1, Decimals = 2,
        Callback = function(v) S.EnvironmentDiffuseScale = v ApplyLook() end,
    }))
    setRef("EnvironmentSpecularScale", secL:AddSlider({
        Name = "Env Specular Scale (reflections)", Value = S.EnvironmentSpecularScale,
        Min = 0, Max = 1, Decimals = 2,
        Callback = function(v) S.EnvironmentSpecularScale = v ApplyLook() end,
    }))
    setRef("ShadowSoftness", secL:AddSlider({
        Name = "Shadow Softness", Value = S.ShadowSoftness,
        Min = 0, Max = 1, Decimals = 2,
        Callback = function(v) S.ShadowSoftness = v ApplyLook() end,
    }))
    secL:AddDropdown({
        Name = "Shadow Technology", Value = S.Technology,
        List = { "Voxel", "ShadowMap", "Future", "Legacy" },
        Callback = function(v) S.Technology = v ApplyLook() end,
    })

    -- =====================================================================
    -- LEFT: Fog & Atmosphere
    -- =====================================================================
    local secFog = tab:CreateSection({ Name = "Fog & Atmosphere" })

    setRef("RemoveFog", secFog:AddToggle({
        Name = "Remove Fog", Value = S.RemoveFog,
        Callback = function(v)
            S.RemoveFog = v
            if v then S.CustomFog = false end
            ApplyLook()
        end,
    }))
    secFog:AddToggle({
        Name = "Custom Fog", Value = S.CustomFog,
        Callback = function(v)
            S.CustomFog = v
            if v then S.RemoveFog = false; syncRef("RemoveFog", false) end
            ApplyLook()
        end,
    })
    secFog:AddSlider({
        Name = "Fog Start", Value = S.FogStart, Min = 0, Max = 5000,
        Callback = function(v) S.FogStart = v ApplyLook() end,
    })
    secFog:AddSlider({
        Name = "Fog End", Value = S.FogEnd, Min = 0, Max = 100000,
        Callback = function(v) S.FogEnd = v ApplyLook() end,
    })
    secFog:AddColorpicker({
        Name = "Fog Color", Value = S.FogColor,
        Callback = function(v) S.FogColor = v ApplyLook() end,
    })

    setRef("AtmosphereEnabled", secFog:AddToggle({
        Name = "Atmosphere", Value = S.AtmosphereEnabled,
        Callback = function(v) S.AtmosphereEnabled = v ApplyLook() end,
    }))
    setRef("AtmosphereDensity", secFog:AddSlider({
        Name = "Atmosphere Density", Value = S.AtmosphereDensity,
        Min = 0, Max = 1, Decimals = 2,
        Callback = function(v) S.AtmosphereDensity = v ApplyLook() end,
    }))
    secFog:AddSlider({
        Name = "Atmosphere Offset", Value = S.AtmosphereOffset,
        Min = -1, Max = 1, Decimals = 2,
        Callback = function(v) S.AtmosphereOffset = v ApplyLook() end,
    })
    setRef("AtmosphereGlare", secFog:AddSlider({
        Name = "Atmosphere Glare", Value = S.AtmosphereGlare,
        Min = 0, Max = 10, Decimals = 2,
        Callback = function(v) S.AtmosphereGlare = v ApplyLook() end,
    }))
    setRef("AtmosphereHaze", secFog:AddSlider({
        Name = "Atmosphere Haze", Value = S.AtmosphereHaze,
        Min = 0, Max = 10, Decimals = 2,
        Callback = function(v) S.AtmosphereHaze = v ApplyLook() end,
    }))
    secFog:AddColorpicker({
        Name = "Atmosphere Color", Value = S.AtmosphereColor,
        Callback = function(v) S.AtmosphereColor = v ApplyLook() end,
    })
    secFog:AddColorpicker({
        Name = "Atmosphere Decay", Value = S.AtmosphereDecay,
        Callback = function(v) S.AtmosphereDecay = v ApplyLook() end,
    })

    -- =====================================================================
    -- RIGHT: Post-FX (RTX)
    -- =====================================================================
    local secFx = tab:CreateSection({ Name = "Post-FX (RTX)", Side = "Right" })

    setRef("BloomEnabled", secFx:AddToggle({
        Name = "Bloom", Value = S.BloomEnabled,
        Callback = function(v) S.BloomEnabled = v ApplyLook() end,
    }))
    setRef("BloomIntensity", secFx:AddSlider({
        Name = "Bloom Intensity", Value = S.BloomIntensity,
        Min = 0, Max = 5, Decimals = 2,
        Callback = function(v) S.BloomIntensity = v ApplyLook() end,
    }))
    setRef("BloomSize", secFx:AddSlider({
        Name = "Bloom Size", Value = S.BloomSize, Min = 0, Max = 56,
        Callback = function(v) S.BloomSize = v ApplyLook() end,
    }))
    setRef("BloomThreshold", secFx:AddSlider({
        Name = "Bloom Threshold", Value = S.BloomThreshold,
        Min = 0, Max = 5, Decimals = 2,
        Callback = function(v) S.BloomThreshold = v ApplyLook() end,
    }))

    setRef("CCEnabled", secFx:AddToggle({
        Name = "Color Correction", Value = S.CCEnabled,
        Callback = function(v) S.CCEnabled = v ApplyLook() end,
    }))
    setRef("CCBrightness", secFx:AddSlider({
        Name = "CC Brightness", Value = S.CCBrightness,
        Min = -1, Max = 1, Decimals = 2,
        Callback = function(v) S.CCBrightness = v ApplyLook() end,
    }))
    setRef("CCContrast", secFx:AddSlider({
        Name = "CC Contrast", Value = S.CCContrast,
        Min = -1, Max = 1, Decimals = 2,
        Callback = function(v) S.CCContrast = v ApplyLook() end,
    }))
    setRef("CCSaturation", secFx:AddSlider({
        Name = "CC Saturation", Value = S.CCSaturation,
        Min = -1, Max = 1, Decimals = 2,
        Callback = function(v) S.CCSaturation = v ApplyLook() end,
    }))
    secFx:AddColorpicker({
        Name = "CC Tint", Value = S.CCTintColor,
        Callback = function(v) S.CCTintColor = v ApplyLook() end,
    })

    setRef("DOFEnabled", secFx:AddToggle({
        Name = "Depth of Field", Value = S.DOFEnabled,
        Callback = function(v) S.DOFEnabled = v ApplyLook() end,
    }))
    setRef("DOFFarIntensity", secFx:AddSlider({
        Name = "DOF Far Intensity", Value = S.DOFFarIntensity,
        Min = 0, Max = 1, Decimals = 2,
        Callback = function(v) S.DOFFarIntensity = v ApplyLook() end,
    }))
    setRef("DOFFocusDistance", secFx:AddSlider({
        Name = "DOF Focus Distance", Value = S.DOFFocusDistance,
        Min = 0, Max = 200,
        Callback = function(v) S.DOFFocusDistance = v ApplyLook() end,
    }))
    setRef("DOFInFocusRadius", secFx:AddSlider({
        Name = "DOF In-Focus Radius", Value = S.DOFInFocusRadius,
        Min = 0, Max = 200,
        Callback = function(v) S.DOFInFocusRadius = v ApplyLook() end,
    }))
    setRef("DOFNearIntensity", secFx:AddSlider({
        Name = "DOF Near Intensity", Value = S.DOFNearIntensity,
        Min = 0, Max = 1, Decimals = 2,
        Callback = function(v) S.DOFNearIntensity = v ApplyLook() end,
    }))

    setRef("SunRaysEnabled", secFx:AddToggle({
        Name = "Sun Rays", Value = S.SunRaysEnabled,
        Callback = function(v) S.SunRaysEnabled = v ApplyLook() end,
    }))
    setRef("SunRaysIntensity", secFx:AddSlider({
        Name = "Sun Rays Intensity", Value = S.SunRaysIntensity,
        Min = 0, Max = 1, Decimals = 2,
        Callback = function(v) S.SunRaysIntensity = v ApplyLook() end,
    }))
    setRef("SunRaysSpread", secFx:AddSlider({
        Name = "Sun Rays Spread", Value = S.SunRaysSpread,
        Min = 0, Max = 1, Decimals = 2,
        Callback = function(v) S.SunRaysSpread = v ApplyLook() end,
    }))

    secFx:AddToggle({
        Name = "Blur", Value = S.BlurEnabled,
        Callback = function(v) S.BlurEnabled = v ApplyLook() end,
    })
    secFx:AddSlider({
        Name = "Blur Size", Value = S.BlurSize, Min = 0, Max = 56,
        Callback = function(v) S.BlurSize = v ApplyLook() end,
    })

    -- =====================================================================
    -- RIGHT: Sky
    -- =====================================================================
    local secSky = tab:CreateSection({ Name = "Sky", Side = "Right" })
    secSky:AddToggle({
        Name = "Custom Sky Params", Value = S.CustomSky,
        Callback = function(v) S.CustomSky = v ApplyLook() end,
    })
    secSky:AddSlider({
        Name = "Star Count", Value = S.SkyStarCount, Min = 0, Max = 10000,
        Callback = function(v) S.SkyStarCount = v ApplyLook() end,
    })
    secSky:AddSlider({
        Name = "Sun Angular Size", Value = S.SkySunAngularSize,
        Min = 0, Max = 90,
        Callback = function(v) S.SkySunAngularSize = v ApplyLook() end,
    })
    secSky:AddSlider({
        Name = "Moon Angular Size", Value = S.SkyMoonAngularSize,
        Min = 0, Max = 90,
        Callback = function(v) S.SkyMoonAngularSize = v ApplyLook() end,
    })

    -- =====================================================================
    -- LEFT: Cleanup (map visual removal)
    -- =====================================================================
    local secClean = tab:CreateSection({ Name = "Cleanup" })
    secClean:AddToggle({
        Name = "No Global Shadows", Value = S.NoShadows,
        Callback = function(v) S.NoShadows = v ApplyLook() end,
    })
    secClean:AddToggle({
        Name = "Remove Textures / Decals", Value = S.RemoveTextures,
        Callback = function(v)
            S.RemoveTextures = v
            if v then ApplyRemoveTextures() else RemoveRemoveTextures() end
        end,
    })
    secClean:AddToggle({
        Name = "Remove Particles", Value = S.RemoveParticles,
        Callback = function(v)
            S.RemoveParticles = v
            if v then ApplyRemoveParticles() else RemoveRemoveParticles() end
        end,
    })
    secClean:AddToggle({
        Name = "Remove Grass", Value = S.RemoveGrass,
        Callback = function(v)
            S.RemoveGrass = v
            if v then ApplyRemoveGrass() else RemoveRemoveGrass() end
        end,
    })
    secClean:AddToggle({
        Name = "Remove Sky (hide skybox)", Value = S.RemoveSky,
        Callback = function(v)
            S.RemoveSky = v
            if v then ApplyRemoveSky() else RemoveRemoveSky() end
        end,
    })

    -- =====================================================================
    -- RIGHT: Presets
    -- =====================================================================
    local secPre = tab:CreateSection({ Name = "Presets", Side = "Right" })
    secPre:AddButton({
        Name = "RTX Ultra",
        Callback = function()
            Preset_RTXUltra()
            SyncPresetUI()
            if Util.ShowError then Util.ShowError("RTX Ultra applied") end
        end,
    })
    secPre:AddButton({
        Name = "Cinematic",
        Callback = function()
            Preset_Cinematic()
            SyncPresetUI()
            if Util.ShowError then Util.ShowError("Cinematic applied") end
        end,
    })
    secPre:AddButton({
        Name = "Clean (Performance)",
        Callback = function()
            Preset_Clean()
            SyncPresetUI()
            if Util.ShowError then Util.ShowError("Clean preset applied") end
        end,
    })
    secPre:AddButton({
        Name = "Restore All World Settings",
        Callback = function()
            World.Functions.Restore()
            SyncPresetUI()
            if Util.ShowError then Util.ShowError("World restored") end
        end,
    })

    return true
end

if not FillUI() then
    task.spawn(function()
        for _ = 1, 60 do
            if H.ShuttingDown then return end
            if FillUI() then return end
            task.wait(0.5)
        end
        warn("[AirHub] 08_world: WorldTab not found after 30s")
    end)
end
