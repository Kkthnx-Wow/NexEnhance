local _, Modules = ...
local Module = Modules.Chat

local gsub, strfind, strmatch = string.gsub, string.find, string.match
local BetterDate, time, date, GetCVarBool = BetterDate, time, date, GetCVarBool
local INTERFACE_ACTION_BLOCKED = INTERFACE_ACTION_BLOCKED
local C_DateAndTime_GetCurrentCalendarTime = C_DateAndTime.GetCurrentCalendarTime

local timestampFormat = {
	["HH_MM_AMPM"] = "[%I:%M %p] ",
	["HH_MM_SS_AMPM"] = "[%I:%M:%S %p] ",
	["HH_MM_24"] = "[%H:%M] ",
	["HH_MM_SS_24"] = "[%H:%M:%S] ",
}

local function GetCurrentTime()
	local locTime = time()
	local realmTime = not GetCVarBool("timeMgrUseLocalTime") and C_DateAndTime_GetCurrentCalendarTime()
	if realmTime then
		realmTime.day = realmTime.monthDay
		realmTime.min = realmTime.minute
		realmTime.sec = date("%S") -- no sec value for realm time
		realmTime = time(realmTime)
	end

	return locTime, realmTime
end

function Module:UpdateChannelNames(text, ...)
	if strfind(text, INTERFACE_ACTION_BLOCKED) and not Modules.isDeveloper then
		return
	end

	local r, g, b = ...
	if Modules.NexConfig.chat.WhisperColor and strfind(text, Modules.L["To"] .. " |H[BN]*player.+%]") then
		r, g, b = r * 0.7, g * 0.7, b * 0.7
	end

	-- Dev logo
	local unitName = strmatch(text, "|Hplayer:([^|:]+)")
	if unitName and Modules.Developers[unitName] then
		text = gsub(text, "(|Hplayer.+)", "|T" .. Module.Logo64 .. ":12:24|t%1")
	end

	-- Timestamp
	if Modules.NexConfig.chat.TimestampFormat > "DISABLE" then
		local locTime, realmTime = GetCurrentTime()
		local defaultTimestamp = GetCVar("showTimestamps")
		if defaultTimestamp == "none" then
			defaultTimestamp = nil
		end

		local oldTimeStamp = defaultTimestamp and gsub(BetterDate(defaultTimestamp, locTime), "%[([^]]*)%]", "%%[%1%%]")
		if oldTimeStamp then
			text = gsub(text, oldTimeStamp, "")
		end

		local timeStamp = BetterDate("|cff7b8489" .. timestampFormat[Modules.NexConfig.chat.TimestampFormat] .. "|r", realmTime or locTime)
		text = timeStamp .. text
	end

	if Modules.NexConfig.chat.DefaultChannelNames then
		text = gsub(text, "|h%[(%d+)%. 大脚世界频道%]|h", "|h%[%1%. 世界%]|h")
		text = gsub(text, "|h%[(%d+)%. 大腳世界頻道%]|h", "|h%[%1%. 世界%]|h")
		return self.oldAddMsg(self, text, r, g, b)
	else
		return self.oldAddMsg(self, gsub(text, "|h%[(%d+)%..-%]|h", "|h[%1]|h"), r, g, b)
	end
end

function Module:RegisterChatRename()
	for i = 1, NUM_CHAT_WINDOWS do
		if i ~= 2 then
			local chatFrame = _G["ChatFrame" .. i]
			chatFrame.oldAddMsg = chatFrame.AddMessage
			chatFrame.AddMessage = Module.UpdateChannelNames
		end
	end

	--online/offline info
	ERR_FRIEND_ONLINE_SS = gsub(ERR_FRIEND_ONLINE_SS, "%]%|h", "]|h|cff00c957")
	ERR_FRIEND_OFFLINE_S = gsub(ERR_FRIEND_OFFLINE_S, "%%s", "%%s|cffff7f50")

	-- whisper
	CHAT_WHISPER_INFORM_GET = Modules.L["To"] .. " %s "
	CHAT_WHISPER_GET = Modules.L["From"] .. " %s "
	CHAT_BN_WHISPER_INFORM_GET = Modules.L["To"] .. " %s "
	CHAT_BN_WHISPER_GET = Modules.L["From"] .. " %s "

	--say / yell
	CHAT_SAY_GET = "%s "
	CHAT_YELL_GET = "%s "

	if Modules.NexConfig.chat.DefaultChannelNames then
		return
	end
	--guild
	CHAT_GUILD_GET = "|Hchannel:GUILD|h[G]|h %s "
	CHAT_OFFICER_GET = "|Hchannel:OFFICER|h[O]|h %s "

	--raid
	CHAT_RAID_GET = "|Hchannel:RAID|h[R]|h %s "
	CHAT_RAID_WARNING_GET = "[RW] %s "
	CHAT_RAID_LEADER_GET = "|Hchannel:RAID|h[RL]|h %s "

	--party
	CHAT_PARTY_GET = "|Hchannel:PARTY|h[P]|h %s "
	CHAT_PARTY_LEADER_GET = "|Hchannel:PARTY|h[PL]|h %s "
	CHAT_PARTY_GUIDE_GET = "|Hchannel:PARTY|h[PG]|h %s "

	--instance
	CHAT_INSTANCE_CHAT_GET = "|Hchannel:INSTANCE|h[I]|h %s "
	CHAT_INSTANCE_CHAT_LEADER_GET = "|Hchannel:INSTANCE|h[IL]|h %s "

	--flags
	CHAT_FLAG_AFK = "[AFK] "
	CHAT_FLAG_DND = "[DND] "
	CHAT_FLAG_GM = "[GM] "
end
