-- NexEnhance Initialization File
local _, Init = ...

-- Create the Engine table and its sub-tables
Init[1] = {}
Init[2] = {}

-- Assign the sub-tables to variables K, C, and L
local NexEnhance, Config = Init[1], Init[2]

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

-- Expose Init as fields of the global NexEnhance table
_G.NexEnhance = Init
