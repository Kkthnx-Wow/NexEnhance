local _, Module = ...

local function styleEquipmentSlot(slotName)
	local slot = _G[slotName]
	if slot then
		Module.StripTextures(slot)
		if slot.ignoreTexture then
			slot.ignoreTexture:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-LeaveItem-Transparent")
		end
	end
end

function Module:PLAYER_LOGIN()
	if not (Module.NexConfig and Module.NexConfig.skins and Module.NexConfig.skins.blizzskins and Module.NexConfig.skins.blizzskins.characterFrame) then
		return
	end

	if CharacterModelScene then
		CharacterModelScene:DisableDrawLayer("BACKGROUND")
		CharacterModelScene:DisableDrawLayer("BORDER")
		CharacterModelScene:DisableDrawLayer("OVERLAY")
		Module.StripTextures(CharacterModelScene)
	end

	if CharacterFrameInsetRightScrollBar then
		Module.HideOption(CharacterFrameInsetRightScrollBar)
	end

	local equipmentSlots = {
		"CharacterBackSlot",
		"CharacterChestSlot",
		"CharacterFeetSlot",
		"CharacterFinger0Slot",
		"CharacterFinger1Slot",
		"CharacterHandsSlot",
		"CharacterHeadSlot",
		"CharacterLegsSlot",
		"CharacterMainHandSlot",
		"CharacterNeckSlot",
		"CharacterSecondaryHandSlot",
		"CharacterShirtSlot",
		"CharacterShoulderSlot",
		"CharacterTabardSlot",
		"CharacterTrinket0Slot",
		"CharacterTrinket1Slot",
		"CharacterWaistSlot",
		"CharacterWristSlot",
	}

	for _, slotName in ipairs(equipmentSlots) do
		styleEquipmentSlot(slotName)
	end

	if CharacterHeadSlot then
		CharacterHeadSlot:ClearAllPoints()
		CharacterHeadSlot:SetPoint("TOPLEFT", CharacterFrame.Inset, "TOPLEFT", 6, -6)
	end
	if CharacterHandsSlot then
		CharacterHandsSlot:ClearAllPoints()
		CharacterHandsSlot:SetPoint("TOPRIGHT", CharacterFrame.Inset, "TOPRIGHT", -6, -6)
	end
	if CharacterMainHandSlot then
		CharacterMainHandSlot:ClearAllPoints()
		CharacterMainHandSlot:SetPoint("BOTTOMLEFT", CharacterFrame.Inset, "BOTTOMLEFT", 176, 5)
	end
	if CharacterSecondaryHandSlot then
		CharacterSecondaryHandSlot:ClearAllPoints()
		CharacterSecondaryHandSlot:SetPoint("BOTTOMRIGHT", CharacterFrame.Inset, "BOTTOMRIGHT", -176, 5)
	end

	if CharacterModelScene then
		CharacterModelScene:ClearAllPoints()
		CharacterModelScene:SetSize(300, 360)
		CharacterModelScene:SetPoint("TOPLEFT", CharacterFrame.Inset, 64, -3)

		if CharacterModelScene.ControlFrame then
			CharacterModelScene.ControlFrame:ClearAllPoints()
			CharacterModelScene.ControlFrame:SetPoint("TOP", CharacterFrame.Inset, "TOP", 0, -2)
		end

		local gearFX = CharacterModelScene.GearEnchantAnimation and CharacterModelScene.GearEnchantAnimation.FrameFX
		if gearFX then
			for _, fxName in ipairs({ "PurpleGlow", "BlueGlow", "Sparkles", "Mask" }) do
				local fx = gearFX[fxName]
				if fx then
					fx:ClearAllPoints()
					fx:SetPoint("TOPLEFT", CharacterFrame.Inset, "TOPLEFT", -244, 102)
					fx:SetPoint("BOTTOMRIGHT", CharacterFrame.Inset, "BOTTOMRIGHT", 247, -103)
				end
			end
		end

		local topFrame = CharacterModelScene.GearEnchantAnimation and CharacterModelScene.GearEnchantAnimation.TopFrame
		if topFrame and topFrame.Frame then
			topFrame.Frame:ClearAllPoints()
			topFrame.Frame:SetPoint("TOPLEFT", CharacterFrame.Inset, "TOPLEFT", 2, -2)
			topFrame.Frame:SetPoint("BOTTOMRIGHT", CharacterFrame.Inset, "BOTTOMRIGHT", -2, 2)
		end
	end

	hooksecurefunc(CharacterFrame, "UpdateSize", function()
		if CharacterFrame.activeSubframe == "PaperDollFrame" then
			CharacterFrame:SetSize(640, 431)
			CharacterFrame.Inset:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMLEFT", 432, 4)

			if CharacterFrame.Inset.Bg then
				CharacterFrame.Inset.Bg:SetTexture("Interface\\DRESSUPFRAME\\DressingRoom" .. (Module.MyClass or ""))
				CharacterFrame.Inset.Bg:SetTexCoord(1 / 512, 479 / 512, 46 / 512, 455 / 512)
				CharacterFrame.Inset.Bg:SetHorizTile(false)
				CharacterFrame.Inset.Bg:SetVertTile(false)
			end

			if CharacterFrame.Background then
				CharacterFrame.Background:Hide()
			end
		else
			if CharacterFrame.Background then
				CharacterFrame.Background:Show()
			end
		end
	end)

	if CharacterStatsPane and CharacterStatsPane.ClassBackground then
		CharacterStatsPane.ClassBackground:ClearAllPoints()
		CharacterStatsPane.ClassBackground:SetHeight(CharacterStatsPane.ClassBackground:GetHeight() + 6)
		CharacterStatsPane.ClassBackground:SetParent(CharacterFrameInsetRight)
		CharacterStatsPane.ClassBackground:SetPoint("CENTER")
	end
end
