--[[
	NexEnhance - Faster Movie Skip
	-------------------------------------------------------------------------
	Lets you blow through movies and cinematics quickly: Space/Enter/Escape
	instantly confirm the "skip?" dialog instead of needing a second click.

	HookScript on the movie frames — non-secure, no taint.
--]]

-- luacheck: globals CinematicFrameCloseDialog CinematicFrameCloseDialogConfirmButton CinematicFrame MovieFrame
---@diagnostic disable: undefined-field
local _, ns = ...
local L = ns.L

local _G = _G

ns:RegisterDefaults({
	movieSkip = {
		enable = true,
	},
})

local MovieSkip = ns:NewModule("MovieSkip", "movieSkip", { group = "automation", title = L["Faster Movie Skip"], order = 40 })

local function db()
	return ns.db.movieSkip
end

-- Resolve the skip dialog + its confirm button for whichever frame fired the
-- key event. Done at keypress time (not login) because the cinematic dialog is
-- created lazily, so capturing references up front is unreliable.
local function GetSkipParts(self)
	if self == MovieFrame then
		local dialog = MovieFrame.CloseDialog
		return dialog, dialog and dialog.ConfirmButton
	end
	return _G.CinematicFrameCloseDialog, _G.CinematicFrameCloseDialogConfirmButton
end

local function skipOnKeyDown(self, key)
	if not db().enable then
		return
	end
	if key == "ESCAPE" then
		local dialog = GetSkipParts(self)
		if self:IsShown() and dialog then
			dialog:Hide()
		end
	end
end

local function skipOnKeyUp(self, key)
	if not db().enable then
		return
	end
	if key == "SPACE" or key == "ESCAPE" or key == "ENTER" then
		local _, confirmButton = GetSkipParts(self)
		if self:IsShown() and confirmButton then
			confirmButton:Click()
		end
	end
end

-- Install the key hooks at most once. The per-key handlers already gate on
-- db().enable, so hooking is harmless while the feature is off and the hook
-- never needs removing (HookScript can't be undone anyway).
local hooksInstalled = false
local function InstallHooks()
	if hooksInstalled then
		return
	end
	hooksInstalled = true

	-- Both are core frames present at login; hook unconditionally and resolve
	-- the dialog widgets on demand (see GetSkipParts).
	if MovieFrame then
		MovieFrame:HookScript("OnKeyDown", skipOnKeyDown)
		MovieFrame:HookScript("OnKeyUp", skipOnKeyUp)
	end

	if CinematicFrame then
		CinematicFrame:HookScript("OnKeyDown", skipOnKeyDown)
		CinematicFrame:HookScript("OnKeyUp", skipOnKeyUp)
	end
end

function MovieSkip:OnEnable()
	InstallHooks()
end

-- OnEnable only fires for modules enabled at login, so a module toggled on
-- later must install its hooks here (otherwise it would need a reload).
function MovieSkip:OnSettingChanged(key, value)
	if key == "enable" and value then
		InstallHooks()
	end
end

function MovieSkip:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Faster Movie Skip"], L["Press Space, Enter or Escape to instantly confirm the movie/cinematic skip dialog."])
end
