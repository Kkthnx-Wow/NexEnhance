--[[
	NexEnhance - Achievement Back Button
	-------------------------------------------------------------------------
	Adds a browser-style "Back" button to the Achievement frame. As you click
	through categories and achievements it records where you've been, and the
	button walks that history back one step at a time -- category, selected
	achievement, and both scroll positions all restored.

	Retail only. The windowed achievement frame expands to the stored category
	for us (AchievementFrame_UpdateAndSelectCategory), so unlike the original
	Classic-era addon we don't have to snapshot category collapse state.

	Adapted from LudiusMaximus' "Achievements Back Button" (MIT), reworked onto
	the NexEnhance framework: load-on-demand handling via the module event API,
	pure hooksecurefunc/HookScript so nothing taints, and no stray globals.
	  https://www.curseforge.com/wow/addons/achievements-back-button
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local L = ns.L

local _G = _G
local hooksecurefunc = hooksecurefunc
local CreateFrame = CreateFrame
local GetTime = GetTime
local tinsert, tremove = table.insert, table.remove
local C_AddOns = C_AddOns

ns:RegisterDefaults({
	achievementBackButton = {
		enable = true,
	},
})

local Module = ns:NewModule("AchievementBackButton", "achievementBackButton", { group = "misc", title = L["Achievement Back Button"], order = 45, since = "1.3.0" })

-- Navigation history. Each entry is a view we *left behind*, so Back pops the
-- most recent one off the top.
local history = {}

-- "We're restoring, don't record" latch: GoBack calls the very Blizzard functions
-- our hooks listen on, which would otherwise push the spot we just came from.
local goingBack = false

-- The view we're currently sitting on (gets pushed onto history when we move).
local curCategory, curAchievement
local curCategoryScroll, curAchievementScroll

-- Change timestamps, so a scroll that settles on the *same frame* as a nav change
-- is recognised as belonging to that change (and overrides the stored offset).
local categoryChangeTime, achievementChangeTime = 0, 0

local backButton

-- ---------------------------------------------------------------------------
-- Scroll helpers (ScrollBox/ScrollBar both mix in ScrollControllerMixin, so
-- Get/SetScrollPercentage is the canonical, version-stable accessor)
-- ---------------------------------------------------------------------------
local function GetScroll(container)
	local frame = _G[container]
	local box = frame and frame.ScrollBox
	return box and box.GetScrollPercentage and box:GetScrollPercentage()
end

local function SetScroll(container, percentage)
	if percentage == nil then
		return
	end
	local frame = _G[container]
	local box = frame and frame.ScrollBox
	if box and box.SetScrollPercentage then
		box:SetScrollPercentage(percentage)
	end
end

-- ---------------------------------------------------------------------------
-- History
-- ---------------------------------------------------------------------------
local function RememberLastState()
	-- Don't record while disabled, mid-restore, or before we've seen a category.
	if not Module.enabled or goingBack or not curCategory then
		return
	end
	-- The click + select hooks can both fire on one frame; only store once.
	local top = history[#history]
	if top and top.time == GetTime() then
		return
	end

	tinsert(history, {
		time = GetTime(),
		categoryID = curCategory,
		achievementID = curAchievement,
		categoryScroll = curCategoryScroll,
		achievementScroll = curAchievementScroll,
	})

	if backButton then
		backButton:Enable()
	end
end

local function GoBack()
	if not Module.enabled then
		return
	end

	local entry = tremove(history)
	if not entry then
		return
	end

	goingBack = true

	-- Updates both the category pane and the achievement list.
	_G.AchievementFrame_UpdateAndSelectCategory(entry.categoryID)
	if entry.achievementID then
		_G.AchievementFrame_SelectAchievement(entry.achievementID)
	end

	SetScroll("AchievementFrameCategories", entry.categoryScroll)
	SetScroll("AchievementFrameAchievements", entry.achievementScroll)

	-- We now sit on the restored view; sync the trackers so the *next* move
	-- records this spot rather than the one before it.
	curCategory = entry.categoryID
	curAchievement = entry.achievementID
	curCategoryScroll = entry.categoryScroll
	curAchievementScroll = entry.achievementScroll

	if #history == 0 and backButton then
		backButton:Disable()
	end

	goingBack = false
end

-- ---------------------------------------------------------------------------
-- Button
-- ---------------------------------------------------------------------------
local function OnEnter(self)
	_G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
	_G.GameTooltip:SetText(_G.BACK) -- Blizzard's localized "Back".
end

local function OnLeave()
	_G.GameTooltip:Hide()
end

local function CreateButton()
	local header = _G.AchievementFrame and _G.AchievementFrame.Header
	if not header or backButton then
		return
	end

	local button = CreateFrame("Button", nil, header)
	button:SetSize(29, 29)
	button:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
	button:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
	button:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")
	button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

	-- Tuck it just right of the achievement-points plaque on the header.
	button:SetPoint("LEFT", header.PointBorder or header, "RIGHT", 10, 1)

	button:SetScript("OnClick", GoBack)
	button:SetScript("OnEnter", OnEnter)
	button:SetScript("OnLeave", OnLeave)
	button:Disable()

	backButton = button
end

-- ---------------------------------------------------------------------------
-- Hook setup (runs once, after Blizzard_AchievementUI exists)
-- ---------------------------------------------------------------------------
function Module:SetupHooks()
	if self.hooked then
		return
	end
	-- Retail surface check: if these aren't here we're on an unsupported client.
	if not (_G.AchievementFrame and _G.AchievementFrame_UpdateAndSelectCategory and _G.AchievementTemplateMixin) then
		return
	end
	self.hooked = true

	-- Switching category (left pane).
	hooksecurefunc("AchievementFrameCategories_OnCategoryChanged", function(categoryID)
		if curCategory ~= categoryID then
			RememberLastState()
			categoryChangeTime = GetTime()
			curCategory = categoryID
			curCategoryScroll = GetScroll("AchievementFrameCategories")
			curAchievement = nil
		end
	end)

	-- Jumping to an achievement (links, search, "show in list", etc.).
	hooksecurefunc("AchievementFrame_SelectAchievement", function(achievementID)
		if achievementID and achievementID ~= curAchievement then
			RememberLastState()
			achievementChangeTime = GetTime()
			curAchievement = achievementID
			curAchievementScroll = GetScroll("AchievementFrameAchievements")
			curCategoryScroll = GetScroll("AchievementFrameCategories")
		end
	end)

	-- Clicking an achievement row.
	hooksecurefunc(_G.AchievementTemplateMixin, "ProcessClick", function()
		local achievementID = _G.AchievementFrameAchievements_GetSelectedAchievementId()
		-- Deselecting returns 0, which we ignore.
		if achievementID and achievementID ~= 0 and achievementID ~= curAchievement then
			-- Skip recording when we're just selecting the first achievement of the
			-- category we already landed on (nothing meaningful to go back to yet).
			if curCategory ~= _G.GetAchievementCategory(achievementID) or curAchievement then
				RememberLastState()
			end
			achievementChangeTime = GetTime()
			curAchievement = achievementID
			curAchievementScroll = GetScroll("AchievementFrameAchievements")
			curCategoryScroll = GetScroll("AchievementFrameCategories")
		end
	end)

	-- Capture the scroll offset that settles on the same frame as a nav change,
	-- so Back returns to exactly where you were looking.
	local catBar = _G.AchievementFrameCategories and _G.AchievementFrameCategories.ScrollBar
	if catBar and catBar.RegisterCallback then
		catBar:RegisterCallback(catBar.Event.OnScroll, function(_, percentage)
			if (categoryChangeTime == GetTime() or achievementChangeTime == GetTime()) and curCategoryScroll ~= percentage then
				curCategoryScroll = percentage
			end
		end, self)
	end

	local achBar = _G.AchievementFrameAchievements and _G.AchievementFrameAchievements.ScrollBar
	if achBar and achBar.RegisterCallback then
		achBar:RegisterCallback(achBar.Event.OnScroll, function(_, percentage)
			if achievementChangeTime == GetTime() and curAchievementScroll ~= percentage then
				curAchievementScroll = percentage
			end
		end, self)
	end

	CreateButton()
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
-- Blizzard_AchievementUI is load-on-demand, so we wait for it. We use the
-- engine-level ns:RegisterEvent with a stable function reference (the module
-- event API has no UnregisterEvent), which the dispatcher handles mid-fire.
local function OnAddonLoaded(_, addon)
	if addon == "Blizzard_AchievementUI" then
		Module.waiting = nil
		Module:SetupHooks()
		ns:UnregisterEvent("ADDON_LOADED", OnAddonLoaded)
	end
end

function Module:Update()
	self.enabled = ns.db.achievementBackButton.enable

	if self.enabled then
		if _G.AchievementFrame or C_AddOns.IsAddOnLoaded("Blizzard_AchievementUI") then
			self:SetupHooks()
		elseif not self.waiting then
			self.waiting = true
			ns:RegisterEvent("ADDON_LOADED", OnAddonLoaded)
		end
		if backButton then
			backButton:Show()
		end
	elseif backButton then
		-- Hooks can't be removed, but hiding the button (and the enabled gate in
		-- RememberLastState/GoBack) makes the feature effectively dormant.
		backButton:Hide()
	end
end

function Module:OnEnable()
	self:Update()
end

function Module:OnSettingChanged()
	self:Update()
end

function Module:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Achievement Back Button"], L["Add a back button to the Achievements frame that retraces your category and achievement history."])
end
