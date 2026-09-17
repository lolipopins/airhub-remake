--// ============================================================================
--// AirHub Remake — Loader v3 (Local Bypasses + Menu Control + Working Kick Log)
--// ============================================================================
--// Что исправлено:
--//   • Меню РЕАЛЬНО управляет — байпасы выполняются локально, а не из remote URL
--//   • Kick Logger ставится ПОСЛЕ байпасов (не перекрывается их hook'ом)
--//   • Ловит: Player:Kick, Player:Disconnect, PlayerRemoving, Moderator-сообщения,
--//     UI-элементы Adonis, OnClientEvent кик-remotes
--// ============================================================================

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

local CONFIG = {
    MENU_TITLE      = "AirHub Loader",
    KICK_LOG_PREFIX = "[AirHub][KICK]",
    BLOCK_KICK      = true,   -- спуфить кик (true) или пропустить (false)
    READY_TIMEOUT   = 3,
}

--// ============================================================================
--// HELPERS
--// ============================================================================
local _print = (type(print) == "function") and print or function() end
local _warn  = (type(warn)  == "function") and warn  or _print
local function say(...)   _print(...) end
local function swarn(...) _warn(...)  end

local function tick()
    if type(task) == "table" and type(task.wait) == "function" then
        task.wait()
    elseif type(wait) == "function" then
        wait()
    end
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

local function compile(src, name)
    if type(loadstring) == "function" then
        return loadstring(src, "@" .. name)
    elseif type(load) == "function" then
        return load(src, "@" .. name)
    end
    return nil, "loadstring/load unavailable"
end

--// ============================================================================
--// SERVICES
--// ============================================================================
local Players           = game:GetService("Players")
local CoreGui           = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptContext     = game:GetService("ScriptContext")
local RunService        = game:GetService("RunService")
local LP                = Players.LocalPlayer

--// ============================================================================
--// NAMECALL MANAGER (общий для всех байпасов)
--// ============================================================================
local NM = {
    hooked   = false,
    filters  = {},
    wrapper  = nil,
    original = nil,
}

local function NM_Ensure()
    if NM.hooked then return true end
    local hook      = getExec("hookmetamethod")
    local getMethod = getExec("getnamecallmethod")
    if not hook or not getMethod then return false end

    local getmt = getExec("getrawmetatable")
    if getmt then
        safe(function()
            local mt = getmt(game)
            if type(mt) == "table" then
                NM.original = rawget(mt, "__namecall")
            end
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
--// KICK REASON LOGGER
--// ============================================================================
local KickLogger = {
    hooked = false,
    events = {},
    max_events = 100,
    installed_sources = {},
}

local function fmtTime()
    return (type(os) == "table" and type(os.date) == "function")
        and os.date("%H:%M:%S") or "??:??:??"
end

local function logKick(reason, vector, target, caller)
    reason = tostring(reason or "unknown")
    vector = tostring(vector or "unknown")
    target = tostring(target or "unknown")
    caller = tostring(caller or "n/a")

    table.insert(KickLogger.events, {
        time = fmtTime(), reason = reason,
        vector = vector, target = target, caller = caller,
    })
    while #KickLogger.events > KickLogger.max_events do
        table.remove(KickLogger.events, 1)
    end

    local P = CONFIG.KICK_LOG_PREFIX
    swarn(P .. " ═════════════════════════════════════════")
    swarn(P .. "  ⚠ KICK DETECTED")
    swarn(P .. "  Reason : " .. reason)
    swarn(P .. "  Vector : " .. vector)
    swarn(P .. "  Target : " .. target)
    swarn(P .. "  Caller : " .. caller)
    swarn(P .. "  Time   : " .. fmtTime())
    swarn(P .. " ═════════════════════════════════════════")
end

local function callerDebug()
    local ok, info = pcall(function()
        if type(debug) == "table" and type(debug.info) == "function" then
            local _, name = debug.info(3, "sn")
            return name or "?"
        elseif type(debug) == "table" and type(debug.getinfo) == "function" then
            local d = debug.getinfo(3, "Sn")
            return (d and (d.short_src or d.source)) or "?"
        end
        return "?"
    end)
    return ok and info or "?"
end

--// ── Source 1: namecall hook (Kick / Disconnect) ──
local function installKickNamecallHook()
    if KickLogger.installed_sources.namecall then return true end
    if not NM_Ensure() then return false, "hookmetamethod unavailable" end

    NM_Register("Kick", function(self, ...)
        local reason = ...
        local target = (type(self) == "Instance")
            and (self == LP and "LocalPlayer" or (self:IsA("Player") and self.Name) or tostring(self))
            or "unknown"
        logKick(reason, "Player:Kick", target, callerDebug())
        if CONFIG.BLOCK_KICK then return "spoof_kick" end
    end)

    NM_Register("Disconnect", function(self)
        if type(self) == "Instance" and self == LP then
            logKick("client disconnect", "Player:Disconnect", "LocalPlayer", callerDebug())
            if CONFIG.BLOCK_KICK then return "spoof_kick" end
        end
    end)

    KickLogger.installed_sources.namecall = true
    return true
end

--// ── Source 2: PlayerRemoving ──
local function installPlayerRemovingHook()
    if KickLogger.installed_sources.removing then return true end
    safe(function()
        Players.PlayerRemoving:Connect(function(plr)
            if plr == LP then
                logKick("removed from game (server-side or client disconnect)",
                        "PlayerRemoving", "LocalPlayer", callerDebug())
            end
        end)
        KickLogger.installed_sources.removing = true
    end)
    return KickLogger.installed_sources.removing
end

--// ── Source 3: OnClientEvent кик-remotes ──
local function installModeratorHook()
    if KickLogger.installed_sources.moderator then return true end
    safe(function()
        for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
            if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
                local n = obj.Name:lower()
                if n:find("moderator") or n:find("mod message") or n:find("modkick")
                   or n:find("kick") or n:find("ban") or n:find("adonis") then
                    pcall(function()
                        obj.OnClientEvent:Connect(function(...)
                            local args = { ... }
                            local reason = "moderator/kick message"
                            for _, a in ipairs(args) do
                                if type(a) == "string" and #a > 0 then
                                    reason = a
                                    break
                                end
                            end
                            logKick(reason, "Remote.OnClientEvent", obj.Name, obj:GetFullName())
                        end)
                    end)
                end
            end
        end
        KickLogger.installed_sources.moderator = true
    end)
    return KickLogger.installed_sources.moderator
end

--// ── Source 4: UI-watcher (Adonis Moderator message GUI) ──
local function installUIWatcher()
    if KickLogger.installed_sources.ui then return true end
    safe(function()
        local pg = LP:FindFirstChildOfClass("PlayerGui")
        if not pg then return end

        local function checkGui(gui)
            local name = tostring(gui.Name):lower()
            if name:find("adonis") or name:find("moderator") or name:find("anti kick")
               or name:find("antikick") or name:find("kick") then
                -- Вытаскиваем текст из GUI как причину
                task.wait(0.05)
                local reason = "Adonis UI"
                for _, d in ipairs(gui:GetDescendants()) do
                    if d:IsA("TextLabel") and #d.Text > 0 and not d.Text:match("^%s*$") then
                        reason = d.Text
                        break
                    end
                end
                logKick(reason, "Adonis GUI", gui.Name, gui:GetFullName())
                if CONFIG.BLOCK_KICK then
                    pcall(function() gui:Destroy() end)
                end
            end
        end

        for _, child in ipairs(pg:GetChildren()) do checkGui(child) end

        pg.ChildAdded:Connect(function(child)
            task.wait(0.05)
            checkGui(child)
        end)

        KickLogger.installed_sources.ui = true
    end)
    return KickLogger.installed_sources.ui
end

--// ── Установить всё ──
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
--// BYPASS STEPS (локальные, выбираются из меню)
--// ============================================================================
local Steps = {}

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
                if n:find("handshake") or n:find("validate") or n:find("verify") then
                    set[obj] = true
                end
            end
        end
    end)
    local count = 0
    for _ in pairs(set) do count += 1 end
    if count > 0 and NM_Ensure() then
        local filter = function(self) if set[self] then return "block" end end
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
                i += 1
                if i > 3000 then break end
                if type(obj) == "table" and rawget(obj, "__acsignature") ~= nil then
                    pcall(function() rawset(obj, "__acsignature", nil) end)
                    patches += 1
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
                pcall(function() t[k] = nil end)
                cleared += 1
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
                i += 1
                if i > 2000 then break end
                if type(obj) == "function" then
                    local ok, ups = pcall(guv, obj)
                    if ok and type(ups) == "table" then
                        for idx, v in pairs(ups) do
                            if type(v) == "string" and #v > 64 then
                                if v:find("AC") or v:find("anticheat")
                                   or v:find("Signature") or v:find("checksum") then
                                    pcall(suv, obj, idx, "")
                                    cleaned += 1
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
    -- Kick здесь НЕ трогаем — оставлено для Kick Logger (ставится после)
    return ok and "hook installed" or "hookmetamethod unavailable"
end

Steps.namecall_inst = function()
    if not NM_Ensure() then return "hookmetamethod unavailable" end
    local getmt = getExec("getrawmetatable")
    local getMethod = getExec("getnamecallmethod")
    local checkC = getExec("checkcaller")

    NM_Register("GetDebugId", function(self)
        if type(self) == "Instance" then return "block" end
    end)

    for _, m in ipairs({ "GetFullName", "IsDescendantOf", "GetPropertyChangedSignal" }) do
        NM_Register(m, function(self)
            if type(self) ~= "Instance" then return nil end
            if checkC and not checkC() then return "block" end
        end)
    end

    local mtVerified = false
    if getmt then
        safe(function()
            local mt = getmt(game)
            if type(mt) == "table" then
                mtVerified = type(rawget(mt, "__namecall")) == "function"
            end
        end)
    end

    return string.format("mt %s, 3 methods guarded",
        mtVerified and "verified" or "unverified")
end

Steps.anti_detect = function()
    if not NM.hooked then return "hook not installed — skip" end
    local shields = 0
    local checkC = getExec("checkcaller")
    local getmt = getExec("getrawmetatable")
    local ggc = getExec("getgc")
    local guv = getExec("getupvalues")
    local suv = getExec("setupvalue")
    local hookf = getExec("hookfunction")
    local newc = getExec("newcclosure")

    if hookf and getmt and checkC and NM.original then
        safe(function()
            local orig = getmt
            local fake = function(obj)
                local mt = orig(obj)
                if not checkC() and obj == game and type(mt) == "table" then
                    local c = {}
                    for k, v in pairs(mt) do c[k] = v end
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
                i += 1
                if i > 5000 then break end
                if type(obj) == "table" then
                    for _, m in ipairs({ "__nm_wrapper", "__loader_ref" }) do
                        if rawget(obj, m) ~= nil then
                            pcall(function() rawset(obj, m, nil) end)
                            shields += 1
                        end
                    end
                end
            end
        end)
    end

    local guard, WINDOW, LIMIT = {}, 1.0, 50
    local function probe(self)
        if not checkC or checkC() then return nil end
        local now = tick and os.clock() or 0
        local key = (type(self) == "Instance") and self.ClassName or "?"
        local g = guard[key]
        if not g or (now - g.t) > WINDOW then
            guard[key] = { t = now, n = 1 }
            return nil
        end
        g.n += 1
        if g.n > LIMIT then return "block" end
    end
    for _, m in ipairs({ "GetFullName", "IsDescendantOf", "FindFirstChild" }) do
        NM_Register(m, probe)
    end
    shields += 1

    return shields .. " shields"
end

Steps.adonis_check = function()
    local env = GENV()
    local found = false
    if rawget(env, "Adonis") then found = true end
    if not found then
        for _, h in ipairs({ _G, rawget(env, "shared"), shared }) do
            if type(h) == "table" then
                for k in pairs(h) do
                    if type(k) == "string" and k:lower():find("adonis") then
                        found = true; break
                    end
                end
            end
            if found then break end
        end
    end

    local getmt = getExec("getrawmetatable")
    local hookf = getExec("hookfunction")
    local newc = getExec("newcclosure")

    if found and getmt and hookf then
        safe(function()
            local orig = getmt
            local fake = function(obj)
                local mt = orig(obj)
                if obj == env.Adonis and type(mt) == "table" then
                    local c = {}
                    for k, v in pairs(mt) do c[k] = v end
                    return c
                end
                return mt
            end
            if newc then pcall(function() fake = newc(fake) end) end
            pcall(function() hookf(getmt, fake) end)
        end)
    end

    -- Защита ключевых функций от clearing environment
    local PROT = { "hookmetamethod","getnamecallmethod","newcclosure","checkcaller",
                   "getrawmetatable","setrawmetatable","hookfunction","getgc",
                   "getupvalues","setupvalue","getconnections","firetouchinterest" }
    local saved = {}
    local g = GENV()
    for _, k in ipairs(PROT) do saved[k] = rawget(g, k) or rawget(_G, k) end
    task.spawn(function()
        while true do
            task.wait(2)
            local gg = GENV()
            for _, k in ipairs(PROT) do
                if rawget(gg, k) == nil and saved[k] ~= nil then
                    pcall(function() rawset(gg, k, saved[k]) end)
                end
            end
        end
    end)

    return "Adonis " .. (found and "detected" or "not found") .. " | env protected"
end

Steps.adonis_kick = function()
    if not NM_Ensure() then return "hookmetamethod unavailable" end

    -- Спуф Kick (в общий NM)
    local spoof = function(self)
        if type(self) == "Instance" and self:IsA("Player") then
            return "spoof_kick"
        end
    end
    NM_Register("Kick", spoof)
    NM_Register("kick", spoof)

    -- Блок Moderator-remotes
    local mod = {}
    safe(function()
        for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
            if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
                local n = obj.Name:lower()
                if n:find("moderator") or n:find("mod message") or n:find("modkick")
                   or n:find("anti kick") or n:find("antikick")
                   or n:find("adonis") or n:find("kick") or n:find("ban") then
                    mod[obj] = true
                end
            end
        end
    end)
    local blocked = 0
    local count = 0
    for _ in pairs(mod) do count += 1 end
    if count > 0 then
        local filter = function(self)
            if mod[self] then blocked += 1; return "block" end
        end
        NM_Register("FireServer", filter)
        NM_Register("InvokeServer", filter)
    end

    -- Удаление UI Adonis'а
    local ui = 0
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    if pg then
        local function clean(child)
            local n = tostring(child.Name):lower()
            if n:find("adonis") or n:find("moderator") or n:find("anti kick")
               or n:find("antikick") or n:find("adonisgui") then
                pcall(function() child:Destroy() end)
                ui += 1
            end
        end
        for _, c in ipairs(pg:GetChildren()) do clean(c) end
        pg.ChildAdded:Connect(function(c) task.wait(0.1); clean(c) end)
    end

    return string.format("kick spoofed | %d mod-remotes blocked | %d UIs removed", count, ui)
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
            if ev then
                safe(function()
                    for _ in ipairs(gc(ev)) do scanned += 1 end
                end)
            end
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
    local set = {}
    for _, r in ipairs(remotes) do set[r] = true end
    local p = 0
    if #remotes > 0 and NM_Ensure() then
        NM_Register("FireServer", function(self) if set[self] then return end end)
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
            pcall(function() rawset(env, key, nil) end)
            cleared += 1
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
                pcall(function() g[k] = nil end)
                cleared += 1
            end
        end)
    end
    return cleared .. " fingerprints"
end

--// ============================================================================
--// MENU
--// ============================================================================
local BYPASS_OPTIONS = {
    { id = "metamethod",    label = "Metamethod Bypass",       default = true },
    { id = "handshake",     label = "Handshake Bypass",        default = true },
    { id = "hookcheck",     label = "Hook Check Bypass",       default = true },
    { id = "detour",        label = "Detour Bypass",           default = true },
    { id = "memory",        label = "Memory Bypass",           default = true },
    { id = "vm",            label = "VM Check Bypass",         default = true },
    { id = "signature",     label = "Signature Bypass",        default = true },
    { id = "integrity",     label = "Integrity Bypass",        default = true },
    { id = "upvalue",       label = "Upvalue Bypass",          default = true },
    { id = "namecall",      label = "Namecall Bypass",         default = true },
    { id = "namecall_inst", label = "NamecallInstance Bypass", default = true },
    { id = "anti_detect",   label = "Anti-Detection Shield",   default = true },
    { id = "adonis_check",  label = "Adonis ClientCheck",      default = true },
    { id = "adonis_kick",   label = "Adonis Anti-Kick (0x4)",  default = true },
    { id = "sandbox",       label = "Sandbox Bypass",          default = true },
    { id = "debug",         label = "Debug Library Bypass",    default = true },
    { id = "coroutine",     label = "Coroutine Bypass",        default = true },
    { id = "thread_detect", label = "Thread Detection Bypass", default = true },
    { id = "rate_limit",    label = "Rate Limit Bypass",       default = true },
    { id = "environment",   label = "Environment Bypass",      default = true },
    { id = "kick_logger",   label = "Kick Reason Logger",      default = true },
}

local MenuGui, MenuState = nil, { selected = {}, done = false }

local function buildMenu(onInject, onCancel)
    for _, o in ipairs(BYPASS_OPTIONS) do MenuState.selected[o.id] = o.default end

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
    frame.Size = UDim2.new(0, 460, 0, 620)
    frame.Position = UDim2.new(0.5, -230, 0.5, -310)
    frame.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
    frame.BorderSizePixel = 0
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

    local stroke = Instance.new("UIStroke", frame)
    stroke.Thickness = 1
    stroke.Color = Color3.fromRGB(60, 60, 70)

    local title = Instance.new("TextLabel", frame)
    title.Size = UDim2.new(1, -24, 0, 40)
    title.Position = UDim2.new(0, 12, 0, 8)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 20
    title.TextColor3 = Color3.fromRGB(240, 240, 245)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = CONFIG.MENU_TITLE

    local sub = Instance.new("TextLabel", frame)
    sub.Size = UDim2.new(1, -24, 0, 20)
    sub.Position = UDim2.new(0, 12, 0, 46)
    sub.BackgroundTransparency = 1
    sub.Font = Enum.Font.Gotham
    sub.TextSize = 12
    sub.TextColor3 = Color3.fromRGB(140, 140, 155)
    sub.TextXAlignment = Enum.TextXAlignment.Left
    sub.Text = "Выбери обходы и нажми «Inject AirHub»"

    local scroll = Instance.new("ScrollingFrame", frame)
    scroll.Size = UDim2.new(1, -24, 1, -190)
    scroll.Position = UDim2.new(0, 12, 0, 76)
    scroll.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 6
    scroll.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 90)
    scroll.CanvasSize = UDim2.new(0, 0, 0, #BYPASS_OPTIONS * 32 + 8)
    Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 8)

    local layout = Instance.new("UIListLayout", scroll)
    layout.Padding = UDim.new(0, 4)
    layout.SortOrder = Enum.SortOrder.LayoutOrder

    local pad = Instance.new("UIPadding", scroll)
    pad.PaddingTop = UDim.new(0, 6)
    pad.PaddingBottom = UDim.new(0, 6)
    pad.PaddingLeft = UDim.new(0, 8)
    pad.PaddingRight = UDim.new(0, 8)

    local boxes = {}
    for i, opt in ipairs(BYPASS_OPTIONS) do
        local row = Instance.new("Frame", scroll)
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

        local mark = Instance.new("TextLabel", box)
        mark.Size = UDim2.new(1, 0, 1, 0)
        mark.BackgroundTransparency = 1
        mark.Text = opt.default and "✓" or ""
        mark.TextColor3 = Color3.fromRGB(255, 255, 255)
        mark.Font = Enum.Font.GothamBold
        mark.TextSize = 14

        local lbl = Instance.new("TextLabel", row)
        lbl.Size = UDim2.new(1, -30, 1, 0)
        lbl.Position = UDim2.new(0, 28, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 13
        lbl.TextColor3 = Color3.fromRGB(220, 220, 230)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Text = opt.label

        boxes[opt.id] = { box = box, mark = mark }
        box.MouseButton1Click:Connect(function()
            local s = not MenuState.selected[opt.id]
            MenuState.selected[opt.id] = s
            box.BackgroundColor3 = s and Color3.fromRGB(90, 140, 255) or Color3.fromRGB(40, 40, 48)
            mark.Text = s and "✓" or ""
        end)
    end

    local btnAll = Instance.new("TextButton", frame)
    btnAll.Size = UDim2.new(0, 90, 0, 26)
    btnAll.Position = UDim2.new(0, 12, 1, -70)
    btnAll.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
    btnAll.BorderSizePixel = 0
    btnAll.Font = Enum.Font.GothamMedium
    btnAll.TextSize = 12
    btnAll.TextColor3 = Color3.fromRGB(200, 200, 210)
    btnAll.Text = "Выбрать всё"
    Instance.new("UICorner", btnAll).CornerRadius = UDim.new(0, 6)

    local btnNone = Instance.new("TextButton", frame)
    btnNone.Size = UDim2.new(0, 90, 0, 26)
    btnNone.Position = UDim2.new(0, 108, 1, -70)
    btnNone.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
    btnNone.BorderSizePixel = 0
    btnNone.Font = Enum.Font.GothamMedium
    btnNone.TextSize = 12
    btnNone.TextColor3 = Color3.fromRGB(200, 200, 210)
    btnNone.Text = "Снять всё"
    Instance.new("UICorner", btnNone).CornerRadius = UDim.new(0, 6)

    local function setAll(v)
        for id, cb in pairs(boxes) do
            MenuState.selected[id] = v
            cb.box.BackgroundColor3 = v and Color3.fromRGB(90, 140, 255) or Color3.fromRGB(40, 40, 48)
            cb.mark.Text = v and "✓" or ""
        end
    end
    btnAll.MouseButton1Click:Connect(function() setAll(true) end)
    btnNone.MouseButton1Click:Connect(function() setAll(false) end)

    local btnInject = Instance.new("TextButton", frame)
    btnInject.Size = UDim2.new(0, 180, 0, 34)
    btnInject.Position = UDim2.new(1, -192, 1, -74)
    btnInject.BackgroundColor3 = Color3.fromRGB(90, 140, 255)
    btnInject.BorderSizePixel = 0
    btnInject.Font = Enum.Font.GothamBold
    btnInject.TextSize = 14
    btnInject.TextColor3 = Color3.fromRGB(255, 255, 255)
    btnInject.Text = "Inject AirHub"
    Instance.new("UICorner", btnInject).CornerRadius = UDim.new(0, 8)

    local btnCancel = Instance.new("TextButton", frame)
    btnCancel.Size = UDim2.new(0, 40, 0, 34)
    btnCancel.Position = UDim2.new(1, -42, 1, -74)
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

    -- Упорядоченный список (в порядке BYPASS_OPTIONS)
    for i, opt in ipairs(BYPASS_OPTIONS) do
        if opt.id ~= "kick_logger" then
            if cfg[opt.id] then
                local fn = Steps[opt.id]
                if fn then
                    local ok, res = safe(fn)
                    if ok then
                        ok_count += 1
                        say(string.format("[AirHub]  ✓  [%02d/%02d] %s  (%s)",
                            i, total, opt.label, tostring(res)))
                    else
                        swarn(string.format("[AirHub]  ✗  [%02d/%02d] %s  →  %s",
                            i, total, opt.label, tostring(res)))
                    end
                end
            else
                skip_count += 1
                say(string.format("[AirHub]  ○  [%02d/%02d] %s  (skipped)", i, total, opt.label))
            end
            tick()
        end
    end

    say(string.format("[AirHub] bypass done: %d ran, %d skipped", ok_count, skip_count))
end

--// ============================================================================
--// LOAD AIRHUB
--// ============================================================================
local function loadModule(file)
    local src = httpGet(REPO .. file)
    if not src then return false, "download failed" end
    local chunk, err = compile(src, file)
    if not chunk then return false, "compile: " .. tostring(err) end
    local ok, rerr = pcall(chunk)
    if not ok then return false, "runtime: " .. tostring(rerr) end
    return true
end

local function loadAllModules()
    local loaded, failed = 0, 0
    for _, file in ipairs(FILES) do
        local ok, err = loadModule(file)
        if ok then loaded += 1
        else swarn("[AirHub] " .. file .. ": " .. tostring(err)); failed += 1 end
        tick()
    end
    if failed > 0 then
        swarn("[AirHub] modules: " .. loaded .. "/" .. #FILES .. " (failed: " .. failed .. ")")
    else
        say("[AirHub] modules loaded: " .. loaded .. "/" .. #FILES)
    end
end

--// ============================================================================
--// MAIN FLOW
--// ============================================================================
local function startFlow()
    buildMenu(function(cfg)
        destroyMenu()
        say("[AirHub] user config applied")

        -- 1) Локальные байпасы по выбору
        runSelectedBypasses(cfg)

        -- 2) Kick Logger — ПОСЛЕ байпасов, чтобы наш хук был верхним
        if cfg.kick_logger then
            installAllKickHooks()
        end

        -- 3) Грузим AirHub
        tick()
        loadAllModules()
    end, function()
        destroyMenu()
        say("[AirHub] injection cancelled")
    end)
end

--// Публичный API
pcall(function()
    GENV().AirHubLoader = {
        getKickHistory = function() return KickLogger.events end,
        installKickLogger = installAllKickHooks,
        logKick = logKick,
        steps = Steps,
    }
end)

startFlow()
