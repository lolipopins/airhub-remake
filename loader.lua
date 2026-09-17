--// ============================================================================
--// AirHub Remake — Loader (hardened, with Bypass Menu + Wait-for-Ready)
--// ============================================================================
--// Что нового:
--//   • Меню с чекбоксами обходов + кнопка "Inject AirHub"
--//   • Лоадер ЖДЁТ сигнал getgenv().ACBypassReady от античит-байпаса
--//   • После клика "Inject" меню скрывается, байпас запускается с выбранными
--//     опциями, затем AirHub грузится автоматически
--//   • Кнопка "Cancel" — выход без загрузки
--//   • Если байпас не подал сигнал за N секунд — грузим всё равно (с логом)
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
--// Конфиг
--// ---------------------------------------------------------------------------
local CONFIG = {
    MENU_TITLE          = "AirHub Loader",
    READY_SIGNAL        = "ACBypassReady",       -- getgenv()[READY_SIGNAL] = true
    CONFIG_SIGNAL       = "ACBypassConfig",      -- сюда кладём выбранные опции
    READY_TIMEOUT       = 30,                    -- сек, ожидание сигнала от байпаса
    AUTO_INJECT         = false,                 -- true = не ждать кнопки, сразу грузить
}

--// ---------------------------------------------------------------------------
--// Безопасные обёртки над print/warn
--// ---------------------------------------------------------------------------
local _print = (type(print) == "function") and print or function() end
local _warn  = (type(warn)  == "function") and warn  or _print

local function say(...)   _print(...) end
local function swarn(...) _warn(...)  end

--// ---------------------------------------------------------------------------
--// tick() — универсальный wait
--// ---------------------------------------------------------------------------
local function tick()
    if type(task) == "table" and type(task.wait) == "function" then
        task.wait()
    elseif type(wait) == "function" then
        wait()
    end
end

--// ---------------------------------------------------------------------------
--// getgenv() — универсальный доступ
--// ---------------------------------------------------------------------------
local function GENV()
    if type(getgenv) == "function" then
        local ok, env = pcall(getgenv)
        if ok and type(env) == "table" then return env end
    end
    return _G
end

--// ---------------------------------------------------------------------------
--// HTTP GET — 6 способов
--// ---------------------------------------------------------------------------
local function httpGet(url)
    local methods = {
        function() if type(HttpGet) == "function" then return HttpGet(url) end end,
        function() if game and type(game.HttpGet) == "function" then return game:HttpGet(url) end end,
        function() if game and type(game.HttpGetAsync) == "function" then return game:HttpGetAsync(url) end end,
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

--// ---------------------------------------------------------------------------
--// Компиляция
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
--// Выполнение с заглушёнными warn/print (для байпаса)
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
--// Список обходов для меню — пользователь выбирает, что включать
--// ---------------------------------------------------------------------------
local BYPASS_OPTIONS = {
    { id = "metamethod",     label = "Metamethod Bypass",       default = true  },
    { id = "handshake",      label = "Handshake Bypass",        default = true  },
    { id = "hookcheck",      label = "Hook Check Bypass",       default = true  },
    { id = "detour",         label = "Detour Bypass",           default = true  },
    { id = "memory",         label = "Memory Bypass",           default = true  },
    { id = "vm",             label = "VM Check Bypass",         default = true  },
    { id = "signature",      label = "Signature Bypass",        default = true  },
    { id = "integrity",      label = "Integrity Bypass",        default = true  },
    { id = "upvalue",        label = "Upvalue Bypass",          default = true  },
    { id = "namecall",       label = "Namecall Bypass",         default = true  },
    { id = "namecall_inst",  label = "NamecallInstance Bypass", default = true  },
    { id = "anti_detect",    label = "Anti-Detection Shield",   default = true  },
    { id = "adonis_check",   label = "Adonis ClientCheck",      default = true  },
    { id = "adonis_kick",    label = "Adonis Anti-Kick (0x4)",  default = true  },
    { id = "sandbox",        label = "Sandbox Bypass",          default = true  },
    { id = "debug",          label = "Debug Library Bypass",    default = true  },
    { id = "coroutine",      label = "Coroutine Bypass",        default = true  },
    { id = "thread_detect",  label = "Thread Detection Bypass", default = true  },
    { id = "rate_limit",     label = "Rate Limit Bypass",       default = true  },
    { id = "environment",    label = "Environment Bypass",      default = true  },
}

--// ---------------------------------------------------------------------------
--// Меню — создаём ScreenGui с чекбоксами и кнопками
--// ---------------------------------------------------------------------------
local MenuGui = nil
local MenuState = { selected = {}, done = false }

local function buildMenu(onInject, onCancel)
    local Players  = game:GetService("Players")
    local CoreGui  = game:GetService("CoreGui")
    local LP       = Players.LocalPlayer

    -- Инициализация состояния
    for _, opt in ipairs(BYPASS_OPTIONS) do
        MenuState.selected[opt.id] = opt.default
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "AirHubBypassMenu"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local parentOk = pcall(function() gui.Parent = CoreGui end)
    if not parentOk and LP then
        local pg = LP:FindFirstChildOfClass("PlayerGui")
        if pg then pcall(function() gui.Parent = pg end) end
    end

    -- Основной контейнер
    local frame = Instance.new("Frame", gui)
    frame.Name = "Main"
    frame.Size = UDim2.new(0, 460, 0, 560)
    frame.Position = UDim2.new(0.5, -230, 0.5, -280)
    frame.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
    frame.BorderSizePixel = 0
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

    local stroke = Instance.new("UIStroke", frame)
    stroke.Thickness = 1
    stroke.Color = Color3.fromRGB(60, 60, 70)

    -- Заголовок
    local title = Instance.new("TextLabel", frame)
    title.Size = UDim2.new(1, -24, 0, 40)
    title.Position = UDim2.new(0, 12, 0, 8)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 20
    title.TextColor3 = Color3.fromRGB(240, 240, 245)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = CONFIG.MENU_TITLE

    -- Подзаголовок
    local subtitle = Instance.new("TextLabel", frame)
    subtitle.Size = UDim2.new(1, -24, 0, 20)
    subtitle.Position = UDim2.new(0, 12, 0, 46)
    subtitle.BackgroundTransparency = 1
    subtitle.Font = Enum.Font.Gotham
    subtitle.TextSize = 12
    subtitle.TextColor3 = Color3.fromRGB(140, 140, 155)
    subtitle.TextXAlignment = Enum.TextXAlignment.Left
    subtitle.Text = "Выбери обходы и нажми «Inject AirHub»"

    -- Скроллящийся список обходов
    local scroll = Instance.new("ScrollingFrame", frame)
    scroll.Size = UDim2.new(1, -24, 1, -180)
    scroll.Position = UDim2.new(0, 12, 0, 76)
    scroll.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 6
    scroll.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 90)
    scroll.CanvasSize = UDim2.new(0, 0, 0, #BYPASS_OPTIONS * 32 + 8)
    Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 8)

    local listLayout = Instance.new("UIListLayout", scroll)
    listLayout.Padding = UDim.new(0, 4)
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local padding = Instance.new("UIPadding", scroll)
    padding.PaddingTop    = UDim.new(0, 6)
    padding.PaddingBottom = UDim.new(0, 6)
    padding.PaddingLeft   = UDim.new(0, 8)
    padding.PaddingRight  = UDim.new(0, 8)

    -- Чекбоксы
    local checkboxes = {}
    for i, opt in ipairs(BYPASS_OPTIONS) do
        local row = Instance.new("Frame", scroll)
        row.Name = opt.id
        row.Size = UDim2.new(1, 0, 0, 26)
        row.BackgroundTransparency = 1
        row.LayoutOrder = i

        local box = Instance.new("TextButton", row)
        box.Size = UDim2.new(0, 18, 0, 18)
        box.Position = UDim2.new(0, 0, 0.5, -9)
        box.BackgroundColor3 = opt.default and Color3.fromRGB(90, 140, 255) or Color3.fromRGB(40, 40, 48)
        box.BorderSizePixel = 0
        box.Text = ""
        box.AutoButtonColor = false
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4)

        local checkMark = Instance.new("TextLabel", box)
        checkMark.Size = UDim2.new(1, 0, 1, 0)
        checkMark.BackgroundTransparency = 1
        checkMark.Text = opt.default and "✓" or ""
        checkMark.TextColor3 = Color3.fromRGB(255, 255, 255)
        checkMark.Font = Enum.Font.GothamBold
        checkMark.TextSize = 14

        local label = Instance.new("TextLabel", row)
        label.Size = UDim2.new(1, -30, 1, 0)
        label.Position = UDim2.new(0, 28, 0, 0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.Gotham
        label.TextSize = 13
        label.TextColor3 = Color3.fromRGB(220, 220, 230)
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Text = opt.label

        checkboxes[opt.id] = { box = box, mark = checkMark, opt = opt }

        box.MouseButton1Click:Connect(function()
            local state = not MenuState.selected[opt.id]
            MenuState.selected[opt.id] = state
            box.BackgroundColor3 = state and Color3.fromRGB(90, 140, 255) or Color3.fromRGB(40, 40, 48)
            checkMark.Text = state and "✓" or ""
        end)
    end

    -- Кнопка "Все" / "Ничего"
    local btnAll = Instance.new("TextButton", frame)
    btnAll.Size = UDim2.new(0, 90, 0, 26)
    btnAll.Position = UDim2.new(0, 12, 1, -66)
    btnAll.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
    btnAll.BorderSizePixel = 0
    btnAll.Font = Enum.Font.GothamMedium
    btnAll.TextSize = 12
    btnAll.TextColor3 = Color3.fromRGB(200, 200, 210)
    btnAll.Text = "Выбрать всё"
    Instance.new("UICorner", btnAll).CornerRadius = UDim.new(0, 6)

    local btnNone = Instance.new("TextButton", frame)
    btnNone.Size = UDim2.new(0, 90, 0, 26)
    btnNone.Position = UDim2.new(0, 108, 1, -66)
    btnNone.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
    btnNone.BorderSizePixel = 0
    btnNone.Font = Enum.Font.GothamMedium
    btnNone.TextSize = 12
    btnNone.TextColor3 = Color3.fromRGB(200, 200, 210)
    btnNone.Text = "Снять всё"
    Instance.new("UICorner", btnNone).CornerRadius = UDim.new(0, 6)

    local function setAll(value)
        for id, cb in pairs(checkboxes) do
            MenuState.selected[id] = value
            cb.box.BackgroundColor3 = value and Color3.fromRGB(90, 140, 255) or Color3.fromRGB(40, 40, 48)
            cb.mark.Text = value and "✓" or ""
        end
    end
    btnAll.MouseButton1Click:Connect(function() setAll(true)  end)
    btnNone.MouseButton1Click:Connect(function() setAll(false) end)

    -- Кнопка "Inject AirHub"
    local btnInject = Instance.new("TextButton", frame)
    btnInject.Size = UDim2.new(0, 180, 0, 34)
    btnInject.Position = UDim2.new(1, -192, 1, -70)
    btnInject.BackgroundColor3 = Color3.fromRGB(90, 140, 255)
    btnInject.BorderSizePixel = 0
    btnInject.Font = Enum.Font.GothamBold
    btnInject.TextSize = 14
    btnInject.TextColor3 = Color3.fromRGB(255, 255, 255)
    btnInject.Text = "Inject AirHub"
    Instance.new("UICorner", btnInject).CornerRadius = UDim.new(0, 8)

    -- Кнопка "Cancel"
    local btnCancel = Instance.new("TextButton", frame)
    btnCancel.Size = UDim2.new(0, 40, 0, 34)
    btnCancel.Position = UDim2.new(1, -42, 1, -70)
    btnCancel.BackgroundColor3 = Color3.fromRGB(60, 40, 40)
    btnCancel.BorderSizePixel = 0
    btnCancel.Font = Enum.Font.GothamBold
    btnCancel.TextSize = 14
    btnCancel.TextColor3 = Color3.fromRGB(220, 140, 140)
    btnCancel.Text = "✕"
    Instance.new("UICorner", btnCancel).CornerRadius = UDim.new(0, 8)

    btnInject.MouseButton1Click:Connect(function()
        if MenuState.done then return end
        MenuState.done = true
        local cfg = {}
        for id, v in pairs(MenuState.selected) do cfg[id] = v end
        if onInject then onInject(cfg) end
    end)

    btnCancel.MouseButton1Click:Connect(function()
        if MenuState.done then return end
        MenuState.done = true
        if onCancel then onCancel() end
    end)

    MenuGui = gui
    return gui
end

local function destroyMenu()
    if MenuGui then
        pcall(function() MenuGui:Destroy() end)
        MenuGui = nil
    end
end

--// ---------------------------------------------------------------------------
--// Запуск античит-байпаса с выбранным конфигом.
--//   Кладём конфиг в getgenv().ACBypassConfig
--//   Сбрасываем getgenv().ACBypassReady = false
--//   После успешного прогона ставим getgenv().ACBypassReady = true
--//   (или ждём, что сам байпас поставит — если он так умеет)
--// ---------------------------------------------------------------------------
local function runBypassWithConfig(url, cfg)
    local genv = GENV()
    genv[CONFIG.CONFIG_SIGNAL] = cfg
    genv[CONFIG.READY_SIGNAL]  = false

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

    -- Если байпас сам не выставил READY — выставляем мы
    if genv[CONFIG.READY_SIGNAL] ~= true then
        genv[CONFIG.READY_SIGNAL] = true
    end

    return true, nil
end

--// ---------------------------------------------------------------------------
--// Ожидание сигнала READY с таймаутом
--// ---------------------------------------------------------------------------
local function waitForReady(timeout)
    local genv = GENV()
    local t0 = os.clock and os.clock() or 0
    local waited = 0

    while not genv[CONFIG.READY_SIGNAL] do
        tick()
        waited = waited + 0.05
        if waited >= timeout then
            return false
        end
    end

    return true
end

--// ---------------------------------------------------------------------------
--// Загрузка модулей AirHub
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

local function loadAllModules()
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

    if failed > 0 then
        swarn("[AirHub] modules loaded: " .. loaded .. "/" .. #FILES ..
              " (failed: " .. failed .. ")")
    else
        say("[AirHub] modules loaded: " .. loaded .. "/" .. #FILES)
    end

    return loaded, failed
end

--// ---------------------------------------------------------------------------
--// MAIN FLOW
--//   1) Показать меню
--//   2) Ждать клик "Inject"
--//   3) Запустить байпас с выбранным конфигом
--//   4) Дождаться READY-сигнала
--//   5) Загрузить AirHub
--//   6) Уничтожить меню (уже сделано в onInject)
--// ---------------------------------------------------------------------------
local function startFlow()
    local bypassUrl = PRE_FILES[1]

    buildMenu(function(cfg)
        -- Меню скрываем сразу после клика
        destroyMenu()

        say("[AirHub] bypass config: " ..
            (function()
                local parts = {}
                for k, v in pairs(cfg) do
                    if v then table.insert(parts, k) end
                end
                return table.concat(parts, ", ")
            end)())

        -- 1) Запуск байпаса
        local ok, err = runBypassWithConfig(bypassUrl, cfg)
        if ok then
            say("[AirHub] anticheat bypassed")
        else
            swarn("[AirHub] anticheat bypass failed: " .. tostring(err))
            -- продолжаем — вдруг и без байпаса прокатит
        end

        -- 2) Ждём сигнал READY
        say("[AirHub] waiting for bypass ready signal...")
        local ready = waitForReady(CONFIG.READY_TIMEOUT)
        if not ready then
            swarn("[AirHub] ready signal timeout — injecting anyway")
        else
            say("[AirHub] bypass ready → injecting modules")
        end

        -- 3) Грузим AirHub
        loadAllModules()
    end, function()
        -- Cancel
        destroyMenu()
        say("[AirHub] injection cancelled by user")
    end)
end

--// ---------------------------------------------------------------------------
--// AUTO_INJECT — если включён, сразу грузим без меню (для отладки)
--// ---------------------------------------------------------------------------
if CONFIG.AUTO_INJECT then
    local cfg = {}
    for _, opt in ipairs(BYPASS_OPTIONS) do cfg[opt.id] = opt.default end

    local bypassUrl = PRE_FILES[1]
    local ok, err = runBypassWithConfig(bypassUrl, cfg)
    if ok then say("[AirHub] anticheat bypassed (auto)")
    else swarn("[AirHub] bypass failed: " .. tostring(err)) end

    waitForReady(CONFIG.READY_TIMEOUT)
    loadAllModules()
else
    startFlow()
end
