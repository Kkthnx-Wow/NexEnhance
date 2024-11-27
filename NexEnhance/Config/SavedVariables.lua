local _, Config = ...

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
			AutoGoodbye = false,
			AutoInvite = false,
			AutoRepair = 0,
			AutoResurrect = false,
			AutoResurrectEmote = "thank",
			AutoScreenshotAchieve = false,
			AutoSell = false,
			CinematicSkip = false,
			CustomGoodbyeMessage = "",
			DeclineDuels = false,
			DeclinePetDuels = false,
			AutoKeystoneSlotting = false,
		},
		chat = {
			Background = false,
			URLCopy = false,
			StickyChat = false,
			SocialButton = false,
			chatfilters = {
				BlockStrangers = false,
				BlockSpammer = false,
				FilterMatches = "1",
				ChatItemLevel = false,
				EnableFilter = false,
				BlockAddonAlert = false,
				ChatFilterList = "%*",
				ChatFilterWhiteList = "",
			},
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
			SuppressTutorialPrompts = false,
			NumberPrefixStyle = "STANDARD",
		},
		loot = {
			FasterLoot = false,
		},
		minimap = {
			EasyVolume = false,
			recycleBin = false,
		},
		miscellaneous = {
			widgetScale = 0.8,
			hideWidgetTexture = true,

			alreadyKnown = false,
			diableTalkingHead = false,
			enableAFKMode = false,
			gemsNEnchants = false,
			missingStats = true,
			moveableFrames = false,
			questRewardsMostValueIcon = false,
			questXPPercent = false,
			itemlevels = {
				characterFrame = false,
				containers = false,
				flyout = false,
				guildBankFrame = false,
				inspectFrame = false,
				lootFrame = false,
				merchantFrame = false,
				scrapping = false,
				tradeFrame = false,
			},
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

	Config:UnregisterEvent("ADDON_LOADED", Config.ADDON_LOADED)

	return true
end
