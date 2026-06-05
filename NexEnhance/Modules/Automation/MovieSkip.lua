--[[
	NexEnhance - Faster Movie Skip
	-------------------------------------------------------------------------
	Lets you blow through movies and cinematics quickly: Space/Enter/Escape
	instantly confirm the "skip?" dialog instead of needing a second click.

	Ported from NDui's Misc FasterMovieSkip (by siweia), adapted to the
	NexEnhance framework. Uses HookScript on the (non-secure) movie frames.
--]]

-- luacheck: globals CinematicFrameCloseDialogConfirmButton CinematicFrame MovieFrame
local _, ns = ...
local L = ns.L

local MovieFrame = MovieFrame
local CinematicFrame = CinematicFrame

ns:RegisterDefaults({
	movieSkip = {
		enable = true,
	},
})

local MovieSkip = ns:NewModule("MovieSkip", "movieSkip", { group = "automation", title = L["Faster Movie Skip"], order = 40 })

local function db()
	return ns.db.movieSkip
end

local function skipOnKeyDown(self, key)
	if not db().enable then return end
	if key == "ESCAPE" then
		if self:IsShown() and self.closeDialog and self.closeDialog.confirmButton then
			self.closeDialog:Hide()
		end
	end
end

local function skipOnKeyUp(self, key)
	if not db().enable then return end
	if key == "SPACE" or key == "ESCAPE" or key == "ENTER" then
		if self:IsShown() and self.closeDialog and self.closeDialog.confirmButton then
			self.closeDialog.confirmButton:Click()
		end
	end
end

function MovieSkip:OnEnable()
	if not db().enable then return end

	if MovieFrame and MovieFrame.CloseDialog then
		MovieFrame.closeDialog = MovieFrame.CloseDialog
		MovieFrame.closeDialog.confirmButton = MovieFrame.CloseDialog.ConfirmButton
		MovieFrame:HookScript("OnKeyDown", skipOnKeyDown)
		MovieFrame:HookScript("OnKeyUp", skipOnKeyUp)
	end

	if CinematicFrame and CinematicFrame.closeDialog then
		CinematicFrame.closeDialog.confirmButton = CinematicFrameCloseDialogConfirmButton
		CinematicFrame:HookScript("OnKeyDown", skipOnKeyDown)
		CinematicFrame:HookScript("OnKeyUp", skipOnKeyUp)
	end
end

function MovieSkip:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Faster Movie Skip"], L["Press Space, Enter or Escape to instantly confirm the movie/cinematic skip dialog."])
end
