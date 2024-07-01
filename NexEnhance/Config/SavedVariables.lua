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
			AutoScreenshotAchieve = false,
			AutoSell = true,
			CinematicSkip = false,
			DeclineDuels = false,
			DeclinePetDuels = false,
		},
		blizzard = {
			characterFrame = true,
			chatbubble = true,
			inspectFrame = true,
			objectiveTracker = true,
		},
		chat = {
			Background = false,
			URLCopy = false,
			StickyChat = false,
		},
		experience = {
			enableExp = true,
			numberFormat = 1,
			barTextFormat = "CURPERC",
			barWidth = 570,
			barHeight = 12,
			showBubbles = true,
		},
		general = {
			AutoScale = false,
			UIScale = 0.53,
			numberPrefixStyle = "STANDARD",
		},
		loot = {
			FasterLoot = false,
		},
		minimap = {
			EasyVolume = false,
		},
		miscellaneous = {
			enableAFKMode = false,
			missingStats = true,
			questXPPercent = false,
			questRewardsMostValueIcon = false,
		},
		settingsApplied = false,
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
			RevealWorldMap = false,
			RevealWorldMapGlow = true,
			AlphaWhenMoving = 0.35,
			Coordinates = true,
			FadeWhenMoving = true,
			SmallWorldMap = true,
			SmallWorldMapScale = 0.9,
		},
		bugfixes = {
			DruidFormFix = false,
			suboptions = {
				subOptionA = false,
				subOptionB = true,
			},
		},
	},
}

function Config:ADDON_LOADED(name)
	if name == AddonName then
		-- initialize database with defaults
		Config.db = LibStub("AceDB-3.0"):New("NexEnhanceDB", defaults)

		return true
	end
end
