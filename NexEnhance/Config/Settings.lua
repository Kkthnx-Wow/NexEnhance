local _, addon = ...

addon:RegisterSettings("NexEnhanceDB", {
	{
		key = "classColorsOn",
		title = "|cff00ff00Unitframe Class Color Health|r",
		tooltip = "Toggle to use class colors for unit frame health bars.",
		type = "toggle",
		default = true,
	},
	{
		key = "betterQuestTracker",
		title = "|cff00ff00Better quest tracker|r",
		tooltip = "Better quest tracker.",
		type = "toggle",
		default = true,
	},
	-- {
	-- 	key = "unitframe_classcolor",
	-- 	title = "|cff00ff00Unitframe Class Color Health|r",
	-- 	tooltip = "Toggle to use class colors for unit frame health bars.",
	-- 	type = "toggle",
	-- 	default = true,
	-- },
	-- {
	-- 	key = "unitframe_classcolor",
	-- 	title = "|cff00ff00Unitframe Class Color Health|r",
	-- 	tooltip = "Toggle to use class colors for unit frame health bars.",
	-- 	type = "toggle",
	-- 	default = true,
	-- },
})

addon:RegisterSettingsSlash("/nexe", "/ne")
