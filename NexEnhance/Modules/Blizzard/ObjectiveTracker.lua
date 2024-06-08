local _, Module = ...

-- Extract color components for easier reference
local red, green, blue = Module.r, Module.g, Module.b

-- Function to apply skin to a header
function Module:ApplyHeaderSkin(header)
	header.Text:SetTextColor(red, green, blue)
	header.Background:SetTexture(nil)

	local backgroundTexture = header:CreateTexture(nil, "ARTWORK")
	backgroundTexture:SetTexture("Interface\\LFGFrame\\UI-LFG-SEPARATOR")
	backgroundTexture:SetTexCoord(0, 0.66, 0, 0.31)
	backgroundTexture:SetVertexColor(red, green, blue, 0.8)
	backgroundTexture:SetPoint("BOTTOMLEFT", 0, -4)
	backgroundTexture:SetSize(250, 30)

	header.bg = backgroundTexture -- Make accessible for other addons
end

-- Function triggered on PLAYER_LOGIN event
function Module:PLAYER_LOGIN()
	if not self.db.profile.blizzard.objectiveTracker then
		return
	end

	local headers = {
		_G.BONUS_OBJECTIVE_TRACKER_MODULE.Header,
		-- _G.MONTHLY_ACTIVITIES_TRACKER_MODULE.Header,
		_G.ObjectiveTrackerBlocksFrame.AchievementHeader,
		_G.ObjectiveTrackerBlocksFrame.CampaignQuestHeader,
		_G.ObjectiveTrackerBlocksFrame.ProfessionHeader,
		_G.ObjectiveTrackerBlocksFrame.QuestHeader,
		_G.ObjectiveTrackerBlocksFrame.ScenarioHeader,
		_G.ObjectiveTrackerFrame.BlocksFrame.UIWidgetsHeader,
		_G.WORLD_QUEST_TRACKER_MODULE.Header,
	}

	for _, header in pairs(headers) do
		self:ApplyHeaderSkin(header)
	end
end
