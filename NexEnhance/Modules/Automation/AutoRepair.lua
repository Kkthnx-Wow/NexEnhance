local _, Module = ...

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
		Module:Print(format(Module.InfoColor .. "%s|r%s", Module.L["Repair costs covered by Guild Bank"], Module:GetMoneyString(repairAllCost, true)))
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
		if (not override) and Module.NexConfig.automation.AutoRepair == 1 and IsInGuild() and CanGuildBankRepair() and GetGuildBankWithdrawMoney() >= repairAllCost then
			RepairAllItems(true)
		else
			if myMoney > repairAllCost then
				RepairAllItems()
				Module:Print(format(Module.InfoColor .. "%s|r%s", Module.L["Repair cost"], Module:GetMoneyString(repairAllCost, true)))
				return
			else
				Module:Print(Module.InfoColor .. Module.L["Yikes! You are running out of gold!"])
				return
			end
		end

		C_Timer_After(0.5, delayFunc)
	end
end

local function checkBankFund(_, message)
	if message == LE_GAME_ERR_GUILD_NOT_ENOUGH_MONEY then
		isBankEmpty = true
	end
end

local function merchantClose()
	isShown = false
	Module:UnregisterEvent("UI_ERROR_MESSAGE", checkBankFund)
	Module:UnregisterEvent("MERCHANT_CLOSED", merchantClose)
end

local function merchantShow()
	if IsShiftKeyDown() or Module.NexConfig.automation.AutoRepair == 0 or not CanMerchantRepair() then
		return
	end
	autoRepair()
	Module:RegisterEvent("UI_ERROR_MESSAGE", checkBankFund)
	Module:RegisterEvent("MERCHANT_CLOSED", merchantClose)
end
Module:RegisterEvent("MERCHANT_SHOW", merchantShow)

local repairGossipIDs = {
	[37005] = true, -- Jeeves
	[44982] = true, -- Rüstmeister der Gnomereganen
}

function Module:GOSSIP_SHOW()
	if IsShiftKeyDown() or Module.NexConfig.automation.AutoRepair == 0 or not CanMerchantRepair() then
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
end
