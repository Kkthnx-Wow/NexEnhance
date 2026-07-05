--[[
	NexEnhance - Chat Channels
	-------------------------------------------------------------------------
	Shortens channel tags ([Party] -> [P], [Party Leader] -> [PL]), optional
	timestamps, clickable URLs. Abbrev/timestamp hook AddMessage; URLs use the
	12.0 message filter so we don't fight the secure chat path.

	LibChatAnims is required when we touch AddMessage — without it, talent
	changes can hard-block.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local format = string.format
local gsub = string.gsub
local strmatch, strfind = string.match, string.find
local strupper = string.upper
local type, date = type, date
local hooksecurefunc = hooksecurefunc
local ChatFrame_AddMessageEventFilter = ChatFrame_AddMessageEventFilter

LibStub("LibChatAnims")

ns:RegisterDefaults({
	chatChannels = {
		enable = true,
		abbreviate = true,
		hideChannels = false,
		urls = true,
		timestamp = false,
	},
})

local ChatChannels = ns:NewModule("ChatChannels", "chatChannels", { group = "chat", title = L["Chat Channels"], order = 30 })

local cfg

-- ChatFrame2/3 are combat log and voice — leave those alone.
local IGNORE_CHAT_IDS = {
	[2] = true,
	[3] = true,
}

local MESSAGE_EVENTS = {
	"CHAT_MSG_CHANNEL",
	"CHAT_MSG_COMMUNITIES_CHANNEL",
	"CHAT_MSG_SAY",
	"CHAT_MSG_YELL",
	"CHAT_MSG_WHISPER",
	"CHAT_MSG_WHISPER_INFORM",
	"CHAT_MSG_BN_WHISPER",
	"CHAT_MSG_BN_WHISPER_INFORM",
	"CHAT_MSG_EMOTE",
	"CHAT_MSG_TEXT_EMOTE",
	"CHAT_MSG_RAID",
	"CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_RAID_WARNING",
	"CHAT_MSG_PARTY",
	"CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_GUILD",
	"CHAT_MSG_OFFICER",
	"CHAT_MSG_BATTLEGROUND",
	"CHAT_MSG_BATTLEGROUND_LEADER",
	"CHAT_MSG_INSTANCE_CHAT",
	"CHAT_MSG_INSTANCE_CHAT_LEADER",
	"CHAT_MSG_AFK",
	"CHAT_MSG_DND",
	"CHAT_MSG_LOOT",
}

-- ---------------------------------------------------------------------------
-- Channel abbreviation
-- ---------------------------------------------------------------------------
local groupAbbr = {
	PARTY = "P",
	PARTY_LEADER = "PL",
	PARTY_GUIDE = "PG",
	PARTY_VOICE = "P",
	RAID = "R",
	RAID_LEADER = "RL",
	INSTANCE_CHAT = "I",
	INSTANCE_CHAT_LEADER = "IL",
	GUILD = "G",
	GUILD_VOICE = "G",
	OFFICER = "O",
	MONSTER_PARTY = "P",
}

-- Blizzard puts PARTY in the |Hchannel:| link even for [Party Leader] — map bracket
-- text from CHAT_*_GET so PL/IL/RL survive localization.
local FORMAT_ABBR = {
	{ "PARTY", "CHAT_PARTY_GET", "P" },
	{ "PARTY", "CHAT_PARTY_LEADER_GET", "PL" },
	{ "PARTY", "CHAT_PARTY_GUIDE_GET", "PG" },
	{ "PARTY", "CHAT_MONSTER_PARTY_GET", "P" },
	{ "RAID", "CHAT_RAID_GET", "R" },
	{ "RAID", "CHAT_RAID_LEADER_GET", "RL" },
	{ "INSTANCE_CHAT", "CHAT_INSTANCE_CHAT_GET", "I" },
	{ "INSTANCE_CHAT", "CHAT_INSTANCE_CHAT_LEADER_GET", "IL" },
	{ "GUILD", "CHAT_GUILD_GET", "G" },
	{ "OFFICER", "CHAT_OFFICER_GET", "O" },
}

local displayAbbr = {}
local displayAbbrReady = false

local function BuildDisplayAbbreviations()
	if displayAbbrReady then
		return
	end
	displayAbbrReady = true

	for i = 1, #FORMAT_ABBR do
		local channelKey, getKey, abbr = FORMAT_ABBR[i][1], FORMAT_ABBR[i][2], FORMAT_ABBR[i][3]
		local fmt = _G[getKey]
		if fmt then
			local tag = strmatch(fmt, "|Hchannel:.-|h%[(.-)%]|h")
			if tag then
				local bucket = displayAbbr[channelKey]
				if not bucket then
					bucket = {}
					displayAbbr[channelKey] = bucket
				end
				bucket[tag] = abbr
			end
		end
	end
end

local function ShortChannelTag(channelKey, displayName)
	BuildDisplayAbbreviations()

	local bucket = displayAbbr[channelKey]
	if bucket and displayName and bucket[displayName] then
		return format("|Hchannel:%s|h[%s]|h", channelKey, bucket[displayName])
	end

	local abbr = groupAbbr[strupper(channelKey or "")]
	if abbr then
		return format("|Hchannel:%s|h[%s]|h", channelKey, abbr)
	end

	local id = strmatch(channelKey or "", "channel:(%d+)")
	if id then
		return format("|Hchannel:%s|h[%s]|h", channelKey, id)
	end

	id = strmatch(displayName or "", "^(%d+)%.")
	return format("|Hchannel:%s|h[%s]|h", channelKey, id or gsub(channelKey or "", "channel:", ""))
end

local function HandleShortChannels(msg, hide)
	if hide then
		msg = gsub(msg, "|Hchannel:(.-)|h%[(.-)%]|h", "")
		msg = gsub(msg, "CHANNEL:", "")
	else
		msg = gsub(msg, "|Hchannel:(.-)|h%[(.-)%]|h", ShortChannelTag)
		msg = gsub(msg, "CHANNEL:", "")
	end

	local raidWarning = _G.RAID_WARNING
	if raidWarning then
		msg = gsub(msg, "^%[" .. raidWarning .. "%]", "[" .. L["ChatShortRW"] .. "]")
	end

	local afk = _G.AFK
	if afk then
		msg = gsub(msg, "<" .. afk .. ">", "[|cffFF9900" .. L["ChatShortAFK"] .. "|r] ")
	end

	local dnd = _G.DND
	if dnd then
		msg = gsub(msg, "<" .. dnd .. ">", "[|cffFF3333" .. L["ChatShortDND"] .. "|r] ")
	end

	return msg
end

-- ---------------------------------------------------------------------------
-- URL highlighting
-- ---------------------------------------------------------------------------
local function ConvertLink(text, value)
	return "|Hurl:" .. tostring(value) .. "|h" .. C.InfoColor .. text .. "|r|h"
end

local function HighlightURL(prefix, url, suffix, href)
	return prefix .. ConvertLink("[" .. url .. "]", href or url) .. suffix
end

local urlShield = {}

local function ShieldHyperlinks(text)
	return (gsub(text, "|H.-|h.-|h", function(block)
		urlShield[#urlShield + 1] = block
		return "\003" .. #urlShield .. "\003"
	end))
end

local function UnshieldHyperlinks(text)
	return (gsub(text, "\003(%d+)\003", function(i)
		return urlShield[tonumber(i)] or ""
	end))
end

local function ApplyURLs(text)
	wipe(urlShield)
	text = ShieldHyperlinks(text)

	if strfind(text, "://", 1, true) then
		text = gsub(text, "(%s?)(%a+://[%w_/%.%?%%=~&%-'%-]+)(%s?)", HighlightURL)
		text = ShieldHyperlinks(text)
	end
	if strfind(text, "www.", 1, true) then
		text = gsub(text, "(%s?)(www%.[%w_/%.%?%%=~&%-'%-]+)(%s?)", function(prefix, url, suffix)
			return HighlightURL(prefix, url, suffix, "https://" .. url)
		end)
		text = ShieldHyperlinks(text)
	end
	if strfind(text, "@", 1, true) then
		text = gsub(text, "(%s?)([_%w%-%.~]+@[_%w%-]+%.[_%w%-%.]+)(%s?)", HighlightURL)
	end

	return UnshieldHyperlinks(text)
end

-- ---------------------------------------------------------------------------
-- Timestamp + AddMessage wrapper
-- ---------------------------------------------------------------------------
local function GetTimestamp()
	return format("|cff909090[%s]|r ", date("%H:%M"))
end

local function TransformDisplayLine(msg)
	if F.IsSecret(msg) then
		return msg
	end
	if type(msg) ~= "string" or msg == "" then
		return msg
	end
	if strmatch(msg, "^%s*$") then
		return msg
	end

	if cfg.hideChannels then
		msg = HandleShortChannels(msg, true)
	elseif cfg.abbreviate then
		msg = HandleShortChannels(msg, false)
	end
	if cfg.timestamp then
		msg = GetTimestamp() .. msg
	end
	return msg
end

local function WrappedAddMessage(frame, msg, ...)
	msg = TransformDisplayLine(msg)
	return frame.OldAddMessage(frame, msg, ...)
end

local function ShouldHookAddMessage()
	return cfg and cfg.enable and (cfg.abbreviate or cfg.timestamp or cfg.hideChannels)
end

local function SyncFrameAddMessage(frame)
	if not frame or not frame.AddMessage then
		return
	end

	local id = frame.GetID and frame:GetID()
	if id and IGNORE_CHAT_IDS[id] then
		return
	end

	if ShouldHookAddMessage() then
		if not frame.OldAddMessage then
			frame.OldAddMessage = frame.AddMessage
			frame.AddMessage = WrappedAddMessage
		end
	elseif frame.OldAddMessage then
		frame.AddMessage = frame.OldAddMessage
		frame.OldAddMessage = nil
	end
end

local function HookAllChatFrames()
	local frames = _G.CHAT_FRAMES
	if not frames then
		return
	end
	for i = 1, #frames do
		SyncFrameAddMessage(_G[frames[i]])
	end
end

local function InstallAddMessageHooks()
	if ChatChannels.addMessageHooksInstalled then
		HookAllChatFrames()
		return
	end
	ChatChannels.addMessageHooksInstalled = true

	HookAllChatFrames()
	hooksecurefunc("FCF_OpenTemporaryWindow", HookAllChatFrames)
end

-- ---------------------------------------------------------------------------
-- Message event filter (URLs on raw message body)
-- ---------------------------------------------------------------------------
local function TransformMessageFilter(_, event, msg, ...)
	if not cfg.enable or not cfg.urls then
		return
	end
	if F.IsSecret(msg) then
		return
	end
	if type(msg) ~= "string" then
		return
	end

	local newMsg = ApplyURLs(msg)
	if newMsg == msg then
		return
	end

	return false, newMsg, ...
end

local function InstallMessageFilters()
	if ChatChannels.filtersInstalled then
		return
	end
	ChatChannels.filtersInstalled = true

	for i = 1, #MESSAGE_EVENTS do
		ChatFrame_AddMessageEventFilter(MESSAGE_EVENTS[i], TransformMessageFilter)
	end
end

-- ---------------------------------------------------------------------------
-- URL click -> copy popup
-- ---------------------------------------------------------------------------
local function SetupURLCopy()
	if StaticPopupDialogs["NEXENHANCE_COPY_URL"] then
		return
	end
	StaticPopupDialogs["NEXENHANCE_COPY_URL"] = {
		text = L["Copy the link below:"],
		button1 = OKAY or "Okay",
		hasEditBox = true,
		editBoxWidth = 350,
		hideOnEscape = true,
		timeout = 0,
		whileDead = true,
		preferredIndex = 3,
		OnShow = function(self, data)
			local eb = self.editBox or (self.GetEditBox and self:GetEditBox())
			if eb then
				eb:SetText(data or "")
				eb:HighlightText()
				eb:SetFocus()
			end
		end,
		EditBoxOnEscapePressed = function(eb)
			eb:GetParent():Hide()
		end,
	}

	hooksecurefunc("SetItemRef", function(link)
		if not (cfg and cfg.enable and cfg.urls) then
			return
		end
		local ltype, value = strmatch(link, "^(%a+):(.+)$")
		if ltype == "url" and value then
			StaticPopup_Show("NEXENHANCE_COPY_URL", nil, nil, value)
		end
	end)
end

local function SyncAll()
	InstallAddMessageHooks()
	HookAllChatFrames()
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function ChatChannels:OnEnable()
	cfg = ns.db.chatChannels
	BuildDisplayAbbreviations()
	InstallMessageFilters()
	SetupURLCopy()
	SyncAll()
end

function ChatChannels:OnSettingChanged()
	cfg = ns.db.chatChannels
	SyncAll()
end

function ChatChannels:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Chat Channels"], L["Tidy channel names, URLs and timestamps in chat."])
	builder:Checkbox(category, self, "abbreviate", L["Abbreviate Channels"], L["Shorten channel brackets, e.g. [1. General] becomes [1], [Guild] becomes [G]."])
	builder:Checkbox(category, self, "hideChannels", L["Hide Channel Tags"], L["Remove channel brackets entirely instead of abbreviating them."])
	builder:Checkbox(category, self, "urls", L["Clickable URLs"], L["Make web links clickable and copyable."])
	builder:Checkbox(category, self, "timestamp", L["Timestamps"], L["Prepend a [HH:MM] timestamp to each message."])
end
