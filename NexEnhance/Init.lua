-- Initialization function for NexEnhance addon
local _, Init = ...

Init.Data = {}
Init.Chat = {}

-- Function triggered on PLAYER_LOGIN event
function Init:OnLogin()
	-- Initial setting to use key down for action bar buttons
	SetCVar("ActionButtonUseKeyDown", 1)
end
