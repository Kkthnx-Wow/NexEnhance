--[[
	NexEnhance - Auto Goodbye
	-------------------------------------------------------------------------
	Sends a random, friendly farewell to the group when a dungeon or Mythic+
	keystone finishes, after a short human-feeling delay.

	Events stay registered while the module is on; enable flag reads live.
	Opt-in by default since it speaks on your behalf.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local L = ns.L

local C_Timer_After = C_Timer.After
local C_PartyInfo_IsPartyWalkIn = C_PartyInfo and C_PartyInfo.IsPartyWalkIn
local GetInstanceInfo = GetInstanceInfo
local GetTime = GetTime
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local IsPartyLFG = IsPartyLFG
-- C_ChatInfo.SendChatMessage is the live API; the global is a deprecated shim.
local SendChatMessage = C_ChatInfo.SendChatMessage
local math_random = math.random

ns:RegisterDefaults({
	autoGoodbye = {
		enable = false,
	},
})

local AutoGoodbye = ns:NewModule("AutoGoodbye", "autoGoodbye", { group = "automation", title = L["Auto Goodbye"], order = 70 })

local eventHandles = {}

-- Throttle/dedupe: both completion events can fire close together, so we queue
-- a single delayed send and rate-limit how often a message can actually go out.
local lastGoodbyeAt = 0
local pendingGoodbye = false

local function GetGroupChannel()
	local _, instanceType = GetInstanceInfo()
	if not instanceType or instanceType == "none" then
		return nil
	end
	if not IsInGroup() then
		return nil
	end

	-- LFD/LFR groups: use INSTANCE_CHAT so everyone queued can see it; walk-in
	-- (manually formed) groups fall through to party/raid.
	if IsPartyLFG() and not (C_PartyInfo_IsPartyWalkIn and C_PartyInfo_IsPartyWalkIn()) then
		return "INSTANCE_CHAT"
	end
	if IsInRaid() then
		return "RAID"
	end
	return "PARTY"
end

local function SendGoodbye()
	pendingGoodbye = false

	local now = GetTime()
	if now > 0 and (now - lastGoodbyeAt) < 8 then
		return
	end

	local list = L["AutoGoodbyeMessages"]
	if not list or #list == 0 then
		return
	end

	local channel = GetGroupChannel()
	if not channel then
		return
	end

	local msg = list[math_random(#list)]
	if not msg or msg == "" then
		return
	end

	SendChatMessage(msg, channel)
	lastGoodbyeAt = now
end

function AutoGoodbye:QueueGoodbye()
	if not ns.db.autoGoodbye.enable then
		return
	end
	if pendingGoodbye then
		return
	end

	pendingGoodbye = true
	-- Random delay so it doesn't fire the instant the rewards pop, feeling botty.
	C_Timer_After(math_random(2, 5), SendGoodbye)
end

function AutoGoodbye:LFG_COMPLETION_REWARD()
	self:QueueGoodbye()
end

function AutoGoodbye:CHALLENGE_MODE_COMPLETED()
	self:QueueGoodbye()
end

function AutoGoodbye:RegisterModuleEvents()
	if self.eventsRegistered then
		return
	end
	self.eventsRegistered = true

	self:TrackEvent(eventHandles, "LFG_COMPLETION_REWARD")
	self:TrackEvent(eventHandles, "CHALLENGE_MODE_COMPLETED")
end

function AutoGoodbye:UnregisterModuleEvents()
	if not self.eventsRegistered then
		return
	end
	self.eventsRegistered = false
	pendingGoodbye = false
	ns:UnregisterModuleEventHandles(eventHandles)
end

function AutoGoodbye:OnDisable()
	self:UnregisterModuleEvents()
end

function AutoGoodbye:OnSettingChanged(key, value)
	if key == "enable" then
		if value then
			self:RegisterModuleEvents()
		else
			self:OnDisable()
		end
	end
end

function AutoGoodbye:OnEnable()
	self:RegisterModuleEvents()
end

function AutoGoodbye:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Auto Goodbye"], L["Send a random friendly farewell to the group after finishing a dungeon or Mythic+ run."])
end
