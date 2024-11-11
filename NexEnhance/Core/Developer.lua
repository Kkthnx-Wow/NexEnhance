local _, Core = ...

-- Devs list
local Developers = {
	["Kkthnx-Area 52"] = true,
}

-- Utility function to check if the player is a developer
local function isDeveloper()
	local playerName = gsub(Core.MyFullName, "%s", "")
	return Developers[playerName]
end

Core.isDeveloper = isDeveloper()

SlashCmdList["RELOADUI"] = ReloadUI
SLASH_RELOADUI1 = "/rl"
