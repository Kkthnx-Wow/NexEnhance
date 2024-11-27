local _, Module = ...

-- Cache frequently used global variables and functions
local TIMER_MINUTES_DISPLAY = TIMER_MINUTES_DISPLAY
local GetDistance, WasClampedToScreen = C_Navigation.GetDistance, C_Navigation.WasClampedToScreen
local math_abs, math_floor = math.abs, math.floor

-- Variables to track distance and update time
local lastDistance, lastUpdate = nil, 0

-- Localization (if TIMER_MINUTES_DISPLAY is localized, use Dashi's localization)
local L = Module.L
local TIMER_MINUTES_FORMAT = TIMER_MINUTES_DISPLAY or "%d:%02d"

-- Updates the arrival time display
local function updateArrival(self, elapsed)
	if self.isClamped then
		self.TimeText:Hide()
		lastDistance = nil
		return
	end

	lastUpdate = lastUpdate + elapsed

	local distance = GetDistance()
	if distance ~= lastDistance and lastUpdate >= 0.3 then
		local speed = (((lastDistance or 0) - distance) / lastUpdate) or 0
		lastDistance = distance

		if speed > 0 then
			local time = math_abs(distance / speed)
			self.TimeText:SetText(TIMER_MINUTES_FORMAT:format(math_floor(time / 60), math_floor(time % 60)))
			self.TimeText:Show()
		else
			self.TimeText:Hide()
		end

		lastUpdate = 0
	end
end

-- Updates the alpha of the frame
local function updateAlpha(self)
	if not WasClampedToScreen() and GetDistance() > 0 then
		self:SetAlpha(0.9)
	end
end

-- Initializes the quest navigation enhancements
local function initializeQuestNavigation()
	local timeText = SuperTrackedFrame:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
	timeText:SetPoint("TOP", SuperTrackedFrame.DistanceText, "BOTTOM", 0, -2)
	timeText:SetHeight(20)
	timeText:SetJustifyV("TOP")

	SuperTrackedFrame.TimeText = timeText
	SuperTrackedFrame:HookScript("OnUpdate", updateArrival)

	hooksecurefunc(SuperTrackedFrame, "UpdateAlpha", updateAlpha)
end

-- Hook into the Blizzard_QuestNavigation addon using Dashi's HookAddOn
Module:HookAddOn("Blizzard_QuestNavigation", function()
	Module:Defer(initializeQuestNavigation)
end)
