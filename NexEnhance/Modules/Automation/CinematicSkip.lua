local _, Module = ...

local function HandleKeyDown(self, key)
	if not Module.db.profile.automation.SkipCinematics then
		return
	end

	if key == "ESCAPE" then
		if self:IsShown() and self.closeDialog and self.closeDialog.confirmButton then
			self.closeDialog:Hide()
		end
	end
end

local function HandleKeyUp(self, key)
	if not Module.db.profile.automation.SkipCinematics then
		return
	end

	if key == "SPACE" or key == "ESCAPE" or key == "ENTER" then
		if self:IsShown() and self.closeDialog and self.closeDialog.confirmButton then
			self.closeDialog.confirmButton:Click()
		end
	end
end

function Module:PLAYER_LOGIN()
	MovieFrame.closeDialog = MovieFrame.CloseDialog
	MovieFrame.closeDialog.confirmButton = MovieFrame.CloseDialog.ConfirmButton
	CinematicFrame.closeDialog.confirmButton = CinematicFrameCloseDialogConfirmButton

	MovieFrame:HookScript("OnKeyDown", HandleKeyDown)
	MovieFrame:HookScript("OnKeyUp", HandleKeyUp)
	CinematicFrame:HookScript("OnKeyDown", HandleKeyDown)
	CinematicFrame:HookScript("OnKeyUp", HandleKeyUp)
end
