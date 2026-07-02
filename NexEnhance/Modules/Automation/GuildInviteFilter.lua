--[[
	NexEnhance - Guild Invite Filter
	-------------------------------------------------------------------------
	Auto-declines guild invites from strangers while letting trusted sources
	through:
	  - character friends
	  - Battle.net friends
	  - guild members (when already in a guild and re-invited / cross-guild)

	Notes:
	  - GUILD_INVITE_REQUEST hands us (inviter, guildName) as plain strings. In
	    12.0 those can be secret values inside restricted instances, so every
	    name read is gated through the shared F secret API; if the inviter name
	    is secret we fail open (leave Blizzard's popup) rather than risk wrongly
	    declining a friend.
	  - The guild roster is name-keyed and rebuilt lazily (only when marked
	    dirty, and only at invite time) so a busy GUILD_ROSTER_UPDATE never
	    triggers a full rescan.
	  - Toggles live in the profile DB; running statistics are account-wide and
	    stored in the global DB.
	  - Blizzard's own "Block Guild Invites" (SetAutoDeclineGuildInvites) drops
	    invites server-side before GUILD_INVITE_REQUEST ever fires, so the two
	    can't run together. While enabled we force it off and remember the
	    player's prior value (per-character, in charDB) so disabling the module
	    restores exactly what they had - even across a reload.
	  - Declining alone doesn't close the on-screen invite: modern retail shows
	    the dedicated GuildInviteFrame (StaticPopupSpecial), not the old
	    StaticPopup. We hide that frame and, because Blizzard may show it after
	    our handler runs, sweep once more next frame so it never lingers.

	Events stay registered while the module is on; the enable flag is read live
	so the toggle applies without a reload.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local F, L = ns.F, ns.L

local DeclineGuild = DeclineGuild
local SetAutoDeclineGuildInvites = SetAutoDeclineGuildInvites
local GetAutoDeclineGuildInvites = GetAutoDeclineGuildInvites
local IsInGuild = IsInGuild
local GetGuildRosterInfo = GetGuildRosterInfo
local GetNumGuildMembers = GetNumGuildMembers
local Ambiguate = Ambiguate
local BNGetNumFriends = BNGetNumFriends
local PlaySound = PlaySound
local StaticPopup_Hide = StaticPopup_Hide
local StaticPopupSpecial_Hide = StaticPopupSpecial_Hide
local C_Timer_After = C_Timer and C_Timer.After
local strlower = strlower
local format = string.format
local date = date
local wipe = wipe

local UNKNOWN = UNKNOWN
local C_BattleNet_GetFriendAccountInfo = C_BattleNet and C_BattleNet.GetFriendAccountInfo
local C_FriendList_GetNumFriends = C_FriendList and C_FriendList.GetNumFriends
local C_FriendList_GetFriendInfoByIndex = C_FriendList and C_FriendList.GetFriendInfoByIndex
-- GuildRoster() was folded into C_GuildInfo on retail; fall back to the old
-- global where the namespace function is unavailable (Classic).
local RequestGuildRoster = (C_GuildInfo and C_GuildInfo.GuildRoster) or _G["GuildRoster"]
local SOUND_DECLINE = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON

ns:RegisterDefaults({
	guildInviteFilter = {
		enable = false,
		fromFriends = true,
		fromGuild = true,
		announce = true,
		sound = true,
	},
})

-- Account-wide running stats (never shared through a profile).
ns:RegisterDefaults({
	guildInviteFilter = {
		totalBlocked = 0,
		totalAllowed = 0,
		blockedPlayers = {},
		lastBlocked = nil,
	},
}, "global")

local GuildInviteFilter = ns:NewModule("GuildInviteFilter", "guildInviteFilter", { group = "automation", title = L["Guild Invite Filter"], order = 65, since = "1.2.9" })

local eventHandles = {}

-- Lower-cased, realm-stripped name. Returns nil when the value is missing or a
-- secret value (string ops on a secret would error), which all callers treat as
-- "can't evaluate".
local function NormalizeName(name)
	if not name or F.IsSecret(name) then
		return nil
	end
	return strlower(Ambiguate(name, "none"))
end

-- A display-safe name for stats / chat output: never store or print a secret.
local function SafeName(name)
	return (name and F.NotSecret(name)) and name or UNKNOWN
end

-- Guild roster cache: name-keyed and rebuilt lazily, only when marked dirty.
local guildMemberCache = {}
local guildCacheDirty = true

local function RebuildGuildCache()
	wipe(guildMemberCache)
	if IsInGuild() then
		for i = 1, GetNumGuildMembers() do
			local normalized = NormalizeName(GetGuildRosterInfo(i))
			if normalized then
				guildMemberCache[normalized] = true
			end
		end
	end
	guildCacheDirty = false
end

local function EnsureGuildCache()
	if guildCacheDirty then
		if RequestGuildRoster then
			RequestGuildRoster()
		end
		RebuildGuildCache()
	end
end

-- Trusted-source checks. All comparisons run on already-normalized names.
local function IsCharacterFriend(target)
	if not (target and C_FriendList_GetNumFriends and C_FriendList_GetFriendInfoByIndex) then
		return false
	end
	for i = 1, (C_FriendList_GetNumFriends() or 0) do
		local info = C_FriendList_GetFriendInfoByIndex(i)
		if info and NormalizeName(info.name) == target then
			return true
		end
	end
	return false
end

local function IsBattleNetFriend(target)
	if not (target and BNGetNumFriends and C_BattleNet_GetFriendAccountInfo) then
		return false
	end
	for i = 1, (BNGetNumFriends() or 0) do
		local accountInfo = C_BattleNet_GetFriendAccountInfo(i)
		local gameAccountInfo = accountInfo and accountInfo.gameAccountInfo
		local characterName = gameAccountInfo and gameAccountInfo.characterName
		if characterName and NormalizeName(characterName) == target then
			return true
		end
	end
	return false
end

local function IsGuildMemberByName(target)
	if not target then
		return false
	end
	EnsureGuildCache()
	return guildMemberCache[target] == true
end

local function IsTrusted(target)
	local cfg = ns.db.guildInviteFilter
	if cfg.fromFriends and (IsCharacterFriend(target) or IsBattleNetFriend(target)) then
		return true
	end
	if cfg.fromGuild and IsGuildMemberByName(target) then
		return true
	end
	return false
end

-- Account-wide running statistics, stored in the global DB.
local function RecordAllowed()
	local stats = ns.global.guildInviteFilter
	stats.totalAllowed = (stats.totalAllowed or 0) + 1
	GuildInviteFilter:RefreshStats()
end

local function RecordBlocked(inviter, guildName, normalized)
	local stats = ns.global.guildInviteFilter
	stats.totalBlocked = (stats.totalBlocked or 0) + 1
	if normalized then
		stats.blockedPlayers[normalized] = (stats.blockedPlayers[normalized] or 0) + 1
	end
	stats.lastBlocked = {
		player = SafeName(inviter),
		guild = SafeName(guildName),
		time = date("%Y-%m-%d %H:%M:%S"),
	}
	GuildInviteFilter:RefreshStats()
end

-- Two stable lines (counts + last block) so the options description never grows
-- past the height reserved for it when the row is first measured.
local function BuildStatsText()
	local stats = ns.global.guildInviteFilter
	local counts = format(L["Blocked: %d    Allowed: %d"], stats.totalBlocked or 0, stats.totalAllowed or 0)

	local last = stats.lastBlocked
	local lastLine
	if last then
		lastLine = format(L["Last blocked: %s to <%s> (%s)"], SafeName(last.player), SafeName(last.guild), last.time or "?")
	else
		lastLine = L["Last blocked: none yet."]
	end

	return counts .. "\n" .. lastLine
end

-- Push the latest numbers into the options description (if the panel was built).
-- The description re-reads its text whenever the page is shown, so updating the
-- stored data here is enough for it to refresh on the next view.
function GuildInviteFilter:RefreshStats()
	local data = self.statsData
	if data then
		data.text = BuildStatsText()
	end
end

-- Dismiss the on-screen guild invite. Modern retail (Cata+) shows the dedicated
-- GuildInviteFrame via StaticPopupSpecial, NOT the old StaticPopup "GUILD_INVITE"
-- - so hiding the static popup alone left it sitting there. Hide the real frame
-- (its OnHide re-declines, which is harmless since we already did) and keep the
-- legacy StaticPopup hide as a fallback for older clients.
local function HideGuildInvitePopup()
	local frame = _G.GuildInviteFrame
	if frame and frame:IsShown() then
		if StaticPopupSpecial_Hide then
			StaticPopupSpecial_Hide(frame)
		else
			frame:Hide()
		end
	end
	if StaticPopup_Hide then
		StaticPopup_Hide("GUILD_INVITE")
	end
end

function GuildInviteFilter:GUILD_INVITE_REQUEST(inviter, guildName)
	if not ns.db.guildInviteFilter.enable then
		return
	end

	-- A secret inviter name (restricted instance) can't be evaluated; fail open.
	local target = NormalizeName(inviter)
	if not target then
		return
	end

	if IsTrusted(target) then
		RecordAllowed()
		return
	end

	DeclineGuild()
	HideGuildInvitePopup()
	-- Blizzard's own handler can show the invite frame AFTER ours runs (event
	-- dispatch order isn't guaranteed), so sweep once more next frame - otherwise
	-- a declined invite can still flash up on screen.
	if C_Timer_After then
		C_Timer_After(0, HideGuildInvitePopup)
	end

	local cfg = ns.db.guildInviteFilter
	if cfg.sound and SOUND_DECLINE then
		PlaySound(SOUND_DECLINE, "Master")
	end

	RecordBlocked(inviter, guildName, target)
	if cfg.announce then
		F.Print(format(L["Blocked guild invite from %s to join <%s>."], SafeName(inviter), SafeName(guildName)))
	end
end

function GuildInviteFilter:GUILD_ROSTER_UPDATE()
	guildCacheDirty = true
end

function GuildInviteFilter:PLAYER_GUILD_UPDATE()
	guildCacheDirty = true
	if not IsInGuild() then
		wipe(guildMemberCache)
	end
end

function GuildInviteFilter:RegisterModuleEvents()
	if self.eventsRegistered then
		return
	end
	self.eventsRegistered = true

	self:TrackEvent(eventHandles, "GUILD_INVITE_REQUEST", "GUILD_INVITE_REQUEST")
	self:TrackEvent(eventHandles, "GUILD_ROSTER_UPDATE", "GUILD_ROSTER_UPDATE")
	self:TrackEvent(eventHandles, "PLAYER_GUILD_UPDATE", "PLAYER_GUILD_UPDATE")
end

function GuildInviteFilter:UnregisterModuleEvents()
	if not self.eventsRegistered then
		return
	end
	self.eventsRegistered = false

	ns:UnregisterModuleEventHandles(eventHandles)
end

-- GetAutoDeclineGuildInvites returns a numeric flag (1/0), and 0 is truthy in
-- Lua, so test the value rather than relying on plain truthiness.
local function IsBlizzardAutoDeclineOn()
	if not GetAutoDeclineGuildInvites then
		return false
	end
	local value = GetAutoDeclineGuildInvites()
	return value == 1 or value == "1" or value == true
end

-- Force Blizzard's "Block Guild Invites" off so invites reach our filter,
-- caching the player's real value the first time we override it. Guarded so a
-- reload (which re-enables the module while the option is already forced off)
-- never overwrites the genuine cached value with our own 0.
function GuildInviteFilter:SuppressBlizzardAutoDecline()
	if not SetAutoDeclineGuildInvites then
		return
	end

	local cdb = ns.charDB.guildInviteFilter or {}
	ns.charDB.guildInviteFilter = cdb
	if cdb.prevAutoDecline == nil then
		cdb.prevAutoDecline = IsBlizzardAutoDeclineOn() and 1 or 0
	end

	SetAutoDeclineGuildInvites(false)
end

-- Restore whatever the player had before we took over, then drop the cache.
function GuildInviteFilter:RestoreBlizzardAutoDecline()
	if not SetAutoDeclineGuildInvites then
		return
	end

	local cdb = ns.charDB.guildInviteFilter
	if cdb and cdb.prevAutoDecline ~= nil then
		SetAutoDeclineGuildInvites(cdb.prevAutoDecline == 1)
		cdb.prevAutoDecline = nil
	end
end

function GuildInviteFilter:OnSettingChanged(key, value)
	if key ~= "enable" then
		return
	end
	if value then
		self:RegisterModuleEvents()
		self:SuppressBlizzardAutoDecline()
	else
		self:OnDisable()
	end
end

function GuildInviteFilter:OnDisable()
	self:UnregisterModuleEvents()
	self:RestoreBlizzardAutoDecline()
end

function GuildInviteFilter:OnEnable()
	self:RegisterModuleEvents()
	self:SuppressBlizzardAutoDecline()
end

function GuildInviteFilter:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Guild Invite Filter"], L["Automatically decline guild invites from players who are not friends or guild members."])
	local _, friendsInit = builder:Checkbox(category, self, "fromFriends", L["Allow From Friends"], L["Let guild invites from Battle.net and character friends through."])
	local _, guildInit = builder:Checkbox(category, self, "fromGuild", L["Allow From Guild"], L["Let guild invites from your current guild members through."])
	local _, announceInit = builder:Checkbox(category, self, "announce", L["Announce Blocks"], L["Print a chat message whenever a guild invite is declined."])
	local _, soundInit = builder:Checkbox(category, self, "sound", L["Play Sound"], L["Play a short sound whenever a guild invite is declined."])

	-- These only matter while the filter is on, so grey them out otherwise.
	builder:DependsOn(friendsInit, enableInit)
	builder:DependsOn(guildInit, enableInit)
	builder:DependsOn(announceInit, enableInit)
	builder:DependsOn(soundInit, enableInit)

	-- Lifetime running totals (account-wide), refreshed each time this page opens.
	builder:Header(L["Statistics"])
	local statsInit = builder:Description(BuildStatsText())
	builder:DependsOn(statsInit, enableInit)
	---@type table?
	self.statsData = statsInit and statsInit:GetData()
end
