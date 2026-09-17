--// ============================================================================
--// AirHub Remake — Loader (hardened, full)
--// ============================================================================
--// Исправлено:
--//   • убран goto/::continue::  → причина ошибки "attempt to call a nil value"
--//   • warn/print nil-safe      → не падает, если executor их не даёт
--//   • 6 способов HTTP          → HttpGet / game:HttpGet / HttpGetAsync /
--//                                request / http_request / syn.request
--//   • loadstring + load        → fallback на случай отсутствия loadstring
--//   • весь код без меток       → работает и на Lua 5.1, и на Luau
--// ============================================================================

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

--// ---------------------------------------------------------------------------
--// Безопасные обёртки над print/warn — если их нет, используем заглушку.
--// ---------------------------------------------------------------------------
local _print = (type(print) == "function") and print or function() end
local _warn  = (type(warn)  == "function") and warn  or _print

local function say(...)   _print(...) end
local function swarn(...) _warn(...)  end

--// ---------------------------------------------------------------------------
--// Универсальный task.wait/wait — что есть в executor'е, то и вызываем.
--// ---------------------------------------------------------------------------
local function tick()
    if type(task) == "table" and type(task.wait) == "function" then
        task.wait()
    elseif type(wait) == "function" then
        wait()
    end
end

--// ---------------------------------------------------------------------------
--// HTTP GET — перебираем все известные методы, пока какой-нибудь не сработает.
--// ---------------------------------------------------------------------------
local function httpGet(url)
    local methods = {
        function()
            if type(HttpGet) == "function" then
                return HttpGet(url)
            end
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

local function Fetch(url)
    return httpGet(url)
end

--// ---------------------------------------------------------------------------
--// Компиляция: loadstring, при его отсутствии — load.
--// ---------------------------------------------------------------------------
local function compile(src, name)
    if type(loadstring) == "function" then
        return loadstring(src, "@" .. name)
    elseif type(load) == "function" then
        return load(src, "@" .. name)
    end
    return nil, "loadstring/load unavailable in this executor"
end

--// ---------------------------------------------------------------------------
--// Выполнение с заглушёнными warn/print — для античит-байпаса.
--// Восстановление глобалов защищено pcall, чтобы не уронить скрипт.
--// ---------------------------------------------------------------------------
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

--// ---------------------------------------------------------------------------
--// Загрузка и выполнение античит-байпаса (тихо).
--// ---------------------------------------------------------------------------
local function runBypassSilently(url)
    local src = Fetch(url)
    if not src then
        return false, "download failed"
    end

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
    tick()
end

--// ---------------------------------------------------------------------------
--// Загрузка основных модулей. Никаких goto и меток — только функции и if/else.
--// ---------------------------------------------------------------------------
local function loadModule(file)
    local url = REPO .. file

    local src = Fetch(url)
    if not src then
        return false, "download failed"
    end

    local chunk, compileErr = compile(src, file)
    if not chunk then
        return false, "compile error: " .. tostring(compileErr)
    end

    local ok, err = pcall(chunk)
    if not ok then
        return false, "runtime error: " .. tostring(err)
    end

    return true, nil
end

local loaded, failed = 0, 0

for _, file in ipairs(FILES) do
    local ok, err = loadModule(file)

    if ok then
        loaded = loaded + 1
    else
        swarn("[AirHub] " .. file .. ": " .. tostring(err))
        failed = failed + 1
    end

    tick()
end

--// ---------------------------------------------------------------------------
--// Итоговый отчёт.
--// ---------------------------------------------------------------------------
if failed > 0 then
    swarn("[AirHub] modules loaded: " .. loaded .. "/" .. #FILES ..
          " (failed: " .. failed .. ")")
else
    say("[AirHub] modules loaded: " .. loaded .. "/" .. #FILES)
end
