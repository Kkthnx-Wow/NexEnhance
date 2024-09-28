local AddonName, Config = ...

local defaults = {
	profile = {
		actionbars = {
			MmssTH = 60,
			OverrideWA = false,
			TenthTH = 3,
			cooldowns = false,
			range = false,
		},
		automation = {
			AnnoyingBuffs = false,
			AutoInvite = false,
			AutoRepair = 2,
			AutoScreenshotAchieve = false,
			AutoSell = false,
			CinematicSkip = false,
			DeclineDuels = false,
			DeclinePetDuels = false,
		},
		blizzard = {},
		chat = {
			Background = false,
			URLCopy = false,
			StickyChat = false,
		},
		experience = {
			enableExp = false,
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
			diableTalkingHead = false,
			enableAFKMode = false,
			missingStats = true,
			questRewardsMostValueIcon = false,
			questXPPercent = false,
		},
		settingsApplied = false,
		skins = {
			blizzskins = {
				characterFrame = false,
				inspectFrame = false,
				chatbubble = false,
				objectiveTracker = false,
			},
			addonskins = {
				details = false,
			},
		},
		tempanchor = {},
		tooltip = {
			ShowID = false,
			SpecLevelByShift = true,
			combatHide = false,
			cursorPosition = "DISABLE",
			factionIcon = false,
			hideJunkGuild = false,
			hideRank = false,
			hideRealm = false,
			hideTitle = false,
			lfdRole = false,
			mdScore = false,
			qualityColor = false,
		},
		unitframes = {
			classColorHealth = false,
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
		-- bugfixes = {},
	},
}

function Config:ADDON_LOADED(addon)
	if addon ~= "NexEnhance" then
		return
	end

	-- initialize database with defaults
	Config.db = LibStub("AceDB-3.0"):New("NexEnhanceDB", defaults)
	Config:SetupUIScale(true)

	return true
end
