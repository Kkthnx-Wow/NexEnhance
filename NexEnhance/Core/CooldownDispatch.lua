--[[
	NexEnhance - Cooldown dispatch
	-------------------------------------------------------------------------
	One shared listener for spell and bag cooldown events (EllesmereUI-style
	central dispatcher). Action-bar modules subscribe instead of each registering
	SPELL_UPDATE_COOLDOWN / BAG_UPDATE_COOLDOWN on the module bus.
--]]

local _, ns = ...

local CreateFrame = CreateFrame

local EVENT_SPELL = "SPELL_UPDATE_COOLDOWN"
local EVENT_BAG = "BAG_UPDATE_COOLDOWN"

local listeners = {}
local listenerN = 0
local dispatchFrame

local function Dispatch(event)
	for i = 1, listenerN do
		local entry = listeners[i]
		if entry and (entry.event == event or entry.event == nil) then
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
--- `eventFilter` — nil (both), EVENT_SPELL, or EVENT_BAG.
--- Returns an id for `UnregisterCooldownDispatchCallback`.
function ns:RegisterCooldownDispatchCallback(fn, eventFilter)
	if type(fn) ~= "function" then
		return
	end
	EnsureDispatchFrame()
	listenerN = listenerN + 1
	listeners[listenerN] = { fn = fn, event = eventFilter }
	return listenerN
end

function ns:UnregisterCooldownDispatchCallback(id)
	if id and listeners[id] then
		listeners[id] = nil
	end
end
