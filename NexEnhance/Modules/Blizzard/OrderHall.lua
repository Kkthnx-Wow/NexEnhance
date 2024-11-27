local _, Module = ...

-- Constants
local LE_GARRISON_TYPE_7_0 = Enum.GarrisonType.Type_7_0_Garrison or Enum.GarrisonType.Type_7_0
local LE_FOLLOWER_TYPE_GARRISON_7_0 = Enum.GarrisonFollowerType.FollowerType_7_0_GarrisonFollower or Enum.GarrisonFollowerType.FollowerType_7_0

-- Local references for global functions
local C_CurrencyInfo_GetCurrencyInfo = C_CurrencyInfo.GetCurrencyInfo
local C_Garrison_GetClassSpecCategoryInfo = C_Garrison.GetClassSpecCategoryInfo
local C_Garrison_GetCurrencyTypes = C_Garrison.GetCurrencyTypes
local C_Garrison_RequestClassSpecCategoryInfo = C_Garrison.RequestClassSpecCategoryInfo
local IsShiftKeyDown = IsShiftKeyDown
local hooksecurefunc = hooksecurefunc
local GameTooltip = GameTooltip

-- Utility: Format icon string
local function GetIconString(texture)
	return string.format("|T%s:12:12:0:0:64:64:5:59:5:59|t ", texture)
end

-- Create the Order Hall icon frame
function Module:CreateOrderHallIcon()
	local hall = CreateFrame("Frame", "NE_OrderHallIcon", UIParent)
	hall:SetSize(66, 70)
	hall:SetPoint("TOP", 0, -30)
	hall:SetFrameStrata("HIGH")
	hall:Hide()

	-- Create and set the class-specific atlas texture
	hall.Icon = hall:CreateTexture(nil, "ARTWORK")
	hall.Icon:SetAllPoints()
	local classAtlasName = "ClassHall-Circle-" .. UnitClassBase("player")
	hall.Icon:SetAtlas(classAtlasName, true)

	hall.Category = {}

	hall:SetScript("OnEnter", function()
		self:OnIconEnter(hall)
	end)

	hall:SetScript("OnLeave", function()
		self:OnIconLeave()
	end)

	hooksecurefunc(OrderHallCommandBar, "SetShown", function(_, state)
		hall:SetShown(state)
	end)

	Module.HideObject(OrderHallCommandBar.CurrencyHitTest)
	Module.HideOption(OrderHallCommandBar)

	Module.CreateMoverFrame(hall, nil, true)
	Module.RestoreMoverFrame(hall)

	self.IconFrame = hall
end

-- Refresh Order Hall data
function Module:RefreshOrderHallData()
	C_Garrison_RequestClassSpecCategoryInfo(LE_FOLLOWER_TYPE_GARRISON_7_0)
	local currencyID = C_Garrison_GetCurrencyTypes(LE_GARRISON_TYPE_7_0)
	local currencyInfo = C_CurrencyInfo_GetCurrencyInfo(currencyID)

	if currencyInfo then
		self.CurrencyName = currencyInfo.name
		self.CurrencyAmount = currencyInfo.quantity
		self.CurrencyIcon = currencyInfo.iconFileID
	else
		self.IconFrame:Hide()
		return
	end

	local categories = C_Garrison_GetClassSpecCategoryInfo(LE_FOLLOWER_TYPE_GARRISON_7_0)
	self.IconFrame.Category = {}
	for _, info in ipairs(categories) do
		table.insert(self.IconFrame.Category, {
			name = info.name,
			count = info.count,
			limit = info.limit,
			description = info.description,
			icon = info.icon,
		})
	end
end

-- Tooltip for the Order Hall Icon
function Module:OnIconEnter(frame)
	self:RefreshOrderHallData()

	GameTooltip:SetOwner(frame, "ANCHOR_BOTTOMRIGHT", 5, -5)
	GameTooltip:ClearLines()
	GameTooltip:AddLine(self.MyClassColor .. _G["ORDER_HALL_" .. self.MyClass])
	GameTooltip:AddLine(" ")

	-- Add currency info
	if self.CurrencyName then
		GameTooltip:AddDoubleLine(GetIconString(self.CurrencyIcon) .. self.CurrencyName, self.CurrencyAmount, 1, 1, 1, 1, 1, 1)
	end

	-- Add categories
	local hasCategories = false
	for _, category in ipairs(self.IconFrame.Category) do
		if not hasCategories then
			GameTooltip:AddLine(" ")
			hasCategories = true
		end
		GameTooltip:AddDoubleLine(GetIconString(category.icon) .. category.name, category.count .. "/" .. category.limit, 1, 1, 1, 1, 1, 1)
		if IsShiftKeyDown() then
			GameTooltip:AddLine(category.description, 0.5, 0.7, 1, true)
		end
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("Shift:", "Expand Details", 1, 1, 1, 0.5, 0.7, 1)
	GameTooltip:Show()

	self:RegisterEvent("MODIFIER_STATE_CHANGED", self.OnShiftKeyChange)
end

-- Hide the tooltip
function Module:OnIconLeave()
	GameTooltip:Hide()
	self:UnregisterEvent("MODIFIER_STATE_CHANGED", self.OnShiftKeyChange)
end

-- Refresh tooltip when shift key is pressed
function Module:OnShiftKeyChange(_, key)
	if key == "LSHIFT" then
		self:OnIconEnter(self.IconFrame)
	end
end

-- Load the Order Hall icon after the Blizzard_OrderHallUI addon is loaded
function Module:OnAddonLoaded(addon)
	if addon == "Blizzard_OrderHallUI" then
		self:CreateOrderHallIcon()
		self:UnregisterEvent("ADDON_LOADED", self.OnAddonLoaded)
	end
end

-- Initialize the module
function Module:Initialize()
	if C_AddOns.IsAddOnLoaded("Blizzard_OrderHallUI") then
		self:CreateOrderHallIcon()
	else
		self:RegisterEvent("ADDON_LOADED", self.OnAddonLoaded)
	end
end

-- Register initialization for PLAYER_LOGIN
function Module:PLAYER_LOGIN()
	self:Initialize()
end
