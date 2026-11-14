--[[
	NexEnhance - Cooldown dispatch
	-------------------------------------------------------------------------
	One shared listener for spell and bag cooldown events (EllesmereUI-style
	central dispatcher). Action-bar modules subscribe instead of each registering
	SPELL_UPDATE_COOLDOWN / BAG_UPDATE_COOLDOWN on the module bus.

	Subscriptions are kept in a dense array so Dispatch only walks live entries.
	Unregistering marks the entry dead and drops its closure; once dead entries
	outnumber live ones the array is rebuilt. This matters because a toggleable
	module (GCD bar, cursor ring) subscribes on every enable: with the old
	append-only list, each enable/disable cycle left one more hole for every
	SPELL_UPDATE_COOLDOWN to walk for the rest of the session.
--]]

local _, ns = ... -- luacheck: ignore 212

local CreateFrame = CreateFrame

local EVENT_SPELL = "SPELL_UPDATE_COOLDOWN"
local EVENT_BAG = "BAG_UPDATE_COOLDOWN"

-- id -> entry. Ids stay valid across compaction because the entry carries it.
local listeners = {}
local nextId = 0

-- Dense array of entries (live and dead); activeN bounds Dispatch.
local active = {}
local activeN = 0
local deadN = 0

local dispatchFrame

local function Compact()
	local write = 0
	for i = 1, activeN do
		local entry = active[i]
		if entry and not entry.dead then
			write = write + 1
			active[write] = entry
		end
	end
	for i = write + 1, activeN do
		active[i] = nil
	end
	activeN = write
	deadN = 0
end

local function Dispatch(event)
	for i = 1, activeN do
		local entry = active[i]
		if entry and not entry.dead and (entry.event == event or entry.event == nil) then
			entry.fn(event)
		end
	end
end

local function EnsureDispatchFrame()
	if dispatchFrame then
		return
	end
	dispatchFrame = CreateFrame("Frame")
	dispatchFrame:RegisterEvent(EVENT_SPELL)
	dispatchFrame:RegisterEvent(EVENT_BAG)
	dispatchFrame:SetScript("OnEvent", function(_, event)
		Dispatch(event)
	end)
end

--- Subscribe to cooldown refresh events.
--- `eventFilter` - nil (both), EVENT_SPELL, or EVENT_BAG.
--- Returns an id for `UnregisterCooldownDispatchCallback`.
function ns:RegisterCooldownDispatchCallback(fn, eventFilter)
	if type(fn) ~= "function" then
		return
	end
	EnsureDispatchFrame()
	nextId = nextId + 1
	local entry = { fn = fn, event = eventFilter, id = nextId }
	listeners[nextId] = entry
	activeN = activeN + 1
	active[activeN] = entry
	return nextId
end

function ns:UnregisterCooldownDispatchCallback(id)
	local entry = id and listeners[id]
	if not entry or entry.dead then
		return
	end
	entry.dead = true
	-- Drop the closure now: a disabled module must not stay reachable through
	-- the dispatcher for the rest of the session.
	entry.fn = nil
	listeners[id] = nil
	deadN = deadN + 1
	if deadN > activeN / 2 then
		Compact()
	end
end
