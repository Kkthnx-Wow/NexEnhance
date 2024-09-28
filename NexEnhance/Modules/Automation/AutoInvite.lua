local _, Module = ...

-- Cache global references for performance
local C_BattleNet = C_BattleNet
local C_FriendList = C_FriendList
local IsGuildMember = IsGuildMember
local IsInGroup = IsInGroup
local QueueStatusButton = QueueStatusButton
local StaticPopupSpecial_Hide = StaticPopupSpecial_Hide
local StaticPopup_Hide = StaticPopup_Hide
local LFGInvitePopup = LFGInvitePopup

local previousInviterGUID

-- Handles the party invite by checking if the inviter is a friend, guild member, or Battle.net friend.
local function HandlePartyInvite(inviterGUID)
	if IsInGroup() then
		return
	end

	if QueueStatusButton:IsShown() then
		return
	end

	if inviterGUID == previousInviterGUID then
		return
	end

	local accountInfo = C_BattleNet.GetAccountInfoByGUID(inviterGUID)
	if accountInfo or C_FriendList.IsFriend(inviterGUID) or IsGuildMember(inviterGUID) then
		Module:DebugPrint("Accepting group invite from inviterGUID:", inviterGUID)
		AcceptGroup()
		previousInviterGUID = inviterGUID
	end
end

-- Use the eventMixin to handle party invite requests
local function OnPartyInviteReceived(_, _, _, _, _, _, inviterGUID)
	HandlePartyInvite(inviterGUID)
end

-- Use the eventMixin to clear the previous inviter when the group roster updates
local function OnGroupRosterUpdated()
	StaticPopupSpecial_Hide(LFGInvitePopup)
	StaticPopup_Hide("PARTY_INVITE")
	previousInviterGUID = nil
end

-- Initializes or disables the AutoInvite module based on user settings.
function Module:CreateAutoInvite()
	if Module.db.profile.automation.AutoInvite then
		Module:RegisterEvent("PARTY_INVITE_REQUEST", OnPartyInviteReceived)
		Module:RegisterEvent("GROUP_ROSTER_UPDATE", OnGroupRosterUpdated)
	else
		Module:UnregisterEvent("PARTY_INVITE_REQUEST", OnPartyInviteReceived)
		Module:UnregisterEvent("GROUP_ROSTER_UPDATE", OnGroupRosterUpdated)
	end
end

function Module:PLAYER_LOGIN()
	Module:CreateAutoInvite()
end
