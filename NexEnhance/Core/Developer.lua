local _, Core = ...

Core.Devs = {
	["Kkthnx-Valdrakken"] = true,
}
local function isDeveloper()
	local rawName = gsub(Core.MyFullName, "%s", "")
	return Core.Devs[rawName]
end
Core.isDeveloper = isDeveloper()

-- Commands
SlashCmdList["RELOADUI"] = ReloadUI
SLASH_RELOADUI1 = "/rl"
