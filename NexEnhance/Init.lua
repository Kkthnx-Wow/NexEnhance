-- Initialization function for NexEnhance addon
local NexEnhance, NE_Init = ...

-- Function triggered on PLAYER_LOGIN event
function NE_Init:PLAYER_LOGIN()
	-- Initial setting to use key down for action bar buttons
	SetCVar("ActionButtonUseKeyDown", 1)
end
