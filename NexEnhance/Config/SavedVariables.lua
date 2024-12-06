local _, Config = ...

local defaults = {
	profile = {
		actionbars = {
			MmssTH = 60, -- MM:SS Threshold for cooldown timers
			OverrideWA = false, -- Disable WeakAuras cooldown timers
			TenthTH = 3, -- Threshold for showing decimal cooldowns
			cooldowns = false, -- Enable/Disable cooldown timers
			range = false, -- Enable/Disable range indicators
			nameSize = 12, -- Font size for action button names
			countSize = 14, -- Font size for item count
			hotkeySize = 12, -- Font size for hotkeys
			showName = true, -- Show/Hide action button names
			showCount = true, -- Show/Hide item count
			showHotkey = true, -- Show/Hide hotkey text
		},
		automation = {
			IgnoreQuestNPC = {},
			AnnoyingBuffs = false,
			AutoBestQuestReward = false,
			AutoGoodbye = false,
			AutoInvite = false,
			AutoKeystoneSlotting = false,
			AutoQuest = false,
			AutoRepair = 0,
			AutoResurrect = false,
			AutoResurrectEmote = "thank",
			AutoScreenshotAchieve = false,
			AutoSell = false,
			CustomGoodbyeMessage = "",
			DeclineDuels = false,
			DeclinePetDuels = false,
			SkipCinematics = false,
		},
		chat = {
			Background = false,
			URLCopy = false,
			StickyChat = false,
			SocialButton = false,
			MenuButton = false,
			ChannelButton = false,
			DefaultChannelNames = false,
			TimestampFormat = "DISABLE",
			WhisperColor = false,
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
			barHeight = 12,
			barTextFormat = "CURPERC",
			barWidth = 570,
			classColorBar = false,
			enableExp = false,
			numberFormat = 1,
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
			PingNotifier = false,
			recycleBin = false,
			recycleBinAuto = true,
		},
		miscellaneous = {
			alreadyKnown = false,
			diableTalkingHead = false,
			enableAFKMode = false,
			gemsNEnchants = false,
			hideWidgetTexture = true,
			missingStats = true,
			moveableFrames = false,
			questRewardsMostValueIcon = false,
			questXPPercent = false,
			widgetScale = 0.8,
			QuestTrackerAlerts = {
				OnlyCompleteRing = false,
				QuestNotification = false,
				QuestProgress = false,
			},
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
				chatbubble = false,
				collectionsFrame = false,
				inspectFrame = false,
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
			playerFrameEnhancements = {
				classColorFramesSkipPlayer = false,
				colorPetAfterOwner = false,
				playerReputationColor = false,
				playerReputationClassColor = false,
				playerHitIndicatorHide = false,
			},
			targetFrameEnhancements = {
				targetReputationColorHide = false,
			},
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

	-- Initialize database with defaults
	Config.db = LibStub("AceDB-3.0"):New("NexEnhanceDB", defaults)

	-- Attach to namespace
	Config.NexConfig = Config.db.profile

	Config:SetupUIScale(true)

	Config:UnregisterEvent("ADDON_LOADED", Config.ADDON_LOADED)
end
