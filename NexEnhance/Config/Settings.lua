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
		title = "|cff00ff00Better Quest Tracker|r",
		tooltip = "Toggle Better Quest Trackers.",
		type = "toggle",
		default = true,
	},
	{
		key = "betterCharacterFrame",
		title = "|cff00ff00Improved Character Frame|r",
		tooltip = "Toggle Better Character Frames.",
		type = "toggle",
		default = false,
	},
	{
		key = "betterInspectFrame",
		title = "|cff00ff00Improved Inspect Frame|r",
		tooltip = "Toggle Better Inspect Frames.",
		type = "toggle",
		default = false,
	},
	{
		key = "whisperColor",
		title = "|cff00ff00whisperColor|r",
		tooltip = "whisperColor.",
		type = "toggle",
		default = true,
	},
	{
		key = "oldChatNames",
		title = "|cff00ff00oldChatNames|r",
		tooltip = "oldChatNames.",
		type = "toggle",
		default = false,
	},
})

addon:RegisterSettingsSlash("/nexe", "/ne")
