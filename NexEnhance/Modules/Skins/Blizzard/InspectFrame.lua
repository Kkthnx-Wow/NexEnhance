local _, Module = ...

Module:HookAddOn("Blizzard_InspectUI", function()
	if not Module.db.profile.skins.blizzskins.inspectFrame then
		return
	end

	local PanelTemplates_GetSelectedTab = PanelTemplates_GetSelectedTab
	local UnitClass = UnitClass
	local hooksecurefunc = hooksecurefunc

	local InspectPaperDollItemsFrame = InspectPaperDollItemsFrame
	local InspectModelFrame = InspectModelFrame

	if InspectPaperDollItemsFrame.InspectTalents then
		InspectPaperDollItemsFrame.InspectTalents:ClearAllPoints()
		InspectPaperDollItemsFrame.InspectTalents:SetPoint("TOPRIGHT", InspectFrame, "BOTTOMRIGHT", 0, -1)
	end

	InspectModelFrame:DisableDrawLayer("BACKGROUND")
	InspectModelFrame:DisableDrawLayer("BORDER")
	InspectModelFrame:DisableDrawLayer("OVERLAY")
	Module.StripTextures(InspectModelFrame, true)

	local equipmentSlots = {
		"InspectHeadSlot",
		"InspectNeckSlot",
		"InspectShoulderSlot",
		"InspectShirtSlot",
		"InspectChestSlot",
		"InspectWaistSlot",
		"InspectLegsSlot",
		"InspectFeetSlot",
		"InspectWristSlot",
		"InspectHandsSlot",
		"InspectFinger0Slot",
		"InspectFinger1Slot",
		"InspectTrinket0Slot",
		"InspectTrinket1Slot",
		"InspectBackSlot",
		"InspectMainHandSlot",
		"InspectSecondaryHandSlot",
		"InspectTabardSlot",
	}

	local numEquipmentSlots = #equipmentSlots

	for i = 1, numEquipmentSlots do
		local slot = _G[equipmentSlots[i]]
		Module.StripTextures(slot)
	end

	local InspectHeadSlot = InspectHeadSlot
	local InspectHandsSlot = InspectHandsSlot
	local InspectMainHandSlot = InspectMainHandSlot
	local InspectSecondaryHandSlot = InspectSecondaryHandSlot

	InspectHeadSlot:ClearAllPoints()
	InspectHandsSlot:ClearAllPoints()
	InspectMainHandSlot:ClearAllPoints()
	InspectSecondaryHandSlot:ClearAllPoints()
	InspectModelFrame:ClearAllPoints()

	InspectHeadSlot:SetPoint("TOPLEFT", InspectFrameInset, "TOPLEFT", 6, -6)
	InspectHandsSlot:SetPoint("TOPRIGHT", InspectFrameInset, "TOPRIGHT", -6, -6)
	InspectMainHandSlot:SetPoint("BOTTOMLEFT", InspectFrameInset, "BOTTOMLEFT", 176, 5)
	InspectSecondaryHandSlot:SetPoint("BOTTOMRIGHT", InspectFrameInset, "BOTTOMRIGHT", -176, 5)

	InspectModelFrame:SetSize(300, 360)
	InspectModelFrame:SetPoint("TOPLEFT", InspectFrameInset, 64, -3)

	local function ApplyInspectFrameLayout()
		local InspectFrame = InspectFrame
		local InspectFrameInset = InspectFrame.Inset

		if PanelTemplates_GetSelectedTab(InspectFrame) == 1 then
			InspectFrame:SetSize(438, 431) -- 338 + 100, 424 + 7
			InspectFrameInset:SetPoint("BOTTOMRIGHT", InspectFrame, "BOTTOMLEFT", 432, 4)

			local _, targetClass = UnitClass("target")
			if targetClass then
				InspectFrameInset.Bg:SetTexture("Interface\\DRESSUPFRAME\\DressingRoom" .. targetClass)
				InspectFrameInset.Bg:SetTexCoord(0.00195312, 0.935547, 0.00195312, 0.978516)
				InspectFrameInset.Bg:SetHorizTile(false)
				InspectFrameInset.Bg:SetVertTile(false)
			end
		else
			InspectFrame:SetSize(338, 424)
			InspectFrameInset:SetPoint("BOTTOMRIGHT", InspectFrame, "BOTTOMLEFT", 332, 4)

			InspectFrameInset.Bg:SetTexture("Interface\\FrameGeneral\\UI-Background-Marble", "REPEAT", "REPEAT")
			InspectFrameInset.Bg:SetTexCoord(0, 1, 0, 1)
			InspectFrameInset.Bg:SetHorizTile(true)
			InspectFrameInset.Bg:SetVertTile(true)
		end
	end

	-- Adjust the inset based on tabs
	local function OnInspectSwitchTabs(newID)
		local tabID = newID or PanelTemplates_GetSelectedTab(InspectFrame)
		ApplyInspectFrameLayout(tabID == 1)
	end

	-- Hook it to tab switches
	hooksecurefunc("InspectSwitchTabs", OnInspectSwitchTabs)
	-- Call it once to apply it from the start
	OnInspectSwitchTabs(1)
end)
