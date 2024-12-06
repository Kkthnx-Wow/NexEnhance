local _, Module = ...

local pairs = pairs
local IsAddOnLoaded = C_AddOns.IsAddOnLoaded
local hooksecurefunc = hooksecurefunc
local ObjectiveTrackerFrame = _G.ObjectiveTrackerFrame

local trackers = {
	_G.ScenarioObjectiveTracker,
	_G.UIWidgetObjectiveTracker,
	_G.CampaignQuestObjectiveTracker,
	_G.QuestObjectiveTracker,
	_G.AdventureObjectiveTracker,
	_G.AchievementObjectiveTracker,
	_G.MonthlyActivitiesObjectiveTracker,
	_G.ProfessionsRecipeTracker,
	_G.BonusObjectiveTracker,
	_G.WorldQuestObjectiveTracker,
}

local function SkinObjectiveTrackerHeaders(header)
	if header and header.Background then
		header.Background:SetAtlas(nil)
	end
end

local function SetCollapsed(header, collapsed)
	if not header or not header.MinimizeButton then
		return
	end

	local MinimizeButton = header.MinimizeButton
	local normalTexture = MinimizeButton:GetNormalTexture()
	local pushedTexture = MinimizeButton:GetPushedTexture()

	if normalTexture and pushedTexture then
		local expandAtlas = "UI-QuestTrackerButton-Secondary-Expand"
		local collapseAtlas = "UI-QuestTrackerButton-Secondary-Collapse"

		normalTexture:SetAtlas(collapsed and expandAtlas or collapseAtlas, true)
		pushedTexture:SetAtlas(collapsed and expandAtlas .. "-Pressed" or collapseAtlas .. "-Pressed", true)
	end
end

local function ReskinBarTemplate(bar)
	if bar and Module.r and Module.g and Module.b then
		bar:SetStatusBarColor(Module.r, Module.g, Module.b)
	end
end

local function HandleProgressBar(tracker, key)
	if tracker and tracker.usedProgressBars then
		local progressBar = tracker.usedProgressBars[key]
		local bar = progressBar and progressBar.Bar
		if bar then
			ReskinBarTemplate(bar)
		end
	end
end

local function HandleTimers(tracker, key)
	if tracker and tracker.usedTimerBars then
		local timerBar = tracker.usedTimerBars[key]
		local bar = timerBar and timerBar.Bar
		if bar then
			ReskinBarTemplate(bar)
		end
	end
end

function Module:PLAYER_LOGIN()
	if IsAddOnLoaded("!KalielsTracker") then
		return
	end

	if ObjectiveTrackerFrame then
		local TrackerHeader = ObjectiveTrackerFrame.Header
		if TrackerHeader then
			SkinObjectiveTrackerHeaders(TrackerHeader)

			local MinimizeButton = TrackerHeader.MinimizeButton
			if MinimizeButton then
				MinimizeButton:SetSize(16, 16)
				MinimizeButton:SetHighlightAtlas("UI-QuestTrackerButton-Yellow-Highlight", "ADD")

				SetCollapsed(TrackerHeader, ObjectiveTrackerFrame.isCollapsed)
				hooksecurefunc(TrackerHeader, "SetCollapsed", SetCollapsed)
			end
		end
	end

	for _, tracker in pairs(trackers) do
		if tracker and tracker.Header then
			SkinObjectiveTrackerHeaders(tracker.Header)
			hooksecurefunc(tracker, "GetProgressBar", HandleProgressBar)
			hooksecurefunc(tracker, "GetTimerBar", HandleTimers)
		end
	end
end
