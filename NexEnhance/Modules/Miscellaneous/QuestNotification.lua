-- Module Initialization
local _, Module = ...

-- Localized Lua Functions
local strmatch, strfind, gsub, format, floor = strmatch, strfind, gsub, format, floor
local wipe, mod, tonumber, pairs, print = wipe, mod, tonumber, pairs, print

-- WoW API References
local SendChatMessage = SendChatMessage
local GetQuestLink = GetQuestLink
local C_QuestLog_GetInfo = C_QuestLog.GetInfo
local C_QuestLog_IsComplete = C_QuestLog.IsComplete
local C_QuestLog_IsWorldQuest = C_QuestLog.IsWorldQuest
local C_QuestLog_GetQuestTagInfo = C_QuestLog.GetQuestTagInfo
local C_QuestLog_GetTitleForQuestID = C_QuestLog.GetTitleForQuestID
local C_QuestLog_GetQuestIDForLogIndex = C_QuestLog.GetQuestIDForLogIndex
local C_QuestLog_GetNumQuestLogEntries = C_QuestLog.GetNumQuestLogEntries
local C_QuestLog_GetLogIndexForQuestID = C_QuestLog.GetLogIndexForQuestID

-- Constants and Globals
local soundKitID = SOUNDKIT.ALARM_CLOCK_WARNING_3
local DAILY, QUEST_COMPLETE, COLLECTED = DAILY, QUEST_COMPLETE, COLLECTED
local LE_QUEST_TAG_TYPE_PROFESSION = Enum.QuestTagType.Profession
local LE_QUEST_FREQUENCY_DAILY = Enum.QuestFrequency.Daily

-- State Variables
local debugMode = false
local completedQuest = {}
local initComplete = false

-- Utility Functions
local function GetQuestLinkOrName(questID)
	return GetQuestLink(questID) or C_QuestLog_GetTitleForQuestID(questID) or ""
end

local function acceptText(questID, daily)
	local title = GetQuestLinkOrName(questID)
	if daily then
		return format("%s [%s]%s", Module.L["Accepted Quest"], DAILY, title)
	else
		return format("%s %s", Module.L["Accepted Quest"], title)
	end
end

local function completeText(questID)
	PlaySound(soundKitID, "Master")
	return format("%s %s", GetQuestLinkOrName(questID), QUEST_COMPLETE)
end

local function sendQuestMsg(msg)
	if Module.NexConfig.miscellaneous.QuestTrackerAlerts.OnlyCompleteRing then
		return
	end

	if debugMode and Module.isDeveloper then
		print(msg)
	elseif IsPartyLFG() or C_PartyInfo.IsPartyWalkIn() then
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

-- Quest Match Patterns
local questMatches = {
	["Found"] = getPattern(ERR_QUEST_ADD_FOUND_SII),
	["Item"] = getPattern(ERR_QUEST_ADD_ITEM_SII),
	["Kill"] = getPattern(ERR_QUEST_ADD_KILL_SII),
	["PKill"] = getPattern(ERR_QUEST_ADD_PLAYER_KILL_SII),
	["ObjectiveComplete"] = getPattern(ERR_QUEST_OBJECTIVE_COMPLETE_S),
	["QuestComplete"] = getPattern(ERR_QUEST_COMPLETE_S),
	["QuestFailed"] = getPattern(ERR_QUEST_FAILED_S),
}

-- Main Quest Event Handlers
function Module:FindQuestProgress(_, msg)
	if not Module.NexConfig.miscellaneous.QuestTrackerAlerts.QuestProgress or Module.NexConfig.miscellaneous.QuestTrackerAlerts.OnlyCompleteRing then
		return
	end

	for _, pattern in pairs(questMatches) do
		if strmatch(msg, pattern) then
			local _, _, _, cur, max = strfind(msg, "(.*)[:：]%s*([-%d]+)%s*/%s*([-%d]+)%s*$")
			cur, max = tonumber(cur), tonumber(max)
			if cur and max and max >= 10 and mod(cur, floor(max / 5)) == 0 then
				sendQuestMsg(msg)
			else
				sendQuestMsg(msg)
			end
			break
		end
	end
end

local WQcache = {}
function Module:FindQuestAccept(questID)
	if not questID or (C_QuestLog_IsWorldQuest(questID) and WQcache[questID]) then
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

function Module:FindQuestComplete()
	for i = 1, C_QuestLog_GetNumQuestLogEntries() do
		local questID = C_QuestLog_GetQuestIDForLogIndex(i)
		if questID and C_QuestLog_IsComplete(questID) and not completedQuest[questID] and not C_QuestLog_IsWorldQuest(questID) then
			if initComplete then
				sendQuestMsg(completeText(questID))
			end
			completedQuest[questID] = true
		end
	end
	initComplete = true
end

function Module:FindWorldQuestComplete(questID)
	if questID and C_QuestLog_IsWorldQuest(questID) and not completedQuest[questID] then
		sendQuestMsg(completeText(questID))
		completedQuest[questID] = true
	end
end

-- Dragon Glyph Notifications
local glyphAchievements = {
	[16575] = true, -- Awakening Shore
	[16576] = true, -- Ohn'ahran Plains
	[16577] = true, -- Azure Span
	[16578] = true, -- Thaldraszus
}

function Module:FindDragonGlyph(achievementID, criteriaString)
	if glyphAchievements[achievementID] then
		sendQuestMsg(criteriaString .. " " .. COLLECTED)
	end
end

-- Helper function to manage event registration
function Module:ManageEvent(event, handler, register)
	if register then
		if not self:IsEventRegistered(event, handler) then
			self:RegisterEvent(event, handler)
		end
	else
		if self:IsEventRegistered(event, handler) then
			self:UnregisterEvent(event, handler)
		end
	end
end

-- Notification Management
function Module:QuestNotification()
	if Module.NexConfig.miscellaneous.QuestTrackerAlerts.QuestNotification then
		self:ManageEvent("QUEST_ACCEPTED", Module.FindQuestAccept, true)
		self:ManageEvent("QUEST_LOG_UPDATE", Module.FindQuestComplete, true)
		self:ManageEvent("QUEST_TURNED_IN", Module.FindWorldQuestComplete, true)
		self:ManageEvent("UI_INFO_MESSAGE", Module.FindQuestProgress, true)
		self:ManageEvent("CRITERIA_EARNED", Module.FindDragonGlyph, true)
	else
		wipe(completedQuest)
		self:ManageEvent("QUEST_ACCEPTED", Module.FindQuestAccept, false)
		self:ManageEvent("QUEST_LOG_UPDATE", Module.FindQuestComplete, false)
		self:ManageEvent("QUEST_TURNED_IN", Module.FindWorldQuestComplete, false)
		self:ManageEvent("UI_INFO_MESSAGE", Module.FindQuestProgress, false)
		self:ManageEvent("CRITERIA_EARNED", Module.FindDragonGlyph, false)
	end
end

-- Initialization
function Module:PLAYER_LOGIN()
	self:QuestNotification()
end
