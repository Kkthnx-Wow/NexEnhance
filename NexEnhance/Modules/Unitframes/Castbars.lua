local _, Module = ...

local function UpdateCastbarText(castingFrame)
	if not castingFrame.timer then
		return
	end

	local value = castingFrame.value or 0
	local maxValue = castingFrame.maxValue or 0

	if castingFrame.casting then
		castingFrame.timer:SetText(("%.1f/%.1f"):format(max(maxValue - value, 0), maxValue))
	elseif castingFrame.channeling then
		castingFrame.timer:SetText(("%.1f"):format(max(value, 0)))
	else
		castingFrame.timer:SetText("")
	end
end

local function UpdateCastbarIcons(castingFrame)
	PlayerCastingBarFrame.Icon:ClearAllPoints()
	PlayerCastingBarFrame.Icon:SetPoint("BOTTOM", castingFrame, "TOP", 0, 4)
	PlayerCastingBarFrame.Icon:SetSize(26, 26)
	PlayerCastingBarFrame.Icon:Show()
end

local function CreateCastbarTimer()
	PlayerCastingBarFrame.timer = PlayerCastingBarFrame:CreateFontString(nil, "OVERLAY")
	PlayerCastingBarFrame.timer:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
	PlayerCastingBarFrame.timer:SetPoint("TOP", PlayerCastingBarFrame, "BOTTOM", 0, 10)
	PlayerCastingBarFrame.timer:SetText("")

	TargetFrameSpellBar.timer = TargetFrameSpellBar:CreateFontString(nil, "OVERLAY")
	TargetFrameSpellBar.timer:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
	TargetFrameSpellBar.timer:SetPoint("TOP", TargetFrameSpellBar, "BOTTOM", 0, 10)
	TargetFrameSpellBar.timer:SetText("")

	FocusFrameSpellBar.timer = FocusFrameSpellBar:CreateFontString(nil, "OVERLAY")
	FocusFrameSpellBar.timer:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
	FocusFrameSpellBar.timer:SetPoint("TOP", FocusFrameSpellBar, "BOTTOM", 0, 10)
	FocusFrameSpellBar.timer:SetText("")
end

function Module:PLAYER_LOGIN()
	CreateCastbarTimer()

	local function HookCastbarOnValueChanged(frame)
		frame:HookScript("OnValueChanged", function(self)
			UpdateCastbarIcons(self)
			UpdateCastbarText(self)
		end)
	end

	HookCastbarOnValueChanged(PlayerCastingBarFrame)
	HookCastbarOnValueChanged(TargetFrameSpellBar)
	HookCastbarOnValueChanged(FocusFrameSpellBar)
end
