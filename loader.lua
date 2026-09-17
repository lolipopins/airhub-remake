--// AirHub Remake — hardened loader
--// - nil-safe warn/print (fixes "attempt to call a nil value")
--// - multi-method HTTP (HttpGet / game:HttpGet / request / syn.request / http_request)
--// - loadstring OR load fallback
--// - no goto/labels (works on Lua 5.1 and Luau)

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

--// ---------- capture originals, nil-safe ----------
local _print = (type(print) == "function") and print or function() end
local _warn  = (type(warn)  == "function") and warn  or _print

local function say(...)   _print(...) end
local function swarn(...) _warn(...)  end

--// ---------- HTTP ----------
local function httpGet(url)
    local methods = {
        function()
            if type(HttpGet) == "function" then return HttpGet(url) end
        end,
        function()
            if game and type(game.HttpGet) == "function" then
                return game:HttpGet(url)
            end
        end,
        function()
            if game and type(game.HttpGetAsync) == "function" then
                return game:HttpGetAsync(url)
            end
        end,
        function()
            if type(request) == "function" then
                local r = request({ Url = url, Method = "GET" })
                return r and r.Body
            end
        end,
        function()
            if type(http_request) == "function" then
                local r = http_request({ Url = url, Method = "GET" })
                return r and r.Body
            end
        end,
        function()
            if type(syn) == "table" and type(syn.request) == "function" then
                local r = syn.request({ Url = url, Method = "GET" })
                return r and r.Body
            end
        end,
    }
    for _, m in ipairs(methods) do
        local ok, res = pcall(m)
        if ok and type(res) == "string" and #res > 0 then
            return res
        end
    end
    return nil
end

local function Fetch(url) return httpGet(url) end

--// ---------- compile ----------
local function compile(src, name)
    if type(loadstring) == "function" then
        return loadstring(src, "@" .. name)
    elseif type(load) == "function" then
        return load(src, "@" .. name)
    end
    return nil, "loadstring/load unavailable in this executor"
end

--// ---------- silence globals during bypass ----------
local function withSilencedOutput(fn)
    local savedWarn, savedPrint
    pcall(function() savedWarn  = warn  end)
    pcall(function() savedPrint = print end)

    pcall(function() warn  = function() end end)
    pcall(function() print = function() end end)

    local ok, err = pcall(fn)

    pcall(function() warn  = savedWarn  end)
    pcall(function() print = savedPrint end)

    return ok, err
end

--// ---------- run bypass silently ----------
local function runBypassSilently(url)
    local src = Fetch(url)
    if not src then return false, "download failed" end

    local chunk, compileErr = compile(src, "anticheat_bypass")
    if not chunk then
        return false, "compile error: " .. tostring(compileErr)
    end

    local ok, err = withSilencedOutput(chunk)
    if not ok then
        return false, "runtime error: " .. tostring(err)
    end
    return true, nil
end

for _, url in ipairs(PRE_FILES) do
    local ok, err = runBypassSilently(url)
    if ok then
        say("[AirHub] anticheat bypassed")
    else
        swarn("[AirHub] anticheat bypass failed: " .. tostring(err))
    end
    if type(task) == "table" and type(task.wait) == "function" then
        task.wait()
    elseif type(wait) == "function" then
        wait()
    end
end

--// ---------- load modules ----------
local loaded, failed = 0, 0

for _, file in ipairs(FILES) do
    local url = REPO .. file
    local src = Fetch(url)

    if not src then
        swarn("[AirHub] FAILED to download: " .. file)
        failed = failed + 1
    else
        local chunk, compileErr = compile(src, file)
        if not chunk then
            swarn("[AirHub] COMPILE ERROR in " .. file .. ": " .. tostring(compileErr))
            failed = failed + 1
        else
            local ok, err = pcall(chunk)
            if not ok then
                swarn("[AirHub] RUNTIME ERROR in " .. file .. ": " .. tostring(err))
                failed = failed + 1
            else
                loaded = loaded + 1
            end
        end
    end

    if type(task) == "table" and type(task.wait) == "function" then
        task.wait()
    elseif type(wait) == "function" then
        wait()
    end
end

if failed > 0 then
    swarn("[AirHub] modules loaded: " .. loaded .. "/" .. #FILES ..
          " (failed: " .. failed .. ")")
else
    say("[AirHub] modules loaded: " .. loaded .. "/" .. #FILES)
end
