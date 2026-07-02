--[[
	NexEnhance - Quest Notification
	-------------------------------------------------------------------------
	Announces quest activity to your group: quests you accept, objective
	progress, and completions (with a completion sound). Useful so the party
	knows when everyone is ready to turn in.

	Ported from NDui's Modules/Misc/QuestNotification.lua (by siweia), adapted
	to the NexEnhance framework. Subscriptions toggle live (no reload).

	Progress detection diverges from the NDui port on purpose: instead of building
	locale regexes from ERR_QUEST_ADD_* and pattern-matching the UI_INFO_MESSAGE
	text (brittle, locale-fragile, and a possibly-secret string in Midnight), we
	diff structured objective counts from C_QuestLog.GetQuestObjectives off the
	debounced QUEST_LOG_UPDATE scan. That event is the only one that fires for
	every quest-log change regardless of tracking state -- QUEST_WATCH_UPDATE and
	QUEST_LOG_CRITERIA_UPDATE both quietly skip untracked/non-criteria objectives.
	Locale-independent, no string parsing, and it actually fires. You're welcome.
--]]

-- The Lua Language Server types quest IDs as optional; silence those false positives.
---@diagnostic disable: param-type-mismatch, need-check-nil
local _, ns = ...
local F, L = ns.F, ns.L

local format, floor, mod, wipe = string.format, math.floor, mod, wipe
local IsPartyLFG, IsInRaid, IsInGroup = IsPartyLFG, IsInRaid, IsInGroup
local PlaySound, GetQuestLink = PlaySound, GetQuestLink
local GetQuestProgressBarPercent = GetQuestProgressBarPercent
local C_PartyInfo = C_PartyInfo
-- C_ChatInfo.SendChatMessage is the live API; the global SendChatMessage is now
-- a deprecated shim that forwards to it (Blizzard_DeprecatedChatInfo).
local SendChatMessage = C_ChatInfo.SendChatMessage
local C_QuestLog_GetInfo = C_QuestLog.GetInfo
local C_QuestLog_IsComplete = C_QuestLog.IsComplete
local C_QuestLog_IsWorldQuest = C_QuestLog.IsWorldQuest
local C_QuestLog_GetQuestObjectives = C_QuestLog.GetQuestObjectives
local C_QuestLog_GetQuestTagInfo = C_QuestLog.GetQuestTagInfo
local C_QuestLog_GetTitleForQuestID = C_QuestLog.GetTitleForQuestID
local C_QuestLog_GetQuestIDForLogIndex = C_QuestLog.GetQuestIDForLogIndex
local C_QuestLog_GetNumQuestLogEntries = C_QuestLog.GetNumQuestLogEntries
local C_QuestLog_GetLogIndexForQuestID = C_QuestLog.GetLogIndexForQuestID
local soundKitID = SOUNDKIT.ALARM_CLOCK_WARNING_3
local DAILY, QUEST_COMPLETE = DAILY, QUEST_COMPLETE
local LE_QUEST_TAG_TYPE_PROFESSION = Enum.QuestTagType.Profession
local LE_QUEST_FREQUENCY_DAILY = Enum.QuestFrequency.Daily

ns:RegisterDefaults({
	questNotification = {
		enable = false,
		progress = true,
		onlyCompleteRing = false,
	},
})

local QuestNotification = ns:NewModule("QuestNotification", "questNotification", { group = "announcements", title = L["Quest Notification"], order = 10 })

local function db()
	return ns.db.questNotification
end

local completedQuest, initComplete = {}, nil

-- ---------------------------------------------------------------------------
-- Message helpers
-- ---------------------------------------------------------------------------
local function GetQuestLinkOrName(questID)
	return GetQuestLink(questID) or C_QuestLog_GetTitleForQuestID(questID) or ""
end

local function acceptText(questID, daily)
	local title = GetQuestLinkOrName(questID)
	if daily then
		return format("%s [%s]%s", L["Accepted"], DAILY, title)
	else
		return format("%s %s", L["Accepted"], title)
	end
end

local function completeText(questID)
	PlaySound(soundKitID, "Master")
	return format("%s %s", GetQuestLinkOrName(questID), QUEST_COMPLETE)
end

-- True only when there's somewhere to announce to. Solo, every handler below is
-- pointless work, so we bail on this early rather than scanning objectives for a
-- message that sendQuestMsg would just drop on the floor.
local function inAnnounceableGroup()
	return IsPartyLFG() or (C_PartyInfo and C_PartyInfo.IsPartyWalkIn and C_PartyInfo.IsPartyWalkIn()) or IsInRaid() or IsInGroup()
end

local function sendQuestMsg(msg)
	if db().onlyCompleteRing then
		return
	end

	-- Debug/self-test: route to your own chat and skip the group requirement, so
	-- you can actually watch the thing work while questing solo. Toggle with
	-- /nex questnotify. Never on by default.
	if QuestNotification.debug then
		F.Print(msg)
		return
	end

	if IsPartyLFG() or (C_PartyInfo and C_PartyInfo.IsPartyWalkIn and C_PartyInfo.IsPartyWalkIn()) then
		SendChatMessage(msg, "INSTANCE_CHAT")
	elseif IsInRaid() then
		SendChatMessage(msg, "RAID")
	elseif IsInGroup() then
		SendChatMessage(msg, "PARTY")
	end
end

-- ---------------------------------------------------------------------------
-- Event handlers (signatures match ns:RegisterEvent -> (event, ...))
-- ---------------------------------------------------------------------------
-- Last seen fulfilled-count (or 20% bucket, for progress bars) per objective, so
-- we only post on an actual change and can throttle noisy high-count objectives.
-- Keyed questID*100+index since a quest never has anywhere near 100 objectives.
-- The first time we see an objective we record it *silently* (prev == nil), so a
-- fresh login, a /reload, or toggling the feature on never dumps progress the
-- player already made -- only changes we actually witness get announced. Cleared
-- on completion / turn-in / disable so it stays bounded to your active quests.
local objectiveProgress = {}

local function clearQuestProgress(questID)
	for index = 1, 20 do
		objectiveProgress[questID * 100 + index] = nil
	end
end

-- Walk one quest's objectives and announce any that advanced since the last scan.
-- `announce` is false while solo (and on the very first sighting via the prev==nil
-- guard below), in which case we just record counts without saying anything.
local function ScanQuestProgress(questID, announce)
	local objectives = C_QuestLog_GetQuestObjectives(questID)
	if not objectives then
		return
	end

	for index = 1, #objectives do
		local o = objectives[index]
		-- Midnight: GetQuestObjectives fields can be secret in instances. We can't
		-- read, compare, mod, or broadcast a secret, so skip the objective entirely
		-- rather than fight taint. Out in the world they're plain numbers/strings.
		if o and F.NotSecret(o.finished) and not o.finished then
			local key = questID * 100 + index
			if F.NotSecret(o.type) and o.type == "progressbar" then
				-- Percent-style objective ("73% complete"). The count fields read 0
				-- here; the real value lives behind GetQuestProgressBarPercent (which
				-- can also be a secret in instances, so guard it the same way).
				local pct = GetQuestProgressBarPercent and GetQuestProgressBarPercent(questID)
				if F.NotSecret(pct) and pct and pct > 0 then
					local step = floor(pct / 20) -- one chime per 20%, not per point
					local prev = objectiveProgress[key]
					if prev ~= step then
						objectiveProgress[key] = step
						if announce and prev ~= nil then
							sendQuestMsg(format("%s: %d%%", GetQuestLinkOrName(questID), floor(pct)))
						end
					end
				end
			elseif F.NotSecret(o.numFulfilled) and F.NotSecret(o.numRequired) and F.NotSecret(o.text) then
				local cur, req = o.numFulfilled, o.numRequired
				local prev = objectiveProgress[key]
				if cur and prev ~= cur then
					objectiveProgress[key] = cur
					-- prev == nil means this is the seeding pass: record, stay quiet.
					if announce and prev ~= nil and cur > 0 then
						-- Chatty objectives (req >= 10) only ping every ~20% so we
						-- don't carpet-bomb the party with 1/50, 2/50, 3/50...
						local ok = true
						if req and req >= 10 then
							ok = mod(cur, floor(req / 5)) == 0
						end
						if ok then
							sendQuestMsg(format("%s: %s", GetQuestLinkOrName(questID), o.text))
						end
					end
				end
			end
		end
	end
end

local WQcache = {}
local function FindQuestAccept(_, questID)
	if not questID then
		return
	end
	if not (QuestNotification.debug or inAnnounceableGroup()) then
		return
	end
	if C_QuestLog_IsWorldQuest(questID) and WQcache[questID] then
		return
	end
	WQcache[questID] = true

	local tagInfo = C_QuestLog_GetQuestTagInfo(questID)
	if tagInfo and tagInfo.worldQuestType == LE_QUEST_TAG_TYPE_PROFESSION then
		return
	end

	local questLogIndex = C_QuestLog_GetLogIndexForQuestID(questID)
	if questLogIndex then
		local info = C_QuestLog_GetInfo(questLogIndex)
		if info then
			sendQuestMsg(acceptText(questID, info.frequency == LE_QUEST_FREQUENCY_DAILY))
		end
	end
end

-- One pass over the quest log, driving both completion and objective progress.
-- QUEST_LOG_UPDATE is the only signal that reliably fires for *every* quest-log
-- change regardless of whether the quest is watched/tracked -- QUEST_WATCH_UPDATE
-- and QUEST_LOG_CRITERIA_UPDATE both miss untracked or non-criteria objectives,
-- which is why progress used to silently do nothing. So we diff structured
-- objective counts here instead.
local function ScanQuestLog()
	-- Progress only matters when there's a group to tell. Completion seeding still
	-- has to run regardless, so we gate progress separately from the loop itself.
	local announceProgress = db().progress and not db().onlyCompleteRing and (QuestNotification.debug or inAnnounceableGroup())

	for i = 1, C_QuestLog_GetNumQuestLogEntries() do
		local questID = C_QuestLog_GetQuestIDForLogIndex(i)
		if questID and not C_QuestLog_IsWorldQuest(questID) then
			if C_QuestLog_IsComplete(questID) then
				if not completedQuest[questID] then
					if initComplete then
						sendQuestMsg(completeText(questID))
					end
					completedQuest[questID] = true
					clearQuestProgress(questID)
				end
			elseif db().progress then
				-- Always scan (even solo) so counts stay seeded; ScanQuestProgress
				-- itself decides whether to actually open its mouth.
				ScanQuestProgress(questID, announceProgress)
			end
		end
	end
	initComplete = true
end

-- QUEST_LOG_UPDATE storms (it can fire many times per second during quest/log
-- churn). Coalesce the full-log scan so we only walk the quest log once the
-- burst settles, per the event-throttling guidance in the research reports.
local ScanQuestLogThrottled = F.Debounce(0.2, ScanQuestLog)

local function FindWorldQuestComplete(_, questID)
	if questID and C_QuestLog_IsWorldQuest(questID) then
		if not completedQuest[questID] then
			sendQuestMsg(completeText(questID))
			completedQuest[questID] = true
		end
	end
	if questID then
		clearQuestProgress(questID)
	end
end

-- ---------------------------------------------------------------------------
-- Subscription management
-- ---------------------------------------------------------------------------
local subscriptions = {
	{ "QUEST_ACCEPTED", FindQuestAccept },
	{ "QUEST_LOG_UPDATE", ScanQuestLogThrottled },
	{ "QUEST_TURNED_IN", FindWorldQuestComplete },
}

function QuestNotification:Update()
	-- Debug mode is reason enough to keep the events live, so the /nex questnotify
	-- self-test works even when the module is otherwise disabled.
	if db().enable or self.debug then
		if not self.registered then
			for i = 1, #subscriptions do
				ns:RegisterEvent(subscriptions[i][1], subscriptions[i][2])
			end
			self.registered = true
		end
	elseif self.registered then
		wipe(completedQuest)
		wipe(objectiveProgress)
		-- Reset the seed flag too, so a later re-enable rebuilds the
		-- completed-quest set silently instead of announcing everything.
		initComplete = nil
		for i = 1, #subscriptions do
			ns:UnregisterEvent(subscriptions[i][1], subscriptions[i][2])
		end
		self.registered = nil
	end
end

-- Flip the self-test on/off (wired to /nex questnotify). When turning it on we
-- print a snapshot of your current incomplete objectives so you get instant
-- confirmation it's hooked up, instead of standing around waiting for a kill.
function QuestNotification:ToggleDebug()
	self.debug = not self.debug or nil
	self:Update()

	if self.debug then
		F.Print(L["Quest Notification debug ON - messages will print here."])
		for i = 1, C_QuestLog_GetNumQuestLogEntries() do
			local questID = C_QuestLog_GetQuestIDForLogIndex(i)
			if questID and not C_QuestLog_IsWorldQuest(questID) and not C_QuestLog_IsComplete(questID) then
				-- Seed counts now (announce = false) so your very next kill prints
				-- instead of being eaten by the silent first-sighting rule.
				ScanQuestProgress(questID, false)
				local objectives = C_QuestLog_GetQuestObjectives(questID)
				if objectives then
					for index = 1, #objectives do
						local o = objectives[index]
						if o and F.NotSecret(o.finished) and not o.finished and F.NotSecret(o.text) then
							F.Print(format("%s: %s", GetQuestLinkOrName(questID), o.text))
						end
					end
				end
			end
		end
	else
		F.Print(L["Quest Notification debug OFF."])
	end
end

function QuestNotification:OnEnable()
	self:Update()
end

function QuestNotification:OnDisable()
	if self.registered then
		wipe(completedQuest)
		wipe(objectiveProgress)
		initComplete = nil
		for i = 1, #subscriptions do
			ns:UnregisterEvent(subscriptions[i][1], subscriptions[i][2])
		end
		self.registered = nil
	end
end

function QuestNotification:OnSettingChanged()
	self:Update()
end

function QuestNotification:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Quest Notification"], L["Announce accepted quests and completions to your group."])
	local _, progressInit = builder:Checkbox(category, self, "progress", L["Quest Progress"], L["Also announce objective progress updates."])
	local _, ringInit = builder:Checkbox(category, self, "onlyCompleteRing", L["Only Completion Sound"], L["Play a sound on quest completion but do not post any chat messages."])

	builder:DependsOn(progressInit, enableInit)
	builder:DependsOn(ringInit, enableInit)
end

ns.Debug.RegisterScope("questnotify", {
	title = L["Quest Notification"],
	module = QuestNotification,
	dump = function()
		F.Print(format("  self-test debug: %s", QuestNotification.debug and "ON" or "OFF"))
		F.Print(format("  module enabled: %s", QuestNotification:IsEnabled() and "yes" or "no"))
	end,
})
