--[[
	NexEnhance - Quick Join
	-------------------------------------------------------------------------
	Quality-of-life pass over Blizzard's Group Finder (Premade Groups):
	  - double-click a search result to sign up (Alt skips the confirm dialog)
	  - an "Auto-accept" check on the applicant viewer that auto-invites
	    applicants while you're the leader
	  - auto-dismisses the throwaway "informational"/expired LFG popups
	  - shows the leader's M+/PvP rating on each result, with a cross-faction
	    crest, and trims the long "Zone:" activity prefix
	  - a one-time HelpTip pointing out the double-click shortcut (F.ShowHelpTip)

	Adapted from NDui's Modules/Misc/QuickJoin.lua (by siweia):
	  https://github.com/siweia/NDui

	The Group Finder UI lives in Blizzard_GroupFinder, which is load-on-demand -
	so unlike NDui we don't touch LFGListFrame at file scope. We wait for the
	addon to load, then install our hooks once. Every hook re-checks the live
	toggles, because hooksecurefunc is a one-way street: you can hook it, but you
	can never un-hook it, so disabling the module just makes the hooks nap.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local select = select
local gsub = string.gsub
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc
local GetTime = GetTime
local IsAltKeyDown = IsAltKeyDown
local UnitIsGroupLeader = UnitIsGroupLeader
local StaticPopup_Hide = StaticPopup_Hide
local StaticPopupSpecial_Hide = StaticPopupSpecial_Hide
local HideUIPanel = HideUIPanel

local C_Timer_After = C_Timer.After
local C_LFGList_GetSearchResultInfo = C_LFGList and C_LFGList.GetSearchResultInfo
local C_LFGList_GetActivityInfoTable = C_LFGList and C_LFGList.GetActivityInfoTable
local C_LFGList_InviteApplicant = C_LFGList and C_LFGList.InviteApplicant
local C_ChallengeMode_GetDungeonScoreRarityColor = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor
local IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded

local HEADER_COLON = _G["HEADER_COLON"] or ":"
local LE_PARTY_CATEGORY_HOME = _G["LE_PARTY_CATEGORY_HOME"] or 1
local LFG_LIST_AUTO_ACCEPT = _G["LFG_LIST_AUTO_ACCEPT"] or "Auto-accept"
local HIGHLIGHT_FONT_COLOR = HIGHLIGHT_FONT_COLOR

-- Grey "(%s)" wrapper so the rating reads "(1234) Group Name" with the brackets
-- muted and the score itself rarity-coloured.
local GRAY = ("|cff%02x%02x%02x"):format(C.Colors.gray[1] * 255, C.Colors.gray[2] * 255, C.Colors.gray[3] * 255)
local SCORE_FORMAT = GRAY .. "(%s) |r%s"

-- Full texture paths so the per-row search-result update never concatenates.
local FACTION_LOGO = { [0] = "Interface\\Timer\\Horde-Logo", [1] = "Interface\\Timer\\Alliance-Logo" }

ns:RegisterDefaults({
	quickJoin = {
		enable = false,
		autoAccept = false, -- persisted state of the on-frame "Auto-accept" check
		leaderScore = true,
		autoHide = true,
	},
})

local QuickJoin = ns:NewModule("QuickJoin", "quickJoin", { group = "automation", title = L["Quick Join"], order = 35, since = "1.2.9" })

local eventHandles = {}
local eventsRegistered = false

-- ---------------------------------------------------------------------------
-- Score helper (mirrors the Tooltip module's GetDungeonScore colouring)
-- ---------------------------------------------------------------------------
local function ColorScore(score)
	local color = (C_ChallengeMode_GetDungeonScoreRarityColor and C_ChallengeMode_GetDungeonScoreRarityColor(score)) or HIGHLIGHT_FONT_COLOR
	return color:WrapTextInColorCode(score)
end

-- ---------------------------------------------------------------------------
-- Quick sign-up: double-click a result to apply
-- ---------------------------------------------------------------------------
local function ApplyToSelected()
	if not ns.db.quickJoin.enable then
		return
	end

	local searchPanel = LFGListFrame and LFGListFrame.SearchPanel
	if searchPanel and searchPanel.SignUpButton:IsEnabled() then
		searchPanel.SignUpButton:Click()
	end

	-- Hold Alt to review the sign-up note yourself; otherwise just send it.
	local dialog = _G["LFGListApplicationDialog"]
	if not IsAltKeyDown() and dialog and dialog:IsShown() and dialog.SignUpButton:IsEnabled() then
		dialog.SignUpButton:Click()
	end
end

-- ---------------------------------------------------------------------------
-- Auto-dismiss the throwaway LFG popups (declined notices, expired listings).
-- Blizzard fires these with no user value mid-search, so we shoo them after a
-- beat. One pending slot is plenty - they don't stack in practice.
-- ---------------------------------------------------------------------------
local pendingPopup
local function HidePendingPopup()
	local popup = pendingPopup
	pendingPopup = nil
	if not popup then
		return
	end

	-- StaticPopup_Show passes a `which` string; LFGListInviteDialog_Show passes
	-- the dialog frame. Handle whichever showed up.
	if type(popup) == "table" then
		if popup.informational then
			StaticPopupSpecial_Hide(popup)
		end
	elseif popup == "LFG_LIST_ENTRY_EXPIRED_TOO_MANY_PLAYERS" then
		StaticPopup_Hide(popup)
	end
end

local function QueuePopupHide(popup)
	if not (ns.db.quickJoin.enable and ns.db.quickJoin.autoHide) then
		return
	end
	pendingPopup = popup
	C_Timer_After(1, HidePendingPopup)
end

-- ---------------------------------------------------------------------------
-- Leader rating + cross-faction crest on each search result
-- ---------------------------------------------------------------------------
local function ShowLeaderScore(self)
	if not ns.db.quickJoin.enable or not ns.db.quickJoin.leaderScore then
		return
	end

	local resultID = self.resultID
	local info = resultID and C_LFGList_GetSearchResultInfo and C_LFGList_GetSearchResultInfo(resultID)
	-- activityIDs can be a 12.0 secret value; bail rather than index it.
	if not info or not F.NotSecret(info.activityIDs) then
		return
	end

	local activityInfo = C_LFGList_GetActivityInfoTable and C_LFGList_GetActivityInfoTable(info.activityIDs[1], nil, info.isWarMode)
	if activityInfo then
		local score = (activityInfo.isMythicPlusActivity and info.leaderOverallDungeonScore) or (activityInfo.isRatedPvpActivity and info.leaderPvpRatingInfo and info.leaderPvpRatingInfo.rating)
		if score then
			local oldName = self.ActivityName:GetText()
			if F.NotSecret(oldName) then
				oldName = gsub(oldName, ".-" .. HEADER_COLON, "") -- trim "Tazavesh:" etc.
				self.ActivityName:SetFormattedText(SCORE_FORMAT, ColorScore(score), oldName)
			end
			if not self.nexCrossFactionLogo then
				local logo = self:CreateTexture(nil, "OVERLAY")
				logo:SetPoint("TOPLEFT", -6, 5)
				logo:SetSize(24, 24)
				self.nexCrossFactionLogo = logo
			end
		end
	end

	if self.nexCrossFactionLogo then
		if info.crossFactionListing or not FACTION_LOGO[info.leaderFactionGroup] then
			self.nexCrossFactionLogo:Hide()
		else
			self.nexCrossFactionLogo:SetTexture(FACTION_LOGO[info.leaderFactionGroup])
			self.nexCrossFactionLogo:Show()
		end
	end
end

-- ---------------------------------------------------------------------------
-- Auto-accept applicants (leader only), driven by the on-frame check box
-- ---------------------------------------------------------------------------
local lastInviteAt = 0
local function InviteApplicant(button)
	if button.applicantID and button.InviteButton and button.InviteButton:IsEnabled() then
		C_LFGList_InviteApplicant(button.applicantID)
	end
end

function QuickJoin:LFG_LIST_APPLICANT_LIST_UPDATED()
	if not (ns.db.quickJoin.enable and self.autoAcceptCheck and self.autoAcceptCheck:GetChecked()) then
		return
	end
	if not UnitIsGroupLeader("player", LE_PARTY_CATEGORY_HOME) then
		return
	end

	local viewer = LFGListFrame and LFGListFrame.ApplicationViewer
	if not viewer then
		return
	end
	viewer.ScrollBox:ForEachFrame(InviteApplicant)

	-- Nudge the viewer to refresh, but no more than once a second so a noisy
	-- applicant list can't turn into a click storm.
	if viewer:IsShown() then
		local now = GetTime()
		if now - lastInviteAt > 1 then
			lastInviteAt = now
			viewer.RefreshButton:Click()
		end
	end
end

function QuickJoin:CreateAutoAcceptCheck()
	if self.autoAcceptCheck then
		return
	end

	local viewer = LFGListFrame and LFGListFrame.ApplicationViewer
	if not viewer then
		return
	end

	local check = CreateFrame("CheckButton", nil, viewer, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	check:SetHitRectInsets(0, -130, 0, 0)
	check:SetPoint("BOTTOMLEFT", viewer.InfoBackground or viewer, 12, 5)
	check:SetChecked(ns.db.quickJoin.autoAccept)
	if check.text then
		check.text:SetText(LFG_LIST_AUTO_ACCEPT)
	end
	check:SetScript("OnClick", function(self)
		ns.db.quickJoin.autoAccept = self:GetChecked() or false
	end)

	-- Only the group leader can invite, so only show the check for them - and
	-- never on top of Blizzard's own auto-accept toggle when it's present.
	hooksecurefunc("LFGListApplicationViewer_UpdateInfo", function(frame)
		check:SetShown(ns.db.quickJoin.enable and UnitIsGroupLeader("player", LE_PARTY_CATEGORY_HOME) and not frame.AutoAcceptButton:IsShown())
	end)

	self.autoAcceptCheck = check
end

-- ---------------------------------------------------------------------------
-- Setup (runs once, after Blizzard_GroupFinder is loaded)
-- ---------------------------------------------------------------------------
function QuickJoin:Setup()
	if self.setupDone then
		return
	end
	if not (LFGListFrame and LFGListFrame.SearchPanel) then
		return
	end
	self.setupDone = true

	-- One-shot nudge about the double-click shortcut, the first time the sign-up
	-- button shows. F.ShowHelpTip handles the "once per account" bookkeeping.
	LFGListFrame.SearchPanel.SignUpButton:HookScript("OnShow", function()
		if ns.db.quickJoin.enable then
			F.ShowHelpTip(PVEFrame, "QuickJoinApply", L["QuickJoinHelpTip"])
		end
	end)

	-- Double-click search results to apply.
	hooksecurefunc(LFGListFrame.SearchPanel.ScrollBox, "Update", function(scrollBox)
		local target = scrollBox.ScrollTarget
		for i = 1, target:GetNumChildren() do
			local child = select(i, target:GetChildren())
			-- .Name is the search-entry template's title fontstring; it marks a
			-- real result row (dividers/other children don't have it).
			if child.Name and not child.nexHooked then
				child:HookScript("OnDoubleClick", ApplyToSelected)
				child.nexHooked = true
			end
		end
	end)

	-- Auto-hide informational/expired popups.
	hooksecurefunc("StaticPopup_Show", QueuePopupHide)
	hooksecurefunc("LFGListInviteDialog_Show", QueuePopupHide)

	-- Close the Group Finder once you accept an invite to a listed group.
	hooksecurefunc("LFGListInviteDialog_Accept", function()
		if ns.db.quickJoin.enable and PVEFrame and PVEFrame:IsShown() then
			HideUIPanel(PVEFrame)
		end
	end)

	-- Leader rating on results.
	hooksecurefunc("LFGListSearchEntry_Update", ShowLeaderScore)

	-- Auto-accept applicants.
	self:CreateAutoAcceptCheck()
	self:RegisterModuleEvents()
end

function QuickJoin:RegisterModuleEvents()
	if eventsRegistered or not self.setupDone then
		return
	end
	eventsRegistered = true
	self:TrackEvent(eventHandles, "LFG_LIST_APPLICANT_LIST_UPDATED", "LFG_LIST_APPLICANT_LIST_UPDATED")
end

function QuickJoin:UnregisterModuleEvents()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
end

function QuickJoin:StopWaiting()
	if self.addonLoadHandle then
		ns:UnregisterEvent("ADDON_LOADED", self.addonLoadHandle)
		self.addonLoadHandle = nil
	end
	self.waiting = nil
end

function QuickJoin:Stop()
	self:UnregisterModuleEvents()
	self:StopWaiting()
end

-- Blizzard_GroupFinder is load-on-demand, so set up now if it's already here,
-- otherwise wait for it. The handle lets us unhook the one-shot listener once it
-- fires (no point waking on every other addon's ADDON_LOADED for the session).
function QuickJoin:TrySetup()
	if self.setupDone or self.waiting then
		return
	end

	if IsAddOnLoaded and IsAddOnLoaded("Blizzard_GroupFinder") then
		self:Setup()
		return
	end

	self.waiting = true
	self.addonLoadHandle = ns:RegisterEvent("ADDON_LOADED", function(_, addon)
		if addon == "Blizzard_GroupFinder" then
			QuickJoin:StopWaiting()
			QuickJoin:Setup()
		end
	end)
end

function QuickJoin:OnDisable()
	self:Stop()
end

function QuickJoin:OnSettingChanged(key, value)
	if key == "enable" then
		if value then
			self:TrySetup()
		else
			self:Stop()
		end
	end
end

function QuickJoin:OnEnable()
	self:TrySetup()
end

function QuickJoin:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Quick Join"], L["Double-click Group Finder results to apply, auto-invite applicants, hide throwaway LFG popups and show leader rating."])
	local _, scoreInit = builder:Checkbox(category, self, "leaderScore", L["Show Leader Rating"], L["Show the group leader's Mythic+/PvP rating on each search result, with a cross-faction crest."])
	local _, hideInit = builder:Checkbox(category, self, "autoHide", L["Auto-hide LFG Popups"], L["Automatically dismiss the throwaway informational and expired-listing LFG popups."])

	builder:DependsOn(scoreInit, enableInit)
	builder:DependsOn(hideInit, enableInit)
end
