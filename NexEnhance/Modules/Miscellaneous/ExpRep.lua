--[[
	NexEnhance - Experience / Reputation Bar
	-------------------------------------------------------------------------
	Replaces Blizzard's status tracking bar with one movable bar that chooses
	the most relevant active mode:

	  * Experience while levelling, with a rested overlay
	  * House XP when a house is tracked (Midnight housing)
	  * Watched reputation at max level
	  * Honor when "track honor as experience" is active
	  * Azerite power when a Heart of Azeroth is equipped

	Priority when several apply: levelling XP wins, then house XP (it is an
	explicit opt-in - you choose a tracked house), then reputation/honor/Azerite.
	Every applicable section still appears in the tooltip regardless of which one
	owns the visible bar.

	The tooltip still shows every applicable progress section, so levelling
	characters can see watched reputation/honor/Azerite details while XP remains
	the visible bar. Alt + Right-Click reports the visible bar to party chat.

	Adapted from KkthnxUI by Josh "Kkthnx" Russell:
	  https://github.com/Kkthnx-Wow/KkthnxUI/blob/main/KkthnxUI/Modules/Miscellaneous/Elements/ExpRep.lua
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local _G = _G
local format = string.format
local sfind = string.find
local tonumber = tonumber
local type = type
local math_huge = math.huge
local math_min = math.min

local CreateFrame = CreateFrame
local GetTime = GetTime
local UIParent = UIParent
local UnitLevel = UnitLevel
local UnitXP = UnitXP
local UnitXPMax = UnitXPMax
local GetXPExhaustion = GetXPExhaustion
local IsLevelAtEffectiveMaxLevel = IsLevelAtEffectiveMaxLevel
local IsXPUserDisabled = IsXPUserDisabled
local IsRestrictedAccount = IsRestrictedAccount
local IsTrialAccount = IsTrialAccount
local IsVeteranTrialAccount = IsVeteranTrialAccount
local IsWatchingHonorAsXP = IsWatchingHonorAsXP
local IsAltKeyDown = IsAltKeyDown
local IsInGroup = IsInGroup
-- C_ChatInfo.SendChatMessage is the live API; the global is a deprecated shim.
local SendChatMessage = C_ChatInfo.SendChatMessage
local UnitHonor = UnitHonor
local UnitHonorMax = UnitHonorMax
local UnitHonorLevel = UnitHonorLevel
local UnitExists = UnitExists
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local UIFrameFadeIn = UIFrameFadeIn
local UIFrameFadeOut = UIFrameFadeOut
local UIFrameFadeRemoveFrame = UIFrameFadeRemoveFrame
local hooksecurefunc = hooksecurefunc

local C_Reputation_GetWatchedFactionData = C_Reputation and C_Reputation.GetWatchedFactionData
local C_Reputation_IsFactionParagon = C_Reputation and C_Reputation.IsFactionParagon
local C_Reputation_GetFactionParagonInfo = C_Reputation and C_Reputation.GetFactionParagonInfo
local C_Reputation_IsMajorFaction = C_Reputation and C_Reputation.IsMajorFaction
local C_GossipInfo_GetFriendshipReputation = C_GossipInfo and C_GossipInfo.GetFriendshipReputation
local C_MajorFactions_GetMajorFactionData = C_MajorFactions and C_MajorFactions.GetMajorFactionData
local C_MajorFactions_HasMaximumRenown = C_MajorFactions and C_MajorFactions.HasMaximumRenown
local C_AzeriteItem_FindActiveAzeriteItem = C_AzeriteItem and C_AzeriteItem.FindActiveAzeriteItem
local C_AzeriteItem_GetAzeriteItemXPInfo = C_AzeriteItem and C_AzeriteItem.GetAzeriteItemXPInfo
local C_AzeriteItem_GetPowerLevel = C_AzeriteItem and C_AzeriteItem.GetPowerLevel

-- Midnight housing. GetCurrentHouseLevelFavor is a *request*: it returns nothing
-- and the client answers asynchronously with HOUSE_LEVEL_FAVOR_UPDATED, whose
-- payload { houseGUID, houseLevel, houseFavor } we cache. houseFavor is the
-- absolute total "House XP". To match the Housing dashboard's numbers we show the
-- cumulative "houseFavor / forLevel(level+1)" (e.g. 2670 / 3700) rather than the
-- within-level segment, formatted like the experience bar (cur - max (pct%) plus a
-- Remaining line). These reads are plain numbers (not Secret-flagged), so no
-- F.NotSecret needed.
local C_Housing = _G.C_Housing
local C_Housing_GetTrackedHouseGuid = C_Housing and C_Housing.GetTrackedHouseGuid
local C_Housing_GetCurrentHouseLevelFavor = C_Housing and C_Housing.GetCurrentHouseLevelFavor
local C_Housing_GetHouseLevelFavorForLevel = C_Housing and C_Housing.GetHouseLevelFavorForLevel

-- Neighborhood Endeavors, shown as a percentage line in the housing tooltip.
local C_NeighborhoodInitiative = _G.C_NeighborhoodInitiative
local C_Housing_GetMaxHouseLevel = C_Housing and C_Housing.GetMaxHouseLevel

local STATUSBAR = C.Media.Textures.statusbar
-- Retail unit-frame fill atlas. The "-Status" variant is the neutral, tintable
-- fill Blizzard colors per unit, so our per-type SetStatusBarColor tints still
-- read correctly. StatusBar:SetStatusBarTexture handles atlas names atlas-aware.
local UNITFRAME_ATLAS = "UI-HUD-UnitFrame-Player-PortraitOff-Bar-Health-Status"
local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"
local REPORT_COOLDOWN = 10

-- Use the WoW unit-frame atlas when the client provides it, else fall back to the
-- shared media texture so the bar can never render blank.
local function ApplyBarTexture(sb)
	if _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(UNITFRAME_ATLAS) then
		sb:SetStatusBarTexture(UNITFRAME_ATLAS)
	else
		sb:SetStatusBarTexture(STATUSBAR)
	end
end

-- Classic Blizzard tooltip border (matches the AFK Camera, Changelog, Install
-- panels). Border-only: the dark trough is drawn separately so the bar's fill
-- never paints over the frame.
local BLIZZARD_BORDER = {
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 14,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local REACTION_COLOR = {
	[9] = { r = 0.00, g = 0.60, b = 0.10 }, -- Paragon
	[10] = { r = 0.00, g = 0.74, b = 0.95 }, -- Renown
}

-- Shared defaults: used both for the saved-variable registration and as the
-- per-setting reset value in the Edit Mode dialog (kept in one place so the two
-- adjustment paths never drift).
local DEFAULTS = {
	enable = true,
	width = 400,
	height = 14,
	fontSize = 11,
	showText = true,
	showRested = true,
	fade = false,
	fadeOpacity = 0,
	fadeCombat = true,
	fadeTarget = false,
}

ns:RegisterDefaults({ expRep = DEFAULTS })

local ExpRep = ns:NewModule("ExpRep", "expRep", { group = "datatext", title = L["Experience Bar"], order = 20 })

local editMode
local bar
local displayText = ""
local reportLabel = ""
local lastReport = 0

local xpState, repState, honorState, azeriteState, housingState = {}, {}, {}, {}, {}

-- Latest HOUSE_LEVEL_FAVOR_UPDATED payload for the tracked house (or nil).
local housingData

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
-- GameTooltip has no native divider line, so reproduce Blizzard's own approach:
-- UIDropDownMenu_AddSeparator() draws the "UI-TooltipDivider-Transparent" texture
-- at 8px tall, stretched to the dropdown width (tFitDropDownSizeX). We overlay the
-- same texture parented to the tooltip and anchor it to the tooltip's left/right
-- edges so it stretches to the full tooltip width.
local DIVIDER_TEXTURE = "Interface\\Common\\UI-TooltipDivider-Transparent"
local dividerPool, dividerUsed = {}, 0

local function ReleaseDividers()
	for i = 1, dividerUsed do
		dividerPool[i]:Hide()
	end
	dividerUsed = 0
end

local function AcquireDivider()
	dividerUsed = dividerUsed + 1
	local tex = dividerPool[dividerUsed]
	if not tex then
		tex = _G.GameTooltip:CreateTexture(nil, "OVERLAY")
		tex:SetTexture(DIVIDER_TEXTURE)
		tex:SetHeight(8)
		dividerPool[dividerUsed] = tex
	end
	return tex
end

-- Inserts a blank spacer line and stretches a full-width divider texture over it.
local function AddTooltipDivider()
	local tt = _G.GameTooltip
	tt:AddLine(" ")
	local line = _G["GameTooltipTextLeft" .. tt:NumLines()]
	if not line then
		return
	end

	local tex = AcquireDivider()
	tex:ClearAllPoints()
	tex:SetPoint("LEFT", tt, "LEFT", 10, 0)
	tex:SetPoint("RIGHT", tt, "RIGHT", -10, 0)
	tex:SetPoint("TOP", line, "TOP", 0, 0)
	tex:Show()
end

local function IsMaxLevel()
	local level = UnitLevel("player")
	if IsLevelAtEffectiveMaxLevel and IsLevelAtEffectiveMaxLevel(level) then
		return true
	end
	if IsXPUserDisabled and IsXPUserDisabled() then
		return true
	end
	if (IsRestrictedAccount() or IsTrialAccount() or IsVeteranTrialAccount()) and level == 20 then
		return true
	end
	return false
end

local function SetBarValues(statusbar, minValue, maxValue, value)
	if maxValue <= minValue then
		maxValue = minValue + 1
	end
	statusbar:SetMinMaxValues(minValue, maxValue)
	statusbar:SetValue(value)
end

local function Progress(minValue, maxValue, value)
	if not maxValue or maxValue <= 0 then
		return 0, 1, 0, true, 0
	end

	local current = (value or 0) - (minValue or 0)
	local maximum = maxValue - (minValue or 0)
	if maximum <= 0 then
		maximum = 1
	end
	if current < 0 then
		current = 0
	elseif current > maximum then
		current = maximum
	end

	local percent = (current / maximum) * 100
	return current, maximum, percent, (current >= maximum), (maximum - current)
end

local function AddRemainingLine(state)
	local remaining = state.remaining or ((state.max or 0) - (state.cur or 0))
	if remaining < 0 then
		remaining = 0
	end

	local percent = state.max and state.max > 0 and (remaining / state.max * 100) or 0
	local bars = state.max and state.max > 0 and (remaining / state.max * 20) or 0
	_G.GameTooltip:AddDoubleLine(L["Remaining"], format("%s (%.1f%% - %.1f %s)", F.ShortValue(remaining), percent, bars, L["Bars"]), 1, 1, 1)
end

local function ReactionColor(reaction)
	local color = REACTION_COLOR[reaction] or (_G.FACTION_BAR_COLORS and _G.FACTION_BAR_COLORS[reaction])
	if color then
		return color.r, color.g, color.b
	end
	return 1, 1, 1
end

local function RenownLabel(level)
	level = tonumber(level) or 0
	local label = _G.RENOWN_LEVEL_LABEL
	if type(label) == "string" then
		if sfind(label, "%%d") then
			return format(label, level)
		end
		return label .. " " .. level
	end
	return "Renown " .. level
end

local function AzeriteItem()
	if not C_AzeriteItem_FindActiveAzeriteItem then
		return
	end
	local loc = C_AzeriteItem_FindActiveAzeriteItem()
	if loc and loc.IsEquipmentSlot and loc:IsEquipmentSlot() then
		return loc
	end
end

local function HideVisibleBar()
	displayText = ""
	reportLabel = ""
	bar.text:SetText("")
	bar.rest:Hide()
	bar.reward:Hide()
	bar:Hide()
end

-- ---------------------------------------------------------------------------
-- Fade behaviour (optional)
--   The bar rests at a low opacity and reveals on mouseover, optionally also
--   while in combat or while you have a target/focus. We drive it with the
--   shared Blizzard UIFrameFade manager (one engine-side updater) and the bar's
--   own OnEnter/OnLeave plus a couple of gated events - no per-frame polling.
-- ---------------------------------------------------------------------------
local FADE_DURATION = 0.25
local FADE_OUT_DELAY = 0.75
local fadeEventFrame
local fadeCombatEnterId
local fadeCombatLeaveId
local hideTimer
local isMouseOver = false

-- Conditions (besides hover) that pin the bar fully visible.
local function FadeForced()
	local cfg = ns.db.expRep
	if cfg.fadeCombat and InCombatLockdown() then
		return true
	end
	if cfg.fadeTarget and (UnitExists("target") or UnitExists("focus")) then
		return true
	end
	return false
end

local function FadeBarIn()
	if hideTimer then
		hideTimer:Cancel()
	end
	hideTimer = nil
	if bar then
		UIFrameFadeIn(bar, FADE_DURATION, bar:GetAlpha(), 1)
	end
end

local function FadeBarOut()
	hideTimer = nil
	if bar then
		UIFrameFadeOut(bar, FADE_DURATION, bar:GetAlpha(), (ns.db.expRep.fadeOpacity or 0) / 100)
	end
end

-- Snap the bar to the alpha its current state calls for (no scheduled delay).
local function ApplyFadeState()
	if not bar then
		return
	end
	if hideTimer then
		hideTimer:Cancel()
	end
	hideTimer = nil

	if not ns.db.expRep.fade then
		if UIFrameFadeRemoveFrame then
			UIFrameFadeRemoveFrame(bar)
		end
		bar:SetAlpha(1)
		return
	end

	if isMouseOver or FadeForced() then
		FadeBarIn()
	else
		FadeBarOut()
	end
end

-- (Re)gate the combat/target events to the current fade settings.
local function UnregisterFadeCombat()
	if fadeCombatEnterId then
		ns:UnregisterCombatEnterCallback(fadeCombatEnterId)
		fadeCombatEnterId = nil
	end
	if fadeCombatLeaveId then
		ns:UnregisterCombatLeaveCallback(fadeCombatLeaveId)
		fadeCombatLeaveId = nil
	end
end

local function RefreshFade()
	if not fadeEventFrame then
		fadeEventFrame = CreateFrame("Frame")
		fadeEventFrame:SetScript("OnEvent", ApplyFadeState)
	end
	fadeEventFrame:UnregisterAllEvents()
	UnregisterFadeCombat()

	local cfg = ns.db.expRep
	if cfg.fade then
		if cfg.fadeCombat then
			fadeCombatEnterId = ns:RegisterCombatEnterCallback(ApplyFadeState)
			fadeCombatLeaveId = ns:RegisterCombatLeaveCallback(ApplyFadeState)
		end
		if cfg.fadeTarget then
			fadeEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
			fadeEventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
		end
	end

	ApplyFadeState()
end

-- ---------------------------------------------------------------------------
-- Data builders
-- ---------------------------------------------------------------------------
local function BuildExperienceState()
	if IsMaxLevel() then
		xpState.available = nil
		return false
	end

	local cur = UnitXP("player") or 0
	local maxXP = UnitXPMax("player") or 1
	if maxXP <= 0 then
		maxXP = 1
	end
	local rested = GetXPExhaustion() or 0
	local percent = (cur / maxXP) * 100
	local remaining = maxXP - cur

	xpState.available = true
	xpState.cur, xpState.max, xpState.percent = cur, maxXP, percent
	xpState.rested, xpState.remaining = rested, remaining
	xpState.display = format("%s - %s (%.1f%%)", F.ShortValue(cur), F.ShortValue(maxXP), percent)
	return true
end

local function BuildReputationState(data)
	data = data or (C_Reputation_GetWatchedFactionData and C_Reputation_GetWatchedFactionData())
	if not data or not data.name then
		repState.available = nil
		return false
	end

	local name = data.name
	local reaction = data.reaction or 1
	local curThreshold = data.currentReactionThreshold or 0
	local nextThreshold = data.nextReactionThreshold or 1
	local standing = data.currentStanding or 0
	local factionID = data.factionID
	local label, rewardPending

	if factionID and C_GossipInfo_GetFriendshipReputation then
		local friend = C_GossipInfo_GetFriendshipReputation(factionID)
		if friend and friend.friendshipFactionID and friend.friendshipFactionID > 0 then
			label = friend.reaction
			curThreshold = friend.reactionThreshold or 0
			nextThreshold = friend.nextThreshold or math_huge
			standing = friend.standing or standing
		end
	end

	-- This client only exposes C_Reputation.IsFactionParagon, which returns true
	-- for any faction that *supports* paragon (including renown factions that
	-- are nowhere near it). Only treat it as paragon for regular factions, or
	-- for major factions that have actually reached maximum renown - otherwise a
	-- mid-renown faction (e.g. Silvermoon Court, Renown 4) wrongly shows Paragon.
	local isMajor = factionID and C_Reputation_IsMajorFaction and C_Reputation_IsMajorFaction(factionID)
	local majorMaxed = isMajor and C_MajorFactions_HasMaximumRenown and C_MajorFactions_HasMaximumRenown(factionID)

	if not label and factionID and C_Reputation_IsFactionParagon and C_Reputation_GetFactionParagonInfo and (not isMajor or majorMaxed) and C_Reputation_IsFactionParagon(factionID) then
		local cur, thresh, _, pending = C_Reputation_GetFactionParagonInfo(factionID)
		if cur and thresh and thresh > 0 then
			label = L["Paragon"]
			curThreshold, nextThreshold = 0, thresh
			standing = cur % thresh
			reaction = 9
			rewardPending = pending
		end
	end

	if not label and isMajor and C_MajorFactions_GetMajorFactionData then
		local major = C_MajorFactions_GetMajorFactionData(factionID)
		if major then
			reaction = 10
			curThreshold = 0
			nextThreshold = major.renownLevelThreshold or 1
			if C_MajorFactions_HasMaximumRenown and C_MajorFactions_HasMaximumRenown(factionID) then
				standing = nextThreshold
			else
				standing = major.renownReputationEarned or 0
			end
			label = format("|c%s%s|r", F.RGBToHex(0, 0.74, 0.95), RenownLabel(major.renownLevel))
		end
	end

	if not label then
		label = _G["FACTION_STANDING_LABEL" .. reaction] or _G.UNKNOWN
	end

	repState.available = true
	repState.name, repState.label = name, label
	repState.reaction, repState.rewardPending = reaction, rewardPending
	repState.minValue = (nextThreshold == math_huge or curThreshold == nextThreshold) and 0 or curThreshold
	repState.maxValue = (nextThreshold == math_huge) and 1 or nextThreshold
	repState.value = standing

	if nextThreshold == math_huge then
		repState.cur, repState.max, repState.percent, repState.remaining, repState.capped = 0, 1, 100, 0, true
		repState.display = format("%s: [%s]", name, label)
	else
		local cur, maxP, pct, capped, remaining = Progress(curThreshold, nextThreshold, standing)
		repState.cur, repState.max, repState.percent, repState.remaining, repState.capped = cur, maxP, pct, remaining, capped
		repState.display = format("%s: %s - %s (%.1f%%) [%s]", name, F.ShortValue(cur), F.ShortValue(maxP), pct, label)
	end
	return true
end

local function BuildHonorState()
	if not (IsWatchingHonorAsXP and IsWatchingHonorAsXP()) then
		honorState.available = nil
		return false
	end

	local cur = UnitHonor("player") or 0
	local maxHonor = UnitHonorMax("player") or 1
	if maxHonor <= 0 then
		maxHonor = 1
	end
	local level = UnitHonorLevel("player") or 0
	local percent = (cur / maxHonor) * 100

	honorState.available = true
	honorState.cur, honorState.max, honorState.percent = cur, maxHonor, percent
	honorState.level, honorState.remaining = level, maxHonor - cur
	honorState.display = format("%s - %s (%.1f%%) [%s]", F.ShortValue(cur), F.ShortValue(maxHonor), percent, level)
	return true
end

local function BuildAzeriteState()
	if not (C_AzeriteItem_GetAzeriteItemXPInfo and C_AzeriteItem_GetPowerLevel) then
		azeriteState.available = nil
		return false
	end

	local loc = AzeriteItem()
	if not loc then
		azeriteState.available = nil
		return false
	end

	local cur, maxAz = C_AzeriteItem_GetAzeriteItemXPInfo(loc)
	local level = C_AzeriteItem_GetPowerLevel(loc)
	if not maxAz or maxAz <= 0 then
		azeriteState.available = nil
		return false
	end

	cur = cur or 0
	local percent = (cur / maxAz) * 100

	azeriteState.available = true
	azeriteState.cur, azeriteState.max, azeriteState.percent = cur, maxAz, percent
	azeriteState.level, azeriteState.remaining = level or 0, maxAz - cur
	azeriteState.display = format("%s - %s (%.1f%%) [%s]", F.ShortValue(cur), F.ShortValue(maxAz), percent, level or 0)
	return true
end

-- Ask the client for the tracked house's favor. The reply arrives later via
-- HOUSE_LEVEL_FAVOR_UPDATED, so we only fire this on the events that can change
-- which house is tracked (enter world, tracked-house change) rather than every
-- rebuild, to avoid hammering the request.
local function RequestHousingFavor()
	if not (C_Housing_GetTrackedHouseGuid and C_Housing_GetCurrentHouseLevelFavor) then
		return
	end
	local guid = C_Housing_GetTrackedHouseGuid()
	if guid then
		C_Housing_GetCurrentHouseLevelFavor(guid)
	end
end

-- Neighborhood Endeavors. RequestNeighborhoodInitiativeInfo primes the client
-- cache; the reply lands via NEIGHBORHOOD_INITIATIVE_UPDATED and we simply re-read
-- on the next tooltip hover. GetEndeavorProgress mirrors the dashboard's Endeavors
-- tab: currentProgress against the final milestone's required contribution.
local function RequestEndeavorInfo()
	if C_NeighborhoodInitiative and C_NeighborhoodInitiative.RequestNeighborhoodInitiativeInfo then
		C_NeighborhoodInitiative.RequestNeighborhoodInitiativeInfo()
	end
end

local function GetEndeavorProgress()
	if not (C_NeighborhoodInitiative and C_NeighborhoodInitiative.GetNeighborhoodInitiativeInfo) then
		return nil
	end
	local info = C_NeighborhoodInitiative.GetNeighborhoodInitiativeInfo()
	-- initiativeID 0 means the neighborhood is between Endeavors (choosing stage).
	if not info or not info.isLoaded or info.initiativeID == 0 then
		return nil
	end
	local milestones = info.milestones
	local maxProgress = milestones and #milestones > 0 and milestones[#milestones].requiredContributionAmount or info.progressRequired
	if not maxProgress or maxProgress <= 0 then
		return nil
	end
	local pct = (info.currentProgress or 0) / maxProgress * 100
	return pct > 100 and 100 or pct
end

local function BuildHousingState()
	if not (C_Housing_GetTrackedHouseGuid and C_Housing_GetHouseLevelFavorForLevel) then
		housingState.available = nil
		return false
	end

	local guid = C_Housing_GetTrackedHouseGuid()
	-- Need a tracked house and cached favor data that belongs to it. The data
	-- is seeded by RequestHousingFavor + HOUSE_LEVEL_FAVOR_UPDATED; until it
	-- arrives we simply report unavailable (the event triggers a rebuild).
	if not guid or not housingData or housingData.houseGUID ~= guid then
		housingState.available = nil
		return false
	end

	local level = housingData.houseLevel or 1
	local favor = housingData.houseFavor or 0
	local minBar = C_Housing_GetHouseLevelFavorForLevel(level) or 0
	local nextBar = C_Housing_GetHouseLevelFavorForLevel(level + 1) or minBar
	local maxLevel = C_Housing_GetMaxHouseLevel and C_Housing_GetMaxHouseLevel()
	local atMax = (maxLevel and level >= maxLevel) or nextBar <= minBar

	housingState.available = true
	housingState.level = level
	housingState.capped = atMax

	if atMax then
		housingState.cur, housingState.max, housingState.percent, housingState.remaining = 1, 1, 100, 0
		housingState.display = format("%s [%s %d]", _G.MAXIMUM or "Maximum", _G.LEVEL or "Level", level)
	else
		-- Cumulative "House XP / next-level threshold" exactly like the Housing
		-- dashboard (e.g. 2670 / 3700), formatted like the experience bar.
		local cur, maxP, pct, capped, remaining = Progress(0, nextBar, favor)
		housingState.cur, housingState.max, housingState.percent = cur, maxP, pct
		housingState.remaining, housingState.capped = remaining, capped
		housingState.display = format("%s - %s (%.1f%%)", F.ShortValue(cur), F.ShortValue(maxP), pct)
	end
	return true
end

-- ---------------------------------------------------------------------------
-- Visible bar modes
-- ---------------------------------------------------------------------------
local function ShowExperience()
	reportLabel = _G.COMBAT_XP_GAIN or "Experience"
	displayText = xpState.display

	bar.fill:SetStatusBarColor(0, 0.4, 1, 0.9)
	SetBarValues(bar.fill, 0, xpState.max, xpState.cur)

	local showRested = ns.db.expRep.showRested and xpState.rested and xpState.rested > 0

	if showRested then
		bar.rest:SetStatusBarColor(1, 0, 1, 0.35)
		SetBarValues(bar.rest, 0, xpState.max, math_min(xpState.cur + xpState.rested, xpState.max))
	end

	bar.rest:SetShown(showRested)
	bar.reward:Hide()
	bar.text:SetText(displayText)
	bar:Show()
end

local function ShowReputation()
	reportLabel = _G.REPUTATION or "Reputation"
	displayText = repState.display

	local r, g, b = ReactionColor(repState.reaction)
	bar.fill:SetStatusBarColor(r, g, b, 1)
	SetBarValues(bar.fill, repState.minValue, repState.maxValue, repState.value)

	bar.rest:Hide()
	bar.reward:SetShown(not not repState.rewardPending)
	bar.text:SetText(displayText)
	bar:Show()
end

local function ShowHonor()
	reportLabel = _G.HONOR or "Honor"
	displayText = honorState.display

	bar.fill:SetStatusBarColor(0.94, 0.45, 0.25, 1)
	SetBarValues(bar.fill, 0, honorState.max, honorState.cur)

	bar.rest:Hide()
	bar.reward:Hide()
	bar.text:SetText(displayText)
	bar:Show()
end

local function ShowAzerite()
	reportLabel = _G.AZERITE_POWER or "Azerite"
	displayText = azeriteState.display

	bar.fill:SetStatusBarColor(0.90, 0.80, 0.60, 1)
	SetBarValues(bar.fill, 0, azeriteState.max, azeriteState.cur)

	bar.rest:Hide()
	bar.reward:Hide()
	bar.text:SetText(displayText)
	bar:Show()
end

local function ShowHousing()
	reportLabel = L["Housing Experience"]
	displayText = housingState.display

	-- Housing gold, matching the Housing dashboard's frame art.
	bar.fill:SetStatusBarColor(1.0, 0.82, 0.0, 1)
	SetBarValues(bar.fill, 0, housingState.max, housingState.cur)

	bar.rest:Hide()
	bar.reward:Hide()
	bar.text:SetText(displayText)
	bar:Show()
end

-- ---------------------------------------------------------------------------
-- Tooltip / scripts
-- ---------------------------------------------------------------------------
local function AddExperienceTooltip()
	if not xpState.available then
		return false
	end

	_G.GameTooltip:AddDoubleLine("|cff0070ff" .. (_G.COMBAT_XP_GAIN or "Experience") .. "|r", format("%s %d", _G.LEVEL or "Level", UnitLevel("player")))
	_G.GameTooltip:AddLine(" ")
	_G.GameTooltip:AddDoubleLine(L["XP"], format("%s - %s (%.1f%%)", F.ShortValue(xpState.cur), F.ShortValue(xpState.max), xpState.percent or 0), 1, 1, 1)
	AddRemainingLine(xpState)
	if xpState.rested and xpState.rested > 0 then
		local pct = xpState.max and xpState.max > 0 and (xpState.rested / xpState.max * 100) or 0
		_G.GameTooltip:AddDoubleLine(L["Rested"], format("+%s (%.1f%%)", F.ShortValue(xpState.rested), pct), 1, 1, 1)
	end
	return true
end

local function AddReputationTooltip(addSpacing)
	if not repState.available then
		return false
	end

	if addSpacing then
		AddTooltipDivider()
	end
	_G.GameTooltip:AddDoubleLine("|cff00bdfc" .. (repState.name or "") .. "|r", repState.label or "", 1, 1, 1)
	_G.GameTooltip:AddLine(" ")
	if repState.capped then
		_G.GameTooltip:AddLine(repState.display, 1, 1, 1, true)
	else
		_G.GameTooltip:AddDoubleLine(_G.REPUTATION or "Reputation", format("%s - %s (%.1f%%)", F.ShortValue(repState.cur), F.ShortValue(repState.max), repState.percent or 0), 1, 1, 1)
		AddRemainingLine(repState)
	end
	if repState.rewardPending then
		_G.GameTooltip:AddLine(_G.REWARD_AVAILABLE or "Reward available", 0, 1, 0)
	end
	return true
end

local function AddHonorTooltip(addSpacing)
	if not honorState.available then
		return false
	end

	if addSpacing then
		AddTooltipDivider()
	end
	_G.GameTooltip:AddDoubleLine("|cff00bdfc" .. (_G.HONOR or "Honor") .. "|r", (_G.LEVEL or "Level") .. " " .. (honorState.level or 0))
	_G.GameTooltip:AddLine(" ")
	_G.GameTooltip:AddDoubleLine(L["Honor XP"], format("%s - %s (%.1f%%)", F.ShortValue(honorState.cur), F.ShortValue(honorState.max), honorState.percent or 0), 1, 1, 1)
	AddRemainingLine(honorState)
	return true
end

local function AddAzeriteTooltip(addSpacing)
	if not azeriteState.available then
		return false
	end

	if addSpacing then
		AddTooltipDivider()
	end
	_G.GameTooltip:AddDoubleLine("|cff00bdfc" .. (_G.AZERITE_POWER or "Azerite") .. "|r", (_G.LEVEL or "Level") .. " " .. (azeriteState.level or 0))
	_G.GameTooltip:AddLine(" ")
	_G.GameTooltip:AddDoubleLine(L["XP"], format("%s - %s (%.1f%%)", F.ShortValue(azeriteState.cur), F.ShortValue(azeriteState.max), azeriteState.percent or 0), 1, 1, 1)
	AddRemainingLine(azeriteState)
	return true
end

local function AddHousingTooltip(addSpacing)
	if not housingState.available then
		return false
	end

	if addSpacing then
		AddTooltipDivider()
	end
	local hdr = C.Colors.header
	_G.GameTooltip:AddDoubleLine(L["Housing Experience"], format("%s %d", _G.LEVEL or "Level", housingState.level or 1), hdr[1], hdr[2], hdr[3], hdr[1], hdr[2], hdr[3])
	_G.GameTooltip:AddLine(" ")
	if housingState.capped then
		_G.GameTooltip:AddLine(housingState.display, 1, 1, 1, true)
	else
		_G.GameTooltip:AddDoubleLine(L["XP"], format("%s - %s (%.1f%%)", F.ShortValue(housingState.cur), F.ShortValue(housingState.max), housingState.percent or 0), 1, 1, 1)
		AddRemainingLine(housingState)
	end

	-- Neighborhood Endeavor completion, matching the dashboard's "%0.2f%%" readout.
	local endeavorPct = GetEndeavorProgress()
	if endeavorPct then
		_G.GameTooltip:AddDoubleLine(L["Endeavor Progress"], format("%.2f%%", endeavorPct), 1, 1, 1)
	end
	return true
end

local function OnEnter()
	isMouseOver = true
	if ns.db.expRep.fade then
		FadeBarIn()
	end
	if _G.GameTooltip:IsForbidden() then
		return
	end
	_G.GameTooltip:ClearLines()
	ReleaseDividers()
	_G.GameTooltip:SetOwner(bar, "ANCHOR_CURSOR")

	local any = AddExperienceTooltip()
	local addedHousing = AddHousingTooltip(any)
	any = any or addedHousing
	local addedRep = AddReputationTooltip(any)
	any = any or addedRep
	local addedHonor = AddHonorTooltip(any)
	any = any or addedHonor
	local addedAzerite = AddAzeriteTooltip(any)
	any = any or addedAzerite

	if any then
		_G.GameTooltip:AddLine(" ")
	end
	_G.GameTooltip:AddLine(C.InfoColor .. L["Alt + Right-Click to report to party chat."] .. "|r")
	_G.GameTooltip:Show()
end

local function OnLeave()
	isMouseOver = false
	if ns.db.expRep.fade and not FadeForced() then
		if hideTimer then
			hideTimer:Cancel()
		end
		hideTimer = C_Timer.NewTimer(FADE_OUT_DELAY, FadeBarOut)
	end
	ReleaseDividers()
	if not _G.GameTooltip:IsForbidden() then
		_G.GameTooltip:Hide()
	end
end

local function OnMouseUp(_, button)
	if not (IsAltKeyDown() and button == "RightButton") then
		return
	end
	if displayText == "" then
		return
	end
	if (GetTime() - lastReport) < REPORT_COOLDOWN then
		return
	end
	if not IsInGroup() then
		F.Print(_G.ERR_QUEST_PUSH_NOT_IN_PARTY_S or "Not in a party.")
		return
	end

	lastReport = GetTime()
	SendChatMessage(reportLabel .. ": " .. displayText, "PARTY")
end

-- ---------------------------------------------------------------------------
-- Update / appearance
-- ---------------------------------------------------------------------------
local function UpdateBar(_, _, unit)
	if not ns.db.expRep.enable or not bar then
		return
	end
	if unit and unit ~= "player" then
		return
	end

	BuildExperienceState()
	BuildHousingState()
	BuildReputationState()
	BuildHonorState()
	BuildAzeriteState()

	if xpState.available then
		ShowExperience()
	elseif housingState.available then
		ShowHousing()
	elseif repState.available then
		ShowReputation()
	elseif honorState.available then
		ShowHonor()
	elseif azeriteState.available then
		ShowAzerite()
	else
		HideVisibleBar()
	end

	-- A freshly-shown bar should respect the resting fade alpha right away.
	if ns.db.expRep.fade and bar:IsShown() then
		ApplyFadeState()
	end
end

-- UPDATE_FACTION and PLAYER_EQUIPMENT_CHANGED arrive in bursts (a rep turn-in
-- nudges every faction; a gear swap fires per slot). UpdateBar rebuilds all four
-- states every time, so coalesce the storm into a single end-of-frame rebuild.
local QueueBarUpdate = F.Debounce(0, UpdateBar)

-- Most events just coalesce into a rebuild. HOUSE_LEVEL_FAVOR_UPDATED carries the
-- favor payload we must cache first (it only arrives after a GetCurrentHouseLevelFavor
-- request); a tracked-house change invalidates the cache and asks for fresh data;
-- and entering the world primes the first request.
local function OnBarEvent(_, event, arg1)
	if event == "HOUSE_LEVEL_FAVOR_UPDATED" then
		if arg1 and C_Housing_GetTrackedHouseGuid and arg1.houseGUID == C_Housing_GetTrackedHouseGuid() then
			housingData = arg1
		end
	elseif event == "TRACKED_HOUSE_CHANGED" then
		housingData = nil
		RequestHousingFavor()
	elseif event == "PLAYER_ENTERING_WORLD" then
		RequestHousingFavor()
		RequestEndeavorInfo()
	end
	QueueBarUpdate()
end

local function ApplyAppearance()
	if not bar then
		return
	end
	local cfg = ns.db.expRep

	bar:SetSize(cfg.width, cfg.height)
	bar.spark:SetHeight(cfg.height + 6)
	F.SetFontSize(bar.text, cfg.fontSize)
	bar.text:SetShown(cfg.showText)

	RefreshFade()
end

local EVENTS = {
	"PLAYER_ENTERING_WORLD",
	"PLAYER_LEVEL_UP",
	"UPDATE_EXHAUSTION",
	"PLAYER_XP_UPDATE",
	"ENABLE_XP_GAIN",
	"DISABLE_XP_GAIN",
	"UPDATE_FACTION",
	"QUEST_FINISHED",
	"MAJOR_FACTION_RENOWN_LEVEL_CHANGED",
	"MAJOR_FACTION_UNLOCKED",
	"HONOR_XP_UPDATE",
	"PLAYER_FLAGS_CHANGED",
	"PLAYER_EQUIPMENT_CHANGED",
	"AZERITE_ITEM_EXPERIENCE_CHANGED",
	"HOUSE_LEVEL_FAVOR_UPDATED",
	"TRACKED_HOUSE_CHANGED",
}

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------
local function BuildBar()
	if bar then
		return bar
	end

	local f = CreateFrame("Frame", nil, UIParent)
	f:SetFrameStrata("LOW")
	f:EnableMouse(true)

	local base = f:GetFrameLevel()

	-- Dark trough behind the fill (drawn below the child status bars).
	local trough = f:CreateTexture(nil, "BACKGROUND")
	trough:SetAllPoints()
	trough:SetColorTexture(0, 0, 0, 0.6)
	f.trough = trough

	-- Blizzard tooltip-style border, framed just outside the bar so the fill
	-- texture never covers it. Kept above the fills so the edges stay crisp.
	local border = CreateFrame("Frame", nil, f, "BackdropTemplate")
	border:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 3)
	border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
	border:SetFrameLevel(base + 4)
	border:SetBackdrop(BLIZZARD_BORDER)
	border:SetBackdropBorderColor(1, 1, 1)
	f.border = border

	local rest = CreateFrame("StatusBar", nil, f)
	rest:SetAllPoints()
	rest:SetFrameLevel(base + 1)
	ApplyBarTexture(rest)
	rest:SetStatusBarColor(1, 0, 1, 0.35)
	rest:Hide()
	f.rest = rest

	local fill = CreateFrame("StatusBar", nil, f)
	fill:SetAllPoints()
	fill:SetFrameLevel(base + 3)
	ApplyBarTexture(fill)
	f.fill = fill

	local spark = fill:CreateTexture(nil, "OVERLAY")
	spark:SetTexture(SPARK)
	spark:SetBlendMode("ADD")
	spark:SetAlpha(0.6)
	spark:SetWidth(16)
	spark:SetPoint("CENTER", fill:GetStatusBarTexture(), "RIGHT", 0, 0)
	f.spark = spark

	local reward = fill:CreateTexture(nil, "OVERLAY")
	reward:SetAtlas("ParagonReputation_Bag")
	reward:SetSize(14, 16)
	reward:SetPoint("CENTER", f, "LEFT", 0, 0)
	reward:Hide()
	f.reward = reward

	local text = F.CreateFS(fill, ns.db.expRep.fontSize)
	text:SetPoint("CENTER")
	text:SetWordWrap(false)
	text:SetTextColor(0.9, 0.9, 0.9)
	text:SetDrawLayer("OVERLAY", 7)
	f.text = text

	f:SetScript("OnEvent", OnBarEvent)
	f:SetScript("OnEnter", OnEnter)
	f:SetScript("OnLeave", OnLeave)
	f:SetScript("OnMouseUp", OnMouseUp)

	bar = f
	return f
end

-- Replace Blizzard's status tracker. The frame is not protected; unregistering
-- and hiding it avoids duplicate bars without tainting secure gameplay frames.
local function HideBlizzard()
	local mgr = _G.StatusTrackingBarManager
	if not mgr or mgr.nexHidden then
		return
	end
	mgr.nexHidden = true
	mgr:UnregisterAllEvents()
	mgr:Hide()
	hooksecurefunc(mgr, "Show", function(self)
		if self.nexHidden then
			self:Hide()
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Edit Mode dialog settings
--   Mirror the appearance options (everything except the master enable toggle)
--   onto the LibEditMode dialog so the bar can be tuned while it is being moved.
--   Both paths read/write the same profile keys, so they stay in sync.
-- ---------------------------------------------------------------------------
local function ApplySetting(key, value)
	ns.db.expRep[key] = value
	ApplyAppearance()
	UpdateBar(bar)
end

local function MakeSlider(key, name, desc, minValue, maxValue)
	return {
		kind = editMode.SettingType.Slider,
		name = name,
		desc = desc,
		default = DEFAULTS[key],
		minValue = minValue,
		maxValue = maxValue,
		valueStep = 1,
		get = function()
			return ns.db.expRep[key]
		end,
		set = function(_, value)
			ApplySetting(key, value)
		end,
	}
end

local function MakeCheckbox(key, name, desc)
	return {
		kind = editMode.SettingType.Checkbox,
		name = name,
		desc = desc,
		default = DEFAULTS[key],
		get = function()
			return ns.db.expRep[key]
		end,
		set = function(_, value)
			ApplySetting(key, value)
		end,
	}
end

local function SetupEditModeSettings()
	editMode = _G.LibStub and _G.LibStub("LibEditMode", true)
	if not editMode or not editMode.AddFrameSettings then
		return
	end

	editMode:AddFrameSettings(bar, {
		MakeSlider("width", L["Bar Width"], L["Width of the experience bar."], 120, 600),
		MakeSlider("height", L["Bar Height"], L["Height of the experience bar."], 6, 40),
		MakeSlider("fontSize", L["Font Size"], L["Size of the bar text."], 8, 24),
		MakeCheckbox("showText", L["Show Bar Text"], L["Show the progress text on the bar."]),
		MakeCheckbox("showRested", L["Show Rested"], L["Show the rested-experience overlay while levelling."]),
		MakeCheckbox("fade", L["Fade Bar"], L["Fade the bar out and reveal it on mouseover."]),
		MakeSlider("fadeOpacity", L["Faded Opacity"], L["Opacity of the bar when faded out (0 = fully hidden)."], 0, 100),
		MakeCheckbox("fadeCombat", L["Show in Combat"], L["Keep the bar fully visible while in combat."]),
		MakeCheckbox("fadeTarget", L["Show with Target"], L["Keep the bar fully visible while you have a target or focus."]),
	})
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
local function RegisterBarEvents()
	if not bar or bar.nexEventsRegistered then
		return
	end
	for i = 1, #EVENTS do
		pcall(bar.RegisterEvent, bar, EVENTS[i])
	end
	bar.nexEventsRegistered = true
end

local function UnregisterBarEvents()
	if not bar or not bar.nexEventsRegistered then
		return
	end
	bar:UnregisterAllEvents()
	bar.nexEventsRegistered = nil
end

function ExpRep:Setup()
	if self.setupDone then
		return
	end
	self.setupDone = true

	BuildBar()
	HideBlizzard()
	F.CreateMover(bar, "ExpRepBar", L["Experience Bar"], "TOP", 0, -4)
	SetupEditModeSettings()
	ApplyAppearance()
	-- Prime house favor + neighborhood Endeavor data so they're ready on first hover.
	RequestHousingFavor()
	RequestEndeavorInfo()
	UpdateBar(bar)
	RegisterBarEvents()
end

function ExpRep:OnEnable()
	if not ns.db.expRep.enable then
		return
	end
	self:Setup()
	if bar then
		bar:Show()
		RegisterBarEvents()
		UpdateBar(bar)
	end
end

function ExpRep:OnDisable()
	UnregisterBarEvents()
	UnregisterFadeCombat()
	if fadeEventFrame then
		fadeEventFrame:UnregisterAllEvents()
	end
	if bar then
		bar:Hide()
	end
end

function ExpRep:OnSettingChanged(key, value)
	if key == "enable" then
		if value then
			self:OnEnable()
		else
			self:OnDisable()
		end
		return
	end

	ApplyAppearance()
	UpdateBar(bar)

	-- Reflect Settings-panel changes in the Edit Mode dialog if it is open.
	if editMode and editMode.RefreshFrameSettings and bar then
		editMode:RefreshFrameSettings(bar)
	end
end

function ExpRep:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Experience Bar"], L["Replace Blizzard's experience/reputation tracker with a movable bar (reload to restore Blizzard's)."])
	local _, textInit = builder:Checkbox(category, self, "showText", L["Show Bar Text"], L["Show the progress text on the bar."])
	local _, restedInit = builder:Checkbox(category, self, "showRested", L["Show Rested"], L["Show the rested-experience overlay while levelling."])
	local _, widthInit = builder:Slider(category, self, "width", L["Bar Width"], L["Width of the experience bar."], 120, 600, 1)
	local _, heightInit = builder:Slider(category, self, "height", L["Bar Height"], L["Height of the experience bar."], 6, 40, 1)
	local _, fontInit = builder:Slider(category, self, "fontSize", L["Font Size"], L["Size of the bar text."], 8, 24, 1)
	local _, fadeInit = builder:Checkbox(category, self, "fade", L["Fade Bar"], L["Fade the bar out and reveal it on mouseover."])
	local _, fadeOpacityInit = builder:Slider(category, self, "fadeOpacity", L["Faded Opacity"], L["Opacity of the bar when faded out (0 = fully hidden)."], 0, 100, 5)
	local _, fadeCombatInit = builder:Checkbox(category, self, "fadeCombat", L["Show in Combat"], L["Keep the bar fully visible while in combat."])
	local _, fadeTargetInit = builder:Checkbox(category, self, "fadeTarget", L["Show with Target"], L["Keep the bar fully visible while you have a target or focus."])

	builder:DependsOn(textInit, enableInit)
	builder:DependsOn(restedInit, enableInit)
	builder:DependsOn(widthInit, enableInit)
	builder:DependsOn(heightInit, enableInit)
	builder:DependsOn(fontInit, enableInit)
	builder:DependsOn(fadeInit, enableInit)
	builder:DependsOn(fadeOpacityInit, fadeInit)
	builder:DependsOn(fadeCombatInit, fadeInit)
	builder:DependsOn(fadeTargetInit, fadeInit)
end
