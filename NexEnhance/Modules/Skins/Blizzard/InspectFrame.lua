local _, Module = ...

Module:HookAddOn("Blizzard_InspectUI", function()
	if not (Module.NexConfig and Module.NexConfig.skins and Module.NexConfig.skins.blizzskins and Module.NexConfig.skins.blizzskins.inspectFrame) then
		return
	end

	local function styleInspectSlot(slotName)
		local slot = _G[slotName]
		if slot then
			Module.StripTextures(slot)
		else
			print("Error: Slot not found:", slotName)
		end
	end

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

	for _, slotName in ipairs(equipmentSlots) do
		styleInspectSlot(slotName)
	end

	if InspectModelFrame then
		InspectModelFrame:DisableDrawLayer("BACKGROUND")
		InspectModelFrame:DisableDrawLayer("BORDER")
		InspectModelFrame:DisableDrawLayer("OVERLAY")
		Module.StripTextures(InspectModelFrame, true)

		InspectModelFrame:ClearAllPoints()
		InspectModelFrame:SetSize(300, 360)
		InspectModelFrame:SetPoint("TOPLEFT", InspectFrameInset, 64, -3)
	end

	local function repositionInspectSlots()
		if InspectHeadSlot then
			InspectHeadSlot:ClearAllPoints()
			InspectHeadSlot:SetPoint("TOPLEFT", InspectFrameInset, "TOPLEFT", 6, -6)
		end

		if InspectHandsSlot then
			InspectHandsSlot:ClearAllPoints()
			InspectHandsSlot:SetPoint("TOPRIGHT", InspectFrameInset, "TOPRIGHT", -6, -6)
		end

		if InspectMainHandSlot then
			InspectMainHandSlot:ClearAllPoints()
			InspectMainHandSlot:SetPoint("BOTTOMLEFT", InspectFrameInset, "BOTTOMLEFT", 176, 5)
		end

		if InspectSecondaryHandSlot then
			InspectSecondaryHandSlot:ClearAllPoints()
			InspectSecondaryHandSlot:SetPoint("BOTTOMRIGHT", InspectFrameInset, "BOTTOMRIGHT", -176, 5)
		end
	end

	local function ApplyInspectFrameLayout()
		local InspectFrame = InspectFrame
		local InspectFrameInset = InspectFrame and InspectFrame.Inset

		if not InspectFrame or not InspectFrameInset then
			return
		end

		if PanelTemplates_GetSelectedTab(InspectFrame) == 1 then
			InspectFrame:SetSize(438, 431)
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

	local function OnInspectSwitchTabs(newID)
		local tabID = newID or PanelTemplates_GetSelectedTab(InspectFrame)
		ApplyInspectFrameLayout(tabID == 1)
	end

	hooksecurefunc("InspectSwitchTabs", OnInspectSwitchTabs)

	OnInspectSwitchTabs(1)

	repositionInspectSlots()

	if InspectPaperDollItemsFrame and InspectPaperDollItemsFrame.InspectTalents then
		InspectPaperDollItemsFrame.InspectTalents:ClearAllPoints()
		InspectPaperDollItemsFrame.InspectTalents:SetPoint("TOPRIGHT", InspectFrame, "BOTTOMRIGHT", 0, -1)
	end
end)
