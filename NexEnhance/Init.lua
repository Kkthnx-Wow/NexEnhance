-- Initialization function for NexEnhance addon
local _, Init = ...

-- Initialize tables only if they don't exist
Init.Data = Init.Data or {}
Init.Actionbars = Init.Actionbars or {}
Init.Automation = Init.Automation or {}
Init.Blizzard = Init.Blizzard or {}
Init.BugFixes = Init.BugFixes or {}
Init.Chat = Init.Chat or {}
Init.General = Init.General or {}
Init.Inventory = Init.Inventory or {}
Init.Loot = Init.Loot or {}
Init.Maps = Init.Maps or {}
Init.Miscellaneous = Init.Miscellaneous or {}
Init.Skins = Init.Skins or {}
Init.Unitframes = Init.Unitframes or {}

-- Function triggered on PLAYER_LOGIN event
function Init:OnLogin()
	-- Initial setting to use key down for action bar buttons
	SetCVar("ActionButtonUseKeyDown", 1)
end
