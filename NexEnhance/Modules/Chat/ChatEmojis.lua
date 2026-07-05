--[[
	NexEnhance - Chat Emojis
	-------------------------------------------------------------------------
	Replaces common text emoticons (:D, :smile:, <3, …) with inline textures
	from Media/Emojis. Chat log lines embed a hidden nexmoji hyperlink so
	Chat Copy can recover the original text; optional speech bubbles get
	textures only (no links).

	ChatFrame_AddMessageEventFilter only — hyperlink spans are left alone; plain
	text gets scanned. Bubbles use C_ChatBubbles on a throttled poll (same
	worker pattern as the Chat Bubbles skin).
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local byte = string.byte
local format = string.format
local gsub = string.gsub
local strfind, strmatch, strsub = string.find, string.match, string.sub
local strlen = string.len
local tconcat = table.concat
local wipe = wipe
local ipairs = ipairs
local pairs = pairs
local CreateFrame = CreateFrame
local GetCVarBool = GetCVarBool
local ChatFrame_AddMessageEventFilter = ChatFrame_AddMessageEventFilter
local C_ChatBubbles_GetAllChatBubbles = C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles

LibStub("LibChatAnims")

ns:RegisterDefaults({
	chatEmojis = {
		enable = true,
		bubbles = false,
	},
})

local ChatEmojis = ns:NewModule("ChatEmojis", "chatEmojis", { group = "chat", title = L["Chat Emojis"], order = 25 })

local cfg
local entries = {} -- sorted { pattern, texture } built once from DEFINITIONS
local listReady = false

local EMOJI_PX = 16
local BUBBLE_EMOJI_PX = 12
-- Blizzard caps bubble width around 300px; String inset is 16px per side.
local BUBBLE_MAX_TEXT_WIDTH = 268
local NEXMOJI_SCHEME = "nexmoji:"
local NEXMOJI_LINK_PAD = "|cFFffffff|r|h"
local EMOTICON_HINT = "[%(:;<>=3♥XD]" -- quick reject when segment cannot match

-- { pattern, texKey } — pattern is a Lua match fragment; texKey maps to C.Media.Emojis.
local DEFINITIONS = {
	-- :token: names
	{ ":angry:", "Angry" },
	{ ":blush:", "Blush" },
	{ ":broken_heart:", "BrokenHeart" },
	{ ":call_me:", "CallMe" },
	{ ":cry:", "Cry" },
	{ ":facepalm:", "Facepalm" },
	{ ":grin:", "Grin" },
	{ ":heart:", "Heart" },
	{ ":heart_eyes:", "HeartEyes" },
	{ ":joy:", "Joy" },
	{ ":kappa:", "Kappa" },
	{ ":middle_finger:", "MiddleFinger" },
	{ ":murloc:", "Murloc" },
	{ ":ok_hand:", "OkHand" },
	{ ":open_mouth:", "OpenMouth" },
	{ ":poop:", "Poop" },
	{ ":rage:", "Rage" },
	{ ":sadkitty:", "SadKitty" },
	{ ":scream:", "Scream" },
	{ ":scream_cat:", "ScreamCat" },
	{ ":slight_frown:", "SlightFrown" },
	{ ":slight_smile:", "SlightSmile" },
	{ ":smile:", "Smile" },
	{ ":smirk:", "Smirk" },
	{ ":sob:", "Sob" },
	{ ":sunglasses:", "Sunglasses" },
	{ ":thinking:", "Thinking" },
	{ ":thumbs_up:", "ThumbsUp" },
	{ ":semi_colon:", "SemiColon" },
	{ ":wink:", "Wink" },
	{ ":zzz:", "ZZZ" },
	{ ":stuck_out_tongue:", "StuckOutTongue" },
	{ ":stuck_out_tongue_closed_eyes:", "StuckOutTongueClosedEyes" },
	{ ":meaw:", "Meaw" },
	-- ASCII / shorthand
	{ ">:(", "Rage" },
	{ ":%$", "Blush" },
	{ "<\\3", "BrokenHeart" },
	{ ":'%)", "Joy" },
	{ ";'%)", "Joy" },
	{ ",,!,,", "MiddleFinger" },
	{ "D:<", "Rage" },
	{ ":o3", "ScreamCat" },
	{ "XP", "StuckOutTongueClosedEyes" },
	{ "8%-%)", "Sunglasses" },
	{ "8%)", "Sunglasses" },
	{ ":%+1:", "ThumbsUp" },
	{ ":;:", "SemiColon" },
	{ ";o;", "Sob" },
	{ ":%-@", "Angry" },
	{ ":@", "Angry" },
	{ ":%-%)", "SlightSmile" },
	{ ":%)", "SlightSmile" },
	{ ":D", "Smile" },
	{ ":%-D", "Smile" },
	{ ";%-D", "Grin" },
	{ ";D", "Grin" },
	{ "=D", "Grin" },
	{ "xD", "Grin" },
	{ "XD", "Grin" },
	{ ":%-%(", "SlightFrown" },
	{ ":%(", "SlightFrown" },
	{ ":o", "OpenMouth" },
	{ ":%-o", "OpenMouth" },
	{ ":%-O", "OpenMouth" },
	{ ":O", "OpenMouth" },
	{ ":%-0", "OpenMouth" },
	{ ":P", "StuckOutTongue" },
	{ ":%-P", "StuckOutTongue" },
	{ ":p", "StuckOutTongue" },
	{ ":%-p", "StuckOutTongue" },
	{ "=P", "StuckOutTongue" },
	{ "=p", "StuckOutTongue" },
	{ ";%-p", "StuckOutTongueClosedEyes" },
	{ ";p", "StuckOutTongueClosedEyes" },
	{ ";P", "StuckOutTongueClosedEyes" },
	{ ";%-P", "StuckOutTongueClosedEyes" },
	{ ";%-%)", "Wink" },
	{ ";%)", "Wink" },
	{ ":S", "Smirk" },
	{ ":%-S", "Smirk" },
	{ ":,%(", "Cry" },
	{ ":,%-%(", "Cry" },
	{ ":\'%(", "Cry" },
	{ ":\'%-%(", "Cry" },
	{ ":F", "MiddleFinger" },
	{ "</3", "BrokenHeart" },
	{ "<3", "Heart" },
	{ "♥", "Heart" },
}

-- Same event set as Chat Channels (URL filter); omit loot — no emoticons there.
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
}

-- ---------------------------------------------------------------------------
-- Token encoding (hex — safe for gsub callbacks and chat hyperlinks)
-- ---------------------------------------------------------------------------
local function EncodeToken(text)
	return (gsub(text, ".", function(c)
		return format("%%%02X", byte(c))
	end))
end

local function DecodeToken(encoded)
	if not encoded or encoded == "" then
		return nil
	end
	return (gsub(encoded, "%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end))
end

local function NexMojiLink(matched)
	return "|H" .. NEXMOJI_SCHEME .. EncodeToken(matched) .. "|h" .. NEXMOJI_LINK_PAD
end

-- ---------------------------------------------------------------------------
-- Build sorted replacement list (longest pattern first)
-- ---------------------------------------------------------------------------
local function BuildReplacementList()
	if listReady then
		return
	end
	listReady = true

	local n = 0
	for i = 1, #DEFINITIONS do
		local pattern, texKey = DEFINITIONS[i][1], DEFINITIONS[i][2]
		if pattern and texKey and not strfind(pattern, ":%%", 1, true) then
			local path = C.Media.Emojis[texKey]
			if path then
				n = n + 1
				entries[n] = {
					pattern = pattern,
					chatTexture = F.ChatTexture(path, EMOJI_PX, EMOJI_PX),
					bubbleTexture = F.ChatTexture(path, BUBBLE_EMOJI_PX, BUBBLE_EMOJI_PX),
				}
			end
		end
	end

	table.sort(entries, function(a, b)
		return #a.pattern > #b.pattern
	end)
end

-- ---------------------------------------------------------------------------
-- Plain-segment replacement
-- ---------------------------------------------------------------------------
local function ReplaceInSegment(segment, useLinks, textureKey)
	if not strfind(segment, EMOTICON_HINT, 1) then
		return segment
	end

	for i = 1, #entries do
		local entry = entries[i]
		local pat = entry.pattern
		local tex = entry[textureKey]
		if tex and strmatch(segment, "[%s%p]-" .. pat .. "[%s%p]*") then
			segment = gsub(segment, "([%s%p]-)(" .. pat .. ")([%s%p]*)", function(prefix, matched, suffix)
				local mid = tex
				if useLinks then
					mid = NexMojiLink(matched) .. mid
				end
				return prefix .. mid .. suffix
			end)
		end
	end
	return segment
end

-- Reused each transform to avoid per-message table alloc.
local segmentParts = {}

local function ContainsBlockedSlash(msg)
	return strfind(msg, "/run", 1, true) or strfind(msg, "/dump", 1, true) or strfind(msg, "/script", 1, true)
end

local function TransformMessageBody(msg)
	if not msg or msg == "" then
		return msg
	end
	if ContainsBlockedSlash(msg) then
		return msg
	end

	wipe(segmentParts)
	local partCount = 0
	local cursor = 1
	local len = strlen(msg)

	while cursor <= len do
		local linkStart = strfind(msg, "|H", cursor, true)
		local plainEnd = linkStart and (linkStart - 1) or len

		if plainEnd >= cursor then
			partCount = partCount + 1
			segmentParts[partCount] = ReplaceInSegment(strsub(msg, cursor, plainEnd), true, "chatTexture")
		end

		if not linkStart then
			break
		end

		cursor = linkStart
		local _, linkEnd = strfind(msg, "|h.-|h", cursor)
		linkEnd = linkEnd or len
		if linkEnd >= cursor then
			partCount = partCount + 1
			segmentParts[partCount] = strsub(msg, cursor, linkEnd)
			cursor = linkEnd + 1
		else
			break
		end
	end

	if partCount == 0 then
		return msg
	end
	if partCount == 1 then
		return segmentParts[1]
	end
	return tconcat(segmentParts, nil, 1, partCount)
end

local function TransformBubbleBody(msg)
	if not msg or msg == "" or F.IsSecret(msg) or type(msg) ~= "string" then
		return msg
	end
	if ContainsBlockedSlash(msg) then
		return msg
	end
	return ReplaceInSegment(msg, false, "bubbleTexture")
end

-- After icons replace plain text, shrink String or the bubble stays wide.
local function ReflowBubbleString(str)
	if not str or not str.GetStringWidth or not str.SetWidth then
		return
	end

	local w = str:GetStringWidth()
	if not w or w <= 0 then
		return
	end

	str:SetWidth(w < BUBBLE_MAX_TEXT_WIDTH and w or BUBBLE_MAX_TEXT_WIDTH)
end

-- ---------------------------------------------------------------------------
-- Speech bubbles (optional; off by default)
-- ---------------------------------------------------------------------------
local bubbleWorker
local bubblePollElapsed = 0

-- Gate polling on the same CVars Blizzard uses for bubble display.
local bubbleCVars = {
	CHAT_MSG_SAY = "chatBubbles",
	CHAT_MSG_YELL = "chatBubbles",
	CHAT_MSG_MONSTER_SAY = "chatBubbles",
	CHAT_MSG_MONSTER_YELL = "chatBubbles",
	CHAT_MSG_EMOTE = "chatBubbles",
	CHAT_MSG_TEXT_EMOTE = "chatBubbles",
	CHAT_MSG_PARTY = "chatBubblesParty",
	CHAT_MSG_PARTY_LEADER = "chatBubblesParty",
	CHAT_MSG_MONSTER_PARTY = "chatBubblesParty",
	CHAT_MSG_INSTANCE_CHAT = "chatBubblesParty",
	CHAT_MSG_INSTANCE_CHAT_LEADER = "chatBubblesParty",
	CHAT_MSG_RAID = "chatBubblesRaid",
	CHAT_MSG_RAID_LEADER = "chatBubblesRaid",
	CHAT_MSG_RAID_WARNING = "chatBubblesRaid",
}

local function ShouldPollBubbleEvent(event)
	local cvar = bubbleCVars[event]
	if not cvar then
		return false
	end
	if GetCVarBool(cvar) then
		return true
	end
	if cvar == "chatBubblesParty" and event:find("INSTANCE", 1, true) then
		return GetCVarBool("chatBubblesRaid")
	end
	return false
end

local function ApplyEmojisToBubble(chatBubble)
	if not chatBubble or chatBubble:IsForbidden() then
		return
	end

	local frame = chatBubble.GetChildren and chatBubble:GetChildren()
	if not frame or frame:IsForbidden() then
		return
	end

	local str = frame.String
	if not str or not str.GetText or not str.SetText then
		return
	end

	local text = str:GetText()
	if not text or text == "" or F.IsSecret(text) then
		chatBubble.__nexEmojiApplied = nil
		chatBubble.__nexEmojiSrc = nil
		return
	end

	-- Already showing our texture string — skip. Don't key off plain source text;
	-- recycled bubbles reset to :D :kappa: while __nexEmojiSrc still matches.
	if chatBubble.__nexEmojiApplied == text then
		return
	end

	local newText = TransformBubbleBody(text)
	if newText ~= text then
		str:SetText(newText)
		ReflowBubbleString(str)
		chatBubble.__nexEmojiApplied = newText
		chatBubble.__nexEmojiSrc = text
	else
		chatBubble.__nexEmojiApplied = text
		chatBubble.__nexEmojiSrc = nil
	end
end

local function PollChatBubbles()
	if not (cfg and cfg.enable and cfg.bubbles and C_ChatBubbles_GetAllChatBubbles) then
		return
	end

	local bubbles = C_ChatBubbles_GetAllChatBubbles()
	if not bubbles then
		return
	end

	for i = 1, #bubbles do
		ApplyEmojisToBubble(bubbles[i])
	end
end

local function CreateBubbleWorker()
	if bubbleWorker or not C_ChatBubbles_GetAllChatBubbles then
		return
	end

	bubbleWorker = CreateFrame("Frame")
	bubbleWorker:Hide()

	bubbleWorker:SetScript("OnUpdate", function(self, elapsed)
		bubblePollElapsed = bubblePollElapsed + (elapsed or 0)
		if bubblePollElapsed < 0.1 then
			return
		end
		bubblePollElapsed = 0
		PollChatBubbles()
		self:Hide()
	end)

	bubbleWorker:SetScript("OnEvent", function(self, event)
		if not (cfg and cfg.enable and cfg.bubbles) then
			return
		end
		if ShouldPollBubbleEvent(event) then
			bubblePollElapsed = 0
			self:Show()
		end
	end)

	for event in pairs(bubbleCVars) do
		bubbleWorker:RegisterEvent(event)
	end
end

local function SyncBubbleWorker()
	if not bubbleWorker then
		CreateBubbleWorker()
	end
	if bubbleWorker then
		bubbleWorker:Hide()
	end
end

-- ---------------------------------------------------------------------------
-- Public API (Chat Copy)
-- ---------------------------------------------------------------------------
function ChatEmojis:RestorePlainText(msg)
	if not msg or F.IsSecret(msg) then
		return msg
	end
	return gsub(msg, "|H" .. NEXMOJI_SCHEME .. "(.-)|h.-|h", function(encoded)
		return DecodeToken(encoded) or ""
	end)
end

-- ---------------------------------------------------------------------------
-- Message filter
-- ---------------------------------------------------------------------------
local function TransformEmojiFilter(_, event, msg, ...)
	if not cfg or not cfg.enable then
		return
	end
	if F.IsSecret(msg) or type(msg) ~= "string" then
		return
	end

	local newMsg = TransformMessageBody(msg)
	if newMsg == msg then
		return
	end
	return false, newMsg, ...
end

local function InstallMessageFilters()
	if ChatEmojis.filtersInstalled then
		return
	end
	ChatEmojis.filtersInstalled = true

	for i = 1, #MESSAGE_EVENTS do
		ChatFrame_AddMessageEventFilter(MESSAGE_EVENTS[i], TransformEmojiFilter)
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function ChatEmojis:OnEnable()
	cfg = ns.db.chatEmojis
	BuildReplacementList()
	InstallMessageFilters()
	SyncBubbleWorker()
end

function ChatEmojis:OnDisable()
	if bubbleWorker then
		bubbleWorker:Hide()
	end
end

function ChatEmojis:OnSettingChanged(key)
	cfg = ns.db.chatEmojis
	if key == "bubbles" or key == "enable" then
		SyncBubbleWorker()
	end
end

function ChatEmojis:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Chat Emojis"], L["Replace text emoticons like :D and :smile: with emoji textures in chat."])
	local _, bubbleInit = builder:Checkbox(category, self, "bubbles", L["Show in Chat Bubbles"], L["Also replace emoticons in speech bubbles above characters (say, yell, party). Skipped when bubbles are forbidden or text is secret."])
	builder:DependsOn(bubbleInit, enableInit)
end
