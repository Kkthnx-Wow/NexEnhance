local NexEnhance, NE_AutoRepair = ...

local format = string.format
local GetMoney, GetRepairAllCost, RepairAllItems, CanMerchantRepair = GetMoney, GetRepairAllCost, RepairAllItems, CanMerchantRepair
local IsInGuild, CanGuildBankRepair, GetGuildBankWithdrawMoney = IsInGuild, CanGuildBankRepair, GetGuildBankWithdrawMoney
local C_Timer_After, IsShiftKeyDown, CanMerchantRepair = C_Timer.After, IsShiftKeyDown, CanMerchantRepair

local needToRepair

-- Auto repair
local isShown, isBankEmpty, autoRepair, repairAllCost, canRepair

local function delayFunc()
	if isBankEmpty then
		autoRepair(true)
	else
		NE_AutoRepair:Print(format(NE_AutoRepair.InfoColor .. "%s|r%s", NE_AutoRepair.L["Repair costs covered by Guild Bank"], NE_AutoRepair:GetMoneyString(repairAllCost, true)))
	end
end

function autoRepair(override)
	if isShown and not override then
		return
	end
	isShown = true
	isBankEmpty = false

	local myMoney = GetMoney()
	repairAllCost, canRepair = GetRepairAllCost()

	if canRepair and repairAllCost > 0 then
		if (not override) and NE_AutoRepair.db.profile.automation.AutoRepair == 1 and IsInGuild() and CanGuildBankRepair() and GetGuildBankWithdrawMoney() >= repairAllCost then
			RepairAllItems(true)
		else
			if myMoney > repairAllCost then
				RepairAllItems()
				NE_AutoRepair:Print(format(NE_AutoRepair.InfoColor .. "%s|r%s", NE_AutoRepair.L["Yikes! You're almost broke!"], NE_AutoRepair:GetMoneyString(repairAllCost, true)))
				return
			else
				NE_AutoRepair:Print(NE_AutoRepair.InfoColor .. NE_AutoRepair.L["Yikes! Something went wrong. We can't repair!"])
				return
			end
		end

		C_Timer_After(0.5, delayFunc)
	end
end

local function checkBankFund(_, msgType)
	if msgType == LE_GAME_ERR_GUILD_NOT_ENOUGH_MONEY then
		isBankEmpty = true
	end
end

local function merchantClose()
	isShown = false
	NE_AutoRepair.eventMixin:UnregisterEvent("UI_ERROR_MESSAGE", checkBankFund)
	NE_AutoRepair.eventMixin:UnregisterEvent("MERCHANT_CLOSED", merchantClose)
end

local function merchantShow()
	if IsShiftKeyDown() or NE_AutoRepair.db.profile.automation.AutoRepair == 0 or not CanMerchantRepair() then
		return
	end
	autoRepair()
	NE_AutoRepair.eventMixin:RegisterEvent("UI_ERROR_MESSAGE", checkBankFund)
	NE_AutoRepair.eventMixin:RegisterEvent("MERCHANT_CLOSED", merchantClose)
end
NE_AutoRepair.eventMixin:RegisterEvent("MERCHANT_SHOW", merchantShow)

local repairGossipIDs = {
	[37005] = true, -- 基维斯
	[44982] = true, -- 里弗斯
}
NE_AutoRepair.eventMixin:RegisterEvent("GOSSIP_SHOW", function()
	if IsShiftKeyDown() then
		return
	end

	if not needToRepair then
		return
	end

	local options = C_GossipInfo.GetOptions()
	for i = 1, #options do
		local option = options[i]
		if repairGossipIDs[option.gossipOptionID] then
			C_GossipInfo.SelectOption(option.gossipOptionID)
		end
	end
end)
