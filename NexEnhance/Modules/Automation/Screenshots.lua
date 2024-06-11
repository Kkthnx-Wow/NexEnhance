local _, Module = ...

function Module:TakeScreenshotOnEvent()
	Module.screenshotFrame.delay = 1
	Module.screenshotFrame:Show()
end

function Module:InitializeScreenshotFrame()
	if not Module.screenshotFrame then
		Module.screenshotFrame = CreateFrame("Frame")
		Module.screenshotFrame:Hide()
		Module.screenshotFrame:SetScript("OnUpdate", function(self, elapsed)
			self.delay = self.delay - elapsed
			if self.delay < 0 then
				Screenshot()
				self:Hide()
			end
		end)
	end
end

function Module:ToggleAutoScreenshotAchieve()
	self:InitializeScreenshotFrame()

	if Module.db.profile.automation.AutoScreenshotAchieve then
		self:RegisterEvent("ACHIEVEMENT_EARNED", self.TakeScreenshotOnEvent)
	elseif self:IsEventRegistered("ACHIEVEMENT_EARNED", self.TakeScreenshotOnEvent) then
		Module.screenshotFrame:Hide()
		self:UnregisterEvent("ACHIEVEMENT_EARNED", self.TakeScreenshotOnEvent)
	end
end
