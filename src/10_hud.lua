--// AirHub - 10_hud.lua
--// DEPRECATED: this module used to inject a second "HUD" section into the
--// Visuals tab, duplicating the one already provided by 04_wallhack.lua
--// (which owns WallHack.Visuals.HUDSettings and WallHack.Functions.*HUD*).
--//
--// To avoid duplicate sections and two overlapping HUDs on screen, all HUD
--// logic lives in 04_wallhack.lua now. This file is intentionally a no-op
--// so that loader.lua's file list stays unchanged.

local H = getgenv().AirHub
if not H or not H._CoreLoaded then
    warn("[AirHub] 10_hud: core not loaded")
    return
end

--// No-op stub — HUD is provided by 04_wallhack.lua.
return
