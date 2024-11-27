-- NexEnhance Initialization File
local _, Init = ...

Init.LibMoreEvents = LibStub("LibMoreEvents-1.0-NexEnhance", true) or nil

-- Initialize addon modules
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

-- Initialization function triggered on PLAYER_LOGIN event
function Init:OnLogin()
	-- Set default CVars
	SetCVar("ActionButtonUseKeyDown", 1)
end
