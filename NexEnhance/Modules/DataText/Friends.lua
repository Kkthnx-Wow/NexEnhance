--[[
	NexEnhance - DataText: Friends
	-------------------------------------------------------------------------
	Friends roster tooltip on Blizzard's QuickJoinToastButton (social button by
	the chat frame). The button already shows the online count — we add no
	overlay text, only the hover tooltip. Native click/queue-toast untouched.

	Battle.net entries group by client/game with lazy sub-headers, classic vs
	anniversary realm split, app/mobile de-duplication, and WoW project ->
	faction -> name sorting.
--]]

---@diagnostic disable: undefined-field, undefined-global
local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local _G = _G
local format = string.format
local strmatch, strfind, gsub = string.match, string.find, string.gsub
local ipairs, pairs, sort, wipe, tonumber, tremove = ipairs, pairs, sort, wipe, tonumber, tremove

local GameTooltip = GameTooltip
local GameTooltip_SetTitle = GameTooltip_SetTitle
local MicroButtonTooltipText = MicroButtonTooltipText
local GetQuestDifficultyColor = GetQuestDifficultyColor
local GetZoneText = GetZoneText
local GetRealmName = GetRealmName
local IsShiftKeyDown = IsShiftKeyDown
local MouseIsOver = MouseIsOver
local BNGetNumFriends = BNGetNumFriends
local BNet_GetValidatedCharacterName = BNet_GetValidatedCharacterName
local UnitInParty = UnitInParty
local UnitInRaid = UnitInRaid

local C_FriendList = C_FriendList
local C_BattleNet = C_BattleNet
local GetFriendAccountInfo = C_BattleNet.GetFriendAccountInfo
local GetFriendGameAccountInfo = C_BattleNet.GetFriendGameAccountInfo
local GetFriendNumGameAccounts = C_BattleNet.GetFriendNumGameAccounts

local FRIENDS_LIST_ONLINE = _G.FRIENDS_LIST_ONLINE
local CHARACTER_FRIEND = _G.CHARACTER_FRIEND
local BATTLENET_OPTIONS_LABEL = _G.BATTLENET_OPTIONS_LABEL
local SOCIAL_BUTTON = _G.SOCIAL_BUTTON
local WOW_STRING = _G.BNET_CLIENT_WOW
local WOW_PROJECT_MAINLINE = _G.WOW_PROJECT_MAINLINE
local EXPANSION_NAME0 = _G.EXPANSION_NAME0

local HDR = C.Colors.header
local LBL = C.Colors.label

local CLASS_COLORS = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS

ns:RegisterDefaults({
	friendsText = {
		enable = true,
		maxFriends = 30,
	},
})

local FriendsText = ns:NewModule("FriendsText", "friendsText", { group = "datatext", title = L["Friends"], order = 60 })

local cfg
local hooksInstalled
local eventHandles = {}
local eventsRegistered = false
local dataValid

local friendTable = {}
local bnetByClient = {} -- client token -> array of online entries
local clientSorted = {} -- client tokens in display order

local AFK_TAG = format(" |cffFFFFFF[|r|cffFF9900%s|r|cffFFFFFF]|r", _G.AFK or "AFK")
local DND_TAG = format(" |cffFFFFFF[|r|cffFF3333%s|r|cffFFFFFF]|r", _G.DND or "DND")

-- Plain-text fragments from ERR_FRIEND_* for CHAT_MSG_SYSTEM roster invalidation (ElvUI pattern).
local friendOnline, friendOffline
if _G.ERR_FRIEND_ONLINE_SS and _G.ERR_FRIEND_OFFLINE_S then
	friendOnline = gsub(_G.ERR_FRIEND_ONLINE_SS, "|Hplayer:%%s|h%[%%s%]|h", "")
	friendOffline = gsub(_G.ERR_FRIEND_OFFLINE_S, "%%s", "")
end

-- Client display order and short tags for Battle.net friend grouping.
local MOBILE = _G.BNET_FRIEND_TOOLTIP_MOBILE or "Mobile"
local clientList = {
	WoW = { index = 1, tag = "WoW" },
	WTCG = { index = 2, tag = "HS" },
	Hero = { index = 3, tag = "HotS" },
	Pro = { index = 4, tag = "OW" },
	OSI = { index = 5, tag = "D2" },
	D3 = { index = 6, tag = "D3" },
	Fen = { index = 7, tag = "D4" },
	ANBS = { index = 8, tag = "DI" },
	S1 = { index = 9, tag = "SC" },
	S2 = { index = 10, tag = "SC2" },
	W3 = { index = 11, tag = "WC3" },
	RTRO = { index = 12, tag = "AC" },
	GRY = { index = 20, tag = "AR" },
	App = { index = 21, tag = "App" },
	BSAp = { index = 22, tag = MOBILE },
}

local classToken = {}
do
	local male = _G.LOCALIZED_CLASS_NAMES_MALE
	local female = _G.LOCALIZED_CLASS_NAMES_FEMALE
	if male then
		for token, localized in pairs(male) do
			classToken[localized] = token
		end
	end
	if female then
		for token, localized in pairs(female) do
			classToken[localized] = token
		end
	end
end

local function ClassColorRGB(class)
	if not class then
		return 1, 1, 1
	end
	local token = classToken[class] or class
	local color = CLASS_COLORS and CLASS_COLORS[token]
	if color then
		return color.r, color.g, color.b
	end
	return 1, 1, 1
end

local playerRealm
local function InGroup(name, realm)
	if not name then
		return ""
	end
	if realm and realm ~= "" and realm ~= playerRealm then
		name = name .. "-" .. realm
	end
	return (UnitInParty(name) or UnitInRaid(name)) and "|cffaaaaaa*|r" or ""
end

-- ---------------------------------------------------------------------------
-- Roster building
-- Friend/guild roster APIs: no SecretReturns in Resources 12.0.7.
-- ---------------------------------------------------------------------------

local function SortByName(a, b)
	if a.name and b.name then
		return a.name < b.name
	end
end

local function BuildFriendTable()
	wipe(friendTable)
	local total = C_FriendList.GetNumFriends()
	if not total then
		return
	end

	for i = 1, total do
		local info = C_FriendList.GetFriendInfoByIndex(i)
		if info and info.connected then
			local status = (info.afk and AFK_TAG) or (info.dnd and DND_TAG) or ""
			friendTable[#friendTable + 1] = {
				name = info.name or "?",
				level = info.level or 0,
				class = info.className,
				zone = info.area or "",
				status = status,
			}
		end
	end

	if #friendTable > 0 then
		sort(friendTable, SortByName)
	end
end

-- Within a single client group: WoW sorts by project -> faction -> name,
-- everything else by Battle.net tag.
local function SortClientGroup(a, b)
	if a.client == WOW_STRING and a.wowProjectID and b.wowProjectID then
		if a.wowProjectID == b.wowProjectID then
			local af, bf = a.faction or "", b.faction or ""
			if af == bf then
				return (a.characterName or "") < (b.characterName or "")
			end
			return af < bf
		end
		return a.wowProjectID < b.wowProjectID
	end
	return (a.battleTag or "") < (b.battleTag or "")
end

local function ClientSort(a, b)
	local A, B = clientList[a], clientList[b]
	if A and B then
		return A.index < B.index
	end
	if A then
		return true
	end
	if B then
		return false
	end
	return a < b
end

local function GroupAdd(obj)
	local list = bnetByClient[obj.client]
	if not list then
		list = {}
		bnetByClient[obj.client] = list
	end
	list[#list + 1] = obj
end

local function GroupRemove(obj)
	local list = bnetByClient[obj.client]
	if not list then
		return
	end
	for n = #list, 1, -1 do
		if list[n] == obj then
			tremove(list, n)
			return
		end
	end
end

local function MakeBNetObject(account, game)
	local client = game.clientProgram or ""
	local characterName = BNet_GetValidatedCharacterName(game.characterName, account.battleTag, client) or ""

	local afk = account.isAFK or game.isGameAFK
	local dnd = account.isDND or game.isGameBusy

	local obj = {
		accountID = account.bnetAccountID,
		accountName = account.accountName or "?",
		battleTag = account.battleTag or "",
		characterName = characterName,
		client = client,
		isWoW = client == WOW_STRING,
		wowProjectID = game.wowProjectID,
		faction = game.factionName,
		className = game.className,
		realmName = game.realmName or "",
		zone = game.areaName or "",
		level = tonumber(game.characterLevel) or 0,
		gameText = game.richPresence or "",
		status = (afk and AFK_TAG) or (dnd and DND_TAG) or "",
	}

	-- Classic / Anniversary realms encode "<game> - <realm>" in rich presence.
	if obj.wowProjectID and obj.wowProjectID ~= WOW_PROJECT_MAINLINE and obj.gameText ~= "" then
		local classicText, realm = strmatch(obj.gameText, "(.-)%s%-%s?(.-)$")
		if classicText and classicText ~= "" then
			if classicText ~= EXPANSION_NAME0 and EXPANSION_NAME0 then
				classicText = gsub(classicText, "%s?" .. EXPANSION_NAME0 .. "%s?", "")
			end
			obj.classicText = classicText
		end
		if realm and realm ~= "" then
			obj.realmName = realm
		end
	end

	return obj
end

local function BuildBNetTable()
	for _, list in pairs(bnetByClient) do
		wipe(list)
	end
	wipe(clientSorted)

	local total = BNGetNumFriends()
	if not total then
		return
	end

	-- De-dup the same account showing up on a real game AND on the App/Mobile
	-- client: the real game entry wins; App is preferred over Mobile otherwise.
	local realByAccount = {}
	local appByAccount = {}

	local function Consider(account, game)
		if not (game and game.isOnline) then
			return
		end
		local obj = MakeBNetObject(account, game)
		local id = obj.accountID
		local newIsApp = obj.client == "App" or obj.client == "BSAp"

		if newIsApp then
			if realByAccount[id] then
				return
			end
			local existing = appByAccount[id]
			if existing then
				-- Prefer App over Mobile (BSAp); otherwise keep what we have.
				if existing.client == "BSAp" and obj.client == "App" then
					GroupRemove(existing)
					appByAccount[id] = obj
					GroupAdd(obj)
				end
				return
			end
			appByAccount[id] = obj
			GroupAdd(obj)
		else
			local existing = appByAccount[id]
			if existing then
				GroupRemove(existing)
				appByAccount[id] = nil
			end
			realByAccount[id] = true
			GroupAdd(obj)
		end
	end

	for i = 1, total do
		local account = GetFriendAccountInfo(i)
		if account then
			local numGame = GetFriendNumGameAccounts(i) or 0
			if numGame > 0 then
				for y = 1, numGame do
					Consider(account, GetFriendGameAccountInfo(i, y))
				end
			else
				Consider(account, account.gameAccountInfo)
			end
		end
	end

	for client, list in pairs(bnetByClient) do
		if #list > 0 then
			sort(list, SortClientGroup)
			clientSorted[#clientSorted + 1] = client
		end
	end
	sort(clientSorted, ClientSort)
end

function FriendsText:Rebuild()
	BuildFriendTable()
	BuildBNetTable()
	dataValid = true
end

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------

function FriendsText:BuildTooltip(button)
	if not cfg.enable then
		return
	end
	-- A live queue toast is showing; leave Blizzard's own tooltip alone.
	if button.displayedToast then
		return
	end
	if not button:IsEnabled() then
		return
	end

	local onlineFriends = C_FriendList.GetNumOnlineFriends() or 0
	local numFriends = C_FriendList.GetNumFriends() or 0
	local totalBNet, numBNetOnline = BNGetNumFriends()
	totalBNet = totalBNet or 0
	numBNetOnline = numBNetOnline or 0

	local totalOnline = onlineFriends + numBNetOnline
	if totalOnline == 0 then
		return
	end

	if not dataValid then
		self:Rebuild()
	end

	playerRealm = GetRealmName()
	local totalFriends = numFriends + totalBNet
	local shiftDown = IsShiftKeyDown()
	local playerZone = GetZoneText()
	local limit = cfg.maxFriends or 30
	local shown = 0
	local lastHeader

	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:ClearLines()
	GameTooltip_SetTitle(GameTooltip, MicroButtonTooltipText(SOCIAL_BUTTON, "TOGGLESOCIAL"))
	GameTooltip:AddDoubleLine(L["Friends List"], format("%s: %d/%d", FRIENDS_LIST_ONLINE or "Online", totalOnline, totalFriends), HDR.r, HDR.g, HDR.b, HDR.r, HDR.g, HDR.b)

	-- Lazily emit a section header only when the client group changes.
	local function AddHeader(header)
		if lastHeader ~= header then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(header, HDR.r, HDR.g, HDR.b)
			lastHeader = header
		end
	end

	local function ZoneColor(zone)
		if playerZone and zone and zone ~= "" and playerZone == zone then
			return 0.3, 1, 0.3
		end
		return 0.65, 0.65, 0.65
	end

	-- Character (non-Battle.net) friends.
	if onlineFriends > 0 then
		for _, info in ipairs(friendTable) do
			if shown >= limit then
				break
			end
			shown = shown + 1
			AddHeader(CHARACTER_FRIEND or "Friends")

			local classR, classG, classB = ClassColorRGB(info.class)
			local levelColor = GetQuestDifficultyColor(info.level)
			local zoneR, zoneG, zoneB = ZoneColor(info.zone)
			GameTooltip:AddDoubleLine(format("|cff%02x%02x%02x%d|r |cff%02x%02x%02x%s|r%s%s", levelColor.r * 255, levelColor.g * 255, levelColor.b * 255, info.level, classR * 255, classG * 255, classB * 255, info.name, InGroup(info.name), info.status), info.zone, 1, 1, 1, zoneR, zoneG, zoneB)
		end
	end

	-- Battle.net friends, grouped by client with lazy per-game headers.
	for _, client in ipairs(clientSorted) do
		local clientInfo = clientList[client]
		for _, info in ipairs(bnetByClient[client]) do
			if shown >= limit then
				break
			end
			shown = shown + 1

			local header = format("%s (%s)", BATTLENET_OPTIONS_LABEL or "Battle.net", info.classicText or (clientInfo and clientInfo.tag) or client)
			AddHeader(header)

			if info.isWoW and info.characterName ~= "" then
				local classR, classG, classB = ClassColorRGB(info.className)
				local levelColor = GetQuestDifficultyColor(info.level)
				GameTooltip:AddDoubleLine(format("|cff%02x%02x%02x%d|r |cff%02x%02x%02x%s|r%s%s", levelColor.r * 255, levelColor.g * 255, levelColor.b * 255, info.level, classR * 255, classG * 255, classB * 255, info.characterName, InGroup(info.characterName, info.realmName), info.status), info.accountName, 1, 1, 1, 0.9, 0.9, 0.9)
				if shiftDown and (info.zone ~= "" or info.realmName ~= "") then
					local zoneR, zoneG, zoneB = ZoneColor(info.zone)
					GameTooltip:AddDoubleLine("   " .. (info.zone ~= "" and info.zone or " "), info.realmName, zoneR, zoneG, zoneB, 0.65, 0.65, 0.65)
				end
			else
				local left = info.characterName ~= "" and (info.characterName .. info.status) or (info.accountName .. info.status)
				GameTooltip:AddDoubleLine(left, info.accountName, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9)
				if shiftDown and info.gameText ~= "" and info.client ~= "App" and info.client ~= "BSAp" then
					GameTooltip:AddLine("   " .. info.gameText, 0.65, 0.65, 0.65)
				end
			end
		end
		if shown >= limit then
			break
		end
	end

	if totalOnline > shown then
		local count = totalOnline - shown
		GameTooltip:AddLine(format("+%d %s...", count, FRIENDS_LIST_ONLINE or "online"), LBL.r, LBL.g, LBL.b)
	end

	if not shiftDown then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L["Hold Shift for details"], LBL.r, LBL.g, LBL.b)
	end

	GameTooltip:Show()
end

local function OnEnterHook(button)
	FriendsText:BuildTooltip(button)
end

function FriendsText:RefreshIfHovering()
	local button = _G.QuickJoinToastButton
	if button and MouseIsOver(button) then
		self:BuildTooltip(button)
	end
end

function FriendsText:FRIENDLIST_UPDATE()
	dataValid = false
	self:RefreshIfHovering()
end

function FriendsText:BN_FRIEND_ACCOUNT_ONLINE()
	dataValid = false
	self:RefreshIfHovering()
end

function FriendsText:BN_FRIEND_ACCOUNT_OFFLINE()
	dataValid = false
	self:RefreshIfHovering()
end

function FriendsText:BN_FRIEND_INFO_CHANGED()
	dataValid = false
	self:RefreshIfHovering()
end

function FriendsText:CHAT_MSG_SYSTEM(_, arg1)
	if not friendOnline or not arg1 or F.IsSecret(arg1) then
		return
	end
	if not strfind(arg1, friendOnline, 1, true) and not strfind(arg1, friendOffline, 1, true) then
		return
	end
	dataValid = false
	self:RefreshIfHovering()
end

function FriendsText:MODIFIER_STATE_CHANGED()
	self:RefreshIfHovering()
end

function FriendsText:InstallHooks()
	if hooksInstalled then
		return
	end
	local button = _G.QuickJoinToastButton
	if not button then
		return
	end
	button:HookScript("OnEnter", OnEnterHook)
	hooksInstalled = true
end

function FriendsText:Create()
	local button = _G.QuickJoinToastButton
	if not button then
		return
	end

	self:InstallHooks()

	self:RegisterModuleEvents()

	dataValid = false
end

function FriendsText:RegisterModuleEvents()
	if eventsRegistered then
		return
	end
	eventsRegistered = true
	self:TrackEvent(eventHandles, "FRIENDLIST_UPDATE", "FRIENDLIST_UPDATE")
	self:TrackEvent(eventHandles, "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_ONLINE")
	self:TrackEvent(eventHandles, "BN_FRIEND_ACCOUNT_OFFLINE", "BN_FRIEND_ACCOUNT_OFFLINE")
	self:TrackEvent(eventHandles, "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_INFO_CHANGED")
	self:TrackEvent(eventHandles, "CHAT_MSG_SYSTEM", "CHAT_MSG_SYSTEM")
	self:TrackEvent(eventHandles, "MODIFIER_STATE_CHANGED", "MODIFIER_STATE_CHANGED")
end

function FriendsText:UnregisterModuleEvents()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
end

function FriendsText:Stop()
	self:UnregisterModuleEvents()
end

function FriendsText:OnEnable()
	cfg = ns.db.friendsText
	if not cfg.enable then
		return
	end
	self:Create()
end

function FriendsText:OnDisable()
	self:Stop()
end

function FriendsText:OnSettingChanged(key)
	cfg = ns.db.friendsText
	if key == "enable" then
		-- ApplyModuleSetting owns enable lifecycle.
		return
	end
	if key == "maxFriends" then
		self:RefreshIfHovering()
	end
end

function FriendsText:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Friends Text"], L["Show a friends roster tooltip when hovering the social button by the chat frame (reload to disable)."])
	local _, maxInit = builder:Slider(category, self, "maxFriends", L["Max Friends"], L["Maximum friends shown in the tooltip before stopping."], 10, 60, 1)

	builder:DependsOn(maxInit, enableInit)
end
