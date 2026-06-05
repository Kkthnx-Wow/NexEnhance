--[[
	NexEnhance - AutoVendor
	-------------------------------------------------------------------------
	When you open a merchant this:
	  * auto-repairs, preferring guild funds (with a fallback to your own gold
	    if the guild bank comes up short), and
	  * sells Poor-quality items plus anything on your custom junk list, one
	    item at a time so the client never throttles the sell stream.

	It also auto-selects the "repair" gossip option on repair NPCs (e.g. the
	stable repair handlers) when your gear is actually damaged.

	Selling/repair logic adapted from NDui by siweia:
	  https://github.com/siweia/NDui

	Hold Shift while opening a merchant to skip both selling and repairing.
--]]

-- luacheck: globals LE_GAME_ERR_GUILD_NOT_ENOUGH_MONEY LE_GAME_ERR_VENDOR_DOESNT_BUY
---@diagnostic disable: undefined-global, inject-field
local _, ns = ...
local F, L = ns.F, ns.L

local _G = _G
local pairs, tonumber = pairs, tonumber
local format = string.format
local wipe = wipe

local C_Container = C_Container
local C_Container_GetContainerNumSlots = C_Container.GetContainerNumSlots
local C_Container_GetContainerItemInfo = C_Container.GetContainerItemInfo
local C_Container_UseContainerItem = C_Container.UseContainerItem
local C_Timer_After = C_Timer.After
local C_GossipInfo = C_GossipInfo
local C_Item_GetItemInfo = C_Item.GetItemInfo
local GetItemInfoFromHyperlink = GetItemInfoFromHyperlink
local CanMerchantRepair = CanMerchantRepair
local GetRepairAllCost = GetRepairAllCost
local RepairAllItems = RepairAllItems
local CanGuildBankRepair = CanGuildBankRepair
local GetGuildBankWithdrawMoney = GetGuildBankWithdrawMoney
local GetMoney = GetMoney
local IsInGuild = IsInGuild
local IsShiftKeyDown = IsShiftKeyDown
local GetInventoryItemDurability = GetInventoryItemDurability

local NUM_BAG_SLOTS = NUM_BAG_SLOTS
local BACKPACK_CONTAINER = BACKPACK_CONTAINER
local POOR_QUALITY = Enum.ItemQuality.Poor -- 0
local GUILD_NOT_ENOUGH = LE_GAME_ERR_GUILD_NOT_ENOUGH_MONEY
local VENDOR_DOESNT_BUY = LE_GAME_ERR_VENDOR_DOESNT_BUY

-- Grey-looking items that double as a currency or are otherwise worth keeping;
-- protected from the junk sweep when "keepPetTrash" is on (mirrors NDui).
local petTrashCurrencies = {
	[3300] = true, [3670] = true, [6150] = true, [11406] = true, [11944] = true,
	[25402] = true, [36812] = true, [62072] = true, [67410] = true,
}

-- Repair-on-gossip NPCs (select their repair option automatically).
local repairGossipIDs = {
	[37005] = true,
	[44982] = true,
}

-- ---------------------------------------------------------------------------
-- Defaults & module
-- ---------------------------------------------------------------------------
ns:RegisterDefaults({
	autoVendor = {
		enable = true,
		autoRepair = true,
		useGuildFunds = true,
		sellJunk = true,
		keepPetTrash = true,
	},
})
ns:RegisterDefaults({ autoVendor = { junkList = {} } }, "global")

local AutoVendor = ns:NewModule("AutoVendor", "autoVendor", { group = "automation", title = L["Auto Vendor"], order = 10 })

-- ---------------------------------------------------------------------------
-- Selling (throttled + stop-on-error)
-- ---------------------------------------------------------------------------
local sellStop = true
local sellCache = {}

local function IsPetTrash(itemID)
	return ns.db.autoVendor.keepPetTrash and petTrashCurrencies[itemID]
end

local function StartSelling()
	if sellStop then return end

	local junkList = ns.global.autoVendor.junkList
	for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
		for slot = 1, C_Container_GetContainerNumSlots(bag) do
			if sellStop then return end

			local info = C_Container_GetContainerItemInfo(bag, slot)
			if info and not info.hasNoValue then
				local itemID = info.itemID
				local key = bag * 100 + slot
				if not sellCache[key]
					and (info.quality == POOR_QUALITY or junkList[itemID])
					and not IsPetTrash(itemID)
				then
					sellCache[key] = true
					C_Container_UseContainerItem(bag, slot)
					-- One item per tick; the server credits the gold for us.
					C_Timer_After(0.15, StartSelling)
					return
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Repairing
-- ---------------------------------------------------------------------------
local repairShown, isBankEmpty, repairAllCost, canRepair

local function NeedToRepair()
	for slot = 1, 18 do
		local cur, max = GetInventoryItemDurability(slot)
		if cur and max and max > 0 and cur < max then
			return true
		end
	end
	return false
end

local function ReportGuildRepair()
	if isBankEmpty then
		-- Guild bank could not cover it; fall back to personal funds.
		AutoVendor:Repair(true)
	else
		F.Print(format(L["Repaired equipment using guild funds for %s"], F.FormatMoney(repairAllCost)))
	end
end

function AutoVendor:Repair(override)
	local db = ns.db.autoVendor
	if not db.autoRepair then return end
	if repairShown and not override then return end
	repairShown = true
	isBankEmpty = false

	repairAllCost, canRepair = GetRepairAllCost()
	if not canRepair or repairAllCost <= 0 then return end

	if (not override) and db.useGuildFunds and IsInGuild() and CanGuildBankRepair() and GetGuildBankWithdrawMoney() >= repairAllCost then
		RepairAllItems(true)
		-- Wait for a possible "not enough guild money" error, then confirm.
		C_Timer_After(0.5, ReportGuildRepair)
	elseif GetMoney() >= repairAllCost then
		RepairAllItems(false)
		F.Print(format(L["Repaired equipment for %s"], F.FormatMoney(repairAllCost)))
	else
		F.Print(F.Colorize(L["Not enough money to repair"], "red"))
	end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
function AutoVendor:MERCHANT_SHOW()
	if not self:IsEnabled() then return end
	if IsShiftKeyDown() then return end

	if CanMerchantRepair() then
		self:Repair()
	end

	if ns.db.autoVendor.sellJunk then
		sellStop = false
		wipe(sellCache)
		StartSelling()
	end
end

function AutoVendor:MERCHANT_CLOSED()
	sellStop = true
	repairShown = false
end

function AutoVendor:UI_ERROR_MESSAGE(errorType)
	if errorType == GUILD_NOT_ENOUGH then
		isBankEmpty = true
	elseif errorType == VENDOR_DOESNT_BUY then
		sellStop = true
	end
end

function AutoVendor:GOSSIP_SHOW()
	if not self:IsEnabled() then return end
	if not ns.db.autoVendor.autoRepair then return end
	if IsShiftKeyDown() or not NeedToRepair() then return end

	local options = C_GossipInfo.GetOptions()
	for i = 1, #options do
		local option = options[i]
		if repairGossipIDs[option.gossipOptionID] then
			C_GossipInfo.SelectOption(option.gossipOptionID)
			return
		end
	end
end

-- ---------------------------------------------------------------------------
-- Custom junk list (/nexjunk)
-- ---------------------------------------------------------------------------
local function ResolveItemID(arg)
	if not arg or arg == "" then return end
	local id = tonumber(arg)
	if id then return id end
	return GetItemInfoFromHyperlink(arg)
end

local function HandleJunkCommand(input)
	local list = ns.global.autoVendor.junkList
	local cmd, rest = (input or ""):match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()

	if cmd == "add" then
		local id = ResolveItemID(rest)
		if id then
			list[id] = true
			F.Print(format(L["Added %s to the junk list."], (C_Item_GetItemInfo(id)) or id))
		else
			F.Print(L["Usage: /nexjunk add <item link or id>"])
		end
	elseif cmd == "del" or cmd == "remove" then
		local id = ResolveItemID(rest)
		if id and list[id] then
			list[id] = nil
			F.Print(format(L["Removed %s from the junk list."], (C_Item_GetItemInfo(id)) or id))
		end
	elseif cmd == "clear" then
		wipe(list)
		F.Print(L["Cleared the junk list."])
	else
		F.Print(F.Colorize(L["Custom Junk List"] .. ":", "brand"))
		local empty = true
		for id in pairs(list) do
			empty = false
			F.Print(" -", (C_Item_GetItemInfo(id)) or id)
		end
		if empty then
			F.Print(L["The junk list is empty."])
		end
		F.Print(L["Usage: /nexjunk add <item link or id>"])
	end
end

-- ---------------------------------------------------------------------------
-- Options & lifecycle
-- ---------------------------------------------------------------------------
function AutoVendor:OnSettingChanged(key, value)
	if key == "enable" and value then
		self:RegisterModuleEvents()
	end
end

function AutoVendor:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Auto Vendor"], L["Automatically sell junk and repair when opening a merchant."])
	local _, repairInit = builder:Checkbox(category, self, "autoRepair", L["Auto Repair"], L["Repair equipment when opening a merchant that can repair."])
	local _, guildFundsInit = builder:Checkbox(category, self, "useGuildFunds", L["Use Guild Repairs"], L["Use guild repair funds when available, falling back to your own gold."])
	local _, junkInit = builder:Checkbox(category, self, "sellJunk", L["Sell Junk"], L["Sell Poor-quality items, plus anything on your /nexjunk list, one at a time."])
	local _, petTrashInit = builder:Checkbox(category, self, "keepPetTrash", L["Protect Pet Trash"], L["Never auto-sell the handful of grey items that double as a currency."])

	builder:DependsOn(repairInit, enableInit)
	builder:DependsOn(guildFundsInit, repairInit) -- guild repairs only matter if repairing
	builder:DependsOn(junkInit, enableInit)
	builder:DependsOn(petTrashInit, junkInit) -- pet-trash protection only matters if selling junk
end

function AutoVendor:RegisterModuleEvents()
	if self.eventsRegistered then return end
	self.eventsRegistered = true

	self:RegisterEvent("MERCHANT_SHOW")
	self:RegisterEvent("MERCHANT_CLOSED")
	self:RegisterEvent("UI_ERROR_MESSAGE")
	self:RegisterEvent("GOSSIP_SHOW")
end

function AutoVendor:OnEnable()
	---@diagnostic disable-next-line: undefined-field
	_G.SlashCmdList["NEXJUNK"] = HandleJunkCommand
	_G.SLASH_NEXJUNK1 = "/nexjunk"

	self:RegisterModuleEvents()
end
