--[[
	NexEnhance - Transition API
	-------------------------------------------------------------------------
	Patch-day shims for renamed or moved Blizzard APIs. Add compatibility bridges
	here when a new interface version ships, then remove them once the deprecated
	fallback layer is gone (Narcissus APITransition pattern).

	Loaded after Core/Functions.lua so helpers are available. Keep each shim
	documented with the interface version it targets.
--]]

local _, ns = ...

ns.Transition = ns.Transition or {}

-- Example (12.0.7 — already handled in-module; do not duplicate here):
-- if C_PartyInfo and not C_PartyInfo.IsGUIDInGroup and IsGUIDInGroup then
-- 	C_PartyInfo.IsGUIDInGroup = function(guid, category)
-- 		return IsGUIDInGroup(guid, category)
-- 	end
-- end
