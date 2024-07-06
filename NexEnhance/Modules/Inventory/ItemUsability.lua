local _, Module = ...
Module.LibUnfit = LibStub("Unfit-1.0")

local select = select
local C_Container_GetContainerItemInfo = C_Container.GetContainerItemInfo
local GetItemInfo = C_Item.GetItemInfo or GetItemInfo

function Module:IsItemUsable_Containers()
	for i = 1, 13 do
		local containerFrame = _G["ContainerFrame" .. i]
		for _, button in containerFrame:EnumerateItems() do
			button.IconBorder.__owner = button
			hooksecurefunc(button.IconBorder, "SetShown", Module.IsItemUsable_UpdateBags)
		end
	end

	for i = 1, 28 do
		local button = _G["BankFrameItem" .. i]
		button.IconBorder.__owner = button
		hooksecurefunc(button.IconBorder, "SetShown", Module.IsItemUsable_UpdateBags)
	end
end

function Module:IsItemUsable_UpdateBags()
	local button = self.__owner
	if not button.usableTexture then
		button.usableTexture = button:CreateTexture(nil, "ARTWORK")
		button.usableTexture:SetTexture(Module.White8x8)
		button.usableTexture:SetAllPoints(button)
		button.usableTexture:SetVertexColor(1, 0, 0)
		button.usableTexture:SetBlendMode("MOD")
		button.usableTexture:Hide() -- Initialize as hidden
	end

	local bagID = button:GetBagID()
	local slotID = button:GetID()
	local itemInfo = C_Container_GetContainerItemInfo(bagID, slotID)
	local hyperLink = itemInfo and itemInfo.hyperlink
	local isLocked = itemInfo and itemInfo.isLocked

	if hyperLink then
		local itemMinLevel = select(5, GetItemInfo(hyperLink)) -- Fetch item info once
		if (Module.LibUnfit:IsItemUnusable(hyperLink) or (itemMinLevel and itemMinLevel > Module.MyLevel)) and not isLocked then
			if not button.usableTexture:IsShown() then -- Only show if not already shown
				button.usableTexture:Show()
			end
		else
			if button.usableTexture:IsShown() then -- Only hide if not already hidden
				button.usableTexture:Hide()
			end
		end
	else
		if button.usableTexture:IsShown() then
			button.usableTexture:Hide()
		end
	end
end

function Module:OnLogin()
	Module:IsItemUsable_Containers()
end
