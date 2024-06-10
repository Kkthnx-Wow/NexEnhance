-- Initialization function for NexEnhance addon
local _, Init = ...

-- Init Libs
do
	Init.Libs = {}
	local function AddLib(name, libname, silent)
		if not name then
			return
		end
		Init.Libs[name] = _G.LibStub(libname, silent)
	end

	AddLib("LibDD", "LibUIDropDownMenu-4.0", true)
end

-- Function triggered on PLAYER_LOGIN event
function Init:PLAYER_LOGIN()
	-- Initial setting to use key down for action bar buttons
	SetCVar("ActionButtonUseKeyDown", 1)
end
