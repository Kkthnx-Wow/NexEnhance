--[[
	NexEnhance - Chat Filter
	-------------------------------------------------------------------------
	Cuts chat spam and decorates item links:
	  * Keyword filter - hides messages that match enough blacklisted keywords
	    (with an optional per-channel whitelist).
	  * Repeat filter - hides near-identical messages from the same sender using
	    a normalized Levenshtein distance (catches reworded gold/boost spam).
	  * Block strangers - hides whispers from anyone not a friend/guildie/group.
	  * Block spammers - hides everything from a sender once they trip the
	    filters enough times in a session.
	  * Chat item level - appends the item level (and gem sockets) to item links
	    posted in chat.

	Keyword/whitelist tables are account-wide (ns.global) and editable in Filters
	settings or via /nexfilter. Message reads are secret-gated.
--]]

local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local pairs = pairs
local gsub, strmatch, strrep, strlower = string.gsub, string.match, string.rep, string.lower
local strfind = string.find
local min, max, tremove = math.min, math.max, table.remove
local sort = table.sort
local tconcat = table.concat
local wipe = wipe
local GetTime, Ambiguate = GetTime, Ambiguate
local IsGuildMember = IsGuildMember
local C_PartyInfo_IsGUIDInGroup = C_PartyInfo and C_PartyInfo.IsGUIDInGroup
local ChatFrame_AddMessageEventFilter = ChatFrame_AddMessageEventFilter
local C_FriendList_IsFriend = C_FriendList.IsFriend
local C_BattleNet_GetGameAccountInfoByGUID = C_BattleNet.GetGameAccountInfoByGUID
local C_Item_GetItemInfo = C_Item.GetItemInfo
local C_Item_GetItemStats = C_Item.GetItemStats
local Enum = Enum

ns:RegisterDefaults({
	chatFilter = {
		enable = false,
		spamFilter = true,
		blockStranger = false,
		blockSpammer = true,
		matches = 3,
		chatItemLevel = true,
	},
})

-- Account-wide keyword tables (sets keyed by the keyword), edited in settings or /nexfilter.
ns:RegisterDefaults({
	chatFilter = {
		keywords = {},
		whitelist = {},
		keywordVersion = 0,
	},
}, "global")

local ChatFilter = ns:NewModule("ChatFilter", "chatFilter", { group = "filters", title = L["Chat Filter"], order = 10 })

-- Predefined spam keywords (stored lowercase; matching is case-insensitive). A line
-- must hit `matches` of these before it is hidden (default 3). Curated from
-- current Midnight services/trade boosting spam: WTS carries, M+, raid bundles,
-- gold-only payment lines, commercial site links, and copy-paste booking CTAs.
-- Bump DEFAULT_KEYWORD_VERSION when adding new defaults for existing installs.
local DEFAULT_KEYWORD_VERSION = 1
local DEFAULT_KEYWORDS = {
	-- WTS markers
	["wts"] = true,
	["<<wts>>"] = true,
	["<wts>"] = true,
	["[wts]"] = true,
	["-wts-"] = true,

	-- Payment / gold-only boosting
	["gold only"] = true,
	["only accept gold"] = true,
	["pay in raid"] = true,
	["trade in raid"] = true,
	["trade gold in raid"] = true,

	-- Mythic+ / dungeon carries
	["mythic+"] = true,
	["mythic keystone"] = true,
	["m+ carry"] = true,
	["timed guarantee"] = true,
	["armor stack"] = true,
	["specific key"] = true,
	["discount on multi"] = true,
	["crest farming"] = true,
	["free reruns"] = true,
	["loot traders"] = true,
	["mega dungeon"] = true,

	-- Keystone achievements / io spam
	["ksm"] = true,
	["ksh"] = true,
	["ksl"] = true,
	["ksmythic"] = true,
	["3400io"] = true,

	-- Leveling services
	["power lvl"] = true,
	["power level"] = true,
	["afk level"] = true,
	["1-90"] = true,
	["10-80"] = true,
	["80-90"] = true,
	["1>90"] = true,

	-- Raid boosting
	["saved heroic"] = true,
	["hc unsaved"] = true,
	["unsaved vip"] = true,
	["vip loot"] = true,
	["loot prio"] = true,
	["lootrun"] = true,
	["loot run"] = true,
	["aotc"] = true,
	["bundle discount"] = true,
	["bundle run"] = true,
	["mythic raid"] = true,
	["full run"] = true,
	["all loot is up for roll"] = true,
	["single kills"] = true,
	["single boss"] = true,
	["mount runs"] = true,
	["mount run"] = true,

	-- Commercial / external links
	["wowvendor"] = true,
	["trustpilot"] = true,
	["discord.gg"] = true,
	["price match"] = true,
	["24/7 support"] = true,
	["24/7 schedule"] = true,
	["instant start"] = true,

	-- Booking / whisper spam
	["/w to book"] = true,
	["/w me for spots"] = true,
	["/w for info"] = true,
	["pst for more"] = true,
	["pm for booking"] = true,
	["check prices"] = true,
	["book now"] = true,
	["whisper me for prices"] = true,

	-- TCG / mount sellers
	["tcg seller"] = true,

	-- Common spam phrases
	["boosting"] = true,
	["carry service"] = true,
	["best service"] = true,
	["going now"] = true,
	["join us now"] = true,
	["no waiting"] = true,
}

local function MergeDefaultKeywords()
	local chatGlobal = ns.global and ns.global.chatFilter
	if not chatGlobal then
		return
	end
	local version = chatGlobal.keywordVersion or 0
	if version >= DEFAULT_KEYWORD_VERSION then
		return
	end
	chatGlobal.keywords = chatGlobal.keywords or {}
	for keyword in pairs(DEFAULT_KEYWORDS) do
		chatGlobal.keywords[keyword] = true
	end
	chatGlobal.keywordVersion = DEFAULT_KEYWORD_VERSION
end

local keywordSortScratch = {}

local function SerializeKeywordSet(set)
	wipe(keywordSortScratch)
	for keyword in pairs(set) do
		if keyword ~= "" then
			keywordSortScratch[#keywordSortScratch + 1] = keyword
		end
	end
	sort(keywordSortScratch)
	return tconcat(keywordSortScratch, "\n")
end

local function ApplyKeywordText(text, set)
	wipe(set)
	for line in (text or ""):gmatch("[^\r\n]+") do
		local keyword = strlower(line:match("^%s*(.-)%s*$") or "")
		if keyword ~= "" then
			set[keyword] = true
		end
	end
end

local function RestoreDefaultKeywords()
	local set = ns.global.chatFilter.keywords
	set = set or {}
	ns.global.chatFilter.keywords = set
	for keyword in pairs(DEFAULT_KEYWORDS) do
		set[keyword] = true
	end
	ns.global.chatFilter.keywordVersion = DEFAULT_KEYWORD_VERSION
end

local MyName = C.Player.name

-- ---------------------------------------------------------------------------
-- Spam filtering
-- ---------------------------------------------------------------------------
local BadBoys = {} -- [name] = times filtered this session
local chatLines, prevLineID = {}, 0
local filterResult ---@type any
local last, this = {}, {} -- reused Levenshtein rows (no per-call allocation)
local rowPool = {}
-- Shared with Modules/Chat/Chat.lua so whispers hidden by this filter do not
-- still trigger the optional whisper sound in the same event pass.
ns.ChatMuteCache = ns.ChatMuteCache or {}
local MuteCache = ns.ChatMuteCache

local function AcquireChatLine(name, timestamp)
	local row = tremove(rowPool)
	if row then
		row[1], row[3] = name, timestamp
		wipe(row[2])
	else
		row = { name, {}, timestamp }
	end
	return row
end

local function ReleaseChatLine(row)
	if not row then
		return
	end
	row[1], row[3] = nil, nil
	wipe(row[2])
	rowPool[#rowPool + 1] = row
end

-- Normalized edit distance between two byte arrays (0 = identical, 1 = totally
-- different). Reuses module-level rows to avoid GC churn.
local function CompareStrDiff(sA, sB)
	local lenA, lenB = #sA, #sB
	if lenA == 0 or lenB == 0 then
		return 1
	end

	for j = 0, lenB do
		last[j + 1] = j
	end
	for i = 1, lenA do
		this[1] = i
		for j = 1, lenB do
			this[j + 1] = (sA[i] == sB[j]) and last[j] or (min(last[j + 1], this[j], last[j]) + 1)
		end
		for j = 0, lenB do
			last[j + 1] = this[j + 1]
		end
	end
	return this[lenB + 1] / max(lenA, lenB)
end

local function GetFilterResult(event, msg, name, flag, guid)
	local cfg = ns.db.chatFilter

	-- Never filter yourself, GMs or developers.
	if name == MyName or (event == "CHAT_MSG_WHISPER" and flag == "GM") or flag == "DEV" then
		return
	end

	-- Never filter people you know.
	if guid and F.NotSecret(guid) and guid ~= "" and (IsGuildMember(guid) or C_BattleNet_GetGameAccountInfoByGUID(guid) or C_FriendList_IsFriend(guid) or (C_PartyInfo_IsGUIDInGroup and C_PartyInfo_IsGUIDInGroup(guid))) then
		return
	end

	if cfg.blockStranger and event == "CHAT_MSG_WHISPER" then
		MuteCache[name] = GetTime()
		return true
	end

	if cfg.blockSpammer and BadBoys[name] and BadBoys[name] >= 5 then
		return true
	end

	if not cfg.spamFilter then
		return
	end

	-- Strip hyperlinks and colour codes down to plain text for matching.
	local filterMsg = gsub(msg, "|H.-|h(.-)|h", "%1")
	filterMsg = gsub(filterMsg, "|c%x%x%x%x%x%x%x%x", "")
	filterMsg = gsub(filterMsg, "|C%x%x%x%x%x%x%x%x", "")
	filterMsg = gsub(filterMsg, "|r", "")
	filterMsg = gsub(filterMsg, "|R", "")
	filterMsg = strlower(filterMsg)

	local keywords = ns.global.chatFilter.keywords
	local whitelist = ns.global.chatFilter.whitelist

	-- Channel whitelist: if a whitelist exists and the line matches none of it,
	-- drop it (without counting the sender as a spammer).
	if event == "CHAT_MSG_CHANNEL" then
		local matches, found = 0, false
		for keyword in pairs(whitelist) do
			if keyword ~= "" then
				found = true
				-- Plain (literal) substring match so keywords containing Lua
				-- magic characters (%, [, ], -, ...) can't error or over-match.
				if strfind(filterMsg, keyword, 1, true) then
					matches = matches + 1
				end
			end
		end
		if matches == 0 and found then
			return 0
		end
	end

	-- Keyword blacklist.
	local matches = 0
	for keyword in pairs(keywords) do
		if keyword ~= "" then
			if strfind(filterMsg, keyword, 1, true) then
				matches = matches + 1
			end
		end
	end
	if matches >= cfg.matches then
		return true
	end

	-- Repeat filter: compare against recent lines from the same sender.
	local msgTable = AcquireChatLine(name, GetTime())
	if filterMsg == "" then
		filterMsg = msg
	end
	for i = 1, #filterMsg do
		msgTable[2][i] = filterMsg:byte(i)
	end

	local size = #chatLines
	chatLines[size + 1] = msgTable
	for i = 1, size do
		local line = chatLines[i]
		if line[1] == msgTable[1] and ((event == "CHAT_MSG_CHANNEL" and msgTable[3] - line[3] < 0.6) or CompareStrDiff(line[2], msgTable[2]) <= 0.1) then
			ReleaseChatLine(tremove(chatLines, i))
			return true
		end
	end
	if size >= 30 then
		ReleaseChatLine(tremove(chatLines, 1))
	end
end

local function UpdateChatFilter(_, event, msg, author, _, _, _, flag, _, _, _, _, lineID, guid)
	if not ns.db.chatFilter.enable or F.IsSecret(msg) then
		return
	end

	-- One result per chat line, shared across all chat frames showing it.
	if lineID ~= prevLineID then
		prevLineID = lineID
		if F.IsSecret(author) then
			filterResult = nil
		else
			local name = Ambiguate(author, "none")
			filterResult = GetFilterResult(event, msg, name, flag, guid)
			if filterResult and filterResult ~= 0 then
				BadBoys[name] = (BadBoys[name] or 0) + 1
			end
			if filterResult == 0 then
				filterResult = true
			end
		end
	end

	return filterResult
end

-- ---------------------------------------------------------------------------
-- Item level on chat hyperlinks
-- ---------------------------------------------------------------------------
local socketWatchList = {
	BLUE = true,
	RED = true,
	YELLOW = true,
	COGWHEEL = true,
	HYDRAULIC = true,
	META = true,
	PRISMATIC = true,
	PUNCHCARDBLUE = true,
	PUNCHCARDRED = true,
	PUNCHCARDYELLOW = true,
	DOMINATION = true,
	PRIMORDIAL = true,
}

local function GetSocketTexture(socket, count)
	return strrep("|TInterface\\ItemSocketingFrame\\UI-EmptySocket-" .. socket .. ":0|t", count)
end

local socketParts = {}
local function ItemGemText(link)
	wipe(socketParts)
	local stats = C_Item_GetItemStats(link)
	if stats then
		for stat, count in pairs(stats) do
			local socket = strmatch(stat, "EMPTY_SOCKET_(%S+)")
			if socket and socketWatchList[socket] then
				if socket == "PRIMORDIAL" then
					socket = "META"
				end -- texture missing; reuse meta
				socketParts[#socketParts + 1] = GetSocketTexture(socket, count)
			end
		end
	end
	return tconcat(socketParts)
end

local function ItemHasLevel(link)
	local name, _, rarity, level, _, _, _, _, _, _, _, classID = C_Item_GetItemInfo(link)
	if name and level and rarity and rarity > 1 and (classID == Enum.ItemClass.Weapon or classID == Enum.ItemClass.Armor) then
		return name, F.GetItemLevel(link)
	end
end

local itemCache = {}
local function ReplaceChatHyperlink(link, linkType)
	if not link then
		return
	end
	if linkType ~= "item" then
		return link
	end

	if itemCache[link] then
		return itemCache[link]
	end
	local name, itemLevel = ItemHasLevel(link)
	if name and itemLevel then
		local new = gsub(link, "|h%[(.-)%]|h", "|h[" .. name .. "(" .. itemLevel .. ")]|h" .. ItemGemText(link))
		return F.CacheSet(itemCache, link, new)
	end
	return link
end

local function UpdateChatItemLevel(_, _, msg, ...)
	if not ns.db.chatFilter.enable or not ns.db.chatFilter.chatItemLevel or F.IsSecret(msg) then
		return
	end
	-- No hyperlink, no work: skip the (relatively expensive) gsub entirely on the
	-- vast majority of chat lines that carry no item link. Cheap probe first.
	if not strfind(msg, "|H", 1, true) then
		return
	end
	msg = gsub(msg, "(|H([^:]+):(%d+):.-|h.-|h)", ReplaceChatHyperlink)
	return false, msg, ...
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------
local FILTER_EVENTS = {
	"CHAT_MSG_CHANNEL",
	"CHAT_MSG_SAY",
	"CHAT_MSG_YELL",
	"CHAT_MSG_WHISPER",
	"CHAT_MSG_EMOTE",
	"CHAT_MSG_TEXT_EMOTE",
}

local ITEMLEVEL_EVENTS = {
	"CHAT_MSG_LOOT",
	"CHAT_MSG_CHANNEL",
	"CHAT_MSG_SAY",
	"CHAT_MSG_YELL",
	"CHAT_MSG_WHISPER",
	"CHAT_MSG_WHISPER_INFORM",
	"CHAT_MSG_BN_WHISPER",
	"CHAT_MSG_RAID",
	"CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_PARTY",
	"CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_GUILD",
	"CHAT_MSG_BATTLEGROUND",
	"CHAT_MSG_INSTANCE_CHAT",
	"CHAT_MSG_INSTANCE_CHAT_LEADER",
}

-- Filters are installed once; each behaviour is gated live by its cfg flag so
-- the individual toggles apply without a reload (ChatFrame message filters
-- cannot be cleanly toggled per-flag, so we gate inside the callbacks instead).
function ChatFilter:Install()
	if self.installed then
		return
	end
	self.installed = true

	for i = 1, #FILTER_EVENTS do
		ChatFrame_AddMessageEventFilter(FILTER_EVENTS[i], UpdateChatFilter)
	end
	for i = 1, #ITEMLEVEL_EVENTS do
		ChatFrame_AddMessageEventFilter(ITEMLEVEL_EVENTS[i], UpdateChatItemLevel)
	end
end

-- ---------------------------------------------------------------------------
-- /nexfilter - manage the account-wide keyword lists
-- ---------------------------------------------------------------------------
local function PrintSet(set)
	local any = false
	for keyword in pairs(set) do
		F.Print("  " .. keyword)
		any = true
	end
	if not any then
		F.Print(F.Colorize("  (" .. L["empty"] .. ")", "gray"))
	end
end

local function HandleFilterCommand(input)
	local set = ns.global.chatFilter
	local cmd, rest = (input or ""):match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	rest = rest:gsub("^%s+", ""):gsub("%s+$", "")

	if cmd == "add" and rest ~= "" then
		set.keywords[rest] = true
		F.Print(F.Colorize(L["Added keyword"] .. ": ", "brand") .. rest)
	elseif (cmd == "del" or cmd == "remove") and rest ~= "" then
		set.keywords[rest] = nil
		set.whitelist[rest] = nil
		F.Print(F.Colorize(L["Removed keyword"] .. ": ", "brand") .. rest)
	elseif cmd == "white" and rest ~= "" then
		set.whitelist[rest] = true
		F.Print(F.Colorize(L["Added whitelist keyword"] .. ": ", "brand") .. rest)
	elseif cmd == "clear" then
		wipe(set.keywords)
		wipe(set.whitelist)
		set.keywordVersion = DEFAULT_KEYWORD_VERSION
		F.Print(F.Colorize(L["Chat filter keywords cleared."], "brand"))
	elseif cmd == "defaults" or cmd == "resetkeywords" then
		RestoreDefaultKeywords()
		F.Print(F.Colorize(L["Chat filter default keywords restored."], "brand"))
	elseif cmd == "list" then
		F.Print(F.Colorize(L["Filter keywords"] .. ":", "brand"))
		PrintSet(set.keywords)
		F.Print(F.Colorize(L["Whitelist keywords"] .. ":", "brand"))
		PrintSet(set.whitelist)
	else
		F.Print(F.Colorize(L["Chat filter usage:"], "brand"))
		F.Print("  /nexfilter add <keyword>")
		F.Print("  /nexfilter del <keyword>")
		F.Print("  /nexfilter white <keyword>")
		F.Print("  /nexfilter list")
		F.Print("  /nexfilter clear")
		F.Print("  /nexfilter defaults")
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function ChatFilter:OnInitialize()
	MergeDefaultKeywords()
end
function ChatFilter:OnEnable()
	---@diagnostic disable-next-line: undefined-field
	_G.SlashCmdList["NEXFILTER"] = HandleFilterCommand
	_G.SLASH_NEXFILTER1 = "/nexfilter"

	if ns.db.chatFilter.enable then
		self:Install()
	end
end

function ChatFilter:OnSettingChanged()
	if ns.db.chatFilter.enable then
		self:Install()
	end
end

function ChatFilter:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Chat Filter"], L["Filter chat spam and decorate item links (installs on enable; individual toggles below apply live)."])
	local _, spamInit = builder:Checkbox(category, self, "spamFilter", L["Spam Filter"], L["Hide messages matching blacklisted keywords or repeated near-identical spam."])
	local _, matchesInit = builder:Slider(category, self, "matches", L["Match Threshold"], L["How many blacklisted keywords a message must contain before it is hidden."], 1, 6, 1)
	local _, strangerInit = builder:Checkbox(category, self, "blockStranger", L["Block Strangers"], L["Hide whispers from anyone who is not a friend, guild member or group member."])

	local chatGlobal = ns.global.chatFilter
	local keywordsInit = builder:MultilineEditBox(category, L["Filter keywords"], L["CHATFILTER_KEYWORDS_TIP"], function()
		return SerializeKeywordSet(chatGlobal.keywords)
	end, function(text)
		ApplyKeywordText(text, chatGlobal.keywords)
	end, {
		width = 280,
		boxHeight = 130,
		onRestoreDefaults = RestoreDefaultKeywords,
		restoreLabel = L["Restore Default Keywords"],
	})

	local whitelistInit = builder:MultilineEditBox(category, L["Whitelist keywords"], L["CHATFILTER_WHITELIST_TIP"], function()
		return SerializeKeywordSet(chatGlobal.whitelist)
	end, function(text)
		ApplyKeywordText(text, chatGlobal.whitelist)
	end, {
		width = 280,
		boxHeight = 72,
	})

	builder:DependsOn(spamInit, enableInit)
	builder:DependsOn(matchesInit, spamInit) -- threshold only matters with the spam filter on
	builder:DependsOn(strangerInit, enableInit)
	if keywordsInit then
		builder:DependsOn(keywordsInit, spamInit)
	end
	if whitelistInit then
		builder:DependsOn(whitelistInit, spamInit)
	end
	builder:Checkbox(category, self, "blockSpammer", L["Block Spammers"], L["Hide all messages from a sender once they have tripped the filter repeatedly this session."])
	builder:Checkbox(category, self, "chatItemLevel", L["Item Level in Chat"], L["Append the item level and gem sockets to item links posted in chat."])
end
