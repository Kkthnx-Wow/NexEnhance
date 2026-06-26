--[[
	NexEnhance - Auto Warband Gold Sync
	-------------------------------------------------------------------------
	Automatically manages your gold by sync'ing it with your account-wide
	Warband bank when you open the bank frame. 

	Let's be honest: Warband banks are the best thing Blizzard has added in years,
	but manually typing in deposit/withdraw amounts on every alt is a mind-numbing
	chore. We automate this flow by enforcing a character gold threshold.

	If you have more gold than your target, the surplus is deposited. If you're
	running low, we automatically pull gold out of the Warband bank to top you off,
	assuming you've checked the "Allow Withdraw" box (safety first, we don't want
	an alt draining your shared savings by default!).

	Adapted from the sync feature in EnhanceQoL.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local F, L = ns.F, ns.L

local C_Bank = C_Bank
local Enum = Enum
local GetMoney = GetMoney
local C_Timer_After = C_Timer.After

local COPPER_PER_GOLD = 10000

ns:RegisterDefaults({
	autoWarbandGold = {
		enable = false,
		targetGold = 10000,
		allowWithdraw = false,
	},
})

local AutoWarbandGold = ns:NewModule("AutoWarbandGold", "autoWarbandGold", { group = "automation", title = L["Auto Warband Gold"], order = 120 })

local function AutoSync()
	if not ns.db.autoWarbandGold.enable then
		return
	end

	local bankType = Enum.BankType and Enum.BankType.Account
	if not bankType then
		-- No account bank type? Maybe running on a weird client flavour. Bail.
		return
	end

	-- Verify the API is ready and transfer is actually supported.
	if not C_Bank.DoesBankTypeSupportMoneyTransfer or not C_Bank.DoesBankTypeSupportMoneyTransfer(bankType) then
		return
	end
	if not C_Bank.CanUseBank or not C_Bank.CanUseBank(bankType) then
		return
	end

	local targetGold = tonumber(ns.db.autoWarbandGold.targetGold) or 10000
	if targetGold < 0 then
		targetGold = 0
	end
	local targetCopper = math.floor((targetGold * COPPER_PER_GOLD) + 0.5)
	local playerMoney = GetMoney() or 0

	if playerMoney > targetCopper then
		-- We have more gold than our target threshold. Deposit the excess.
		if not C_Bank.CanDepositMoney or not C_Bank.CanDepositMoney(bankType) then
			return
		end
		local amountToDeposit = playerMoney - targetCopper
		if amountToDeposit <= 0 then
			return
		end

		C_Bank.DepositMoney(bankType, amountToDeposit)

		-- Use F.Print and F.FormatMoney for local consistency.
		F.Print((L["Deposited %s to Warband bank."]):format(F.FormatMoney(amountToDeposit)))
		return
	end

	-- Below threshold: pull gold out of the shared bank if allowed.
	if not ns.db.autoWarbandGold.allowWithdraw then
		return
	end
	if playerMoney >= targetCopper then
		return
	end
	if not C_Bank.CanWithdrawMoney or not C_Bank.CanWithdrawMoney(bankType) then
		return
	end

	local warbandMoney = C_Bank.FetchDepositedMoney and C_Bank.FetchDepositedMoney(bankType) or 0
	local amountToWithdraw = math.min(targetCopper - playerMoney, warbandMoney)
	if amountToWithdraw <= 0 then
		return
	end

	C_Bank.WithdrawMoney(bankType, amountToWithdraw)
	F.Print((L["Withdrew %s from Warband bank."]):format(F.FormatMoney(amountToWithdraw)))
end

function AutoWarbandGold:BANKFRAME_OPENED()
	-- Give the client a brief moment to update its gold cache after opening the bank.
	C_Timer_After(0.1, AutoSync)
end

function AutoWarbandGold:RegisterModuleEvents()
	if self.eventsRegistered then
		return
	end
	self.eventsRegistered = true

	self:RegisterEvent("BANKFRAME_OPENED")
end

function AutoWarbandGold:UnregisterModuleEvents()
	if not self.eventsRegistered then
		return
	end
	self.eventsRegistered = false

	ns:UnregisterEvent("BANKFRAME_OPENED", self.BANKFRAME_OPENED)
end

function AutoWarbandGold:OnSettingChanged(key, value)
	if key ~= "enable" then
		return
	end
	if value then
		self:RegisterModuleEvents()
	else
		self:UnregisterModuleEvents()
	end
end

function AutoWarbandGold:OnEnable()
	if ns.db.autoWarbandGold.enable then
		self:RegisterModuleEvents()
	end
end

function AutoWarbandGold:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Auto Warband Gold"], L["Automatically sync gold with your Account/Warband bank when opening the Bank Frame."])
	local _, targetInit = builder:Slider(category, self, "targetGold", L["Target Gold"], L["The amount of gold to keep on your character. Gold above this amount is deposited; if below, gold is withdrawn (if allowed)."], 100, 1000000, 100, "%d")
	local _, allowInit = builder:Checkbox(category, self, "allowWithdraw", L["Allow Withdraw"], L["Allow withdrawing gold from the Warband bank if your character has less than the target amount."])

	builder:DependsOn(targetInit, enableInit)
	builder:DependsOn(allowInit, enableInit)
end
