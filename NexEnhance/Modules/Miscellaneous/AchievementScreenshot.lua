--[[
	NexEnhance - Achievement Screenshot
	-------------------------------------------------------------------------
	Automatically takes a screenshot a moment after you earn an achievement
	(skipped for achievements already completed on the account, so account-wide
	unlocks on alts don't spam screenshots).

	The 1s delay lets the achievement toast finish animating in so it shows up
	in the shot. The capture frame is a self-stopping countdown (no polling
	when idle).
--]]

local _, ns = ...
local L = ns.L

local CreateFrame = CreateFrame
local Screenshot = Screenshot

ns:RegisterDefaults({
	achievementScreenshot = {
		enable = false,
	},
})

local AchievementScreenshot = ns:NewModule("AchievementScreenshot", "achievementScreenshot", { group = "automation", title = L["Achievement Screenshot"], order = 110 })

local captureFrame
local eventHandles = {}
local eventsRegistered = false

local function CountdownOnUpdate(self, elapsed)
	self.delay = self.delay - elapsed
	if self.delay < 0 then
		self:Hide()
		Screenshot()
	end
end

function AchievementScreenshot:ACHIEVEMENT_EARNED(_, alreadyEarnedOnAccount)
	if not ns.db.achievementScreenshot.enable then
		return
	end
	if alreadyEarnedOnAccount then
		return
	end

	if not captureFrame then
		captureFrame = CreateFrame("Frame")
		captureFrame:Hide()
		captureFrame:SetScript("OnUpdate", CountdownOnUpdate)
	end

	captureFrame.delay = 1
	captureFrame:Show()
end

function AchievementScreenshot:RegisterModuleEvents()
	if eventsRegistered then
		return
	end
	eventsRegistered = true
	self:TrackEvent(eventHandles, "ACHIEVEMENT_EARNED", "ACHIEVEMENT_EARNED")
end

function AchievementScreenshot:UnregisterModuleEvents()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
	if captureFrame then
		captureFrame:Hide()
	end
end

function AchievementScreenshot:OnEnable()
	if not ns.db.achievementScreenshot.enable then
		return
	end
	self:RegisterModuleEvents()
end

function AchievementScreenshot:OnDisable()
	self:UnregisterModuleEvents()
end

function AchievementScreenshot:OnSettingChanged(key)
	if key == "enable" then
		-- ApplyModuleSetting owns enable lifecycle.
		return
	end
end

function AchievementScreenshot:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Achievement Screenshot"], L["Automatically take a screenshot when you earn a new achievement."])
end
