--[[
	NexEnhance - AutoVendor (reference module)
	-------------------------------------------------------------------------
	Demonstrates the full module pattern:
	  * Register defaults at file-run time.
	  * Create the module with a DB key so it gets a free enable/disable.
	  * React to events through the central dispatcher.
	  * Cache globals and keep allocations out of the bag-scanning loop.

	Behaviour: when you open a merchant it auto-repairs (using guild funds if
	allowed and available) and sells Poor (grey) quality items.
--]]

local _, ns = ...
local F, L = ns.F, ns.L

-- Localised API.
local C_Container = C_Container
local CanMerchantRepair = CanMerchantRepair
local GetRepairAllCost = GetRepairAllCost
local RepairAllItems = RepairAllItems
local CanGuildBankRepair = CanGuildBankRepair
local GetGuildBankWithdrawMoney = GetGuildBankWithdrawMoney
local GetMoney = GetMoney
local IsInGuild = IsInGuild
local format = string.format

local NUM_BAG_SLOTS = NUM_BAG_SLOTS
local BACKPACK_CONTAINER = BACKPACK_CONTAINER

-- ---------------------------------------------------------------------------
-- Defaults & module
-- ---------------------------------------------------------------------------
ns:RegisterDefaults({
	autoVendor = {
		enable = true,
		autoRepair = true,
		useGuildFunds = true,
		sellJunk = true,
	},
})

local AutoVendor = ns:NewModule("AutoVendor", "autoVendor", { group = "automation", title = L["Auto Vendor"], order = 10 })

-- ---------------------------------------------------------------------------
-- Selling
-- ---------------------------------------------------------------------------
local POOR_QUALITY = Enum.ItemQuality.Poor -- 0

function AutoVendor:SellJunk()
	if not ns.db.autoVendor.sellJunk then return end

	local profit = 0
	for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			-- Sell only Poor items that have a vendor value and are not locked.
			if info and info.quality == POOR_QUALITY and not info.hasNoValue and not info.isLocked then
				C_Container.UseContainerItem(bag, slot)
				-- Stack vendor value is not exposed here directly; the gold is
				-- still credited by the server. We only report that we sold.
				profit = profit + 1
			end
		end
	end

	if profit > 0 then
		F.Print(format(L["Sold junk for %s"], F.Colorize(tostring(profit) .. " items", "yellow")))
	end
end

-- ---------------------------------------------------------------------------
-- Repairing
-- ---------------------------------------------------------------------------
function AutoVendor:Repair()
	local db = ns.db.autoVendor
	if not db.autoRepair or not CanMerchantRepair() then return end

	local cost, canRepair = GetRepairAllCost()
	if not canRepair or cost <= 0 then return end

	-- Prefer guild funds when allowed and the guild bank can cover it.
	if db.useGuildFunds and IsInGuild() and CanGuildBankRepair() and GetGuildBankWithdrawMoney() >= cost then
		RepairAllItems(true)
		F.Print(format(L["Repaired equipment using guild funds for %s"], F.FormatMoney(cost)))
		return
	end

	if GetMoney() >= cost then
		RepairAllItems(false)
		F.Print(format(L["Repaired equipment for %s"], F.FormatMoney(cost)))
	else
		F.Print(F.Colorize(L["Not enough money to repair"], "red"))
	end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
function AutoVendor:MERCHANT_SHOW()
	if not self:IsEnabled() then return end

	self:Repair()
	self:SellJunk()
end

function AutoVendor:OnSettingChanged(key, value)
	if key == "enable" and value then
		self:RegisterModuleEvents()
	end
end

function AutoVendor:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Auto Vendor"], L["Automatically sell junk and repair when opening a merchant."])
	builder:Checkbox(category, self, "autoRepair", L["Auto Repair"], L["Repair equipment when opening a merchant that can repair."])
	builder:Checkbox(category, self, "useGuildFunds", L["Use Guild Repairs"], L["Use guild repair funds when available and allowed."])
	builder:Checkbox(category, self, "sellJunk", L["Sell Junk"], L["Sell Poor-quality items when opening a merchant."])
end

function AutoVendor:RegisterModuleEvents()
	if self.eventsRegistered then return end
	self.eventsRegistered = true

	self:RegisterEvent("MERCHANT_SHOW")
end

function AutoVendor:OnEnable()
	self:RegisterModuleEvents()
end
