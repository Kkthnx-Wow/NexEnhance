local _, Module = ...

-- Cache commonly used WoW API functions
local C_BattleNet_GetGameAccountInfoByGUID = C_BattleNet.GetGameAccountInfoByGUID
local C_FriendList_IsFriend = C_FriendList.IsFriend
local IsGuildMember = IsGuildMember
local IsInGroup = IsInGroup
local QueueStatusButton = QueueStatusButton
local StaticPopupSpecial_Hide = StaticPopupSpecial_Hide
local StaticPopup_Hide = StaticPopup_Hide
local LFGInvitePopup = LFGInvitePopup

local hideStatic

-- Function to handle PARTY_INVITE_REQUEST
function Module:PARTY_INVITE_REQUEST(_, _, _, _, _, _, inviterGUID)
	if not Module.NexConfig or not Module.NexConfig.automation.AutoInvite then
		return
	end

	if not inviterGUID or inviterGUID == "" or IsInGroup() then
		return
	end

	if QueueStatusButton and QueueStatusButton:IsShown() then
		return
	end

	if C_BattleNet_GetGameAccountInfoByGUID(inviterGUID) or C_FriendList_IsFriend(inviterGUID) or IsGuildMember(inviterGUID) then
		hideStatic = true
		AcceptGroup()
	end
end

-- Function to handle GROUP_ROSTER_UPDATE
function Module:GROUP_ROSTER_UPDATE()
	if not Module.NexConfig or not Module.NexConfig.automation.AutoInvite then
		return
	end

	if hideStatic then
		if LFGInvitePopup and LFGInvitePopup:IsShown() then
			StaticPopupSpecial_Hide(LFGInvitePopup)
		end

		StaticPopup_Hide("PARTY_INVITE")
		hideStatic = nil
	end
end
