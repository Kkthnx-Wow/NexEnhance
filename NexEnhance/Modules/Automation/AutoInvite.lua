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
	if IsInGroup() or QueueStatusButton:IsShown() or inviterGUID == previousInviterGUID then
		return
	end

	local accountInfo = C_BattleNet.GetAccountInfoByGUID(inviterGUID)
	if accountInfo or C_FriendList.IsFriend(inviterGUID) or IsGuildMember(inviterGUID) then
		AcceptGroup()
		previousInviterGUID = inviterGUID
	end
end

-- Event handler for party invite requests and group roster updates.
local function AutoInvite(event, _, _, _, _, _, _, inviterGUID)
	if event == "PARTY_INVITE_REQUEST" then
		HandlePartyInvite(inviterGUID)
	elseif event == "GROUP_ROSTER_UPDATE" then
		StaticPopupSpecial_Hide(LFGInvitePopup)
		StaticPopup_Hide("PARTY_INVITE")
		previousInviterGUID = nil
	end
end

-- Initializes or disables the AutoInvite module based on user settings.
function Module:CreateAutoInvite()
	if Module.db.profile.automation.AutoInvite then
		self:RegisterEvent("PARTY_INVITE_REQUEST", AutoInvite)
		self:RegisterEvent("GROUP_ROSTER_UPDATE", AutoInvite)
	else
		self:UnregisterEvent("PARTY_INVITE_REQUEST", AutoInvite)
		self:UnregisterEvent("GROUP_ROSTER_UPDATE", AutoInvite)
	end
end

function Module:PLAYER_LOGIN()
	self:CreateAutoInvite()
end
