--[[
	NexEnhance - ObjectiveTracker (skin)
	-------------------------------------------------------------------------
	Tidies the Blizzard quest/objective tracker so it sits quietly in the
	corner: hides the busy header backgrounds, shrinks/cleans the minimise
	button, and recolours quest progress and timer bars to a single calm
	colour (class colour by default, brand colour otherwise).

	Adapted from KkthnxUI by Josh "Kkthnx" Russell:
	  https://github.com/Kkthnx-Wow/KkthnxUI

	Integration notes:
	  * The tracker lives in the Blizzard_ObjectiveTracker addon. We style it
	    immediately if it is already loaded, otherwise we wait for its
	    ADDON_LOADED through the central dispatcher.
	  * All work is purely cosmetic and goes through hooksecurefunc, so it is
	    taint-safe around the secure tracker frames.
--]]

local _, ns = ...
local C, L = ns.C, ns.L

-- Localised globals.
local _G = _G
local hooksecurefunc = hooksecurefunc
local C_AddOns = C_AddOns

ns:RegisterDefaults({
	objectiveTracker = {
		enable = true,
		classColor = true,
	},
})

local ObjectiveTracker = ns:NewModule("ObjectiveTracker", "objectiveTracker", { group = "skins", title = L["Objective Tracker"], order = 10 })

-- ---------------------------------------------------------------------------
-- Colour helpers
-- ---------------------------------------------------------------------------
local function GetBarColor()
	local settings = ns.db and ns.db.objectiveTracker
	if settings and settings.classColor == false then
		return C.Colors.brand[1], C.Colors.brand[2], C.Colors.brand[3]
	end
	return C.ClassColor[1], C.ClassColor[2], C.ClassColor[3]
end

local function ReskinBar(bar)
	if bar then
		bar:SetStatusBarColor(GetBarColor())
	end
end

-- ---------------------------------------------------------------------------
-- Header + minimise button
-- ---------------------------------------------------------------------------
local function HideHeaderBackground(header)
	if header and header.Background then
		header.Background:Hide()
	end
end

local function SetCollapsed(header, collapsed)
	local minimize = header and header.MinimizeButton
	if not minimize then
		return
	end

	local normal = minimize:GetNormalTexture()
	local pushed = minimize:GetPushedTexture()
	if not (normal and pushed) then
		return
	end

	if collapsed then
		normal:SetAtlas("UI-QuestTrackerButton-Secondary-Expand", true)
		pushed:SetAtlas("UI-QuestTrackerButton-Secondary-Expand-Pressed", true)
	else
		normal:SetAtlas("UI-QuestTrackerButton-Secondary-Collapse", true)
		pushed:SetAtlas("UI-QuestTrackerButton-Secondary-Collapse-Pressed", true)
	end
end

-- ---------------------------------------------------------------------------
-- Per-tracker progress / timer bars (created on demand by Blizzard)
-- ---------------------------------------------------------------------------
local function HandleProgressBar(tracker, key)
	local progressBar = tracker.usedProgressBars and tracker.usedProgressBars[key]
	ReskinBar(progressBar and progressBar.Bar)
end

local function HandleTimerBar(tracker, key)
	local timerBar = tracker.usedTimerBars and tracker.usedTimerBars[key]
	ReskinBar(timerBar and timerBar.Bar)
end

-- Recolour any bars that are already on screen (used on a live setting change).
local function RecolorActiveBars(tracker)
	if tracker.usedProgressBars then
		for _, progressBar in pairs(tracker.usedProgressBars) do
			ReskinBar(progressBar and progressBar.Bar)
		end
	end
	if tracker.usedTimerBars then
		for _, timerBar in pairs(tracker.usedTimerBars) do
			ReskinBar(timerBar and timerBar.Bar)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Styling
-- ---------------------------------------------------------------------------
function ObjectiveTracker:Style()
	if self.styled then
		return
	end

	local TrackerFrame = _G["ObjectiveTrackerFrame"]
	if not TrackerFrame then
		return
	end

	self.styled = true

	local header = TrackerFrame.Header
	if header then
		HideHeaderBackground(header)

		local minimize = header.MinimizeButton
		if minimize then
			minimize:SetSize(16, 16)
			minimize:SetHighlightAtlas("UI-QuestTrackerButton-Yellow-Highlight", "ADD")
			SetCollapsed(header, TrackerFrame.isCollapsed)
			hooksecurefunc(header, "SetCollapsed", SetCollapsed)
		end
	end

	-- All sub-trackers that own headers and progress/timer bar pools.
	local trackers = {
		_G["ScenarioObjectiveTracker"],
		_G["UIWidgetObjectiveTracker"],
		_G["CampaignQuestObjectiveTracker"],
		_G["QuestObjectiveTracker"],
		_G["AdventureObjectiveTracker"],
		_G["AchievementObjectiveTracker"],
		_G["MonthlyActivitiesObjectiveTracker"],
		_G["ProfessionsRecipeTracker"],
		_G["BonusObjectiveTracker"],
		_G["WorldQuestObjectiveTracker"],
	}

	self.trackers = trackers

	for i = 1, #trackers do
		local tracker = trackers[i]
		if tracker then
			HideHeaderBackground(tracker.Header)
			if tracker.GetProgressBar then
				hooksecurefunc(tracker, "GetProgressBar", HandleProgressBar)
			end
			if tracker.GetTimerBar then
				hooksecurefunc(tracker, "GetTimerBar", HandleTimerBar)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function ObjectiveTracker:ADDON_LOADED(addon)
	if addon == "Blizzard_ObjectiveTracker" then
		self:Style()
	end
end

function ObjectiveTracker:OnEnable()
	if C_AddOns.IsAddOnLoaded("Blizzard_ObjectiveTracker") then
		self:Style()
	else
		self:RegisterEvent("ADDON_LOADED")
	end
end

-- Live re-tint when the class-colour toggle flips.
function ObjectiveTracker:OnSettingChanged(key)
	if key == "classColor" and self.trackers then
		for i = 1, #self.trackers do
			if self.trackers[i] then
				RecolorActiveBars(self.trackers[i])
			end
		end
	end
end

function ObjectiveTracker:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Objective Tracker Skin"], L["Hide the tracker header backgrounds and tidy the minimise button (reload to disable)."])
	builder:Checkbox(category, self, "classColor", L["Class-Coloured Bars"], L["Tint quest progress and timer bars with your class colour instead of the brand colour."])
end
