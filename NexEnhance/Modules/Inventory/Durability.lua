--[[
	NexEnhance - Durability
	-------------------------------------------------------------------------
	Attaches a small, non-interactive tab to the bottom of the Character pane
	showing the lowest equipped-item durability. Hovering it lists the
	durability of every damaged slot plus the total repair cost, and a HelpTip
	nudges you when any piece drops below 25%.

	Adapted to the NexEnhance architecture from KkthnxUI's DataText/Durability
	(by Josh "Kkthnx" Russell):
	  https://github.com/Kkthnx-Wow/KkthnxUI/blob/master/KkthnxUI/Modules/DataText/Elements/Durability.lua

	K.* helpers are replaced with our framework equivalents:
	  * K.RGBToHex          -> F.ColorStr
	  * K.RGBColorGradient  -> local DurabilityColor (red -> yellow -> green)
	  * K.FormatMoney       -> F.FormatMoney
	  * K.MyClassColor      -> F.ColorStr(F.UnitColor("player"))
--]]

---@diagnostic disable: undefined-field

local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

-- Shared tooltip palette (single source of truth in Constants.lua): gold section
-- headers, light-blue labels, white values.
local HDR = C.Colors.header
local LBL = C.Colors.label

-- Localised globals / API.
local _G = _G
local ipairs, pairs = ipairs, pairs
local floor = math.floor
local format, gsub = string.format, string.gsub
local tsort = table.sort

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local GetAverageItemLevel = GetAverageItemLevel
local GetInventoryItemDurability = GetInventoryItemDurability
local GetInventoryItemLink = GetInventoryItemLink
local GetInventoryItemTexture = GetInventoryItemTexture
local GetRepairAllCost = GetRepairAllCost
local C_TooltipInfo_GetInventoryItem = C_TooltipInfo and C_TooltipInfo.GetInventoryItem

local DURABILITY = _G.DURABILITY
local NONE = _G.NONE
local STAT_AVERAGE_ITEM_LEVEL = _G.STAT_AVERAGE_ITEM_LEVEL
local repairCostString = gsub(_G.REPAIR_COST, _G.HEADER_COLON, ":")
local LOW_DURABILITY_CAP = 0.25

ns:RegisterDefaults({
	durability = {
		enable = true,
	},
})

local Durability = ns:NewModule("Durability", "durability", { group = "inventory", title = L["Durability"], order = 20 })

-- Slot id, localised label, durability fraction (0-1, defaults 1000 = "unset"),
-- icon escape string. Re-sorted each scan so index 1 is always the worst slot.
local slots = {
	{ 1, _G.INVTYPE_HEAD, 1000 },
	{ 3, _G.INVTYPE_SHOULDER, 1000 },
	{ 5, _G.INVTYPE_CHEST, 1000 },
	{ 6, _G.INVTYPE_WAIST, 1000 },
	{ 9, _G.INVTYPE_WRIST, 1000 },
	{ 10, _G.INVTYPE_HAND, 1000 },
	{ 7, _G.INVTYPE_LEGS, 1000 },
	{ 8, _G.INVTYPE_FEET, 1000 },
	{ 16, _G.INVTYPE_WEAPONMAINHAND, 1000 },
	{ 17, _G.INVTYPE_WEAPONOFFHAND, 1000 },
}

local button -- the tab widget (created lazily on enable)
local paperDollHooked
local retryScheduled

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
-- 3-stop gradient (red @ 0% -> yellow @ 50% -> green @ 100%). `percent` is 0-100.
local function DurabilityColor(percent)
	local p = percent / 100
	if p <= 0 then
		return 1, 0, 0
	end
	if p >= 1 then
		return 0, 1, 0
	end
	if p <= 0.5 then
		return 1, p / 0.5, 0
	end
	return 1 - (p - 0.5) / 0.5, 1, 0
end

local function SortSlots(a, b)
	if a and b then
		return (a[3] == b[3] and a[1] < b[1]) or (a[3] < b[3])
	end
end

-- Per-slot repair cost from C_TooltipInfo.GetInventoryItem (12.0.7: repairCost lives
-- on TooltipData itself; TooltipDataRules.FinalizeItemTooltip reads tooltipData.repairCost).
local function GetSlotRepairCost(slot)
	if not C_TooltipInfo_GetInventoryItem then
		return nil
	end
	local data = C_TooltipInfo_GetInventoryItem("player", slot)
	if not data then
		return nil
	end

	local cost = data.repairCost
	if cost and F.NotSecret(cost) and cost > 0 then
		return cost
	end

	if data.args then
		for _, arg in ipairs(data.args) do
			if arg.field == "repairCost" and arg.intVal and F.NotSecret(arg.intVal) and arg.intVal > 0 then
				return arg.intVal
			end
		end
	end
	if data.lines then
		for _, line in ipairs(data.lines) do
			if line.args then
				for _, arg in ipairs(line.args) do
					if arg.field == "repairCost" and arg.intVal and F.NotSecret(arg.intVal) and arg.intVal > 0 then
						return arg.intVal
					end
				end
			end
		end
	end
	return nil
end

-- Total equipped repair bill; same API the merchant Repair All button uses.
local function GetTotalRepairCost()
	local total, canRepair = GetRepairAllCost()
	if canRepair and total and F.NotSecret(total) and total > 0 then
		return total
	end
	return nil
end

local function UpdateAllSlots()
	local numSlots = 0
	for i = 1, #slots do
		slots[i][3] = 1000
		local index = slots[i][1]
		if GetInventoryItemLink("player", index) then
			local current, max = GetInventoryItemDurability(index)
			if current and max and F.NotSecret(current) and F.NotSecret(max) and max > 0 then
				slots[i][3] = current / max
				numSlots = numSlots + 1
			end
			local iconTexture = GetInventoryItemTexture("player", index) or 134400
			slots[i][4] = "|T" .. iconTexture .. ":13:15:0:0:50:50:4:46:4:46|t "
		end
	end
	tsort(slots, SortSlots)
	return numSlots
end

local function HasLowDurability()
	for i = 1, #slots do
		if slots[i][3] < LOW_DURABILITY_CAP then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- HelpTip (low-durability nudge)
-- ---------------------------------------------------------------------------
local function HideAlertWhileCombat()
	if InCombatLockdown() and button then
		button:RegisterEvent("PLAYER_REGEN_ENABLED")
		button:UnregisterEvent("UPDATE_INVENTORY_DURABILITY")
	end
end

local lowDurabilityInfo
local function GetLowDurabilityInfo()
	if not lowDurabilityInfo then
		local HelpTip = _G.HelpTip
		if not HelpTip then
			return nil
		end
		lowDurabilityInfo = {
			text = L["DurabilityHelpTip"],
			buttonStyle = HelpTip.ButtonStyle.Okay,
			targetPoint = HelpTip.Point.TopEdgeCenter,
			onAcknowledgeCallback = HideAlertWhileCombat,
			offsetY = 10,
		}
	end
	return lowDurabilityInfo
end

-- ---------------------------------------------------------------------------
-- Scripts
-- ---------------------------------------------------------------------------
local function OnEvent(self, event)
	local numSlots = UpdateAllSlots()
	local isLow = HasLowDurability()

	if event == "PLAYER_REGEN_ENABLED" then
		self:UnregisterEvent(event)
		self:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
	end

	if self.Text then
		if numSlots > 0 then
			local percent = floor(slots[1][3] * 100)
			local color = F.ColorStr(DurabilityColor(percent))
			self.Text:SetFormattedText("%s%d%%|r |cFFF0C500%s|r", color, percent, DURABILITY)
		else
			self.Text:SetFormattedText("%s: %s%s|r", DURABILITY, F.ColorStr(F.UnitColor("player")), NONE)
		end
	end

	local HelpTip = _G.HelpTip
	if HelpTip and not InCombatLockdown() then
		if isLow then
			local info = GetLowDurabilityInfo()
			if info then
				HelpTip:Show(self, info)
			end
		else
			HelpTip:Hide(self, L["DurabilityHelpTip"])
		end
	end
end

local function OnEnter(self)
	UpdateAllSlots()

	local totalItemLevel, equippedItemLevel = GetAverageItemLevel()
	GameTooltip:SetOwner(self, "ANCHOR_NONE")
	GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPRIGHT", 0, 0)
	GameTooltip:AddDoubleLine(DURABILITY, format("%s: %d/%d", STAT_AVERAGE_ITEM_LEVEL, equippedItemLevel, totalItemLevel), HDR[1], HDR[2], HDR[3], 1, 1, 1)
	GameTooltip:AddLine(" ")

	local slotCostSum = 0
	for i = 1, #slots do
		if slots[i][3] ~= 1000 then
			local curPercent = floor(slots[i][3] * 100)
			local slotIcon = slots[i][4] or ""
			local slotCost = GetSlotRepairCost(slots[i][1])
			local dr, dg, db = DurabilityColor(curPercent)
			local rightText = format("%s%d%%|r", F.ColorStr(dr, dg, db), curPercent)
			if slotCost then
				slotCostSum = slotCostSum + slotCost
				rightText = rightText .. "  |cffffffff" .. F.FormatMoney(slotCost) .. "|r"
			end
			GameTooltip:AddDoubleLine(slotIcon .. slots[i][2], rightText, 1, 1, 1, 1, 1, 1)
		end
	end

	local totalCost = GetTotalRepairCost() or (slotCostSum > 0 and slotCostSum or nil)
	if totalCost then
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine(repairCostString, F.FormatMoney(totalCost), LBL[1], LBL[2], LBL[3], 1, 1, 1)
	end

	GameTooltip:Show()
end

local function OnLeave()
	GameTooltip:Hide()
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
local function RefreshTab()
	if button then
		OnEvent(button, "UPDATE_INVENTORY_DURABILITY")
	end
end

function Durability:Create()
	if button then
		-- Re-arm after a previous disable left the events unregistered.
		button:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
		button:Show()
		RefreshTab()
		return true
	end

	local PaperDollFrame = _G.PaperDollFrame
	if not PaperDollFrame then
		return false
	end

	button = CreateFrame("Button", "NexEnhanceDurability", PaperDollFrame, "PanelTabButtonTemplate")
	button:SetPoint("TOP", PaperDollFrame, "BOTTOM", 214, 3)
	button:SetFrameLevel(PaperDollFrame:GetFrameLevel() + 2)
	button:Disable()

	-- Drop Blizzard's "selected tab" textures so the tab reads as a flat label.
	for _, region in pairs({ "LeftActive", "MiddleActive", "RightActive" }) do
		if button[region] then
			button[region]:Hide()
		end
	end

	button:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
	button:SetScript("OnEvent", OnEvent)
	button:SetScript("OnEnter", OnEnter)
	button:SetScript("OnLeave", OnLeave)

	if not paperDollHooked then
		paperDollHooked = true
		PaperDollFrame:HookScript("OnShow", RefreshTab)
	end

	RefreshTab()
	return true
end

-- Bootstrap the tab and refresh its label. Module-level events cover the login
-- race where PLAYER_ENTERING_WORLD fires before OnEnable, and
-- UPDATE_INVENTORY_ALERTS (Blizzard's minimap durability frame) covers the
-- initial population that UPDATE_INVENTORY_DURABILITY alone does not send.
function Durability:Bootstrap()
	if not ns.db.durability.enable then
		return
	end

	if not self:Create() and not retryScheduled then
		retryScheduled = true
		C_Timer.After(0.5, function()
			retryScheduled = false
			Durability:Bootstrap()
		end)
		return
	end

	RefreshTab()
end

function Durability:OnEnable()
	if not ns.db.durability.enable then
		return
	end
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "Bootstrap")
	self:RegisterEvent("UPDATE_INVENTORY_ALERTS", "Bootstrap")
	self:RegisterEvent("UPDATE_INVENTORY_DURABILITY", "Bootstrap")
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "Bootstrap")
	self:Bootstrap()
	C_Timer.After(0, function()
		Durability:Bootstrap()
	end)
end

function Durability:OnSettingChanged(key, value)
	if key ~= "enable" then
		return
	end
	if value then
		self:Bootstrap()
	elseif button then
		-- Go fully idle: a hidden tab shouldn't keep processing durability events.
		button:UnregisterAllEvents()
		button:Hide()
		_G.HelpTip:Hide(button, L["DurabilityHelpTip"])
	end
end

function Durability:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Show Durability Information"], L["Display the lowest equipped-item durability on the Character pane, with a per-slot repair-cost tooltip."])
end
