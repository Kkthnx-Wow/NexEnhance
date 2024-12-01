-- Core Actionbars Module File
local _, Modules = ...

-- Ensure Modules.Actionbars exists
Modules.Actionbars = Modules.Actionbars or {}

-- Event handler for ADDON_LOADED
-- function Modules:ADDON_LOADED() end

-- Event handler for PLAYER_LOGIN
function Modules:PLAYER_LOGIN()
	local actionbars = Modules.Actionbars

	if actionbars then
		if Modules.Actionbars.RegisterActionbarStyle then
			Modules.Actionbars:RegisterActionbarStyle()
		end
		if Modules.Actionbars.RegisterRangeIndicator then
			Modules.Actionbars:RegisterRangeIndicator()
		end
		if Modules.Actionbars.RegisterCooldowns then
			Modules.Actionbars:RegisterCooldowns()
		end
	end
end
