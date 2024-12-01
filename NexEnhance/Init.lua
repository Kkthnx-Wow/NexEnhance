-- NexEnhance Initialization File
local _, Init = ...

-- Initialize addon modules with minimal overhead
local moduleNames = {
	"Data",
	"Actionbars",
	"Chat",
}

for _, moduleName in ipairs(moduleNames) do
	Init[moduleName] = Init[moduleName] or {}
end

-- Initialization function triggered on PLAYER_LOGIN event
function Init:OnLogin()
	-- Set default CVars for optimal performance
	SetCVar("ActionButtonUseKeyDown", 1)
end

-- Expose Init as NexEnhance globally
_G.NexEnhance = Init
