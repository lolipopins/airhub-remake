local REPO = "https://raw.githubusercontent.com/lolipopins/airhub-remake/main/src/"

local PRE_FILES = {
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

--// ---------------------------------------------------------------------------
--// Античит-байпас — глушим весь его вывод, отчёт делает лоадер.
--// ---------------------------------------------------------------------------
local realWarn = warn
local realPrint = print

local function RunBypassSilently(url)
    local src = Fetch(url)
    if not src then
        return false, "download failed"
    end
    local chunk, compileErr = loadstring(src, "@anticheat_bypass")
    if not chunk then
        return false, "compile error: " .. tostring(compileErr)
    end

    warn = function() end
    print = function() end
    local ok, err = pcall(chunk)
    warn = realWarn
    print = realPrint

    if not ok then
        return false, "runtime error: " .. tostring(err)
    end
    return true, nil
end

for _, url in ipairs(PRE_FILES) do
    local ok, err = RunBypassSilently(url)
    if ok then
        print("[AirHub] anticheat bypassed")
    else
        warn("[AirHub] anticheat bypass failed: " .. tostring(err))
    end
    task.wait()
end

--// ---------------------------------------------------------------------------
--// Основные модули — лоадер отчитывается по каждому.
--// ---------------------------------------------------------------------------
local loaded, failed = 0, 0
for _, file in ipairs(FILES) do
    local url = REPO .. file
    local src = Fetch(url)
    if not src then
        warn("[AirHub] FAILED to download: " .. file)
        failed = failed + 1
        goto continue
    end
    local chunk, compileErr = loadstring(src, "@" .. file)
    if not chunk then
        warn("[AirHub] COMPILE ERROR in " .. file .. ": " .. tostring(compileErr))
        failed = failed + 1
        goto continue
    end
    local ok, err = pcall(chunk)
    if not ok then
        warn("[AirHub] RUNTIME ERROR in " .. file .. ": " .. tostring(err))
        failed = failed + 1
        goto continue
    end
    loaded = loaded + 1
    ::continue::
    task.wait()
end

if failed > 0 then
    warn("[AirHub] modules loaded: " .. loaded .. "/" .. #FILES .. " (failed: " .. failed .. ")")
else
    print("[AirHub] modules loaded: " .. loaded .. "/" .. #FILES)
end
