--[[
	NexEnhance - Zone-triggered registration
	-------------------------------------------------------------------------
	Plumber-style zone gating: register heavy map logic only while the player
	is in one of the configured map IDs (C_Map.GetBestMapForUnit).
--]]

local _, ns = ...

local C_Map = C_Map
local C_Timer = C_Timer
local GetBestMapForUnit = C_Map and C_Map.GetBestMapForUnit

--- Create a zone gate. `zoneSet` is `{ [mapID] = true, ... }`.
--- `onEnter` / `onLeave` run when crossing the boundary (not on first Enable
--- unless already in-zone — Enable calls Sync immediately).
--- Returns `{ Enable(), Disable(), IsActive(), Sync() }`.
function ns:CreateZoneTrigger(zoneSet, onEnter, onLeave)
	local active = false
	local enabled = false
	local evtHandles = {}

	local function MapInZone()
		if not GetBestMapForUnit then
			return false
		end
		local mapID = GetBestMapForUnit("player")
		return mapID and zoneSet[mapID] or false
	end

	local function Sync()
		local inZone = MapInZone()
		if inZone and not active then
			active = true
			if onEnter then
				onEnter()
			end
		elseif not inZone and active then
			active = false
			if onLeave then
				onLeave()
			end
		end
	end

	local function OnZoneEvent()
		if enabled then
			Sync()
		end
	end

	local function Enable()
		if enabled then
			return
		end
		enabled = true
		evtHandles[1] = { "ZONE_CHANGED_NEW_AREA", ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", OnZoneEvent) }
		evtHandles[2] = { "PLAYER_ENTERING_WORLD", ns:RegisterEvent("PLAYER_ENTERING_WORLD", OnZoneEvent) }
		Sync()
	end

	local function Disable()
		if not enabled then
			return
		end
		enabled = false
		if active then
			active = false
			if onLeave then
				onLeave()
			end
		end
		for i = 1, #evtHandles do
			local handle = evtHandles[i]
			ns:UnregisterEvent(handle[1], handle[2])
			evtHandles[i] = nil
		end
	end

	return {
		Enable = Enable,
		Disable = Disable,
		IsActive = function()
			return active
		end,
		Sync = Sync,
	}
end

--- Predicate-gated registration (Delve walk-in, scenario flags, etc.).
--- `opts.debounce` — seconds to wait after boundary events (APIs like
--- `IsPartyWalkIn` lag on `PLAYER_ENTERING_WORLD`). `opts.events` — extra
--- event names that should trigger a sync.
function ns:CreateStateTrigger(predicate, onEnter, onLeave, opts)
	opts = opts or {}
	local debounce = opts.debounce or 0
	local extraEvents = opts.events or {}
	local active = false
	local enabled = false
	local evtHandles = {}
	local debouncePending = false

	local function Sync()
		local want = predicate()
		if want and not active then
			active = true
			if onEnter then
				onEnter()
			end
		elseif not want and active then
			active = false
			if onLeave then
				onLeave()
			end
		end
	end

	local function RunSync()
		debouncePending = false
		if enabled then
			Sync()
		end
	end

	local function OnGateEvent()
		if not enabled then
			return
		end
		if debounce > 0 and C_Timer and C_Timer.After then
			if debouncePending then
				return
			end
			debouncePending = true
			C_Timer.After(debounce, RunSync)
			return
		end
		Sync()
	end

	local function Enable()
		if enabled then
			return
		end
		enabled = true
		evtHandles[#evtHandles + 1] = { "ZONE_CHANGED_NEW_AREA", ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", OnGateEvent) }
		evtHandles[#evtHandles + 1] = { "PLAYER_ENTERING_WORLD", ns:RegisterEvent("PLAYER_ENTERING_WORLD", OnGateEvent) }
		evtHandles[#evtHandles + 1] = { "PLAYER_MAP_CHANGED", ns:RegisterEvent("PLAYER_MAP_CHANGED", OnGateEvent) }
		for i = 1, #extraEvents do
			local ev = extraEvents[i]
			evtHandles[#evtHandles + 1] = { ev, ns:RegisterEvent(ev, OnGateEvent) }
		end
		OnGateEvent()
	end

	local function Disable()
		if not enabled then
			return
		end
		enabled = false
		debouncePending = false
		if active then
			active = false
			if onLeave then
				onLeave()
			end
		end
		for i = 1, #evtHandles do
			local handle = evtHandles[i]
			ns:UnregisterEvent(handle[1], handle[2])
			evtHandles[i] = nil
		end
	end

	return {
		Enable = Enable,
		Disable = Disable,
		IsActive = function()
			return active
		end,
		Sync = Sync,
	}
end
