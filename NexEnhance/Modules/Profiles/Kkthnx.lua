local _, Module = ...

function Module:ForceLoadKkthnxProfile()
	local db = Module.db.profile

	db.chat.URLCopy = true
	db.chat.StickyChat = true

	db.general.AutoScale = true

	db.blizzard.characterFrame = true
	db.blizzard.objectiveTracker = true
	db.blizzard.chatbubble = true
	db.blizzard.inspectFrame = true

	db.tooltip.factionIcon = true
	db.tooltip.lfdRole = true
	db.tooltip.hideJunkGuild = true
	db.tooltip.hideRank = true
	db.tooltip.qualityColor = true
	db.tooltip.hideTitle = true
	db.tooltip.ShowID = true
	db.tooltip.mdScore = true

	db.unitframes.classColorHealth = true

	db.minimap.EasyVolume = true

	db.miscellaneous.enableAFKMode = true
	db.miscellaneous.questXPPercent = true
	db.miscellaneous.questRewardsMostValueIcon = true

	db.loot.FasterLoot = true

	db.automation.DeclinePetDuels = true
	db.automation.AutoSell = true
	db.automation.DeclineDuels = true
	db.automation.AnnoyingBuffs = true
	db.automation.AutoScreenshotAchieve = true
	db.automation.AutoRepair = true
	db.automation.CinematicSkip = true

	db.experience.enableExp = true

	db.actionbars.cooldowns = true
	db.actionbars.range = true
end
