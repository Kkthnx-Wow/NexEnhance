-- Core Chat Module File
local _, Modules = ...

-- Ensure Modules.Chat exists
Modules.Chat = Modules.Chat or {}

-- Event handler for ADDON_LOADED
function Modules:ADDON_LOADED()
	if Modules.Chat.RegisterChatHooks then
		Modules.Chat:RegisterChatHooks()
	else
		print("Modules.Chat:RegisterChatHooks is not defined.")
	end
end

-- Event handler for PLAYER_LOGIN
function Modules:PLAYER_LOGIN()
	local chat = Modules.Chat

	if chat then
		if chat.RegisterChat then
			chat:RegisterChat()
		end
		if chat.RegisterChatCopy then
			chat:RegisterChatCopy()
		end
		if chat.RegisterChatRename then
			chat:RegisterChatRename()
		end
		if chat.RegisterChatURLCopy then
			chat:RegisterChatURLCopy()
		end
		if chat.RegisterChatFilters then
			chat:RegisterChatFilters()
		end
		if chat.RegisterChatToggles then
			chat:RegisterChatToggles()
		end
	else
		print("Modules.Chat is not defined.")
	end
end
