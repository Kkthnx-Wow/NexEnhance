--[[
	NexEnhance - Quest Notification
	-------------------------------------------------------------------------
	Announces quest activity to your group: quests you accept, objective
	progress, and completions (with a completion sound). Useful so the party
	knows when everyone is ready to turn in.

	Progress detection: we diff structured objective counts from
	C_QuestLog.GetQuestObjectives off a debounced QUEST_LOG_UPDATE scan instead
	of pattern-matching localized UI_INFO_MESSAGE text. Locale-independent, no
	string parsing, fires for every quest regardless of tracking — and the text
	can be a Secret value in instances anyway.
--]]

-- The Lua Language Server types quest IDs as optional; silence those false positives.
---@diagnostic disable: param-type-mismatch, need-check-nil
local _, ns = ...
local F, L = ns.F, ns.L

local format, floor, mod, wipe, tinsert = string.format, math.floor, mod, wipe, table.insert
local IsPartyLFG, IsInRaid, IsInGroup = IsPartyLFG, IsInRaid, IsInGroup
local GetTime = GetTime
local C_Timer = C_Timer
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
local LE_QUEST_CLASSIFICATION_WORLD_QUEST = Enum.QuestClassification.WorldQuest
local WORLD_QUEST = _G.WORLD_QUEST
local C_QuestInfoSystem_GetQuestClassification = C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification

local QuestNotification = ns:NewModule("QuestNotification", "questNotification", { group = "announcements", title = L["Quest Notification"], order = 10 })

local function db()
	return ns.db.questNotification
end

-- Map-popup world quests: C_QuestLog.IsWorldQuest, tag worldQuestType, or
-- QuestClassification.WorldQuest (see QuestUtils IsQuestWorldQuest_Internal).
-- Do NOT use IsQuestTask + timer — that catches weeklies, zone events, and campaign tasks.
local function IsWorldQuestLike(questID)
	if not questID then
		return false
	end
	if C_QuestLog_IsWorldQuest(questID) then
		return true
	end
	local tagInfo = C_QuestLog_GetQuestTagInfo(questID)
	if tagInfo and tagInfo.worldQuestType ~= nil then
		return true
	end
	if C_QuestInfoSystem_GetQuestClassification then
		local class = C_QuestInfoSystem_GetQuestClassification(questID)
		if F.NotSecret(class) and class == LE_QUEST_CLASSIFICATION_WORLD_QUEST then
			return true
		end
	end
	local logIndex = C_QuestLog_GetLogIndexForQuestID(questID)
	if logIndex then
		local info = C_QuestLog_GetInfo(logIndex)
		if info and F.NotSecret(info.questClassification) and info.questClassification == LE_QUEST_CLASSIFICATION_WORLD_QUEST then
			return true
		end
	end
	return false
end

-- Profession world quests (crafting orders) stay silent — too noisy even when WQ
-- announcements are enabled.
local function IsProfessionWorldQuest(questID)
	local tagInfo = C_QuestLog_GetQuestTagInfo(questID)
	return tagInfo and tagInfo.worldQuestType == LE_QUEST_TAG_TYPE_PROFESSION
end

-- Gate accepts, progress, and completions. World quests require the opt-in toggle.
local function IsHiddenLogQuest(questID)
	local logIndex = C_QuestLog_GetLogIndexForQuestID(questID)
	if not logIndex then
		return false
	end
	local info = C_QuestLog_GetInfo(logIndex)
	if not info then
		return false
	end
	if info.isHeader then
		return true
	end
	if info.isHidden then
		return true
	end
	if F.NotSecret(info.isInternalOnly) and info.isInternalOnly then
		return true
	end
	return false
end

local function HasObjectiveText(o)
	return o and F.NotSecret(o.text) and o.text ~= "" and o.text:match("%S") ~= nil
end

local function ShouldAnnounceQuest(questID)
	if not questID then
		return false
	end
	if IsHiddenLogQuest(questID) then
		return false
	end
	if IsProfessionWorldQuest(questID) then
		return false
	end
	if IsWorldQuestLike(questID) and not db().worldQuests then
		return false
	end
	return true
end

ns:RegisterDefaults({
	questNotification = {
		enable = false,
		progress = true,
		onlyCompleteRing = false,
		batchAnnouncements = true,
		worldQuests = false,
	},
})

local completedQuest, initComplete = {}, nil
local acceptQueue, acceptAnnounced, acceptFlushTimer = {}, {}, nil
local completeQueue, completeFlushTimer = {}, nil
local ACCEPT_BATCH_DELAY, ACCEPT_DEDUP_SEC = 0.75, 10
local CHAT_SAFE_LEN = 240

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
-- Message helpers
-- ---------------------------------------------------------------------------
local function GetQuestLinkOrName(questID)
	return GetQuestLink(questID) or C_QuestLog_GetTitleForQuestID(questID) or ""
end

local function acceptText(questID, daily, worldQuest)
	local title = GetQuestLinkOrName(questID)
	if worldQuest then
		local tag = WORLD_QUEST or L["World Quest"]
		return format("%s [%s]%s", L["Accepted"], tag, title)
	end
	if daily then
		return format("%s [%s]%s", L["Accepted"], DAILY, title)
	end
	return format("%s %s", L["Accepted"], title)
end

local function acceptBatchText(entries)
	if #entries == 1 then
		return acceptText(entries[1].questID, entries[1].daily, entries[1].worldQuest)
	end

	local prefix = format(L["Accepted (%d):"], #entries)
	local parts, hidden = {}, 0
	for i = 1, #entries do
		local title = GetQuestLinkOrName(entries[i].questID)
		local trial = prefix .. " " .. table.concat(parts, ", ") .. (#parts > 0 and ", " or "") .. title
		if #trial > CHAT_SAFE_LEN and #parts > 0 then
			hidden = #entries - #parts
			break
		end
		tinsert(parts, title)
	end
	if hidden > 0 then
		return format("%s %s %s", prefix, table.concat(parts, ", "), format(L["and %d more"], hidden))
	end
	return format("%s %s", prefix, table.concat(parts, ", "))
end

local function completeText(questID, playSound)
	if playSound ~= false then
		PlaySound(soundKitID, "Master")
	end
	return format("%s %s", GetQuestLinkOrName(questID), QUEST_COMPLETE)
end

local function completeBatchText(questIDs)
	PlaySound(soundKitID, "Master")
	if #questIDs == 1 then
		return completeText(questIDs[1], false)
	end
	local prefix = format(L["Completed (%d):"], #questIDs)
	local parts, hidden = {}, 0
	for i = 1, #questIDs do
		local title = GetQuestLinkOrName(questIDs[i])
		local trial = prefix .. " " .. table.concat(parts, ", ") .. (#parts > 0 and ", " or "") .. title
		if #trial > CHAT_SAFE_LEN and #parts > 0 then
			hidden = #questIDs - #parts
			break
		end
		tinsert(parts, title)
	end
	if hidden > 0 then
		return format("%s %s %s", prefix, table.concat(parts, ", "), format(L["and %d more"], hidden))
	end
	return format("%s %s", prefix, table.concat(parts, ", "))
end

-- Progress cache (declared before completion queue — QueueQuestComplete clears it).
local objectiveProgress = {}

local function clearQuestProgress(questID)
	for index = 1, 20 do
		objectiveProgress[questID * 100 + index] = nil
	end
end

local function ClearAcceptQueue()
	if acceptFlushTimer then
		acceptFlushTimer:Cancel()
		acceptFlushTimer = nil
	end
	wipe(acceptQueue)
end

local function ClearCompleteQueue()
	if completeFlushTimer then
		completeFlushTimer:Cancel()
		completeFlushTimer = nil
	end
	wipe(completeQueue)
end

local function FlushCompleteQueue()
	completeFlushTimer = nil
	if #completeQueue == 0 then
		return
	end
	local ids = {}
	for i = 1, #completeQueue do
		ids[i] = completeQueue[i]
	end
	wipe(completeQueue)
	if db().batchAnnouncements and #ids > 1 then
		sendQuestMsg(completeBatchText(ids))
	else
		for i = 1, #ids do
			sendQuestMsg(completeText(ids[i]))
		end
	end
end

local function QueueQuestComplete(questID)
	if completedQuest[questID] then
		return
	end
	completedQuest[questID] = true
	clearQuestProgress(questID)

	if not initComplete or not ShouldAnnounceQuest(questID) then
		return
	end

	if not db().batchAnnouncements then
		sendQuestMsg(completeText(questID))
		return
	end

	tinsert(completeQueue, questID)
	if completeFlushTimer then
		completeFlushTimer:Cancel()
	end
	completeFlushTimer = C_Timer.NewTimer(ACCEPT_BATCH_DELAY, FlushCompleteQueue)
end

local function FlushAcceptQueue()
	acceptFlushTimer = nil
	if #acceptQueue == 0 then
		return
	end
	local now = GetTime()
	local entries = {}
	for i = 1, #acceptQueue do
		local e = acceptQueue[i]
		tinsert(entries, e)
		acceptAnnounced[e.questID] = now
	end
	wipe(acceptQueue)
	sendQuestMsg(acceptBatchText(entries))
end

local function QueueQuestAccept(questID, daily, worldQuest)
	local now = GetTime()
	local last = acceptAnnounced[questID]
	if last and (now - last) < ACCEPT_DEDUP_SEC then
		return
	end
	for i = 1, #acceptQueue do
		if acceptQueue[i].questID == questID then
			return
		end
	end

	if not db().batchAnnouncements then
		acceptAnnounced[questID] = now
		sendQuestMsg(acceptText(questID, daily, worldQuest))
		return
	end

	tinsert(acceptQueue, { questID = questID, daily = daily, worldQuest = worldQuest })
	if acceptFlushTimer then
		acceptFlushTimer:Cancel()
	end
	acceptFlushTimer = C_Timer.NewTimer(ACCEPT_BATCH_DELAY, FlushAcceptQueue)
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
			elseif F.NotSecret(o.numFulfilled) and F.NotSecret(o.numRequired) and F.NotSecret(o.text) and HasObjectiveText(o) then
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

local function FindQuestAccept(_, questID)
	if not questID or not (QuestNotification.debug or inAnnounceableGroup()) then
		return
	end

	-- Quest metadata (IsWorldQuest, tag info) often lags QUEST_ACCEPTED by a tick.
	C_Timer.After(0, function()
		if not ShouldAnnounceQuest(questID) then
			if IsWorldQuestLike(questID) then
				acceptAnnounced[questID] = GetTime()
			end
			return
		end

		local daily = false
		local questLogIndex = C_QuestLog_GetLogIndexForQuestID(questID)
		if questLogIndex then
			local info = C_QuestLog_GetInfo(questLogIndex)
			if info and F.NotSecret(info.frequency) then
				daily = info.frequency == LE_QUEST_FREQUENCY_DAILY
			end
		end
		QueueQuestAccept(questID, daily, IsWorldQuestLike(questID))
	end)
end

-- One pass over the quest log, driving both completion and objective progress.
-- QUEST_LOG_UPDATE is the only signal that reliably fires for *every* quest-log
-- change regardless of whether the quest is watched/tracked -- QUEST_WATCH_UPDATE
-- and QUEST_LOG_CRITERIA_UPDATE both miss untracked or non-criteria objectives,
-- which is why progress used to silently do nothing. So we diff structured
-- objective counts here instead.
local function ScanQuestLog()
	local announceProgress = db().progress and not db().onlyCompleteRing and (QuestNotification.debug or inAnnounceableGroup())

	for i = 1, C_QuestLog_GetNumQuestLogEntries() do
		local questID = C_QuestLog_GetQuestIDForLogIndex(i)
		if not questID then
			-- skip
		elseif not ShouldAnnounceQuest(questID) then
			-- Seed world quests silently so toggling the option on mid-session
			-- does not dump completions for quests already finished.
			local isComplete = C_QuestLog_IsComplete(questID)
			if F.NotSecret(isComplete) and isComplete and not completedQuest[questID] then
				completedQuest[questID] = true
				clearQuestProgress(questID)
			end
		else
			local isComplete = C_QuestLog_IsComplete(questID)
			if F.NotSecret(isComplete) and isComplete then
				if not completedQuest[questID] then
					if initComplete then
						QueueQuestComplete(questID)
					else
						completedQuest[questID] = true
						clearQuestProgress(questID)
					end
				end
			elseif db().progress then
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

local function FindQuestTurnedIn(_, questID)
	if not questID then
		return
	end
	-- World quests complete via QUEST_TURNED_IN; regular quests via the log scan.
	if IsWorldQuestLike(questID) then
		QueueQuestComplete(questID)
	else
		clearQuestProgress(questID)
	end
end

-- ---------------------------------------------------------------------------
-- Subscription management
-- ---------------------------------------------------------------------------
local subscriptions = {
	{ "QUEST_ACCEPTED", FindQuestAccept },
	{ "QUEST_LOG_UPDATE", ScanQuestLogThrottled },
	{ "QUEST_TURNED_IN", FindQuestTurnedIn },
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
		wipe(acceptAnnounced)
		ClearAcceptQueue()
		ClearCompleteQueue()
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
-- print a compact snapshot: settings, suppressed world quests, then eligible objectives.
function QuestNotification:ToggleDebug()
	self.debug = not self.debug or nil
	self:Update()

	if self.debug then
		F.Print(L["Quest Notification debug ON - messages will print here."])
		F.Print(db().worldQuests and L["Quest Notification debug WQ on"] or L["Quest Notification debug WQ off"])

		local suppressed, eligible = {}, 0
		for i = 1, C_QuestLog_GetNumQuestLogEntries() do
			local questID = C_QuestLog_GetQuestIDForLogIndex(i)
			if questID and not IsHiddenLogQuest(questID) and IsWorldQuestLike(questID) and not db().worldQuests then
				tinsert(suppressed, GetQuestLinkOrName(questID))
			end
		end

		for i = 1, C_QuestLog_GetNumQuestLogEntries() do
			local questID = C_QuestLog_GetQuestIDForLogIndex(i)
			local isComplete = questID and C_QuestLog_IsComplete(questID)
			if questID and ShouldAnnounceQuest(questID) and F.NotSecret(isComplete) and not isComplete then
				eligible = eligible + 1
				-- Seed counts silently so the next live update prints instead of seeding.
				ScanQuestProgress(questID, false)
			end
		end

		F.Print(format(L["Quest Notification debug suppressed WQs"], #suppressed))
		for i = 1, #suppressed do
			F.Print("  " .. suppressed[i])
		end
		F.Print(format(L["Quest Notification debug eligible"], eligible))
		if eligible > 0 then
			F.Print(L["Quest Notification debug live hint"])
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
		wipe(acceptAnnounced)
		ClearAcceptQueue()
		ClearCompleteQueue()
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
	local _, batchInit = builder:Checkbox(category, self, "batchAnnouncements", L["Batch Announcements"], L["Combine multiple accepts or completions from the same moment into one chat line."])
	local _, wqInit = builder:Checkbox(category, self, "worldQuests", L["Announce World Quests"], L["Include world quest accepts, progress, and completions in group chat."])
	local _, ringInit = builder:Checkbox(category, self, "onlyCompleteRing", L["Only Completion Sound"], L["Play a sound on quest completion but do not post any chat messages."])

	builder:DependsOn(progressInit, enableInit)
	builder:DependsOn(batchInit, enableInit)
	builder:DependsOn(wqInit, enableInit)
	builder:DependsOn(ringInit, enableInit)
end

ns.Debug.RegisterScope("questnotify", {
	title = L["Quest Notification"],
	module = QuestNotification,
	dump = function()
		F.Print(format("  self-test debug: %s", QuestNotification.debug and "ON" or "OFF"))
		F.Print(format("  module enabled: %s", QuestNotification:IsEnabled() and "yes" or "no"))
		F.Print(format("  world quests: %s", db().worldQuests and "yes" or "no"))
	end,
})
