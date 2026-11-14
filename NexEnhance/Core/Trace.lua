--[[
	NexEnhance - Trace
	-------------------------------------------------------------------------
	Hook attribution for the profiler (Core/Profiler.lua).

	A hooksecurefunc callback cannot be wrapped after the fact, and the client
	gives no way to ask which addon file a callback came from. So modules reach
	hooksecurefunc and TooltipDataProcessor through `ns.hooksecurefunc` and
	`ns.TooltipDataProcessor`, and this file decides what those are.

	  * Normal play: they ARE the real client functions. No wrapper, no extra
	    call, no behaviour change.
	  * Trace mode (`## X-PerfTrace: 1` in the TOC, then /reload): each callback
	    is wrapped once at registration. The wrapper is a straight pass-through
	    until `/nex perf start` runs, then it times the call under a label made
	    from the registration site, for example "Tooltip/TooltipID.lua:198 post Spell".

	The flag lives in the TOC because saved variables are not readable yet while
	the first files run, and hooks are registered during file load.
--]]

local addonName, ns = ...

local traceOn = C_AddOns.GetAddOnMetadata(addonName, "X-PerfTrace") == "1"
ns.traceEnabled = traceOn

if not traceOn then
	ns.hooksecurefunc = hooksecurefunc
	ns.TooltipDataProcessor = TooltipDataProcessor
	return
end

local type = type
local format = string.format
local strmatch = string.match
local debugstack = debugstack
local realHook = hooksecurefunc
local realProcessor = TooltipDataProcessor

-- "Modules/Tooltip/TooltipID.lua:198" for whoever called our shim. Level 1 is
-- this function, 2 is Wrap, 3 is the shim, 4 is the addon code that registered
-- the hook.
local function Site()
	local stack = debugstack(4, 1, 0)
	local path, line = strmatch(stack or "", "NexEnhance/([%w_/%.%-]-%.lua)%]?:(%d+)")
	if not path then
		return "?", "?"
	end
	local short = path:gsub("^Modules/", ""):gsub("^Core/", "")
	local base = strmatch(path, "([%w_%-]+)%.lua$") or path
	return format("%s:%s", short, line), base
end

local function Wrap(fn, what)
	if type(fn) ~= "function" then
		return fn
	end
	local site, module = Site()
	local label = format("%s %s", site, what)
	return function(...)
		local profiler = ns.Profiler
		if not (profiler and profiler:IsActive()) then
			return fn(...)
		end
		return profiler:Time(label, module, fn, ...)
	end
end

-- hooksecurefunc("Name", fn) and hooksecurefunc(table, "Name", fn)
ns.hooksecurefunc = function(a, b, c)
	if type(a) == "table" then
		return realHook(a, b, Wrap(c, "hook " .. tostring(b)))
	end
	return realHook(a, Wrap(b, "hook " .. tostring(a)))
end

-- Everything the real processor has stays reachable, only the registration
-- calls are intercepted.
local processor = setmetatable({}, { __index = realProcessor })
ns.TooltipDataProcessor = processor

if realProcessor then
	if realProcessor.AddTooltipPostCall then
		processor.AddTooltipPostCall = function(dataType, fn, ...)
			return realProcessor.AddTooltipPostCall(dataType, Wrap(fn, "post " .. tostring(dataType)), ...)
		end
	end
	if realProcessor.AddLinePreCall then
		processor.AddLinePreCall = function(lineType, fn, ...)
			return realProcessor.AddLinePreCall(lineType, Wrap(fn, "line " .. tostring(lineType)), ...)
		end
	end
end
