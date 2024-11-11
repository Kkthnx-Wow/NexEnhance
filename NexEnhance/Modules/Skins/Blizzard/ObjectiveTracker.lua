local _, Module = ...

local hooksecurefunc = hooksecurefunc

-- Reskin header function
local function ReskinObjectiveHeader(header)
	if not header then
		return
	end

	if header.Background then
		header.Background:SetAtlas(nil)
	end

	if header.Text then
		header.Text:SetFontObject("GameFontNormal")
		header.Text:SetFont(select(1, header.Text:GetFont()), 15, select(3, header.Text:GetFont()))
		header.Text:SetTextColor(Module.r, Module.g, Module.b)
	end
end

-- Register skinning functions
function Module:PLAYER_LOGIN()
	if C_AddOns.IsAddOnLoaded("!KalielsTracker") then
		return
	end

	-- Reskin Headers
	local headers = {
		_G.BONUS_OBJECTIVE_TRACKER_MODULE.Header,
		_G.ObjectiveTrackerBlocksFrame.AchievementHeader,
		_G.ObjectiveTrackerBlocksFrame.CampaignQuestHeader,
		_G.ObjectiveTrackerBlocksFrame.ProfessionHeader,
		_G.ObjectiveTrackerBlocksFrame.QuestHeader,
		_G.ObjectiveTrackerBlocksFrame.ScenarioHeader,
		_G.ObjectiveTrackerFrame.BlocksFrame.UIWidgetsHeader,
		_G.WORLD_QUEST_TRACKER_MODULE.Header,
	}
	for _, header in pairs(headers) do
		ReskinObjectiveHeader(header)
	end
end
