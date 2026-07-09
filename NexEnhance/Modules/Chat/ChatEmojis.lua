--[[
	NexEnhance - Chat Emojis
	-------------------------------------------------------------------------
	Replaces :shortcode: tokens and classic ASCII emoticons with inline
	textures from Media/Emojis (Unicode-style names, spaces → underscores).
	Chat log lines embed a hidden nexmoji hyperlink so Chat Copy can recover
	the original text; optional speech bubbles get textures only (no links).

	ChatFrame_AddMessageEventFilter only — hyperlink spans are left alone; plain
	text gets scanned. Bubbles use C_ChatBubbles on a throttled poll.

	Optional autocomplete: type : in chat for Blizzard's AutoComplete dropdown
	(Tab / Enter / click). Literals are longest-match first; :token: aliases map to
	the same textures as Slack-style shortcodes (:smile:, :heart:, …). Source follows
	AutoComplete_Update(text, cursor) — shortcode parsed from text before the cursor.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local byte = string.byte
local format = string.format
local gsub = string.gsub
local strfind, strmatch, strsub, strlower = string.find, string.match, string.sub, string.lower
local strlen = string.len
local tconcat = table.concat
local wipe = wipe
local unpack = unpack
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
		autocomplete = true,
	},
})

local ChatEmojis = ns:NewModule("ChatEmojis", "chatEmojis", { group = "chat", title = L["Chat Emojis"], order = 25 })

local cfg
local entries = {} -- sorted { literal, pattern, textures } built once from DEFINITIONS
local emoticonHintChars = {} -- byte -> true; cheap precheck before ~110-pattern scan
local listReady = false
local autocompleteCatalog = {} -- sorted { token, label } for :name: picker
local autocompleteReady = false
local hookedEditBoxes = {}
local matchScratch = {}

local AC_PRIORITY = (Enum and Enum.AutoCompletePriority and Enum.AutoCompletePriority.Other)
	or LE_AUTOCOMPLETE_PRIORITY_OTHER

-- Blizzard AutoComplete_Update uses UTF-8 cursor for name sources; we slice with
-- byte-based strsub/strlen, so stay on GetCursorPosition (byte index). Mixing
-- GetUTF8CursorPosition with strsub breaks shortcodes after multibyte text.
local function GetEditBoxCursor(editBox)
	return editBox:GetCursorPosition()
end

-- :token must start the line or follow whitespace/punctuation (not URLs or times).
local function GetIncompleteShortcode(beginning)
	if not beginning or beginning == "" then
		return nil
	end
	local code = strmatch(beginning, "^(:[^:][^:]*)$") or strmatch(beginning, "[%s%p](:[^:][^:]*)$")
	if code then
		return code
	end
	if strmatch(beginning, "^:$") or strmatch(beginning, "[%s%p]:$") then
		return ":"
	end
end

local EMOJI_PX = 16
local BUBBLE_EMOJI_PX = 12
-- Blizzard AutoCompleteButtonTemplate is 14px tall — 16px icons clip and look smooshed.
local AC_EMOJI_PX = 14
local AC_EMOJI_YOFFSET = 1
local AC_ROW_HEIGHT = 20
local AC_TOKEN_COLOR = "|cffd0d0d0"
-- Blizzard caps bubble width around 300px; String inset is 16px per side.
local BUBBLE_MAX_TEXT_WIDTH = 268
local NEXMOJI_SCHEME = "nexmoji:"
local NEXMOJI_LINK_PAD = "|cFFffffff|r|h"

-- { literal, texKey } — literal is the raw emoticon text; we escape to a Lua pattern at build.
-- Longest literals win via sort in BuildReplacementList.
local DEFINITIONS = {
	-- :shortcode: (Slack / CLDR style)
	{ ":smile:", "Grinning_Face_with_Big_Eyes" },
	{ ":joy:", "Face_with_Tears_of_Joy" },
	{ ":laughing:", "Grinning_Squinting_Face" },
	{ ":wink:", "Winking_Face" },
	{ ":blush:", "Smiling_Face_with_Smiling_Eyes" },
	{ ":heart_eyes:", "Smiling_Face_with_Heart_Eyes" },
	{ ":kissing_heart:", "Face_Blowing_a_Kiss" },
	{ ":kissing:", "Kissing_Face" },
	{ ":yum:", "Face_Savoring_Food" },
	{ ":relieved:", "Relieved_Face" },
	{ ":sweat_smile:", "Smiling_Face_with_Sweat" },
	{ ":heart:", "Red_Heart" },
	{ ":broken_heart:", "Broken_Heart" },
	{ ":thumbsup:", "Thumbs_Up" },
	{ ":+1:", "Thumbs_Up" },
	{ ":thumbsdown:", "Thumbs_Down" },
	{ ":-1:", "Thumbs_Down" },
	{ ":wave:", "Waving_Hand" },
	{ ":ok_hand:", "OK_Hand" },
	{ ":sparkles:", "Sparkles" },
	{ ":warning:", "Warning" },
	{ ":eyes:", "Eyes" },
	-- Unicode-style :name: (filename stems)
	{ ":slightly_smiling_face:", "Slightly_Smiling_Face" },
	{ ":slightly_frowning_face:", "Slightly_Frowning_Face" },
	{ ":crying_face:", "Crying_Face" },
	{ ":angry_face:", "Angry_Face" },
	{ ":angry:", "Angry_Face" },
	{ ":rage:", "Face_with_Symbols_on_Mouth" },
	{ ":open_mouth:", "Face_with_Open_Mouth" },
	{ ":expressionless:", "Expressionless_Face" },
	{ ":confused:", "Confused_Face" },
	{ ":stuck_out_tongue:", "Face_with_Tongue" },
	{ ":stuck_out_tongue_winking_eye:", "Winking_Face_with_Tongue" },
	-- Class icons (13 classes + common aliases)
	{ ":death_knight:", "Death_knight" },
	{ ":deathknight:", "Death_knight" },
	{ ":dk:", "Death_knight" },
	{ ":demon_hunter:", "Demon_hunter" },
	{ ":demonhunter:", "Demon_hunter" },
	{ ":dh:", "Demon_hunter" },
	{ ":druid:", "Druid" },
	{ ":evoker:", "Evoker" },
	{ ":hunter:", "Hunter" },
	{ ":mage:", "Mage" },
	{ ":monk:", "Monk" },
	{ ":paladin:", "Paladin" },
	{ ":pally:", "Paladin" },
	{ ":priest:", "Priest" },
	{ ":rogue:", "Rogue" },
	{ ":shaman:", "Shaman" },
	{ ":shammy:", "Shaman" },
	{ ":warlock:", "Warlock" },
	{ ":lock:", "Warlock" },
	{ ":warrior:", "Warrior" },
	{ ":warr:", "Warrior" },
	-- ASCII — happy / affectionate
	{ ":-)", "Slightly_Smiling_Face" },
	{ ":)", "Slightly_Smiling_Face" },
	{ "=:)", "Slightly_Smiling_Face" },
	{ "=-)", "Slightly_Smiling_Face" },
	{ "=)", "Slightly_Smiling_Face" },
	{ ":-D", "Grinning_Face_with_Big_Eyes" },
	{ ":D", "Grinning_Face_with_Big_Eyes" },
	{ "=-D", "Grinning_Face_with_Big_Eyes" },
	{ "=D", "Grinning_Face_with_Big_Eyes" },
	{ "xD", "Face_with_Tears_of_Joy" },
	{ "XD", "Face_with_Tears_of_Joy" },
	{ ":'-)", "Face_with_Tears_of_Joy" },
	{ string.char(58, 39, 41), "Face_with_Tears_of_Joy" }, -- :') happy tears, no nose
	{ ";-)", "Winking_Face" },
	{ ";)", "Winking_Face" },
	{ ";-P", "Winking_Face_with_Tongue" },
	{ ";P", "Winking_Face_with_Tongue" },
	{ ":-P", "Face_with_Tongue" },
	{ ":P", "Face_with_Tongue" },
	{ "=-P", "Face_with_Tongue" },
	{ "=P", "Face_with_Tongue" },
	{ ":-p", "Face_with_Tongue" },
	{ ":p", "Face_with_Tongue" },
	{ "=-p", "Face_with_Tongue" },
	{ "=p", "Face_with_Tongue" },
	{ ":-*", "Face_Blowing_a_Kiss" },
	{ ":*", "Face_Blowing_a_Kiss" },
	{ "=-*", "Face_Blowing_a_Kiss" },
	{ "=*", "Face_Blowing_a_Kiss" },
	{ "<3", "Red_Heart" },
	{ "♥", "Red_Heart" },
	{ "</3", "Broken_Heart" },
	-- ASCII — sad / angry
	{ ":-(", "Slightly_Frowning_Face" },
	{ ":(", "Slightly_Frowning_Face" },
	{ "=-(", "Slightly_Frowning_Face" },
	{ "=(", "Slightly_Frowning_Face" },
	{ ":'-(", "Crying_Face" },
	{ ":'(", "Crying_Face" },
	{ '=("', "Crying_Face" },
	{ "='-(", "Crying_Face" },
	{ ">:-(", "Angry_Face" },
	{ ">:(", "Angry_Face" },
	{ ">=-(", "Angry_Face" },
	{ ">=(", "Angry_Face" },
	{ ":-@", "Face_with_Symbols_on_Mouth" },
	{ ":@", "Face_with_Symbols_on_Mouth" },
	{ "=-@", "Face_with_Symbols_on_Mouth" },
	{ "=@", "Face_with_Symbols_on_Mouth" },
	-- ASCII — shocked / neutral
	{ ":-O", "Face_with_Open_Mouth" },
	{ ":O", "Face_with_Open_Mouth" },
	{ ":-o", "Face_with_Open_Mouth" },
	{ ":o", "Face_with_Open_Mouth" },
	{ "-_-", "Expressionless_Face" },
	{ "o_O", "Confused_Face" },
	{ "O_o", "Confused_Face" },
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
-- Build sorted replacement list (longest literal first)
-- ---------------------------------------------------------------------------
local function EscapeLuaPattern(literal)
	return (gsub(literal, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

local function RegisterHintChars(literal)
	for j = 1, #literal do
		emoticonHintChars[strsub(literal, j, j)] = true
	end
end

local function SegmentMightHaveEmoticon(segment)
	-- Incident (ChatEmojis, Jul 2026): scanning every ':' (timestamps, Player: msg) +
	-- broken :* regex froze the client — only enter the pattern loop when a known byte appears.
	for i = 1, #segment do
		if emoticonHintChars[strsub(segment, i, i)] then
			return true
		end
	end
	return false
end

local function BuildReplacementList()
	if listReady then
		return
	end
	listReady = true
	wipe(emoticonHintChars)

	local n = 0
	for i = 1, #DEFINITIONS do
		local literal, texKey = DEFINITIONS[i][1], DEFINITIONS[i][2]
		if literal and texKey then
			local path = C.Media.Emojis[texKey]
			if path then
				n = n + 1
				entries[n] = {
					literal = literal,
					pattern = EscapeLuaPattern(literal),
					chatTexture = F.ChatTexture(path, EMOJI_PX, EMOJI_PX),
					bubbleTexture = F.ChatTexture(path, BUBBLE_EMOJI_PX, BUBBLE_EMOJI_PX),
				}
				RegisterHintChars(literal)
			end
		end
	end

	table.sort(entries, function(a, b)
		return #a.literal > #b.literal
	end)
end

-- ---------------------------------------------------------------------------
-- Autocomplete catalog (:name: tokens only; one entry per texture)
-- ---------------------------------------------------------------------------
local function FormatAutocompleteLabel(path, token)
	local icon = F.ChatTexture(path, AC_EMOJI_PX, AC_EMOJI_PX, 0, AC_EMOJI_YOFFSET)
	return icon .. "  " .. AC_TOKEN_COLOR .. token .. "|r"
end

local acLayoutHooked = false

local function InstallAutocompleteLayoutHook()
	if acLayoutHooked then
		return
	end
	acLayoutHooked = true

	-- Blizzard sizes rows at 14px; our emoji rows need headroom for 14px icons + GameFontNormal.
	hooksecurefunc("AutoComplete_UpdateResults", function(box, results)
		if not ChatEmojis:IsEnabled() or not (cfg and cfg.autocomplete) then
			return
		end
		local isEmoji = results and results[1] and results[1].insertToken
		if not isEmoji then
			return
		end
		local rowH = AC_ROW_HEIGHT
		local maxButtons = AUTOCOMPLETE_MAX_BUTTONS or 5
		local numShown = 0

		for i = 1, maxButtons do
			local button = _G["AutoCompleteButton" .. i]
			if button then
				button:SetHeight(rowH)
				local fs = button:GetFontString()
				if fs then
					fs:ClearAllPoints()
					fs:SetPoint("LEFT", button, "LEFT", 10, 0)
				end
				if button:IsShown() then
					numShown = numShown + 1
				end
			end
		end

		if numShown > 0 and box and box:IsShown() then
			box:SetHeight(numShown * rowH + 35)
		end
	end)
end

local function BuildAutocompleteCatalog()
	if autocompleteReady then
		return
	end
	autocompleteReady = true

	local seenTex = {}
	for i = 1, #DEFINITIONS do
		local literal, texKey = DEFINITIONS[i][1], DEFINITIONS[i][2]
		if literal and texKey and strmatch(literal, "^:[^:]+:$") and not seenTex[texKey] then
			local path = C.Media.Emojis[texKey]
			if path then
				seenTex[texKey] = true
				autocompleteCatalog[#autocompleteCatalog + 1] = {
					token = literal,
					label = FormatAutocompleteLabel(path, literal),
				}
			end
		end
	end

	table.sort(autocompleteCatalog, function(a, b)
		return a.token < b.token
	end)
end

local function GetEmojiAutoCompleteMatches(text, maxResults, cursorPosition)
	wipe(matchScratch)
	if not text or text == "" then
		return matchScratch
	end

	maxResults = maxResults or (AUTOCOMPLETE_MAX_BUTTONS or 5)
	local beginning = strsub(text, 1, cursorPosition or strlen(text))
	local shortCode = GetIncompleteShortcode(beginning)
	if not shortCode then
		return matchScratch
	end

	local q = strlower(shortCode)
	local n = 0
	for i = 1, #autocompleteCatalog do
		local entry = autocompleteCatalog[i]
		if strfind(strlower(entry.token), q, 1, true) == 1 then
			n = n + 1
			matchScratch[n] = {
				name = entry.label,
				priority = AC_PRIORITY,
				insertToken = entry.token,
			}
			if n >= maxResults then
				break
			end
		end
	end
	return matchScratch
end

-- Forward declarations — CompleteEmojiToken calls ClearEmojiAutocomplete on complete.
local ClearEmojiAutocomplete, ActivateEmojiAutocomplete, CompleteEmojiToken

ClearEmojiAutocomplete = function(editBox)
	if not editBox or not editBox.__nexEmojiACActive then
		return
	end
	AutoCompleteEditBox_SetCustomAutoCompleteFunction(editBox, editBox.__nexSavedAutoCompleteFn)
	local savedSource = editBox.__nexSavedACSource
	local savedParams = editBox.__nexSavedACParams
	if savedSource then
		AutoCompleteEditBox_SetAutoCompleteSource(editBox, savedSource, unpack(savedParams or {}))
	else
		AutoCompleteEditBox_SetAutoCompleteSource(editBox, nil)
	end
	AutoComplete_HideIfAttachedTo(editBox)
	editBox.__nexEmojiACActive = nil
end

ActivateEmojiAutocomplete = function(editBox)
	if not editBox.__nexEmojiACActive then
		editBox.__nexSavedACSource = editBox.autoCompleteSource
		editBox.__nexSavedACParams = editBox.autoCompleteParams
		editBox.__nexSavedAutoCompleteFn = editBox.customAutoCompleteFunction
	end
	AutoCompleteEditBox_SetAutoCompleteSource(editBox, GetEmojiAutoCompleteMatches)
	AutoCompleteEditBox_SetCustomAutoCompleteFunction(editBox, CompleteEmojiToken)
	editBox.__nexEmojiACActive = true
	AutoComplete_Update(editBox, editBox:GetText(), GetEditBoxCursor(editBox))
end

CompleteEmojiToken = function(editBox, _, nameInfo)
	local token = nameInfo and nameInfo.insertToken
	if not token then
		return false
	end

	local cursorPosition = GetEditBoxCursor(editBox)
	local text = editBox:GetText()
	local beginning = strsub(text, 1, cursorPosition)
	local incomplete = GetIncompleteShortcode(beginning)
	if not incomplete then
		return false
	end

	local startPos = strlen(beginning) - strlen(incomplete) + 1
	local newBeginning = strsub(beginning, 1, startPos - 1) .. token .. " "
	local newText = newBeginning .. strsub(text, cursorPosition + 1)
	local newCursor = strlen(newBeginning)

	-- SetText fires OnTextChanged before the cursor moves; ignore it so we do not
	-- re-open autocomplete on the stale partial token (e.g. :poo while inserting :poop:).
	editBox.ignoreTextChange = true
	editBox:SetText(newText)
	editBox:SetCursorPosition(newCursor)
	editBox.ignoreTextChange = nil
	ClearEmojiAutocomplete(editBox)
	return true
end

local function OnEditBoxTextChanged(editBox, userInput)
	if editBox.ignoreTextChange then
		return
	end
	if editBox.disallowAutoComplete then
		ClearEmojiAutocomplete(editBox)
		return
	end
	if not cfg or not cfg.enable or not cfg.autocomplete then
		return
	end

	local text = editBox:GetText()
	local cursorPosition = GetEditBoxCursor(editBox)
	local beginning = strsub(text, 1, cursorPosition)
	local shortCode = GetIncompleteShortcode(beginning)

	-- Blizzard skips autocomplete on programmatic SetText; still react to paste or
	-- clearing a prior emoji dropdown when the incomplete token is removed.
	if not userInput and not shortCode and not editBox.__nexEmojiACActive then
		return
	end

	if shortCode then
		ActivateEmojiAutocomplete(editBox)
	else
		ClearEmojiAutocomplete(editBox)
	end
end

local function SetupEditBoxAutocomplete(editBox)
	if not editBox or not editBox.HookScript or editBox.__nexEmojiAutoCompleteHooked then
		return
	end
	editBox.__nexEmojiAutoCompleteHooked = true
	hookedEditBoxes[#hookedEditBoxes + 1] = editBox
	editBox:HookScript("OnTextChanged", OnEditBoxTextChanged)
end

local function InstallEditBoxAutocomplete()
	if not (cfg and cfg.enable and cfg.autocomplete) then
		return
	end
	BuildAutocompleteCatalog()
	InstallAutocompleteLayoutHook()

	for i = 1, NUM_CHAT_WINDOWS do
		local editBox = _G["ChatFrame" .. i .. "EditBox"]
		if editBox then
			SetupEditBoxAutocomplete(editBox)
		end
	end

	if CHAT_FRAMES then
		for _, frameName in ipairs(CHAT_FRAMES) do
			local frame = _G[frameName]
			local editBox = frame and (frame.editBox or _G[frameName .. "EditBox"])
			if editBox then
				SetupEditBoxAutocomplete(editBox)
			end
		end
	end
end

local function TeardownEditBoxAutocomplete()
	for i = 1, #hookedEditBoxes do
		ClearEmojiAutocomplete(hookedEditBoxes[i])
	end
end

-- ---------------------------------------------------------------------------
-- Plain-segment replacement
-- ---------------------------------------------------------------------------
local function ReplaceInSegment(segment, useLinks, textureKey)
	if not SegmentMightHaveEmoticon(segment) then
		return segment
	end

	for i = 1, #entries do
		local entry = entries[i]
		local literal = entry.literal
		local pat = entry.pattern
		local tex = entry[textureKey]
		-- Plain search first — avoids catastrophic backtracking on patterns like :*
		if tex and strfind(segment, literal, 1, true) then
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

	-- Hidden frames do not receive OnUpdate — Show() arms a one-shot poll, Hide() sleeps.
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
end

local function EnsureBubbleWorkerEvents()
	if not bubbleWorker then
		return
	end
	for event in pairs(bubbleCVars) do
		bubbleWorker:RegisterEvent(event)
	end
end

local function TearDownBubbleWorker()
	if not bubbleWorker then
		return
	end
	bubbleWorker:UnregisterAllEvents()
	bubbleWorker:Hide()
end

local function SyncBubbleWorker()
	if not (cfg and cfg.enable and cfg.bubbles) then
		TearDownBubbleWorker()
		return
	end
	if not bubbleWorker then
		CreateBubbleWorker()
	end
	EnsureBubbleWorkerEvents()
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
	InstallEditBoxAutocomplete()
	ns:RegisterCallback("Chat.EditBoxRegistered", SetupEditBoxAutocomplete)
end

function ChatEmojis:OnDisable()
	TearDownBubbleWorker()
	TeardownEditBoxAutocomplete()
	ns:UnregisterCallback("Chat.EditBoxRegistered", SetupEditBoxAutocomplete)
end

function ChatEmojis:OnSettingChanged(key)
	cfg = ns.db.chatEmojis
	if key == "bubbles" or key == "enable" then
		SyncBubbleWorker()
	end
	if key == "autocomplete" or key == "enable" then
		if cfg.enable and cfg.autocomplete then
			InstallEditBoxAutocomplete()
		else
			TeardownEditBoxAutocomplete()
		end
	end
end

function ChatEmojis:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Chat Emojis"], L["Replace text emoticons like :D and :smile: with emoji textures in chat."])
	local _, bubbleInit = builder:Checkbox(category, self, "bubbles", L["Show in Chat Bubbles"], L["Also replace emoticons in speech bubbles above characters (say, yell, party). Skipped when bubbles are forbidden or text is secret."])
	local _, acInit = builder:Checkbox(category, self, "autocomplete", L["Emoji Autocomplete"], L["Type : in chat to pick :name: emojis from a list. Tab, Enter, or click to insert."])
	builder:DependsOn(bubbleInit, enableInit)
	builder:DependsOn(acInit, enableInit)
end
