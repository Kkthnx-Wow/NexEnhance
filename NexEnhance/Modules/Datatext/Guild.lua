local _, Module = ...
local CommaValue = Module.ShortValue

local guildTable = {}

Module.myrealm = GetRealmName()

do
	local function GWGetClassColor(class, useClassColor, forNameString)
		if not class or not useClassColor then
			return RAID_CLASS_COLORS.PRIEST
		end

		local color = RAID_CLASS_COLORS[class]
		local colorForNameString

		if type(color) ~= "table" then
			return
		end

		if not color.colorStr then
			color.colorStr = Module.RGBToHex(color.r, color.g, color.b, "ff")
		elseif strlen(color.colorStr) == 6 then
			color.colorStr = "ff" .. color.colorStr
		end

		return forNameString and colorForNameString or color
	end
	Module.GWGetClassColor = GWGetClassColor
end

local menuList = {
	{ text = OPTIONS, isTitle = true, notCheckable = true },
	{ text = INVITE, hasArrow = true, notCheckable = true },
	{ text = CHAT_MSG_WHISPER_INFORM, hasArrow = true, notCheckable = true },
}

local onlinestatus = {
	[0] = "",
	[1] = "|cffFFFFFF[|r|cffFF0000" .. AFK .. "|r|cffFFFFFF]|r",
	[2] = "|cffFFFFFF[|r|cffFF0000" .. DND .. "|r|cffFFFFFF]|r",
}
local mobilestatus = {
	[0] = [[|TInterface\ChatFrame\UI-ChatIcon-ArmoryChat:14:14:0:0:16:16:0:16:0:16:73:177:73|t]],
	[1] = [[|TInterface\ChatFrame\UI-ChatIcon-ArmoryChat-AwayMobile:14:14:0:0:16:16:0:16:0:16|t]],
	[2] = [[|TInterface\ChatFrame\UI-ChatIcon-ArmoryChat-BusyMobile:14:14:0:0:16:16:0:16:0:16|t]],
}

Module.FACTION_COLOR = {
	[1] = { r = 163 / 255, g = 46 / 255, b = 54 / 255 }, --Horde
	[2] = { r = 57 / 255, g = 115 / 255, b = 186 / 255 }, --Alliance
}

Module.myfaction, Module.myLocalizedFaction = UnitFactionGroup("player")

local tthead = Module.myfaction == "Alliance" and Module.FACTION_COLOR[2] or Module.FACTION_COLOR[1]
local ttsubh = { r = 1, g = 0.93, b = 0.73 }
local ttoff = { r = 0.3, g = 1, b = 0.3 }
local activezone = { r = 0.3, g = 1.0, b = 0.3 }
local inactivezone = { r = 0.65, g = 0.65, b = 0.65 }

local function sortByRank(a, b)
	if a and b then
		if a.rankIndex == b.rankIndex then
			return a.name < b.name
		end
		return a.rankIndex < b.rankIndex
	end
end

local function sortByName(a, b)
	if a and b then
		return a.name < b.name
	end
end

local function SortGuildTable(shift)
	if shift then
		sort(guildTable, sortByRank)
	else
		sort(guildTable, sortByName)
	end
end

local function inGroup(name)
	return (UnitInParty(name) or UnitInRaid(name)) and "|cffaaaaaa*|r" or ""
end

function Module.FetchGuildMembers()
	wipe(guildTable)

	local totalMembers = GetNumGuildMembers()
	for i = 1, totalMembers do
		local name, rank, rankIndex, level, _, zone, note, officerNote, connected, memberstatus, className, _, _, isMobile, _, _, guid = GetGuildRosterInfo(i)
		if not name then
			return
		end

		local statusInfo = isMobile and mobilestatus[memberstatus] or onlinestatus[memberstatus]
		zone = (isMobile and not connected) and REMOTE_CHAT or zone

		if connected or isMobile then
			guildTable[#guildTable + 1] = {
				name = gsub(name, gsub(Module.myrealm, "[%s%-]", ""), ""),
				rank = rank,
				level = level,
				zone = zone,
				note = note,
				officerNote = officerNote,
				online = connected,
				status = statusInfo,
				class = className,
				rankIndex = rankIndex,
				isMobile = isMobile,
				guid = guid,
			}
		end
	end
end

function Module.Guild_OnEnter(self)
	if not IsInGuild() then
		return
	end

	GameTooltip:ClearLines()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	-- get blizzard tooltip infos:
	GameTooltip_SetTitle(GameTooltip, self.tooltipText)
	if not self:IsEnabled() then
		if self.factionGroup == "Neutral" then
			GameTooltip:AddLine(FEATURE_NOT_AVAILBLE_PANDAREN, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b, true)
		elseif self.minLevel then
			GameTooltip:AddLine(format(FEATURE_BECOMES_AVAILABLE_AT_LEVEL, self.minLevel), RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b, true)
		elseif self.disabledTooltip then
			local disabledTooltipText = GetValueOrCallFunction(self, "disabledTooltip")
			GameTooltip:AddLine(disabledTooltipText, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b, true)
		end
	end
	GameTooltip:AddLine(" ")

	local shiftDown = IsShiftKeyDown()
	local total, _, online = GetNumGuildMembers()
	if #guildTable == 0 then
		Module.FetchGuildMembers()
	end

	SortGuildTable(shiftDown)

	local guildName, guildRank = GetGuildInfo("player")

	if guildName and guildRank then
		GameTooltip:AddDoubleLine(guildName, GUILD .. ": " .. online .. "/" .. total, tthead.r, tthead.g, tthead.b, tthead.r, tthead.g, tthead.b)
		GameTooltip:AddLine(guildRank, 1, 1, 1, 1)
	end

	if GetGuildRosterMOTD() ~= "" then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(GUILD_MOTD .. " |cffaaaaaa- |cffffffff" .. GetGuildRosterMOTD(), tthead.r, tthead.g, tthead.b, 1)
	end

	local _, _, standingID, barMin, barMax, barValue = GetGuildFactionInfo()
	-- Show only if not on max rep
	if standingID ~= 8 then
		barMax = barMax - barMin
		barValue = barValue - barMin
		GameTooltip:AddLine(Module.RGBToHex(ttsubh.r, ttsubh.g, ttsubh.b) .. COMBAT_FACTION_CHANGE .. ":|r |cFFFFFFFF" .. CommaValue(barValue) .. "/" .. CommaValue(barMax) .. "(" .. ceil((barValue / barMax) * 100) .. "%)")
	end

	local zonec

	GameTooltip:AddLine(" ")
	for i, info in ipairs(guildTable) do
		if i > 20 then
			GameTooltip:AddLine("+ " .. (online - 20) .. " " .. BINDING_HEADER_OTHER, ttsubh.r, ttsubh.g, ttsubh.b)
			break
		end

		local zoneText = GetRealZoneText() or UNKNOWN
		if zoneText and (zoneText == info.zone) then
			zonec = activezone
		else
			zonec = inactivezone
		end

		local classc, levelc = Module.GWGetClassColor(info.class, true, true), GetQuestDifficultyColor(info.level)
		if not classc then
			classc = levelc
		end

		if shiftDown then
			GameTooltip:AddDoubleLine(strmatch(info.name, "([^%-]+).*") .. " |cff999999-|cffffffff " .. info.rank, info.zone, classc.r, classc.g, classc.b, zonec.r, zonec.g, zonec.b)
			if info.note ~= "" then
				GameTooltip:AddLine("|cff999999   " .. LABEL_NOTE .. ":|r " .. info.note, ttsubh.r, ttsubh.g, ttsubh.b, 1)
			end
			if info.officerNote ~= "" then
				GameTooltip:AddLine("|cff999999   " .. GUILD_RANK1_DESC .. ":|r " .. info.officerNote, ttoff.r, ttoff.g, ttoff.b, 1)
			end
		else
			GameTooltip:AddDoubleLine(format("|cff%02x%02x%02x%d|r %s%s %s", levelc.r * 255, levelc.g * 255, levelc.b * 255, info.level, strmatch(info.name, "([^%-]+).*"), inGroup(info.name), info.status), info.zone, classc.r, classc.g, classc.b, zonec.r, zonec.g, zonec.b)
		end
	end

	GameTooltip:Show()
end

local function inviteClick(_, name, guid)
	Module.EasyMenu:Hide()

	if not (name and name ~= "") then
		return
	end

	if guid then
		local inviteType = GetDisplayedInviteType(guid)
		if inviteType == "INVITE" or inviteType == "SUGGEST_INVITE" then
			C_PartyInfo.InviteUnit(name)
		elseif inviteType == "REQUEST_INVITE" then
			C_PartyInfo.RequestInviteFromUnit(name)
		end
	end
end

local function whisperClick(_, playerName)
	Module.EasyMenu:Hide()
	SetItemRef("player:" .. playerName, format("|Hplayer:%1$s|h[%1$s]|h", playerName), "LeftButton")
end

function Module.Guild_OnClick(self, button)
	if button == "LeftButton" then
		self:OnClick()
	elseif button == "RightButton" and IsInGuild() then
		local menuCountWhispers = 0
		local menuCountInvites = 0

		menuList[2].menuList = {}
		menuList[3].menuList = {}

		for _, info in ipairs(guildTable) do
			if (info.online or info.isMobile) and strmatch(info.name, "([^%-]+).*") ~= Module.myname then
				local classc, levelc = Module.GWGetClassColor(info.class, true, true), GetQuestDifficultyColor(info.level)
				if not classc then
					classc = levelc
				end

				local name = format("|cff%02x%02x%02x%d|r |cff%02x%02x%02x%s|r", levelc.r * 255, levelc.g * 255, levelc.b * 255, info.level, classc.r * 255, classc.g * 255, classc.b * 255, strmatch(info.name, "([^%-]+).*"))
				if inGroup(strmatch(info.name, "([^%-]+).*")) ~= "" then
					name = name .. " |cffaaaaaa*|r"
				elseif not (info.isMobile and info.zone == REMOTE_CHAT) then
					menuCountInvites = menuCountInvites + 1
					menuList[2].menuList[menuCountInvites] = { text = name, arg1 = strmatch(info.name, "([^%-]+).*"), arg2 = info.guid, notCheckable = true, func = inviteClick }
				end

				menuCountWhispers = menuCountWhispers + 1
				menuList[3].menuList[menuCountWhispers] = { text = name, arg1 = strmatch(info.name, "([^%-]+).*"), notCheckable = true, func = whisperClick }
			end
		end
		Module.SetEasyMenuAnchor(Module.EasyMenu, self)
		Module.Libs.LibDD:EasyMenu(menuList, Module.EasyMenu, nil, nil, nil, "MENU")
	end
end

function Module:Guild_RosterUpdate()
	local gmb = GuildMicroButton
	if gmb == nil then
		return
	end

	local _, _, numOnlineMembers = GetNumGuildMembers()

	if numOnlineMembers ~= nil and numOnlineMembers > 0 then
		if numOnlineMembers > 9 then
			GuildMicroButton.Text:SetText(numOnlineMembers)
		else
			GuildMicroButton.Text:SetText(numOnlineMembers .. " ")
		end
		GuildMicroButton.Text:Show()
	else
		GuildMicroButton.Text:Hide()
	end

	Module.FetchGuildMembers()

	if GetMouseFocus() == self then
		Module.Guild_OnEnter(self)
	end
end

function Module:Guild_ModifierStateChanged()
	if not IsAltKeyDown() and GetMouseFocus() == self then
		Module.Guild_OnEnter(self)
	end
end

function Module:Guild_Motd()
	if GetMouseFocus() == self then
		Module.Guild_OnEnter(self)
	end
end

function Module:Guild_OnEvent(event)
	if event == "GUILD_ROSTER_UPDATE" then
		Module:Guild_RosterUpdate()
	elseif event == "MODIFIER_STATE_CHANGED" then
		Module:Guild_ModifierStateChanged()
	elseif event == "GUILD_MOTD" then
		Module:Guild_Motd()
	end
end

function Module:PLAYER_LOGIN()
	local gmb = GuildMicroButton
	if not gmb.Text then
		gmb.Text = Module.CreateFontString(gmb, 13, "", false, "", "BOTTOM", 3, 0)
		gmb.Text:Hide()
	end

	gmb.Ticker = C_Timer.NewTicker(15, function()
		C_GuildInfo.GuildRoster()
	end)

	gmb:RegisterEvent("GUILD_ROSTER_UPDATE", Module.GUILD_ROSTER_UPDATE)
	gmb:RegisterEvent("MODIFIER_STATE_CHANGED", Module.MODIFIER_STATE_CHANGED)
	gmb:RegisterEvent("GUILD_MOTD", Module.GUILD_MOTD)

	GuildMicroButton:HookScript("OnEvent", Module.Guild_OnEvent)
	GuildMicroButton:HookScript("OnEnter", Module.Guild_OnEnter)
	GuildMicroButton:SetScript("OnClick", Module.Guild_OnClick)
	gmb:SetScript("OnClick", Module.Guild_OnClick)
end
