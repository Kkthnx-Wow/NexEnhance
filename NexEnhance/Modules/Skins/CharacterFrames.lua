--[[
	NexEnhance - CharacterFrames
	-------------------------------------------------------------------------
	Cleans up and resizes the Character and Inspect frames: strips Blizzard
	textures, standardises item-slot sizes, repositions the model and slots,
	and swaps in a class dressing-room background when on the gear tab.

	Uses F.StripTextures from Core/API.lua. Inspect lives in load-on-demand
	Blizzard_InspectUI — style on load or wait for ADDON_LOADED. Layout hooks
	defer to Apply*Layout helpers that respect Blizzard panel constants.
	Resizing guarded by InCombatLockdown() (secure frames).
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local L, F = ns.L, ns.F

local _G = _G
local select = select
local hooksecurefunc = hooksecurefunc
local InCombatLockdown = InCombatLockdown
local HideUIPanel = HideUIPanel
local UnitClass = UnitClass
local PanelTemplates_GetSelectedTab = PanelTemplates_GetSelectedTab
local C_AddOns = C_AddOns
local C_Timer = C_Timer

ns:RegisterDefaults({
	characterFrames = {
		enable = true,
	},
})

local CharacterFrames = ns:NewModule("CharacterFrames", "characterFrames", { group = "skins", title = L["Character Frames"], order = 20 })

-- Blizzard panel constants (12.0.7: CharacterFrame.lua, Constants.lua, SharedUIPanelTemplates.lua)
local PANEL_DEFAULT_WIDTH = _G.PANEL_DEFAULT_WIDTH or 338
local PANEL_DEFAULT_HEIGHT = _G.PANEL_DEFAULT_HEIGHT or 424
local PANEL_INSET_LEFT_OFFSET = _G.PANEL_INSET_LEFT_OFFSET or 4
local PANEL_INSET_RIGHT_OFFSET = _G.PANEL_INSET_RIGHT_OFFSET or -6
local PANEL_INSET_BOTTOM_OFFSET = _G.PANEL_INSET_BOTTOM_OFFSET or 4
local PANEL_INSET_BOTTOM_BUTTON_OFFSET = _G.PANEL_INSET_BOTTOM_BUTTON_OFFSET or 26
local PANEL_INSET_ATTIC_OFFSET = _G.PANEL_INSET_ATTIC_OFFSET or -60
local CHARACTERFRAME_EXPANDED_WIDTH = _G.CHARACTERFRAME_EXPANDED_WIDTH or 540

local CHAR_PAPERDOLL_WIDTH = 640
local CHAR_PAPERDOLL_HEIGHT = 431
local CHAR_INSET_OFFSET = PANEL_DEFAULT_WIDTH + PANEL_INSET_RIGHT_OFFSET + (CHAR_PAPERDOLL_WIDTH - CHARACTERFRAME_EXPANDED_WIDTH)

local INSPECT_PAPERDOLL_WIDTH = 438
local INSPECT_PAPERDOLL_HEIGHT = 431
local INSPECT_INSET_OFFSET_PAPER = 432
local INSPECT_TAB_GUILD = 3
local SLOT_SIZE = 37
local CHAR_MODEL_ZOOM_SCALE = 1.1
local MARBLE_BG = "Interface\\FrameGeneral\\UI-Background-Marble"

local function ShouldStyle()
	return CharacterFrames:IsEnabled() and ns.db.characterFrames.enable
end

-- Pawn sits under PaperDollFrame; CharacterStatsPane is a sibling on top and
-- blocks clicks. Frame *level* only orders siblings under the same parent, so
-- raising level inside PaperDollFrame cannot beat the stats pane. Lifting
-- *strata* on the button keeps Pawn's normal parent/show-hide behavior.
local pawnHookInstalled = false

local function LiftPawnButton(button, refFrame)
	if not (button and refFrame) then
		return
	end
	button:EnableMouse(true)
	button:SetFrameStrata("HIGH")
	button:SetFrameLevel(refFrame:GetFrameLevel() + 50)
	button:Raise()
end

local function FixInventoryPawnButton()
	local button = _G.PawnUI_InventoryPawnButton
	local statsPane = _G.CharacterStatsPane
	local characterFrame = _G.CharacterFrame
	if not (button and characterFrame) then
		return
	end
	LiftPawnButton(button, statsPane or characterFrame)
end

local function FixInspectPawnButton()
	local button = _G.PawnUI_InspectPawnButton
	local inspectFrame = _G.InspectFrame
	if not (button and inspectFrame) then
		return
	end
	LiftPawnButton(button, inspectFrame)
end

local function FixPawnButtons()
	if not ShouldStyle() then
		return
	end
	FixInventoryPawnButton()
	FixInspectPawnButton()
end

local function InstallPawnButtonFix()
	if pawnHookInstalled or not _G.PawnUI_InventoryPawnButton_Move then
		return
	end
	-- issecurevariable() returns false when Pawn has set this global from a
	-- tainted execution path. Hooking a tainted global propagates that taint
	-- into NexEnhance and blocks secure code. Skip the hook in that case —
	-- the cosmetic button reposition is less important than staying taint-free.
	if not issecurevariable("PawnUI_InventoryPawnButton_Move") then
		return
	end
	pawnHookInstalled = true
	hooksecurefunc("PawnUI_InventoryPawnButton_Move", FixPawnButtons)
end

local function RefreshPawnButtons()
	if not ShouldStyle() then
		return
	end
	InstallPawnButtonFix()
	-- Only call the Pawn function if it exists AND is not tainted.
	-- Calling a tainted function from secure addon code causes the same
	-- "action blocked because of taint" error that the hook would.
	if _G.PawnUI_InventoryPawnButton_Move and issecurevariable("PawnUI_InventoryPawnButton_Move") then
		_G.PawnUI_InventoryPawnButton_Move()
	else
		FixPawnButtons()
	end
end

-- Only touch equipment slots (name contains "Slot"); skip InspectTalents etc.
local function StyleItemSlots(...)
	for i = 1, select("#", ...) do
		local slot = select(i, ...)
		local name = slot and slot.GetName and slot:GetName()
		if name and name:find("Slot") and (slot:IsObjectType("Button") or slot:IsObjectType("ItemButton")) then
			slot:StripTextures()
			slot:SetSize(SLOT_SIZE, SLOT_SIZE)
		end
	end
end

local function SetMarbleBackground(bg)
	if not bg then
		return
	end
	bg:SetTexture(MARBLE_BG, "REPEAT", "REPEAT")
	bg:SetTexCoord(0, 1, 0, 1)
	bg:SetHorizTile(true)
	bg:SetVertTile(true)
end

-- Default ButtonFrameTemplate inset (SharedUIPanelTemplates.xml).
local function ApplyDefaultInset(frame, useButtonBar)
	frame.Inset:ClearAllPoints()
	frame.Inset:SetPoint("TOPLEFT", frame, "TOPLEFT", PANEL_INSET_LEFT_OFFSET, PANEL_INSET_ATTIC_OFFSET)
	local bottom = useButtonBar and PANEL_INSET_BOTTOM_BUTTON_OFFSET or PANEL_INSET_BOTTOM_OFFSET
	frame.Inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", PANEL_INSET_RIGHT_OFFSET, bottom)
end

-- Paper-doll static inset anchor (CharacterFrameMixin:UpdateSize, useStaticInsetSize).
local function ApplyPaperdollInset(frame, offsetX)
	frame.Inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", offsetX, PANEL_INSET_BOTTOM_OFFSET)
end

local function AdjustCharacterModelZoom()
	local scene = _G.CharacterModelScene
	local camera = scene and scene.GetActiveCamera and scene:GetActiveCamera()
	if not (camera and camera.GetZoomDistance and camera.SetZoomDistance) then
		return
	end

	local distance = camera:GetZoomDistance()
	if not distance then
		return
	end

	local target = distance * CHAR_MODEL_ZOOM_SCALE
	local maxDistance = camera.GetMaxZoomDistance and camera:GetMaxZoomDistance()
	if maxDistance and maxDistance > 0 and target > maxDistance then
		target = maxDistance
	end

	camera:SetZoomDistance(target)
	if camera.SnapToTargetInterpolationZoom then
		camera:SnapToTargetInterpolationZoom()
	end
end

local function FitCharacterEnchantAnimationToInset()
	local CharacterFrame = _G.CharacterFrame
	local CharacterModelScene = _G.CharacterModelScene
	local inset = CharacterFrame and CharacterFrame.Inset
	local enchant = CharacterModelScene and CharacterModelScene.GearEnchantAnimation
	if not (inset and enchant and enchant.FrameFX and enchant.TopFrame) then
		return
	end

	local width = inset:GetWidth()
	local height = inset:GetHeight()
	if not (width and height and width > 0 and height > 0) then
		return
	end

	-- Blizzard's enchant animation is authored as a centered 128x128 widget.
	-- Our custom CharacterFrame layout is wider, so pin and size it to the inset
	-- (minus tiny border offsets) or the glow hugs the middle instead of the frame.
	enchant:ClearAllPoints()
	enchant:SetPoint("TOPLEFT", inset, "TOPLEFT", 1, -1)
	enchant:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -1, 1)
	enchant.FrameFX:ClearAllPoints()
	enchant.FrameFX:SetAllPoints(enchant)
	enchant.TopFrame:ClearAllPoints()
	enchant.TopFrame:SetAllPoints(enchant)

	local glowTextures = {
		enchant.FrameFX.PurpleGlow,
		enchant.FrameFX.BlueGlow,
		enchant.FrameFX.Sparkles,
		enchant.FrameFX.Mask,
		enchant.TopFrame.Frame,
	}
	for i = 1, #glowTextures do
		local tex = glowTextures[i]
		if tex then
			tex:ClearAllPoints()
			tex:SetAllPoints(enchant)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Character frame layout (post-UpdateSize)
-- ---------------------------------------------------------------------------
function CharacterFrames:ApplyCharacterLayout()
	if InCombatLockdown() or not ShouldStyle() then
		return
	end

	local CharacterFrame = _G.CharacterFrame
	if not CharacterFrame then
		return
	end

	local subframe = CharacterFrame.activeSubframe

	if subframe == "PaperDollFrame" then
		-- Only widen when the stats sidebar is expanded; collapsed gear keeps
		-- Blizzard's UpdateSize() width (338) and static inset (332).
		if CharacterFrame.Expanded then
			CharacterFrame:SetSize(CHAR_PAPERDOLL_WIDTH, CHAR_PAPERDOLL_HEIGHT)
			ApplyPaperdollInset(CharacterFrame, CHAR_INSET_OFFSET)
		end

		local _, class = UnitClass("player")
		if class then
			CharacterFrame.Inset.Bg:SetTexture("Interface\\DressUpFrame\\DressingRoom" .. class)
			CharacterFrame.Inset.Bg:SetTexCoord(1 / 512, 479 / 512, 46 / 512, 455 / 512)
			CharacterFrame.Inset.Bg:SetHorizTile(false)
			CharacterFrame.Inset.Bg:SetVertTile(false)
		end

		CharacterFrame.Background:Hide()
	elseif subframe == "ReputationFrame" or subframe == "TokenFrame" then
		-- UpdateSize() already set width (400) and Inset -> BOTTOMRIGHT (-6, 4).
		CharacterFrame.Background:Show()
	end
end

function CharacterFrames:RestoreCharacterLayout()
	if InCombatLockdown() then
		self.pendingCharacterRestore = true
		return
	end

	local CharacterFrame = _G.CharacterFrame
	if not CharacterFrame then
		return
	end

	CharacterFrame.Background:Show()
	if CharacterFrame.UpdateSize then
		CharacterFrame:UpdateSize()
	end
end

function CharacterFrames:StyleCharacterFrame()
	if self.charStyled then
		self:ApplyCharacterLayout()
		return
	end
	self.charStyled = true

	local CharacterFrame = _G.CharacterFrame
	local CharacterModelScene = _G.CharacterModelScene
	local PaperDollItemsFrame = _G.PaperDollItemsFrame
	local PaperDollFrame = _G.PaperDollFrame
	local CharacterStatsPane = _G.CharacterStatsPane
	local CharacterFrameInsetRight = _G.CharacterFrameInsetRight
	if not (CharacterFrame and CharacterModelScene and PaperDollItemsFrame) then
		return
	end

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
	-- Keep the model scene inside Blizzard's paper-doll inner frame (not the full
	-- inset). When we stretched the scene to the whole inset, GearEnchantAnimation
	-- (anchored to CharacterModelScene center) looked offset/oversized.
	CharacterModelScene:SetPoint("TOPLEFT", CharacterFrame.Inset, 46, -4)
	CharacterModelScene:SetPoint("BOTTOMRIGHT", CharacterFrame.Inset, -47, 31)
	FitCharacterEnchantAnimationToInset()

	if not self.charUpdateHooked then
		self.charUpdateHooked = true
		hooksecurefunc(CharacterFrame, "UpdateSize", function()
			-- Defer layout resizing to the next tick. If we call SetSize directly inside
			-- the secure show/update size path, it taints the execution, causing Blizzard's
			-- status bar code to fail when comparing health/power (secret values). Slay the taint!
			C_Timer.After(0, function()
				CharacterFrames:ApplyCharacterLayout()
				FitCharacterEnchantAnimationToInset()
			end)
		end)
	end

	local itemLevelValue = CharacterStatsPane.ItemLevelFrame.Value
	local ilvlFont, _, ilvlFlags = itemLevelValue:GetFont()
	itemLevelValue:SetFont(ilvlFont, 20, ilvlFlags)

	local function StyleTitleChildren(...)
		for i = 1, select("#", ...) do
			local child = select(i, ...)
			if child and not child.nexStyled then
				child:DisableDrawLayer("BACKGROUND")
				child.nexStyled = true
			end
		end
	end

	if PaperDollFrame and PaperDollFrame.TitleManagerPane and PaperDollFrame.TitleManagerPane.ScrollBox then
		hooksecurefunc(PaperDollFrame.TitleManagerPane.ScrollBox, "Update", function(scrollBox)
			if ShouldStyle() then
				StyleTitleChildren(scrollBox.ScrollTarget:GetChildren())
			end
		end)
	end

	CharacterStatsPane.ClassBackground:ClearAllPoints()
	CharacterStatsPane.ClassBackground:SetHeight(CharacterStatsPane.ClassBackground:GetHeight() + 6)
	CharacterStatsPane.ClassBackground:SetParent(CharacterFrameInsetRight)
	CharacterStatsPane.ClassBackground:SetPoint("CENTER")

	if _G.PaperDollFrame_SetPlayer then
		hooksecurefunc("PaperDollFrame_SetPlayer", function()
			if ShouldStyle() then
				AdjustCharacterModelZoom()
				FitCharacterEnchantAnimationToInset()
				RefreshPawnButtons()
			end
		end)
	end

	if PaperDollFrame then
		PaperDollFrame:HookScript("OnShow", RefreshPawnButtons)
		if _G.PaperDollFrame_UpdateStats then
			hooksecurefunc("PaperDollFrame_UpdateStats", RefreshPawnButtons)
		end
	end

	self:ApplyCharacterLayout()
	AdjustCharacterModelZoom()
	FitCharacterEnchantAnimationToInset()
	RefreshPawnButtons()
end

-- ---------------------------------------------------------------------------
-- Inspect frame (Blizzard_InspectUI - load on demand)
-- ---------------------------------------------------------------------------
function CharacterFrames:ApplyInspectLayout(tabID)
	if InCombatLockdown() or not ShouldStyle() then
		return
	end

	local InspectFrame = _G.InspectFrame
	if not InspectFrame then
		return
	end

	tabID = tabID or PanelTemplates_GetSelectedTab(InspectFrame)
	if tabID == 1 then
		InspectFrame:SetSize(INSPECT_PAPERDOLL_WIDTH, INSPECT_PAPERDOLL_HEIGHT)
		ApplyPaperdollInset(InspectFrame, INSPECT_INSET_OFFSET_PAPER)

		local _, targetClass = UnitClass("target")
		-- classFilename (2nd return): no ConditionalSecret.
		if targetClass then
			InspectFrame.Inset.Bg:SetTexture("Interface\\DressUpFrame\\DressingRoom" .. targetClass)
			InspectFrame.Inset.Bg:SetTexCoord(0.00195312, 0.935547, 0.00195312, 0.978516)
			InspectFrame.Inset.Bg:SetHorizTile(false)
			InspectFrame.Inset.Bg:SetVertTile(false)
		end
	else
		InspectFrame:SetSize(PANEL_DEFAULT_WIDTH, PANEL_DEFAULT_HEIGHT)
		ApplyDefaultInset(InspectFrame, tabID == INSPECT_TAB_GUILD)
		SetMarbleBackground(InspectFrame.Inset.Bg)
	end
end

function CharacterFrames:RestoreInspectLayout()
	if InCombatLockdown() then
		self.pendingInspectRestore = true
		return
	end

	local InspectFrame = _G.InspectFrame
	if not InspectFrame then
		return
	end

	InspectFrame:SetSize(PANEL_DEFAULT_WIDTH, PANEL_DEFAULT_HEIGHT)
	local tabID = PanelTemplates_GetSelectedTab(InspectFrame)
	ApplyDefaultInset(InspectFrame, tabID == INSPECT_TAB_GUILD)
	SetMarbleBackground(InspectFrame.Inset.Bg)
end

function CharacterFrames:StyleInspectFrame()
	if self.inspectStyled then
		self:ApplyInspectLayout()
		return
	end

	local InspectFrame = _G.InspectFrame
	local InspectModelFrame = _G.InspectModelFrame
	local InspectPaperDollItemsFrame = _G.InspectPaperDollItemsFrame
	if not (InspectFrame and InspectModelFrame and InspectPaperDollItemsFrame) then
		return
	end

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

	local averageItemLevelText = F.CreatePlainFS(InspectPaperDollItemsFrame, 12)
	local aiFont, _, aiFlags = averageItemLevelText:GetFont()
	averageItemLevelText:SetFont(aiFont, 12, aiFlags)
	if averageItemLevelText.nexShadow then
		averageItemLevelText.nexShadow:SetFont(aiFont, 12, aiFlags)
	end
	averageItemLevelText:SetJustifyH("CENTER")
	averageItemLevelText:SetPoint("BOTTOM", InspectFrame.Inset, "BOTTOM", 0, 46)
	InspectPaperDollItemsFrame.AverageItemLevelText = averageItemLevelText

	if _G.InspectPaperDollFrame_SetLevel and _G.C_PaperDollInfo and _G.C_PaperDollInfo.GetInspectItemLevel then
		hooksecurefunc("InspectPaperDollFrame_SetLevel", function()
			if not ShouldStyle() then
				return
			end
			local unit = InspectFrame.unit
			if not unit then
				return
			end
			local ilvl = _G.C_PaperDollInfo.GetInspectItemLevel(unit)
			-- GetInspectItemLevel: SecretArguments only.
			if ilvl then
				F.SetPlainFormattedText(averageItemLevelText, _G.DUNGEON_SCORE_LINK_ITEM_LEVEL or "Item Level %d", ilvl)
			end
		end)
	end

	if not self.inspectTabHooked then
		self.inspectTabHooked = true
		hooksecurefunc("InspectSwitchTabs", function(newID)
			-- Defer to the next tick to avoid tainting secure elements during tab switches
			C_Timer.After(0, function()
				CharacterFrames:ApplyInspectLayout(newID)
			end)
		end)
	end

	self:ApplyInspectLayout(1)

	if _G.InspectPaperDollFrame then
		_G.InspectPaperDollFrame:HookScript("OnShow", RefreshPawnButtons)
	end
end

function CharacterFrames:ADDON_LOADED(addon)
	if addon == "Pawn" then
		RefreshPawnButtons()
	elseif addon == "Blizzard_InspectUI" and ShouldStyle() then
		self:StyleInspectFrame()
	end
end

function CharacterFrames:PLAYER_REGEN_ENABLED()
	if self.pendingCharacterRestore then
		self.pendingCharacterRestore = nil
		if not ShouldStyle() then
			self:RestoreCharacterLayout()
		end
	end
	if self.pendingInspectRestore then
		self.pendingInspectRestore = nil
		if not ShouldStyle() then
			self:RestoreInspectLayout()
		end
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function CharacterFrames:OnInitialize()
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("ADDON_LOADED")
end

function CharacterFrames:OnEnable()
	self:StyleCharacterFrame()

	if C_AddOns.IsAddOnLoaded("Blizzard_InspectUI") then
		self:StyleInspectFrame()
	end

	if C_AddOns.IsAddOnLoaded("Pawn") then
		RefreshPawnButtons()
	end
end

function CharacterFrames:OnSettingChanged(key)
	if key ~= "enable" then
		return
	end

	if ShouldStyle() then
		self:StyleCharacterFrame()
		if C_AddOns.IsAddOnLoaded("Blizzard_InspectUI") then
			self:StyleInspectFrame()
		end
		local ilvlText = _G.InspectPaperDollItemsFrame and _G.InspectPaperDollItemsFrame.AverageItemLevelText
		if ilvlText then
			ilvlText:Show()
		end
	else
		self:RestoreCharacterLayout()
		self:RestoreInspectLayout()
		local ilvlText = _G.InspectPaperDollItemsFrame and _G.InspectPaperDollItemsFrame.AverageItemLevelText
		if ilvlText then
			ilvlText:Hide()
		end
	end
end

function CharacterFrames:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Character Frames"], L["Restyle and resize the Character and Inspect frames. Layout toggles live; stripped slot art needs /reload to fully undo."])
end
