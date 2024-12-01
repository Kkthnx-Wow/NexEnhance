local _, Module = ...
local L = Module.L

-- Cache global functions
local strmatch = strmatch
local tonumber = tonumber
local ceil = math.ceil
local format = string.format

-- Cache WoW API functions
local C_Item_GetItemInfo = C_Item.GetItemInfo
local GetInboxItem = GetInboxItem
local GetInboxItemLink = GetInboxItemLink
local GetLootSlotInfo = GetLootSlotInfo
local GetLootSlotLink = GetLootSlotLink
local GetMerchantNumItems = GetMerchantNumItems
local GetMerchantItemInfo = GetMerchantItemInfo
local GetMerchantItemLink = GetMerchantItemLink
local GetNumQuestRewards = GetNumQuestRewards
local GetNumQuestChoices = GetNumQuestChoices
local GetQuestItemInfo = GetQuestItemInfo
local GetQuestLogItemLink = GetQuestLogItemLink
local GetQuestItemLink = GetQuestItemLink
local GetNumBuybackItems = GetNumBuybackItems
local GetBuybackItemInfo = GetBuybackItemInfo
local GetBuybackItemLink = GetBuybackItemLink
local GetCurrentGuildBankTab = GetCurrentGuildBankTab
local GetGuildBankItemInfo = GetGuildBankItemInfo
local GetGuildBankItemLink = GetGuildBankItemLink
local C_PetJournal_GetNumCollectedInfo = C_PetJournal.GetNumCollectedInfo

-- Cache WoW API objects and constants
local C_TooltipInfo = C_TooltipInfo
local C_AddOns = C_AddOns
local LootFrameElementMixin = LootFrameElementMixin
local COLLECTED = COLLECTED
local ITEM_SPELL_KNOWN = ITEM_SPELL_KNOWN
local ATTACHMENTS_MAX_RECEIVE = ATTACHMENTS_MAX_RECEIVE
local MERCHANT_ITEMS_PER_PAGE = MERCHANT_ITEMS_PER_PAGE
local MAX_GUILDBANK_SLOTS_PER_TAB = MAX_GUILDBANK_SLOTS_PER_TAB or 98
local NUM_SLOTS_PER_GUILDBANK_GROUP = NUM_SLOTS_PER_GUILDBANK_GROUP or 14

-- Cache UI functions
local SetItemButtonTextureVertexColor = SetItemButtonTextureVertexColor

-- Cache global variables
local _G = _G

local COLOR = { r = 0.1, g = 1, b = 0.1 }
local knowables = {
	[Enum.ItemClass.Consumable] = true,
	[Enum.ItemClass.Recipe] = true,
	[Enum.ItemClass.Miscellaneous] = true,
	[Enum.ItemClass.ItemEnhancement] = true,
}
local knowns = {}

local function isPetCollected(speciesID)
	if not speciesID or speciesID == 0 then
		return
	end

	local numOwned = C_PetJournal_GetNumCollectedInfo(speciesID)
	if numOwned > 0 then
		return true
	end
end

local function IsAlreadyKnown(link, index)
	-- Check if the feature is enabled in config
	if not Module.NexConfig.miscellaneous.alreadyKnown or not link then
		return
	end

	local linkType, linkID = strmatch(link, "|H(%a+):(%d+)")
	linkID = tonumber(linkID)

	if linkType == "battlepet" then
		return isPetCollected(linkID)
	elseif linkType == "item" then
		local name, _, _, _, _, _, _, _, _, _, _, itemClassID = C_Item_GetItemInfo(link)
		if not name then
			return
		end

		if itemClassID == Enum.ItemClass.Battlepet and index then
			local data = C_TooltipInfo.GetGuildBankItem(GetCurrentGuildBankTab(), index)
			if data then
				return data.battlePetSpeciesID and isPetCollected(data.battlePetSpeciesID)
			end
		else
			if knowns[link] then
				return true
			end
			if not knowables[itemClassID] and not C_Item.IsCosmeticItem(link) then
				return
			end

			local data = C_TooltipInfo.GetHyperlink(link, nil, nil, true)
			if data then
				for i = 1, #data.lines do
					local lineData = data.lines[i]
					local text = lineData.leftText
					if text then
						if strfind(text, COLLECTED) or text == ITEM_SPELL_KNOWN then
							knowns[link] = true
							return true
						end
					end
				end
			end

			-- Clear the 'knowns' table here, as it's not needed beyond this point.
			knowns = {}
		end
	end
end

-- Mail frame
local function OpenMailFrame_UpdateButtonPositions()
	-- Check if the feature is enabled in config
	if not Module.NexConfig.miscellaneous.alreadyKnown then
		return
	end

	for i = 1, ATTACHMENTS_MAX_RECEIVE do
		local button = _G["OpenMailAttachmentButton" .. i]
		if button then
			local name, _, _, _, canUse = GetInboxItem(InboxFrame.openMailID, i)
			if name and canUse and IsAlreadyKnown(GetInboxItemLink(InboxFrame.openMailID, i)) then
				SetItemButtonTextureVertexColor(button, COLOR.r, COLOR.g, COLOR.b)
			end
		end
	end
end
hooksecurefunc("OpenMailFrame_UpdateButtonPositions", OpenMailFrame_UpdateButtonPositions)

-- Loot frame
local function LootFrame_UpdateButton(self)
	-- Check if the feature is enabled in config
	if not Module.NexConfig.miscellaneous.alreadyKnown then
		return
	end

	local slotIndex = self:GetSlotIndex()
	local texture, _, _, _, _, locked = GetLootSlotInfo(slotIndex)
	if texture and not locked and IsAlreadyKnown(GetLootSlotLink(slotIndex)) then
		SetItemButtonTextureVertexColor(self.Item, COLOR.r, COLOR.g, COLOR.b)
	end
end
hooksecurefunc(LootFrameElementMixin, "Init", LootFrame_UpdateButton)

-- Merchant frame
local function Hook_UpdateMerchantInfo()
	-- Check if the feature is enabled in config
	if not Module.NexConfig.miscellaneous.alreadyKnown then
		return
	end

	local numItems = GetMerchantNumItems()
	for i = 1, MERCHANT_ITEMS_PER_PAGE do
		local index = (MerchantFrame.page - 1) * MERCHANT_ITEMS_PER_PAGE + i
		if index > numItems then
			return
		end

		local button = _G["MerchantItem" .. i .. "ItemButton"]
		local isButtonShown = button and button:IsShown()
		if isButtonShown then
			local _, _, _, _, numAvailable, isUsable = GetMerchantItemInfo(index)
			if isUsable and IsAlreadyKnown(GetMerchantItemLink(index)) then
				local r, g, b = COLOR.r, COLOR.g, COLOR.b
				if numAvailable == 0 then
					r, g, b = r * 0.5, g * 0.5, b * 0.5
				end
				SetItemButtonTextureVertexColor(button, r, g, b)
			end
		end
	end
end
hooksecurefunc("MerchantFrame_UpdateMerchantInfo", Hook_UpdateMerchantInfo)

-- Quest frame
local function QuestInfo_ShowRewards()
	if not Module.NexConfig.miscellaneous.alreadyKnown then
		return
	end

	local numQuestRewards, numQuestChoices
	if QuestInfoFrame.questLog then
		numQuestRewards, numQuestChoices = GetNumQuestLogRewards(), GetNumQuestLogChoices(C_QuestLog.GetSelectedQuest(), true)
	else
		numQuestRewards, numQuestChoices = GetNumQuestRewards(), GetNumQuestChoices()
	end

	local totalRewards = numQuestRewards + numQuestChoices
	if totalRewards == 0 then
		return
	end

	local rewardsCount = 0

	if numQuestChoices > 0 then
		local baseIndex = rewardsCount
		for i = 1, numQuestChoices do
			local button = _G["QuestInfoItem" .. i + baseIndex]
			local isButtonShown = button and button:IsShown()
			if isButtonShown then
				local isUsable
				if QuestInfoFrame.questLog then
					_, _, _, _, isUsable = GetQuestLogChoiceInfo(i)
				else
					_, _, _, _, isUsable = GetQuestItemInfo("choice", i)
				end
				if isUsable and IsAlreadyKnown(QuestInfoFrame.questLog and GetQuestLogItemLink("choice", i) or GetQuestItemLink("choice", i)) then
					SetItemButtonTextureVertexColor(button, COLOR.r, COLOR.g, COLOR.b)
				end
			end
			rewardsCount = rewardsCount + 1
		end
	end

	if numQuestRewards > 0 then
		local baseIndex = rewardsCount
		for i = 1, numQuestRewards do
			local button = _G["QuestInfoItem" .. i + baseIndex]
			local isButtonShown = button and button:IsShown()
			if isButtonShown then
				local isUsable
				if QuestInfoFrame.questLog then
					_, _, _, _, isUsable = GetQuestLogRewardInfo(i)
				else
					_, _, _, _, isUsable = GetQuestItemInfo("reward", i)
				end
				if isUsable and IsAlreadyKnown(QuestInfoFrame.questLog and GetQuestLogItemLink("reward", i) or GetQuestItemLink("reward", i)) then
					SetItemButtonTextureVertexColor(button, COLOR.r, COLOR.g, COLOR.b)
				end
				rewardsCount = rewardsCount + 1
			end
		end
	end
end

if C_AddOns.IsAddOnLoaded("Pawn") then
	hooksecurefunc("PawnUI_OnQuestInfo_ShowRewards", QuestInfo_ShowRewards)
else
	hooksecurefunc("QuestInfo_ShowRewards", QuestInfo_ShowRewards)
end

local function Hook_UpdateBuybackInfo()
	if not Module.NexConfig.miscellaneous.alreadyKnown then
		return
	end

	local numItems = GetNumBuybackItems()
	for index = 1, BUYBACK_ITEMS_PER_PAGE do
		if index > numItems then
			return
		end

		local button = _G["MerchantItem" .. index .. "ItemButton"]
		local isButtonShown = button and button:IsShown()
		if isButtonShown then
			local _, _, _, _, _, isUsable = GetBuybackItemInfo(index)
			if isUsable and IsAlreadyKnown(GetBuybackItemLink(index)) then
				SetItemButtonTextureVertexColor(button, COLOR.r, COLOR.g, COLOR.b)
			end
		end
	end
end
hooksecurefunc("MerchantFrame_UpdateBuybackInfo", Hook_UpdateBuybackInfo)

local function Hook_UpdateAuctionItems(self)
	if not Module.NexConfig.miscellaneous.alreadyKnown then
		return
	end

	for i = 1, self.ScrollTarget:GetNumChildren() do
		local child = select(i, self.ScrollTarget:GetChildren())
		if child.cells then
			local button = child.cells[2]
			local itemKey = button and button.rowData and button.rowData.itemKey
			if itemKey and itemKey.itemID then
				local itemLink
				if itemKey.itemID == 82800 then
					itemLink = format("|Hbattlepet:%d::::::|h[Dummy]|h", itemKey.battlePetSpeciesID)
				else
					itemLink = format("|Hitem:%d", itemKey.itemID)
				end

				if itemLink and IsAlreadyKnown(itemLink) then
					-- Highlight
					child.SelectedHighlight:Show()
					child.SelectedHighlight:SetVertexColor(COLOR.r, COLOR.g, COLOR.b)
					child.SelectedHighlight:SetAlpha(0.25)
					-- Icon
					button.Icon:SetVertexColor(COLOR.r, COLOR.g, COLOR.b)
					button.IconBorder:SetVertexColor(COLOR.r, COLOR.g, COLOR.b)
				else
					-- Highlight
					child.SelectedHighlight:SetVertexColor(1, 1, 1)
					-- Icon
					button.Icon:SetVertexColor(1, 1, 1)
					button.IconBorder:SetVertexColor(1, 1, 1)
				end
			end
		end
	end
end

local function GuildBankFrame_Update(self)
	if not Module.NexConfig.miscellaneous.alreadyKnown or self.mode ~= "bank" then
		return
	end

	local button, index, column, texture, locked
	local currentTab = GetCurrentGuildBankTab()

	for i = 1, MAX_GUILDBANK_SLOTS_PER_TAB do
		index = (i - 1) % NUM_SLOTS_PER_GUILDBANK_GROUP + 1

		column = ceil(i / NUM_SLOTS_PER_GUILDBANK_GROUP)
		button = self.Columns[column].Buttons[index]

		local isButtonShown = button and button:IsShown()
		if isButtonShown then
			texture, _, locked = GetGuildBankItemInfo(currentTab, i)

			if texture and not locked then
				local itemLink = GetGuildBankItemLink(currentTab, i)
				if IsAlreadyKnown(itemLink, i) then
					SetItemButtonTextureVertexColor(button, COLOR.r, COLOR.g, COLOR.b)
				else
					SetItemButtonTextureVertexColor(button, 1, 1, 1)
				end
			end
		end
	end
end

Module:HookAddOn("Blizzard_AuctionHouseUI", function()
	if AuctionHouseFrame then
		hooksecurefunc(AuctionHouseFrame.BrowseResultsFrame.ItemList.ScrollBox, "Update", Hook_UpdateAuctionItems)
	end
end)

Module:HookAddOn("Blizzard_GuildBankUI", function()
	if GuildBankFrame then
		hooksecurefunc(GuildBankFrame, "Update", GuildBankFrame_Update)
	end
end)
