--[[
	NexEnhance - MissingStats
	-------------------------------------------------------------------------
	Surfaces the character-sheet stats Blizzard hides by default - attack
	power, weapon damage, attack/weapon speed, spell power, energy / rune /
	focus regen and movement speed - and tidies the existing readouts:
	per-decimal rating percentages, equipped + overall item level, and a
	cleaner stat font.

	Reworked from NDui's Modules/Misc/MissingStats.lua (by siweia) against the
	current retail PaperDollFrame (Blizzard_UIPanels_Game/Mainline):

	  * The extra stat rows are added after Blizzard's live update finishes,
	    instead of replacing PAPERDOLL_STATCATEGORIES. Replacing that global
	    taints Blizzard's own UnitStat comparisons in combat on Midnight.
	  * Blizzard already renders off-hand attack speed and the item-level
	    tooltip itself, so those NDui overrides are dropped.
	  * Every value our hooks touch is gated behind a Secret-value check (12.0)
	    before any arithmetic / formatting; if a value is ever Secret we leave
	    Blizzard's own readout untouched rather than erroring.

	The extra rows intentionally do not render while in combat. Some PaperDoll
	stat APIs return Secret values in combat, and Blizzard's own setters compare
	those values internally. Keeping the stock update loop clean avoids taint.
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
local hooksecurefunc = hooksecurefunc
local select = select

local GetAverageItemLevel = GetAverageItemLevel
local GetItemLevelColor = GetItemLevelColor
local InCombatLockdown = InCombatLockdown
local GetSpecializationRoleEnum = GetSpecializationRoleEnum
local UnitSex = UnitSex
local C_SpecializationInfo = C_SpecializationInfo
local C_PaperDollInfo = C_PaperDollInfo
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
	AddMissingStatRows()
	StyleStatFonts()
	ColorItemLevel()
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function MissingStats:OnEnable()
	-- Bail gracefully if the paperdoll surface isn't present/renamed.
	if not (PAPERDOLL_STATCATEGORIES and PAPERDOLL_STATINFO and CharacterStatsPane and type(PaperDollFrame_UpdateStats) == "function") then
		return
	end

	if type(PaperDollFrame_SetItemLevel) == "function" then
		hooksecurefunc("PaperDollFrame_SetItemLevel", EnhanceItemLevel)
	end
	if type(PaperDollFrame_SetLabelAndText) == "function" then
		hooksecurefunc("PaperDollFrame_SetLabelAndText", EnhancePercentage)
	end
	hooksecurefunc("PaperDollFrame_UpdateStats", OnUpdateStats)
end

function MissingStats:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Missing Stats"], L["Show the hidden character-sheet stats (attack power, weapon speed, spell power, regen, movement) and tidy the readouts (reload to disable)."])
end
