--[[
	NexEnhance - Queue Timer
	-------------------------------------------------------------------------
	Replaces the small default LFG / PvP "ready" countdown with a larger, more
	visible timer (colour-coded as it runs down) plus an optional triple-beep
	warning as the queue is about to expire. The PvE pop time is persisted
	per-character so the countdown survives a /reload mid-popup.

	Ported from KkthnxUI's QueueTimer (by Josh "Kkthnx" Russell), adapted to
	the NexEnhance framework:
	  https://github.com/Kkthnx-Wow/KkthnxUI
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local L = ns.L

local _G = _G
local ipairs, select, type = ipairs, select, type
local format = string.format
local max = math.max
local CreateFrame = CreateFrame
local GetTime = GetTime
local PlaySoundFile = PlaySoundFile
local SecondsToTime = SecondsToTime
local C_Timer_After = C_Timer.After
local GetBattlefieldPortExpiration = GetBattlefieldPortExpiration
local GetBattlefieldStatus = GetBattlefieldStatus

-- Tunables.
local WARNING_SOUND_ID = 567458
local WARNING_THRESHOLD = 6
local PVE_EXPIRE_BASE = 40
local UPDATE_INTERVAL = 0.2

ns:RegisterDefaults({
	queueTimer = {
		enable = true,
		warning = true,
		hideOtherTimers = true,
	},
})

local QueueTimer = ns:NewModule("QueueTimer", "queueTimer", { group = "misc", title = L["Queue Timer"], order = 40 })

-- State.
local remainingPvETime = 0
local activePvPIndex
local updateFrame
local hasWarned = false
local sinceLastUpdate = 0

local function db()
	return ns.db.queueTimer
end

-- ---------------------------------------------------------------------------
-- Per-character persistence (survives a reload mid-popup)
-- ---------------------------------------------------------------------------
local function SavePvEPopTime()
	ns.charDB.queueTimer = ns.charDB.queueTimer or {}
	ns.charDB.queueTimer.pvePopTime = GetTime()
end

local function LoadPvEPopTime()
	local data = ns.charDB.queueTimer
	return data and data.pvePopTime or nil
end

local function ClearPvEPopTime()
	local data = ns.charDB.queueTimer
	if data then
		data.pvePopTime = nil
	end
end

local function RecalculateRemainingPvE()
	local popTime = LoadPvEPopTime()
	if type(popTime) ~= "number" then
		remainingPvETime = PVE_EXPIRE_BASE
		return
	end

	local remain = PVE_EXPIRE_BASE - (GetTime() - popTime)
	if remain < 0 or remain > PVE_EXPIRE_BASE then
		remainingPvETime = PVE_EXPIRE_BASE
	else
		remainingPvETime = remain
	end
end

-- ---------------------------------------------------------------------------
-- Custom labels on the ready dialog
-- ---------------------------------------------------------------------------
local function HideDefaultQueueTimers()
	if not db().hideOtherTimers then return end

	local popup = _G.LFGDungeonReadyPopup
	if not popup then return end

	for _, child in ipairs({ popup:GetChildren() }) do
		if child.GetObjectType and child:GetObjectType() == "StatusBar" then
			child:Hide()
		end
	end
end

local function CreateLabels(dialog)
	if not dialog or not dialog.label or dialog.nexQueueLabels then return end

	local width = dialog:GetWidth()

	dialog.nexHeader = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	dialog.nexHeader:SetPoint("TOP", dialog.label, "TOP", 0, 0)
	dialog.nexHeader:SetText(L["Queue expires in"])
	local fontPath = select(1, dialog.nexHeader:GetFont())
	dialog.nexHeader:SetFont(fontPath, 15, "")
	dialog.nexHeader:SetShadowOffset(1, -1)
	dialog.nexHeader:SetWidth(width)

	dialog.nexTimer = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	dialog.nexTimer:SetPoint("TOP", dialog.nexHeader, "BOTTOM", 0, -5)
	dialog.nexTimer:SetFont(fontPath, 24, "")
	dialog.nexTimer:SetShadowOffset(1, -1)
	dialog.nexTimer:SetWidth(width)

	dialog.nexName = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	dialog.nexName:SetPoint("TOP", dialog.nexTimer, "BOTTOM", 0, -4)
	dialog.nexName:SetFont(fontPath, 15, "")
	dialog.nexName:SetShadowOffset(1, -1)
	dialog.nexName:SetWidth(width)

	dialog.nexStatus = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	dialog.nexStatus:SetPoint("TOP", dialog.nexName, "BOTTOM", 0, -3)
	dialog.nexStatus:SetFont(fontPath, 11, "")
	dialog.nexStatus:SetShadowOffset(1, -1)
	dialog.nexStatus:SetWidth(width)

	dialog.nexQueueLabels = true
end

local function ExpiresText(seconds)
	local remain = (seconds and seconds > 0) and seconds or 1
	local hex = (remain > 20) and "20ff20" or (remain > 10) and "ffff00" or "ff0000"
	return format("|cff%s%s|r", hex, SecondsToTime(remain))
end

function QueueTimer:UpdateDisplay(timeRemaining, dialog, isPvP)
	if not dialog then return end
	CreateLabels(dialog)

	local remain = timeRemaining or 0
	if dialog.label then
		dialog.label:SetText("")
	end
	if dialog.instanceInfo and dialog.instanceInfo.SetAlpha then
		dialog.instanceInfo:SetAlpha(0)
	end

	if dialog.nexTimer then
		dialog.nexTimer:SetText(ExpiresText(remain))
	end

	local info = dialog.instanceInfo
	if dialog.nexName and dialog.nexStatus and info and info.name and (info:IsShown() or isPvP) then
		dialog.nexName:SetText(info.name:GetText() or "")
		dialog.nexStatus:SetText(info.statusText and info.statusText:GetText() or "")
	else
		if dialog.nexName then dialog.nexName:SetText("") end
		if dialog.nexStatus then dialog.nexStatus:SetText("") end
	end
end

-- ---------------------------------------------------------------------------
-- Warning sound
-- ---------------------------------------------------------------------------
local function WarnOnExpiration(seconds)
	if not db().warning then return end
	if seconds <= WARNING_THRESHOLD and not hasWarned then
		PlaySoundFile(WARNING_SOUND_ID, "master")
		C_Timer_After(0.1, function() PlaySoundFile(WARNING_SOUND_ID, "master") end)
		C_Timer_After(0.2, function() PlaySoundFile(WARNING_SOUND_ID, "master") end)
		hasWarned = true
	end
end

-- ---------------------------------------------------------------------------
-- Ticker
-- ---------------------------------------------------------------------------
local function UpdatePvE()
	local dialog = _G.LFGDungeonReadyDialog
	if dialog and dialog:IsShown() then
		local seconds = max(remainingPvETime or 0, 0)
		WarnOnExpiration(seconds)
		QueueTimer:UpdateDisplay(seconds, dialog)
	end
end

local function UpdatePvP()
	local dialog = _G.PVPReadyDialog
	if activePvPIndex and dialog and _G.PVPReadyDialog_Showing and _G.PVPReadyDialog_Showing(activePvPIndex) then
		local seconds = GetBattlefieldPortExpiration(activePvPIndex)
		if seconds and seconds > 0 then
			WarnOnExpiration(seconds)
			QueueTimer:UpdateDisplay(seconds, dialog, true)
		else
			activePvPIndex = nil
			hasWarned = false
		end
	end
end

local function OnUpdate(_, elapsed)
	sinceLastUpdate = sinceLastUpdate + elapsed
	if sinceLastUpdate < UPDATE_INTERVAL then return end
	sinceLastUpdate = 0

	if remainingPvETime and remainingPvETime > 0 then
		remainingPvETime = remainingPvETime - UPDATE_INTERVAL
		UpdatePvE()
	end
	UpdatePvP()
end

local function StartTicker()
	if not updateFrame then
		updateFrame = CreateFrame("Frame")
		updateFrame:SetScript("OnUpdate", OnUpdate)
	end
	updateFrame:Show()
end

local function StopTicker()
	if updateFrame then
		updateFrame:Hide()
	end
	hasWarned = false
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
function QueueTimer:LFG_PROPOSAL_SHOW()
	remainingPvETime = PVE_EXPIRE_BASE
	RecalculateRemainingPvE()
	self:UpdateDisplay(remainingPvETime, _G.LFGDungeonReadyDialog)
	SavePvEPopTime()
	hasWarned = false
	StartTicker()
	HideDefaultQueueTimers()
end

function QueueTimer:LFG_PROPOSAL_ENDED()
	StopTicker()
	ClearPvEPopTime()
end

function QueueTimer:UPDATE_BATTLEFIELD_STATUS(index)
	if GetBattlefieldStatus(index) == "confirm" then
		activePvPIndex = index
		self:UpdateDisplay(GetBattlefieldPortExpiration(index) or 0, _G.PVPReadyDialog, true)
		hasWarned = false
		StartTicker()
	elseif not remainingPvETime or remainingPvETime <= 0 then
		activePvPIndex = nil
		StopTicker()
	end
end

function QueueTimer:RegisterModuleEvents()
	if self.eventsRegistered then return end
	self.eventsRegistered = true

	self:RegisterEvent("LFG_PROPOSAL_SHOW")
	self:RegisterEvent("LFG_PROPOSAL_SUCCEEDED", "LFG_PROPOSAL_ENDED")
	self:RegisterEvent("LFG_PROPOSAL_DONE", "LFG_PROPOSAL_ENDED")
	self:RegisterEvent("LFG_PROPOSAL_FAILED", "LFG_PROPOSAL_ENDED")
	self:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")

	if _G.PVPReadyDialog_Display then
		hooksecurefunc("PVPReadyDialog_Display", function(_, index)
			activePvPIndex = index
			self:UpdateDisplay(GetBattlefieldPortExpiration(index) or 0, _G.PVPReadyDialog, true)
			hasWarned = false
			StartTicker()
		end)
	end
end

function QueueTimer:OnEnable()
	if not db().enable then return end
	self:RegisterModuleEvents()
end

function QueueTimer:OnSettingChanged(key, value)
	if key == "enable" and value then
		self:RegisterModuleEvents()
	end
end

function QueueTimer:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Queue Timer"], L["Replace the small LFG/PvP ready countdown with a larger, colour-coded timer (reload to disable)."])
	local _, warnInit = builder:Checkbox(category, self, "warning", L["Queue Warning Sound"], L["Play a triple beep when the queue is about to expire."])
	local _, hideInit = builder:Checkbox(category, self, "hideOtherTimers", L["Hide Default Timers"], L["Hide Blizzard's default queue status bars while the custom timer is shown."])

	builder:DependsOn(warnInit, enableInit)
	builder:DependsOn(hideInit, enableInit)
end
