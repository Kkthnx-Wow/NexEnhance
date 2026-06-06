--[[
	NexEnhance - Reload UI
	-------------------------------------------------------------------------
	Adds short slash commands for reloading the interface: /rl, /reloadui, //
	and /. (the native /reload is left untouched).

	Adapted from KkthnxUI by Josh "Kkthnx" Russell:
	  https://github.com/Kkthnx-Wow/KkthnxUI/blob/master/KkthnxUI/Developer/Elements/ReloadUI.lua
--]]

---@diagnostic disable: inject-field
local _, ns = ...
local L = ns.L

local _G = _G

ns:RegisterDefaults({
	reloadUI = {
		enable = true,
	},
})

local ReloadUI = ns:NewModule("ReloadUI", "reloadUI", { group = "misc", title = L["Reload UI"], order = 80 })

function ReloadUI:OnEnable()
	if not ns.db.reloadUI.enable then return end

	_G.SLASH_NEXRELOADUI1 = "/rl"
	_G.SLASH_NEXRELOADUI2 = "/reloadui"
	_G.SLASH_NEXRELOADUI3 = "//"
	_G.SLASH_NEXRELOADUI4 = "/."
	---@diagnostic disable-next-line: undefined-field
	_G.SlashCmdList["NEXRELOADUI"] = _G.ReloadUI
end

function ReloadUI:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Reload Command"], L["Add /rl, /reloadui, // and /. slash commands to reload the interface (reload to disable)."])
end
