local REPO = "https://raw.githubusercontent.com/lolipopins/airhub-remake/main/src/"

local FILES = {
    "01_core.lua",
    "02_aimbot.lua",
    "03_antiaim.lua",
    "04_wallhack.lua",
    "05_serverposition.lua",
    "06a_movement_fly_bhop.lua",
    "06b_movement_speed_strafer.lua",
    "07a_ui_core.lua",
    "07b_ui_tabs.lua",
}

local function Fetch(url)
    local ok, res = pcall(function() return game:HttpGet(url) end)
    if ok and type(res) == "string" and #res > 0 then return res end
    if type(request) == "function" then
        local ok2, r2 = pcall(function()
            return request({ Url = url, Method = "GET" }).Body
        end)
        if ok2 and type(r2) == "string" and #r2 > 0 then return r2 end
    end
    return nil
end

local function RunModule(filename)
    local url = REPO .. filename
    local src = Fetch(url)
    if not src then
        warn("[AirHub] Failed to download: " .. filename .. " (" .. url .. ")")
        return false
    end
    local chunk, compileErr = loadstring(src, "@" .. filename)
    if not chunk then
        warn("[AirHub] Compile error in " .. filename .. ": " .. tostring(compileErr))
        return false
    end
    local runOk, runErr = pcall(chunk)
    if not runOk then
        warn("[AirHub] Runtime error in " .. filename .. ": " .. tostring(runErr))
        return false
    end
    return true
end

for _, file in ipairs(FILES) do
    if not RunModule(file) then
        warn("[AirHub] Aborting — module '" .. file .. "' failed.")
        return
    end
    task.wait()
end

warn("[AirHub] All modules loaded successfully")
