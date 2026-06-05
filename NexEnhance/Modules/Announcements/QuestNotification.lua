--[[
	NexEnhance - Quest Notification
	-------------------------------------------------------------------------
	Announces quest activity to your group: quests you accept, objective
	progress, and completions (with a completion sound). Useful so the party
	knows when everyone is ready to turn in.

	Ported from NDui's Modules/Misc/QuestNotification.lua (by siweia), adapted
	to the NexEnhance framework. Subscriptions toggle live (no reload).
--]]

-- luacheck: globals SendChatMessage
-- The Lua Language Server types quest IDs as optional; silence those false positives.
---@diagnostic disable: param-type-mismatch, need-check-nil
local _, ns = ...
local F, L = ns.F, ns.L

local strmatch, strfind, gsub, format, floor = strmatch, strfind, gsub, string.format, math.floor
local wipe, mod, tonumber, pairs = wipe, mod, tonumber, pairs
local IsPartyLFG, IsInRaid, IsInGroup = IsPartyLFG, IsInRaid, IsInGroup
local PlaySound, GetQuestLink = PlaySound, GetQuestLink
local C_PartyInfo = C_PartyInfo
local C_QuestLog_GetInfo = C_QuestLog.GetInfo
local C_QuestLog_IsComplete = C_QuestLog.IsComplete
local C_QuestLog_IsWorldQuest = C_QuestLog.IsWorldQuest
local C_QuestLog_GetQuestTagInfo = C_QuestLog.GetQuestTagInfo
local C_QuestLog_GetTitleForQuestID = C_QuestLog.GetTitleForQuestID
local C_QuestLog_GetQuestIDForLogIndex = C_QuestLog.GetQuestIDForLogIndex
local C_QuestLog_GetNumQuestLogEntries = C_QuestLog.GetNumQuestLogEntries
local C_QuestLog_GetLogIndexForQuestID = C_QuestLog.GetLogIndexForQuestID
local soundKitID = SOUNDKIT.ALARM_CLOCK_WARNING_3
local DAILY, QUEST_COMPLETE = DAILY, QUEST_COMPLETE
local COLLECTED = COLLECTED
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

local function sendQuestMsg(msg)
	if db().onlyCompleteRing then return end

	if IsPartyLFG() or (C_PartyInfo and C_PartyInfo.IsPartyWalkIn and C_PartyInfo.IsPartyWalkIn()) then
		SendChatMessage(msg, "INSTANCE_CHAT")
	elseif IsInRaid() then
		SendChatMessage(msg, "RAID")
	elseif IsInGroup() then
		SendChatMessage(msg, "PARTY")
	end
end

local function getPattern(pattern)
	pattern = gsub(pattern, "%(", "%%%1")
	pattern = gsub(pattern, "%)", "%%%1")
	pattern = gsub(pattern, "%%%d?$?.", "(.+)")
	return format("^%s$", pattern)
end

local questMatches = {
	["Found"] = getPattern(ERR_QUEST_ADD_FOUND_SII),
	["Item"] = getPattern(ERR_QUEST_ADD_ITEM_SII),
	["Kill"] = getPattern(ERR_QUEST_ADD_KILL_SII),
	["PKill"] = getPattern(ERR_QUEST_ADD_PLAYER_KILL_SII),
	["ObjectiveComplete"] = getPattern(ERR_QUEST_OBJECTIVE_COMPLETE_S),
	["QuestComplete"] = getPattern(ERR_QUEST_COMPLETE_S),
	["QuestFailed"] = getPattern(ERR_QUEST_FAILED_S),
}

-- ---------------------------------------------------------------------------
-- Event handlers (signatures match ns:RegisterEvent -> (event, ...))
-- ---------------------------------------------------------------------------
local function FindQuestProgress(_, _, msg)
	if not db().progress or db().onlyCompleteRing then return end

	for _, pattern in pairs(questMatches) do
		if strmatch(msg, pattern) then
			local _, _, _, cur, max = strfind(msg, "(.*)[:：]%s*([-%d]+)%s*/%s*([-%d]+)%s*$")
			cur, max = tonumber(cur), tonumber(max)
			if cur and max and max >= 10 then
				if mod(cur, floor(max / 5)) == 0 then
					sendQuestMsg(msg)
				end
			else
				sendQuestMsg(msg)
			end
			break
		end
	end
end

local WQcache = {}
local function FindQuestAccept(_, questID)
	if not questID then return end
	if C_QuestLog_IsWorldQuest(questID) and WQcache[questID] then return end
	WQcache[questID] = true

	local tagInfo = C_QuestLog_GetQuestTagInfo(questID)
	if tagInfo and tagInfo.worldQuestType == LE_QUEST_TAG_TYPE_PROFESSION then return end

	local questLogIndex = C_QuestLog_GetLogIndexForQuestID(questID)
	if questLogIndex then
		local info = C_QuestLog_GetInfo(questLogIndex)
		if info then
			sendQuestMsg(acceptText(questID, info.frequency == LE_QUEST_FREQUENCY_DAILY))
		end
	end
end

local function FindQuestComplete()
	for i = 1, C_QuestLog_GetNumQuestLogEntries() do
		local questID = C_QuestLog_GetQuestIDForLogIndex(i)
		local isComplete = questID and C_QuestLog_IsComplete(questID)
		if isComplete and not completedQuest[questID] and not C_QuestLog_IsWorldQuest(questID) then
			if initComplete then
				sendQuestMsg(completeText(questID))
			end
			completedQuest[questID] = true
		end
	end
	initComplete = true
end

-- QUEST_LOG_UPDATE storms (it can fire many times per second during quest/log
-- churn). Coalesce the full-log scan so we only walk the quest log once the
-- burst settles, per the event-throttling guidance in the research reports.
local FindQuestCompleteThrottled = F.Debounce(0.2, FindQuestComplete)

local function FindWorldQuestComplete(_, questID)
	if questID and C_QuestLog_IsWorldQuest(questID) then
		if not completedQuest[questID] then
			sendQuestMsg(completeText(questID))
			completedQuest[questID] = true
		end
	end
end

-- Dragon glyph collection
local glyphAchievements = {
	[16575] = true, -- Waking Shores
	[16576] = true, -- Ohn'ahran Plains
	[16577] = true, -- Azure Span
	[16578] = true, -- Thaldraszus
}

local function FindDragonGlyph(_, achievementID, criteriaString)
	if glyphAchievements[achievementID] then
		sendQuestMsg(criteriaString .. " " .. COLLECTED)
	end
end

-- ---------------------------------------------------------------------------
-- Subscription management
-- ---------------------------------------------------------------------------
local subscriptions = {
	{ "QUEST_ACCEPTED", FindQuestAccept },
	{ "QUEST_LOG_UPDATE", FindQuestCompleteThrottled },
	{ "QUEST_TURNED_IN", FindWorldQuestComplete },
	{ "UI_INFO_MESSAGE", FindQuestProgress },
	{ "CRITERIA_EARNED", FindDragonGlyph },
}

function QuestNotification:Update()
	if db().enable then
		if not self.registered then
			for i = 1, #subscriptions do
				ns:RegisterEvent(subscriptions[i][1], subscriptions[i][2])
			end
			self.registered = true
		end
	elseif self.registered then
		wipe(completedQuest)
		-- Reset the seed flag too, so a later re-enable rebuilds the
		-- completed-quest set silently instead of announcing everything.
		initComplete = nil
		for i = 1, #subscriptions do
			ns:UnregisterEvent(subscriptions[i][1], subscriptions[i][2])
		end
		self.registered = nil
	end
end

function QuestNotification:OnEnable()
	self:Update()
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
