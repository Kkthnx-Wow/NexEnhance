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

	Adapted to the NexEnhance framework from NDui's Modules/Chat/Filter.lua
	(by siweia):
	  https://github.com/siweia/NDui/blob/master/Interface/AddOns/NDui/Modules/Chat/Filter.lua

	Differences: NDui's hardcoded locale-specific addon/club blocklists and the
	dead BFA Azerite-island filter are dropped. Keyword/whitelist tables are
	account-wide (ns.global) and managed with the /nexfilter slash command since
	the Settings panel has no free-text control. Message reads are secret-gated.
--]]

local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local pairs = pairs
local gsub, strmatch, strrep = string.gsub, string.match, string.rep
local min, max, tremove = math.min, math.max, table.remove
local wipe = wipe
local GetTime, Ambiguate = GetTime, Ambiguate
local IsGuildMember, IsGUIDInGroup = IsGuildMember, IsGUIDInGroup
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

-- Account-wide keyword tables (sets keyed by the keyword), edited via /nexfilter.
ns:RegisterDefaults({
	chatFilter = {
		keywords = {},
		whitelist = {},
	},
}, "global")

local ChatFilter = ns:NewModule("ChatFilter", "chatFilter", { group = "filters", title = L["Chat Filter"], order = 10 })

local MyName = C.Player.name

-- ---------------------------------------------------------------------------
-- Spam filtering
-- ---------------------------------------------------------------------------
local BadBoys = {} -- [name] = times filtered this session
local chatLines, prevLineID = {}, 0
local filterResult ---@type any
local last, this = {}, {} -- reused Levenshtein rows (no per-call allocation)

-- Normalized edit distance between two byte arrays (0 = identical, 1 = totally
-- different). Reuses module-level rows to avoid GC churn.
local function CompareStrDiff(sA, sB)
	local lenA, lenB = #sA, #sB
	if lenA == 0 or lenB == 0 then return 1 end

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
	if guid and guid ~= "" and (IsGuildMember(guid) or C_BattleNet_GetGameAccountInfoByGUID(guid) or C_FriendList_IsFriend(guid) or IsGUIDInGroup(guid)) then
		return
	end

	if cfg.blockStranger and event == "CHAT_MSG_WHISPER" then
		return true
	end

	if cfg.blockSpammer and BadBoys[name] and BadBoys[name] >= 5 then
		return true
	end

	if not cfg.spamFilter then return end

	-- Strip hyperlinks and colour codes down to plain text for matching.
	local filterMsg = gsub(msg, "|H.-|h(.-)|h", "%1")
	filterMsg = gsub(filterMsg, "|c%x%x%x%x%x%x%x%x", "")
	filterMsg = gsub(filterMsg, "|r", "")

	local keywords = ns.global.chatFilter.keywords
	local whitelist = ns.global.chatFilter.whitelist

	-- Channel whitelist: if a whitelist exists and the line matches none of it,
	-- drop it (without counting the sender as a spammer).
	if event == "CHAT_MSG_CHANNEL" then
		local matches, found = 0, false
		for keyword in pairs(whitelist) do
			if keyword ~= "" then
				found = true
				local _, count = gsub(filterMsg, keyword, "")
				if count > 0 then matches = matches + 1 end
			end
		end
		if matches == 0 and found then return 0 end
	end

	-- Keyword blacklist.
	local matches = 0
	for keyword in pairs(keywords) do
		if keyword ~= "" then
			local _, count = gsub(filterMsg, keyword, "")
			if count > 0 then matches = matches + 1 end
		end
	end
	if matches >= cfg.matches then return true end

	-- Repeat filter: compare against recent lines from the same sender.
	local msgTable = { name, {}, GetTime() }
	if filterMsg == "" then filterMsg = msg end
	for i = 1, #filterMsg do
		msgTable[2][i] = filterMsg:byte(i)
	end

	local size = #chatLines
	chatLines[size + 1] = msgTable
	for i = 1, size do
		local line = chatLines[i]
		if line[1] == msgTable[1] and ((event == "CHAT_MSG_CHANNEL" and msgTable[3] - line[3] < 0.6) or CompareStrDiff(line[2], msgTable[2]) <= 0.1) then
			tremove(chatLines, i)
			return true
		end
	end
	if size >= 30 then tremove(chatLines, 1) end
end

local function UpdateChatFilter(_, event, msg, author, _, _, _, flag, _, _, _, _, lineID, guid)
	if F.IsSecret(msg) then return end

	-- One result per chat line, shared across all chat frames showing it.
	if lineID ~= prevLineID then
		prevLineID = lineID
		local name = Ambiguate(author, "none")
		filterResult = GetFilterResult(event, msg, name, flag, guid)
		if filterResult and filterResult ~= 0 then
			BadBoys[name] = (BadBoys[name] or 0) + 1
		end
		if filterResult == 0 then filterResult = true end
	end

	return filterResult
end

-- ---------------------------------------------------------------------------
-- Item level on chat hyperlinks
-- ---------------------------------------------------------------------------
local socketWatchList = {
	BLUE = true, RED = true, YELLOW = true, COGWHEEL = true, HYDRAULIC = true,
	META = true, PRISMATIC = true, PUNCHCARDBLUE = true, PUNCHCARDRED = true,
	PUNCHCARDYELLOW = true, DOMINATION = true, PRIMORDIAL = true,
}

local function GetSocketTexture(socket, count)
	return strrep("|TInterface\\ItemSocketingFrame\\UI-EmptySocket-" .. socket .. ":0|t", count)
end

local function ItemGemText(link)
	local text = ""
	local stats = C_Item_GetItemStats(link)
	if stats then
		for stat, count in pairs(stats) do
			local socket = strmatch(stat, "EMPTY_SOCKET_(%S+)")
			if socket and socketWatchList[socket] then
				if socket == "PRIMORDIAL" then socket = "META" end -- texture missing; reuse meta
				text = text .. GetSocketTexture(socket, count)
			end
		end
	end
	return text
end

local function ItemHasLevel(link)
	local name, _, rarity, level, _, _, _, _, _, _, _, classID = C_Item_GetItemInfo(link)
	if name and level and rarity and rarity > 1 and (classID == Enum.ItemClass.Weapon or classID == Enum.ItemClass.Armor) then
		return name, F.GetItemLevel(link)
	end
end

local itemCache = {}
local function ReplaceChatHyperlink(link, linkType)
	if not link then return end
	if linkType ~= "item" then return link end

	if itemCache[link] then return itemCache[link] end
	local name, itemLevel = ItemHasLevel(link)
	if name and itemLevel then
		local new = gsub(link, "|h%[(.-)%]|h", "|h[" .. name .. "(" .. itemLevel .. ")]|h" .. ItemGemText(link))
		itemCache[link] = new
		return new
	end
	return link
end

local function UpdateChatItemLevel(_, _, msg, ...)
	if not ns.db.chatFilter.chatItemLevel or F.IsSecret(msg) then return end
	msg = gsub(msg, "(|H([^:]+):(%d+):.-|h.-|h)", ReplaceChatHyperlink)
	return false, msg, ...
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------
local FILTER_EVENTS = {
	"CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER",
	"CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
}

local ITEMLEVEL_EVENTS = {
	"CHAT_MSG_LOOT", "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL",
	"CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER",
	"CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_PARTY",
	"CHAT_MSG_PARTY_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_BATTLEGROUND",
	"CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
}

-- Filters are installed once; each behaviour is gated live by its cfg flag so
-- the individual toggles apply without a reload (ChatFrame message filters
-- cannot be cleanly toggled per-flag, so we gate inside the callbacks instead).
function ChatFilter:Install()
	if self.installed then return end
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
local function PrintSet(label, set)
	local any = false
	for keyword in pairs(set) do
		F.Print("  " .. keyword)
		any = true
	end
	if not any then
		F.Print(F.Colorize("  (" .. L["empty"] .. ")", "gray"))
	end
	return label
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
		F.Print(F.Colorize(L["Chat filter keywords cleared."], "brand"))
	elseif cmd == "list" then
		F.Print(F.Colorize(L["Filter keywords"] .. ":", "brand"))
		PrintSet(nil, set.keywords)
		F.Print(F.Colorize(L["Whitelist keywords"] .. ":", "brand"))
		PrintSet(nil, set.whitelist)
	else
		F.Print(F.Colorize(L["Chat filter usage:"], "brand"))
		F.Print("  /nexfilter add <keyword>")
		F.Print("  /nexfilter del <keyword>")
		F.Print("  /nexfilter white <keyword>")
		F.Print("  /nexfilter list")
		F.Print("  /nexfilter clear")
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
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
	local _, spamInit = builder:Checkbox(category, self, "spamFilter", L["Spam Filter"], L["Hide messages matching blacklisted keywords or repeated near-identical spam. Manage keywords with /nexfilter."])
	local _, matchesInit = builder:Slider(category, self, "matches", L["Match Threshold"], L["How many blacklisted keywords a message must contain before it is hidden."], 1, 6, 1)
	local _, strangerInit = builder:Checkbox(category, self, "blockStranger", L["Block Strangers"], L["Hide whispers from anyone who is not a friend, guild member or group member."])

	builder:DependsOn(spamInit, enableInit)
	builder:DependsOn(matchesInit, spamInit) -- threshold only matters with the spam filter on
	builder:DependsOn(strangerInit, enableInit)
	builder:Checkbox(category, self, "blockSpammer", L["Block Spammers"], L["Hide all messages from a sender once they have tripped the filter repeatedly this session."])
	builder:Checkbox(category, self, "chatItemLevel", L["Item Level in Chat"], L["Append the item level and gem sockets to item links posted in chat."])
end
