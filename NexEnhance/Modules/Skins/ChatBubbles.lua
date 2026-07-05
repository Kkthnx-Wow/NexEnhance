--[[
	NexEnhance - Chat Bubbles (skin)
	-------------------------------------------------------------------------
	Replaces the default chat-bubble art with the game's tooltip border and
	dark fill, matching the chat edit box, tinted per channel.

	Bubbles are created on demand and recycled — we poll C_ChatBubbles on a
	throttled OnUpdate (chat events arm the worker) and skin anything new.
	Purely cosmetic; no taint.

	Recycled bubbles often keep the previous channel's FontString colour
	(party blue on instance chat is the classic). We record recent messages
	from chat events and match ChatTypeInfo instead of trusting GetTextColor().
--]]

local _, ns = ...
local F, L = ns.F, ns.L

local ipairs, pairs, tinsert, tremove = ipairs, pairs, table.insert, table.remove
local gsub = string.gsub
local CreateFrame = CreateFrame
local GetCVarBool = GetCVarBool
local GetTime = GetTime
local ChatTypeInfo = ChatTypeInfo
local ChatTypeGroupInverted = ChatTypeGroupInverted
local C_ChatBubbles_GetAllChatBubbles = C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles

ns:RegisterDefaults({
	chatBubbles = {
		enable = true,
	},
})

local ChatBubbles = ns:NewModule("ChatBubbles", "chatBubbles", { group = "skins", title = L["Chat Bubbles"], order = 30 })

-- Blizzard CVars that gate which bubble types appear; used to start the poll worker.
local BUBBLE_EVENT_CVARS = {
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

local PENDING_MAX = 10
local PENDING_TTL = 6
local pendingMessages = {}

local function ShouldPollForEvent(event)
	local cvar = BUBBLE_EVENT_CVARS[event]
	if not cvar then
		return false
	end
	if GetCVarBool(cvar) then
		return true
	end
	-- Instance chat bubbles follow the party toggle on most clients; also honour raid.
	if cvar == "chatBubblesParty" and event:find("INSTANCE", 1, true) then
		return GetCVarBool("chatBubblesRaid")
	end
	return false
end

local function StripInlineTextures(text)
	return gsub(text, "|T.-|t", "")
end

local function NormalizeBubbleText(text)
	if not text or text == "" then
		return ""
	end
	text = F.StripColorCodes(text)
	text = StripInlineTextures(text)
	return text
end

local function GetChatTypeColor(chatType)
	if not chatType then
		return
	end
	local info = ChatTypeInfo and ChatTypeInfo[chatType]
	if info and info.r then
		return info.r, info.g, info.b
	end
end

local function RecordBubbleMessage(event, message)
	if not message or message == "" or F.IsSecret(message) then
		return
	end
	if not ChatTypeGroupInverted then
		return
	end

	local chatType = ChatTypeGroupInverted[event]
	if not chatType then
		return
	end

	tinsert(pendingMessages, 1, {
		chatType = chatType,
		text = NormalizeBubbleText(message),
		time = GetTime(),
	})
	while #pendingMessages > PENDING_MAX do
		tremove(pendingMessages)
	end
end

local function MatchPendingMessage(chatBubble, displayKey, emojiSrcKey)
	local now = GetTime()
	for i = 1, #pendingMessages do
		local entry = pendingMessages[i]
		if now - entry.time > PENDING_TTL then
			break
		end
		if entry.text == displayKey or (emojiSrcKey and entry.text == emojiSrcKey) then
			tremove(pendingMessages, i)
			return entry.chatType
		end
	end
end

local function ResolveBubbleChatType(chatBubble, displayText)
	if not displayText or displayText == "" or F.IsSecret(displayText) then
		chatBubble.__nexBubbleKey = nil
		chatBubble.__nexChatType = nil
		return nil
	end

	local displayKey = NormalizeBubbleText(displayText)
	local emojiSrcKey = chatBubble.__nexEmojiSrc and NormalizeBubbleText(chatBubble.__nexEmojiSrc)
	if displayKey == "" and emojiSrcKey and emojiSrcKey ~= "" then
		displayKey = emojiSrcKey
	end

	if chatBubble.__nexBubbleKey == displayKey and chatBubble.__nexChatType then
		return chatBubble.__nexChatType
	end

	local chatType = MatchPendingMessage(chatBubble, displayKey, emojiSrcKey)
	chatBubble.__nexBubbleKey = displayKey
	chatBubble.__nexChatType = chatType
	return chatType
end

local function UpdateBubbleColors(chatBubble, frame, chatType)
	local str = frame.String
	local r, g, b = GetChatTypeColor(chatType)

	if not r and str and str.GetTextColor then
		local tr, tg, tb = str:GetTextColor()
		r, g, b = tr, tg, tb
	end

	r, g, b = r or 1, g or 1, b or 1

	if str and str.SetTextColor then
		str:SetTextColor(r, g, b)
	end

	local bg = chatBubble.__nexBG
	if bg then
		bg:SetBackdropBorderColor(r, g, b)
	end
end

local function ReskinBubble(chatBubble)
	if not chatBubble or chatBubble:IsForbidden() then
		return
	end

	local frame = chatBubble.GetChildren and chatBubble:GetChildren()
	if not frame or frame:IsForbidden() then
		return
	end

	if not chatBubble.__nexStyled then
		frame:DisableDrawLayer("BORDER")
		frame:DisableDrawLayer("BACKGROUND")
		if frame.Tail then
			frame.Tail:SetAlpha(0)
		end

		local bg = CreateFrame("Frame", nil, chatBubble)
		local level = frame:GetFrameLevel()
		bg:SetFrameLevel(level > 0 and level - 1 or 0)
		bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
		bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
		F.CreateTooltipBackdrop(bg, { edgeSize = 8 })

		chatBubble.__nexBG = bg.nexBackdrop
		chatBubble.__nexStyled = true
	end

	local str = frame.String
	local text = str and str.GetText and str:GetText()
	local chatType = ResolveBubbleChatType(chatBubble, text)
	UpdateBubbleColors(chatBubble, frame, chatType)
end

local worker
local function CreateWorker()
	if worker or not C_ChatBubbles_GetAllChatBubbles then
		return
	end

	worker = CreateFrame("Frame")
	worker:Hide()

	local elapsed = 0
	worker:SetScript("OnUpdate", function(self, e)
		elapsed = elapsed + (e or 0)
		if elapsed < 0.1 then
			return
		end
		elapsed = 0

		local bubbles = C_ChatBubbles_GetAllChatBubbles()
		if bubbles then
			for i = 1, #bubbles do
				ReskinBubble(bubbles[i])
			end
		end
		self:Hide()
	end)

	worker:SetScript("OnEvent", function(self, event, message)
		if not ShouldPollForEvent(event) then
			return
		end
		RecordBubbleMessage(event, message)
		elapsed = 0
		self:Show()
	end)

	for event in pairs(BUBBLE_EVENT_CVARS) do
		worker:RegisterEvent(event)
	end
end

local FONT_REDUCTION = 4
local function ShrinkBubbleFont()
	local font = _G.ChatBubbleFont
	if not font or ChatBubbles.fontResized then
		return
	end

	local fontFile, fontSize, fontFlags = font:GetFont()
	if fontFile and fontSize then
		font:SetFont(fontFile, math.max(fontSize - FONT_REDUCTION, 8), fontFlags)
		ChatBubbles.fontResized = true
	end
end

function ChatBubbles:OnEnable()
	if not ns.db.chatBubbles.enable then
		return
	end
	CreateWorker()
	ShrinkBubbleFont()
end

function ChatBubbles:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Chat Bubble Border"], L["Give chat bubbles a clean Blizzard-style border (reload to disable)."])
end
