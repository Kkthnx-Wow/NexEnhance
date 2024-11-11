local _, Module = ...

local function styleEquipmentSlot(slotName)
	local slot = _G[slotName]

	Module.StripTextures(slot)

	-- Set ignore texture
	slot.ignoreTexture:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-LeaveItem-Transparent")
end

function Module:PLAYER_LOGIN()
	if not Module.db.profile.skins.blizzskins.characterFrame then
		return
	end

	-- Character model scene
	CharacterModelScene:DisableDrawLayer("BACKGROUND")
	CharacterModelScene:DisableDrawLayer("BORDER")
	CharacterModelScene:DisableDrawLayer("OVERLAY")
	Module.StripTextures(CharacterModelScene, true)

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

	CharacterHeadSlot:ClearAllPoints()
	CharacterHandsSlot:ClearAllPoints()
	CharacterMainHandSlot:ClearAllPoints()
	CharacterSecondaryHandSlot:ClearAllPoints()
	CharacterModelScene:ClearAllPoints()
	CharacterModelScene.ControlFrame:ClearAllPoints()

	-- Character control buttons
	CharacterModelScene.ControlFrame:SetPoint("TOP", CharacterFrame.Inset, "TOP", 0, -2)

	-- Character slots
	CharacterHeadSlot:SetPoint("TOPLEFT", CharacterFrame.Inset, "TOPLEFT", 6, -6)
	CharacterHandsSlot:SetPoint("TOPRIGHT", CharacterFrame.Inset, "TOPRIGHT", -6, -6)
	CharacterMainHandSlot:SetPoint("BOTTOMLEFT", CharacterFrame.Inset, "BOTTOMLEFT", 176, 5)
	CharacterSecondaryHandSlot:SetPoint("BOTTOMRIGHT", CharacterFrame.Inset, "BOTTOMRIGHT", -176, 5)

	-- Character model scene
	CharacterModelScene:SetPoint("TOPLEFT", CharacterFrame.Inset, 4, -4)
	CharacterModelScene:SetPoint("BOTTOMRIGHT", CharacterFrame.Inset, -4, 4)

	hooksecurefunc(CharacterFrame, "UpdateSize", function()
		if CharacterFrame.activeSubframe == "PaperDollFrame" then
			CharacterFrame:SetSize(640, 431)
			CharacterFrame.Inset:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMLEFT", 432, 4)

			CharacterFrame.Inset.Bg:SetTexture("Interface\\DRESSUPFRAME\\DressingRoom" .. Module.MyClass)
			CharacterFrame.Inset.Bg:SetTexCoord(1 / 512, 479 / 512, 46 / 512, 455 / 512)
			CharacterFrame.Inset.Bg:SetHorizTile(false)
			CharacterFrame.Inset.Bg:SetVertTile(false)

			CharacterFrame.Background:Hide()
		else
			CharacterFrame.Background:Show()
		end
	end)

	-- Class background
	CharacterStatsPane.ClassBackground:ClearAllPoints()
	CharacterStatsPane.ClassBackground:SetHeight(CharacterStatsPane.ClassBackground:GetHeight() + 6)
	CharacterStatsPane.ClassBackground:SetParent(CharacterFrameInsetRight)
	CharacterStatsPane.ClassBackground:SetPoint("CENTER")
end
