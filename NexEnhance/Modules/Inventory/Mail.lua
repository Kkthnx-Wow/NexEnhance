--[[
	NexEnhance - Mail
	-------------------------------------------------------------------------
	Quality-of-life helpers for the default mailbox:
	  * "Collect Gold" button that sweeps all attached money from the inbox
	  * "Take All" button on an opened letter that grabs every attachment
	  * a small delete button on each inbox row
	  * an attachment list in the inbox row tooltip when a mail holds several
	    items
	  * a fix for the default "Open All" routine choking on GM mail

	Adapted (functional parts only) from NDui's Modules/Misc/Mail.lua by
	siweia:
	  https://github.com/siweia/NDui/blob/master/Interface/AddOns/NDui/Modules/Misc/Mail.lua
--]]

-- luacheck: globals OpenAllMail InboxFrame ATTACHMENTS_MAX_RECEIVE
---@diagnostic disable: undefined-field, redundant-parameter
local _, ns = ...
local F, L = ns.F, ns.L

local _G = _G
local select = select
local format = string.format
local CreateFrame = CreateFrame
local C_Timer_After = C_Timer.After

local GetInboxNumItems = GetInboxNumItems
local GetInboxHeaderInfo = GetInboxHeaderInfo
local GetInboxItem = GetInboxItem
local TakeInboxMoney = TakeInboxMoney
local TakeInboxItem = TakeInboxItem
local HasInboxItem = HasInboxItem
local InboxItemCanDelete = InboxItemCanDelete
local DeleteInboxItem = DeleteInboxItem
local C_Mail_HasInboxMoney = C_Mail.HasInboxMoney
local C_Mail_IsCommandPending = C_Mail.IsCommandPending
local C_Item_GetItemInfo = C_Item.GetItemInfo
local C_Item_GetItemQualityColor = C_Item.GetItemQualityColor

local DELETE = _G.DELETE
local ERR_MAIL_DELETE_ITEM_ERROR = _G.ERR_MAIL_DELETE_ITEM_ERROR
local MAX_RECEIVE = _G.ATTACHMENTS_MAX_RECEIVE or 12

ns:RegisterDefaults({
	mail = {
		enable = true,
	},
})

local Mail = ns:NewModule("Mail", "mail", { group = "inventory", title = L["Mail"], order = 40 })

local goldButton
local isGoldCollecting
local mailIndex = 0
local timeToWait = 0.15

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------
local function GetTotalInboxMoney()
	local total = 0
	for i = 1, GetInboxNumItems() do
		total = total + (select(5, GetInboxHeaderInfo(i)) or 0)
	end
	return total
end

local function UpdateGoldButtonText(opening)
	if goldButton then
		goldButton:SetText(opening and L["Collecting..."] or L["Collect Gold"])
	end
end

-- ---------------------------------------------------------------------------
-- Collect all gold
--   Walk the inbox back-to-front taking attached money, one mail per tick so
--   the server's command queue keeps up (mirrors the default Open-All cadence).
-- ---------------------------------------------------------------------------
local function CollectGold()
	if mailIndex > 0 then
		if not C_Mail_IsCommandPending() then
			if C_Mail_HasInboxMoney(mailIndex) then
				TakeInboxMoney(mailIndex)
			end
			mailIndex = mailIndex - 1
		end
		C_Timer_After(timeToWait, CollectGold)
	else
		isGoldCollecting = false
		UpdateGoldButtonText(false)
	end
end

local function CollectAllGold()
	if isGoldCollecting then return end
	if GetTotalInboxMoney() == 0 then return end

	isGoldCollecting = true
	mailIndex = GetInboxNumItems()
	UpdateGoldButtonText(true)
	CollectGold()
end

local function GoldButton_OnEnter(self)
	local total = GetTotalInboxMoney()
	if total <= 0 then return end

	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(L["Total Gold"])
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(F.FormatMoney(total), 1, 1, 1)
	GameTooltip:Show()
end

local function CreateGoldButton()
	local inbox = _G["InboxFrame"]
	local openAll = _G["OpenAllMail"]
	if not (inbox and openAll) then return end

	openAll:ClearAllPoints()
	openAll:SetPoint("TOPLEFT", inbox, "TOPLEFT", 50, -35)

	goldButton = CreateFrame("Button", nil, inbox, "UIPanelButtonTemplate")
	goldButton:SetSize(120, 24)
	goldButton:SetPoint("LEFT", openAll, "RIGHT", 3, 0)
	goldButton:SetScript("OnClick", CollectAllGold)
	goldButton:HookScript("OnEnter", GoldButton_OnEnter)
	goldButton:HookScript("OnLeave", GameTooltip_Hide)
	UpdateGoldButtonText(false)
end

-- ---------------------------------------------------------------------------
-- Take All (open mail)
-- ---------------------------------------------------------------------------
local function CollectAttachment()
	local openMail = _G["OpenMailFrame"]
	for i = 1, MAX_RECEIVE do
		local attachmentButton = openMail.OpenMailAttachments[i]
		if attachmentButton and attachmentButton:IsShown() then
			TakeInboxItem(_G["InboxFrame"].openMailID, i)
			C_Timer_After(timeToWait, CollectAttachment)
			return
		end
	end
end

local function CollectCurrent()
	local openMail = _G["OpenMailFrame"]
	if openMail.cod then
		UIErrorsFrame:AddMessage(F.Colorize(L["This letter is cash on delivery."], "red"))
		return
	end

	local currentID = _G["InboxFrame"].openMailID
	if C_Mail_HasInboxMoney(currentID) then
		TakeInboxMoney(currentID)
	end
	CollectAttachment()
end

local function CreateTakeAllButton()
	local openMail = _G["OpenMailFrame"]
	local replyButton = _G["OpenMailReplyButton"]
	if not (openMail and replyButton) then return end

	local button = CreateFrame("Button", nil, openMail, "UIPanelButtonTemplate")
	button:SetSize(82, 22)
	button:SetPoint("RIGHT", replyButton, "LEFT", -1, 0)
	button:SetText(L["Take All"])
	button:SetScript("OnClick", CollectCurrent)
end

-- ---------------------------------------------------------------------------
-- Quick delete button per inbox row
-- ---------------------------------------------------------------------------
local function DeleteButton_OnClick(self)
	local inbox = _G["InboxFrame"]
	local selectedID = self.id + (inbox.pageNum - 1) * 7
	if InboxItemCanDelete(selectedID) then
		DeleteInboxItem(selectedID)
	else
		UIErrorsFrame:AddMessage(F.Colorize(ERR_MAIL_DELETE_ITEM_ERROR, "red"))
	end
end

local function DeleteButton_OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(DELETE)
	GameTooltip:Show()
end

local function CreateDeleteButtons()
	for i = 1, 7 do
		local item = _G["MailItem" .. i .. "Button"]
		if item and not item.nexDelete then
			local bu = CreateFrame("Button", nil, item)
			bu:SetSize(16, 16)
			bu:SetPoint("BOTTOMRIGHT", item:GetParent(), "BOTTOMRIGHT", -10, 5)

			local icon = bu:CreateTexture(nil, "ARTWORK")
			icon:SetAllPoints()
			icon:SetAtlas("common-icon-redx")
			bu.icon = icon

			bu.id = i
			bu:SetScript("OnClick", DeleteButton_OnClick)
			bu:SetScript("OnEnter", DeleteButton_OnEnter)
			bu:SetScript("OnLeave", GameTooltip_Hide)

			item.nexDelete = bu
		end
	end
end

-- ---------------------------------------------------------------------------
-- Attachment list in the inbox row tooltip
-- ---------------------------------------------------------------------------
local inboxItems = {}
local function InboxItem_OnEnter(self)
	if not self.index then return end -- ignore fake rows from other addons

	wipe(inboxItems)

	local itemAttached = select(8, GetInboxHeaderInfo(self.index))
	if not (itemAttached and itemAttached > 1) then return end

	for attachID = 1, 12 do
		local _, itemID, _, itemCount = GetInboxItem(self.index, attachID)
		if itemID and itemCount and itemCount > 0 then
			inboxItems[itemID] = (inboxItems[itemID] or 0) + itemCount
		end
	end

	GameTooltip:AddLine(L["Attachments"])
	for itemID, count in pairs(inboxItems) do
		local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = C_Item_GetItemInfo(itemID)
		if itemName then
			local r, g, b = C_Item_GetItemQualityColor(itemQuality)
			GameTooltip:AddDoubleLine(format(" |T%s:12:12:0:0:50:50:4:46:4:46|t %s", itemTexture, itemName), count, r, g, b)
		end
	end
	GameTooltip:Show()
end

-- ---------------------------------------------------------------------------
-- Fix the default Open-All routine skipping past GM mail (it can stall when a
-- GM letter sits in the queue). Mirrors NDui's guard.
-- ---------------------------------------------------------------------------
local function ApplyOpenAllMailFix()
	local openAll = _G["OpenAllMail"]
	if not (openAll and openAll.AdvanceToNextItem) then return end
	local ATTACHMENTS_MAX = _G.ATTACHMENTS_MAX or MAX_RECEIVE

	function openAll:AdvanceToNextItem()
		local foundAttachment = false
		while not foundAttachment do
			local _, _, _, _, _, CODAmount, _, _, _, _, _, _, isGM = GetInboxHeaderInfo(self.mailIndex)
			local itemID = select(2, GetInboxItem(self.mailIndex, self.attachmentIndex))
			local hasBlacklistedItem = self:IsItemBlacklisted(itemID)
			local hasCOD = CODAmount and CODAmount > 0
			local hasMoneyOrItem = C_Mail_HasInboxMoney(self.mailIndex) or HasInboxItem(self.mailIndex, self.attachmentIndex)
			if not hasBlacklistedItem and not isGM and not hasCOD and hasMoneyOrItem then
				foundAttachment = true
			else
				self.attachmentIndex = self.attachmentIndex - 1
				if self.attachmentIndex == 0 then
					break
				end
			end
		end

		if not foundAttachment then
			self.mailIndex = self.mailIndex + 1
			self.attachmentIndex = ATTACHMENTS_MAX
			if self.mailIndex > GetInboxNumItems() then
				return false
			end
			return self:AdvanceToNextItem()
		end

		return true
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function Mail:Setup()
	if self.done then return end
	self.done = true

	CreateDeleteButtons()
	CreateGoldButton()
	CreateTakeAllButton()

	if _G["InboxFrameItem_OnEnter"] then
		hooksecurefunc("InboxFrameItem_OnEnter", InboxItem_OnEnter)
	end

	ApplyOpenAllMailFix()
end

function Mail:OnEnable()
	if not ns.db.mail.enable then return end
	self:Setup()
end

function Mail:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Mail"], L["Add Collect-Gold, Take-All and quick-delete buttons to the mailbox (reload to disable)."])
end
