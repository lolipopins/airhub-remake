local REPO = "https://raw.githubusercontent.com/lolipopins/airhub-remake/main/src/"

local PRE_FILES = {
    -- Античит-байпас грузится ПЕРВЫМ, до всех модулей
    "https://raw.githubusercontent.com/lolipopins/airhub-remake/refs/heads/main/anticheat%20bypass",
}

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

local function RunFromURL(url, label, required)
    local src = Fetch(url)
    if not src then
        warn("[AirHub] Failed to download: " .. label .. " (" .. url .. ")")
        return not required
    end
    local chunk, compileErr = loadstring(src, "@" .. label)
    if not chunk then
        warn("[AirHub] Compile error in " .. label .. ": " .. tostring(compileErr))
        return not required
    end
    local runOk, runErr = pcall(chunk)
    if not runOk then
        warn("[AirHub] Runtime error in " .. label .. ": " .. tostring(runErr))
        return not required
    end
    return true
end

--// Античит-байпас (если упадёт — грузим остальное всё равно)
for i, url in ipairs(PRE_FILES) do
    RunFromURL(url, "pre_" .. i, false)
    task.wait()
end

--// Основные модули (если хоть один упадёт — прерываем загрузку)
for _, file in ipairs(FILES) do
    if not RunFromURL(REPO .. file, file, true) then
        warn("[AirHub] Aborting — module '" .. file .. "' failed.")
        return
    end
    task.wait()
end

warn("[AirHub] All modules loaded successfully")
