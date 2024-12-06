local _, Module = ...

local format, max = string.format, math.max
local BreakUpLargeNumbers, GetMeleeHaste, UnitAttackSpeed = BreakUpLargeNumbers, GetMeleeHaste, UnitAttackSpeed
local GetAverageItemLevel, C_PaperDollInfo_GetMinItemLevel = GetAverageItemLevel, C_PaperDollInfo.GetMinItemLevel
local PaperDollFrame_SetLabelAndText = PaperDollFrame_SetLabelAndText
local HIGHLIGHT_FONT_COLOR_CODE, FONT_COLOR_CODE_CLOSE = HIGHLIGHT_FONT_COLOR_CODE, FONT_COLOR_CODE_CLOSE
local STAT_HASTE, ATTACK_SPEED, STAT_AVERAGE_ITEM_LEVEL = STAT_HASTE, ATTACK_SPEED, STAT_AVERAGE_ITEM_LEVEL
local WEAPON_SPEED, PAPERDOLLFRAME_TOOLTIP_FORMAT, STAT_ATTACK_SPEED_BASE_TOOLTIP = WEAPON_SPEED, PAPERDOLLFRAME_TOOLTIP_FORMAT, STAT_ATTACK_SPEED_BASE_TOOLTIP

function Module:PLAYER_LOGIN()
	if not (Module.NexConfig and Module.NexConfig.miscellaneous and Module.NexConfig.miscellaneous.missingStats) then
		return
	end

	if C_AddOns and C_AddOns.IsAddOnLoaded("DejaCharacterStats") then
		return
	end

	local statPanel = CreateFrame("Frame", nil, CharacterFrameInsetRight)
	statPanel:SetSize(200, 350)
	statPanel:SetPoint("TOP", 0, -5)

	local scrollFrame = CreateFrame("ScrollFrame", nil, statPanel, "UIPanelScrollFrameTemplate")
	scrollFrame:SetAllPoints()
	if scrollFrame.ScrollBar then
		scrollFrame.ScrollBar:Hide()
		scrollFrame.ScrollBar.Show = Module.Noop
	end

	local stat = CreateFrame("Frame", nil, scrollFrame)
	stat:SetSize(200, 1)
	scrollFrame:SetScrollChild(stat)

	if CharacterStatsPane then
		CharacterStatsPane:ClearAllPoints()
		CharacterStatsPane:SetParent(stat)
		CharacterStatsPane:SetAllPoints(stat)

		hooksecurefunc("PaperDollFrame_UpdateSidebarTabs", function()
			if statPanel then
				statPanel:SetShown(CharacterStatsPane:IsShown())
			end
		end)
	end

	PAPERDOLL_STATCATEGORIES = {
		[1] = {
			categoryFrame = "AttributesCategory",
			stats = {
				{ stat = "STRENGTH", primary = LE_UNIT_STAT_STRENGTH },
				{ stat = "AGILITY", primary = LE_UNIT_STAT_AGILITY },
				{ stat = "INTELLECT", primary = LE_UNIT_STAT_INTELLECT },
				{ stat = "STAMINA" },
				{ stat = "ARMOR" },
				{ stat = "STAGGER", hideAt = 0, roles = { Enum.LFGRole.Tank } },
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
			},
		},
		[2] = {
			categoryFrame = "EnhancementsCategory",
			stats = {
				{ stat = "CRITCHANCE", hideAt = 0 },
				{ stat = "HASTE", hideAt = 0 },
				{ stat = "MASTERY", hideAt = 0 },
				{ stat = "VERSATILITY", hideAt = 0 },
				{ stat = "LIFESTEAL", hideAt = 0 },
				{ stat = "AVOIDANCE", hideAt = 0 },
				{ stat = "SPEED", hideAt = 0 },
				{ stat = "DODGE", roles = { Enum.LFGRole.Tank } },
				{ stat = "PARRY", hideAt = 0, roles = { Enum.LFGRole.Tank } },
				{ stat = "BLOCK", hideAt = 0, showFunc = C_PaperDollInfo.OffhandHasShield },
			},
		},
	}

	if PAPERDOLL_STATINFO then
		PAPERDOLL_STATINFO["ENERGY_REGEN"].updateFunc = function(statFrame, unit)
			if statFrame then
				statFrame.numericValue = 0
				PaperDollFrame_SetEnergyRegen(statFrame, unit)
			end
		end

		PAPERDOLL_STATINFO["RUNE_REGEN"].updateFunc = function(statFrame, unit)
			if statFrame then
				statFrame.numericValue = 0
				PaperDollFrame_SetRuneRegen(statFrame, unit)
			end
		end

		PAPERDOLL_STATINFO["FOCUS_REGEN"].updateFunc = function(statFrame, unit)
			if statFrame then
				statFrame.numericValue = 0
				PaperDollFrame_SetFocusRegen(statFrame, unit)
			end
		end
	end

	function PaperDollFrame_SetAttackSpeed(statFrame, unit)
		local meleeHaste = GetMeleeHaste()
		local speed, offhandSpeed = UnitAttackSpeed(unit)
		local displaySpeed = format("%.2f", speed)
		if offhandSpeed then
			offhandSpeed = format("%.2f", offhandSpeed)
			displaySpeed = BreakUpLargeNumbers(displaySpeed) .. " / " .. offhandSpeed
		else
			displaySpeed = BreakUpLargeNumbers(displaySpeed)
		end
		PaperDollFrame_SetLabelAndText(statFrame, WEAPON_SPEED, displaySpeed, false, speed)

		statFrame.tooltip = HIGHLIGHT_FONT_COLOR_CODE .. format(PAPERDOLLFRAME_TOOLTIP_FORMAT, ATTACK_SPEED) .. " " .. displaySpeed .. FONT_COLOR_CODE_CLOSE
		statFrame.tooltip2 = format(STAT_ATTACK_SPEED_BASE_TOOLTIP, BreakUpLargeNumbers(meleeHaste))
		statFrame:Show()
	end

	hooksecurefunc("PaperDollFrame_SetItemLevel", function(statFrame, unit)
		if unit ~= "player" then
			return
		end

		local avgItemLevel, avgItemLevelEquipped = GetAverageItemLevel()
		local minItemLevel = C_PaperDollInfo_GetMinItemLevel()
		local displayItemLevel = max(minItemLevel or 0, avgItemLevelEquipped)
		displayItemLevel = format("%.1f", displayItemLevel)
		avgItemLevel = format("%.1f", avgItemLevel)

		if displayItemLevel ~= avgItemLevel then
			displayItemLevel = displayItemLevel .. " / " .. avgItemLevel
		end
		PaperDollFrame_SetLabelAndText(statFrame, STAT_AVERAGE_ITEM_LEVEL, displayItemLevel, false, displayItemLevel)
	end)

	hooksecurefunc("PaperDollFrame_SetLabelAndText", function(statFrame, label, _, isPercentage)
		if statFrame and (isPercentage or label == STAT_HASTE) then
			statFrame.Value:SetFormattedText("%.2f%%", statFrame.numericValue)
		end
	end)

	hooksecurefunc("PaperDollFrame_UpdateStats", function()
		if CharacterStatsPane and CharacterStatsPane.statsFramePool then
			for statFrame in CharacterStatsPane.statsFramePool:EnumerateActive() do
				if not statFrame.styled then
					if statFrame.Label then
						statFrame.Label:SetFontObject(Game11Font)
					end
					if statFrame.Value then
						statFrame.Value:SetFontObject(Game11Font)
					end

					statFrame.styled = true
				end
			end
		end
	end)
end
