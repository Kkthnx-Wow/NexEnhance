local AddonName, Config = ...

local defaults = {
	profile = {
		actionbars = {
			MmssTH = 60,
			OverrideWA = false,
			TenthTH = 3,
			cooldowns = true,
			range = true,
		},
		automation = {
			AnnoyingBuffs = true,
			AutoRepair = 2,
			AutoSell = true,
		},
		blizzard = {
			characterFrame = true,
			chatbubble = true,
			inspectFrame = true,
		},
		chat = {},
		general = {
			AutoScale = false,
			UIScale = 0.53,
		},
		loot = {
			FasterLoot = false,
		},
		maps = {},
		miscellaneous = {
			missingStats = true,
		},
		tempanchor = {},
		tooltip = {
			ShowID = true,
			SpecLevelByShift = true,
			combatHide = false,
			factionIcon = true,
			hideJunkGuild = true,
			hideRank = true,
			hideRealm = true,
			hideTitle = true,
			lfdRole = true,
			mdScore = true,
			qualityColor = true,
		},
		unitframes = {
			classColorHealth = true,
		},
		worldmap = {
			AlphaWhenMoving = 0.35,
			Coordinates = true,
			FadeWhenMoving = true,
			SmallWorldMap = true,
			SmallWorldMapScale = 0.9,
		},
		settingsApplied = false,
	},
}

function Config:ADDON_LOADED(name)
	if name == AddonName then
		-- initialize database with defaults
		Config.db = LibStub("AceDB-3.0"):New("NexEnhanceDB", defaults, true)
		return true
	end
end
