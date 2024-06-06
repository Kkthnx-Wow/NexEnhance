-- Initialization function for NexEnhance addon
local NexEnhance, NE_Init = ...

-- -- Events
-- -- Local table to hold registered events and their associated functions
-- local registeredEvents = {}

-- -- Create a frame to manage event registration and handling
-- local eventHost = CreateFrame("Frame")

-- -- Event handler function
-- eventHost:SetScript("OnEvent", function(_, event, ...)
-- 	local handlers = registeredEvents[event]
-- 	if handlers then
-- 		for func in pairs(handlers) do
-- 			if event == "COMBAT_LOG_EVENT_UNFILTERED" then
-- 				func(event, CombatLogGetCurrentEventInfo())
-- 			else
-- 				func(event, ...)
-- 			end
-- 		end
-- 	end
-- end)

-- -- Register a new event and its handler function
-- function NE_Init:RegisterEvent(event, func, unit1, unit2)
-- 	-- Normalize the event name for combat log events
-- 	if event == "CLEU" then
-- 		event = "COMBAT_LOG_EVENT_UNFILTERED"
-- 	end

-- 	-- Initialize the event entry if it doesn't exist
-- 	if not registeredEvents[event] then
-- 		registeredEvents[event] = {}

-- 		-- Register the event with the frame
-- 		if unit1 then
-- 			eventHost:RegisterUnitEvent(event, unit1, unit2)
-- 		else
-- 			eventHost:RegisterEvent(event)
-- 		end
-- 	end

-- 	-- Store the function in the event's handler list
-- 	registeredEvents[event][func] = true
-- end

-- -- Unregister an event and remove its handler function
-- function NE_Init:UnregisterEvent(event, func)
-- 	-- Normalize the event name for combat log events
-- 	if event == "CLEU" then
-- 		event = "COMBAT_LOG_EVENT_UNFILTERED"
-- 	end

-- 	-- Retrieve the list of functions for the event
-- 	local handlers = registeredEvents[event]
-- 	if handlers and handlers[func] then
-- 		-- Remove the specific function from the event's handler list
-- 		handlers[func] = nil

-- 		-- If no more functions are registered for the event, remove the event entry
-- 		if not next(handlers) then
-- 			registeredEvents[event] = nil
-- 			eventHost:UnregisterEvent(event)
-- 		end
-- 	end
-- end

-- Function triggered on PLAYER_LOGIN event
function NE_Init:PLAYER_LOGIN()
	-- Initial setting to use key down for action bar buttons
	SetCVar("ActionButtonUseKeyDown", 1)
end
