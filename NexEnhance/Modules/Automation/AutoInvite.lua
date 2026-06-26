--[[
	NexEnhance - Auto Invite
	-------------------------------------------------------------------------
	Automatically accepts group invites from trusted sources (Battle.net
	friends, character friends and guild members), and tidies up the invite
	popups once the roster updates.

	Adapted from KkthnxUI by Josh "Kkthnx" Russell:
	  https://github.com/Kkthnx-Wow/KkthnxUI/blob/main/KkthnxUI/Modules/Automation/Elements/Invite.lua

	Both events stay registered while the module is on; the trusted-source
	sub-options are read live so the toggles apply without a reload.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local F, L = ns.F, ns.L

local AcceptGroup = AcceptGroup
local IsInGroup = IsInGroup
local IsGuildMember = IsGuildMember
local StaticPopup_Hide = StaticPopup_Hide
local StaticPopupSpecial_Hide = StaticPopupSpecial_Hide
-- PARTY_INVITE_REQUEST hands us a player (character) GUID, so resolve it with
-- GetGameAccountInfoByGUID; GetAccountInfoByGUID expects a Battle.net account GUID.
local C_BattleNet_GetGameAccountInfoByGUID = C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID
local C_FriendList_IsFriend = C_FriendList and C_FriendList.IsFriend

ns:RegisterDefaults({
	autoInvite = {
		enable = false,
		fromFriends = true,
		fromGuild = true,
	},
})

local AutoInvite = ns:NewModule("AutoInvite", "autoInvite", { group = "automation", title = L["Auto Accept Invites"], order = 60 })

-- Remember the last inviter so a duplicate PARTY_INVITE_REQUEST (Blizzard fires
-- it more than once) doesn't double-accept.
local previousInviterGUID

local function IsTrustedInviter(guid)
	if not guid or F.IsSecret(guid) then
		return false
	end

	local cfg = ns.db.autoInvite
	if cfg.fromFriends then
		if C_BattleNet_GetGameAccountInfoByGUID and C_BattleNet_GetGameAccountInfoByGUID(guid) then
			return true
		end
		if C_FriendList_IsFriend and C_FriendList_IsFriend(guid) then
			return true
		end
	end
	if cfg.fromGuild and IsGuildMember(guid) then
		return true
	end
	return false
end

function AutoInvite:PARTY_INVITE_REQUEST(_, _, _, _, _, _, inviterGUID)
	if not ns.db.autoInvite.enable then
		return
	end

	-- Don't hijack a deliberate manual decision: skip if already grouped, mid
	-- queue, or this is the repeat fire for an invite we just handled. The GUID
	-- can be a secret value in 12.0, so gate the equality/cache on F.NotSecret.
	if IsInGroup() then
		return
	end
	if QueueStatusButton and QueueStatusButton:IsShown() then
		return
	end
	if F.NotSecret(inviterGUID) and inviterGUID == previousInviterGUID then
		return
	end

	if IsTrustedInviter(inviterGUID) then
		AcceptGroup()
		previousInviterGUID = F.NotSecret(inviterGUID) and inviterGUID or nil
	end
end

function AutoInvite:GROUP_ROSTER_UPDATE()
	if LFGInvitePopup then
		StaticPopupSpecial_Hide(LFGInvitePopup)
	end
	StaticPopup_Hide("PARTY_INVITE")
	previousInviterGUID = nil
end

function AutoInvite:RegisterModuleEvents()
	if self.eventsRegistered then
		return
	end
	self.eventsRegistered = true

	self:RegisterEvent("PARTY_INVITE_REQUEST")
	self:RegisterEvent("GROUP_ROSTER_UPDATE")
end

function AutoInvite:OnSettingChanged(key, value)
	if key == "enable" and value then
		self:RegisterModuleEvents()
	end
end

function AutoInvite:OnEnable()
	self:RegisterModuleEvents()
end

function AutoInvite:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Auto Accept Invites"], L["Automatically accept group invites from trusted sources."])
	local _, friendsInit = builder:Checkbox(category, self, "fromFriends", L["Accept From Friends"], L["Auto-accept invites from Battle.net and character friends."])
	local _, guildInit = builder:Checkbox(category, self, "fromGuild", L["Accept From Guild"], L["Auto-accept invites from guild members."])

	-- These only matter while Auto Invite is on, so grey them out otherwise.
	builder:DependsOn(friendsInit, enableInit)
	builder:DependsOn(guildInit, enableInit)
end
