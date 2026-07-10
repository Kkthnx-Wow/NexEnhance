--[[
	NexEnhance - Quick Join
	-------------------------------------------------------------------------
	Quality-of-life pass over Blizzard's Group Finder (Premade Groups):
	  - double-click a search result to sign up (Alt skips the confirm dialog)
	  - auto-dismisses the throwaway "informational"/expired LFG popups
	  - shows the leader's M+/PvP rating on each result, with a cross-faction
	    crest, and trims the long "Zone:" activity prefix
	  - optional locale region tag (MX, OCE, DE, etc.) when the leader's realm
	    locale differs from yours (Blizzard realm-list metadata)
	  - a one-time HelpTip pointing out the double-click shortcut (F.ShowHelpTip)

	Auto-invite applicants is intentionally NOT implemented: C_LFGList.InviteApplicant
	is protected. Addon-initiated button:Click() still runs tainted and triggers
	ADDON_ACTION_BLOCKED. Use Blizzard's listing Auto-accept when
	C_LFGList.CanActiveEntryUseAutoAccept() shows it.

	Blizzard_GroupFinder is load-on-demand — we don't touch LFGListFrame at file
	scope. Hooks install once the addon loads, and each hook re-checks the live
	toggles (hooksecurefunc can't be removed, so disabling just makes them no-op).
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local select = select
local format = string.format
local gsub = string.gsub
local hooksecurefunc = hooksecurefunc
local IsAltKeyDown = IsAltKeyDown
local StaticPopup_Hide = StaticPopup_Hide
local StaticPopupSpecial_Hide = StaticPopupSpecial_Hide
local HideUIPanel = HideUIPanel

local C_Timer_After = C_Timer.After
local C_LFGList_GetSearchResultInfo = C_LFGList and C_LFGList.GetSearchResultInfo
local C_LFGList_GetActivityInfoTable = C_LFGList and C_LFGList.GetActivityInfoTable
local C_LFGList_GetActivityFullName = C_LFGList and C_LFGList.GetActivityFullName
local C_ChallengeMode_GetDungeonScoreRarityColor = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor
local IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
local CreateAtlasMarkup = _G.CreateAtlasMarkup

local HEADER_COLON = _G["HEADER_COLON"] or ":"
local HIGHLIGHT_FONT_COLOR = HIGHLIGHT_FONT_COLOR

-- Grey "(%s)" wrapper so the rating reads "(1234) Group Name" with the brackets
-- muted and the score itself rarity-coloured.
local GRAY = ("|cff%02x%02x%02x"):format(C.Colors.gray[1] * 255, C.Colors.gray[2] * 255, C.Colors.gray[3] * 255)
local SCORE_FORMAT = GRAY .. "(%s) |r%s"
local REGION_FORMAT = "|cff%02x%02x%02x[%s]|r %s"

ns:RegisterDefaults({
	quickJoin = {
		enable = false,
		-- Legacy key from the removed addon auto-invite checkbox; kept so CopyDefaults
		-- does not thrash old profiles. Blizzard's AutoAcceptButton is the only legal path.
		autoAccept = false,
		leaderScore = true,
		leaderRegion = true,
		autoHide = true,
	},
})

-- Cross-faction leader crest (inline atlas markup on the activity line).
local FACTION_ATLAS = { [0] = "questlog-questtypeicon-horde", [1] = "questlog-questtypeicon-alliance" }
local FACTION_LOGO_SIZE = 16

local function GetFactionPrefix(info)
	if not (ns.db.quickJoin.leaderScore and info and not info.crossFactionListing) then
		return ""
	end
	local atlas = FACTION_ATLAS[info.leaderFactionGroup]
	if not atlas or not CreateAtlasMarkup then
		return ""
	end
	return CreateAtlasMarkup(atlas, FACTION_LOGO_SIZE, FACTION_LOGO_SIZE) .. " "
end

local QuickJoin = ns:NewModule("QuickJoin", "quickJoin", { group = "automation", title = L["Quick Join"], order = 35, since = "1.2.9" })
local RealmCatalog = ns.RealmCatalog

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
-- Leader rating, region tag, and cross-faction crest on each search result
-- ---------------------------------------------------------------------------
local function GetBaseActivityName(info)
	if not info or not F.NotSecret(info.activityIDs) or not C_LFGList_GetActivityFullName then
		return
	end
	local activityName = C_LFGList_GetActivityFullName(info.activityIDs[1], nil, info.isWarMode)
	if not activityName or F.IsSecret(activityName) then
		return
	end
	return gsub(activityName, ".-" .. HEADER_COLON, "")
end

local function EnhanceSearchEntry(self)
	if not ns.db.quickJoin.enable then
		return
	end
	if not (ns.db.quickJoin.leaderScore or ns.db.quickJoin.leaderRegion) then
		return
	end

	local resultID = self.resultID
	local info = resultID and C_LFGList_GetSearchResultInfo and C_LFGList_GetSearchResultInfo(resultID)
	if not info then
		return
	end

	local activityName = GetBaseActivityName(info)
	if not activityName then
		return
	end

	local displayText = activityName

	if ns.db.quickJoin.leaderRegion and RealmCatalog and info.leaderName and F.NotSecret(info.leaderName) then
		local tag = RealmCatalog:GetLocaleTag(info.leaderName)
		if tag then
			displayText = format(REGION_FORMAT, C.Colors.orange[1] * 255, C.Colors.orange[2] * 255, C.Colors.orange[3] * 255, tag, displayText)
		end
	end

	local factionPrefix = GetFactionPrefix(info)
	if factionPrefix ~= "" then
		displayText = factionPrefix .. displayText
	end

	if ns.db.quickJoin.leaderScore and F.NotSecret(info.activityIDs) then
		local activityInfo = C_LFGList_GetActivityInfoTable and C_LFGList_GetActivityInfoTable(info.activityIDs[1], nil, info.isWarMode)
		if activityInfo then
			local pvpInfo = info.leaderPvpRatingInfo and info.leaderPvpRatingInfo[1]
			local score = (activityInfo.isMythicPlusActivity and info.leaderOverallDungeonScore) or (activityInfo.isRatedPvpActivity and pvpInfo and pvpInfo.rating)
			if score then
				displayText = format(SCORE_FORMAT, ColorScore(score), displayText)
			end
		end
	end

	self.ActivityName:SetText(displayText)
end

local function AddLeaderRegionTooltip(tooltip, resultID)
	if not (ns.db.quickJoin.enable and ns.db.quickJoin.leaderRegion and RealmCatalog) then
		return
	end
	local info = resultID and C_LFGList_GetSearchResultInfo and C_LFGList_GetSearchResultInfo(resultID)
	if not info or not info.leaderName or F.IsSecret(info.leaderName) then
		return
	end
	local tag = RealmCatalog:GetLocaleTag(info.leaderName)
	if not tag then
		return
	end
	local realm = RealmCatalog:ParseLeaderRealm(info.leaderName)
	local line = realm and format(L["Leader region: %s (%s)"], tag, realm) or format(L["Leader region: %s"], tag)
	tooltip:AddLine(line, C.Colors.orange[1], C.Colors.orange[2], C.Colors.orange[3])
	-- Blizzard's function already called Show(); relayout so the new line fits inside the frame.
	tooltip:Show()
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

	if RealmCatalog then
		RealmCatalog:RefreshPlayerContext()
	end

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

	-- Leader rating / region tags on results.
	hooksecurefunc("LFGListSearchEntry_Update", EnhanceSearchEntry)
	hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", AddLeaderRegionTooltip)
end

function QuickJoin:StopWaiting()
	if self.addonLoadHandle then
		ns:UnregisterEvent("ADDON_LOADED", self.addonLoadHandle)
		self.addonLoadHandle = nil
	end
	self.waiting = nil
end

function QuickJoin:Stop()
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

function QuickJoin:OnSettingChanged(key)
	if key == "enable" then
		-- ApplyModuleSetting owns enable lifecycle.
		return
	end
end

function QuickJoin:OnEnable()
	if RealmCatalog then
		RealmCatalog:RefreshPlayerContext()
	end
	self:TrySetup()
end

function QuickJoin:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Quick Join"], L["Double-click Group Finder results to apply, hide throwaway LFG popups, and show leader rating and region tags."])
	local _, scoreInit = builder:Checkbox(category, self, "leaderScore", L["Show Leader Rating"], L["Show the group leader's Mythic+/PvP rating on each search result, with a cross-faction crest."])
	local _, regionInit = builder:Checkbox(category, self, "leaderRegion", L["Show Leader Region"], L["Show a locale region tag (e.g. MX, OCE, DE) on Group Finder results when the leader is on a different realm locale than yours."])
	local _, hideInit = builder:Checkbox(category, self, "autoHide", L["Auto-hide LFG Popups"], L["Automatically dismiss the throwaway informational and expired-listing LFG popups."])

	builder:DependsOn(scoreInit, enableInit)
	builder:DependsOn(regionInit, enableInit)
	builder:DependsOn(hideInit, enableInit)
end
