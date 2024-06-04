local _, addon = ...

local betterQuestTracker

addon:RegisterOptionCallback("betterQuestTracker", function(value)
	betterQuestTracker = value
end)

function addon:reskinHeader(header)
	if not header or not betterQuestTracker then
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
function addon:PLAYER_LOGIN()
	if not betterQuestTracker then
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
		addon:reskinHeader(header)
	end
end
