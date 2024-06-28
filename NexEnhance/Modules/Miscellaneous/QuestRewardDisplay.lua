local _, Module = ...

local function QuestXPPercent()
	if not Module.db.profile.miscellaneous.questXPPercent then
		return
	end

	local _, unitXPMax = UnitXP("player"), UnitXPMax("player")
	if QuestInfoFrame.questLog then
		local selectedQuest = C_QuestLog.GetSelectedQuest()
		if C_QuestLog.ShouldShowQuestRewards(selectedQuest) then
			local xp = GetQuestLogRewardXP()
			if xp and xp > 0 then
				local text = MapQuestInfoRewardsFrame.XPFrame.Name:GetText()
				if text then
					MapQuestInfoRewardsFrame.XPFrame.Name:SetFormattedText("%s (|cff4beb2c+%.2f%%|r)", text, (xp / unitXPMax) * 100)
				end
			end
		end
	else
		local xp = GetRewardXP()
		if xp and xp > 0 then
			local text = QuestInfoXPFrame.ValueText:GetText()
			if text then
				QuestInfoXPFrame.ValueText:SetFormattedText("%s (|cff4beb2c+%.2f%%|r)", text, (xp / unitXPMax) * 100)
			end
		end
	end
end

local function ResetQuestRewardMostValueIcon()
	-- hide all old overlays
	for i = 1, MAX_NUM_ITEMS do
		if Module.QuestRewardGoldIconOverlay[i] then
			Module.QuestRewardGoldIconOverlay[i]:Hide()
		end
	end
end

function Module:QUEST_COMPLETE()
	if not Module.db.profile.miscellaneous.questRewardsMostValueIcon then
		return
	end

	ResetQuestRewardMostValueIcon()

	local firstItem = QuestInfoRewardsFrameQuestInfoItem1
	if not firstItem then
		return
	end

	local numQuests = GetNumQuestChoices()
	if numQuests < 2 then
		return
	end

	local bestValue, bestItem = 0, 0
	for i = 1, numQuests do
		local questLink = GetQuestItemLink("choice", i)
		local _, _, amount = GetQuestItemInfo("choice", i)
		local itemSellPrice = questLink and select(11, GetItemInfo(questLink))

		local totalValue = (itemSellPrice and itemSellPrice * amount) or 0
		if totalValue > bestValue then
			bestValue = totalValue
			bestItem = i
		end
	end

	if bestItem > 0 then
		local btn = _G["QuestInfoRewardsFrameQuestInfoItem" .. bestItem]
		if btn and btn.type == "choice" then
			local questRewardGoldOverlay = Module.QuestRewardGoldIconOverlay[bestItem]

			if not questRewardGoldOverlay then
				questRewardGoldOverlay = btn:CreateTexture(nil, "OVERLAY")
				questRewardGoldOverlay:SetPoint("TOPLEFT", -5, 5)
				questRewardGoldOverlay:SetAtlas("Coin-Gold", true)
				questRewardGoldOverlay:SetDrawLayer("OVERLAY", 7)

				Module.QuestRewardGoldIconOverlay[bestItem] = questRewardGoldOverlay
			end

			questRewardGoldOverlay:Show()
		end
	end
end

function Module:PLAYER_LOGIN()
	if not Module.QuestRewardGoldIconOverlay then
		Module.QuestRewardGoldIconOverlay = {}
	end

	--Add (+X%) to quest rewards experience text
	hooksecurefunc("QuestInfo_Display", QuestXPPercent)
end
