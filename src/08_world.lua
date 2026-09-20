--// AirHub - 08_world.lua
--// World tab: Lighting / Sky / Environment / Map tweaks (visuals only).

local H = getgenv().AirHub
if not H or not H._CoreLoaded then warn("[AirHub] 08_world: core not loaded"); return end
if H.World then warn("[AirHub] World already loaded"); return end

local Util     = H.Util
local Track    = Util.Track
local Lighting = game:GetService("Lighting")

H.World = {
    Settings = {
        Fullbright      = false,
        RemoveFog       = false,
        NoShadows       = false,
        RemoveTextures  = false,
        RemoveParticles = false,
        RemoveGrass     = false,
        RemoveSky       = false,
    },
    Internal = {
        Original = {
            Brightness           = Lighting.Brightness,
            ClockTime            = Lighting.ClockTime,
            Ambient              = Lighting.Ambient,
            OutdoorAmbient       = Lighting.OutdoorAmbient,
            FogEnd               = Lighting.FogEnd,
            FogStart             = Lighting.FogStart,
            GlobalShadows        = Lighting.GlobalShadows,
            ExposureCompensation = Lighting.ExposureCompensation,
            Sky                  = Lighting:FindFirstChildOfClass("Sky"),
        },
        Saved = {},
        Conns = {},
    },
    Functions = {},
}
local World = H.World

local function safeSet(obj, prop, value)
    pcall(function() obj[prop] = value end)
end

local function ApplyFullbright()
    safeSet(Lighting, "Brightness", 3)
    safeSet(Lighting, "ClockTime", 14)
    safeSet(Lighting, "Ambient", Color3.fromRGB(180, 180, 180))
    safeSet(Lighting, "OutdoorAmbient", Color3.fromRGB(180, 180, 180))
    safeSet(Lighting, "ExposureCompensation", 0.5)
end
local function RemoveFullbright()
    local O = World.Internal.Original
    safeSet(Lighting, "Brightness", O.Brightness)
    safeSet(Lighting, "ClockTime", O.ClockTime)
    safeSet(Lighting, "Ambient", O.Ambient)
    safeSet(Lighting, "OutdoorAmbient", O.OutdoorAmbient)
    safeSet(Lighting, "ExposureCompensation", O.ExposureCompensation)
end

local function ApplyNoFog()
    safeSet(Lighting, "FogEnd", 1e6)
    safeSet(Lighting, "FogStart", 1e6)
end
local function RemoveNoFog()
    local O = World.Internal.Original
    safeSet(Lighting, "FogEnd", O.FogEnd)
    safeSet(Lighting, "FogStart", O.FogStart)
end

local function ApplyNoShadows() safeSet(Lighting, "GlobalShadows", false) end
local function RemoveNoShadows()
    safeSet(Lighting, "GlobalShadows", World.Internal.Original.GlobalShadows)
end

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
--// FIXED: mutate table via collected key list, not directly inside `pairs`.
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
--// FIXED: same pairs-mutation fix.
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
    local O = World.Internal.Original
    if O.Sky and not O.Sky.Parent then
        safeSet(O.Sky, "Parent", Lighting)
    end
end

World.Functions.Restore = function()
    RemoveFullbright()
    RemoveNoFog()
    RemoveNoShadows()
    RemoveRemoveTextures()
    RemoveRemoveParticles()
    RemoveRemoveGrass()
    RemoveRemoveSky()
end

local function FillUI()
    local tab = H._UI and H._UI.WorldTab
    if not tab then return false end

    local secL = tab:CreateSection({ Name = "Lighting" })
    secL:AddToggle({ Name = "Fullbright", Value = World.Settings.Fullbright, Callback = function(v)
        World.Settings.Fullbright = v
        if v then ApplyFullbright() else RemoveFullbright() end
    end })
    secL:AddToggle({ Name = "Remove Fog", Value = World.Settings.RemoveFog, Callback = function(v)
        World.Settings.RemoveFog = v
        if v then ApplyNoFog() else RemoveNoFog() end
    end })
    secL:AddToggle({ Name = "No Global Shadows", Value = World.Settings.NoShadows, Callback = function(v)
        World.Settings.NoShadows = v
        if v then ApplyNoShadows() else RemoveNoShadows() end
    end })

    local secV = tab:CreateSection({ Name = "Visuals", Side = "Right" })
    secV:AddToggle({ Name = "Remove Textures / Decals", Value = World.Settings.RemoveTextures, Callback = function(v)
        World.Settings.RemoveTextures = v
        if v then ApplyRemoveTextures() else RemoveRemoveTextures() end
    end })
    secV:AddToggle({ Name = "Remove Particles", Value = World.Settings.RemoveParticles, Callback = function(v)
        World.Settings.RemoveParticles = v
        if v then ApplyRemoveParticles() else RemoveRemoveParticles() end
    end })
    secV:AddToggle({ Name = "Remove Grass", Value = World.Settings.RemoveGrass, Callback = function(v)
        World.Settings.RemoveGrass = v
        if v then ApplyRemoveGrass() else RemoveRemoveGrass() end
    end })
    secV:AddToggle({ Name = "Remove Sky", Value = World.Settings.RemoveSky, Callback = function(v)
        World.Settings.RemoveSky = v
        if v then ApplyRemoveSky() else RemoveRemoveSky() end
    end })

    local secM = tab:CreateSection({ Name = "Presets" })
    secM:AddButton({ Name = "Restore All World Settings", Callback = function()
        World.Functions.Restore()
        for k in pairs(World.Settings) do World.Settings[k] = false end
    end })

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
