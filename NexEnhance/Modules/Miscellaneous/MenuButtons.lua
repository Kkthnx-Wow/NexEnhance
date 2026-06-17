--[[
	NexEnhance - Menu Buttons
	-------------------------------------------------------------------------
	Appends quick social actions to the unit right-click menu: Add Friend,
	Guild Invite, Copy Name and Whisper. Only the actions that make sense for a
	given menu type are added, and they appear as real, brand-coloured menu
	entries (no floating widgets).

	Built on the 10.0+ menu system researched in Resources
	(Blizzard_Menu/Menu.lua + 11_0_0_MenuImplementationGuide.lua):
	  * Menu.ModifyMenu("MENU_UNIT_<TYPE>", cb) is the supported, taint-safe way
	    to add entries - the guide notes addons can insert elements at any
	    position without imparting taint to surrounding handlers.
	  * The callback receives the unit's contextData (.name/.server/.unit and,
	    for BNet friends, .accountInfo.gameAccountInfo).
	  * GuildInvite is a deprecated shim now, so we call the live C_GuildInfo.Invite.
	  * contextData.name / .server can be Secret inside instances on 12.0; the
	    name is resolved once (guarded) up front and the click handlers only ever
	    see a plain string. If nothing is readable, our entries are simply omitted.

	Action set per menu type follows KkthnxUI's curation (it only adds the useful
	options Blizzard's menu for that type is missing).
--]]

-- Menu is a valid Blizzard global missing from the generated luacheck std.
-- luacheck: globals Menu
local _, ns = ...
local F, L, C = ns.F, ns.L, ns.C

local pairs = pairs
local format, gsub = string.format, string.gsub
local GetGuildInfo = GetGuildInfo
local UnitIsUnit = UnitIsUnit
local C_FriendList = C_FriendList
local C_GuildInfo = C_GuildInfo
local ChatFrame_SendTell = ChatFrame_SendTell
local ChatEdit_ChooseBoxForSend = ChatEdit_ChooseBoxForSend
local ChatEdit_ActivateChat = ChatEdit_ActivateChat

-- Blizzard global strings (client-localised). Read through _G with fallbacks.
local ADD_FRIEND = _G["ADD_CHARACTER_FRIEND"] or _G["ADD_FRIEND"] or "Add Friend"
local COPY_NAME = _G["COPY_NAME"] or "Copy Name"
local WHISPER = _G["WHISPER"] or "Whisper"
local HEADER_COLON = _G["HEADER_COLON"] or ": "
local INVITE_LABEL = _G["COMMUNITIES_INVITE_MANAGER_LABEL"] or "Invite to %s"
local GUILD_INVITE_FALLBACK = gsub(_G["CHAT_GUILD_INVITE_SEND"] or "Invite to Guild", HEADER_COLON, "")

-- Brand colour escape so our additions read as NexEnhance entries.
local INFO = "|c" .. C.BrandHex

-- Section header shown above our entries. CreateTitle defaults to
-- NORMAL_FONT_COLOR (yellow), matching Blizzard's own section titles.
local ADDON_TITLE = "NexEnhance"

ns:RegisterDefaults({
	menuButtons = {
		enable = true,
	},
})

local Module = ns:NewModule("MenuButtons", "menuButtons", { group = "misc", title = L["Menu Buttons"], order = 15 })

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
-- Resolve a plain "Name-Realm" from the menu's contextData, preferring a BNet
-- friend's logged-in character. Returns nil when nothing is readable or a value
-- is Secret (instances), so the caller omits our entries.
local function ResolveName(data)
	if not data or F.IsSecretTable(data) then
		return nil
	end

	local accountInfo = data.accountInfo
	local gameInfo = accountInfo and accountInfo.gameAccountInfo
	if gameInfo then
		local charName, realmName = gameInfo.characterName, gameInfo.realmName
		if charName and realmName and F.NotSecret(charName) and F.NotSecret(realmName) then
			return charName .. "-" .. realmName
		end
	end

	local name = data.name
	if not name or F.IsSecret(name) then
		return nil
	end

	local server = data.server
	if server and F.NotSecret(server) then
		return name .. "-" .. server
	end
	return name .. "-" .. C.Player.realm
end

-- Whispering or friending yourself is nonsense, so bail on your own frame. This
-- also covers targeting yourself (fires MENU_UNIT_TARGET, not _SELF). The unit
-- token can be secret in instances; treat an unreadable result as "not us".
local function IsSelf(data)
	local unit = data and data.unit
	if not (unit and F.NotSecret(unit)) then
		return false
	end
	local same = UnitIsUnit(unit, "player")
	return F.NotSecret(same) and same and true or false
end

-- "Invite to <YourGuild>" when guilded, else a generic label. The guild name is
-- bracketed and tinted with the guild-chat colour (live ChatTypeInfo so a custom
-- colour is honoured, default green otherwise); "Invite to" stays brand-coloured.
-- The name segment closes with |r and re-opens INFO so any trailing locale text
-- (e.g. a closing quote) keeps the brand colour. Cheap to build on demand.
local function GuildInviteText()
	local guildName = GetGuildInfo("player")
	if not (guildName and guildName ~= "" and F.NotSecret(guildName)) then
		return INFO .. GUILD_INVITE_FALLBACK
	end

	local info = _G["ChatTypeInfo"] and _G["ChatTypeInfo"]["GUILD"]
	local r, g, b = 0.25, 1.0, 0.25
	if info and info.r then
		r, g, b = info.r, info.g, info.b
	end
	local coloredName = format("|cff%02x%02x%02x<%s>|r%s", r * 255, g * 255, b * 255, guildName, INFO)
	return INFO .. format(INVITE_LABEL, coloredName)
end

-- ---------------------------------------------------------------------------
-- Click handlers
--   Shared (file-scope) so no closures are allocated per menu open. The menu
--   system invokes a button responder as callback(data, ...) (Menu.lua:860), so
--   the pre-resolved plain "Name-Realm" string rides along as `data` and the
--   handlers never touch a Secret value.
-- ---------------------------------------------------------------------------
local function OnAddFriend(name)
	if C_FriendList and C_FriendList.AddFriend then
		C_FriendList.AddFriend(name)
	end
end

local function OnGuildInvite(name)
	if C_GuildInfo and C_GuildInfo.Invite then
		C_GuildInfo.Invite(name)
	end
end

local function OnCopyName(name)
	local editBox = ChatEdit_ChooseBoxForSend()
	if not editBox then
		return
	end
	local hasText = editBox:GetText() ~= ""
	ChatEdit_ActivateChat(editBox)
	editBox:Insert(name)
	if not hasText then
		editBox:HighlightText()
	end
end

local function OnWhisper(name)
	if ChatFrame_SendTell then
		ChatFrame_SendTell(name)
	end
end

-- ---------------------------------------------------------------------------
-- Entry builders (text + shared handler + the resolved name as data)
-- ---------------------------------------------------------------------------
local function AddFriendButton(root, name)
	root:CreateButton(INFO .. ADD_FRIEND, OnAddFriend, name)
end

local function GuildInviteButton(root, name)
	-- GuildInviteText() already carries its own colour codes.
	root:CreateButton(GuildInviteText(), OnGuildInvite, name)
end

local function CopyNameButton(root, name)
	root:CreateButton(INFO .. COPY_NAME, OnCopyName, name)
end

local function WhisperButton(root, name)
	root:CreateButton(INFO .. WHISPER, OnWhisper, name)
end

-- Menu tag -> ordered builders. Mirrors KkthnxUI's per-type action set.
-- No MENU_UNIT_SELF entry: there's nothing useful to do to your own frame, and
-- the IsSelf() guard below suppresses the section if you target yourself anyway.
local MENU_ACTIONS = {
	MENU_UNIT_TARGET = { CopyNameButton },
	MENU_UNIT_PLAYER = { GuildInviteButton },
	MENU_UNIT_FRIEND = { AddFriendButton, GuildInviteButton },
	MENU_UNIT_BN_FRIEND = { AddFriendButton, GuildInviteButton, CopyNameButton },
	MENU_UNIT_PARTY = { GuildInviteButton },
	MENU_UNIT_RAID = { AddFriendButton, GuildInviteButton, CopyNameButton, WhisperButton },
	MENU_UNIT_RAID_PLAYER = { GuildInviteButton },
}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
-- ModifyMenu subscriptions are permanent (the menu system has no unregister),
-- so install once and gate each callback on the live setting instead.
local function Setup()
	if Module.started then
		return
	end
	if not (Menu and Menu.ModifyMenu) then
		return
	end
	Module.started = true

	for tag, builders in pairs(MENU_ACTIONS) do
		Menu.ModifyMenu(tag, function(_, rootDescription, data)
			if not ns.db.menuButtons.enable then
				return
			end
			if IsSelf(data) then
				return
			end
			local name = ResolveName(data)
			if not name then
				return
			end
			-- A divider + yellow title open our section, the same way Blizzard's
			-- stock menu sections itself (see 11_0_0_MenuImplementationGuide.lua).
			rootDescription:CreateDivider()
			rootDescription:CreateTitle(ADDON_TITLE)
			for i = 1, #builders do
				builders[i](rootDescription, name)
			end
		end)
	end
end

function Module:OnEnable()
	if ns.db.menuButtons.enable then
		Setup()
	end
end

function Module:OnSettingChanged(key, value)
	-- Installs on first enable; once installed the callbacks self-gate, so
	-- toggling off just stops adding entries on the next menu open.
	if key == "enable" and value then
		Setup()
	end
end

function Module:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Menu Buttons"], L["Add quick Add Friend, Guild Invite, Copy Name and Whisper actions to the unit right-click menu."])
end
