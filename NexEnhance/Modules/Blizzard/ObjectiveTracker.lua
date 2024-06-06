local NexEnhance, NE_ObjectiveTracker = ...

function NE_ObjectiveTracker:ReskinHeader(header)
	if not header then
		return
	end

	if header.Background then
		header.Background:SetAtlas(nil)
	end

	if header.Text then
		header.Text:SetTextColor(240 / 255, 197 / 255, 0 / 255, 0.8)
	end

	local bg = header:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\LFGFrame\\UI-LFG-SEPARATOR")
	bg:SetTexCoord(0, 0.66, 0, 0.31)
	bg:SetVertexColor(240 / 255, 197 / 255, 0 / 255, 0.8)
	bg:SetPoint("BOTTOMLEFT", 0, -4)
	bg:SetSize(250, 30)
	header.bg = bg -- accessable for other addons
end

-- Reskin Headers
function NE_ObjectiveTracker:PLAYER_LOGIN()
	if not NE_ObjectiveTracker.db.profile.blizzard.objectiveTracker then
		return
	end

	local headers = {
		_G.BONUS_OBJECTIVE_TRACKER_MODULE.Header,
		-- _G.MONTHLY_ACTIVITIES_TRACKER_MODULE,
		_G.ObjectiveTrackerBlocksFrame.AchievementHeader,
		_G.ObjectiveTrackerBlocksFrame.CampaignQuestHeader,
		_G.ObjectiveTrackerBlocksFrame.ProfessionHeader,
		_G.ObjectiveTrackerBlocksFrame.QuestHeader,
		_G.ObjectiveTrackerBlocksFrame.ScenarioHeader,
		_G.ObjectiveTrackerFrame.BlocksFrame.UIWidgetsHeader,
		_G.WORLD_QUEST_TRACKER_MODULE.Header,
	}

	for _, header in pairs(headers) do
		NE_ObjectiveTracker:ReskinHeader(header)
	end
end
