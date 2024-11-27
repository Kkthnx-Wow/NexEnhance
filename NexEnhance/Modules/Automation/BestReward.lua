local _, Module = ...

-- Local references for global functions
local GetNumQuestChoices = GetNumQuestChoices
local GetQuestItemLink = GetQuestItemLink
local GetQuestItemInfo = GetQuestItemInfo
local C_Item_GetItemInfo = C_Item.GetItemInfo

-- Frame for displaying the best reward icon
local rewardIconFrame

-- Retrieve quest rewards
local function RetrieveQuestRewards()
	local numChoices = GetNumQuestChoices()
	if numChoices < 2 then
		return nil
	end

	local questRewards = {}
	for i = 1, numChoices do
		local btn = QuestInfoRewardsFrame.RewardButtons[i]
		if btn and btn.type == "choice" then
			questRewards[i] = btn
		end
	end
	return questRewards
end

-- Calculate the best quest reward
local function DetermineBestQuestReward(questRewards)
	local bestValue, bestItem = 0, nil

	for i, btn in ipairs(questRewards) do
		local questLink = GetQuestItemLink("choice", i)
		if questLink then
			local _, _, amount = GetQuestItemInfo("choice", i)
			local itemSellPrice = select(11, C_Item_GetItemInfo(questLink)) or 0
			local itemRarity = select(3, C_Item_GetItemInfo(questLink)) or 0
			local itemUsefulness = (itemRarity == 6) and 5 or itemRarity

			local totalValue = itemSellPrice * amount + itemUsefulness
			if totalValue > bestValue then
				bestValue = totalValue
				bestItem = i
			end
		end
	end

	return bestItem
end

-- Highlight the best reward
local function HighlightBestQuestReward()
	local questRewards = RetrieveQuestRewards()
	if not questRewards then
		return
	end

	local bestItem = DetermineBestQuestReward(questRewards)
	if bestItem then
		local btn = questRewards[bestItem]
		rewardIconFrame:ClearAllPoints()
		rewardIconFrame:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -2)
		rewardIconFrame:Show()
	end
end

-- Initialize the reward icon frame
local function InitializeRewardIconFrame()
	rewardIconFrame = Module:CreateFrame("Frame", "NE_RewardIconFrame", UIParent)
	rewardIconFrame:SetFrameStrata("HIGH")
	rewardIconFrame:SetSize(20, 20)
	rewardIconFrame:Hide()

	local icon = rewardIconFrame:CreateTexture(nil, "OVERLAY")
	icon:SetAllPoints(rewardIconFrame)
	icon:SetAtlas("Coin-Gold")

	QuestFrameRewardPanel:HookScript("OnHide", function()
		rewardIconFrame:Hide()
	end)
end

-- Event handler for quest rewards
local function HandleQuestCompleteEvent()
	Module:Defer(HighlightBestQuestReward)
end

-- Initialization function
function Module:OnLogin()
	if Module.db.profile.automation.AutoBestQuestReward then
		InitializeRewardIconFrame()
		self:RegisterEvent("QUEST_COMPLETE", HandleQuestCompleteEvent)
	else
		self:UnregisterEvent("QUEST_COMPLETE", HandleQuestCompleteEvent)
	end
end
