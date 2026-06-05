--[[
	NexEnhance - CharacterFrames
	-------------------------------------------------------------------------
	Cleans up and resizes the Character and Inspect frames: strips Blizzard
	textures, standardises item-slot sizes, repositions the model and slots,
	and swaps in a class dressing-room background when on the gear tab.

	Adapted from CharInspectPlus by Kkthnx:
	  https://github.com/Kkthnx-Wow/CharInspectPlus

	Integration notes:
	  * Uses the framework's :StripTextures() widget API (Core/API.lua).
	  * The Inspect frame lives in the load-on-demand Blizzard_InspectUI addon,
	    so we style it immediately if it is already loaded, otherwise we wait
	    for its ADDON_LOADED through the central dispatcher.
	  * All resizing is guarded by InCombatLockdown() because these are secure
	    frames.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local L = ns.L

-- Localised globals.
local _G = _G
local select = select
local hooksecurefunc = hooksecurefunc
local InCombatLockdown = InCombatLockdown
local HideUIPanel = HideUIPanel
local UnitClass = UnitClass
local PanelTemplates_GetSelectedTab = PanelTemplates_GetSelectedTab
local C_AddOns = C_AddOns

ns:RegisterDefaults({
	characterFrames = {
		enable = true,
	},
})

local CharacterFrames = ns:NewModule("CharacterFrames", "characterFrames", { group = "skins", title = L["Character Frames"], order = 20 })

-- Standardise item-slot buttons: strip their borders and use a uniform size.
local function StyleItemSlots(...)
	for i = 1, select("#", ...) do
		local slot = select(i, ...)
		if slot:IsObjectType("Button") or slot:IsObjectType("ItemButton") then
			slot:StripTextures()
			slot:SetSize(37, 37)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Character frame
-- ---------------------------------------------------------------------------
function CharacterFrames:StyleCharacterFrame()
	if self.charStyled then return end
	self.charStyled = true

	local CharacterFrame = _G.CharacterFrame
	local CharacterModelScene = _G.CharacterModelScene
	local PaperDollItemsFrame = _G.PaperDollItemsFrame
	local PaperDollFrame = _G.PaperDollFrame
	local CharacterStatsPane = _G.CharacterStatsPane
	local CharacterFrameInsetRight = _G.CharacterFrameInsetRight
	if not (CharacterFrame and CharacterModelScene) then return end

	if CharacterFrame:IsShown() then
		HideUIPanel(CharacterFrame)
	end

	CharacterModelScene:DisableDrawLayer("BACKGROUND")
	CharacterModelScene:DisableDrawLayer("BORDER")
	CharacterModelScene:DisableDrawLayer("OVERLAY")
	CharacterModelScene:StripTextures(true)

	StyleItemSlots(PaperDollItemsFrame:GetChildren())

	_G.CharacterHeadSlot:SetPoint("TOPLEFT", CharacterFrame.Inset, "TOPLEFT", 6, -6)
	_G.CharacterHandsSlot:SetPoint("TOPRIGHT", CharacterFrame.Inset, "TOPRIGHT", -6, -6)
	_G.CharacterMainHandSlot:SetPoint("BOTTOMLEFT", CharacterFrame.Inset, "BOTTOMLEFT", 176, 5)
	_G.CharacterSecondaryHandSlot:ClearAllPoints()
	_G.CharacterSecondaryHandSlot:SetPoint("BOTTOMRIGHT", CharacterFrame.Inset, "BOTTOMRIGHT", -176, 5)

	CharacterModelScene:SetSize(0, 0)
	CharacterModelScene:ClearAllPoints()
	CharacterModelScene:SetPoint("TOPLEFT", CharacterFrame.Inset, 0, 0)
	CharacterModelScene:SetPoint("BOTTOMRIGHT", CharacterFrame.Inset, 0, 20)

	hooksecurefunc(CharacterFrame, "UpdateSize", function()
		if InCombatLockdown() then return end -- secure frame; never resize in combat

		if CharacterFrame.activeSubframe == "PaperDollFrame" then
			CharacterFrame:SetSize(640, 431)
			CharacterFrame.Inset:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMLEFT", 432, 4)

			local _, class = UnitClass("player")
			CharacterFrame.Inset.Bg:SetTexture("Interface\\DressUpFrame\\DressingRoom" .. class)
			CharacterFrame.Inset.Bg:SetTexCoord(1 / 512, 479 / 512, 46 / 512, 455 / 512)
			CharacterFrame.Inset.Bg:SetHorizTile(false)
			CharacterFrame.Inset.Bg:SetVertTile(false)

			CharacterFrame.Background:Hide()
		else
			CharacterFrame.Background:Show()
		end
	end)

	-- Larger, clearer item-level readout.
	local itemLevelValue = CharacterStatsPane.ItemLevelFrame.Value
	local ilvlFont, _, ilvlFlags = itemLevelValue:GetFont()
	itemLevelValue:SetFont(ilvlFont, 20, ilvlFlags)
	itemLevelValue:SetShadowOffset(1, -1)

	-- Clean the Title Manager list rows as they scroll into view.
	local function StyleTitleChildren(...)
		for i = 1, select("#", ...) do
			local child = select(i, ...)
			if child and not child.nexStyled then
				child:DisableDrawLayer("BACKGROUND")
				child.nexStyled = true
			end
		end
	end

	hooksecurefunc(PaperDollFrame.TitleManagerPane.ScrollBox, "Update", function(scrollBox)
		StyleTitleChildren(scrollBox.ScrollTarget:GetChildren())
	end)

	CharacterStatsPane.ClassBackground:ClearAllPoints()
	CharacterStatsPane.ClassBackground:SetHeight(CharacterStatsPane.ClassBackground:GetHeight() + 6)
	CharacterStatsPane.ClassBackground:SetParent(CharacterFrameInsetRight)
	CharacterStatsPane.ClassBackground:SetPoint("CENTER")
end

-- ---------------------------------------------------------------------------
-- Inspect frame (Blizzard_InspectUI - load on demand)
-- ---------------------------------------------------------------------------
function CharacterFrames:StyleInspectFrame()
	if self.inspectStyled then return end

	local InspectFrame = _G.InspectFrame
	local InspectModelFrame = _G.InspectModelFrame
	local InspectPaperDollItemsFrame = _G.InspectPaperDollItemsFrame
	if not (InspectFrame and InspectModelFrame and InspectPaperDollItemsFrame) then return end

	self.inspectStyled = true

	if InspectFrame:IsShown() then
		HideUIPanel(InspectFrame)
	end

	InspectPaperDollItemsFrame.InspectTalents:ClearAllPoints()
	InspectPaperDollItemsFrame.InspectTalents:SetPoint("TOPRIGHT", InspectFrame, "BOTTOMRIGHT", 0, -1)

	InspectModelFrame:StripTextures(true)

	StyleItemSlots(InspectPaperDollItemsFrame:GetChildren())

	_G.InspectHeadSlot:SetPoint("TOPLEFT", InspectFrame.Inset, "TOPLEFT", 6, -6)
	_G.InspectHandsSlot:SetPoint("TOPRIGHT", InspectFrame.Inset, "TOPRIGHT", -6, -6)
	_G.InspectMainHandSlot:SetPoint("BOTTOMLEFT", InspectFrame.Inset, "BOTTOMLEFT", 175, 5)
	_G.InspectSecondaryHandSlot:ClearAllPoints()
	_G.InspectSecondaryHandSlot:SetPoint("BOTTOMRIGHT", InspectFrame.Inset, "BOTTOMRIGHT", -175, 5)

	InspectModelFrame:SetSize(0, 0)
	InspectModelFrame:ClearAllPoints()
	InspectModelFrame:SetPoint("TOPLEFT", InspectFrame.Inset, 0, 0)
	InspectModelFrame:SetPoint("BOTTOMRIGHT", InspectFrame.Inset, 0, 30)
	InspectModelFrame:SetCamDistanceScale(1.1)

	local function OnInspectSwitchTabs(newID)
		if InCombatLockdown() then return end -- secure frame

		local tabID = newID or PanelTemplates_GetSelectedTab(InspectFrame)
		if tabID == 1 then
			InspectFrame:SetSize(438, 431)
			InspectFrame.Inset:SetPoint("BOTTOMRIGHT", InspectFrame, "BOTTOMLEFT", 432, 4)

			local _, targetClass = UnitClass("target")
			if targetClass then
				InspectFrame.Inset.Bg:SetTexture("Interface\\DressUpFrame\\DressingRoom" .. targetClass)
				InspectFrame.Inset.Bg:SetTexCoord(0.00195312, 0.935547, 0.00195312, 0.978516)
				InspectFrame.Inset.Bg:SetHorizTile(false)
				InspectFrame.Inset.Bg:SetVertTile(false)
			end
		else
			InspectFrame:SetSize(338, 424)
			InspectFrame.Inset:SetPoint("BOTTOMRIGHT", InspectFrame, "BOTTOMLEFT", 332, 4)

			InspectFrame.Inset.Bg:SetTexture("Interface\\FrameGeneral\\UI-Background-Marble", "REPEAT", "REPEAT")
			InspectFrame.Inset.Bg:SetTexCoord(0, 1, 0, 1)
			InspectFrame.Inset.Bg:SetHorizTile(true)
			InspectFrame.Inset.Bg:SetVertTile(true)
		end
	end

	hooksecurefunc("InspectSwitchTabs", OnInspectSwitchTabs)
	OnInspectSwitchTabs(1)
end

function CharacterFrames:ADDON_LOADED(addon)
	if addon == "Blizzard_InspectUI" then
		self:StyleInspectFrame()
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function CharacterFrames:OnEnable()
	self:StyleCharacterFrame()

	if C_AddOns.IsAddOnLoaded("Blizzard_InspectUI") then
		self:StyleInspectFrame()
	else
		self:RegisterEvent("ADDON_LOADED")
	end
end

function CharacterFrames:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Character Frames"], L["Restyle and resize the Character and Inspect frames (reload to disable)."])
end
