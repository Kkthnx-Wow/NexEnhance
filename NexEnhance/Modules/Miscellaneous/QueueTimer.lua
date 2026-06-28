--[[
	NexEnhance - Queue Timer
	-------------------------------------------------------------------------
	Replaces the small default LFG / PvP "ready" countdown with a larger, more
	visible timer (colour-coded as it runs down) plus an optional triple-beep
	warning as the queue is about to expire. The PvE pop time is persisted
	per-character so the countdown survives a /reload mid-popup.

	Blizzard (12.0.7) shows LFGDungeonReadyPopup / PVPReadyDialog via
	StaticPopupSpecial_Show but does not render a countdown in FrameXML; PvP
	expiration comes from GetBattlefieldPortExpiration. LFG still has no
	expiration API — ~40s is measured client-side (same pattern as LFG
	ProposalTime and other community addons).

	Ported from KkthnxUI's QueueTimer (by Josh "Kkthnx" Russell), adapted to
   the NexEnhance framework:
	  https://github.com/Kkthnx-Wow/KkthnxUI
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local F, L = ns.F, ns.L

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
local GetLFGProposal = GetLFGProposal
local GetMaxBattlefieldID = GetMaxBattlefieldID

-- Tunables.
local WARNING_SOUND_ID = 567458 -- the "you're about to lose your queue" beep
local WARNING_THRESHOLD = 6 -- seconds left when the beep + red kicks in
local PVE_EXPIRE_BASE = 40 -- LFG pops give ~40s to accept; no API hands us this
local UPDATE_INTERVAL = 0.2 -- 5fps is plenty for a whole-second countdown

ns:RegisterDefaults({
	queueTimer = {
		enable = true,
		warning = true,
		hideOtherTimers = true,
	},
})

local QueueTimer = ns:NewModule("QueueTimer", "queueTimer", { group = "alerts", title = L["Queue Timer"], order = 30 })

-- State.
local remainingPvETime = 0
local activePvPIndex
local updateFrame
local hasWarned = false
local sinceLastUpdate = 0

local function db()
	return ns.db.queueTimer
end

function QueueTimer:IsActive()
	return db().enable and self.eventsRegistered
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
	if not db().hideOtherTimers then
		return
	end

	-- Legacy: older clients attached StatusBar children to LFGDungeonReadyPopup.
	-- 12.0.7 FrameXML has no default LFG countdown bar; this is harmless if absent.
	local popup = _G.LFGDungeonReadyPopup
	if not popup then
		return
	end

	for _, child in ipairs({ popup:GetChildren() }) do
		if child.GetObjectType and child:GetObjectType() == "StatusBar" then
			child:Hide()
		end
	end
end

local function CreateLabels(dialog)
	if not dialog or not dialog.label or dialog.nexQueueLabels then
		return
	end

	local width = dialog:GetWidth()

	dialog.nexHeader = F.CreatePlainFS(dialog, 15, L["Queue expires in"])
	dialog.nexHeader:SetPoint("TOP", dialog.label, "TOP", 0, 0)
	dialog.nexHeader:SetWidth(width)

	dialog.nexTimer = F.CreatePlainFS(dialog, 24)
	dialog.nexTimer:SetPoint("TOP", dialog.nexHeader, "BOTTOM", 0, -5)
	dialog.nexTimer:SetWidth(width)

	dialog.nexName = F.CreatePlainFS(dialog, 15)
	dialog.nexName:SetPoint("TOP", dialog.nexTimer, "BOTTOM", 0, -4)
	dialog.nexName:SetWidth(width)

	dialog.nexStatus = F.CreatePlainFS(dialog, 11)
	dialog.nexStatus:SetPoint("TOP", dialog.nexName, "BOTTOM", 0, -3)
	dialog.nexStatus:SetWidth(width)

	dialog.nexQueueLabels = true
end

local function ExpiresText(seconds)
	local remain = (seconds and seconds > 0) and seconds or 1
	local hex = (remain > 20) and "20ff20" or (remain > 10) and "ffff00" or "ff0000"
	return format("|cff%s%s|r", hex, SecondsToTime(remain))
end

function QueueTimer:UpdateDisplay(timeRemaining, dialog, isPvP)
	if not dialog then
		return
	end
	CreateLabels(dialog)

	local remain = timeRemaining or 0
	if dialog.label then
		dialog.label:SetText("")
	end
	if dialog.instanceInfo and dialog.instanceInfo.SetAlpha then
		dialog.instanceInfo:SetAlpha(0)
	end

	if dialog.nexTimer then
		F.SetPlainText(dialog.nexTimer, ExpiresText(remain))
	end

	local info = dialog.instanceInfo
	if dialog.nexName and dialog.nexStatus and info and info.name and (info:IsShown() or isPvP) then
		F.SetPlainText(dialog.nexName, info.name:GetText() or "")
		F.SetPlainText(dialog.nexStatus, info.statusText and info.statusText:GetText() or "")
	else
		if dialog.nexName then
			F.SetPlainText(dialog.nexName, "")
		end
		if dialog.nexStatus then
			F.SetPlainText(dialog.nexStatus, "")
		end
	end
end

local function RefreshPvEDisplay()
	if not remainingPvETime or remainingPvETime <= 0 then
		return
	end
	local dialog = _G.LFGDungeonReadyDialog
	if dialog and dialog:IsShown() then
		QueueTimer:UpdateDisplay(remainingPvETime, dialog)
		HideDefaultQueueTimers()
	end
end

-- ---------------------------------------------------------------------------
-- Warning sound
-- ---------------------------------------------------------------------------
local function WarnOnExpiration(seconds)
	if not db().warning then
		return
	end
	if seconds <= WARNING_THRESHOLD and not hasWarned then
		PlaySoundFile(WARNING_SOUND_ID, "master")
		C_Timer_After(0.1, function()
			PlaySoundFile(WARNING_SOUND_ID, "master")
		end)
		C_Timer_After(0.2, function()
			PlaySoundFile(WARNING_SOUND_ID, "master")
		end)
		hasWarned = true
	end
end

-- ---------------------------------------------------------------------------
-- Ticker
-- ---------------------------------------------------------------------------
local function OnUpdate(_, elapsed)
	sinceLastUpdate = sinceLastUpdate + elapsed
	if sinceLastUpdate < UPDATE_INTERVAL then
		return
	end
	sinceLastUpdate = 0

	if remainingPvETime and remainingPvETime > 0 then
		remainingPvETime = remainingPvETime - UPDATE_INTERVAL
		local dialog = _G.LFGDungeonReadyDialog
		if dialog and dialog:IsShown() then
			local seconds = max(remainingPvETime, 0)
			WarnOnExpiration(seconds)
			QueueTimer:UpdateDisplay(seconds, dialog)
		end
	end

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

local function StartTicker()
	if not updateFrame then
		updateFrame = CreateFrame("Frame")
	end
	updateFrame:SetScript("OnUpdate", OnUpdate)
	updateFrame:Show()
end

local function StopTicker()
	if updateFrame then
		updateFrame:SetScript("OnUpdate", nil)
		updateFrame:Hide()
	end
	hasWarned = false
end

local function SyncActivePvE()
	local proposalExists = GetLFGProposal()
	local popup = _G.LFGDungeonReadyPopup

	if not proposalExists or not popup or not popup:IsShown() then
		if remainingPvETime > 0 then
			remainingPvETime = 0
			StopTicker()
			ClearPvEPopTime()
		end
		return
	end

	RecalculateRemainingPvE()
	if remainingPvETime > 0 then
		RefreshPvEDisplay()
		StartTicker()
	end
end

local function SyncActivePvP()
	for i = 1, GetMaxBattlefieldID() do
		if GetBattlefieldStatus(i) == "confirm" then
			activePvPIndex = i
			QueueTimer:UpdateDisplay(GetBattlefieldPortExpiration(i) or 0, _G.PVPReadyDialog, true)
			hasWarned = false
			StartTicker()
			return
		end
	end
	activePvPIndex = nil
	if remainingPvETime <= 0 then
		StopTicker()
	end
end

local function BootstrapActiveQueues()
	if not QueueTimer:IsActive() then
		return
	end
	SyncActivePvE()
	SyncActivePvP()
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
function QueueTimer:LFG_PROPOSAL_SHOW()
	remainingPvETime = PVE_EXPIRE_BASE
	RecalculateRemainingPvE()
	SavePvEPopTime()
	hasWarned = false
	StartTicker()
	-- Dialog content is filled in LFGDungeonReadyPopup_Update (OnShow / PROPOSAL_UPDATE).
	C_Timer_After(0, RefreshPvEDisplay)
end

function QueueTimer:LFG_PROPOSAL_UPDATE()
	if not GetLFGProposal() then
		self:LFG_PROPOSAL_ENDED()
		return
	end
	RefreshPvEDisplay()
end

function QueueTimer:LFG_PROPOSAL_ENDED()
	remainingPvETime = 0
	StopTicker()
	ClearPvEPopTime()
end

function QueueTimer:UPDATE_BATTLEFIELD_STATUS(index)
	local status = GetBattlefieldStatus(index)
	if status == "confirm" then
		activePvPIndex = index
		self:UpdateDisplay(GetBattlefieldPortExpiration(index) or 0, _G.PVPReadyDialog, true)
		hasWarned = false
		StartTicker()
	elseif activePvPIndex == index then
		activePvPIndex = nil
		hasWarned = false
		if remainingPvETime <= 0 then
			StopTicker()
		end
	end
end

function QueueTimer:RegisterModuleEvents()
	if self.eventsRegistered then
		return
	end
	self.eventsRegistered = true

	self._evtProposalShow = self:RegisterEvent("LFG_PROPOSAL_SHOW")
	self._evtProposalUpdate = self:RegisterEvent("LFG_PROPOSAL_UPDATE")
	self._evtProposalSucceeded = self:RegisterEvent("LFG_PROPOSAL_SUCCEEDED", "LFG_PROPOSAL_ENDED")
	self._evtProposalDone = self:RegisterEvent("LFG_PROPOSAL_DONE", "LFG_PROPOSAL_ENDED")
	self._evtProposalFailed = self:RegisterEvent("LFG_PROPOSAL_FAILED", "LFG_PROPOSAL_ENDED")
	self._evtBattlefieldStatus = self:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")

	if not self._hooksInstalled then
		self._hooksInstalled = true

		if _G.LFGDungeonReadyPopup_Update then
			hooksecurefunc("LFGDungeonReadyPopup_Update", function()
				if QueueTimer:IsActive() and remainingPvETime > 0 then
					RefreshPvEDisplay()
				end
			end)
		end

		if _G.PVPReadyDialog_Display then
			hooksecurefunc("PVPReadyDialog_Display", function(_, index)
				if not QueueTimer:IsActive() then
					return
				end
				activePvPIndex = index
				QueueTimer:UpdateDisplay(GetBattlefieldPortExpiration(index) or 0, _G.PVPReadyDialog, true)
				hasWarned = false
				StartTicker()
			end)
		end
	end

	C_Timer_After(0, BootstrapActiveQueues)
end

function QueueTimer:UnregisterModuleEvents()
	if not self.eventsRegistered then
		return
	end
	self.eventsRegistered = false

	ns:UnregisterEvent("LFG_PROPOSAL_SHOW", self._evtProposalShow)
	ns:UnregisterEvent("LFG_PROPOSAL_UPDATE", self._evtProposalUpdate)
	ns:UnregisterEvent("LFG_PROPOSAL_SUCCEEDED", self._evtProposalSucceeded)
	ns:UnregisterEvent("LFG_PROPOSAL_DONE", self._evtProposalDone)
	ns:UnregisterEvent("LFG_PROPOSAL_FAILED", self._evtProposalFailed)
	ns:UnregisterEvent("UPDATE_BATTLEFIELD_STATUS", self._evtBattlefieldStatus)

	self._evtProposalShow = nil
	self._evtProposalUpdate = nil
	self._evtProposalSucceeded = nil
	self._evtProposalDone = nil
	self._evtProposalFailed = nil
	self._evtBattlefieldStatus = nil

	remainingPvETime = 0
	activePvPIndex = nil
	StopTicker()
end

function QueueTimer:OnEnable()
	if not db().enable then
		return
	end
	self:RegisterModuleEvents()
end

function QueueTimer:OnSettingChanged(key, value)
	if key == "enable" then
		if value then
			self:RegisterModuleEvents()
		else
			self:UnregisterModuleEvents()
		end
	end
end

function QueueTimer:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Queue Timer"], L["Replace the small LFG/PvP ready countdown with a larger, colour-coded timer (reload to disable)."])
	local _, warnInit = builder:Checkbox(category, self, "warning", L["Queue Warning Sound"], L["Play a triple beep when the queue is about to expire."])
	local _, hideInit = builder:Checkbox(category, self, "hideOtherTimers", L["Hide Default Timers"], L["Hide legacy LFG queue status bars on the ready popup, if any (12.0.7 has no default countdown)."])

	builder:DependsOn(warnInit, enableInit)
	builder:DependsOn(hideInit, enableInit)
end
