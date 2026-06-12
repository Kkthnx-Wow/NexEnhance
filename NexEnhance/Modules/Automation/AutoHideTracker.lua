--[[
	NexEnhance - Auto Hide Tracker
	-------------------------------------------------------------------------
	Hides the Objective Tracker during boss encounters and arena matches so it
	stays out of the way when it matters, then restores it afterwards.

	Adapted from KkthnxUI by Josh "Kkthnx" Russell:
	  https://github.com/Kkthnx-Wow/KkthnxUI/blob/main/KkthnxUI/Modules/Automation/Elements/AutoHideTracker.lua

	How it works:
	  * A SecureHandlerStateTemplate frame is driven by a [@boss#/@arena#,exists]
	    state condition, so the *trigger* is fully secure and fires in combat.
	  * The (insecure) OnHide/OnShow scripts then reparent the tracker to our
	    shared hider frame to collapse it, or back to UIParent to restore it.
	    The tracker is NOT a protected frame, so it can't be reparented from
	    inside the secure snippet (in combat only protected frames are valid
	    frame handles - see WoWUIBugs #469). Hence the insecure reparent, which
	    we pcall and defer to PLAYER_REGEN_ENABLED if combat blocks it.
	  * That insecure reparent taints ObjectiveTrackerFrame. Blizzard's
	    SplashFrame:OnHide() calls ObjectiveTrackerFrame:Update(), which would
	    then run through tainted code and could spread taint to the tracker's
	    secure quest-item buttons. Once we have reparented at least once we
	    replace SplashFrame's OnHide with a faithful copy that omits that single
	    Update (mirrors Blizzard_FrameXML/SplashFrame.lua, SplashFrameMixin:OnHide).
	  * Mythic+ keystone runs keep the tracker visible by default (you usually
	    want your objectives there); flip "Hide in Mythic+" to override.
	  * We bow out entirely if a boss mod (BigWigs/DBM) or a third-party quest
	    tracker is loaded, since those manage the tracker themselves.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local L = ns.L

local _G = _G
local pcall = pcall
local CreateFrame = CreateFrame
local UIParent = UIParent
local InCombatLockdown = InCombatLockdown
local GetInstanceInfo = GetInstanceInfo
local RegisterStateDriver = RegisterStateDriver
local UnregisterStateDriver = UnregisterStateDriver
local ShowUIPanel = ShowUIPanel
local C_AddOns_IsAddOnLoaded = C_AddOns.IsAddOnLoaded
local C_TalkingHead = C_TalkingHead

-- GetInstanceInfo difficultyID for a Mythic+ keystone run.
local DIFFICULTY_KEYSTONE = 8

-- Resolve "hide" while any boss/arena unit exists, "show" otherwise. The bracket
-- groups are OR-ed, so any match collapses the tracker.
local STATE_CONDITION = "[@arena1,exists][@arena2,exists][@arena3,exists][@arena4,exists][@arena5,exists]" .. "[@boss1,exists][@boss2,exists][@boss3,exists][@boss4,exists][@boss5,exists] hide;show"

ns:RegisterDefaults({
	autoHideTracker = {
		enable = true,
		hideInKeystone = false,
	},
})

local AutoHideTracker = ns:NewModule("AutoHideTracker", "autoHideTracker", { group = "automation", title = L["Auto Hide Tracker"], order = 100 })

local autoHider
local pendingAction
local waitingForCombat
local driverPending
local splashGuarded

local function GetTracker()
	return _G["ObjectiveTrackerFrame"]
end

local function IsCollapsed(tracker)
	return tracker and tracker:GetParent() == ns.HiderFrame
end

-- Combat blocked the reparent earlier; apply it now that we're out of combat.
local function ApplyPending()
	if InCombatLockdown() then
		return
	end

	local tracker = GetTracker()
	if tracker and pendingAction then
		pcall(tracker.SetParent, tracker, pendingAction == "collapse" and ns.HiderFrame or UIParent)
	end

	pendingAction = nil
	waitingForCombat = nil
	ns:UnregisterEvent("PLAYER_REGEN_ENABLED", ApplyPending)
end

-- A faithful copy of Blizzard's SplashFrameMixin:OnHide that drops the single
-- ObjectiveTrackerFrame:Update() call. Installed only after we have tainted the
-- tracker by reparenting it, so before that point Blizzard's own handler runs.
-- Source: Blizzard_FrameXML/SplashFrame.lua.
local function SplashOnHide(self)
	local fromGameMenu = self.screenInfo and self.screenInfo.gameMenuRequest
	self.screenInfo = nil

	if C_TalkingHead then
		C_TalkingHead.SetConversationsDeferred(false)
	end

	local alertFrame = _G["AlertFrame"]
	if alertFrame then
		alertFrame:SetAlertsEnabled(true, "splashFrame")
	end

	-- ObjectiveTrackerFrame:Update() intentionally omitted (taint guard).

	-- We run insecurely, so only poke the protected GameMenu out of combat.
	if not self.showingQuestDialog and fromGameMenu and not InCombatLockdown() then
		ShowUIPanel(_G["GameMenuFrame"])
	end

	self.showingQuestDialog = nil
end

local function EnsureSplashGuard()
	if splashGuarded then
		return
	end
	local splash = _G["SplashFrame"]
	if not splash then
		return
	end

	splashGuarded = true
	splash:SetScript("OnHide", SplashOnHide)
end

-- Reparenting a frame with protected children can be blocked mid-combat; if so,
-- remember what we wanted and finish once combat ends. Any insecure reparent
-- taints the tracker, so this is also where we arm the splash taint guard.
local function SetParentSafe(tracker, parent, action)
	if not tracker then
		return
	end

	EnsureSplashGuard()

	if pcall(tracker.SetParent, tracker, parent) then
		return
	end

	pendingAction = action
	if not waitingForCombat then
		waitingForCombat = true
		ns:RegisterEvent("PLAYER_REGEN_ENABLED", ApplyPending)
	end
end

local function Collapse()
	local tracker = GetTracker()
	if not tracker or IsCollapsed(tracker) then
		return
	end

	-- Keep objectives visible during Mythic+ keystones unless asked otherwise.
	if not ns.db.autoHideTracker.hideInKeystone then
		local _, _, difficultyID = GetInstanceInfo()
		if difficultyID == DIFFICULTY_KEYSTONE then
			return
		end
	end

	SetParentSafe(tracker, ns.HiderFrame, "collapse")
end

local function Expand()
	local tracker = GetTracker()
	if tracker and IsCollapsed(tracker) then
		SetParentSafe(tracker, UIParent, "expand")
	end
end

-- Re-run UpdateDriver once combat ends (a setting was toggled mid-fight).
local function ReapplyDriverAfterCombat()
	if InCombatLockdown() then
		return
	end
	driverPending = nil
	ns:UnregisterEvent("PLAYER_REGEN_ENABLED", ReapplyDriverAfterCombat)
	AutoHideTracker:UpdateDriver()
end

function AutoHideTracker:UpdateDriver()
	if not autoHider then
		return
	end

	-- (Un)registering a state driver touches the secure environment, so keep it
	-- out of combat. You can no longer /reload in combat, so Setup always runs
	-- clean - this guard only covers a setting toggled during a fight.
	if InCombatLockdown() then
		if not driverPending then
			driverPending = true
			ns:RegisterEvent("PLAYER_REGEN_ENABLED", ReapplyDriverAfterCombat)
		end
		return
	end

	if ns.db.autoHideTracker.enable then
		-- Re-registering re-evaluates immediately, so a setting change applies now.
		RegisterStateDriver(autoHider, "trackervis", STATE_CONDITION)
	else
		UnregisterStateDriver(autoHider, "trackervis")
		Expand()
	end
end

function AutoHideTracker:Setup()
	if self.setup or not GetTracker() then
		return
	end

	-- Boss mods drive the tracker during encounters; don't fight them.
	if C_AddOns_IsAddOnLoaded("BigWigs") or C_AddOns_IsAddOnLoaded("DBM-Core") then
		return
	end
	-- Third-party quest trackers replace the default one entirely.
	if C_AddOns_IsAddOnLoaded("KalielsTracker") or C_AddOns_IsAddOnLoaded("DugisGuideViewerZ") then
		return
	end

	self.setup = true

	autoHider = CreateFrame("Frame", "NexEnhanceTrackerAutoHider", UIParent, "SecureHandlerStateTemplate")
	-- Secure trigger (fires in combat); the heavy lifting is in OnHide/OnShow.
	autoHider:SetAttribute(
		"_onstate-trackervis",
		[[
		if newstate == "hide" then
			self:Hide()
		else
			self:Show()
		end
	]]
	)
	autoHider:SetScript("OnHide", Collapse)
	autoHider:SetScript("OnShow", Expand)

	self:UpdateDriver()
end

function AutoHideTracker:ADDON_LOADED(addon)
	if addon == "Blizzard_ObjectiveTracker" then
		self:Setup()
	end
end

function AutoHideTracker:OnEnable()
	if C_AddOns_IsAddOnLoaded("Blizzard_ObjectiveTracker") then
		self:Setup()
	else
		self:RegisterEvent("ADDON_LOADED")
	end
end

function AutoHideTracker:OnSettingChanged()
	self:UpdateDriver()
end

function AutoHideTracker:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Auto Hide Tracker"], L["Hide the Objective Tracker during boss encounters and arena matches."])
	local _, keystoneInit = builder:Checkbox(category, self, "hideInKeystone", L["Hide in Mythic+"], L["Also hide the tracker during Mythic+ keystone runs (otherwise your objectives stay visible)."])

	builder:DependsOn(keystoneInit, enableInit)
end
