local NexEnhance, NE_SavedVariables = ...

local defaults = {
	profile = {
		general = {
			AutoScale = false,
			UIScale = 0.53,
		},
		actionbars = {
			cooldowns = true,
			MmssTH = 60,
			TenthTH = 3,
			OverrideWA = false,
		},
		automation = {
			AutoRepair = 2,
			AutoSell = true,
		},
		blizzard = {
			characterFrame = true,
			inspectFrame = true,
		},
		chat = {},
		maps = {},
		miscellaneous = {
			missingStats = true,
		},
		tooltip = {
			combatHide = false,
			factionIcon = true,
			hideJunkGuild = true,
			hideRank = true,
			hideRealm = true,
			hideTitle = true,
			lfdRole = true,
			mdScore = true,
			qualityColor = true,
			SpecLevelByShift = true,
		},
		unitframes = {
			classColorHealth = true,
		},
		worldmap = {
			SmallWorldMap = true,
			Coordinates = true,
			FadeWhenMoving = true,
			SmallWorldMapScale = 0.9,
			AlphaWhenMoving = 0.35,
		},

		tempanchor = {},
	},
}

function NE_SavedVariables:ADDON_LOADED(name)
	if name == NexEnhance then
		-- initialize database with defaults
		NE_SavedVariables.db = LibStub("AceDB-3.0"):New("NexEnhanceDB", defaults, true)
		return true
	end
end
