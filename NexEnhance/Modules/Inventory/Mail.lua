--[[
	NexEnhance - Mail
	-------------------------------------------------------------------------
	Quality-of-life helpers for the default mailbox:
	  * "Collect Gold" button that sweeps all attached money from the inbox
	  * "Take All" button on an opened letter that grabs every attachment
	  * a small delete button on each inbox row
	  * an attachment list in the inbox row tooltip when a mail holds several
	    items
--]]

-- luacheck: globals OpenAllMail InboxFrame ATTACHMENTS_MAX_RECEIVE INBOXITEMS_TO_DISPLAY
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
local HasInboxItem = HasInboxItem
local TakeInboxMoney = TakeInboxMoney
local TakeInboxItem = TakeInboxItem
local InboxItemCanDelete = InboxItemCanDelete
local DeleteInboxItem = DeleteInboxItem
local C_Mail_HasInboxMoney = C_Mail.HasInboxMoney
local C_Mail_IsCommandPending = C_Mail.IsCommandPending
local C_Item_GetItemInfo = C_Item.GetItemInfo
local C_Item_GetItemQualityColor = C_Item.GetItemQualityColor
local C_Container_CalculateTotalNumberOfFreeBagSlots = C_Container and C_Container.CalculateTotalNumberOfFreeBagSlots

local DELETE = _G.DELETE
local ERR_MAIL_DELETE_ITEM_ERROR = _G.ERR_MAIL_DELETE_ITEM_ERROR
local ERR_INV_FULL = _G.ERR_INV_FULL
-- Blizzard_MailFrame loads at login (DefaultState: enabled), so these globals
-- exist; fall back to current live values just in case the constants move.
local MAX_RECEIVE = _G.ATTACHMENTS_MAX_RECEIVE or 16
local PER_PAGE = _G.INBOXITEMS_TO_DISPLAY or 7
local OPEN_ALL_MAIL_MIN_DELAY = 0.15

ns:RegisterDefaults({
	mail = {
		enable = true,
	},
})

local Mail = ns:NewModule("Mail", "mail", { group = "inventory", title = L["Mail"], order = 30 })

local goldButton
local takeAllButton
local isGoldCollecting
local isTakeAllRunning
local mailIndex = 0
local goldInboxSnapshot
local takeAllAttachment = MAX_RECEIVE
local timeToWait = OPEN_ALL_MAIL_MIN_DELAY
local eventHandles = {}
local eventsRegistered = false
local inboxHooked

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------
local function MailFrameOpen()
	local mailFrame = _G["MailFrame"]
	return mailFrame and mailFrame:IsShown()
end

local function ShouldSkipMailForGoldCollect(index)
	local _, _, _, _, money, codAmount, _, _, _, _, _, _, isGM = GetInboxHeaderInfo(index)
	if isGM then
		return true
	end
	if codAmount and F.NotSecret(codAmount) and codAmount > 0 then
		return true
	end
	if not (money and F.NotSecret(money) and money > 0) then
		return true
	end
	return false
end

local function GetTotalInboxMoney()
	local total = 0
	for i = 1, GetInboxNumItems() do
		if not ShouldSkipMailForGoldCollect(i) then
			local money = select(5, GetInboxHeaderInfo(i)) or 0
			if F.NotSecret(money) then
				total = total + money
			end
		end
	end
	return total
end

local function UpdateGoldButtonText(opening)
	if goldButton then
		goldButton:SetText(opening and L["Collecting..."] or L["Collect Gold"])
	end
end

local function StopTakeAll()
	isTakeAllRunning = false
	takeAllAttachment = MAX_RECEIVE
end

local function StopGoldCollect()
	isGoldCollecting = false
	mailIndex = 0
	goldInboxSnapshot = nil
	UpdateGoldButtonText(false)
end

-- ---------------------------------------------------------------------------
-- Collect all gold
--   Walk the inbox back-to-front taking attached money, one mail per tick so
--   the server's command queue keeps up (mirrors the default Open-All cadence).
-- ---------------------------------------------------------------------------
local function CollectGold()
	if not MailFrameOpen() then
		StopGoldCollect()
		return
	end

	if mailIndex > 0 then
		if not C_Mail_IsCommandPending() then
			local numItems = GetInboxNumItems()
			if goldInboxSnapshot and numItems ~= goldInboxSnapshot then
				mailIndex = numItems
			end
			goldInboxSnapshot = numItems

			if not ShouldSkipMailForGoldCollect(mailIndex) and C_Mail_HasInboxMoney(mailIndex) then
				TakeInboxMoney(mailIndex)
			end
			mailIndex = mailIndex - 1
			goldInboxSnapshot = GetInboxNumItems()
		end
		C_Timer_After(timeToWait, CollectGold)
	else
		StopGoldCollect()
	end
end

local function CollectAllGold()
	if isGoldCollecting or isTakeAllRunning then
		return
	end
	if GetTotalInboxMoney() == 0 then
		return
	end

	isGoldCollecting = true
	mailIndex = GetInboxNumItems()
	goldInboxSnapshot = mailIndex
	UpdateGoldButtonText(true)
	CollectGold()
end

local function GoldButton_OnEnter(self)
	local total = GetTotalInboxMoney()
	if total <= 0 then
		return
	end

	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(L["Total Gold"])
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(F.FormatMoney(total), 1, 1, 1)
	GameTooltip:Show()
end

local function CreateGoldButton()
	if goldButton then
		return
	end

	local inbox = _G["InboxFrame"]
	local openAll = _G["OpenAllMail"]
	if not (inbox and openAll) then
		return
	end

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
local function TakeAllStep()
	if not isTakeAllRunning or not MailFrameOpen() then
		StopTakeAll()
		return
	end

	local inbox = _G["InboxFrame"]
	local mailID = inbox and inbox.openMailID
	if not mailID or mailID == 0 or mailID > GetInboxNumItems() then
		StopTakeAll()
		return
	end

	if C_Mail_IsCommandPending() then
		C_Timer_After(timeToWait, TakeAllStep)
		return
	end

	if C_Container_CalculateTotalNumberOfFreeBagSlots and C_Container_CalculateTotalNumberOfFreeBagSlots() == 0 then
		UIErrorsFrame:AddMessage(F.Colorize(ERR_INV_FULL, "red"))
		StopTakeAll()
		return
	end

	while takeAllAttachment >= 1 do
		if HasInboxItem(mailID, takeAllAttachment) then
			TakeInboxItem(mailID, takeAllAttachment)
			takeAllAttachment = takeAllAttachment - 1
			C_Timer_After(timeToWait, TakeAllStep)
			return
		end
		takeAllAttachment = takeAllAttachment - 1
	end

	StopTakeAll()
end

local function CollectCurrent()
	if isTakeAllRunning or isGoldCollecting then
		return
	end

	local openMail = _G["OpenMailFrame"]
	local inbox = _G["InboxFrame"]
	if not (openMail and inbox) then
		return
	end

	local cod = openMail.cod
	if cod and (F.IsSecret(cod) or cod > 0) then
		UIErrorsFrame:AddMessage(F.Colorize(L["This letter is cash on delivery."], "red"))
		return
	end

	local currentID = inbox.openMailID
	if not currentID or currentID == 0 or currentID > GetInboxNumItems() then
		return
	end

	isTakeAllRunning = true
	takeAllAttachment = MAX_RECEIVE

	if C_Mail_HasInboxMoney(currentID) then
		TakeInboxMoney(currentID)
		C_Timer_After(timeToWait, TakeAllStep)
	else
		TakeAllStep()
	end
end

local function CreateTakeAllButton()
	if takeAllButton then
		return
	end

	local openMail = _G["OpenMailFrame"]
	local replyButton = _G["OpenMailReplyButton"]
	if not (openMail and replyButton) then
		return
	end

	takeAllButton = CreateFrame("Button", nil, openMail, "UIPanelButtonTemplate")
	takeAllButton:SetSize(82, 22)
	takeAllButton:SetPoint("RIGHT", replyButton, "LEFT", -1, 0)
	takeAllButton:SetText(L["Take All"])
	takeAllButton:SetScript("OnClick", CollectCurrent)
end

-- ---------------------------------------------------------------------------
-- Quick delete button per inbox row
-- ---------------------------------------------------------------------------
local function DeleteButton_OnClick(self)
	local inbox = _G["InboxFrame"]
	if not inbox then
		return
	end

	local selectedID = self.id + (inbox.pageNum - 1) * PER_PAGE
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
	for i = 1, PER_PAGE do
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
	if not self.index then
		return
	end -- ignore fake rows from other addons

	wipe(inboxItems)

	local itemAttached = select(8, GetInboxHeaderInfo(self.index))
	if not (itemAttached and F.NotSecret(itemAttached) and itemAttached > 1) then
		return
	end

	for attachID = 1, MAX_RECEIVE do
		if HasInboxItem(self.index, attachID) then
			local _, itemID, _, itemCount = GetInboxItem(self.index, attachID)
			if itemID and itemCount and F.NotSecret(itemID) and F.NotSecret(itemCount) and itemCount > 0 then
				inboxItems[itemID] = (inboxItems[itemID] or 0) + itemCount
			end
		end
	end

	GameTooltip:AddLine(L["Attachments"])
	for itemID, count in pairs(inboxItems) do
		local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = C_Item_GetItemInfo(itemID)
		if itemName then
			local r, g, b = C_Item_GetItemQualityColor(itemQuality)
			local tex = itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark"
			GameTooltip:AddDoubleLine(format(" |T%s:12:12:0:0:50:50:4:46:4:46|t %s", tex, itemName), count, r, g, b)
		end
	end
	GameTooltip:Show()
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function Mail:Setup()
	if not ns.db.mail.enable then
		return
	end

	CreateDeleteButtons()
	CreateGoldButton()
	CreateTakeAllButton()

	if not inboxHooked and _G["InboxFrameItem_OnEnter"] then
		hooksecurefunc("InboxFrameItem_OnEnter", InboxItem_OnEnter)
		inboxHooked = true
	end
end

function Mail:RegisterModuleEvents()
	if eventsRegistered then
		return
	end
	eventsRegistered = true
	self:TrackEvent(eventHandles, "MAIL_SHOW", "Setup")
end

function Mail:UnregisterModuleEvents()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
end

function Mail:OnEnable()
	if not ns.db.mail.enable then
		return
	end
	self:RegisterModuleEvents()
	self:Setup()
end

function Mail:OnDisable()
	self:UnregisterModuleEvents()
	StopGoldCollect()
	StopTakeAll()
end

function Mail:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Mail"], L["Add Collect-Gold, Take-All and quick-delete buttons to the mailbox (reload to disable)."])
end
