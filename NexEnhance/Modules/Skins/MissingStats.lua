--[[
	NexEnhance - MissingStats
	-------------------------------------------------------------------------
	Surfaces the character-sheet stats Blizzard hides by default - attack
	power, weapon damage, attack/weapon speed, spell power, energy / rune /
	focus regen and movement speed - and tidies the existing readouts:
	per-decimal rating percentages, equipped + overall item level, and a
	cleaner stat font.

	Extra stat rows hook in after Blizzard's live update — we don't replace
	PAPERDOLL_STATCATEGORIES (that taints UnitStat comparisons in combat).
	Blizzard already renders off-hand attack speed and the item-level tooltip,
	so we don't duplicate those. Secret-guarded: if a value is secret we leave
	Blizzard's readout alone.

	The extra rows skip combat entirely — some PaperDoll APIs return secrets there
	and Blizzard's setters compare internally.
--]]

-- luacheck: globals PAPERDOLL_STATCATEGORIES PAPERDOLL_STATINFO CharacterStatsPane
-- luacheck: read_globals PaperDollFrame_SetLabelAndText PaperDollFrame_UpdateStats PaperDollFrame_SetItemLevel
-- luacheck: read_globals GetAverageItemLevel GetItemLevelColor STAT_AVERAGE_ITEM_LEVEL STAT_HASTE Game13Font Enum
-- luacheck: read_globals LE_UNIT_STAT_STRENGTH LE_UNIT_STAT_AGILITY LE_UNIT_STAT_INTELLECT C_PaperDollInfo
---@diagnostic disable: undefined-global, undefined-field
local _, ns = ...
local L, F = ns.L, ns.F

local format = string.format
local max = math.max
local min = math.min
local hooksecurefunc = hooksecurefunc
local select = select
local CreateFrame = CreateFrame
local ipairs = ipairs

local GetAverageItemLevel = GetAverageItemLevel
local GetItemLevelColor = GetItemLevelColor
local InCombatLockdown = InCombatLockdown
local GetSpecializationRoleEnum = GetSpecializationRoleEnum
local UnitSex = UnitSex
local C_SpecializationInfo = C_SpecializationInfo
local C_PaperDollInfo = C_PaperDollInfo
local C_Timer = C_Timer
local Game13Font = _G.Game13Font

-- Artifact "light gold" (#e6cc80). Used when Blizzard leaves the item-level
-- readout uncoloured (white); its own blue/purple quality tints are kept.
local ARTIFACT_R, ARTIFACT_G, ARTIFACT_B = 0.90, 0.80, 0.50

ns:RegisterDefaults({
	missingStats = {
		enable = true,
	},
})

local MissingStats = ns:NewModule("MissingStats", "missingStats", { group = "skins", title = L["Missing Stats"], order = 25 })

-- CharacterStatsPane is anchored to InsetRight in CharacterFrame.xml (12.0.7).
-- Extra rows from AddMissingStatRows exceed that viewport; wrap the pane in a
-- Extra stat rows live in the scroll child without touching Blizzard's categories.
local scrollContainer
local scrollFrame
local scrollChild
local scrollInstalled = false
local extentPending = false
local extentPendingCombat = false

local INSET_PAD_LEFT = 3
local INSET_PAD_TOP = -3
local INSET_PAD_RIGHT = -3
local INSET_PAD_BOTTOM = 2

local function GetPaneContentHeight(pane)
	local paneTop = pane:GetTop()
	if not paneTop or F.IsSecret(paneTop) then
		return 1
	end

	local lowestBottom = paneTop
	local function track(frame)
		if frame and frame.IsShown and frame:IsShown() then
			local bottom = frame:GetBottom()
			if bottom and not F.IsSecret(bottom) and bottom < lowestBottom then
				lowestBottom = bottom
			end
		end
	end

	track(pane.ItemLevelCategory)
	track(pane.ItemLevelFrame)
	track(pane.AttributesCategory)
	track(pane.EnhancementsCategory)
	for statFrame in pane.statsFramePool:EnumerateActive() do
		track(statFrame)
	end

	if F.IsSecret(lowestBottom) then
		return 1
	end
	return max(paneTop - lowestBottom + 16, 1)
end

local function UpdateStatsScrollExtent()
	if not (scrollChild and scrollFrame and scrollContainer) then
		return
	end

	if InCombatLockdown() then
		extentPendingCombat = true
		return
	end

	local pane = CharacterStatsPane
	local width = scrollContainer:GetWidth()
	if not width or width <= 0 or F.IsSecret(width) then
		width = 200
	end

	local height = GetPaneContentHeight(pane)
	if F.IsSecret(height) then
		return
	end
	scrollChild:SetSize(width, height)
	if scrollFrame.UpdateScrollChildRect then
		scrollFrame:UpdateScrollChildRect()
	end

	local range = scrollFrame:GetVerticalScrollRange()
	local scroll = scrollFrame:GetVerticalScroll()
	if not F.IsSecret(range) and not F.IsSecret(scroll) and scroll > range then
		scrollFrame:SetVerticalScroll(range)
	end
end

local function ScheduleStatsScrollExtent()
	if extentPending then
		return
	end
	extentPending = true
	C_Timer.After(0, function()
		extentPending = false
		UpdateStatsScrollExtent()
	end)
end

local function OnStatsScrollWheel(frame, delta)
	local cur = frame:GetVerticalScroll()
	local range = frame:GetVerticalScrollRange()
	if F.IsSecret(cur) or F.IsSecret(range) or F.IsSecret(delta) then
		return
	end
	local step = 20
	frame:SetVerticalScroll(max(0, min(range, cur - delta * step)))
end

local function SyncScrollContainerVisibility()
	if scrollContainer and CharacterStatsPane then
		scrollContainer:SetShown(CharacterStatsPane:IsShown())
	end
end

local function InstallStatsScrollFrame()
	if scrollInstalled then
		SyncScrollContainerVisibility()
		ScheduleStatsScrollExtent()
		return true
	end

	local inset = _G.CharacterFrameInsetRight
	local pane = CharacterStatsPane
	if not (inset and pane) then
		return false
	end

	scrollInstalled = true

	scrollContainer = CreateFrame("Frame", nil, inset)
	scrollContainer:SetPoint("TOPLEFT", inset, "TOPLEFT", INSET_PAD_LEFT, INSET_PAD_TOP)
	scrollContainer:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", INSET_PAD_RIGHT, INSET_PAD_BOTTOM)
	scrollContainer:SetFrameLevel(inset:GetFrameLevel() + 2)
	scrollContainer:SetScript("OnSizeChanged", function(self)
		if scrollChild then
			scrollChild:SetWidth(self:GetWidth())
			ScheduleStatsScrollExtent()
		end
	end)

	-- Plain ScrollFrame only: ScrollFrameTemplate's OnLoad auto-creates a
	-- MinimalScrollBar in 12.0; we scroll via mouse wheel with no visible bar.
	scrollFrame = CreateFrame("ScrollFrame", "NexEnhanceCharacterStatsScroll", scrollContainer)
	scrollFrame:SetAllPoints()
	scrollFrame:EnableMouseWheel(true)
	scrollFrame:SetScript("OnMouseWheel", OnStatsScrollWheel)

	scrollChild = CreateFrame("Frame", nil, scrollFrame)
	scrollChild:SetSize(scrollContainer:GetWidth() or 200, 1)
	scrollFrame:SetScrollChild(scrollChild)

	-- Pane fills the scroll child; child height is set after layout.
	pane:ClearAllPoints()
	pane:SetParent(scrollChild)
	pane:SetAllPoints(scrollChild)

	pane:HookScript("OnShow", function()
		SyncScrollContainerVisibility()
		ScheduleStatsScrollExtent()
	end)
	pane:HookScript("OnHide", SyncScrollContainerVisibility)

	if type(_G.PaperDollFrame_UpdateSidebarTabs) == "function" then
		hooksecurefunc("PaperDollFrame_UpdateSidebarTabs", SyncScrollContainerVisibility)
	end

	local paperDoll = _G.PaperDollFrame
	if paperDoll then
		paperDoll:HookScript("OnShow", function()
			if scrollFrame then
				scrollFrame:SetVerticalScroll(0)
			end
			ScheduleStatsScrollExtent()
		end)
	end

	SyncScrollContainerVisibility()
	ScheduleStatsScrollExtent()

	if _G.PaperDollFrame and _G.PaperDollFrame:IsShown() and type(_G.PaperDollFrame_UpdateStats) == "function" then
		_G.PaperDollFrame_UpdateStats()
	end
	return true
end

local function EnsureStatsScrollFrame()
	if scrollInstalled then
		return true
	end
	if InstallStatsScrollFrame() then
		return true
	end
	if not MissingStats.deferredScrollInstall then
		MissingStats.deferredScrollInstall = true
		local paperDoll = _G.PaperDollFrame
		if paperDoll then
			paperDoll:HookScript("OnShow", function()
				InstallStatsScrollFrame()
			end)
		end
	end
	return scrollInstalled
end

-- primary: only show for the spec whose primary stat matches.
-- roles: only show if the spec's role is one of these.
-- hideAt: hide when numericValue equals this (for example, 0 = not applicable).
local MISSING_STATS = {
	{ stat = "ATTACK_DAMAGE", primary = LE_UNIT_STAT_STRENGTH, roles = { Enum.LFGRole.Tank, Enum.LFGRole.Damage } },
	{ stat = "ATTACK_AP", hideAt = 0, primary = LE_UNIT_STAT_STRENGTH, roles = { Enum.LFGRole.Tank, Enum.LFGRole.Damage } },
	{ stat = "ATTACK_ATTACKSPEED", primary = LE_UNIT_STAT_STRENGTH, roles = { Enum.LFGRole.Tank, Enum.LFGRole.Damage } },
	{ stat = "ATTACK_DAMAGE", primary = LE_UNIT_STAT_AGILITY, roles = { Enum.LFGRole.Tank, Enum.LFGRole.Damage } },
	{ stat = "ATTACK_AP", hideAt = 0, primary = LE_UNIT_STAT_AGILITY, roles = { Enum.LFGRole.Tank, Enum.LFGRole.Damage } },
	{ stat = "ATTACK_ATTACKSPEED", primary = LE_UNIT_STAT_AGILITY, roles = { Enum.LFGRole.Tank, Enum.LFGRole.Damage } },
	{ stat = "SPELLPOWER", hideAt = 0, primary = LE_UNIT_STAT_INTELLECT },
	{ stat = "MANAREGEN", hideAt = 0, primary = LE_UNIT_STAT_INTELLECT },
	{ stat = "ENERGY_REGEN", hideAt = 0, primary = LE_UNIT_STAT_AGILITY },
	{ stat = "RUNE_REGEN", hideAt = 0, primary = LE_UNIT_STAT_STRENGTH },
	{ stat = "FOCUS_REGEN", hideAt = 0, primary = LE_UNIT_STAT_AGILITY },
	{ stat = "MOVESPEED" },
}

local function HasRole(roles, role)
	if not roles then
		return true
	end

	for i = 1, #roles do
		if roles[i] == role then
			return true
		end
	end
	return false
end

local function ShouldShowMissingStat(stat, spec, role)
	if stat.primary and spec then
		local primaryStat = select(6, C_SpecializationInfo.GetSpecializationInfo(spec, false, false, nil, UnitSex("player")))
		if primaryStat ~= stat.primary then
			return false
		end
	end

	return HasRole(stat.roles, role)
end

local function AddMissingStatRows()
	if InCombatLockdown() then
		return
	end

	local pane = CharacterStatsPane
	local pool = pane and pane.statsFramePool
	local enhancements = pane and pane.EnhancementsCategory
	if not (pool and enhancements) then
		return
	end

	local _, anchor = enhancements:GetPoint()
	if not anchor then
		return
	end

	local spec = C_SpecializationInfo.GetSpecialization()
	local role = spec and GetSpecializationRoleEnum(spec)
	local lastAnchor = anchor
	local numAdded = 0

	for i = 1, #MISSING_STATS do
		local stat = MISSING_STATS[i]
		local info = PAPERDOLL_STATINFO[stat.stat]
		if info and ShouldShowMissingStat(stat, spec, role) then
			local statFrame = pool:Acquire()
			statFrame:ClearAllPoints()
			statFrame.onEnterFunc = nil
			statFrame.UpdateTooltip = nil
			statFrame.numericValue = 0

			info.updateFunc(statFrame, "player")

			local value = statFrame.numericValue
			if statFrame:IsShown() and not F.IsSecret(value) and (not stat.hideAt or stat.hideAt ~= value) then
				statFrame:SetPoint("TOP", lastAnchor, "BOTTOM", 0, 0)
				numAdded = numAdded + 1
				if statFrame.Background then
					statFrame.Background:SetShown((numAdded % 2) == 0)
				end
				lastAnchor = statFrame
			else
				pool:Release(statFrame)
			end
		end
	end

	if numAdded > 0 then
		enhancements:ClearAllPoints()
		enhancements:SetPoint("TOP", lastAnchor, "BOTTOM", 0, 0)
	end
end

-- ---------------------------------------------------------------------------
-- Item level: show "equipped / overall" (with a decimal) when they differ.
-- Item level is not Secret today, but guard anyway so a future predicate can
-- only fall back to Blizzard's value instead of erroring.
-- ---------------------------------------------------------------------------
local function EnhanceItemLevel(statFrame, unit)
	if not MissingStats:IsEnabled() then
		return
	end
	if unit ~= "player" then
		return
	end

	local avgItemLevel, avgItemLevelEquipped = GetAverageItemLevel()
	local minItemLevel = C_PaperDollInfo.GetMinItemLevel()
	if F.IsSecret(avgItemLevel) or F.IsSecret(avgItemLevelEquipped) or F.IsSecret(minItemLevel) then
		return
	end

	local displayItemLevel = max(minItemLevel or 0, avgItemLevelEquipped or 0)
	local equipped = format("%.1f", displayItemLevel)
	local overall = format("%.1f", avgItemLevel or 0)
	if equipped ~= overall then
		equipped = equipped .. " / " .. overall
	end

	PaperDollFrame_SetLabelAndText(statFrame, STAT_AVERAGE_ITEM_LEVEL, equipped, false, displayItemLevel)
end

-- ---------------------------------------------------------------------------
-- Rating percentages: Blizzard rounds to a whole number; show two decimals.
-- ---------------------------------------------------------------------------
local function EnhancePercentage(statFrame, label, _, isPercentage)
	if not MissingStats:IsEnabled() then
		return
	end
	if not (isPercentage or label == STAT_HASTE) then
		return
	end

	local value = statFrame.numericValue
	if F.IsSecret(value) then
		return
	end -- 12.0: leave Blizzard's rounded text

	statFrame.Value:SetFormattedText("%.2f%%", value)
end

-- ---------------------------------------------------------------------------
-- A slightly larger, cleaner font for the stat rows.
-- ---------------------------------------------------------------------------
-- Shrink a font string by `delta` points, keeping its face and flags.
local function ShrinkFont(fontString, delta)
	local face, size, flags = fontString:GetFont()
	if face and size then
		fontString:SetFont(face, size - delta, flags)
	end
end

local function StyleStatFonts()
	for statFrame in CharacterStatsPane.statsFramePool:EnumerateActive() do
		if not statFrame.nexStyled then
			if Game13Font then
				statFrame.Label:SetFontObject(Game13Font)
				statFrame.Value:SetFontObject(Game13Font)
			end
			ShrinkFont(statFrame.Label, 2)
			ShrinkFont(statFrame.Value, 2)
			statFrame.nexStyled = true
		end
	end
end

-- Blizzard tints the item-level readout by quality (blue/purple/etc); when it
-- has no tint the text is plain white. Repaint just the white case as artifact
-- gold and leave Blizzard's coloured cases alone.
local function ColorItemLevel()
	local value = CharacterStatsPane.ItemLevelFrame and CharacterStatsPane.ItemLevelFrame.Value
	if not (value and GetItemLevelColor) then
		return
	end

	local r, g, b = GetItemLevelColor()
	if not (r and g and b) or F.IsSecret(r) or F.IsSecret(g) or F.IsSecret(b) then
		return
	end

	if r > 0.99 and g > 0.99 and b > 0.99 then
		value:SetTextColor(ARTIFACT_R, ARTIFACT_G, ARTIFACT_B)
	end
end

local function OnUpdateStats()
	if not MissingStats:IsEnabled() or InCombatLockdown() then
		return
	end
	AddMissingStatRows()
	StyleStatFonts()
	ColorItemLevel()
	ScheduleStatsScrollExtent()
end

function MissingStats:PLAYER_REGEN_ENABLED()
	if not self:IsEnabled() then
		return
	end
	if extentPendingCombat then
		extentPendingCombat = false
		UpdateStatsScrollExtent()
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function MissingStats:OnEnable()
	-- Bail gracefully if the paperdoll surface isn't present/renamed.
	if not (PAPERDOLL_STATCATEGORIES and PAPERDOLL_STATINFO and CharacterStatsPane and type(PaperDollFrame_UpdateStats) == "function") then
		return
	end

	EnsureStatsScrollFrame()

	-- hooksecurefunc can't uninstall — handlers gate on IsEnabled().
	if not self._hooksInstalled then
		self._hooksInstalled = true
		if type(PaperDollFrame_SetItemLevel) == "function" then
			hooksecurefunc("PaperDollFrame_SetItemLevel", EnhanceItemLevel)
		end
		if type(PaperDollFrame_SetLabelAndText) == "function" then
			hooksecurefunc("PaperDollFrame_SetLabelAndText", EnhancePercentage)
		end
		hooksecurefunc("PaperDollFrame_UpdateStats", OnUpdateStats)
	end
	MissingStats:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function MissingStats:OnDisable()
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	extentPendingCombat = false
end

function MissingStats:OnSettingChanged(key)
	if key == "enable" then
		return
	end
end

function MissingStats:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Missing Stats"], L["Show the hidden character-sheet stats (attack power, weapon speed, spell power, regen, movement) and tidy the readouts (reload to fully restore Blizzard layout)."])
end
