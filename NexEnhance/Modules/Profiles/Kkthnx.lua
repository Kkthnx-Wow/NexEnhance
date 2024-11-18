local _, Module = ...

function Module:ForceLoadKkthnxProfile()
	local db = Module.db.profile

	-- General Settings
	db.general.AutoScale = true

	-- Loot Settings
	db.loot.FasterLoot = true

	-- Tooltip Settings
	db.tooltip.factionIcon = true
	db.tooltip.lfdRole = true
	db.tooltip.hideJunkGuild = true
	db.tooltip.hideRank = true
	db.tooltip.qualityColor = true
	db.tooltip.hideTitle = true
	db.tooltip.ShowID = true
	db.tooltip.mdScore = true

	-- Minimap Settings
	db.minimap.EasyVolume = true
	db.minimap.recycleBin = true

	-- Chat Settings
	db.chat.StickyChat = true
	db.chat.URLCopy = true
	db.chat.Background = true
	db.chat.chatfilters.BlockAddonAlert = true
	db.chat.chatfilters.ChatItemLevel = true
	db.chat.chatfilters.BlockSpammer = true
	db.chat.chatfilters.EnableFilter = true

	-- Miscellaneous Settings
	db.miscellaneous.itemlevels.merchantFrame = true
	db.miscellaneous.itemlevels.inspectFrame = true
	db.miscellaneous.itemlevels.guildBankFrame = true
	db.miscellaneous.itemlevels.characterFrame = true
	db.miscellaneous.itemlevels.flyout = true
	db.miscellaneous.itemlevels.lootFrame = true
	db.miscellaneous.itemlevels.scrapping = true
	db.miscellaneous.itemlevels.containers = true
	db.miscellaneous.itemlevels.tradeFrame = true
	db.miscellaneous.gemsNEnchants = true
	db.miscellaneous.moveableFrames = true
	db.miscellaneous.questXPPercent = true
	db.miscellaneous.disableTalkingHead = true
	db.miscellaneous.enableAFKMode = true
	db.miscellaneous.questRewardsMostValueIcon = true
	db.miscellaneous.alreadyKnown = true

	-- Experience Settings
	db.experience.enableExp = true

	-- Settings Applied
	db.settingsApplied = true

	-- Automation Settings
	db.automation.DeclinePetDuels = true
	db.automation.AutoSell = true
	db.automation.AutoInvite = true
	db.automation.DeclineDuels = true
	db.automation.AnnoyingBuffs = true
	db.automation.AutoScreenshotAchieve = true
	db.automation.AutoRepair = true
	db.automation.CinematicSkip = true

	-- Skin Settings
	db.skins.blizzskins.characterFrame = true
	db.skins.blizzskins.objectiveTracker = true
	db.skins.blizzskins.inspectFrame = true
	db.skins.blizzskins.chatbubble = true
	db.skins.addonskins.details = true

	-- Action Bar Settings
	db.actionbars.cooldowns = true
	db.actionbars.range = true

	-- Unit Frames Settings
	db.unitframes.classColorHealth = true
end
