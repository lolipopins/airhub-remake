--!nonstrict
--// ============================================================================
--// AirHub Loader + Specific Game version — Luau Edition
--// ============================================================================
--// Features:
--//   • Supports SIX versions (Full / Lite / Legacy / Original V2 / Original / Specific Game)
--//   • Specific Game loads the "+1 mog script" from lolipopins/airhub-remake
--//   • LOCAL PRIORITY: читает файлы из workspace (AirHub/src/...) если они есть,
--//     иначе качает по HTTP с GitHub.
--//   • Version picker in the menu (6 buttons)
--//   • Kick Logger with reason-change detection
--//   • All bypasses embedded, selectable from menu (OFF by default)
--//   • Adonis AntiCheat bypass (Detected/Kill + debug.info shield)
--//   • replaceHumanoid(BAC) — мягкая подмена Humanoid с авто-фиксом камеры
--//     и перезапуском Animate (минимум побочек).
--//   • Bypass list sorted alphabetically
--//   • "arsenal extra tab" loads ONLY when game.PlaceId == ARSENAL_PLACE_ID
--//   • sanitizeSource(): ловит HTTP 404 / HTML-ответы ДО loadstring
--// ============================================================================

--// ---------------------------------------------------------------------------
--// TYPES
--// ---------------------------------------------------------------------------

type VersionType = "modules" | "single"

type VersionConfig = {
	id: string,
	label: string,
	description: string,
	type: VersionType,
	repo: string?,
	files: { string }?,
	url: string?,
	localPath: string?,
}

type BypassOption = {
	id: string,
	label: string,
	default: boolean,
}

type KickKind = "first" | "changed" | "repeat"

type KickEvent = {
	time: string,
	reason: string,
	vector: string,
	target: string,
	caller: string,
	kind: KickKind,
	prev_reason: string?,
	repeat_count: number,
	change_count: number,
}

type BypassStep = () -> string
type StepMap = { [string]: BypassStep }

type UserConfig = { [string]: any }

type HttpGetter = (url: string) -> string?

type NMHandler = (self: any, ...any) -> string?
type NMFilterMap = { [string]: { NMHandler } }

--// ---------------------------------------------------------------------------
--// CONSTANTS
--// ---------------------------------------------------------------------------

local AIRHUB_VERSIONS: { [string]: VersionConfig } = {
	full = {
		id = "full",
		label = "Full",
		description = "Modular build (13 modules from /src/)",
		type = "modules",
		repo = "https://raw.githubusercontent.com/lolipopins/airhub-remake/main/src/",
		files = {
			"01_core.lua",
			"02_aimbot.lua",
			"03_antiaim.lua",
			"04_wallhack.lua",
			"05_serverposition.lua",
			"06a_movement_fly_bhop.lua",
			"06b_movement_speed_strafer.lua",
			"07a_ui_core.lua",
			"07b_ui_tabs.lua",
			"08_world.lua",
			"09_exploits.lua",
			"10_hud.lua",
			"arsenal extra tab",
		},
	},
	lite = {
		id = "lite",
		label = "Lite",
		description = "Single-file, GUI bypass, no config system",
		type = "single",
		url = "https://raw.githubusercontent.com/lolipopins/airhub-remake/refs/heads/main/airhub%20lite",
		localPath = "airhub lite.lua",
	},
	legacy = {
		id = "legacy",
		label = "Legacy",
		description = "Single-file, archived (no updates)",
		type = "single",
		url = "https://raw.githubusercontent.com/lolipopins/airhub-remake/refs/heads/main/airhub%20legacy",
		localPath = "airhub legacy.lua",
	},
	original_v2 = {
		id = "original_v2",
		label = "Original V2",
		description = "Exunys official V2 (Aimbot + ESP + Crosshair)",
		type = "single",
		url = "https://raw.githubusercontent.com/Exunys/AirHub-V2/main/src/Main.lua",
		localPath = "original_v2.lua",
	},
	original = {
		id = "original",
		label = "Original",
		description = "Exunys official V1 (Aimbot + WallHack)",
		type = "single",
		url = "https://raw.githubusercontent.com/Exunys/AirHub/main/AirHub.lua",
		localPath = "original.lua",
	},
	specific_game = {
		id = "specific_game",
		label = "Specific Game",
		description = "Custom mod menu: Auto Mog / Auto Clicker / Noclip / Speed",
		type = "single",
		url = "https://raw.githubusercontent.com/lolipopins/airhub-remake/refs/heads/main/specific%20games/%2B1%20mog%20evolution",
		localPath = "+1 mog script.lua",
	},
}

local AIRHUB_VERSION_ORDER: { string } = {
	"full", "lite", "legacy", "original_v2", "original", "specific_game",
}

local LOCAL_DIRS_MODULES: { string } = {
	"AirHub/src/",
	"airhub/src/",
	"src/",
	"",
}

local LOCAL_DIRS_SINGLE: { string } = {
	"AirHub/",
	"airhub/",
	"",
	".",
}

local CONFIG = {
	MENU_TITLE = "AirHub Loader",
	KICK_LOG_PREFIX = "[AirHub][KICK]",
	BLOCK_KICK = true,
	SPECIFIC_PLACE_ID = 92648272637932,
	ARSENAL_PLACE_ID = 286090429,
	ARSENAL_FILE = "arsenal extra tab",
}

--// ---------------------------------------------------------------------------
--// HELPERS
--// ---------------------------------------------------------------------------

local _print: (...any) -> () = if type(print) == "function" then print else function() end
local _warn: (...any) -> () = if type(warn) == "function" then warn else _print

local function say(...: any) _print(...) end
local function swarn(...: any) _warn(...) end

local function tick(): ()
	if type(task) == "table" and type(task.wait) == "function" then
		task.wait()
	elseif type(wait) == "function" then
		wait()
	end
end

local function GENV(): { [any]: any }
	if type(getgenv) == "function" then
		local ok, env = pcall(getgenv)
		if ok and type(env) == "table" then
			return env
		end
	end
	return _G
end

local function getExec(name: string): any
	local f = rawget(_G, name)
	if type(f) == "function" then
		return f
	end
	local env = GENV()
	if env ~= _G then
		f = rawget(env, name)
		if type(f) == "function" then
			return f
		end
	end
	return nil
end

local function hasExec(name: string): boolean
	return getExec(name) ~= nil
end

local function safe<A..., R...>(fn: (A...) -> R..., ...: A...): (boolean, R...)
	local r = table.pack(pcall(fn, ...))
	if not r[1] then
		return false, r[2]
	end
	return true, table.unpack(r, 2, r.n)
end

--// ---- File sources ---------------------------------------------------------

local function httpGet(url: string): string?
	local methods: { () -> string? } = {
		function()
			if type(HttpGet) == "function" then return HttpGet(url) end
			return nil
		end,
		function()
			if game and type(game.HttpGet) == "function" then return game:HttpGet(url) end
			return nil
		end,
		function()
			if game and type(game.HttpGetAsync) == "function" then return game:HttpGetAsync(url) end
			return nil
		end,
		function()
			if type(request) == "function" then
				local r = request({ Url = url, Method = "GET" })
				return r and r.Body
			end
			return nil
		end,
		function()
			if type(http_request) == "function" then
				local r = http_request({ Url = url, Method = "GET" })
				return r and r.Body
			end
			return nil
		end,
		function()
			if type(syn) == "table" and type(syn.request) == "function" then
				local r = syn.request({ Url = url, Method = "GET" })
				return r and r.Body
			end
			return nil
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

--// Проверяет, что источник — реальный Lua, а не 404-страница.
local function sanitizeSource(src: any): (string?, string?)
	if type(src) ~= "string" or #src == 0 then
		return nil, "empty source"
	end

	local trimmed = (src :: string):gsub("^%s+", "")
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
		return nil, "HTTP 404 / not found (file missing on remote?)"
	end

	local looksLikeLua = lowerHead:find("local ", 1, true)
		or lowerHead:find("--", 1, true)
		or lowerHead:find("return", 1, true)
		or lowerHead:find("if ", 1, true)
		or lowerHead:find("getgenv", 1, true)
		or lowerHead:find("warn(", 1, true)

	if not looksLikeLua then
		return nil, "response does not look like Lua source"
	end

	return src, nil
end

local function tryReadLocal(filename: string, dirs: { string }): (string?, string?)
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

local function compile(src: string, name: string): (any, string?)
	if type(loadstring) == "function" then
		return loadstring(src, "@" .. name)
	elseif type(load) == "function" then
		return load(src, "@" .. name)
	end
	return nil, "loadstring/load unavailable"
end

--// ---------------------------------------------------------------------------
--// SERVICES
--// ---------------------------------------------------------------------------

local Players: any = game:GetService("Players")
local CoreGui: any = game:GetService("CoreGui")
local ReplicatedStorage: any = game:GetService("ReplicatedStorage")
local ScriptContext: any = game:GetService("ScriptContext")
local RunService: any = game:GetService("RunService")
local LP: any = Players.LocalPlayer

--// ---------------------------------------------------------------------------
--// NAMECALL MANAGER
--// ---------------------------------------------------------------------------

type NMManager = {
	hooked: boolean,
	filters: NMFilterMap,
	wrapper: any,
	original: any,
}

local NM: NMManager = {
	hooked = false,
	filters = {},
	wrapper = nil,
	original = nil,
}

local function NM_Ensure(): boolean
	if NM.hooked then return true end

	local hook = getExec("hookmetamethod")
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
		local old: any
		local wrapper = function(self: any, ...: any)
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

local function NM_Register(method: string, handler: NMHandler): ()
	if not NM.filters[method] then
		NM.filters[method] = {}
	end
	table.insert(NM.filters[method], handler)
end

--// ---------------------------------------------------------------------------
--// KICK REASON LOGGER
--// ---------------------------------------------------------------------------

type KickLoggerState = {
	events: { KickEvent },
	max_events: number,
	installed_sources: { [string]: boolean },
	last_reason: string?,
	last_vector: string?,
	repeat_count: number,
	change_count: number,
}

local KickLogger: KickLoggerState = {
	events = {},
	max_events = 100,
	installed_sources = {},
	last_reason = nil,
	last_vector = nil,
	repeat_count = 0,
	change_count = 0,
}

local function fmtTime(): string
	if type(os) == "table" and type(os.date) == "function" then
		return os.date("%H:%M:%S")
	end
	return "??:??:??"
end

local function normalizeReason(r: any): string
	local s = tostring(r or "unknown")
	s = s:gsub("^%s+", ""):gsub("%s+$", "")
	if s == "" then s = "unknown" end
	return s
end

local function resetKickTracking(): ()
	KickLogger.last_reason = nil
	KickLogger.last_vector = nil
	KickLogger.repeat_count = 0
	KickLogger.change_count = 0
end

local function logKick(reason: any, vector: any, target: any, caller: any): ()
	reason = normalizeReason(reason)
	vector = tostring(vector or "unknown")
	target = tostring(target or "unknown")
	caller = tostring(caller or "n/a")

	local prev = KickLogger.last_reason
	local is_first = prev == nil
	local is_repeat = prev ~= nil and prev == reason
	local is_change = prev ~= nil and prev ~= reason

	if is_repeat then
		KickLogger.repeat_count += 1
	else
		KickLogger.repeat_count = 1
	end
	if is_change then
		KickLogger.change_count += 1
	end

	KickLogger.last_reason = reason
	KickLogger.last_vector = vector

	local kind: KickKind = if is_first then "first" elseif is_change then "changed" else "repeat"

	table.insert(KickLogger.events, {
		time = fmtTime(),
		reason = reason,
		vector = vector,
		target = target,
		caller = caller,
		kind = kind,
		prev_reason = prev,
		repeat_count = KickLogger.repeat_count,
		change_count = KickLogger.change_count,
	})

	while #KickLogger.events > KickLogger.max_events do
		table.remove(KickLogger.events, 1)
	end

	local P = CONFIG.KICK_LOG_PREFIX
	swarn(P .. " =========================================")

	if is_first then
		swarn(P .. "  [!]  KICK DETECTED (first)")
		swarn(P .. "  Reason : " .. reason)
	elseif is_change then
		swarn(string.format("%s  [!!] KICK REASON CHANGED  (#%d)", P, KickLogger.change_count))
		swarn(P .. "  Prev   : " .. tostring(prev))
		swarn(P .. "  New    : " .. reason)
	else
		swarn(string.format("%s  [!]  KICK REPEATED  (x%d)", P, KickLogger.repeat_count))
		swarn(P .. "  Reason : " .. reason)
	end

	swarn(P .. "  Vector : " .. vector)
	swarn(P .. "  Target : " .. target)
	swarn(P .. "  Caller : " .. caller)
	swarn(P .. "  Time   : " .. fmtTime())
	swarn(P .. " =========================================")
end

local function callerDebug(): string
	local ok, info = pcall(function(): string
		if type(debug) == "table" and type(debug.info) == "function" then
			local _, name = debug.info(3, "sn")
			return name or "?"
		elseif type(debug) == "table" and type(debug.getinfo) == "function" then
			local d = debug.getinfo(3, "Sn")
			return (d and (d.short_src or d.source)) or "?"
		end
		return "?"
	end)
	return if ok then info else "?"
end

local function installKickNamecallHook(): (boolean, string?)
	if KickLogger.installed_sources.namecall then return true end
	if not NM_Ensure() then return false, "hookmetamethod unavailable" end

	NM_Register("Kick", function(self: any, ...: any): string?
		local reason = ...
		local target: string
		if type(self) == "Instance" then
			if self == LP then
				target = "LocalPlayer"
			elseif self:IsA("Player") then
				target = self.Name
			else
				target = tostring(self)
			end
		else
			target = "unknown"
		end
		logKick(reason, "Player:Kick", target, callerDebug())
		if CONFIG.BLOCK_KICK then return "spoof_kick" end
		return nil
	end)

	NM_Register("Disconnect", function(self: any): string?
		if type(self) == "Instance" and self == LP then
			logKick("client disconnect", "Player:Disconnect", "LocalPlayer", callerDebug())
			if CONFIG.BLOCK_KICK then return "spoof_kick" end
		end
		return nil
	end)

	KickLogger.installed_sources.namecall = true
	return true, nil
end

local function installPlayerRemovingHook(): boolean
	if KickLogger.installed_sources.removing then return true end

	safe(function()
		Players.PlayerRemoving:Connect(function(plr: any)
			if plr == LP then
				logKick(
					"removed from game (server-side or client disconnect)",
					"PlayerRemoving",
					"LocalPlayer",
					callerDebug()
				)
			end
		end)
		KickLogger.installed_sources.removing = true
	end)

	return KickLogger.installed_sources.removing or false
end

local function installModeratorHook(): boolean
	if KickLogger.installed_sources.moderator then return true end

	safe(function()
		for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
			if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
				local n = obj.Name:lower()
				if n:find("moderator")
					or n:find("mod message")
					or n:find("modkick")
					or n:find("kick")
					or n:find("ban")
				then
					pcall(function()
						obj.OnClientEvent:Connect(function(...: any)
							local args = { ... }
							local reason: any = "moderator/kick message"
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

	return KickLogger.installed_sources.moderator or false
end

local function installUIWatcher(): boolean
	if KickLogger.installed_sources.ui then return true end

	safe(function()
		local pg = LP:FindFirstChildOfClass("PlayerGui")
		if not pg then return end

		local watched_labels: { [any]: boolean } = {}

		local function watchLabel(label: any, guiRef: any)
			if watched_labels[label] then return end
			watched_labels[label] = true
			label:GetPropertyChangedSignal("Text"):Connect(function()
				local txt = label.Text
				if txt and txt ~= "" and not txt:match("^%s*$") then
					logKick(
						txt,
						"GUI.TextChanged",
						guiRef and guiRef.Name or "ModeratorUI",
						label:GetFullName()
					)
				end
			end)
		end

		local function checkGui(gui: any)
			local name = tostring(gui.Name):lower()
			if name:find("moderator")
				or name:find("anti kick")
				or name:find("antikick")
				or name:find("kick")
			then
				task.wait(0.05)
				local initial_reason: string? = nil
				for _, d in ipairs(gui:GetDescendants()) do
					if d:IsA("TextLabel") and #d.Text > 0 and not d.Text:match("^%s*$") then
						if not initial_reason then
							initial_reason = d.Text
						end
						watchLabel(d, gui)
					end
				end
				if initial_reason then
					logKick(initial_reason, "Moderator GUI", gui.Name, gui:GetFullName())
				end
				if CONFIG.BLOCK_KICK then
					pcall(function() gui:Destroy() end)
				end
			end
		end

		for _, child in ipairs(pg:GetChildren()) do
			checkGui(child)
		end

		pg.ChildAdded:Connect(function(child: any)
			task.wait(0.05)
			checkGui(child)
		end)

		KickLogger.installed_sources.ui = true
	end)

	return KickLogger.installed_sources.ui or false
end

local function installAllKickHooks(): boolean
	local nc_ok, nc_err = installKickNamecallHook()
	if nc_ok then
		say(CONFIG.KICK_LOG_PREFIX .. " namecall hook installed")
	else
		swarn(CONFIG.KICK_LOG_PREFIX .. " namecall hook failed: " .. tostring(nc_err))
	end

	installPlayerRemovingHook()
	installModeratorHook()
	installUIWatcher()

	return nc_ok
end

--// ---------------------------------------------------------------------------
--// BYPASS STEPS
--// ---------------------------------------------------------------------------

local Steps
