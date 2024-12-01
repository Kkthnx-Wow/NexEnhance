local _, Modules = ...

function Modules:ADDON_LOADED()
	Modules.Chat:RegisterChatHooks()
end

function Modules:PLAYER_LOGIN()
	Modules.Chat:RegisterChat()
	Modules.Chat:RegisterChatCopy()
	Modules.Chat:RegisterChatRename()
	Modules.Chat:RegisterChatURLCopy()
	Modules.Chat:RegisterChatFilters()
	Modules.Chat:ToggleSocialButton()
	Modules.Chat:ToggleMenuButton()
	Modules.Chat:ToggleChannelButton()
end
