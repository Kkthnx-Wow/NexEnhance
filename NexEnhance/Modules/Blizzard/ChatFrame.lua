local _, Module = ...

local hooksecurefunc = hooksecurefunc

local FRIEND_TEXTURE = "UI-ChatIcon-App"
local QUEUE_TEXTURE = "groupfinder-eye-frame"
local HOME_TEXTURE = "Interface\\Buttons\\UI-HomeButton"
local CHANNEL_TEXTURE = "chatframe-button-icon-voicechat"

local function SkinQuickJoinToastButton(button)
	button:SetSize(28, 28)
	button:SetHighlightTexture(0)
	button.FriendsButton:SetAtlas(FRIEND_TEXTURE)
	button.QueueButton:SetAtlas(QUEUE_TEXTURE)
	button.FriendCount:ClearAllPoints()
	button.FriendCount:SetPoint("BOTTOM", 1, 2)
end

-- Theme Application
function Module:ADDON_LOADED()
	-- QuickJoinToastButton
	SkinQuickJoinToastButton(QuickJoinToastButton)
	QuickJoinToastButton:HookScript("OnMouseDown", function(self)
		self.FriendsButton:SetAtlas(FRIEND_TEXTURE)
	end)
	QuickJoinToastButton:HookScript("OnMouseUp", function(self)
		self.FriendsButton:SetAtlas(FRIEND_TEXTURE)
	end)
	QuickJoinToastButton.Toast:ClearAllPoints()
	QuickJoinToastButton.Toast:SetPoint("LEFT", QuickJoinToastButton, "RIGHT")

	hooksecurefunc(QuickJoinToastButton, "ToastToFriendFinished", function(self)
		self.FriendsButton:SetShown(not self.displayedToast)
		self.FriendCount:SetShown(not self.displayedToast)
	end)
	hooksecurefunc(QuickJoinToastButton, "UpdateQueueIcon", function(self)
		if not self.displayedToast then
			return
		end
		self.FriendsButton:SetAtlas(FRIEND_TEXTURE)
		self.QueueButton:SetAtlas(QUEUE_TEXTURE)
		self.FlashingLayer:SetAtlas(QUEUE_TEXTURE)
		self.FriendsButton:SetShown(false)
		self.FriendCount:SetShown(false)
	end)

	ChatFrameChannelButton:SetSize(18, 18)
	Module.RemoveTextures(ChatFrameChannelButton)
	ChatFrameChannelButton:SetNormalTexture(CHANNEL_TEXTURE)
	ChatFrameChannelButton:SetPushedTexture(CHANNEL_TEXTURE)
	ChatFrameChannelButton:SetHighlightTexture(CHANNEL_TEXTURE)

	ChatFrameToggleVoiceDeafenButton:SetSize(20, 20)
	ChatFrameToggleVoiceMuteButton:SetSize(20, 20)

	ChatFrameMenuButton:SetSize(20, 20)
	ChatFrameMenuButton:SetNormalTexture(HOME_TEXTURE)
	ChatFrameMenuButton:SetPushedTexture(HOME_TEXTURE)
	ChatFrameMenuButton:SetHighlightTexture(HOME_TEXTURE)
end
