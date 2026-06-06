--[[
	NexEnhance - Number Format
	-------------------------------------------------------------------------
	Picks which abbreviation style F.ShortValue uses across the UI (datatexts,
	tooltips, etc.). The actual formatting lives in Core/Functions.lua via the
	12.0 AbbreviateNumbers API; this module just owns the saved preference and
	its General-page option.

	  * style = 1  Western      (1.2k / 3.4m / 5.6b / 7.8t)
	  * style = 2  East Asian   (1.2w / 3.4y / 5.6z)
	  * style = 3  Full Numbers (no abbreviation)
--]]

local _, ns = ...
local L = ns.L

ns:RegisterDefaults({
	numberFormat = {
		style = 1,
	},
})

local NumberFormat = ns:NewModule("NumberFormat", "numberFormat", { group = "general", title = L["Number Format"], order = 30 })

function NumberFormat:RegisterOptions(category, builder)
	builder:Dropdown(category, self, "style", L["Number Format"], L["Choose how large numbers are abbreviated throughout NexEnhance."], {
		{ value = 1, label = L["Standard (1.2k / 3.4m)"] },
		{ value = 2, label = L["East Asian (1.2w / 3.4y)"] },
		{ value = 3, label = L["Full Numbers (No Abbreviation)"] },
	})
end
