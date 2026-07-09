--[[
	NexEnhance - Popup QoL
	-------------------------------------------------------------------------
	Removes common popup friction (aligned with Blizzard UIParent.lua /
	StaticPopupDefs in Resources 12.0.7):
	  * Auto-confirm BoP loot and tradeable equip/sell prompts
	  * Enter accepts non-refundable purchases
	  * Alt+right-click buys a full merchant stack (once-per-item confirm)
	  * Click-through event toasts
	  * Summon / party invite popups ignore Escape

	Each sub-option is off by default except click-through toasts.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local L = ns.L
local F = ns.F

local InCombatLockdown = InCombatLockdown
local IsAltKeyDown = IsAltKeyDown
local floor = math.floor
local min = math.min
local hooksecurefunc = hooksecurefunc
local StaticPopupDialogs = StaticPopupDialogs
local StaticPopup_Show = StaticPopup_Show
local StaticPopup_Hide = StaticPopup_Hide
local BuyMerchantItem = BuyMerchantItem
local GetMerchantItemLink = GetMerchantItemLink
local GetMerchantItemMaxStack = GetMerchantItemMaxStack
local GetMerchantItemCostInfo = GetMerchantItemCostInfo
local GetMerchantItemCostItem = GetMerchantItemCostItem
local GetMoney = GetMoney
local C_Item = C_Item
local C_MerchantFrame = C_MerchantFrame
local MAX_ITEM_COST = MAX_ITEM_COST

ns:RegisterDefaults({
	popupQoL = {
		enable = true,
		autoConfirmLoot = false,
		autoConfirmTradeableEquip = false,
		autoConfirmTradeableSell = false,
		clickThroughToasts = true,
		enterAcceptPurchase = false,
		altStackBuy = false,
	},
})

local PopupQoL = ns:NewModule("PopupQoL", "popupQoL", { group = "misc", title = L["Popup QoL"], order = 55 })

local applied = {}
local toastHooked
local originalEnterPurchase
local stackBuySkipCache = {}
local origMerchantModifiedClick

local eventHandles = {}
local eventsRegistered = false

-- Mirrors MerchantItemButton_OnLoad SplitStack routing (MerchantFrame.lua) plus the
-- high-price confirm path from MerchantItemButton_OnClick right-button buys.
local function BuyMerchantStack(button, index, quantity)
	if quantity <= 0 then
		return
	end
	if button.extendedCost or button.showNonrefundablePrompt then
		if MerchantFrame_ConfirmExtendedItemCost then
			MerchantFrame_ConfirmExtendedItemCost(button, quantity)
			return
		end
	elseif button.price and MERCHANT_HIGH_PRICE_COST and button.price >= MERCHANT_HIGH_PRICE_COST then
		if MerchantFrame_ConfirmHighCostItem then
			MerchantFrame_ConfirmHighCostItem(button, quantity)
			return
		end
	end
	BuyMerchantItem(index, quantity)
end

-- Affordability cap copied from MerchantItemButton_OnModifiedClick SPLITSTACK handling.
local function GetMaxPurchasableStack(index)
	local maxStack = GetMerchantItemMaxStack(index)
	if not maxStack or maxStack <= 1 then
		return maxStack
	end
	if not C_MerchantFrame or not C_MerchantFrame.GetItemInfo then
		return maxStack
	end
	local info = C_MerchantFrame.GetItemInfo(index)
	if not info then
		return maxStack
	end

	local canAfford = maxStack
	if info.price and F.NotSecret(info.price) and info.price > 0 then
		local money = GetMoney()
		if F.NotSecret(money) then
			canAfford = floor(money / (info.price / info.stackCount))
		end
	end

	if info.hasExtendedCost then
		for i = 1, MAX_ITEM_COST do
			local _, itemValue, costItemLink, currencyName = GetMerchantItemCostItem(index, i)
			if costItemLink and not currencyName and itemValue and itemValue > 0 then
				local myCount = C_Item.GetItemCount(costItemLink, false, false, true)
				canAfford = min(canAfford, floor(myCount / (itemValue / info.stackCount)))
			end
		end
	end

	return min(maxStack, canAfford)
end

-- Same popupData shape as MerchantFrame_GetProductInfo / CONFIRM_PURCHASE_* dialogs.
local function BuildStackBuyPopupData(button, index, itemLink, quantity)
	if MerchantFrame_GetProductInfo then
		local popupData = MerchantFrame_GetProductInfo(button)
		popupData.count = quantity
		popupData.button = button
		return popupData
	end
	return {
		link = itemLink,
		index = index,
		count = quantity,
		button = button,
		useLinkForItemInfo = true,
	}
end

StaticPopupDialogs["NEXENHANCE_BUY_STACK"] = {
	text = "%s",
	button1 = _G.YES,
	button2 = _G.NO,
	hasItemFrame = true,
	hideOnEscape = true,
	timeout = 0,
	whileDead = true,
	preferredIndex = 3,
	OnAccept = function(_, data)
		if type(data) ~= "table" or not data.index then
			return
		end
		local index = data.index
		local quantity = data.count or GetMaxPurchasableStack(index) or GetMerchantItemMaxStack(index)
		if not quantity or quantity <= 0 then
			return
		end
		if data.button then
			BuyMerchantStack(data.button, index, quantity)
		else
			BuyMerchantItem(index, quantity)
		end
		if data.link then
			stackBuySkipCache[data.link] = true
		end
	end,
}

local function OnMerchantItemModifiedClick(self, button)
	if ns.db.popupQoL.enable
		and ns.db.popupQoL.altStackBuy
		and button == "RightButton"
		and IsAltKeyDown()
		and MerchantFrame
		and MerchantFrame.selectedTab == 1
	then
		local index = self:GetID()
		local itemLink = GetMerchantItemLink(index)
		if itemLink then
			local quantity = GetMaxPurchasableStack(index)
			if quantity and quantity > 1 then
				if stackBuySkipCache[itemLink] then
					BuyMerchantStack(self, index, quantity)
					return
				end
				local popupData = BuildStackBuyPopupData(self, index, itemLink, quantity)
				StaticPopup_Show("NEXENHANCE_BUY_STACK", L["Stack Buying Check"], nil, popupData)
				return
			end
		end
	end
	if origMerchantModifiedClick then
		origMerchantModifiedClick(self, button)
	end
end

local function InstallStackBuyHook()
	if applied.stackBuyHook then
		return
	end
	if not MerchantItemButton_OnModifiedClick then
		return
	end
	origMerchantModifiedClick = MerchantItemButton_OnModifiedClick
	MerchantItemButton_OnModifiedClick = OnMerchantItemModifiedClick
	applied.stackBuyHook = true
end

local function RestoreStackBuyHook()
	if not applied.stackBuyHook then
		return
	end
	if origMerchantModifiedClick then
		MerchantItemButton_OnModifiedClick = origMerchantModifiedClick
		origMerchantModifiedClick = nil
	end
	StaticPopup_Hide("NEXENHANCE_BUY_STACK")
	applied.stackBuyHook = nil
end

local function OnMerchantShow()
	if ns.db.popupQoL.enable and ns.db.popupQoL.altStackBuy then
		InstallStackBuyHook()
	end
end

local function ConfirmLoot(_, lootSlot)
	ConfirmLootSlot(lootSlot)
end

local function ConfirmTradeableEquip(_, inventorySlot)
	if not InCombatLockdown() then
		EquipPendingItem(inventorySlot)
	end
end

local function ConfirmTradeableSell()
	if CursorHasItem() then
		SellCursorItem()
	end
end

local function SetPopupFlag(dialogName, field, value)
	local dialog = StaticPopupDialogs and StaticPopupDialogs[dialogName]
	if dialog then
		dialog[field] = value
	end
end

local function ApplyEscapeGuards()
	SetPopupFlag("PARTY_INVITE", "hideOnEscape", nil)
	SetPopupFlag("CONFIRM_SUMMON", "hideOnEscape", nil)
	SetPopupFlag("AREA_SPIRIT_HEAL", "hideOnEscape", nil)
	SetPopupFlag("CAMP", "hideOnEscape", nil)
	applied.escapeGuards = true
end

local function ApplyEnterPurchase()
	if not StaticPopupDialogs then
		return
	end
	local dialog = StaticPopupDialogs.CONFIRM_PURCHASE_NONREFUNDABLE_ITEM
	if dialog and not applied.enterPurchase then
		originalEnterPurchase = dialog.enterClicksFirstButton
		dialog.enterClicksFirstButton = true
		applied.enterPurchase = true
	end
end

local function RestoreEnterPurchase()
	if applied.enterPurchase and StaticPopupDialogs then
		local dialog = StaticPopupDialogs.CONFIRM_PURCHASE_NONREFUNDABLE_ITEM
		if dialog then
			dialog.enterClicksFirstButton = originalEnterPurchase
		end
		applied.enterPurchase = nil
	end
end

local function OnToastDisplay(frame)
	if not ns.db.popupQoL.enable or not ns.db.popupQoL.clickThroughToasts then
		return
	end
	frame:EnableMouse(false)
	local toast = frame.currentDisplayingToast
	if toast then
		toast:EnableMouse(false)
		if toast.TitleTextMouseOverFrame then
			toast.TitleTextMouseOverFrame:EnableMouse(false)
		end
		if toast.SubTitleMouseOverFrame then
			toast.SubTitleMouseOverFrame:EnableMouse(false)
		end
	end
end

local function HookToasts()
	if toastHooked or not EventToastManagerFrame then
		return
	end
	hooksecurefunc(EventToastManagerFrame, "DisplayToast", OnToastDisplay)
	toastHooked = true
end

local function ApplyLootConfirm()
	if applied.lootConfirm then
		return
	end
	if UIParent then
		UIParent:UnregisterEvent("LOOT_BIND_CONFIRM")
	end
	ns:RegisterEvent("LOOT_BIND_CONFIRM", ConfirmLoot)
	applied.lootConfirm = true
end

local function RestoreLootConfirm()
	if not applied.lootConfirm then
		return
	end
	ns:UnregisterEvent("LOOT_BIND_CONFIRM", ConfirmLoot)
	if UIParent then
		UIParent:RegisterEvent("LOOT_BIND_CONFIRM")
	end
	applied.lootConfirm = nil
end

local function ApplyEquipConfirm()
	if applied.equipConfirm then
		return
	end
	if UIParent then
		UIParent:UnregisterEvent("EQUIP_BIND_TRADEABLE_CONFIRM")
	end
	ns:RegisterEvent("EQUIP_BIND_TRADEABLE_CONFIRM", ConfirmTradeableEquip)
	applied.equipConfirm = true
end

local function RestoreEquipConfirm()
	if not applied.equipConfirm then
		return
	end
	ns:UnregisterEvent("EQUIP_BIND_TRADEABLE_CONFIRM", ConfirmTradeableEquip)
	if UIParent then
		UIParent:RegisterEvent("EQUIP_BIND_TRADEABLE_CONFIRM")
	end
	applied.equipConfirm = nil
end

local function ApplySellConfirm()
	if applied.sellConfirm or not MerchantFrame then
		return
	end
	MerchantFrame:UnregisterEvent("MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL")
	ns:RegisterEvent("MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL", ConfirmTradeableSell)
	applied.sellConfirm = true
end

local function RestoreSellConfirm()
	if not applied.sellConfirm then
		return
	end
	ns:UnregisterEvent("MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL", ConfirmTradeableSell)
	if MerchantFrame then
		MerchantFrame:RegisterEvent("MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL")
	end
	applied.sellConfirm = nil
end

local function ApplyAll()
	local db = ns.db.popupQoL
	if not db.enable then
		return
	end

	ApplyEscapeGuards()
	HookToasts()

	if db.autoConfirmLoot then
		ApplyLootConfirm()
	end
	if db.autoConfirmTradeableEquip then
		ApplyEquipConfirm()
	end
	if db.autoConfirmTradeableSell then
		ApplySellConfirm()
	end
	if db.enterAcceptPurchase then
		ApplyEnterPurchase()
	end
	if db.altStackBuy then
		InstallStackBuyHook()
	end
end

local function RestoreAll()
	RestoreLootConfirm()
	RestoreEquipConfirm()
	RestoreSellConfirm()
	RestoreEnterPurchase()
	RestoreStackBuyHook()
end

function PopupQoL:OnEnable()
	if eventsRegistered then
		return
	end
	eventsRegistered = true
	self:TrackEvent(eventHandles, "MERCHANT_SHOW", OnMerchantShow)
	ApplyAll()
end

function PopupQoL:OnDisable()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
	RestoreAll()
end

function PopupQoL:OnSettingChanged(key, value)
	if key == "enable" and not value then
		RestoreAll()
		return
	end
	if key == "altStackBuy" then
		if value and ns.db.popupQoL.enable then
			InstallStackBuyHook()
		else
			RestoreStackBuyHook()
		end
		return
	end
	if key == "enable" or key == "autoConfirmLoot" or key == "autoConfirmTradeableEquip" or key == "autoConfirmTradeableSell" or key == "enterAcceptPurchase" then
		RestoreAll()
		ApplyAll()
	end
end

function PopupQoL:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Popup QoL"], L["Reduce popup friction for loot, tradeables, purchases, and event toasts. Sub-options below are off by default except click-through toasts."])
	local _, lootInit = builder:Checkbox(category, self, "autoConfirmLoot", L["Auto-Confirm BoP Loot"], L["Automatically confirm loot that binds on pickup."])
	local _, equipInit = builder:Checkbox(category, self, "autoConfirmTradeableEquip", L["Auto-Confirm Tradeable Equip"], L["Automatically equip BoE items still within the trade window."])
	local _, sellInit = builder:Checkbox(category, self, "autoConfirmTradeableSell", L["Auto-Confirm Tradeable Sell"], L["Automatically sell BoE items still within the trade window at vendors."])
	local _, toastInit = builder:Checkbox(category, self, "clickThroughToasts", L["Click-Through Event Toasts"], L["Let the mouse pass through event toasts so they do not block clicks."])
	local _, purchaseInit = builder:Checkbox(category, self, "enterAcceptPurchase", L["Enter Accepts Purchases"], L["Press Enter to accept non-refundable purchase confirmations."])
	local _, stackInit = builder:Checkbox(category, self, "altStackBuy", L["Alt+Right-Click Stack Buy"], L["Hold Alt and right-click a merchant item to buy a full stack. Asks once per item until you reload."])

	builder:DependsOn(lootInit, enableInit)
	builder:DependsOn(equipInit, enableInit)
	builder:DependsOn(sellInit, enableInit)
	builder:DependsOn(toastInit, enableInit)
	builder:DependsOn(purchaseInit, enableInit)
	builder:DependsOn(stackInit, enableInit)
end
