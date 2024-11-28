local _, Module = ...

function Module:ForceLoadKkthnxProfile()
	local db = Module.db.profile

	-- General Settings
	db.general.AutoScale = true
	db.general.disableTutorialButtons = true

	-- Chat Settings
	db.chat.SocialButton = true
	db.chat.StickyChat = true
	db.chat.URLCopy = true
	db.chat.Background = true
	db.chat.chatfilters.BlockAddonAlert = true
	db.chat.chatfilters.BlockSpammer = true
	db.chat.chatfilters.ChatItemLevel = true
	db.chat.chatfilters.EnableFilter = true

	-- Tooltip Settings
	db.tooltip.factionIcon = true
	db.tooltip.lfdRole = true
	db.tooltip.hideJunkGuild = true
	db.tooltip.hideRank = true
	db.tooltip.qualityColor = true
	db.tooltip.hideTitle = true
	db.tooltip.ShowID = true
	db.tooltip.mdScore = true

	-- Action Bar Settings
	db.actionbars.hotkeySize = 13
	db.actionbars.range = true
	db.actionbars.cooldowns = true

	-- World Map Settings
	db.worldmap.RevealWorldMap = true

	-- Experience Settings
	db.experience.enableExp = true

	-- Settings Applied
	db.settingsApplied = true

	-- Loot Settings
	db.loot.FasterLoot = true

	-- Automation Settings
	db.automation.DeclineDuels = true
	db.automation.AutoSell = true
	db.automation.AutoInvite = true
	db.automation.AutoScreenshotAchieve = true
	db.automation.AnnoyingBuffs = true
	db.automation.CinematicSkip = true
	db.automation.DeclinePetDuels = true
	db.automation.SkipCinematics = true
	db.automation.AutoRepair = 1
	db.automation.AutoResurrect = true
	db.automation.AutoGoodbye = true
	db.automation.AutoKeystoneSlotting = true
	db.automation.AutoBestQuestReward = true

	-- Skin Settings
	db.skins.blizzskins.characterFrame = true
	db.skins.blizzskins.objectiveTracker = true
	db.skins.blizzskins.chatbubble = true
	db.skins.blizzskins.inspectFrame = true
	db.skins.blizzskins.collectionsFrame = true
	db.skins.addonskins.details = true

	-- Miscellaneous Settings
	db.miscellaneous.itemlevels.merchantFrame = true
	db.miscellaneous.itemlevels.inspectFrame = true
	db.miscellaneous.itemlevels.guildBankFrame = true
	db.miscellaneous.itemlevels.characterFrame = true
	db.miscellaneous.itemlevels.lootFrame = true
	db.miscellaneous.itemlevels.containers = true
	db.miscellaneous.itemlevels.flyout = true
	db.miscellaneous.itemlevels.tradeFrame = true
	db.miscellaneous.itemlevels.scrapping = true
	db.miscellaneous.gemsNEnchants = true
	db.miscellaneous.moveableFrames = true
	db.miscellaneous.questXPPercent = true
	db.miscellaneous.questRewardsMostValueIcon = true
	db.miscellaneous.disableTalkingHead = true
	db.miscellaneous.enableAFKMode = true
	db.miscellaneous.alreadyKnown = true

	-- Unit Frames Settings
	db.unitframes.classColorHealth = true

	-- Minimap Settings
	db.minimap.PingNotifier = true
	db.minimap.recycleBin = true
	db.minimap.EasyVolume = true
end
