local _, Module = ...

-- Constants
local GARRISON_TYPE = Enum.GarrisonType.Type_7_0_Garrison or Enum.GarrisonType.Type_7_0
local FOLLOWER_TYPE = Enum.GarrisonFollowerType.FollowerType_7_0_GarrisonFollower or Enum.GarrisonFollowerType.FollowerType_7_0

-- Local references for global functions
local GetCurrencyInfo = C_CurrencyInfo.GetCurrencyInfo
local GetClassSpecCategoryInfo = C_Garrison.GetClassSpecCategoryInfo
local GetCurrencyTypes = C_Garrison.GetCurrencyTypes
local RequestClassSpecCategoryInfo = C_Garrison.RequestClassSpecCategoryInfo
local IsShiftKeyDown = IsShiftKeyDown
local hooksecurefunc = hooksecurefunc
local GameTooltip = GameTooltip

-- Utility: Format icon string
local function FormatIcon(texture)
	return string.format("|T%s:12:12:0:0:64:64:5:59:5:59|t ", texture)
end

-- Create the Order Hall Icon
function Module:CreateOrderHallIcon()
	local orderHallIcon = CreateFrame("Frame", "OrderHallIconFrame", UIParent)
	orderHallIcon:SetSize(66, 70)
	orderHallIcon:SetPoint("TOP", 0, -30)
	orderHallIcon:SetFrameStrata("HIGH")
	orderHallIcon:Hide()

	orderHallIcon.Icon = orderHallIcon:CreateTexture(nil, "ARTWORK")
	orderHallIcon.Icon:SetAllPoints()
	local classAtlas = "ClassHall-Circle-" .. UnitClassBase("player")
	orderHallIcon.Icon:SetAtlas(classAtlas, true)

	orderHallIcon.CategoryData = {}

	orderHallIcon:SetScript("OnEnter", function()
		self:ShowOrderHallTooltip(orderHallIcon)
	end)

	orderHallIcon:SetScript("OnLeave", function()
		self:HideOrderHallTooltip()
	end)

	hooksecurefunc(OrderHallCommandBar, "SetShown", function(_, state)
		orderHallIcon:SetShown(state)
	end)

	Module.HideObject(OrderHallCommandBar.CurrencyHitTest)
	Module.HideOption(OrderHallCommandBar)

	Module.CreateMoverFrame(orderHallIcon, nil, true)
	Module.RestoreMoverFrame(orderHallIcon)

	self.IconFrame = orderHallIcon
end

-- Update Order Hall Data
function Module:UpdateOrderHallData()
	RequestClassSpecCategoryInfo(FOLLOWER_TYPE)

	local currencyID = GetCurrencyTypes(GARRISON_TYPE)
	local currencyInfo = GetCurrencyInfo(currencyID)

	if currencyInfo then
		self.CurrencyName = currencyInfo.name
		self.CurrencyAmount = currencyInfo.quantity
		self.CurrencyIcon = currencyInfo.iconFileID
	else
		self.IconFrame:Hide()
		return
	end

	local categoryInfo = GetClassSpecCategoryInfo(FOLLOWER_TYPE)
	self.IconFrame.CategoryData = {}

	for _, data in ipairs(categoryInfo) do
		table.insert(self.IconFrame.CategoryData, {
			name = data.name,
			count = data.count,
			limit = data.limit,
			description = data.description,
			icon = data.icon,
		})
	end
end

-- Show Tooltip for Order Hall Icon
function Module:ShowOrderHallTooltip(frame)
	self:UpdateOrderHallData()

	GameTooltip:SetOwner(frame, "ANCHOR_BOTTOMRIGHT", 5, -5)
	GameTooltip:ClearLines()
	GameTooltip:AddLine(self.MyClassColor .. _G["ORDER_HALL_" .. self.MyClass])
	GameTooltip:AddLine(" ")

	if self.CurrencyName then
		GameTooltip:AddDoubleLine(FormatIcon(self.CurrencyIcon) .. self.CurrencyName, self.CurrencyAmount, 1, 1, 1, 1, 1, 1)
	end

	local hasCategories = false
	for _, category in ipairs(self.IconFrame.CategoryData) do
		if not hasCategories then
			GameTooltip:AddLine(" ")
			hasCategories = true
		end

		GameTooltip:AddDoubleLine(FormatIcon(category.icon) .. category.name, category.count .. "/" .. category.limit, 1, 1, 1, 1, 1, 1)
		if IsShiftKeyDown() then
			GameTooltip:AddLine(category.description, 0.5, 0.7, 1, true)
		end
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("Shift:", "Expand Details", 1, 1, 1, 0.5, 0.7, 1)
	GameTooltip:Show()

	self:RegisterEvent("MODIFIER_STATE_CHANGED", self.OnModifierStateChanged)
end

-- Hide Tooltip
function Module:HideOrderHallTooltip()
	GameTooltip:Hide()
	self:UnregisterEvent("MODIFIER_STATE_CHANGED", self.OnModifierStateChanged)
end

-- Refresh Tooltip on Modifier State Change
function Module:OnModifierStateChanged(_, key)
	if key == "LSHIFT" or key == "RSHIFT" then
		if GameTooltip:IsShown() then
			self:ShowOrderHallTooltip(self.IconFrame)
		end
	end
end

-- Initialize the Order Hall Icon
function Module:InitializeOrderHall()
	if C_AddOns.IsAddOnLoaded("Blizzard_OrderHallUI") then
		self:CreateOrderHallIcon()
	else
		self:RegisterEvent("ADDON_LOADED", function(_, addon)
			if addon == "Blizzard_OrderHallUI" then
				self:CreateOrderHallIcon()
			end
		end)
	end
end

-- Event Handler for PLAYER_LOGIN
function Module:PLAYER_LOGIN()
	self:InitializeOrderHall()
end
