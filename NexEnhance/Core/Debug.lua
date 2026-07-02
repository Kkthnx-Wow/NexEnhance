--[[
	NexEnhance - Debug
	-------------------------------------------------------------------------
	Central diagnostics for modules and core code. Register a scope per feature,
	log with expectations, dump state to chat, and export a copy-paste report
	for bug reports / AI-assisted triage (paste the chat block — then go play the
	game, you've earned it).

	Module pattern (at load or OnInitialize):

	    ns.Debug.BindModule(self, "uiScale", {
	        title = L["UI Scale"],
	        dump = function() ... end,
	        expectations = {
	            { name = "C.Mult > 0", test = function() return C.Mult > 0 end },
	        },
	    })
	    self:DebugLog("info", "scale applied", scale)

	Slash commands:
	    /nex debug              - help
	    /nex debug list         - registered scopes
	    /nex debug on|off|toggle [scope|all] [persist]
	    /nex debug dump [scope|all]
	    /nex debug log [count]  - recent ring buffer
	    /nex debug export       - full report (copy from chat)

	Run expectations anywhere:
	    ns.Debug.Expect("uiScale", condition, "message %s", value)
--]]

local _, ns = ...
local C, F, L = ns.C, ns.F, ns.L

local type, tostring, format = type, tostring, string.format
local tinsert, tremove, wipe = table.insert, table.remove, wipe
local date = date
local GetTime = GetTime
local GetBuildInfo = GetBuildInfo
local GetPhysicalScreenSize = GetPhysicalScreenSize
local InCombatLockdown = InCombatLockdown
local GetZoneText = GetZoneText
local GetCVar = GetCVar
local UIParent = UIParent
local ipairs = ipairs
local pairs = pairs
local sort = table.sort
local math_max = math.max
local tconcat = table.concat

-- Scratch for export dump capture (reused; not retained across calls).
local dumpCapture = {}
local scopeSortScratch = {}

-- Publish the API table before RegisterDefaults — Debug.lua used to sit before
-- Database.lua in the TOC, so ns:RegisterDefaults was nil and the whole file
-- aborted before this assignment (every BindModule call then saw ns.Debug nil).
local Debug = {}
ns.Debug = Debug

ns:RegisterDefaults({
	debug = {
		scopes = {},
		recordAll = false,
	},
}, "global")

local LEVEL = {
	trace = 1,
	info = 2,
	pass = 2,
	warn = 3,
	fail = 4,
}

local MAX_LOG = 250
local log = {}
local scopes = {}
local session = {}

-- Reusable format scratch (avoid garbage in hot Log paths).
local fmtScratch = {}

local function SafeStr(v)
	if v == nil then
		return "nil"
	end
	-- Midnight said no peeking. Fine.
	if F.IsSecret(v) then
		return "<secret>"
	end
	local ok, s = pcall(tostring, v)
	return ok and s or "<tostring error>"
end

local function FormatMsg(msg, ...)
	if select("#", ...) == 0 then
		return tostring(msg)
	end
	wipe(fmtScratch)
	for i = 1, select("#", ...) do
		fmtScratch[i] = SafeStr(select(i, ...))
	end
	local ok, out = pcall(format, tostring(msg), unpack(fmtScratch))
	return ok and out or (tostring(msg) .. " (format error)")
end

local function ScopeKey(name)
	return name and name:lower() or ""
end

local function IsScopeEnabled(key)
	if session[key] then
		return true
	end
	local g = ns.global and ns.global.debug
	if g and g.scopes and g.scopes[key] then
		return true
	end
	if session.__all or (g and g.scopes and g.scopes.__all) then
		return true
	end
	return false
end

local function ShouldRecord(levelKey)
	if ns.global and ns.global.debug and ns.global.debug.recordAll then
		return true
	end
	local n = LEVEL[levelKey] or LEVEL.info
	if n >= LEVEL.warn then
		return true
	end
	return false
end

local function AppendLog(entry)
	log[#log + 1] = entry
	if #log > MAX_LOG then
		tremove(log, 1)
	end
end

local function Timestamp()
	return date("%H:%M:%S", GetTime())
end

local function SortedScopeKeys()
	wipe(scopeSortScratch)
	for key in pairs(scopes) do
		scopeSortScratch[#scopeSortScratch + 1] = key
	end
	sort(scopeSortScratch, function(a, b)
		local ta = (scopes[a] and scopes[a].title) or a
		local tb = (scopes[b] and scopes[b].title) or b
		return ta:lower() < tb:lower()
	end)
	return scopeSortScratch
end

local function CollectDumpLines(def)
	if not def or not def.dump then
		return nil
	end
	wipe(dumpCapture)
	local origPrint = F.Print
	F.Print = function(msg)
		dumpCapture[#dumpCapture + 1] = tostring(msg)
	end
	local ok, err = pcall(def.dump)
	F.Print = origPrint
	if not ok then
		dumpCapture[#dumpCapture + 1] = format("  (dump error: %s)", SafeStr(err))
	end
	return dumpCapture
end

--- Append to the ring buffer; print to chat when the scope (or recordAll) is on.
function Debug.Log(scope, level, msg, ...)
	local key = ScopeKey(scope)
	level = level or "info"
	local text = FormatMsg(msg, ...)
	local entry = {
		t = Timestamp(),
		scope = scope or "?",
		level = level,
		text = text,
	}

	local enabled = IsScopeEnabled(key)
	if enabled or ShouldRecord(level) then
		AppendLog(entry)
	end

	if not enabled and LEVEL[level] ~= LEVEL.fail then
		return
	end

	local color = "white"
	if level == "warn" then
		color = "yellow"
	elseif level == "fail" then
		color = "red"
	elseif level == "pass" then
		color = "green"
	end
	F.Print(F.Colorize(format("[%s][%s] %s", scope, level:upper(), text), color))
end

--- Assert-style check; logs FAIL and returns false when `condition` is falsy.
function Debug.Expect(scope, condition, msg, ...)
	if condition then
		if IsScopeEnabled(ScopeKey(scope)) then
			Debug.Log(scope, "pass", msg, ...)
		end
		return true
	end
	Debug.Log(scope, "fail", msg, ...)
	return false
end

function Debug.RegisterScope(key, opts)
	key = ScopeKey(key)
	scopes[key] = {
		key = key,
		title = opts.title or key,
		dump = opts.dump,
		expectations = opts.expectations,
		module = opts.module,
	}
end

--- Attach DebugLog / ToggleDebug to a module and register its scope.
function Debug.BindModule(module, key, opts)
	opts = opts or {}
	Debug.RegisterScope(key, {
		title = opts.title or (module and module.title) or (module and module.name) or key,
		dump = opts.dump,
		expectations = opts.expectations,
		module = module,
	})

	if not module then
		return
	end

	function module:DebugLog(level, msg, ...)
		Debug.Log(key, level, msg, ...)
	end

	function module:ToggleDebug(persist)
		Debug.ToggleScope(key, persist)
	end
end

function Debug.IsEnabled(scope)
	return IsScopeEnabled(ScopeKey(scope))
end

function Debug.SetScope(scope, enabled, persist)
	local key = ScopeKey(scope)
	if key == "all" then
		key = "__all"
	end
	if enabled then
		session[key] = true
		if persist and ns.global then
			ns.global.debug = ns.global.debug or {}
			ns.global.debug.scopes = ns.global.debug.scopes or {}
			ns.global.debug.scopes[key] = true
		end
	else
		session[key] = nil
		if persist and ns.global and ns.global.debug and ns.global.debug.scopes then
			ns.global.debug.scopes[key] = nil
		end
	end
end

function Debug.ToggleScope(scope, persist)
	local key = ScopeKey(scope)
	if key == "all" then
		key = "__all"
	end
	local now = not IsScopeEnabled(key)
	if now then
		Debug.SetScope(key == "__all" and "all" or scope, true, persist)
	else
		Debug.SetScope(key == "__all" and "all" or scope, false, persist)
		if persist and ns.global and ns.global.debug and ns.global.debug.scopes then
			ns.global.debug.scopes[key] = nil
		end
		session[key] = nil
	end
	local def = scopes[key == "__all" and "all" or key] or scopes[key]
	local label = def and def.title or scope
	F.Print(format(L["Debug scope '%s': %s"], label, now and L["ON"] or L["OFF"]))
	return now
end

function Debug.ListScopes()
	F.Print(F.Colorize(L["Debug scopes"] .. ":", "brand"))
	for _, key in ipairs(SortedScopeKeys()) do
		local def = scopes[key]
		local flags = {}
		if session[key] or session.__all then
			tinsert(flags, L["session"])
		end
		if ns.global and ns.global.debug and ns.global.debug.scopes and (ns.global.debug.scopes[key] or ns.global.debug.scopes.__all) then
			tinsert(flags, L["saved"])
		end
		local state = #flags > 0 and tconcat(flags, "+") or L["off"]
		local modState = ""
		if def.module and def.module.IsEnabled then
			modState = format(" | module:%s", def.module:IsEnabled() and L["Enabled"] or L["Disabled"])
		end
		F.Print(format("  %s (%s) — %s%s", def.title, key, state, modState))
	end
end

-- `lines` nil → print to chat; otherwise append plain-text lines for export.
local function RunExpectations(def, lines)
	if not def or not def.expectations or #def.expectations == 0 then
		return 0, 0
	end
	local passed, failed = 0, 0
	for i = 1, #def.expectations do
		local exp = def.expectations[i]
		local ok, result = pcall(exp.test)
		local status, detail
		if not ok then
			failed = failed + 1
			status = "FAIL"
			detail = SafeStr(result)
		elseif result then
			passed = passed + 1
			status = "PASS"
		else
			failed = failed + 1
			status = "FAIL"
			detail = exp.detail and (type(exp.detail) == "function" and exp.detail() or exp.detail) or ""
		end
		if lines then
			local line = format("  [%s] %s", status, exp.name or ("#" .. i))
			if status == "FAIL" and detail and detail ~= "" then
				line = line .. " — " .. detail
			end
			lines[#lines + 1] = line
		elseif status == "PASS" then
			F.Print(F.Colorize(format("  [PASS] %s", exp.name or ("#" .. i)), "green"))
		else
			F.Print(F.Colorize(format("  [FAIL] %s%s", exp.name or ("#" .. i), detail and detail ~= "" and (" — " .. detail) or ""), "red"))
		end
	end
	return passed, failed
end

function Debug.DumpScope(scope)
	local key = ScopeKey(scope)
	local def = scopes[key]
	if not def then
		F.Print(F.Colorize(format(L["Unknown debug scope '%s'."], scope or ""), "red"))
		return false
	end

	F.Print(F.Colorize(format("--- %s (%s) ---", def.title, key), "brand"))
	if def.module and def.module.IsEnabled then
		F.Print(format("  module enabled: %s", def.module:IsEnabled() and "yes" or "no"))
	end
	local passed, failed = RunExpectations(def)
	if def.dump then
		def.dump()
	end
	if def.expectations then
		F.Print(format("  expectations: %d pass, %d fail", passed, failed))
	end
	return failed == 0
end

function Debug.DumpAll()
	Debug.PrintEnvironment()
	local anyFail = false
	for _, key in ipairs(SortedScopeKeys()) do
		if not Debug.DumpScope(key) then
			anyFail = true
		end
	end
	return not anyFail
end

function Debug.PrintEnvironment()
	local _, _, _, interface = GetBuildInfo()
	local w, h = GetPhysicalScreenSize()
	F.Print(F.Colorize(L["Debug environment"] .. ":", "brand"))
	F.Print(format("  addon: %s | interface: %s", ns.version or "?", interface or "?"))
	F.Print(format("  zone: %s | combat: %s | lockdown: %s", SafeStr(GetZoneText()), UnitAffectingCombat("player") and "yes" or "no", InCombatLockdown() and "yes" or "no"))
	F.Print(format("  screen: %dx%d | UIParent scale: %s | C.Mult: %s", w or 0, h or 0, SafeStr(UIParent:GetScale()), SafeStr(C.Mult)))
	F.Print(format("  useUiScale: %s | uiScale CVar: %s", SafeStr(GetCVar("useUiScale")), SafeStr(GetCVar("uiScale"))))
end

function Debug.PrintLog(count)
	count = tonumber(count) or 30
	if count < 1 then
		count = 1
	end
	local start = math_max(1, #log - count + 1)
	F.Print(F.Colorize(format(L["Debug log (last %d of %d)"] .. ":", count, #log), "brand"))
	for i = start, #log do
		local e = log[i]
		F.Print(format("  %s [%s][%s] %s", e.t, e.scope, e.level, e.text))
	end
end

--- Full copy-paste report for bug reports / AI triage.
function Debug.Export()
	local lines = {}
	local function add(line)
		lines[#lines + 1] = line
	end

	add("===== NexEnhance Debug Export =====")
	add(format("generated: %s", date("%Y-%m-%d %H:%M:%S")))
	local _, _, _, interface = GetBuildInfo()
	local w, h = GetPhysicalScreenSize()
	add(format("addon: %s | interface: %s", ns.version or "?", interface or "?"))
	add(format("zone: %s | combat: %s | lockdown: %s", SafeStr(GetZoneText()), UnitAffectingCombat("player") and "yes" or "no", InCombatLockdown() and "yes" or "no"))
	add(format("screen: %dx%d | UIParent: %s | C.Mult: %s", w or 0, h or 0, SafeStr(UIParent:GetScale()), SafeStr(C.Mult)))
	add(format("useUiScale: %s | uiScale: %s", SafeStr(GetCVar("useUiScale")), SafeStr(GetCVar("uiScale"))))
	add("")

	local scopeKeys = SortedScopeKeys()
	add(format("-- scopes (%d registered) --", #scopeKeys))
	for _, key in ipairs(scopeKeys) do
		local def = scopes[key]
		local flags = {}
		if IsScopeEnabled(key) then
			tinsert(flags, "on")
		end
		if def.module and def.module.IsEnabled then
			tinsert(flags, def.module:IsEnabled() and "module:enabled" or "module:disabled")
		end
		local suffix = #flags > 0 and (" [" .. tconcat(flags, ", ") .. "]") or ""
		add(format("  %s (%s)%s", def.title, key, suffix))
	end
	add("")

	local totalPass, totalFail = 0, 0
	for _, key in ipairs(scopeKeys) do
		local def = scopes[key]
		local hasExpect = def.expectations and #def.expectations > 0
		local hasDump = def.dump ~= nil
		if not hasExpect and not hasDump then
			-- Skip scopes with nothing to report (e.g. quickquest trace-only).
		else
			add(format("-- %s (%s) --", def.title, key))
			if def.module and def.module.IsEnabled then
				add(format("  module enabled: %s", def.module:IsEnabled() and "yes" or "no"))
			end
			if hasExpect then
				local passed, failed = RunExpectations(def, lines)
				totalPass = totalPass + passed
				totalFail = totalFail + failed
			end
			if hasDump then
				local dumpLines = CollectDumpLines(def)
				for i = 1, #dumpLines do
					add(dumpLines[i])
				end
			end
			add("")
		end
	end

	add(format("-- summary: %d pass, %d fail --", totalPass, totalFail))
	add("")

	add(format("-- log (last %d) --", math.min(40, #log)))
	local start = math_max(1, #log - 39)
	for i = start, #log do
		local e = log[i]
		add(format("  %s [%s][%s] %s", e.t, e.scope, e.level, e.text))
	end
	add("===== end =====")

	for i = 1, #lines do
		F.Print(lines[i])
	end
end

function Debug.HandleSlash(rest)
	rest = rest or ""
	local cmd, arg, extra = rest:match("^(%S*)%s*(%S*)%s*(.*)$")
	cmd = (cmd or ""):lower()
	arg = (arg or ""):lower()
	extra = (extra or ""):lower()

	if cmd == "" or cmd == "help" then
		F.Print(F.Colorize(L["Debug commands"] .. ":", "brand"))
		F.Print("  /nex debug list")
		F.Print("  /nex debug on|off|toggle <scope|all> [persist]")
		F.Print("  /nex debug dump [scope|all]")
		F.Print("  /nex debug log [count]")
		F.Print("  /nex debug export")
		F.Print("  /nex debug record on|off  -", L["Always record log ring buffer"])
		return
	end

	if cmd == "list" then
		Debug.ListScopes()
		return
	end

	if cmd == "on" or cmd == "off" or cmd == "toggle" then
		if arg == "" then
			F.Print(L["Usage"] .. ": /nex debug " .. cmd .. " <scope|all> [persist]")
			return
		end
		local persist = extra == "persist" or arg == "persist"
		if arg == "persist" then
			F.Print(L["Usage"] .. ": /nex debug " .. cmd .. " <scope|all> [persist]")
			return
		end
		if cmd == "toggle" then
			Debug.ToggleScope(arg, persist)
		else
			Debug.SetScope(arg, cmd == "on", persist)
			local def = scopes[ScopeKey(arg == "all" and "__all" or arg)]
			local label = def and def.title or arg
			F.Print(format(L["Debug scope '%s': %s"], label, cmd == "on" and L["ON"] or L["OFF"]))
		end
		return
	end

	if cmd == "dump" then
		if arg == "" or arg == "all" then
			Debug.PrintEnvironment()
			if arg == "all" then
				Debug.DumpAll()
			else
				F.Print(L["Usage"] .. ": /nex debug dump <scope|all>")
			end
		else
			Debug.PrintEnvironment()
			Debug.DumpScope(arg)
		end
		return
	end

	if cmd == "log" then
		Debug.PrintLog(arg ~= "" and arg or 30)
		return
	end

	if cmd == "export" then
		Debug.Export()
		return
	end

	if cmd == "record" then
		if not ns.global then
			return
		end
		ns.global.debug = ns.global.debug or {}
		ns.global.debug.recordAll = (arg == "on")
		F.Print(format(L["Debug recordAll: %s"], ns.global.debug.recordAll and L["ON"] or L["OFF"]))
		return
	end

	Debug.HandleSlash("help")
end

-- Thin global aliases used by existing slash handlers.
function ns:DumpUIScaleDebug()
	Debug.DumpScope("uiscale")
end

function ns:ApplyUIScaleNow()
	local mod = ns:GetModule("UIScale")
	if mod and mod.ForceApply then
		mod:ForceApply()
	end
end
