local _, Modules = ...
local Module = Modules.Chat

-- Section: Chat Frame Toggle Functions
function Module:ToggleSocialButton()
	if QuickJoinToastButton then
		if Modules.NexConfig.chat.SocialButton then
			QuickJoinToastButton:Hide()
		else
			QuickJoinToastButton:Show()
		end
	end
end

function Module:ToggleMenuButton()
	if ChatFrameMenuButton then
		if Modules.NexConfig.chat.MenuButton then
			ChatFrameMenuButton:SetScript("OnShow", nil)
			ChatFrameMenuButton:Hide()
		else
			ChatFrameMenuButton:Show()
		end
	end
end

function Module:ToggleChannelButton()
	if ChatFrameChannelButton then
		if Modules.NexConfig.chat.ChannelButton then
			ChatFrameChannelButton:SetScript("OnShow", nil)
			ChatFrameChannelButton:Hide()
		else
			ChatFrameChannelButton:Show()
		end
	end
end
