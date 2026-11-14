--[[
	NexEnhance - Profiler
	-------------------------------------------------------------------------
	A profiling mode for NexEnhance itself. Nothing in the shipped code paths is
	instrumented. Start() swaps timing wrappers onto the functions that matter
	and Stop() puts the originals back, so the cost while profiling is off is
	exactly zero.

	What it answers
	  * Which module and which event handler cost time, how often they ran, how
	    many bytes they allocated. Self time (children subtracted) and total.
	  * How much of the addon's real cost the probes explain. The client's own
	    C_AddOnProfiler gives the per-addon total, so the gap is work the probes
	    cannot see (hooksecurefunc callbacks, OnUpdate scripts, local functions).

	Usage
	  /nex perf start [seconds] [deep]   install probes, optionally stop after N seconds
	  /nex perf stop                     remove probes and print the report
	  /nex perf report                   print the current numbers without stopping
	  /nex perf reset                    zero the counters
	  /nex perf stack <name>             where the slowest call of a probe came from
	  /nex perf mem [gc]                 memory (gc runs a full collect)
	  /nex perf native                   the client profiler, NexEnhance vs all addons
	  /nex perf sources                  which measurement sources work on this client

	Everything is also written to NexEnhanceDB.global.perf so a report can be
	read from disk after /reload.

	Accuracy notes
	  * debugprofilestop is a wall clock. A frame hitch while a probe is open is
	    charged to it. Compare peaks with averages before trusting one number.
	  * alloc is the sum of positive collectgarbage("count") deltas, so it is a
	    lower bound (a GC step inside the call hides some of it).
	  * Probes only see calls made through a table. A local alias captured at file
	    scope bypasses a probe, which is why event handlers are timed at the
	    dispatcher instead.
--]]

local _, ns = ...
local F = ns.F

local format = string.format
local sort = table.sort
local wipe = wipe
local type = type
local pairs = pairs
local pcall = pcall
local InCombatLockdown = InCombatLockdown
local rawget = rawget
local tostring = tostring
local tonumber = tonumber
local math_max = math.max
local math_min = math.min
local collectgarbage = collectgarbage
local debugprofilestop = debugprofilestop
local debugstack = debugstack
local GetTimePreciseSec = GetTimePreciseSec
local C_Timer = C_Timer

local Profiler = {}
ns.Profiler = Profiler

local MAX_REPORT_ROWS = 14
local MAX_REPORT_MODULES = 10
local MAX_REPORT_EVENTS = 8
local MAX_PERSISTED_ROWS = 120
local SLOW_MS = 1

-- ns keys that must never be wrapped. They are the profiler itself, the event
-- plumbing the dispatcher probe replaces, and anything compared by identity.
local SKIP_KEYS = {
	RegisterEvent = true,
	RegisterUnitEvent = true,
	UnregisterEvent = true,
	UnregisterModuleEventHandles = true,
	NewModule = true,
	GetModule = true,
	RegisterAddonModule = true,
}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local probes = {} -- label -> record
local patched = {} -- { tbl, key, orig, wrapper }
local patchedKeys = setmetatable({}, { __mode = "k" }) -- tbl -> { key = true }
local active = false
local startedAt
local runGen = 0 -- invalidates a pending auto-stop when profiling restarts
local nativeAtStart -- C_AddOnProfiler snapshot taken when probes were installed

-- Call stack bookkeeping so a probe can subtract the time spent in probes it
-- called. childMs[d] collects the inclusive time of every probe closed at d+1.
local depth = 0
local childMs = {}

local eventFrame, origOnEvent, eventWrapper
local owners = {} -- event wrapper function -> module name
local ownersMissing = {} -- wrapper functions known to have no owner
local ownerLabelCache = {} -- "owner" .. event -> record, avoids per-event string builds

local function Print(msg)
	F.Print(msg)
end

local function GetProbe(label, module)
	local p = probes[label]
	if not p then
		p = { label = label, module = module, calls = 0, total = 0, self = 0, peak = 0, slow = 0, alloc = 0 }
		probes[label] = p
	end
	return p
end

local function Now()
	return GetTimePreciseSec and GetTimePreciseSec() or GetTime()
end

local function Elapsed()
	if not startedAt then
		return 0
	end
	return Now() - startedAt
end

-- ---------------------------------------------------------------------------
-- Probe wrapper
-- ---------------------------------------------------------------------------
local function Account(p, myDepth, elapsed, allocKB)
	local child = childMs[myDepth] or 0
	childMs[myDepth] = nil
	depth = myDepth - 1
	if depth > 0 then
		childMs[depth] = (childMs[depth] or 0) + elapsed
	end
	local own = elapsed - child
	if own < 0 then
		own = 0
	end
	p.calls = p.calls + 1
	p.total = p.total + elapsed
	p.self = p.self + own
	if elapsed > p.peak then
		p.peak = elapsed
		-- Who made the slowest call so far. Only captured on a new slow peak so the
		-- cost stays off the common path.
		if elapsed >= SLOW_MS and debugstack then
			p.peakStack = debugstack(3, 20, 0)
		end
	end
	if elapsed >= SLOW_MS then
		p.slow = p.slow + 1
	end
	if allocKB > 0 then
		p.alloc = p.alloc + allocKB
	end
end

local function Finish(p, myDepth, kb0, t0, ...)
	local elapsed = debugprofilestop() - t0
	Account(p, myDepth, elapsed, collectgarbage("count") - kb0)
	return ...
end

local function MakeWrapper(p, orig)
	return function(...)
		if not active then
			return orig(...)
		end
		local myDepth = depth + 1
		depth = myDepth
		childMs[myDepth] = 0
		-- Arguments evaluate left to right, so the clock reads happen before orig.
		return Finish(p, myDepth, collectgarbage("count"), debugprofilestop(), orig(...))
	end
end

--- Put a timing wrapper on tbl[key]. Returns true when a probe was installed.
--- Public so a module or plugin can add its own probe point.
function Profiler:Track(tbl, key, label, module)
	if type(tbl) ~= "table" then
		return false
	end
	local orig = rawget(tbl, key)
	if type(orig) ~= "function" then
		return false
	end
	local keys = patchedKeys[tbl]
	if keys and keys[key] then
		return false
	end
	local wrapper = MakeWrapper(GetProbe(label or key, module), orig)
	tbl[key] = wrapper
	patched[#patched + 1] = { tbl, key, orig, wrapper }
	if not keys then
		keys = {}
		patchedKeys[tbl] = keys
	end
	keys[key] = true
	return true
end

--- Time one call under `label`. Used by Core/Trace.lua for hook callbacks, which
--- cannot be wrapped from outside. Varargs and returns pass straight through.
function Profiler:Time(label, module, fn, ...)
	local p = probes[label] or GetProbe(label, module)
	local myDepth = depth + 1
	depth = myDepth
	childMs[myDepth] = 0
	return Finish(p, myDepth, collectgarbage("count"), debugprofilestop(), fn(...))
end

--- Wrap every own function field of `tbl`. Returns how many probes were added.
function Profiler:TrackAll(tbl, prefix, module, skip)
	if type(tbl) ~= "table" then
		return 0
	end
	-- Collect first, then wrap. Assigning to an existing key during pairs() is
	-- allowed, but a separate pass keeps the iteration obviously safe.
	local keys = {}
	for key, value in pairs(tbl) do
		if type(key) == "string" and type(value) == "function" and not (skip and skip[key]) then
			keys[#keys + 1] = key
		end
	end
	local n = 0
	for i = 1, #keys do
		if self:Track(tbl, keys[i], prefix .. keys[i], module) then
			n = n + 1
		end
	end
	return n
end

-- ---------------------------------------------------------------------------
-- Targets
-- ---------------------------------------------------------------------------
local function InstallTargets(deep)
	local n = 0
	local list = ns.modules
	for i = 1, #list do
		local module = list[i]
		-- Module methods only. Event handler wrappers live in _eventHandles, not as
		-- own function fields, so they are not double wrapped here.
		n = n + Profiler:TrackAll(module, module.name .. ".", module.name)
	end
	n = n + Profiler:TrackAll(ns, "ns:", "(core)", SKIP_KEYS)
	if deep then
		n = n + Profiler:TrackAll(ns.F, "F.", "(core)")
	end
	return n
end

-- ---------------------------------------------------------------------------
-- Event dispatcher probe
--   Engine hands every game event to one frame, which walks an array of
--   wrappers. Timing each wrapper there attributes cost to the module that
--   registered it without touching a single handler.
-- ---------------------------------------------------------------------------
local function BuildOwners()
	wipe(owners)
	local list = ns.modules
	for i = 1, #list do
		local module = list[i]
		local handles = rawget(module, "_eventHandles")
		if handles then
			for _, records in pairs(handles) do
				for j = 1, #records do
					local record = records[j]
					if record and record.wrapper then
						owners[record.wrapper] = module.name
					end
				end
			end
		end
	end
end

local function EventProbe(callback, event)
	local owner = owners[callback]
	if not owner and not ownersMissing[callback] then
		-- A module registered after Start. Rebuild once, then give up on this one.
		BuildOwners()
		owner = owners[callback]
		if not owner then
			ownersMissing[callback] = true
		end
	end
	owner = owner or "(core)"
	local byEvent = ownerLabelCache[owner]
	if not byEvent then
		byEvent = {}
		ownerLabelCache[owner] = byEvent
	end
	local p = byEvent[event]
	if not p then
		p = GetProbe(owner .. " @" .. event, owner)
		p.isEvent = true
		byEvent[event] = p
	end
	return p
end

local function InstallEventProbe()
	local callbacksByEvent = ns._eventCallbacks
	eventFrame = _G.NexEnhanceEventFrame
	if not (callbacksByEvent and eventFrame and eventFrame.GetScript) then
		return false
	end
	origOnEvent = eventFrame:GetScript("OnEvent")
	if type(origOnEvent) ~= "function" then
		origOnEvent = nil
		return false
	end
	BuildOwners()
	local orig = origOnEvent
	eventWrapper = function(self, event, ...)
		if not active then
			return orig(self, event, ...)
		end
		local callbacks = callbacksByEvent[event]
		if not callbacks then
			return
		end
		-- Same walk as Engine: tombstoned slots are false, never removed mid-fire.
		for i = 1, #callbacks do
			local callback = callbacks[i]
			if callback then
				local p = EventProbe(callback, event)
				local myDepth = depth + 1
				depth = myDepth
				childMs[myDepth] = 0
				Finish(p, myDepth, collectgarbage("count"), debugprofilestop(), callback(event, ...))
			end
		end
	end
	eventFrame:SetScript("OnEvent", eventWrapper)
	return true
end

local function RemoveEventProbe()
	if eventFrame and eventWrapper and eventFrame:GetScript("OnEvent") == eventWrapper then
		eventFrame:SetScript("OnEvent", origOnEvent)
	end
	eventFrame, origOnEvent, eventWrapper = nil, nil, nil
	wipe(owners)
	wipe(ownersMissing)
end

-- ---------------------------------------------------------------------------
-- Client profiler (C_AddOnProfiler)
-- ---------------------------------------------------------------------------
local function Try(fn, ...)
	local ok, result = pcall(fn, ...)
	if ok then
		return result
	end
	return nil, tostring(result)
end

local NATIVE_METRICS = {
	{ "SessionAverageTime", "session avg" },
	{ "RecentAverageTime", "recent avg" },
	{ "EncounterAverageTime", "encounter avg" },
	{ "LastTime", "last tick" },
	{ "PeakTime", "peak" },
	{ "CountTimeOver1Ms", ">1ms ticks" },
	{ "CountTimeOver5Ms", ">5ms ticks" },
	{ "CountTimeOver10Ms", ">10ms ticks" },
	{ "CountTimeOver50Ms", ">50ms ticks" },
	{ "CountTimeOver100Ms", ">100ms ticks" },
}

--- Read C_AddOnProfiler for this addon and for everything combined. Every call
--- is guarded because a client may not ship the API or may stub it.
function Profiler:ReadNative()
	local api = _G.C_AddOnProfiler
	local enum = _G.Enum and _G.Enum.AddOnProfilerMetric
	if not (api and api.GetAddOnMetric and enum) then
		return nil, "C_AddOnProfiler is not available on this client"
	end
	local out = { addon = {}, overall = {}, top = {} }
	if api.IsEnabled then
		out.enabled = Try(api.IsEnabled)
	end
	local anyValue = false
	for i = 1, #NATIVE_METRICS do
		local field = NATIVE_METRICS[i][1]
		local metric = enum[field]
		if metric ~= nil then
			local mine = Try(api.GetAddOnMetric, ns.name, metric)
			if type(mine) == "number" then
				out.addon[field] = mine
				if mine ~= 0 then
					anyValue = true
				end
			end
			if api.GetOverallMetric then
				local all = Try(api.GetOverallMetric, metric)
				if type(all) == "number" then
					out.overall[field] = all
					if all ~= 0 then
						anyValue = true
					end
				end
			end
		end
	end
	if api.GetTopKAddOnsForMetric and enum.RecentAverageTime ~= nil then
		local top = Try(api.GetTopKAddOnsForMetric, enum.RecentAverageTime, 5)
		if type(top) == "table" then
			for i = 1, #top do
				local row = top[i]
				if type(row) == "table" and type(row.addOnName) == "string" then
					out.top[#out.top + 1] = { name = row.addOnName, value = row.metricValue }
				end
			end
		end
	end
	out.allZero = not anyValue
	return out
end

-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------
local store = {}
local overheadUs -- cost of one probe wrapper, measured at Start

local function Snapshot()
	local rows = {}
	local seconds = math_max(Elapsed(), 0.001)
	for _, p in pairs(probes) do
		if p.calls > 0 then
			rows[#rows + 1] = {
				label = p.label,
				module = p.module,
				isEvent = p.isEvent or nil,
				calls = p.calls,
				totalMs = p.total,
				selfMs = p.self,
				avgMs = p.total / p.calls,
				peakMs = p.peak,
				slow = p.slow,
				allocKB = p.alloc,
				callsPerSec = p.calls / seconds,
				peakStack = p.peakStack,
			}
		end
	end
	sort(rows, function(a, b)
		if a.selfMs ~= b.selfMs then
			return a.selfMs > b.selfMs
		end
		return a.label < b.label
	end)
	return rows
end

-- Self time summed per module. Probes nest, and self time already excludes the
-- probes a call made, so the sum is each module's own cost with no double count.
local function ModuleRollup(rows)
	local byModule = {}
	local list = {}
	for i = 1, #rows do
		local r = rows[i]
		local name = r.module or "?"
		local m = byModule[name]
		if not m then
			m = { name = name, selfMs = 0, calls = 0, allocKB = 0, peakMs = 0 }
			byModule[name] = m
			list[#list + 1] = m
		end
		m.selfMs = m.selfMs + r.selfMs
		m.calls = m.calls + r.calls
		m.allocKB = m.allocKB + r.allocKB
		if r.peakMs > m.peakMs then
			m.peakMs = r.peakMs
		end
	end
	sort(list, function(a, b)
		if a.selfMs ~= b.selfMs then
			return a.selfMs > b.selfMs
		end
		return a.name < b.name
	end)
	return list
end

local function PrintRow(row)
	Print(format("  %-42s %6d calls %6.1f/s  self %8.2f  total %8.2f  avg %6.3f  peak %7.2f  >%dms %d  alloc %.0fK", row.label,
		row.calls, row.callsPerSec, row.selfMs, row.totalMs, row.avgMs, row.peakMs, SLOW_MS, row.slow, row.allocKB))
end

local function PersistedRows(rows)
	if #rows <= MAX_PERSISTED_ROWS then
		return rows
	end
	local kept = {}
	for i = 1, MAX_PERSISTED_ROWS do
		kept[i] = rows[i]
	end
	return kept
end

local function Persist()
	local global = ns.global
	if not global then
		return
	end
	local _, build, _, toc = GetBuildInfo()
	global.perf = {
		version = 1,
		stamp = date and date("%Y-%m-%d %H:%M:%S") or nil,
		addonVersion = ns.version,
		build = build,
		interface = toc,
		seconds = Elapsed(),
		probeOverheadUs = overheadUs,
		probes = store.probes,
		modules = store.modules,
		native = store.native,
		nativeAtStart = nativeAtStart,
		memory = store.memory,
		load = store.load,
		bench = store.bench,
		sources = store.sources,
	}
end

function Profiler:GetStatus()
	local count = 0
	for _, p in pairs(probes) do
		if p.calls > 0 then
			count = count + 1
		end
	end
	return { active = active, probeCount = count, seconds = Elapsed(), overheadUs = overheadUs }
end

function Profiler:Report(quiet)
	local rows = Snapshot()
	local funcs, events = {}, {}
	for i = 1, #rows do
		if rows[i].isEvent then
			events[#events + 1] = rows[i]
		else
			funcs[#funcs + 1] = rows[i]
		end
	end
	local modules = ModuleRollup(rows)
	local seconds = math_max(Elapsed(), 0.001)
	local totalSelf = 0
	for i = 1, #modules do
		totalSelf = totalSelf + modules[i].selfMs
	end

	-- What the client says the addon cost over the same span, for the gap line.
	local nativeNow = self:ReadNative()
	store.native = nativeNow
	store.probes = PersistedRows(rows)
	store.modules = modules
	store.totalSelfMs = totalSelf
	Persist()

	if quiet then
		return rows
	end
	if #rows == 0 then
		Print("Profiler: nothing recorded yet. Use /nex perf start, play for a bit, then /nex perf report.")
		return rows
	end
	Print(format("Profiler: %d probes over %.1fs, %s. Self time in ms, probes explain %.1f ms (%.2f ms/s).", #rows,
		seconds, active and "running" or "stopped", totalSelf, totalSelf / seconds))
	if overheadUs then
		Print(format("  Each probe adds about %.2f us per call, already inside these numbers. Very hot, very short functions read high.", overheadUs))
	end
	Print("  By module:")
	for i = 1, math_min(#modules, MAX_REPORT_MODULES) do
		local m = modules[i]
		Print(format("    %-26s self %8.2f ms  %6d calls  peak %7.2f  alloc %.0fK", m.name, m.selfMs, m.calls, m.peakMs, m.allocKB))
	end
	Print("  By function:")
	for i = 1, math_min(#funcs, MAX_REPORT_ROWS) do
		PrintRow(funcs[i])
	end
	if #events > 0 then
		Print("  By event handler:")
		for i = 1, math_min(#events, MAX_REPORT_EVENTS) do
			PrintRow(events[i])
		end
	end
	if nativeNow and nativeNow.addon.RecentAverageTime then
		Print(format("  Client says NexEnhance recent avg %.3f ms/tick, peak %.2f ms (probes are wall time inside calls, not per tick).",
			nativeNow.addon.RecentAverageTime or 0, nativeNow.addon.PeakTime or 0))
	end
	Print("Slowest call stack for a probe: /nex perf stack <name>. Full list in NexEnhanceDB.global.perf.")
	return rows
end

-- ---------------------------------------------------------------------------
-- Start / stop
-- ---------------------------------------------------------------------------
function Profiler:IsActive()
	return active
end

function Profiler:Reset()
	-- Zero the records in place. Every installed wrapper holds its own record, so
	-- emptying the map would leave them counting into tables nothing reads.
	for _, p in pairs(probes) do
		p.calls, p.total, p.self, p.peak, p.slow, p.alloc = 0, 0, 0, 0, 0, 0
		p.peakStack = nil
	end
	depth = 0
	wipe(childMs)
	startedAt = Now()
end

--- Price one wrapper against a bare call so the report can say how much of a
--- very hot probe is the probe itself.
local function Calibrate()
	local runs = 2000
	local noop = function() end
	local wrapped = MakeWrapper({ label = "calibrate", calls = 0, total = 0, self = 0, peak = 0, slow = 0, alloc = 0 }, noop)
	local t0 = debugprofilestop()
	for _ = 1, runs do
		noop()
	end
	local bare = debugprofilestop() - t0
	t0 = debugprofilestop()
	for _ = 1, runs do
		wrapped()
	end
	local with = debugprofilestop() - t0
	depth = 0
	wipe(childMs)
	overheadUs = math_max(with - bare, 0) / runs * 1000
end

function Profiler:Start(seconds, deep)
	if active then
		Print("Profiler is already running. /nex perf report, /nex perf stop.")
		return
	end
	if not debugprofilestop then
		Print("debugprofilestop is not available on this client, probes cannot run.")
		return
	end
	self:Reset()
	nativeAtStart = self:ReadNative()
	active = true
	Calibrate()
	local n = InstallTargets(deep)
	local events = InstallEventProbe()
	runGen = runGen + 1
	local gen = runGen
	Print(format("Profiler started: %d probes%s. Play normally, then /nex perf stop.", n, events and " + event timing" or ""))
	if seconds and seconds > 0 then
		C_Timer.After(seconds, function()
			if active and runGen == gen then
				self:Stop()
			end
		end)
	end
end

function Profiler:Stop(quiet)
	if not active then
		if not quiet then
			Print("Profiler is not running.")
		end
		return
	end
	active = false
	for i = #patched, 1, -1 do
		local p = patched[i]
		-- Only restore what is still our wrapper, never clobber a later change.
		if rawget(p[1], p[2]) == p[4] then
			p[1][p[2]] = p[3]
		end
		patched[i] = nil
	end
	wipe(patchedKeys)
	RemoveEventProbe()
	depth = 0
	wipe(childMs)
	self:Report(quiet)
end

-- ---------------------------------------------------------------------------
-- Native, sources, memory
-- ---------------------------------------------------------------------------
function Profiler:PrintNative()
	local data, err = self:ReadNative()
	if not data then
		Print(err .. ". Use /nex perf start instead.")
		return
	end
	store.native = data
	Persist()
	Print(format("Client profiler (C_AddOnProfiler)%s. Times in ms per tick.", data.enabled == false and ", reports itself disabled" or ""))
	for i = 1, #NATIVE_METRICS do
		local field, label = NATIVE_METRICS[i][1], NATIVE_METRICS[i][2]
		local mine, all = data.addon[field], data.overall[field]
		if mine ~= nil or all ~= nil then
			Print(format("  %-13s NexEnhance %9.3f    all addons %9.3f", label, mine or 0, all or 0))
		end
	end
	if #data.top > 0 then
		Print("  Heaviest by recent average:")
		for i = 1, #data.top do
			Print(format("    %d. %-28s %.3f", i, data.top[i].name, data.top[i].value or 0))
		end
	end
	if data.allZero then
		Print("  Every value is 0. Either nothing ran yet or this client stubs the API. Trust /nex perf start over this.")
	end
end

local function ResolveFn(name)
	local addons = _G.C_AddOns
	if addons and type(addons[name]) == "function" then
		return addons[name]
	end
	if type(_G[name]) == "function" then
		return _G[name]
	end
end

function Profiler:PrintSources()
	local sources = {}
	Print("Measurement sources on this client:")
	local native = self:ReadNative()
	sources.native = native and (native.allZero and "present, all zero" or "present, reporting") or "missing"
	Print("  C_AddOnProfiler        " .. sources.native)

	local cvar
	if _G.C_CVar and _G.C_CVar.GetCVar then
		cvar = Try(_G.C_CVar.GetCVar, "scriptProfile")
	end
	local getCpu = ResolveFn("GetAddOnCPUUsage")
	local updateCpu = ResolveFn("UpdateAddOnCPUUsage")
	local cpuValue
	if getCpu then
		if updateCpu then
			Try(updateCpu)
		end
		cpuValue = Try(getCpu, ns.name)
	end
	sources.legacyCpu = format("scriptProfile=%s, %s, NexEnhance=%s", tostring(cvar),
		getCpu and "GetAddOnCPUUsage present" or "no GetAddOnCPUUsage", tostring(cpuValue))
	Print("  Legacy CPU counters    " .. sources.legacyCpu)

	sources.memory = ResolveFn("GetAddOnMemoryUsage") and "GetAddOnMemoryUsage present" or "missing"
	Print("  Memory counters        " .. sources.memory)
	sources.probes = debugprofilestop and "debugprofilestop present" or "missing"
	Print("  Internal probes        " .. sources.probes .. " (/nex perf start)")
	store.sources = sources
	Persist()
end

function Profiler:Memory(runGC)
	local luaKB = collectgarbage("count")
	local getMem = ResolveFn("GetAddOnMemoryUsage")
	local updateMem = ResolveFn("UpdateAddOnMemoryUsage")

	local function AddonKB()
		if not getMem then
			return nil
		end
		if updateMem then
			Try(updateMem)
		end
		return Try(getMem, ns.name)
	end

	local mem = { luaKB = luaKB, addonKB = AddonKB() }
	if runGC then
		collectgarbage("collect")
		mem.luaKBAfterGC = collectgarbage("count")
		mem.addonKBAfterGC = AddonKB()
	end
	store.memory = mem
	Persist()

	Print(format("Memory: Lua heap %.0fK total%s.", luaKB, mem.addonKB and format(", NexEnhance %.0fK", mem.addonKB) or ""))
	if runGC then
		Print(format("  after full GC: Lua heap %.0fK%s (the drop was garbage, the rest is retained)", mem.luaKBAfterGC,
			mem.addonKBAfterGC and format(", NexEnhance %.0fK", mem.addonKBAfterGC) or ""))
	elseif getMem then
		Print("  Add 'gc' to run a full collect and split garbage from retained memory.")
	end
end

--- Startup cost per module, recorded by Engine around OnInitialize and OnEnable.
--- It covers only those calls, file parse time is not split out per module.
function Profiler:Load()
	local log = ns._loadLog
	if not log or #log == 0 then
		Print("No startup timings recorded.")
		return
	end
	local rows, totalMs, totalKB = {}, 0, 0
	for i = 1, #log, 4 do
		rows[#rows + 1] = { module = log[i], method = log[i + 1], ms = log[i + 2], kb = log[i + 3] }
		totalMs = totalMs + log[i + 2]
		totalKB = totalKB + log[i + 3]
	end
	sort(rows, function(a, b)
		return a.ms > b.ms
	end)
	store.load = { totalMs = totalMs, totalKB = totalKB, rows = {} }
	for i = 1, math_min(#rows, 40) do
		store.load.rows[i] = rows[i]
	end
	Persist()
	Print(format("Startup: %d lifecycle calls, %.1f ms and %.0fK in OnInitialize and OnEnable.", #rows, totalMs, totalKB))
	for i = 1, math_min(#rows, 12) do
		local r = rows[i]
		Print(format("  %-28s %-12s %8.2f ms  %8.0fK", r.module, r.method, r.ms, r.kb))
	end
end

-- ---------------------------------------------------------------------------
-- Bench
--   A module opts in with `module:PerfBench()`, returning a list of
--   { label, fn } pairs (and optionally `cleanup`). Each fn runs n times with
--   the clock and allocation counter around it, so a change can be compared
--   before and after without having to play for a while.
-- ---------------------------------------------------------------------------
local function Measure(label, n, fn)
	local times = {}
	local alloc = 0
	for i = 1, n do
		local kb0 = collectgarbage("count")
		local t0 = debugprofilestop()
		fn(i)
		times[i] = debugprofilestop() - t0
		local grown = collectgarbage("count") - kb0
		if grown > 0 then
			alloc = alloc + grown
		end
	end
	sort(times)
	local sum = 0
	for i = 1, n do
		sum = sum + times[i]
	end
	return {
		label = label,
		runs = n,
		minMs = times[1],
		medianMs = times[math.floor((n + 1) / 2)],
		avgMs = sum / n,
		maxMs = times[n],
		allocKBPerRun = alloc / n,
	}
end

function Profiler:Bench(n)
	if InCombatLockdown() then
		Print("Bench refused in combat.")
		return
	end
	n = math_max(1, math_min(tonumber(n) or 20, 200))
	local results = {}
	local list = ns.modules
	for i = 1, #list do
		local module = list[i]
		if type(rawget(module, "PerfBench")) == "function" then
			local cases = Try(module.PerfBench, module)
			if type(cases) == "table" then
				for j = 1, #cases do
					local case = cases[j]
					local result, err = Try(Measure, module.name .. ": " .. case[1], n, case[2])
					results[#results + 1] = result or { label = case[1], error = err }
				end
				if type(cases.cleanup) == "function" then
					Try(cases.cleanup)
				end
			end
		end
	end
	if #results == 0 then
		Print("Bench: no module offered a workload (the module may be off).")
		return
	end
	Print(format("Bench: %d runs per workload.", n))
	for i = 1, #results do
		local r = results[i]
		if r.runs then
			Print(format("  %-40s min %7.3f  median %7.3f  avg %7.3f  max %7.3f ms   %6.1fK/run", r.label, r.minMs,
				r.medianMs, r.avgMs, r.maxMs, r.allocKBPerRun))
		else
			Print("  " .. r.label .. " failed: " .. tostring(r.error))
		end
	end
	store.bench = { runs = n, results = results }
	Persist()
end

-- ---------------------------------------------------------------------------
-- Command
-- ---------------------------------------------------------------------------
function Profiler:PrintStack(name)
	name = (name or ""):lower()
	if name == "" then
		Print("Usage: /nex perf stack <part of a probe name>")
		return
	end
	local best
	for label, p in pairs(probes) do
		if label:lower():find(name, 1, true) and p.peakStack and (not best or p.peak > best.peak) then
			best = p
		end
	end
	if not best then
		Print("No slow call recorded for '" .. name .. "'. A stack is kept for calls over " .. SLOW_MS .. "ms.")
		return
	end
	Print(format("Slowest call of %s: %.3f ms. Called from:", best.label, best.peak))
	local lines = 0
	for line in best.peakStack:gmatch("[^\n]+") do
		Print("    " .. line)
		lines = lines + 1
		if lines >= 14 then
			break
		end
	end
end

local HELP = {
	"Performance profiler (/nex perf):",
	"  start [seconds] [deep] - install probes, optionally stop after N seconds, deep also times ns.F helpers",
	"  stop / report / reset",
	"  stack <name> - where the slowest call of a probe came from",
	"  bench [n] - fixed workloads that modules offer through PerfBench",
	"  load - startup cost per module (OnInitialize and OnEnable)",
	"  mem [gc] - memory, gc runs a full collect",
	"  native - the client's own profiler, NexEnhance vs all addons",
	"  sources - which measurement sources work on this client",
}

function Profiler:HandleCommand(value)
	local sub, arg = (value or ""):match("^(%S*)%s*(.-)$")
	sub = (sub or ""):lower()
	arg = arg or ""
	if sub == "start" then
		self:Start(tonumber(arg:match("%d+")), arg:lower():find("deep", 1, true) ~= nil)
	elseif sub == "stop" then
		self:Stop()
	elseif sub == "report" then
		self:Report()
	elseif sub == "stack" then
		self:PrintStack(arg)
	elseif sub == "reset" then
		self:Reset()
		Print("Profiler counters reset.")
	elseif sub == "bench" then
		self:Bench(tonumber(arg))
	elseif sub == "load" then
		self:Load()
	elseif sub == "native" then
		self:PrintNative()
	elseif sub == "mem" or sub == "memory" then
		self:Memory(arg:lower() == "gc")
	elseif sub == "sources" then
		self:PrintSources()
	else
		for i = 1, #HELP do
			Print(HELP[i])
		end
	end
end

-- A /reload or logout while probes are running would otherwise lose the whole
-- run, because the report is only written when it is built.
ns:RegisterEvent("PLAYER_LOGOUT", function()
	if active then
		Profiler:Stop(true)
	end
end)
