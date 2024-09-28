local _, Module = ...

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

function Module:PARTY_INVITE_REQUEST(_, _, _, _, _, _, _, inviterGUID)
	HandlePartyInvite(inviterGUID)
end

function Module:GROUP_ROSTER_UPDATE()
	StaticPopupSpecial_Hide(LFGInvitePopup)
	StaticPopup_Hide("PARTY_INVITE")
	previousInviterGUID = nil
end

-- Initializes or disables the AutoInvite module based on user settings.
function Module:CreateAutoInvite()
	if Module.db.profile.automation.AutoInvite then
		self:RegisterEvent("PARTY_INVITE_REQUEST", self.PARTY_INVITE_REQUEST)
		self:RegisterEvent("GROUP_ROSTER_UPDATE", self.GROUP_ROSTER_UPDATE)
	else
		self:UnregisterEvent("PARTY_INVITE_REQUEST", self.PARTY_INVITE_REQUEST)
		self:UnregisterEvent("GROUP_ROSTER_UPDATE", self.GROUP_ROSTER_UPDATE)
	end
end

function Module:PLAYER_LOGIN()
	self:CreateAutoInvite()
end
