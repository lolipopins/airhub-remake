--// AirHub Loader — MERGED EDITION (Remake + Specific Game)
--// ============================================================================
--// Объединяет AirHub Remake (13 модулей) и Specific Game (Auto Mog и т.д.)
--// Использует Fast Loader v3 логику для модулей (параллельный fetch)
--// ============================================================================

local AIRHUB_VERSIONS = {
    merged = {
        id          = "merged",
        label       = "AirHub Remake",
        description = "AirHub Remake + Specific Game (Auto Mog и т.д.)",
        isNew       = false,
        type        = "combined",
        modulesVersion = "full",
        singleVersion  = "specific_game",
    },
    full = {
        id          = "full",
        label       = "AirHub Remake (Standalone)",
        description = "Модульная сборка airhub-remake (13 модулей)",
        type        = "modules",
        repo        = "https://raw.githubusercontent.com/lolipopins/airhub-remake/main/src/",
        files       = {
            "01_core.lua", "02_aimbot.lua", "03_antiaim.lua", "04_wallhack.lua",
            "05_serverposition.lua", "06a_movement_fly_bhop.lua", "06b_movement_speed_strafer.lua",
            "07a_ui_core.lua", "07b_ui_tabs.lua", "08_world.lua", "09_exploits.lua", "10_hud.lua", "arsenal extra tab",
        },
    },
    reloaded = {
        id          = "reloaded",
        label       = "AirHub Reloaded",
        description = "Новая модульная сборка (00_ui_lib → 08_settings)",
        isNew       = true,
        type        = "modules",
        repo        = "https://raw.githubusercontent.com/lolipopins/Airhub-reloaded/main/src/",
        files       = {
            "00_ui_lib.lua", "01_core.lua", "02_aimbot.lua", "03_antiaim.lua", "04_wallhack.lua",
            "05_movement.lua", "06_world.lua", "07_exploits.lua", "08_settings.lua",
            "arsenal_extra_tab.lua", "rivals_extra_tab.lua",
        },
    },
    lite = {
        id          = "lite",
        label       = "Lite",
        description = "Один файл, GUI bypass, без конфига",
        type        = "single",
        url         = "https://raw.githubusercontent.com/lolipopins/airhub-remake/refs/heads/main/airhub%20lite",
        localPath   = "airhub lite.lua",
    },
    legacy = {
        id          = "legacy",
        label       = "Legacy",
        description = "Один файл, архивный (без обновлений)",
        type        = "single",
        url         = "https://raw.githubusercontent.com/lolipopins/airhub-remake/refs/heads/main/airhub%20legacy",
        localPath   = "airhub legacy.lua",
    },
    original_v2 = {
        id          = "original_v2",
        label       = "Original V2",
        description = "Официальный Exunys V2 (Aimbot + ESP + Crosshair)",
        type        = "single",
        url         = "https://raw.githubusercontent.com/Exunys/AirHub-V2/main/src/Main.lua",
        localPath   = "original_v2.lua",
    },
    original = {
        id          = "original",
        label       = "Original",
        description = "Официальный Exunys V1 (Aimbot + WallHack)",
        type        = "single",
        url         = "https://raw.githubusercontent.com/Exunys/AirHub/main/AirHub.lua",
        localPath   = "original.lua",
    },
    specific_game = {
        id          = "specific_game",
        label       = "Specific Game",
        description = "Кастомное меню: Auto Mog / Auto Clicker / Noclip / Speed",
        type        = "single",
        url         = "https://raw.githubusercontent.com/lolipopins/airhub-remake/refs/heads/main/specific%20games/%2B1%20mog%20evolution",
        localPath   = "+1 mog script.lua",
    },
}

-- Reloaded теперь первый, Specific Game убран (он есть внутри merged)
local AIRHUB_VERSION_ORDER = {
    "reloaded", "merged", "lite", "legacy",
    "original_v2", "original",
}

local LOCAL_DIRS_MODULES = { "AirHub/src/", "airhub/src/", "src/", "" }
local LOCAL_DIRS_SINGLE  = { "AirHub/", "airhub/", "", "." }

local CONFIG = {
    MENU_TITLE        = "AirHub Loader",
    KICK_LOG_PREFIX   = "[AirHub][KICK]",
    BLOCK_KICK        = true,
    SPECIFIC_PLACE_ID = 92648272637932,
    ARSENAL_PLACE_ID  = 286090429,
    ARSENAL_FILE      = "arsenal extra tab",
    ARSENAL_FILE2     = "arsenal_extra_tab",
    RIVALS_PLACE_ID   = 17625359962,
    RIVALS_FILE       = "rivals_extra_tab",
    FETCH_TIMEOUT     = 20,
}

--// ============================================================================
--// BYPASS CATEGORIES + RISKY SET
--// ============================================================================
local BYPASS_CATEGORIES = {
    adonis           = "Anti-Cheat",
    integrity        = "Anti-Cheat",
    anti_detect      = "Detection",
    environment      = "Detection",
    hookcheck        = "Detection",
    signature        = "Detection",
    thread_detect    = "Detection",
    vm               = "Detection",
    memory           = "Memory",
    upvalue          = "Memory",
    handshake        = "Network",
    rate_limit       = "Network",
    replace_humanoid = "Character",
    kick_logger      = "Utility",
    coroutine        = "Runtime",
    debug            = "Runtime",
    detour           = "Runtime",
    metamethod       = "Runtime",
    namecall         = "Runtime",
    namecall_inst    = "Runtime",
    sandbox          = "Runtime",
}
local RISKY_BYPASSES = {
    memory           = true,
    upvalue          = true,
    adonis           = true,
    replace_humanoid = true,
}
local CATEGORY_ORDER = {
    "All", "Anti-Cheat", "Detection", "Runtime", "Memory",
    "Network", "Character", "Utility",
}

--// ============================================================================
--// HELPERS
--// ============================================================================
local _print = (type(print) == "function") and print or function() end
local _warn  = (type(warn)  == "function") and warn  or _print
local function say(...)   _print(...) end
local function swarn(...) _warn(...)  end

--// Fast Loader Fallbacks
local TASK = rawget(_G, "task")
if type(TASK) ~= "table" and type(getgenv) == "function" then
    local ok, env = pcall(getgenv)
    if ok and type(env) == "table" then TASK = rawget(env, "task") end
end

local spawnFn = (TASK and type(TASK.spawn) == "function" and TASK.spawn)
             or (type(rawget(_G, "spawn")) == "function" and rawget(_G, "spawn"))
             or function(f) f() end

local waitFn = (TASK and type(TASK.wait) == "function" and TASK.wait)
            or (type(rawget(_G, "wait")) == "function" and rawget(_G, "wait"))
            or function() end

local clockFn = (os and os.clock) or tick or function() return 0 end

local function tick()
    waitFn()
end

local function GENV()
    if type(getgenv) == "function" then
        local ok, env = pcall(getgenv)
        if ok and type(env) == "table" then return env end
    end
    return _G
end

local function getExec(name)
    local f = rawget(_G, name)
    if type(f) == "function" then return f end
    local env = GENV()
    if env and env ~= _G then
        f = rawget(env, name)
        if type(f) == "function" then return f end
    end
    return nil
end

local function hasExec(name) return getExec(name) ~= nil end

local function safe(fn, ...)
    local r = table.pack(pcall(fn, ...))
    if not r[1] then return false, r[2] end
    return true, table.unpack(r, 2, r.n)
end

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
        if ok and type(res) == "string" and #res > 0 then return res end
    end
    return nil
end

local function sanitizeSource(src)
    if type(src) ~= "string" or #src == 0 then return nil, "empty source" end
    local trimmed = src:gsub("^%s+", "")
    local head = trimmed:sub(1, 200)
    local lowerHead = head:lower()
    if lowerHead:find("^404: not found", 1, true)
       or lowerHead:find("^404 not found", 1, true)
       or lowerHead:find("^<!doctype html", 1, true)
       or lowerHead:find("^<html", 1, true)
       or lowerHead:find("this repository is empty", 1, true)
       or lowerHead:find("page not found", 1, true)
       or lowerHead:find("\"message\":\"not found\"", 1, true)
    then
        return nil, "HTTP 404 / not found"
    end
    local looksLikeLua = lowerHead:find("local ", 1, true)
        or lowerHead:find("--", 1, true)
        or lowerHead:find("return", 1, true)
        or lowerHead:find("if ", 1, true)
        or lowerHead:find("getgenv", 1, true)
        or lowerHead:find("warn(", 1, true)
    if not looksLikeLua then return nil, "response does not look like Lua source" end
    return src
end

local function tryReadLocal(filename, dirs)
    if type(readfile) ~= "function" then return nil, nil end
    if type(filename) ~= "string" or filename == "" then return nil, nil end
    for _, dir in ipairs(dirs) do
        local path = dir .. filename
        local ok, content = pcall(readfile, path)
        if ok and type(content) == "string" and #content > 0 then
            return content, path
        end
    end
    return nil, nil
end

local function compile(src, name)
    if type(loadstring) == "function" then return loadstring(src, "@" .. name) end
    if type(load) == "function" then return load(src, "@" .. name) end
    return nil, "loadstring/load unavailable"
end

local function fetchOneFile(baseUrl, filename)
    local localSrc, localPath = tryReadLocal(filename, LOCAL_DIRS_MODULES)
    if localSrc then return localSrc, "LOCAL:" .. localPath end

    local url = baseUrl .. filename:gsub(" ", "%%20")
    local remote = httpGet(url)
    if not remote then return nil, "no source (local + HTTP failed)" end

    local clean, err = sanitizeSource(remote)
    if not clean then return nil, "bad source: " .. tostring(err) end
    return clean, "HTTP"
end

--// ============================================================================
--// SERVICES
--// ============================================================================
local Players           = game:GetService("Players")
local CoreGui           = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptContext     = game:GetService("ScriptContext")
local MarketplaceService= game:GetService("MarketplaceService")
local LP                = Players.LocalPlayer

--// ============================================================================
--// NAMECALL MANAGER
--// ============================================================================
local NM = { hooked = false, filters = {}, wrapper = nil, original = nil }

local function NM_Ensure()
    if NM.hooked then return true end
    local hook      = getExec("hookmetamethod")
    local getMethod = getExec("getnamecallmethod")
    if not hook or not getMethod then return false end
    local getmt = getExec("getrawmetatable")
    if getmt then
        safe(function()
            local mt = getmt(game)
            if type(mt) == "table" then NM.original = rawget(mt, "__namecall") end
        end)
    end
    local ok = pcall(function()
        local old
        local wrapper = function(self, ...)
            local method = getMethod()
            if type(method) == "string" then
                local handlers = NM.filters[method]
                if handlers then
                    for _, h in ipairs(handlers) do
                        local hOk, res = pcall(h, self, ...)
                        if hOk and res == "block" then return end
                        if hOk and res == "spoof_kick" then return nil end
                    end
                end
            end
            return old(self, ...)
        end
        local newc = getExec("newcclosure")
        if newc then pcall(function() wrapper = newc(wrapper) end) end
        NM.wrapper = wrapper
        old = hook(game, "__namecall", wrapper)
    end)
    if ok then NM.hooked = true end
    return NM.hooked
end

local function NM_Register(method, handler)
    if not NM.filters[method] then NM.filters[method] = {} end
    table.insert(NM.filters[method], handler)
end

--// ============================================================================
--// KICK LOGGER
--// ============================================================================
local KickLogger = {
    events = {}, max_events = 100, 
    installed_sources = {
        namecall = false, removing = false, moderator = false, ui = false,
    },
    last_reason = nil, last_vector = nil, repeat_count = 0, change_count = 0,
}

local function fmtTime()
    return (type(os) == "table" and type(os.date) == "function")
        and os.date("%H:%M:%S") or "??:??:??"
end

local function normalizeReason(r)
    local s = tostring(r or "unknown")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then s = "unknown" end
    return s
end

local function resetKickTracking()
    KickLogger.last_reason = nil; KickLogger.last_vector = nil
    KickLogger.repeat_count = 0; KickLogger.change_count = 0
end

local function logKick(reason, vector, target, caller)
    reason = normalizeReason(reason)
    vector = tostring(vector or "unknown")
    target = tostring(target or "unknown")
    caller = tostring(caller or "n/a")
    local prev      = KickLogger.last_reason
    local is_first  = (prev == nil)
    local is_repeat = (prev ~= nil and prev == reason)
    local is_change = (prev ~= nil and prev ~= reason)
    if is_repeat then KickLogger.repeat_count += 1 else KickLogger.repeat_count = 1 end
    if is_change then KickLogger.change_count += 1 end
    KickLogger.last_reason = reason
    KickLogger.last_vector = vector
    table.insert(KickLogger.events, {
        time = fmtTime(), reason = reason, vector = vector,
        target = target, caller = caller,
        kind = is_first and "first" or is_change and "changed" or "repeat",
        prev_reason = prev,
        repeat_count = KickLogger.repeat_count, change_count = KickLogger.change_count,
    })
    while #KickLogger.events > KickLogger.max_events do table.remove(KickLogger.events, 1) end
    local P = CONFIG.KICK_LOG_PREFIX
    swarn(P .. " =========================================")
    if is_first then
        swarn(P .. "  [!]  KICK DETECTED (first)")
        swarn(P .. "  Reason : " .. reason)
    elseif is_change then
        swarn(P .. "  [!!] KICK REASON CHANGED  (#" .. KickLogger.change_count .. ")")
        swarn(P .. "  Prev   : " .. tostring(prev))
        swarn(P .. "  New    : " .. reason)
    else
        swarn(P .. "  [!]  KICK REPEATED  (x" .. KickLogger.repeat_count .. ")")
        swarn(P .. "  Reason : " .. reason)
    end
    swarn(P .. "  Vector : " .. vector)
    swarn(P .. "  Target : " .. target)
    swarn(P .. "  Caller : " .. caller)
    swarn(P .. "  Time   : " .. fmtTime())
    swarn(P .. " =========================================")
end

local function callerDebug()
    local ok, info = pcall(function()
        if type(debug) == "table" and type(debug.info) == "function" then
            local _, name = debug.info(3, "sn"); return name or "?"
        elseif type(debug) == "table" and type(debug.getinfo) == "function" then
            local d = debug.getinfo(3, "Sn"); return (d and (d.short_src or d.source)) or "?"
        end
        return "?"
    end)
    return ok and info or "?"
end

local function installKickNamecallHook()
    if KickLogger.installed_sources.namecall then return true end
    if not NM_Ensure() then return false, "hookmetamethod unavailable" end
    NM_Register("Kick", function(self, ...)
        local reason = ...
        local target = (typeof(self) == "Instance")
            and (self == LP and "LocalPlayer" or (self:IsA("Player") and self.Name) or tostring(self))
            or "unknown"
        logKick(reason, "Player:Kick", target, callerDebug())
        if CONFIG.BLOCK_KICK then return "spoof_kick" end
        return nil
    end)
    NM_Register("Disconnect", function(self)
        if typeof(self) == "Instance" and self == LP then
            logKick("client disconnect", "Player:Disconnect", "LocalPlayer", callerDebug())
            if CONFIG.BLOCK_KICK then return "spoof_kick" end
        end
        return nil
    end)
    KickLogger.installed_sources.namecall = true
    return true
end

local function installPlayerRemovingHook()
    if KickLogger.installed_sources.removing then return true end
    safe(function()
        Players.PlayerRemoving:Connect(function(plr)
            if plr == LP then
                logKick("removed from game (server-side or client disconnect)",
                        "PlayerRemoving", "LocalPlayer", callerDebug())
            end
            return nil
        end)
        KickLogger.installed_sources.removing = true
    end)
    return KickLogger.installed_sources.removing
end

local function installModeratorHook()
    if KickLogger.installed_sources.moderator then return true end
    safe(function()
        for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
            if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
                local n = obj.Name:lower()
                if n:find("moderator") or n:find("mod message") or n:find("modkick")
                   or n:find("kick") or n:find("ban") then
                    pcall(function()
                        obj.OnClientEvent:Connect(function(...)
                            local args = { ... }
                            local reason = "moderator/kick message"
                            for _, a in ipairs(args) do
                                if type(a) == "string" and #a > 0 then reason = a; break end
                            end
                            logKick(reason, "Remote.OnClientEvent", obj.Name, obj:GetFullName())
                            return nil
                        end)
                    end)
                end
            end
        end
        KickLogger.installed_sources.moderator = true
    end)
    return KickLogger.installed_sources.moderator
end

local function installUIWatcher()
    if KickLogger.installed_sources.ui then return true end
    safe(function()
        local pg = LP:FindFirstChildOfClass("PlayerGui")
        if not pg then return end
        local watched_labels = {}
        local function watchLabel(label, guiRef)
            if watched_labels[label] then return end
            watched_labels[label] = true
            label:GetPropertyChangedSignal("Text"):Connect(function()
                local txt = label.Text
                if txt and txt ~= "" and not txt:match("^%s*$") then
                    logKick(txt, "GUI.TextChanged",
                            guiRef and guiRef.Name or "ModeratorUI",
                            label:GetFullName())
                end
                return nil
            end)
        end
        local function checkGui(gui)
            local name = tostring(gui.Name):lower()
            if name:find("moderator") or name:find("anti kick")
               or name:find("antikick") or name:find("kick") then
                waitFn(0.05)
                local initial_reason = nil
                for _, d in ipairs(gui:GetDescendants()) do
                    if d:IsA("TextLabel") and #d.Text > 0 and not d.Text:match("^%s*$") then
                        if not initial_reason then initial_reason = d.Text end
                        watchLabel(d, gui)
                    end
                end
                if initial_reason then
                    logKick(initial_reason, "Moderator GUI", gui.Name, gui:GetFullName())
                end
                if CONFIG.BLOCK_KICK then pcall(function() gui:Destroy() end) end
            end
        end
        for _, child in ipairs(pg:GetChildren()) do checkGui(child) end
        pg.ChildAdded:Connect(function(child) waitFn(0.05); checkGui(child) return nil end)
        KickLogger.installed_sources.ui = true
    end)
    return KickLogger.installed_sources.ui
end

local function installAllKickHooks()
    local nc_ok, nc_err = installKickNamecallHook()
    if nc_ok then say(CONFIG.KICK_LOG_PREFIX .. " namecall hook installed")
    else swarn(CONFIG.KICK_LOG_PREFIX .. " namecall hook failed: " .. tostring(nc_err)) end
    installPlayerRemovingHook()
    installModeratorHook()
    installUIWatcher()
    return nc_ok
end

--// ============================================================================
--// BYPASS STEPS
--// ============================================================================
local Steps = {}
local _replaced = setmetatable({}, { __mode = "k" })

local function _fixCameraIfBroken(newHumanoid, oldHumanoid)
    local cam = workspace.CurrentCamera
    if not cam or not newHumanoid or not newHumanoid.Parent then return end
    local subj = cam.CameraSubject
    local broken = (subj == nil) or (subj == oldHumanoid)
                or (typeof(subj) == "Instance" and subj.Parent == nil)
    if broken then
        pcall(function()
            cam.CameraType = Enum.CameraType.Custom
            cam.CameraSubject = newHumanoid
        end)
    end
end

local function replaceHumanoid(character)
    if not character or typeof(character) ~= "Instance" then return nil end
    if _replaced[character] then return nil end
    local oldHumanoid = character:WaitForChild("Humanoid", 10)
    if not oldHumanoid then return nil end
    if not character.PrimaryPart then character:WaitForChild("HumanoidRootPart", 5) end
    tick()
    _replaced[character] = true
    local okRun = pcall(function()
        local animate = character:FindFirstChild("Animate")
        local oldAnimator = oldHumanoid:FindFirstChildOfClass("Animator")
        if oldAnimator then
            pcall(function()
                for _, track in ipairs(oldAnimator:GetPlayingAnimationTracks()) do
                    track:Stop(0)
                end
            end)
        end
        local stats = {
            WalkSpeed = oldHumanoid.WalkSpeed, JumpPower = oldHumanoid.JumpPower,
            JumpHeight = oldHumanoid.JumpHeight, MaxHealth = oldHumanoid.MaxHealth,
            Health = oldHumanoid.Health,
        }
        oldHumanoid.Archivable = true
        local okClone, newHumanoid = pcall(function() return oldHumanoid:Clone() end)
        if not okClone or not newHumanoid then error("clone failed") end
        if animate then pcall(function() animate.Disabled = true end) end
        pcall(function() oldHumanoid.Name = "_OldHumanoid"; oldHumanoid.Parent = nil end)
        newHumanoid.Name = "Humanoid"; newHumanoid.Parent = character
        local newAnimator = Instance.new("Animator"); newAnimator.Parent = newHumanoid
        newHumanoid.WalkSpeed = stats.WalkSpeed
        newHumanoid.JumpPower = stats.JumpPower
        newHumanoid.JumpHeight = stats.JumpHeight
        newHumanoid.MaxHealth = stats.MaxHealth
        newHumanoid.Health = math.clamp(stats.Health, 0, stats.MaxHealth)
        if animate then task.defer(function() pcall(function() animate.Disabled = false end) end) end
        _fixCameraIfBroken(newHumanoid, oldHumanoid)
        for _, d in ipairs({ 0.05, 0.15, 0.30, 0.50 }) do
            task.delay(d, function() _fixCameraIfBroken(newHumanoid, oldHumanoid) end)
        end
        task.delay(0.4, function() pcall(function() oldHumanoid:Destroy() end) end)
    end)
    if not okRun then _replaced[character] = nil; return nil end
    return character:FindFirstChild("Humanoid")
end

local _humanoid_hook_conn = nil
local function installHumanoidReplaceHook()
    if _humanoid_hook_conn then return true end
    if not LP then return false, "no LocalPlayer" end
    _humanoid_hook_conn = LP.CharacterAdded:Connect(function(character)
        task.spawn(function() pcall(replaceHumanoid, character) end)
        return nil
    end)
    return true
end

Steps.replace_humanoid = function()
    local character = LP and LP.Character
    if not character then return "no character (hook applies on spawn)" end
    installHumanoidReplaceHook()
    local newH = replaceHumanoid(character)
    if newH then return "replaced, camera guarded, animate restarted" end
    return "replace failed (already done or humanoid missing)"
end

Steps.metamethod = function()
    local checks = { "checkcaller","getcallingscript","getfenv","setfenv","getreg","getgc","getconnections","hookfunction","newcclosure" }
    local found = 0
    for _, c in ipairs(checks) do if hasExec(c) then found += 1 end end
    if hasExec("setreadonly") and hasExec("getrenv") then
        safe(function()
            local renv = getExec("getrenv")()
            if type(renv) == "table" then getExec("setreadonly")(renv, false) end
        end)
    end
    return found .. " executor fns"
end

Steps.handshake = function()
    local set = {}
    safe(function()
        for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
            if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
                local n = obj.Name:lower()
                if n:find("handshake") or n:find("validate") or n:find("verify") then set[obj] = true end
            end
        end
    end)
    local count = 0; for _ in pairs(set) do count += 1 end
    if count > 0 and NM_Ensure() then
        local filter = function(self) if set[self] then return "block" end return nil end
        NM_Register("FireServer", filter)
        NM_Register("InvokeServer", filter)
    end
    return count .. " remotes tracked"
end

Steps.hookcheck = function()
    local count = 0
    if hasExec("getreg") then
        safe(function()
            for _, v in pairs(getExec("getreg")()) do
                if type(v) == "function" then count += 1 end
            end
        end)
    end
    return count .. " functions scanned"
end

Steps.detour = function()
    local count = 0
    local env = GENV()
    for _, name in ipairs({ "getfenv","setfenv","getreg","getgc","checkcaller" }) do
        if type(rawget(env, name)) == "function" then count += 1 end
    end
    return count .. " globals"
end

Steps.memory = function()
    local patches = 0
    if hasExec("setreadonly") then
        local setro = getExec("setreadonly")
        for _, name in ipairs({ "getrenv","getreg","getgc" }) do
            if hasExec(name) then
                safe(function()
                    local t = getExec(name)()
                    if type(t) == "table" then setro(t, false); patches += 1 end
                end)
            end
        end
    end
    if hasExec("getgc") then
        safe(function()
            local i = 0
            for _, obj in pairs(getExec("getgc")()) do
                i += 1; if i > 3000 then break end
                if type(obj) == "table" and rawget(obj, "__acsignature") ~= nil then
                    pcall(function() rawset(obj, "__acsignature", nil) end); patches += 1
                end
            end
        end)
    end
    return patches .. " patches"
end

Steps.vm = function()
    local found = 0
    if hasExec("getcallingscript") then found += 1 end
    if hasExec("getfenv") then found += 1 end
    if type(debug) == "table" then found += 1 end
    return found .. " VM vectors"
end

Steps.signature = function()
    local cleared = 0
    local env = GENV()
    for _, name in ipairs({ "_G","shared" }) do
        local t = rawget(env, name)
        if type(t) == "table" then
            local toDelete = {}
            for k in pairs(t) do
                local ks = tostring(k):lower()
                if ks:find("signature") or ks:find("checksum") or ks:find("hash") then
                    table.insert(toDelete, k)
                end
            end
            for _, k in ipairs(toDelete) do
                pcall(function() t[k] = nil end); cleared += 1
            end
        end
    end
    return cleared .. " signatures"
end

Steps.integrity = function()
    local n = 0
    safe(function()
        local toDestroy = {}
        for _, m in ipairs(ReplicatedStorage:GetDescendants()) do
            if m:IsA("ModuleScript") then
                local name = m.Name:lower()
                if name:find("integrity") or name:find("security") or name:find("anti") then
                    table.insert(toDestroy, m)
                end
            end
        end
        for _, m in ipairs(toDestroy) do
            if pcall(function() m:Destroy() end) then n += 1 end
        end
    end)
    return n .. " modules removed"
end

Steps.upvalue = function()
    local cleaned = 0
    local guv, suv, ggc = getExec("getupvalues"), getExec("setupvalue"), getExec("getgc")
    if guv and suv and ggc then
        safe(function()
            local i = 0
            for _, obj in pairs(ggc()) do
                i += 1; if i > 2000 then break end
                if type(obj) == "function" then
                    local ok, ups = pcall(guv, obj)
                    if ok and type(ups) == "table" then
                        for idx, v in pairs(ups) do
                            if type(v) == "string" and #v > 64 then
                                if v:find("AC") or v:find("anticheat")
                                   or v:find("Signature") or v:find("checksum") then
                                    pcall(suv, obj, idx, ""); cleaned += 1
                                end
                            end
                        end
                    end
                end
            end
        end)
    end
    return cleaned .. " upvalues"
end

Steps.namecall = function()
    local ok = NM_Ensure()
    return ok and "hook installed" or "hookmetamethod unavailable"
end

Steps.namecall_inst = function()
    if not NM_Ensure() then return "hookmetamethod unavailable" end
    local getmt   = getExec("getrawmetatable")
    local checkC  = getExec("checkcaller")
    NM_Register("GetDebugId", function(self) if typeof(self) == "Instance" then return "block" end return nil end)
    for _, m in ipairs({ "GetFullName", "IsDescendantOf", "GetPropertyChangedSignal" }) do
        NM_Register(m, function(self)
            if typeof(self) == "Instance" and self == LP and checkC and not checkC() then return "block" end
            return nil
        end)
    end
    local mtVerified = false
    if getmt then
        safe(function()
            local mt = getmt(game)
            if type(mt) == "table" then mtVerified = type(rawget(mt, "__namecall")) == "function" end
        end)
    end
    return string.format("mt %s, 3 methods guarded (LocalPlayer scope)",
        mtVerified and "verified" or "unverified")
end

Steps.anti_detect = function()
    if not NM.hooked then return "hook not installed - skip" end
    local shields = 0
    local checkC = getExec("checkcaller")
    local getmt  = getExec("getrawmetatable")
    local ggc    = getExec("getgc")
    local guv    = getExec("getupvalues")
    local suv    = getExec("setupvalue")
    local hookf  = getExec("hookfunction")
    local newc   = getExec("newcclosure")
    if hookf and getmt and checkC and NM.original then
        safe(function()
            local orig = getmt
            local fake = function(obj)
                local mt = orig(obj)
                if not checkC() and obj == game and type(mt) == "table" then
                    local c = {}; for k, v in pairs(mt) do c[k] = v end
                    c.__namecall = NM.original
                    return c
                end
                return mt
            end
            if newc then pcall(function() fake = newc(fake) end) end
            pcall(function() hookf(getmt, fake) end)
            shields += 1
        end)
    end
    if guv and suv and NM.wrapper then
        safe(function()
            local ups = guv(NM.wrapper)
            if type(ups) == "table" then
                for i = 1, #ups do
                    if type(ups[i]) == "string" and #ups[i] > 0 then
                        pcall(suv, NM.wrapper, i, "")
                    end
                end
            end
            shields += 1
        end)
    end
    if ggc then
        safe(function()
            local i = 0
            for _, obj in pairs(ggc()) do
                i += 1; if i > 5000 then break end
                if type(obj) == "table" then
                    for _, m in ipairs({ "__nm_wrapper", "__loader_ref" }) do
                        if rawget(obj, m) ~= nil then
                            pcall(function() rawset(obj, m, nil) end); shields += 1
                        end
                    end
                end
            end
        end)
    end
    return shields .. " shields"
end

Steps.sandbox = function()
    local restored = 0
    for _, name in ipairs({
        "getrawmetatable","setrawmetatable","getnamecallmethod",
        "hookmetamethod","firetouchinterest","fireclickdetector",
        "getnilinstances","getloadedmodules","getscripts",
    }) do
        if hasExec(name) then restored += 1 end
    end
    safe(function() GENV().__sandbox = nil end)
    return restored .. " capabilities"
end

Steps.debug = function()
    local p = 0
    if type(debug) == "table" then
        for _, f in ipairs({ "getinfo","getfenv","setfenv","getupvalue","setupvalue" }) do
            if type(debug[f]) == "function" then p += 1 end
        end
    end
    return p .. " debug fns"
end

Steps.coroutine = function()
    local p = 0
    if type(coroutine) == "table" then
        for _, f in ipairs({ "status","running","isyieldable" }) do
            if type(coroutine[f]) == "function" then p += 1 end
        end
    end
    return p .. " coroutine fns"
end

Steps.thread_detect = function()
    local scanned = 0
    if hasExec("getconnections") then
        local gc = getExec("getconnections")
        for _, evName in ipairs({ "Error","ScriptAdded","ScriptRemoved" }) do
            local ev = ScriptContext[evName]
            if ev then safe(function() for _ in ipairs(gc(ev)) do scanned += 1 end end) end
        end
    end
    return scanned .. " connections"
end

Steps.rate_limit = function()
    local remotes = {}
    safe(function()
        for _, r in ipairs(ReplicatedStorage:GetDescendants()) do
            if r:IsA("RemoteEvent") then table.insert(remotes, r) end
        end
    end)
    local set = {}; for _, r in ipairs(remotes) do set[r] = true end
    local p = 0
    if #remotes > 0 and NM_Ensure() then
        NM_Register("FireServer", function(self) if set[self] then return "block" end return nil end)
        p = #remotes
    end
    return p .. " remotes wrapped"
end

Steps.environment = function()
    local cleared = 0
    local env = GENV()
    for _, key in ipairs({
        "syn","krnl","fluxus","scriptware","electron",
        "ac_signature","ac_id","ac_hash","antich_ver",
        "__anticheat","__ac","_ac_",
    }) do
        if rawget(env, key) ~= nil then
            pcall(function() rawset(env, key, nil) end); cleared += 1
        end
    end
    if hasExec("getgenv") then
        safe(function()
            local g = getgenv()
            local del = {}
            for k in pairs(g) do
                local ks = tostring(k):lower()
                if ks:find("^ac_") or ks:find("^__ac") or ks:find("anticheat") then
                    table.insert(del, k)
                end
            end
            for _, k in ipairs(del) do
                pcall(function() g[k] = nil end); cleared += 1
            end
        end)
    end
    return cleared .. " fingerprints"
end

--// ---- Adonis ---------------------------------------------------------------
local function _adonis_getGC()
    local getgc = getExec("getgc")
    if not getgc then return nil end
    local ok, iter = pcall(getgc, true)
    if ok and type(iter) == "table" then return iter end
    ok, iter = pcall(getgc)
    if ok and type(iter) == "table" then return iter end
    return nil
end
local function _adonis_setIdentity(level)
    local fn = getExec("setthreadidentity")
    if not fn then return false end
    return pcall(fn, level)
end
local function _adonis_getIdentity()
    local fn = getExec("getthreadidentity")
    if not fn then return nil end
    local ok, v = pcall(fn)
    if ok and type(v) == "number" then return v end
    return nil
end

Steps.adonis = function()
    local hookfunction = getExec("hookfunction")
    local newcclosure  = getExec("newcclosure")
    local getrenv      = getExec("getrenv")
    local getgc        = getExec("getgc")
    if not hookfunction then return "skipped (hookfunction missing)" end
    if not getgc then return "skipped (getgc missing)" end
    local saved_id = _adonis_getIdentity()
    _adonis_setIdentity(2)
    local Detected, Kill
    local hooked = {}
    local ok_scan, scan_err = pcall(function()
        local iter = _adonis_getGC()
        if not iter then error("getgc returned no table") end
        for _, v in pairs(iter) do
            if typeof(v) == "table" then
                local DetectFunc = rawget(v, "Detected")
                local KillFunc   = rawget(v, "Kill")
                if typeof(DetectFunc) == "function" and not Detected then
                    Detected = DetectFunc
                    local ok_hook = pcall(hookfunction, Detected, function(Action, Info, NoCrash) return true end)
                    if ok_hook then table.insert(hooked, "Detected") else Detected = nil end
                end
                if rawget(v, "Variables") ~= nil
                   and rawget(v, "Process") ~= nil
                   and typeof(KillFunc) == "function" and not Kill then
                    Kill = KillFunc
                    local ok_hook = pcall(hookfunction, Kill, function(Info) end)
                    if ok_hook then table.insert(hooked, "Kill") else Kill = nil end
                end
            end
        end
    end)
    if not ok_scan then
        _adonis_setIdentity(saved_id or 7)
        return "scan failed: " .. tostring(scan_err)
    end
    if Detected and getrenv then
        local ok_env, renv = pcall(getrenv)
        if ok_env and type(renv) == "table" and type(renv.debug) == "table" then
            local oldInfo = renv.debug.info
            if type(oldInfo) == "function" then
                local wrapped = function(...)
                    local LevelOrFunc = ...
                    if LevelOrFunc == Detected then
                        return coroutine.yield(coroutine.running())
                    end
                    return oldInfo(...)
                end
                if newcclosure then pcall(function() wrapped = newcclosure(wrapped) end) end
                local ok_hook = pcall(hookfunction, oldInfo, wrapped)
                if ok_hook then table.insert(hooked, "debug.info") end
            end
        end
    end
    _adonis_setIdentity(saved_id or 7)
    if #hooked == 0 then return "Adonis not detected in GC" end
    return string.format("Adonis: %d hook(s) [%s]", #hooked, table.concat(hooked, ", "))
end

--// ============================================================================
--// MENU OPTIONS
--// ============================================================================
local BYPASS_OPTIONS = {
    { id = "adonis",           label = "Adonis AntiCheat Bypass",   default = false },
    { id = "anti_detect",      label = "Anti-Detection Shield",     default = false },
    { id = "coroutine",        label = "Coroutine Bypass",          default = false },
    { id = "debug",            label = "Debug Library Bypass",      default = false },
    { id = "detour",           label = "Detour Bypass",             default = false },
    { id = "environment",      label = "Environment Bypass",        default = false },
    { id = "handshake",        label = "Handshake Bypass",          default = false },
    { id = "hookcheck",        label = "Hook Check Bypass",         default = false },
    { id = "integrity",        label = "Integrity Bypass",          default = false },
    { id = "kick_logger",      label = "Kick Reason Logger",        default = false },
    { id = "memory",           label = "Memory Bypass",             default = false },
    { id = "metamethod",       label = "Metamethod Bypass",         default = false },
    { id = "namecall",         label = "Namecall Bypass",           default = false },
    { id = "namecall_inst",    label = "NamecallInstance Bypass",   default = false },
    { id = "rate_limit",       label = "Rate Limit Bypass",         default = false },
    { id = "replace_humanoid", label = "replaceHumanoid(BAC)",      default = false },
    { id = "sandbox",          label = "Sandbox Bypass",            default = false },
    { id = "signature",        label = "Signature Bypass",          default = false },
    { id = "thread_detect",    label = "Thread Detection Bypass",   default = false },
    { id = "upvalue",          label = "Upvalue Bypass",            default = false },
    { id = "vm",               label = "VM Check Bypass",           default = false },
}

--// ============================================================================
--// GUI
--// ============================================================================
local MenuGui, MenuState = nil, {
    selected = {},
    done = false,
    version = "reloaded",
    searchQuery = "",
    category = "All",
    _rebuildList = function() end,
    _updateCounter = function() end,
}

local Theme = {
    bg        = Color3.fromRGB(22, 22, 26),
    bgAlt     = Color3.fromRGB(16, 16, 20),
    panel     = Color3.fromRGB(30, 30, 36),
    panelHover= Color3.fromRGB(40, 40, 48),
    accent    = Color3.fromRGB(90, 140, 255),
    accentHov = Color3.fromRGB(120, 160, 255),
    border    = Color3.fromRGB(55, 55, 65),
    borderHi  = Color3.fromRGB(90, 90, 105),
    text      = Color3.fromRGB(235, 235, 242),
    textDim   = Color3.fromRGB(150, 150, 165),
    textMuted = Color3.fromRGB(115, 115, 130),
    danger    = Color3.fromRGB(210, 80, 90),
    warn      = Color3.fromRGB(240, 180, 70),
    success   = Color3.fromRGB(90, 200, 130),
    new       = Color3.fromRGB(120, 220, 150),
}

local function corner(obj, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 6)
    c.Parent = obj
    return c
end

local function stroke(obj, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or Theme.border
    s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = obj
    return s
end

local function mkLabel(parent, props)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.Gotham
    l.TextColor3 = Theme.text
    l.TextSize = 12
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    for k, v in pairs(props or {}) do l[k] = v end
    l.Parent = parent
    return l
end

local function mkButton(parent, props)
    local b = Instance.new("TextButton")
    b.BorderSizePixel = 0
    b.BackgroundColor3 = Theme.panel
    b.Font = Enum.Font.GothamMedium
    b.TextColor3 = Theme.text
    b.TextSize = 12
    b.AutoButtonColor = false
    for k, v in pairs(props or {}) do b[k] = v end
    b.Parent = parent
    corner(b, 6)
    return b
end

local _gameName = nil
local function getGameName()
    if _gameName then return _gameName end
    local ok, info = pcall(function() return MarketplaceService:GetProductInfo(game.PlaceId) end)
    if ok and info and info.Name then
        _gameName = info.Name
    else
        _gameName = "Unknown"
    end
    return _gameName
end

local function versionDesc(v)
    if not v then return "" end
    local parts = { v.description }
    if v.type == "modules" then
        table.insert(parts, string.format("%d модулей", #v.files))
    elseif v.type == "combined" then
        local mv = AIRHUB_VERSIONS[v.modulesVersion]
        table.insert(parts, string.format("Remake (%d модулей) + Specific", mv and #mv.files or 0))
    end
    return table.concat(parts, " · ")
end

local function matchesFilter(opt)
    local q = MenuState.searchQuery
    if q ~= "" then
        local label = opt.label:lower()
        local id = opt.id:lower()
        if not (label:find(q, 1, true) or id:find(q, 1, true)) then return false end
    end
    if MenuState.category ~= "All" then
        local cat = BYPASS_CATEGORIES[opt.id] or "Other"
        if cat ~= MenuState.category then return false end
    end
    return true
end

local function buildMenu(onInject, onCancel)
    for _, o in ipairs(BYPASS_OPTIONS) do
        if MenuState.selected[o.id] == nil then
            MenuState.selected[o.id] = o.default
        end
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "AirHubBypassMenu"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local ok = pcall(function() gui.Parent = CoreGui end)
    if not ok and LP then
        local pg = LP:FindFirstChildOfClass("PlayerGui")
        if pg then pcall(function() gui.Parent = pg end) end
    end

    local frame = Instance.new("Frame", gui)
    frame.Size = UDim2.new(0, 540, 0, 800)
    frame.Position = UDim2.new(0.5, -270, 0.5, -400)
    frame.BackgroundColor3 = Theme.bg
    frame.BorderSizePixel = 0
    corner(frame, 12)
    stroke(frame, Theme.border, 1)

    -- Header
    local header = Instance.new("Frame", frame)
    header.Size = UDim2.new(1, 0, 0, 78)
    header.BackgroundColor3 = Theme.bgAlt
    header.BorderSizePixel = 0
    corner(header, 12)
    local headerMask = Instance.new("Frame", header)
    headerMask.Size = UDim2.new(1, 0, 0, 20)
    headerMask.Position = UDim2.new(0, 0, 1, -20)
    headerMask.BackgroundColor3 = Theme.bgAlt
    headerMask.BorderSizePixel = 0

    mkLabel(header, {
        Position = UDim2.new(0, 18, 0, 10),
        Size = UDim2.new(1, -36, 0, 26),
        Font = Enum.Font.GothamBold,
        TextSize = 20,
        Text = CONFIG.MENU_TITLE,
        TextColor3 = Theme.text,
    })

    mkLabel(header, {
        Position = UDim2.new(0, 18, 0, 38),
        Size = UDim2.new(1, -36, 0, 16),
        TextSize = 11,
        Text = string.format("%s  ·  PlaceId %d", getGameName(), tonumber(game.PlaceId) or -1),
        TextColor3 = Theme.textDim,
    })

    local function addBadge(text, xOffset, color)
        local b = Instance.new("Frame", header)
        b.Size = UDim2.new(0, 70, 0, 18)
        b.Position = UDim2.new(1, xOffset, 0, 40)
        b.BackgroundColor3 = color
        b.BackgroundTransparency = 0.75
        b.BorderSizePixel = 0
        corner(b, 4)
        mkLabel(b, {
            Size = UDim2.new(1, 0, 1, 0),
            Text = text,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextColor3 = color,
            Font = Enum.Font.GothamBold,
        })
        return b
    end
    local badgeX = -18
    if tonumber(game.PlaceId) == CONFIG.ARSENAL_PLACE_ID then
        addBadge("ARSENAL", badgeX, Theme.new); badgeX -= 78
    elseif tonumber(game.PlaceId) == CONFIG.RIVALS_PLACE_ID then
        addBadge("RIVALS", badgeX, Theme.new); badgeX -= 78
    elseif tonumber(game.PlaceId) == CONFIG.SPECIFIC_PLACE_ID then
        addBadge("SPECIFIC", badgeX, Theme.warn)
    end

    -- Version picker
    local versionSection = Instance.new("Frame", frame)
    versionSection.Position = UDim2.new(0, 14, 0, 90)
    versionSection.Size = UDim2.new(1, -28, 0, 145)
    versionSection.BackgroundTransparency = 1

    mkLabel(versionSection, {
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, 0, 0, 16),
        Text = "Версия",
        TextSize = 11,
        TextColor3 = Theme.textDim,
        Font = Enum.Font.GothamBold,
    })

    local versionGrid = Instance.new("Frame", versionSection)
    versionGrid.Position = UDim2.new(0, 0, 0, 20)
    versionGrid.Size = UDim2.new(1, 0, 0, 102)
    versionGrid.BackgroundTransparency = 1
    local grid = Instance.new("UIGridLayout", versionGrid)
    grid.CellSize = UDim2.new(0, 250, 0, 30) 
    grid.CellPadding = UDim2.new(0, 6, 0, 6)
    grid.SortOrder = Enum.SortOrder.LayoutOrder

    local versionDescLabel = mkLabel(versionSection, {
        Position = UDim2.new(0, 0, 0, 126),
        Size = UDim2.new(1, 0, 0, 14),
        Text = versionDesc(AIRHUB_VERSIONS[MenuState.version]),
        TextSize = 10,
        TextColor3 = Theme.textMuted,
    })

    local versionButtons = {}
    for i, vid in ipairs(AIRHUB_VERSION_ORDER) do
        local v = AIRHUB_VERSIONS[vid]
        local btn = mkButton(versionGrid, {
            LayoutOrder = i,
            Text = v.label,
            TextSize = 12,
        })
        if MenuState.version == vid then
            btn.BackgroundColor3 = Theme.accent
        end
        if v.isNew then
            local badge = Instance.new("Frame", btn)
            badge.Size = UDim2.new(0, 32, 0, 14)
            badge.Position = UDim2.new(1, -36, 0, 2)
            badge.BackgroundColor3 = Theme.new
            badge.BorderSizePixel = 0
            corner(badge, 3)
            mkLabel(badge, {
                Size = UDim2.new(1, 0, 1, 0),
                Text = "NEW",
                TextSize = 9,
                TextXAlignment = Enum.TextXAlignment.Center,
                TextColor3 = Theme.bg,
                Font = Enum.Font.GothamBold,
            })
        end
        btn.MouseEnter:Connect(function()
            if MenuState.version ~= vid then btn.BackgroundColor3 = Theme.panelHover end
            return nil
        end)
        btn.MouseLeave:Connect(function()
            if MenuState.version ~= vid then btn.BackgroundColor3 = Theme.panel end
            return nil
        end)
        btn.MouseButton1Click:Connect(function()
            MenuState.version = vid
            for oid, ob in pairs(versionButtons) do
                ob.BackgroundColor3 = (oid == vid) and Theme.accent or Theme.panel
            end
            versionDescLabel.Text = versionDesc(AIRHUB_VERSIONS[vid])
            return nil
        end)
        versionButtons[vid] = btn
    end

    -- Search row
    local searchRow = Instance.new("Frame", frame)
    searchRow.Position = UDim2.new(0, 14, 0, 245)
    searchRow.Size = UDim2.new(1, -28, 0, 28)
    searchRow.BackgroundColor3 = Theme.panel
    searchRow.BorderSizePixel = 0
    corner(searchRow, 6)
    stroke(searchRow, Theme.border, 1)

    mkLabel(searchRow, {
        Position = UDim2.new(0, 10, 0, 0),
        Size = UDim2.new(0, 16, 1, 0),
        Text = "/",
        TextColor3 = Theme.textMuted,
        TextSize = 12,
    })
    local searchBox = Instance.new("TextBox")
    searchBox.BackgroundTransparency = 1
    searchBox.Position = UDim2.new(0, 30, 0, 0)
    searchBox.Size = UDim2.new(1, -40, 1, 0)
    searchBox.Font = Enum.Font.Gotham
    searchBox.Text = ""
    searchBox.PlaceholderText = "Поиск байпаса..."
    searchBox.PlaceholderColor3 = Theme.textMuted
    searchBox.TextColor3 = Theme.text
    searchBox.TextSize = 12
    searchBox.TextXAlignment = Enum.TextXAlignment.Left
    searchBox.ClearTextOnFocus = false
    searchBox.Parent = searchRow

    -- Category tabs
    local catRow = Instance.new("Frame", frame)
    catRow.Position = UDim2.new(0, 14, 0, 281)
    catRow.Size = UDim2.new(1, -28, 0, 26)
    catRow.BackgroundTransparency = 1

    local catScroll = Instance.new("ScrollingFrame", catRow)
    catScroll.BackgroundTransparency = 1
    catScroll.BorderSizePixel = 0
    catScroll.Size = UDim2.new(1, 0, 1, 0)
    catScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    catScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
    catScroll.ScrollBarThickness = 0
    catScroll.ScrollingDirection = Enum.ScrollingDirection.X
    local catLayout = Instance.new("UIListLayout", catScroll)
    catLayout.FillDirection = Enum.FillDirection.Horizontal
    catLayout.Padding = UDim.new(0, 4)
    catLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local catButtons = {}
    for i, catName in ipairs(CATEGORY_ORDER) do
        local b = mkButton(catScroll, {
            LayoutOrder = i,
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = catName,
            TextSize = 11,
            TextColor3 = (MenuState.category == catName) and Theme.bg or Theme.text,
            BackgroundColor3 = (MenuState.category == catName) and Theme.accent or Theme.panel,
        })
        local pad = Instance.new("UIPadding", b)
        pad.PaddingLeft = UDim.new(0, 8)
        pad.PaddingRight = UDim.new(0, 8)
        b.MouseButton1Click:Connect(function()
            MenuState.category = catName
            for cname, cb in pairs(catButtons) do
                if cname == catName then
                    cb.BackgroundColor3 = Theme.accent; cb.TextColor3 = Theme.bg
                else
                    cb.BackgroundColor3 = Theme.panel; cb.TextColor3 = Theme.text
                end
            end
            MenuState._rebuildList()
            return nil
        end)
        catButtons[catName] = b
    end

    -- Bypass list
    local listFrame = Instance.new("Frame", frame)
    listFrame.Position = UDim2.new(0, 14, 0, 315)
    listFrame.Size = UDim2.new(1, -28, 1, -425)
    listFrame.BackgroundColor3 = Theme.bgAlt
    listFrame.BorderSizePixel = 0
    corner(listFrame, 8)
    stroke(listFrame, Theme.border, 1)

    local scroll = Instance.new("ScrollingFrame", listFrame)
    scroll.Position = UDim2.new(0, 4, 0, 4)
    scroll.Size = UDim2.new(1, -8, 1, -8)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 5
    scroll.ScrollBarImageColor3 = Theme.borderHi
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

    local layout = Instance.new("UIListLayout", scroll)
    layout.Padding = UDim.new(0, 3)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    local pad = Instance.new("UIPadding", scroll)
    pad.PaddingTop = UDim.new(0, 4)
    pad.PaddingBottom = UDim.new(0, 4)
    pad.PaddingLeft = UDim.new(0, 4)
    pad.PaddingRight = UDim.new(0, 4)

    local rowRefs = {}

    local function updateCheckbox(row, isSel)
        local box = row:FindFirstChild("Checkbox")
        local mark = box and box:FindFirstChild("Mark")
        if box then box.BackgroundColor3 = isSel and Theme.accent or Theme.panel end
        if mark then mark.Text = isSel and "X" or "" end
    end

    local function buildRow(opt, idx)
        local row = Instance.new("Frame", scroll)
        row.Size = UDim2.new(1, 0, 0, 30)
        row.BackgroundColor3 = Theme.panel
        row.BackgroundTransparency = 1
        row.BorderSizePixel = 0
        row.LayoutOrder = idx
        corner(row, 6)

        local isRisky = RISKY_BYPASSES[opt.id] == true
        local cat = BYPASS_CATEGORIES[opt.id] or "Other"

        local box = Instance.new("Frame", row)
        box.Name = "Checkbox"
        box.Size = UDim2.new(0, 18, 0, 18)
        box.Position = UDim2.new(0, 6, 0.5, -9)
        box.BackgroundColor3 = MenuState.selected[opt.id] and Theme.accent or Theme.panel
        box.BorderSizePixel = 0
        corner(box, 4)
        stroke(box, Theme.border, 1)

        mkLabel(box, {
            Name = "Mark",
            Size = UDim2.new(1, 0, 1, 0),
            Text = MenuState.selected[opt.id] and "X" or "",
            TextXAlignment = Enum.TextXAlignment.Center,
            TextColor3 = Theme.bg,
            Font = Enum.Font.GothamBold,
            TextSize = 13,
        })

        mkLabel(row, {
            Position = UDim2.new(0, 32, 0, 0),
            Size = UDim2.new(1, -220, 1, 0),
            Text = opt.label,
            TextSize = 12,
            TextColor3 = Theme.text,
        })

        local catBadge = Instance.new("Frame", row)
        catBadge.Size = UDim2.new(0, 0, 0, 16)
        catBadge.AutomaticSize = Enum.AutomaticSize.X
        catBadge.Position = UDim2.new(1, -150, 0.5, -8)
        catBadge.BackgroundColor3 = Theme.border
        catBadge.BackgroundTransparency = 0.5
        catBadge.BorderSizePixel = 0
        corner(catBadge, 3)
        local catPad = Instance.new("UIPadding", catBadge)
        catPad.PaddingLeft = UDim.new(0, 6)
        catPad.PaddingRight = UDim.new(0, 6)
        mkLabel(catBadge, {
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = cat,
            TextSize = 9,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextColor3 = Theme.textDim,
            Font = Enum.Font.GothamMedium,
        })

        if isRisky then
            local riskyBadge = Instance.new("Frame", row)
            riskyBadge.Size = UDim2.new(0, 48, 0, 16)
            riskyBadge.Position = UDim2.new(1, -56, 0.5, -8)
            riskyBadge.BackgroundColor3 = Theme.warn
            riskyBadge.BackgroundTransparency = 0.75
            riskyBadge.BorderSizePixel = 0
            corner(riskyBadge, 3)
            mkLabel(riskyBadge, {
                Size = UDim2.new(1, 0, 1, 0),
                Text = "RISKY",
                TextSize = 9,
                TextXAlignment = Enum.TextXAlignment.Center,
                TextColor3 = Theme.warn,
                Font = Enum.Font.GothamBold,
            })
        end

        local clickBtn = Instance.new("TextButton", row)
        clickBtn.BackgroundTransparency = 1
        clickBtn.Size = UDim2.new(1, 0, 1, 0)
        clickBtn.Text = ""
        clickBtn.ZIndex = 2
        clickBtn.MouseEnter:Connect(function()
            row.BackgroundTransparency = 0
            row.BackgroundColor3 = Theme.panelHover
            return nil
        end)
        clickBtn.MouseLeave:Connect(function()
            row.BackgroundTransparency = 1
            return nil
        end)
        clickBtn.MouseButton1Click:Connect(function()
            MenuState.selected[opt.id] = not MenuState.selected[opt.id]
            updateCheckbox(row, MenuState.selected[opt.id])
            MenuState._updateCounter()
            return nil
        end)

        rowRefs[opt.id] = row
        return row
    end

    local function rebuildList()
        for _, child in ipairs(scroll:GetChildren()) do
            if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
                child:Destroy()
            end
        end
        rowRefs = {}
        local visible = 0
        for idx, opt in ipairs(BYPASS_OPTIONS) do
            if matchesFilter(opt) then
                buildRow(opt, idx)
                visible += 1
            end
        end
        if visible == 0 then
            local empty = mkLabel(scroll, {
                Size = UDim2.new(1, 0, 0, 40),
                Text = "Ничего не найдено",
                TextXAlignment = Enum.TextXAlignment.Center,
                TextColor3 = Theme.textMuted,
                TextSize = 12,
            })
            empty.LayoutOrder = 999
        end
    end
    MenuState._rebuildList = rebuildList

    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        MenuState.searchQuery = string.lower(searchBox.Text or "")
        rebuildList()
        return nil
    end)

    -- Bottom bar
    local bottom = Instance.new("Frame", frame)
    bottom.Position = UDim2.new(0, 14, 1, -100)
    bottom.Size = UDim2.new(1, -28, 0, 30)
    bottom.BackgroundTransparency = 1

    local btnAll = mkButton(bottom, {
        Size = UDim2.new(0, 90, 1, 0),
        Text = "Select All",
        TextSize = 11,
    })
    local btnInvert = mkButton(bottom, {
        Size = UDim2.new(0, 90, 1, 0),
        Position = UDim2.new(0, 96, 0, 0),
        Text = "Invert",
        TextSize = 11,
    })
    local btnNone = mkButton(bottom, {
        Size = UDim2.new(0, 90, 1, 0),
        Position = UDim2.new(0, 192, 0, 0),
        Text = "Deselect All",
        TextSize = 11,
    })

    local counterLbl = mkLabel(bottom, {
        Position = UDim2.new(1, -180, 0, 0),
        Size = UDim2.new(0, 170, 1, 0),
        Text = "",
        TextXAlignment = Enum.TextXAlignment.Right,
        TextColor3 = Theme.textDim,
        TextSize = 11,
    })

    MenuState._updateCounter = function()
        local total, on = 0, 0
        for _, o in ipairs(BYPASS_OPTIONS) do
            total += 1
            if MenuState.selected[o.id] then on += 1 end
        end
        counterLbl.Text = string.format("%d/%d selected", on, total)
    end

    local function refreshAllRows()
        for id, row in pairs(rowRefs) do
            updateCheckbox(row, MenuState.selected[id] == true)
        end
        MenuState._updateCounter()
    end

    btnAll.MouseButton1Click:Connect(function()
        for _, o in ipairs(BYPASS_OPTIONS) do MenuState.selected[o.id] = true end
        refreshAllRows()
        return nil
    end)
    btnInvert.MouseButton1Click:Connect(function()
        for _, o in ipairs(BYPASS_OPTIONS) do
            MenuState.selected[o.id] = not MenuState.selected[o.id]
        end
        refreshAllRows()
        return nil
    end)
    btnNone.MouseButton1Click:Connect(function()
        for _, o in ipairs(BYPASS_OPTIONS) do MenuState.selected[o.id] = false end
        refreshAllRows()
        return nil
    end)

    -- Action row
    local actionRow = Instance.new("Frame", frame)
    actionRow.Position = UDim2.new(0, 14, 1, -62)
    actionRow.Size = UDim2.new(1, -28, 0, 44)
    actionRow.BackgroundTransparency = 1

    mkLabel(actionRow, {
        Size = UDim2.new(0, 240, 1, 0),
        Text = "Enter = Inject · Esc = Cancel · Ctrl+A = Select All",
        TextColor3 = Theme.textMuted,
        TextSize = 10,
    })

    local btnCancel = mkButton(actionRow, {
        Size = UDim2.new(0, 60, 1, 0),
        Position = UDim2.new(1, -260, 0, 0),
        Text = "Cancel",
        TextColor3 = Theme.danger,
        BackgroundColor3 = Color3.fromRGB(46, 30, 34),
    })
    btnCancel.MouseEnter:Connect(function() btnCancel.BackgroundColor3 = Color3.fromRGB(66, 40, 46) return nil end)
    btnCancel.MouseLeave:Connect(function() btnCancel.BackgroundColor3 = Color3.fromRGB(46, 30, 34) return nil end)

    local btnInject = mkButton(actionRow, {
        Size = UDim2.new(0, 190, 1, 0),
        Position = UDim2.new(1, -190, 0, 0),
        Text = "Inject AirHub",
        TextColor3 = Theme.bg,
        BackgroundColor3 = Theme.accent,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
    })
    btnInject.MouseEnter:Connect(function() btnInject.BackgroundColor3 = Theme.accentHov return nil end)
    btnInject.MouseLeave:Connect(function() btnInject.BackgroundColor3 = Theme.accent return nil end)

    btnCancel.MouseButton1Click:Connect(function()
        if MenuState.done then return end
        MenuState.done = true
        if onCancel then onCancel() end
        return nil
    end)
    btnInject.MouseButton1Click:Connect(function()
        if MenuState.done then return end
        MenuState.done = true
        local cfg = {}
        for id, v in pairs(MenuState.selected) do cfg[id] = v end
        cfg._version = MenuState.version
        if onInject then onInject(cfg) end
        return nil
    end)

    local UIS = game:GetService("UserInputService")
    UIS.InputBegan:Connect(function(inp, gpe)
        if gpe then return end
        if MenuState.done then return end
        if inp.KeyCode == Enum.KeyCode.Escape then
            MenuState.done = true
            if onCancel then onCancel() end
        elseif inp.KeyCode == Enum.KeyCode.Return then
            MenuState.done = true
            local cfg = {}
            for id, v in pairs(MenuState.selected) do cfg[id] = v end
            cfg._version = MenuState.version
            if onInject then onInject(cfg) end
        elseif inp.KeyCode == Enum.KeyCode.A and UIS:IsKeyDown(Enum.KeyCode.LeftControl) then
            for _, o in ipairs(BYPASS_OPTIONS) do MenuState.selected[o.id] = true end
            refreshAllRows()
        end
        return nil
    end)

    rebuildList()
    MenuState._updateCounter()

    MenuGui = gui
end

local function destroyMenu()
    if MenuGui then
        pcall(function() MenuGui:Destroy() end)
        MenuGui = nil
    end
end

--// ============================================================================
--// RUN SELECTED BYPASSES
--// ============================================================================
local function runSelectedBypasses(cfg)
    local ok_count, skip_count = 0, 0
    local total = #BYPASS_OPTIONS
    for i, opt in ipairs(BYPASS_OPTIONS) do
        if opt.id ~= "kick_logger" then
            if cfg[opt.id] then
                local fn = Steps[opt.id]
                if fn then
                    local ok, res = safe(fn)
                    if ok then
                        ok_count += 1
                        say(string.format("[AirHub]  [OK]  [%02d/%02d] %s  (%s)",
                            i, total, opt.label, tostring(res)))
                    else
                        swarn(string.format("[AirHub]  [FAIL] [%02d/%02d] %s  ->  %s",
                            i, total, opt.label, tostring(res)))
                    end
                end
            else
                skip_count += 1
                say(string.format("[AirHub]  [--]  [%02d/%02d] %s  (skipped)", i, total, opt.label))
            end
            tick()
        end
    end
    say(string.format("[AirHub] bypass done: %d ran, %d skipped", ok_count, skip_count))
end

--// ============================================================================
--// FAST LOADERS
--// ============================================================================
local function shouldLoadFile(file)
    local f = file:lower()
    if f:find("arsenal_extra_tab", 1, true) or f:find("arsenal extra tab", 1, true) then
        local pid = game.PlaceId
        if pid ~= CONFIG.ARSENAL_PLACE_ID then
            return false, string.format("skipped (wrong place: %d, need %d for Arsenal)",
                tonumber(pid) or -1, CONFIG.ARSENAL_PLACE_ID)
        end
    end
    if f:find("rivals_extra_tab", 1, true) then
        local pid = game.PlaceId
        if pid ~= CONFIG.RIVALS_PLACE_ID then
            return false, string.format("skipped (wrong place: %d, need %d for Rivals)",
                tonumber(pid) or -1, CONFIG.RIVALS_PLACE_ID)
        end
    end
    return true
end

local function loadModularVersion(version)
    local t0 = clockFn()
    say(string.format("[AirHub] Запуск модулей: %s", version.label))

    local files = version.files
    local total = #files
    local sources = {}
    local done = {}

    -- 1) Параллельный fetch
    for i, fname in ipairs(files) do
        spawnFn(function()
            local src, label = fetchOneFile(version.repo, fname)
            sources[i] = { src = src, label = label }
            done[i] = true
        end)
    end

    -- 2) Ожидание fetch с таймаутом
    local waitStart = clockFn()
    while clockFn() - waitStart < CONFIG.FETCH_TIMEOUT do
        local all = true
        for i = 1, total do
            if not done[i] then all = false break end
        end
        if all then break end
        waitFn(0.01)
    end

    local fetchTime = clockFn() - t0

    -- 3) Retry sequential
    local retried = 0
    for i, fname in ipairs(files) do
        local e = sources[i]
        if not e or not e.src then
            retried = retried + 1
            local src, label = fetchOneFile(version.repo, fname)
            sources[i] = { src = src, label = label }
        end
    end
    if retried > 0 then
        say(string.format("[AirHub] Повторная загрузка: %d файлов", retried))
    end

    -- 4) Последовательное выполнение
    local loaded, failed, skipped = 0, 0, 0
    local failed_files = {}

    for i, fname in ipairs(files) do
        local ok, reason = shouldLoadFile(fname)
        if not ok then
            skipped = skipped + 1
            say(string.format("[AirHub] [%02d/%02d] SKIP %-28s -> %s", i, total, fname, tostring(reason)))
        else
            local entry = sources[i]
            if not entry or not entry.src then
                failed = failed + 1
                local err = (entry and entry.label) or "fetch failed / timeout"
                table.insert(failed_files, { name = fname, err = err })
                swarn(string.format("[AirHub] [%02d/%02d] FAIL %-28s -> %s", i, total, fname, err))
            else
                local chunk, cerr = compile(entry.src, fname)
                if not chunk then
                    failed = failed + 1
                    local err = "compile: " .. tostring(cerr)
                    table.insert(failed_files, { name = fname, err = err })
                    swarn(string.format("[AirHub] [%02d/%02d] FAIL %-28s -> %s", i, total, fname, err))
                else
                    local run_ok, rerr = pcall(chunk)
                    if not run_ok then
                        failed = failed + 1
                        local err = "runtime: " .. tostring(rerr)
                        table.insert(failed_files, { name = fname, err = err })
                        swarn(string.format("[AirHub] [%02d/%02d] FAIL %-28s -> %s", i, total, fname, err))
                    else
                        loaded = loaded + 1
                        say(string.format("[AirHub] [%02d/%02d] OK   %-28s <- %s", i, total, fname, entry.label))
                    end
                end
            end
        end

        if i == 1 then waitFn() end
        if i < total then waitFn(0.01) end
    end

    local totalTime = clockFn() - t0
    say(string.format("[AirHub] Модули: %d/%d (успешно: %d, пропущено: %d, ошибок: %d) | fetch: %.2fs | total: %.2fs",
        loaded, total, loaded, skipped, failed, fetchTime, totalTime))
end

local function loadSingleFile(url, name, localFileName, localDirs)
    local src, source
    if localFileName then
        local localSrc, localPath = tryReadLocal(localFileName, localDirs or LOCAL_DIRS_MODULES)
        if localSrc then
            src = localSrc
            source = "LOCAL:" .. localPath
        end
    end
    if not src then
        src = httpGet(url)
        source = "HTTP:" .. tostring(url)
    end
    if not src then return false, "no source (local + http both failed)" end
    local cleanSrc, sanErr = sanitizeSource(src)
    if not cleanSrc then
        return false, string.format("bad source [%s]: %s", source, tostring(sanErr))
    end
    local chunk, err = compile(cleanSrc, name or "airhub_file")
    if not chunk then
        return false, "compile [" .. source .. "]: " .. tostring(err)
    end
    local ok, rerr = pcall(chunk)
    if not ok then
        return false, "runtime [" .. source .. "]: " .. tostring(rerr)
    end
    say("[AirHub]  loaded " .. tostring(name) .. "  <-  " .. source)
    return true
end

local function loadAirHub(versionId)
    local v = AIRHUB_VERSIONS[versionId]
    if not v then
        swarn("[AirHub] unknown version: " .. tostring(versionId)); return
    end
    say(string.format("[AirHub] loading version: %s (%s)", v.label, v.description))

    if v.type == "combined" then
        local mv = AIRHUB_VERSIONS[v.modulesVersion]
        local sv = AIRHUB_VERSIONS[v.singleVersion]
        if mv then
            say(string.format("[AirHub][COMBINED] step 1/2 → %s", mv.label))
            loadModularVersion(mv)
        end
        tick()
        if sv then
            say(string.format("[AirHub][COMBINED] step 2/2 → %s", sv.label))
            local ok, err = loadSingleFile(sv.url, "airhub_" .. sv.id, sv.localPath, LOCAL_DIRS_SINGLE)
            if ok then
                say(string.format("[AirHub][COMBINED] %s loaded successfully", sv.label))
            else
                swarn(string.format("[AirHub][COMBINED] %s failed: %s", sv.label, tostring(err)))
            end
        end
        return
    end

    if v.type == "modules" then
        loadModularVersion(v)
    elseif v.type == "single" then
        local ok, err = loadSingleFile(v.url, "airhub_" .. v.id, v.localPath, LOCAL_DIRS_SINGLE)
        if ok then
            say(string.format("[AirHub] %s loaded successfully", v.label))
        else
            swarn(string.format("[AirHub] %s failed: %s", v.label, tostring(err)))
        end
    end
end

--// ============================================================================
--// GAME DETECTION
--// ============================================================================
local function isSpecificGame()
    local ok, pid = pcall(function() return game.PlaceId end)
    if not ok or type(pid) ~= "number" then return false end
    return pid == CONFIG.SPECIFIC_PLACE_ID
end
local function isArsenalGame()
    local ok, pid = pcall(function() return game.PlaceId end)
    if not ok or type(pid) ~= "number" then return false end
    return pid == CONFIG.ARSENAL_PLACE_ID
end
local function isRivalsGame()
    local ok, pid = pcall(function() return game.PlaceId end)
    if not ok or type(pid) ~= "number" then return false end
    return pid == CONFIG.RIVALS_PLACE_ID
end

--// ============================================================================
--// MAIN FLOW
--// ============================================================================
local function startFlow()
    buildMenu(function(cfg)
        destroyMenu()

        local versionId = cfg._version or "reloaded"
        say(string.format("[AirHub] user config applied | version = %s", versionId))
        say(string.format("[AirHub] PlaceId = %d | game = %s",
            tonumber(game.PlaceId) or -1, getGameName()))
        say(string.format("[AirHub] arsenal gate = %s | rivals gate = %s",
            isArsenalGame() and "ENABLED" or "DISABLED",
            isRivalsGame() and "ENABLED" or "DISABLED"))

        runSelectedBypasses(cfg)

        if cfg.kick_logger then installAllKickHooks() end

        tick()
        loadAirHub(versionId)
    end, function()
        destroyMenu()
        say("[AirHub] injection cancelled")
    end)
end

pcall(function()
    GENV().AirHubLoader = {
        getKickHistory         = function() return KickLogger.events end,
        installKickLogger      = installAllKickHooks,
        logKick                = logKick,
        resetKickTracking      = resetKickTracking,
        replaceHumanoid        = replaceHumanoid,
        installReplaceHook     = installHumanoidReplaceHook,
        steps                  = Steps,
        versions               = AIRHUB_VERSIONS,
        isSpecificGame         = isSpecificGame,
        specificPlaceId        = CONFIG.SPECIFIC_PLACE_ID,
        isArsenalGame          = isArsenalGame,
        arsenalPlaceId         = CONFIG.ARSENAL_PLACE_ID,
        arsenalFile            = CONFIG.ARSENAL_FILE,
        isRivalsGame           = isRivalsGame,
        rivalsPlaceId          = CONFIG.RIVALS_PLACE_ID,
        rivalsFile             = CONFIG.RIVALS_FILE,
        sanitizeSource         = sanitizeSource,
    }
end)

startFlow()
