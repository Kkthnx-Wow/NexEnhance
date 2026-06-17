--[[
	NexEnhance - DataText: Guild
	-------------------------------------------------------------------------
	Online guild member count overlay on Blizzard's GuildMicroButton, with an
	ElvUI-style roster tooltip on hover. Does not replace native click handlers,
	layout, or notification behaviour on the micro button.
--]]

---@diagnostic disable: undefined-field, undefined-global
local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local _G = _G
local format, match, find = string.format, string.match, string.find
local ipairs, pairs, sort, wipe = ipairs, pairs, sort, wipe

local CreateFrame = CreateFrame
local GameTooltip = GameTooltip
local GetGuildInfo = GetGuildInfo
local GetGuildRosterInfo = GetGuildRosterInfo
local GetNumGuildMembers = GetNumGuildMembers
local GetQuestDifficultyColor = GetQuestDifficultyColor
local GetZoneText = GetZoneText
local InCombatLockdown = InCombatLockdown
local IsInGuild = IsInGuild
local IsShiftKeyDown = IsShiftKeyDown
local MouseIsOver = MouseIsOver
local UnitInParty = UnitInParty
local UnitInRaid = UnitInRaid

local C_GuildInfo = C_GuildInfo
local C_Club = C_Club

local GUILD = _G.GUILD
local GUILD_MOTD = _G.GUILD_MOTD
local REMOTE_CHAT = _G.REMOTE_CHAT
local FRIENDS_LIST_ONLINE = _G.FRIENDS_LIST_ONLINE
local LABEL_NOTE = _G.LABEL_NOTE
local GUILD_RANK1_DESC = _G.GUILD_RANK1_DESC

local HDR = C.Colors.header
local LBL = C.Colors.label

local CLASS_COLORS = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS

ns:RegisterDefaults({
	guildText = {
		enable = true,
		maxMembers = 25,
		showMOTD = true,
	},
})

local GuildText = ns:NewModule("GuildText", "guildText", { group = "datatext", title = L["Guild"], order = 50 })

local cfg
local text
local hooksInstalled
local eventsRegistered
local resendRequest

local guildTable, clubTable = {}, {}
local guildMotD = ""

local GetGuildRosterMOTD = C_GuildInfo and C_GuildInfo.GetMOTD or _G.GetGuildRosterMOTD
local GuildRoster = C_GuildInfo and C_GuildInfo.GuildRoster

local classToken = {}
do
	local male = _G.LOCALIZED_CLASS_NAMES_MALE
	local female = _G.LOCALIZED_CLASS_NAMES_FEMALE
	if male then
		for token, localized in pairs(male) do
			classToken[localized] = token
		end
	end
	if female then
		for token, localized in pairs(female) do
			classToken[localized] = token
		end
	end
end

local function ClassColorRGB(class)
	if not class then
		return 1, 1, 1
	end
	local token = classToken[class] or class
	local color = CLASS_COLORS and CLASS_COLORS[token]
	if color then
		return color.r, color.g, color.b
	end
	return 1, 1, 1
end

local function ShortName(name)
	if not name or F.IsSecret(name) then
		return name
	end
	if Ambiguate then
		return Ambiguate(name, "none")
	end
	return match(name, "([^%-]+).*") or name
end

local function InGroup(name)
	if not name or F.IsSecret(name) then
		return ""
	end
	return (UnitInParty(name) or UnitInRaid(name)) and "|cffaaaaaa*|r" or ""
end

local onlinestatus = {
	[0] = "",
	[1] = format(" |cffFFFFFF[|r|cffFF9900%s|r|cffFFFFFF]|r", _G.AFK or "AFK"),
	[2] = format(" |cffFFFFFF[|r|cffFF3333%s|r|cffFFFFFF]|r", _G.DND or "DND"),
}

local mobilestatus = {
	[0] = [[|TInterface\ChatFrame\UI-ChatIcon-ArmoryChat:14:14:0:0:16:16:0:16:0:16:73:177:73|t]],
	[1] = [[|TInterface\ChatFrame\UI-ChatIcon-ArmoryChat-AwayMobile:14:14:0:0:16:16:0:16:0:16|t]],
	[2] = [[|TInterface\ChatFrame\UI-ChatIcon-ArmoryChat-BusyMobile:14:14:0:0:16:16:0:16:0:16|t]],
}

local function SortByRank(a, b)
	if a and b then
		if a.rankIndex == b.rankIndex then
			return a.name < b.name
		end
		return a.rankIndex < b.rankIndex
	end
end

local function SortByName(a, b)
	if a and b then
		return a.name < b.name
	end
end

local function SortGuildTable(shiftDown)
	if shiftDown then
		sort(guildTable, SortByRank)
	else
		sort(guildTable, SortByName)
	end
end

local function BuildClubTable()
	wipe(clubTable)
	if not (C_Club and C_Club.GetSubscribedClubs and CommunitiesUtil) then
		return
	end

	local clubs = C_Club.GetSubscribedClubs()
	if not (F.NotSecret(clubs) and clubs) then
		return
	end

	local guildClubID
	for _, data in pairs(clubs) do
		if F.NotSecretTable(data) and data.clubType == Enum.ClubType.Guild then
			guildClubID = data.clubId
			break
		end
	end
	if not guildClubID then
		return
	end

	local ok, members = pcall(CommunitiesUtil.GetMemberIdsSortedByName, guildClubID)
	if not ok or not F.NotSecret(members) then
		return
	end

	ok, members = pcall(CommunitiesUtil.GetMemberInfo, guildClubID, members)
	if not ok or not members then
		return
	end

	ok, members = pcall(CommunitiesUtil.SortMemberInfo, guildClubID, members)
	if not ok or not members then
		return
	end

	for _, data in pairs(members) do
		if F.NotSecretTable(data) and data.guid then
			clubTable[data.guid] = data
		end
	end
end

function GuildText:BuildGuildTable()
	wipe(guildTable)
	BuildClubTable()

	local totalMembers = GetNumGuildMembers()
	if not totalMembers or F.IsSecret(totalMembers) then
		return
	end

	for i = 1, totalMembers do
		local name, rank, rankIndex, level, _, zone, note, officerNote, connected, memberstatus, className, _, _, isMobile, _, _, guid = GetGuildRosterInfo(i)
		if not name then
			return
		end

		local statusInfo = isMobile and mobilestatus[memberstatus] or onlinestatus[memberstatus]
		if isMobile and not connected then
			zone = REMOTE_CHAT
		end

		if connected or isMobile then
			local clubMember = guid and clubTable[guid]
			local safeNote = F.NotSecret(note) and note or ""
			local safeOfficerNote = F.NotSecret(officerNote) and officerNote or ""
			local safeZone = F.NotSecret(zone) and zone or ""
			local safeRank = F.NotSecret(rank) and rank or ""
			local safeRankIndex = F.NotSecret(rankIndex) and rankIndex or 0
			local safeLevel = F.NotSecret(level) and level or 0

			guildTable[#guildTable + 1] = {
				name = ShortName(name),
				rank = safeRank,
				level = safeLevel,
				zone = safeZone,
				note = safeNote,
				officerNote = safeOfficerNote,
				status = statusInfo,
				class = F.NotSecret(className) and className or nil,
				rankIndex = safeRankIndex,
				isMobile = isMobile,
				timerunningID = clubMember and F.NotSecret(clubMember.timerunningSeasonID) and clubMember.timerunningSeasonID or nil,
				faction = clubMember and F.NotSecret(clubMember.faction) and clubMember.faction or nil,
			}
		end
	end
end

function GuildText:UpdateMotD()
	if InCombatLockdown() then
		return
	end
	local motd = GetGuildRosterMOTD and GetGuildRosterMOTD()
	guildMotD = F.NotSecret(motd) and motd or ""
end

function GuildText:UpdateDisplay()
	if not text then
		return
	end
	if not cfg.enable or not IsInGuild() then
		text:Hide()
		return
	end
	text:SetText(tostring(#guildTable))
	text:Show()
end

function GuildText:ShowTooltip(noUpdate)
	if not cfg.enable or not IsInGuild() then
		return
	end

	local button = _G.GuildMicroButton
	if not button then
		return
	end

	if #guildTable == 0 then
		self:BuildGuildTable()
	end

	local shiftDown = IsShiftKeyDown()
	SortGuildTable(shiftDown)

	local online = #guildTable
	local total = GetNumGuildMembers()
	if F.IsSecret(total) then
		total = online
	end

	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:ClearLines()

	local guildName, guildRank = GetGuildInfo("player")
	if guildName and F.NotSecret(guildName) then
		GameTooltip:AddDoubleLine(guildName, format("%s: %d/%d", GUILD or "Guild", online, total), HDR.r, HDR.g, HDR.b, HDR.r, HDR.g, HDR.b)
		if guildRank and F.NotSecret(guildRank) then
			GameTooltip:AddLine(guildRank, HDR.r, HDR.g, HDR.b)
		end
	end

	if cfg.showMOTD and guildMotD ~= "" then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(format("%s - %s", GUILD_MOTD or "MOTD", guildMotD), LBL.r, LBL.g, LBL.b, 1)
	end

	local playerZone = GetZoneText()
	GameTooltip:AddLine(" ")
	local limit = cfg.maxMembers or 25
	local useLimit = limit > 0

	for i, info in ipairs(guildTable) do
		if useLimit and i > limit then
			local count = online - limit
			if count > 1 then
				GameTooltip:AddLine(format("+%d %s...", count, FRIENDS_LIST_ONLINE or "online"), LBL.r, LBL.g, LBL.b)
			end
			break
		end

		local zoneActive = playerZone and info.zone and playerZone == info.zone
		local zoneR, zoneG, zoneB = zoneActive and 0.3 or 0.65, zoneActive and 1 or 0.65, zoneActive and 0.3 or 0.65
		local classR, classG, classB = ClassColorRGB(info.class)
		local levelColor = GetQuestDifficultyColor(info.level)
		local levelR, levelG, levelB = levelColor.r, levelColor.g, levelColor.b

		if shiftDown then
			GameTooltip:AddDoubleLine(format("%s |cff999999-|r %s", info.name, info.rank), info.zone, classR, classG, classB, zoneR, zoneG, zoneB)
			if info.note ~= "" then
				GameTooltip:AddLine(format("   %s: %s", LABEL_NOTE or "Note", info.note), LBL.r, LBL.g, LBL.b, 1)
			end
			if info.officerNote ~= "" then
				GameTooltip:AddLine(format("   %s: %s", GUILD_RANK1_DESC or "Officer Note", info.officerNote), 0.3, 1, 0.3, 1)
			end
		else
			GameTooltip:AddDoubleLine(format("|cff%02x%02x%02x%d|r |cff%02x%02x%02x%s|r%s%s", levelR * 255, levelG * 255, levelB * 255, info.level, classR * 255, classG * 255, classB * 255, info.name, InGroup(info.name), info.status or ""), info.zone, classR, classG, classB, zoneR, zoneG, zoneB)
		end
	end

	if not shiftDown and #guildTable > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L["Hold Shift for rank and notes"], LBL.r, LBL.g, LBL.b)
	end

	if not noUpdate and GuildRoster then
		GuildRoster()
	end

	GameTooltip:Show()
end

local FRIEND_ONLINE = _G.ERR_FRIEND_ONLINE_SS and select(2, strsplit(" ", _G.ERR_FRIEND_ONLINE_SS, 2))

function GuildText:PLAYER_ENTERING_WORLD()
	if not cfg.enable or not IsInGuild() then
		self:UpdateDisplay()
		return
	end
	if GuildRoster then
		GuildRoster()
	end
	self:UpdateMotD()
end

function GuildText:PLAYER_GUILD_UPDATE()
	if not cfg.enable then
		self:UpdateDisplay()
		return
	end
	if IsInGuild() and GuildRoster then
		GuildRoster()
	else
		wipe(guildTable)
		guildMotD = ""
		self:UpdateDisplay()
	end
end

function GuildText:GUILD_ROSTER_UPDATE()
	if not cfg.enable then
		return
	end
	if resendRequest then
		resendRequest = false
		if GuildRoster then
			GuildRoster()
		end
		return
	end

	self:BuildGuildTable()
	self:UpdateMotD()
	self:UpdateDisplay()

	local button = _G.GuildMicroButton
	if button and MouseIsOver(button) then
		self:ShowTooltip(true)
	end
end

function GuildText:GUILD_MOTD(_, arg1)
	if not cfg.enable then
		return
	end
	guildMotD = F.NotSecret(arg1) and arg1 or ""
	local button = _G.GuildMicroButton
	if button and MouseIsOver(button) and cfg.showMOTD then
		self:ShowTooltip(true)
	end
end

function GuildText:CHAT_MSG_SYSTEM(_, arg1)
	if not cfg.enable or not FRIEND_ONLINE or not arg1 or F.IsSecret(arg1) then
		return
	end
	if find(arg1, FRIEND_ONLINE, 1, true) then
		resendRequest = true
	end
end

function GuildText:MODIFIER_STATE_CHANGED()
	if not cfg.enable then
		return
	end
	local button = _G.GuildMicroButton
	if button and MouseIsOver(button) then
		self:ShowTooltip(true)
	end
end

local function OnEnterHook()
	GuildText:ShowTooltip()
end

function GuildText:InstallHooks()
	if hooksInstalled then
		return
	end
	local button = _G.GuildMicroButton
	if not button then
		return
	end
	button:HookScript("OnEnter", OnEnterHook)
	hooksInstalled = true
end

function GuildText:Create()
	local button = _G.GuildMicroButton
	if not button then
		return
	end

	if not text then
		-- Parent the count to its own overlay frame above the button so Blizzard's
		-- HIGHLIGHT-layer tabard emblem (drawn on hover) can't cover the OVERLAY text.
		local overlay = CreateFrame("Frame", nil, button)
		overlay:SetAllPoints(button)
		overlay:SetFrameLevel(button:GetFrameLevel() + 4)

		text = F.CreateFS(overlay, 12)
		text:SetPoint("CENTER", button, "CENTER", 0, -4)
		text:SetTextColor(1, 1, 1)
	end

	self:InstallHooks()

	if not eventsRegistered then
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
		self:RegisterEvent("PLAYER_GUILD_UPDATE")
		self:RegisterEvent("GUILD_ROSTER_UPDATE")
		self:RegisterEvent("GUILD_MOTD")
		self:RegisterEvent("CHAT_MSG_SYSTEM")
		self:RegisterEvent("MODIFIER_STATE_CHANGED")
		eventsRegistered = true
	end

	if IsInGuild() and GuildRoster then
		GuildRoster()
	end

	self:UpdateDisplay()
end

function GuildText:OnEnable()
	cfg = ns.db.guildText
	if not cfg.enable then
		return
	end
	self:Create()
end

function GuildText:OnSettingChanged(key, value)
	cfg = ns.db.guildText
	if key == "enable" then
		if value then
			self:Create()
		elseif text then
			text:Hide()
		end
	elseif key == "maxMembers" or key == "showMOTD" then
		local button = _G.GuildMicroButton
		if button and MouseIsOver(button) then
			self:ShowTooltip(true)
		end
	end
end

function GuildText:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Guild Text"], L["Show online guild member count on the Guild micro button with a roster tooltip (reload to disable)."])
	local _, maxMembersInit = builder:Slider(category, self, "maxMembers", L["Max Members"], L["Maximum members shown in the guild tooltip before collapsing the rest."], 5, 50, 1)
	local _, motdInit = builder:Checkbox(category, self, "showMOTD", L["Show MOTD"], L["Show the guild message of the day in the tooltip."])

	builder:DependsOn(maxMembersInit, enableInit)
	builder:DependsOn(motdInit, enableInit)
end
