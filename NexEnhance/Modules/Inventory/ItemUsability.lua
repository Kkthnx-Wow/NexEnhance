local _, Module = ...
Module.LibUnfit = LibStub("Unfit-1.0")

function Module:IsItemUsable_UpdateBags()
	local button = self.__owner
	if not button.usableTexture then
		button.usableTexture = button:CreateTexture(nil, "ARTWORK")
		button.usableTexture:SetTexture(Module.White8x8)
		button.usableTexture:SetAllPoints(button)
		button.usableTexture:SetVertexColor(1, 0, 0)
		button.usableTexture:SetBlendMode("MOD")
		button.usableTexture:Hide()
	end

	local bagID = button:GetBagID()
	local slotID = button:GetID()
	local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
	local hyperLink = itemInfo and itemInfo.hyperlink
	local isLocked = itemInfo and itemInfo.isLocked

	if hyperLink then
		local _, _, _, _, itemMinLevel = GetItemInfo(hyperLink)

		if (Module.LibUnfit:IsItemUnusable(hyperLink) or (itemMinLevel and itemMinLevel > Module.MyLevel)) and not isLocked then
			button.usableTexture:Show()
		else
			button.usableTexture:Hide()
		end
	else
		-- Handle case where hyperLink is nil or invalid
		button.usableTexture:Hide()
	end
end

function Module:IsItemUsable_Containers()
	for i = 1, 13 do
		for _, button in _G["ContainerFrame" .. i]:EnumerateItems() do
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

function Module:OnLogin()
	Module:IsItemUsable_Containers()
end
