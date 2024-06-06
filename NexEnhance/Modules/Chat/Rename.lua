local NexEnhance, NE_ChatRename = ...

local string_find, string_gsub = string.find, string.gsub
local INTERFACE_ACTION_BLOCKED = INTERFACE_ACTION_BLOCKED

local whisperColor, oldChatNames

function NE_ChatRename:SetupChannelNames(text, ...)
	if string_find(text, INTERFACE_ACTION_BLOCKED) then
		return
	end

	local r, g, b = ...
	if whisperColor and string_find(text, NE_ChatRename.L["To"] .. " |H[BN]*player.+%]") then
		r, g, b = 0.6274, 0.3231, 0.6274
	end

	if oldChatNames then
		return self.oldAddMessage(self, text, r, g, b)
	else
		return self.oldAddMessage(self, string_gsub(text, "|h%[(%d+)%..-%]|h", "|h[%1]|h"), r, g, b)
	end
end

function NE_ChatRename:RenameChatFrames()
	for i = 1, _G.NUM_CHAT_WINDOWS do
		if i ~= 2 then
			local chatFrame = _G["ChatFrame" .. i]
			chatFrame.oldAddMessage = chatFrame.AddMessage
			chatFrame.AddMessage = NE_ChatRename.SetupChannelNames
		end
	end
end

function NE_ChatRename:RenameChatStrings()
	_G.ERR_FRIEND_ONLINE_SS = string_gsub(_G.ERR_FRIEND_ONLINE_SS, "%]%|h", "]|h|cff00c957")
	_G.ERR_FRIEND_OFFLINE_S = string_gsub(_G.ERR_FRIEND_OFFLINE_S, "%%s", "%%s|cffff7f50")

	_G.CHAT_WHISPER_INFORM_GET = NE_ChatRename.L["To"] .. " %s "
	_G.CHAT_WHISPER_GET = NE_ChatRename.L["From"] .. " %s "
	_G.CHAT_BN_WHISPER_INFORM_GET = NE_ChatRename.L["To"] .. " %s "
	_G.CHAT_BN_WHISPER_GET = NE_ChatRename.L["From"] .. " %s "

	_G.CHAT_SAY_GET = "%s "
	_G.CHAT_YELL_GET = "%s "

	if oldChatNames then
		return
	end

	_G.CHAT_GUILD_GET = "|Hchannel:GUILD|h[G]|h %s "
	_G.CHAT_OFFICER_GET = "|Hchannel:OFFICER|h[O]|h %s "

	_G.CHAT_RAID_GET = "|Hchannel:RAID|h[R]|h %s "
	_G.CHAT_RAID_WARNING_GET = "[RW] %s "
	_G.CHAT_RAID_LEADER_GET = "|Hchannel:RAID|h[RL]|h %s "

	_G.CHAT_PARTY_GET = "|Hchannel:PARTY|h[P]|h %s "
	_G.CHAT_PARTY_LEADER_GET = "|Hchannel:PARTY|h[PL]|h %s "
	_G.CHAT_PARTY_GUIDE_GET = "|Hchannel:PARTY|h[PG]|h %s "

	_G.CHAT_INSTANCE_CHAT_GET = "|Hchannel:INSTANCE|h[I]|h %s "
	_G.CHAT_INSTANCE_CHAT_LEADER_GET = "|Hchannel:INSTANCE|h[IL]|h %s "

	_G.CHAT_FLAG_AFK = "[AFK] "
	_G.CHAT_FLAG_DND = "[DND] "
	_G.CHAT_FLAG_GM = "[GM] "
end

function NE_ChatRename:PLAYER_LOGIN()
	NE_ChatRename:RenameChatFrames()
	NE_ChatRename:RenameChatStrings()
end
