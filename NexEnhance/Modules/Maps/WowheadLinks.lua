local _, Module = ...

-- Wowhead Links

local GameLocale = GetLocale()

function Module:PLAYER_LOGIN()
	-- Get localised Wowhead URL
	local wowheadLoc
	if GameLocale == "deDE" then
		wowheadLoc = "de.wowhead.com"
	elseif GameLocale == "esMX" then
		wowheadLoc = "es.wowhead.com"
	elseif GameLocale == "esES" then
		wowheadLoc = "es.wowhead.com"
	elseif GameLocale == "frFR" then
		wowheadLoc = "fr.wowhead.com"
	elseif GameLocale == "itIT" then
		wowheadLoc = "it.wowhead.com"
	elseif GameLocale == "ptBR" then
		wowheadLoc = "pt.wowhead.com"
	elseif GameLocale == "ruRU" then
		wowheadLoc = "ru.wowhead.com"
	elseif GameLocale == "koKR" then
		wowheadLoc = "ko.wowhead.com"
	elseif GameLocale == "zhCN" then
		wowheadLoc = "cn.wowhead.com"
	elseif GameLocale == "zhTW" then
		wowheadLoc = "cn.wowhead.com"
	else
		wowheadLoc = "wowhead.com"
	end

	----------------------------------------------------------------------
	-- Achievements frame
	----------------------------------------------------------------------

	-- Achievement link function
	EventUtil.ContinueOnAddOnLoaded("Blizzard_AchievementUI", function()
		-- Create editbox
		local aEB = CreateFrame("EditBox", nil, AchievementFrame)
		aEB:ClearAllPoints()
		aEB:SetPoint("BOTTOMRIGHT", -50, 1)
		aEB:SetHeight(16)
		aEB:SetFontObject("GameFontNormalSmall")
		aEB:SetBlinkSpeed(0)
		aEB:SetJustifyH("RIGHT")
		aEB:SetAutoFocus(false)
		aEB:EnableKeyboard(false)
		aEB:SetHitRectInsets(90, 0, 0, 0)
		aEB:SetScript("OnKeyDown", function() end)
		aEB:SetScript("OnMouseUp", function()
			if aEB:IsMouseOver() then
				aEB:HighlightText()
			else
				aEB:HighlightText(0, 0)
			end
		end)

		-- Create hidden font string (used for setting width of editbox)
		aEB.z = aEB:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		aEB.z:Hide()

		-- Store last link in case editbox is cleared
		local lastAchievementLink

		-- Function to set editbox value
		local function SetAchievementFunc(self, achievementID)
			if achievementID then
				-- Set editbox text
				aEB:SetText("https://" .. wowheadLoc .. "/achievement=" .. achievementID)
				lastAchievementLink = aEB:GetText()
				-- Set hidden fontstring then resize editbox to match
				aEB.z:SetText(aEB:GetText())
				aEB:SetWidth(aEB.z:GetStringWidth() + 90)
				-- Get achievement title for tooltip
				local achievementLink = GetAchievementLink(achievementID)
				if achievementLink then
					aEB.tiptext = achievementLink:match("%[(.-)%]") .. "|n|n" .. Module.InfoColor .. "Press CTRL/C to copy."
				end
				-- Show the editbox
				aEB:Show()
			end
		end
		hooksecurefunc(AchievementTemplateMixin, "DisplayObjectives", SetAchievementFunc)
		hooksecurefunc("AchievementFrameComparisonTab_OnClick", function(self)
			aEB:Hide()
		end)

		-- Create tooltip
		aEB:HookScript("OnEnter", function()
			aEB:HighlightText()
			aEB:SetFocus()
			GameTooltip:SetOwner(aEB, "ANCHOR_TOP", 0, 10)
			GameTooltip:SetText(aEB.tiptext, nil, nil, nil, nil, true)
			GameTooltip:Show()
		end)

		aEB:HookScript("OnLeave", function()
			-- Set link text again if it's changed since it was set
			if aEB:GetText() ~= lastAchievementLink then
				aEB:SetText(lastAchievementLink)
			end
			aEB:HighlightText(0, 0)
			aEB:ClearFocus()
			GameTooltip:Hide()
		end)
	end)

	----------------------------------------------------------------------
	-- World map frame
	----------------------------------------------------------------------

	-- Hide the title text
	WorldMapFrameTitleText:Hide()

	-- Create editbox
	local mEB = CreateFrame("EditBox", nil, WorldMapFrame.BorderFrame)
	mEB:SetFrameLevel(501)
	mEB:ClearAllPoints()
	mEB:SetPoint("TOPLEFT", 100, -4)
	mEB:SetHeight(16)
	mEB:SetFontObject("GameFontNormal")
	mEB:SetBlinkSpeed(0)
	mEB:SetAutoFocus(false)
	mEB:EnableKeyboard(false)
	mEB:SetHitRectInsets(0, 90, 0, 0)
	mEB:SetScript("OnKeyDown", function() end)
	mEB:SetScript("OnMouseUp", function()
		if mEB:IsMouseOver() then
			mEB:HighlightText()
		else
			mEB:HighlightText(0, 0)
		end
	end)

	-- Create hidden font string (used for setting width of editbox)
	mEB.z = mEB:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	mEB.z:Hide()

	-- Function to set editbox value
	local function SetQuestInBox()
		local questID
		if QuestMapFrame.DetailsFrame:IsShown() then
			-- Get quest ID from currently showing quest in details panel
			questID = QuestMapFrame_GetDetailQuestID()
		else
			-- Get quest ID from currently selected quest on world map
			questID = C_SuperTrack.GetSuperTrackedQuestID()
		end
		if questID then
			-- Hide editbox if quest ID is invalid
			if questID == 0 then
				mEB:Hide()
			else
				mEB:Show()
			end
			-- Set editbox text
			mEB:SetText("https://" .. wowheadLoc .. "/quest=" .. questID)
			-- Set hidden fontstring then resize editbox to match
			mEB.z:SetText(mEB:GetText())
			mEB:SetWidth(mEB.z:GetStringWidth() + 90)
			-- Get quest title for tooltip
			local questLink = GetQuestLink(questID) or nil
			if questLink then
				mEB.tiptext = questLink:match("%[(.-)%]") .. "|n|n" .. Module.InfoColor .. "Press CTRL/C to copy."
			else
				mEB.tiptext = ""
				if mEB:IsMouseOver() and GameTooltip:IsShown() then
					GameTooltip:Hide()
				end
			end
		end
	end

	-- Set URL when super tracked quest changes and on startup
	mEB:RegisterEvent("SUPER_TRACKING_CHANGED")
	mEB:SetScript("OnEvent", SetQuestInBox)
	SetQuestInBox()

	-- Set URL when quest details frame is shown or hidden
	hooksecurefunc("QuestMapFrame_ShowQuestDetails", SetQuestInBox)
	hooksecurefunc("QuestMapFrame_CloseQuestDetails", SetQuestInBox)

	-- Create tooltip
	mEB:HookScript("OnEnter", function()
		mEB:HighlightText()
		mEB:SetFocus()
		GameTooltip:SetOwner(mEB, "ANCHOR_BOTTOM", 0, -10)
		GameTooltip:SetText(mEB.tiptext, nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)

	mEB:HookScript("OnLeave", function()
		mEB:HighlightText(0, 0)
		mEB:ClearFocus()
		GameTooltip:Hide()
		SetQuestInBox()
	end)
end
