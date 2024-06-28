local _, Module = ...
local L = Module.L

local C_PetBattles_IsInBattle = C_PetBattles.IsInBattle
local C_Timer_After = C_Timer.After
local C_Timer_NewTicker = C_Timer.NewTicker
local C_Timer_NewTimer = C_Timer.NewTimer
local math_floor = math.floor
local math_random = math.random
local string_format = string.format
local string_gsub = string.gsub
local string_sub = string.sub

local ChatFrame_GetMobileEmbeddedTexture = ChatFrame_GetMobileEmbeddedTexture
local ChatHistory_GetAccessID = ChatHistory_GetAccessID
local ChatTypeInfo = ChatTypeInfo
local Chat_GetChatCategory = Chat_GetChatCategory
local CreateFrame = CreateFrame
local GetAchievementInfo = GetAchievementInfo
local GetBattlefieldStatus = GetBattlefieldStatus
local GetColoredName = GetColoredName
local GetGuildInfo = GetGuildInfo
local GetScreenHeight = GetScreenHeight
local GetScreenWidth = GetScreenWidth
local GetStatistic = GetStatistic
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local IsInGuild = IsInGuild
local IsMacClient = IsMacClient
local IsShiftKeyDown = IsShiftKeyDown
local NONE = NONE
local SetCVar = SetCVar
local UIParent = UIParent
local UnitCastingInfo = UnitCastingInfo
local UnitIsAFK = UnitIsAFK

local AFKMode

local ignoreKeys = {
	LALT = true,
	LSHIFT = true,
	RSHIFT = true,
}

local printKeys = {
	["PRINTSCREEN"] = true,
}

local monthAbr = {
	[1] = "Jan",
	[2] = "Feb",
	[3] = "Mar",
	[4] = "Apr",
	[5] = "May",
	[6] = "Jun",
	[7] = "Jul",
	[8] = "Aug",
	[9] = "Sep",
	[10] = "Oct",
	[11] = "Nov",
	[12] = "Dec",
}

local daysAbr = {
	[1] = "Sun",
	[2] = "Mon",
	[3] = "Tue",
	[4] = "Wed",
	[5] = "Thu",
	[6] = "Fri",
	[7] = "Sat",
}

-- Source wowhead.com
local stats = {
	60, -- Total deaths
	94, -- Quests abandoned
	97, -- Daily quests completed
	98, -- Quests completed
	107, -- Creatures killed
	112, -- Deaths from drowning
	114, -- Deaths from falling
	115, -- Deaths from fire and lava
	319, -- Duels won
	320, -- Duels lost
	326, -- Gold from quest rewards
	328, -- Total gold acquired
	329, -- Auctions posted
	331, -- Most expensive bid on auction
	332, -- Most expensive auction sold
	333, -- Gold looted
	334, -- Most gold ever owned
	338, -- Vanity pets owned
	345, -- Health potions consumed
	349, -- Flight paths taken
	353, -- Number of times hearthed
	588, -- Total Honorable Kills
	812, -- Healthstones used
	837, -- Arenas won
	838, -- Arenas played
	839, -- Battlegrounds played
	840, -- Battlegrounds won
	919, -- Gold earned from auctions
	932, -- Total 5-player dungeons entered
	933, -- Total 10-player raids entered
	934, -- Total 25-player raids entered
	1042, -- Number of hugs
	1045, -- Total cheers
	1047, -- Total facepalms
	1065, -- Total waves
	1066, -- Total times LOL"d
	1197, -- Total kills
	1198, -- Total kills that grant experience or honor
	1336, -- Creature type killed the most
	1339, -- Mage portal taken most
	1487, -- Total Killing Blows
	1491, -- Battleground Killing Blows
	1518, -- Fish caught
	1776, -- Food eaten most
	2277, -- Summons accepted
	5692, -- Rated battlegrounds played
	5693, -- Rated battleground played the most
	5695, -- Rated battleground won the most
	5694, -- Rated battlegrounds won
	7399, -- Challenge mode dungeons completed
	8278, -- Pet Battles won at max level
}

local function IsIn(val, ...)
	for i = 1, select("#", ...) do
		if val == select(i, ...) then
			return true
		end
	end
	return false
end

local function setupTime(color, hour, minute)
	local useMilitaryTime = GetCVarBool("timeMgrUseMilitaryTime")

	if useMilitaryTime then
		return string.format("%s" .. TIMEMANAGER_TICKER_24HOUR, color, hour, minute)
	else
		local timerUnit = Module.MyClassColor .. (hour < 12 and " AM" or " PM")

		if hour >= 12 then
			hour = hour - 12
		else
			if hour == 0 then
				hour = 12
			end
		end

		return string.format("%s" .. TIMEMANAGER_TICKER_12HOUR .. timerUnit, color, hour, minute)
	end
end

local function createTime(self)
	local color = C_Calendar.GetNumPendingInvites() > 0 and "|cffFF0000" or ""
	local hour, minute

	if GetCVarBool("timeMgrUseLocalTime") then
		hour, minute = tonumber(date("%H")), tonumber(date("%M"))
	else
		hour, minute = GetGameTime()
	end

	self.top.time:SetText(setupTime(color, hour, minute))
end

-- Create Date
local function createDate(self)
	local date = C_DateAndTime.GetCurrentCalendarTime()
	local presentWeekday = date.weekday
	local presentMonth = date.month
	local presentDay = date.monthDay
	local presentYear = date.year

	self.top.date:SetFormattedText("%s, %s %d, %d", daysAbr[presentWeekday], monthAbr[presentMonth], presentDay, presentYear)
end

local function UpdateLogOff(self)
	local timePassed = GetTime() - self.startTime

	local timeLeft = 30 * 60 - timePassed
	local minutes = math_floor(timeLeft / 60)
	local seconds = math_floor(timeLeft % 60)

	self.top.Status:SetValue(math_floor(timeLeft))

	if minutes == 0 and seconds == 0 then
		self.logoffTimer:Cancel()
		self.countd.text:SetFormattedText("%s: |cfff0ff0000:00|r", "Logout Timer")
	else
		self.countd.text:SetFormattedText("%s: |cfff0ff00-%02d:%02d|r", "Logout Timer", minutes, seconds)
	end
end

local function UpdateTimer(self)
	createTime(self)
	createDate(self)
end

-- Create random stats
local function createStats()
	local id = stats[math_random(#stats)]
	local _, name = GetAchievementInfo(id)
	local result = GetStatistic(id)
	if result == "--" then
		result = NONE
	end

	return string.format("%s: |cfff0ff00%s|r", name, result)
end

local function UpdateStatMessage(self)
	UIFrameFadeIn(self.statMsg.info, 1, 1, 0)
	local createdStat = createStats()
	self.statMsg.info:SetText(createdStat)
	UIFrameFadeIn(self.statMsg.info, 1, 0, 1)
end

local function SetAFK(self, status)
	if status then
		MoveViewLeftStart(0.035)
		self:Show()
		CloseAllWindows()
		UIParent:Hide()

		if IsInGuild() then
			local guildName, guildRankName = GetGuildInfo("player")
			self.bottom.guild:SetFormattedText("<%s> [%s]", guildName, guildRankName)
		else
			self.bottom.guild:SetText(L["No Guild"])
		end

		self.bottom.model.curAnimation = "wave"
		self.bottom.model.startTime = GetTime()
		self.bottom.model.duration = 2.3
		self.bottom.model:SetUnit("player")
		self.bottom.model.isIdle = nil
		self.bottom.model:SetAnimation(67)
		self.bottom.model:SetFacing(6)
		self.bottom.model:SetCamDistanceScale(4.5)
		self.bottom.model.idleDuration = 1

		self.bottom.modelPet.curAnimation = "wave"
		self.bottom.modelPet.startTime = GetTime()
		self.bottom.modelPet.duration = 2.3
		self.bottom.modelPet:SetUnit("pet")
		self.bottom.modelPet.isIdle = nil
		self.bottom.modelPet:SetAnimation(67)
		self.bottom.modelPet:SetFacing(6)
		self.bottom.modelPet:SetCamDistanceScale(9)
		self.bottom.modelPet.idleDuration = 1

		self.startTime = GetTime()

		if self.timer then
			self.timer:Cancel()
			self.timer = nil
		end

		self.timer = C_Timer.NewTicker(1, function()
			UpdateTimer(self)
		end)

		if self.statsTimer then
			self.statsTimer:Cancel()
		end

		self.statsTimer = C_Timer_NewTicker(5, function()
			UpdateStatMessage(self)
		end)

		if self.logoffTimer then
			self.logoffTimer:Cancel()
		end

		self.logoffTimer = C_Timer_NewTicker(1, function()
			UpdateLogOff(self)
		end)

		self.chat:RegisterEvent("CHAT_MSG_WHISPER")
		self.chat:RegisterEvent("CHAT_MSG_BN_WHISPER")
		self.chat:RegisterEvent("CHAT_MSG_GUILD")
		self.chat:RegisterEvent("CHAT_MSG_PARTY")
		self.chat:RegisterEvent("CHAT_MSG_RAID")

		self.isAFK = true
	elseif self.isAFK then
		UIParent:Show()
		self:Hide()
		MoveViewLeftStop()

		if self.startTime then
			self.startTime = nil
		end

		if self.timer then
			self.timer:Cancel()
		end

		if self.statsTimer then
			self.statsTimer:Cancel()
		end

		if self.logoffTimer then
			self.logoffTimer:Cancel()
		end

		if self.animTimer then
			self.animTimer:Cancel()
		end

		self.countd.text:SetFormattedText("%s: |cfff0ff00-30:00|r", "Logout Timer")
		self.statMsg.info:SetFormattedText("|cffb3b3b3%s|r", "Random Stats")

		self.chat:UnregisterAllEvents()
		self.chat:Clear()
		if PVEFrame:IsShown() then
			PVEFrame_ToggleFrame()
			PVEFrame_ToggleFrame()
		end

		self.isAFK = false
	end
end

local function AFKMode_OnEvent(self, event, arg1, ...)
	if IsIn(event, "PLAYER_REGEN_DISABLED", "LFG_PROPOSAL_SHOW", "UPDATE_BATTLEFIELD_STATUS") then
		if event ~= "UPDATE_BATTLEFIELD_STATUS" or (GetBattlefieldStatus(arg1, ...) == "confirm") then
			SetAFK(self, false)
		end

		if event == "PLAYER_REGEN_DISABLED" then
			self:RegisterEvent("PLAYER_REGEN_ENABLED")
		end
		return
	end

	if event == "PLAYER_REGEN_ENABLED" then
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	end

	if (event == "PLAYER_FLAGS_CHANGED" and arg1 ~= "player") or (InCombatLockdown() or CinematicFrame:IsShown() or MovieFrame:IsShown()) then
		return
	end

	if UnitCastingInfo("player") ~= nil then
		--Don't activate afk if player is crafting stuff, check back in 30 seconds
		C_Timer.After(30, function()
			AFKMode_OnEvent(self)
		end)
		return
	end

	SetAFK(self, UnitIsAFK("player") and not C_PetBattles.IsInBattle())
end

local function OnKeyDown(self, key)
	if ignoreKeys[key] then
		return
	end

	if printKeys[key] then
		Screenshot()
	else
		SetAFK(self, false)
		C_Timer.After(60, function()
			AFKMode_OnEvent(self)
		end)
	end
end

local function Chat_OnMouseWheel(self, delta)
	if delta == 1 and IsShiftKeyDown() then
		self:ScrollToTop()
	elseif delta == -1 and IsShiftKeyDown() then
		self:ScrollToBottom()
	elseif delta == -1 then
		self:ScrollDown()
	else
		self:ScrollUp()
	end
end

local function Chat_OnEvent(self, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14)
	local coloredName = GetColoredName(event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14)
	local chatType = strsub(event, 10)
	local info = ChatTypeInfo[chatType]

	if event == "CHAT_MSG_BN_WHISPER" then
		coloredName = format("|c%s%s|r", RAID_CLASS_COLORS.PRIEST.colorStr, arg2)
	end

	arg1 = RemoveExtraSpaces(arg1)

	local chatGroup = Chat_GetChatCategory(chatType)
	local chatTarget
	if chatGroup == "BN_CONVERSATION" then
		chatTarget = tostring(arg8)
	elseif chatGroup == "WHISPER" or chatGroup == "BN_WHISPER" then
		if not (strsub(arg2, 1, 2) == "|K") then
			chatTarget = arg2:upper()
		else
			chatTarget = arg2
		end
	end

	local playerLink
	if chatType ~= "BN_WHISPER" and chatType ~= "BN_CONVERSATION" then
		playerLink = "|Hplayer:" .. arg2 .. ":" .. arg11 .. ":" .. chatGroup .. (chatTarget and ":" .. chatTarget or "") .. "|h"
	else
		playerLink = "|HBNplayer:" .. arg2 .. ":" .. arg13 .. ":" .. arg11 .. ":" .. chatGroup .. (chatTarget and ":" .. chatTarget or "") .. "|h"
	end

	--Escape any % characters, as it may otherwise cause an "invalid option in format" error in the next step
	arg1 = gsub(arg1, "%%", "%%%%")

	--Remove groups of many spaces
	arg1 = RemoveExtraSpaces(arg1)

	-- isMobile
	if arg14 then
		arg1 = ChatFrame_GetMobileEmbeddedTexture(info.r, info.g, info.b) .. arg1
	end

	local _, body = pcall(format, _G["CHAT_" .. chatType .. "_GET"] .. arg1, playerLink .. "[" .. coloredName .. "]" .. "|h")

	local accessID = ChatHistory_GetAccessID(chatGroup, chatTarget)
	local typeID = ChatHistory_GetAccessID(chatType, chatTarget, arg12 == "" and arg13 or arg12)

	-- if GW.settings.CHAT_SHORT_CHANNEL_NAMES then
	-- 	body = body:gsub("|Hchannel:(.-)|h%[(.-)%]|h", GW.ShortChannel)
	-- 	body = body:gsub("^(.-|h) " .. CHAT_WHISPER_GET:format("~"):gsub("~ ", ""):gsub(": ", ""), "%1")
	-- 	body = body:gsub("<" .. AFK .. ">", "[|cffFF0000" .. AFK .. "|r] ")
	-- 	body = body:gsub("<" .. DND .. ">", "[|cffE7E716" .. DND .. "|r] ")
	-- 	body = body:gsub("%[BN_CONVERSATION:", "%[" .. "")
	-- end

	self:AddMessage(body, info.r, info.g, info.b, info.id, false, accessID, typeID)
end

local function LoopAnimations(self)
	if self.curAnimation == "wave" then
		self:SetAnimation(69)
		self.curAnimation = "dance"
		self.startTime = GetTime()
		self.duration = 300
		self.isIdle = false
		self.idleDuration = 120
	elseif self.curAnimation == "dance" then
		self:SetAnimation(71)
		self:SetCamDistanceScale(5.5)
		self:SetFacing(1)
		self.curAnimation = "sleep"
		self.startTime = GetTime()
		self.duration = 3000
		self.isIdle = false
		self.idleDuration = 120
	end
end

local function ToggleAFKMode()
	if Module.db.profile.miscellaneous.enableAFKMode then
		AFKMode:RegisterEvent("PLAYER_FLAGS_CHANGED")
		AFKMode:RegisterEvent("PLAYER_REGEN_DISABLED")
		AFKMode:RegisterEvent("LFG_PROPOSAL_SHOW")
		AFKMode:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
		AFKMode:SetScript("OnEvent", AFKMode_OnEvent)
		C_CVar.SetCVar("autoClearAFK", "1")
	else
		AFKMode:UnregisterAllEvents()
		AFKMode:SetScript("OnEvent", nil)
		C_CVar.SetCVar("autoClearAFK", "1")
	end
end
Module.ToggleAFKMode = ToggleAFKMode

function Module:PLAYER_LOGIN()
	local playerName = Module.MyName

	AFKMode = CreateFrame("Frame")
	AFKMode:SetFrameLevel(1)
	AFKMode:SetScale(UIParent:GetScale())
	AFKMode:SetAllPoints(UIParent)
	AFKMode:Hide()
	AFKMode:EnableKeyboard(true)
	AFKMode:SetScript("OnKeyDown", OnKeyDown)

	AFKMode.chat = CreateFrame("ScrollingMessageFrame", nil, AFKMode)
	AFKMode.chat:SetSize(500, 200)
	AFKMode.chat:SetFont(UNIT_NAME_FONT, 12, "")
	AFKMode.chat:SetJustifyH("LEFT")
	AFKMode.chat:SetMaxLines(100)
	AFKMode.chat:EnableMouseWheel(true)
	AFKMode.chat:SetFading(false)
	AFKMode.chat:SetMovable(true)
	AFKMode.chat:EnableMouse(true)
	AFKMode.chat:RegisterForDrag("LeftButton")
	AFKMode.chat:SetScript("OnDragStart", AFKMode.chat.StartMoving)
	AFKMode.chat:SetScript("OnDragStop", AFKMode.chat.StopMovingOrSizing)
	AFKMode.chat:SetScript("OnMouseWheel", Chat_OnMouseWheel)
	AFKMode.chat:SetScript("OnEvent", Chat_OnEvent)

	AFKMode.top = CreateFrame("Frame", nil, AFKMode, "TooltipBackdropTemplate")
	AFKMode.top:SetFrameLevel(0)
	AFKMode.top:SetPoint("TOP", AFKMode, "TOP", 0, 2)
	AFKMode.top:SetWidth(GetScreenWidth() + (((1 / UIParent:GetScale()) - ((1 - (768 / Module.ScreenHeight)) / UIParent:GetScale())) * 2 * 2))
	AFKMode.top:SetHeight(GetScreenHeight() * (0.6 / 10))

	AFKMode.chat:SetPoint("TOPLEFT", AFKMode.top, "BOTTOMLEFT", 10, -6)

	AFKMode.bottom = CreateFrame("Frame", nil, AFKMode, "TooltipBackdropTemplate")
	AFKMode.bottom:SetFrameLevel(0)
	AFKMode.bottom:SetPoint("BOTTOM", AFKMode, "BOTTOM", 0, -2)
	AFKMode.bottom:SetWidth(GetScreenWidth() + (((1 / UIParent:GetScale()) - ((1 - (768 / Module.ScreenHeight)) / UIParent:GetScale())) * 2 * 2))
	AFKMode.bottom:SetHeight(GetScreenHeight() * (0.9 / 10))

	AFKMode.bottom.logo = AFKMode:CreateTexture(nil, "OVERLAY")
	AFKMode.bottom.logo:SetSize(256 / 1.6, 256 / 1.6)
	AFKMode.bottom.logo:SetPoint("CENTER", AFKMode.bottom, "CENTER", 0, 60)
	AFKMode.bottom.logo:SetTexture(Module.Logo256)

	AFKMode.top.time = AFKMode.top:CreateFontString(nil, "OVERLAY")
	AFKMode.top.time:SetFont(UNIT_NAME_FONT, 16, "")
	AFKMode.top.time:SetText("")
	AFKMode.top.time:SetPoint("RIGHT", AFKMode.top, "RIGHT", -20, 0)
	AFKMode.top.time:SetJustifyH("LEFT")
	AFKMode.top.time:SetTextColor(0.7, 0.7, 0.7)

	-- WoW logo
	AFKMode.top.wowlogo = CreateFrame("Frame", nil, AFKMode) -- need this to upper the logo layer
	AFKMode.top.wowlogo:SetPoint("TOP", AFKMode.top, "TOP", 0, -5)
	AFKMode.top.wowlogo:SetFrameStrata("MEDIUM")
	AFKMode.top.wowlogo:SetSize(300, 150)
	AFKMode.top.wowlogo.tex = AFKMode.top.wowlogo:CreateTexture(nil, "OVERLAY")
	local currentExpansionLevel = GetClampedCurrentExpansionLevel()
	local expansionDisplayInfo = GetExpansionDisplayInfo(currentExpansionLevel)
	if expansionDisplayInfo then
		AFKMode.top.wowlogo.tex:SetTexture(expansionDisplayInfo.logo)
	end
	AFKMode.top.wowlogo.tex:SetAllPoints()

	-- Date text
	AFKMode.top.date = AFKMode.top:CreateFontString(nil, "OVERLAY")
	AFKMode.top.date:SetFont(UNIT_NAME_FONT, 16, "")
	AFKMode.top.date:SetText("")
	AFKMode.top.date:SetPoint("LEFT", AFKMode.top, "LEFT", 20, 0)
	AFKMode.top.date:SetJustifyH("RIGHT")
	AFKMode.top.date:SetTextColor(0.7, 0.7, 0.7)

	-- Statusbar on Top frame decor showing time to log off (30mins)
	AFKMode.top.Status = CreateFrame("StatusBar", nil, AFKMode.top)
	AFKMode.top.Status:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	AFKMode.top.Status:SetMinMaxValues(0, 1800)
	AFKMode.top.Status:SetStatusBarColor(Module.r, Module.g, Module.b, 1)
	AFKMode.top.Status:SetFrameLevel(2)
	AFKMode.top.Status:SetPoint("TOPRIGHT", AFKMode.top, "BOTTOMRIGHT", -4, 10)
	AFKMode.top.Status:SetPoint("BOTTOMLEFT", AFKMode.top, "BOTTOMLEFT", 4, 4)
	AFKMode.top.Status:SetValue(0)

	local factionGroup, size, offsetX, offsetY, nameOffsetX, nameOffsetY = Module.MyFaction, 140, -20, -8, -10, -36
	if factionGroup == "Neutral" then
		factionGroup, size, offsetX, offsetY, nameOffsetX, nameOffsetY = "Panda", 90, 15, 10, 20, -5
	end

	local modelOffsetY = 240
	if Module.MyRace == "Human" then
		modelOffsetY = 195
	elseif Module.MyRace == "Worgen" then
		modelOffsetY = 280
	elseif Module.MyRace == "Tauren" or Module.MyRace == "HighmountainTauren" then
		modelOffsetY = 250
	elseif Module.MyRace == "Draenei" or Module.MyRace == "LightforgedDraenei" then
		if Module.MySex == 2 then
			modelOffsetY = 250
		end
	elseif Module.MyRace == "Pandaren" then
		if Module.MySex == 2 then
			modelOffsetY = 220
		elseif Module.MySex == 3 then
			modelOffsetY = 280
		end
	elseif Module.MyRace == "KulTiran" then
		if Module.MySex == 2 then
			modelOffsetY = 220
		elseif Module.MySex == 3 then
			modelOffsetY = 240
		end
	elseif Module.MyRace == "Goblin" then
		if Module.MySex == 2 then
			modelOffsetY = 240
		elseif Module.MySex == 3 then
			modelOffsetY = 220
		end
	elseif Module.MyRace == "Troll" or Module.MyRace == "ZandalariTroll" then
		if Module.MySex == 2 then
			modelOffsetY = 250
		elseif Module.MySex == 3 then
			modelOffsetY = 280
		end
	elseif Module.MyRace == "Dwarf" or Module.MyRace == "DarkIronDwarf" then
		if Module.MySex == 2 then
			modelOffsetY = 250
		end
	elseif Module.MyRace == "Vulpera" then
		modelOffsetY = 140
	end

	AFKMode.bottom.faction = AFKMode.bottom:CreateTexture(nil, "OVERLAY")
	AFKMode.bottom.faction:SetPoint("BOTTOMLEFT", AFKMode.bottom, "BOTTOMLEFT", offsetX, offsetY)
	AFKMode.bottom.faction:SetTexture("Interface/Timer/" .. factionGroup .. "-Logo")
	AFKMode.bottom.faction:SetSize(size, size)

	AFKMode.bottom.name = AFKMode.bottom:CreateFontString(nil, "OVERLAY")
	AFKMode.bottom.name:SetFont(UNIT_NAME_FONT, 20, "")
	AFKMode.bottom.name:SetFormattedText("%s-%s", playerName, Module.MyRealm)
	AFKMode.bottom.name:SetPoint("TOPLEFT", AFKMode.bottom.faction, "TOPRIGHT", nameOffsetX, nameOffsetY)
	AFKMode.bottom.name:SetTextColor(Module.r, Module.g, Module.b)

	AFKMode.bottom.playerInfo = AFKMode.bottom:CreateFontString(nil, "OVERLAY")
	AFKMode.bottom.playerInfo:SetFont(UNIT_NAME_FONT, 20, "")
	AFKMode.bottom.playerInfo:SetText("|CFFFFCC66" .. LEVEL .. " " .. Module.MyLevel .. "|r " .. "|CFFC0C0C0" .. Module.MyRace .. "|r " .. Module.MyClassColor .. UnitClass("player") .. "|r")
	AFKMode.bottom.playerInfo:SetPoint("TOPLEFT", AFKMode.bottom.name, "BOTTOMLEFT", 0, -6)

	AFKMode.bottom.guild = AFKMode.bottom:CreateFontString(nil, "OVERLAY")
	AFKMode.bottom.guild:SetFont(UNIT_NAME_FONT, 20, "")
	AFKMode.bottom.guild:SetText(L["No Guild"])
	AFKMode.bottom.guild:SetPoint("TOPLEFT", AFKMode.bottom.playerInfo, "BOTTOMLEFT", 0, -6)
	AFKMode.bottom.guild:SetTextColor(0.7, 0.7, 0.7)

	-- Random stats decor (taken from install routine)
	AFKMode.statMsg = CreateFrame("Frame", nil, AFKMode)
	AFKMode.statMsg:SetSize(418, 72)
	AFKMode.statMsg:SetPoint("CENTER", 0, 260)

	AFKMode.statMsg.bg = AFKMode.statMsg:CreateTexture(nil, "BACKGROUND")
	AFKMode.statMsg.bg:SetTexture([[Interface\LevelUp\LevelUpTex]])
	AFKMode.statMsg.bg:SetPoint("BOTTOM")
	AFKMode.statMsg.bg:SetSize(326, 103)
	AFKMode.statMsg.bg:SetTexCoord(0.00195313, 0.63867188, 0.03710938, 0.23828125)
	AFKMode.statMsg.bg:SetVertexColor(1, 1, 1, 0.7)

	AFKMode.statMsg.lineTop = AFKMode.statMsg:CreateTexture(nil, "BACKGROUND")
	AFKMode.statMsg.lineTop:SetDrawLayer("BACKGROUND", 2)
	AFKMode.statMsg.lineTop:SetTexture([[Interface\LevelUp\LevelUpTex]])
	AFKMode.statMsg.lineTop:SetPoint("TOP")
	AFKMode.statMsg.lineTop:SetSize(418, 7)
	AFKMode.statMsg.lineTop:SetTexCoord(0.00195313, 0.81835938, 0.01953125, 0.03320313)

	AFKMode.statMsg.lineBottom = AFKMode.statMsg:CreateTexture(nil, "BACKGROUND")
	AFKMode.statMsg.lineBottom:SetDrawLayer("BACKGROUND", 2)
	AFKMode.statMsg.lineBottom:SetTexture([[Interface\LevelUp\LevelUpTex]])
	AFKMode.statMsg.lineBottom:SetPoint("BOTTOM")
	AFKMode.statMsg.lineBottom:SetSize(418, 7)
	AFKMode.statMsg.lineBottom:SetTexCoord(0.00195313, 0.81835938, 0.01953125, 0.03320313)

	-- Random stats frame
	AFKMode.statMsg.info = AFKMode.statMsg:CreateFontString(nil, "OVERLAY")
	AFKMode.statMsg.info:SetFont(UNIT_NAME_FONT, 18, "")
	AFKMode.statMsg.info:SetPoint("CENTER", AFKMode.statMsg, "CENTER", 0, -2)
	AFKMode.statMsg.info:SetText(string.format("|cffb3b3b3%s|r", "Random Stats"))
	AFKMode.statMsg.info:SetJustifyH("CENTER")
	AFKMode.statMsg.info:SetTextColor(0.7, 0.7, 0.7)

	-- Countdown decor
	AFKMode.countd = CreateFrame("Frame", nil, AFKMode)
	AFKMode.countd:SetSize(418, 36)
	AFKMode.countd:SetPoint("TOP", AFKMode.statMsg.lineBottom, "BOTTOM")

	AFKMode.countd.bg = AFKMode.countd:CreateTexture(nil, "BACKGROUND")
	AFKMode.countd.bg:SetTexture([[Interface\LevelUp\LevelUpTex]])
	AFKMode.countd.bg:SetPoint("BOTTOM")
	AFKMode.countd.bg:SetSize(326, 56)
	AFKMode.countd.bg:SetTexCoord(0.00195313, 0.63867188, 0.03710938, 0.23828125)
	AFKMode.countd.bg:SetVertexColor(1, 1, 1, 0.7)

	AFKMode.countd.lineBottom = AFKMode.countd:CreateTexture(nil, "BACKGROUND")
	AFKMode.countd.lineBottom:SetDrawLayer("BACKGROUND", 2)
	AFKMode.countd.lineBottom:SetTexture([[Interface\LevelUp\LevelUpTex]])
	AFKMode.countd.lineBottom:SetPoint("BOTTOM")
	AFKMode.countd.lineBottom:SetSize(418, 7)
	AFKMode.countd.lineBottom:SetTexCoord(0.00195313, 0.81835938, 0.01953125, 0.03320313)

	-- 30 mins countdown text
	AFKMode.countd.text = AFKMode.countd:CreateFontString(nil, "OVERLAY")
	AFKMode.countd.text:SetFont(UNIT_NAME_FONT, 12, "")
	AFKMode.countd.text:SetPoint("CENTER", AFKMode.countd, "CENTER")
	AFKMode.countd.text:SetJustifyH("CENTER")
	AFKMode.countd.text:SetFormattedText("%s: |cfff0ff00-30:00|r", "Logout Timer")
	AFKMode.countd.text:SetTextColor(0.7, 0.7, 0.7)

	--Use this frame to control position of the model
	AFKMode.bottom.modelHolder = CreateFrame("Frame", nil, AFKMode.bottom)
	AFKMode.bottom.modelHolder:SetSize(150, 150)
	AFKMode.bottom.modelHolder:SetPoint("BOTTOMRIGHT", AFKMode.bottom, "BOTTOMRIGHT", -200, modelOffsetY)

	AFKMode.bottom.model = CreateFrame("PlayerModel", nil, AFKMode.bottom.modelHolder)
	AFKMode.bottom.model:SetPoint("CENTER", AFKMode.bottom.modelHolder, "CENTER")
	AFKMode.bottom.model:SetSize(GetScreenWidth() * 2, GetScreenHeight() * 2)
	AFKMode.bottom.model:SetCamDistanceScale(4.5)
	AFKMode.bottom.model:SetFacing(6)
	AFKMode.bottom.model:SetScript("OnUpdate", function(self)
		local timePassed = GetTime() - self.startTime
		if timePassed > self.duration and self.isIdle ~= true then
			self:SetAnimation(0)
			self.isIdle = true
			AFKMode.animTimer = C_Timer.NewTimer(self.idleDuration, function()
				LoopAnimations(self)
			end)
		end
	end)

	AFKMode.bottom.modelPetHolder = CreateFrame("Frame", nil, AFKMode.bottom)
	AFKMode.bottom.modelPetHolder:SetSize(150, 150)
	AFKMode.bottom.modelPetHolder:SetPoint("BOTTOMRIGHT", AFKMode.bottom, "BOTTOMRIGHT", -500, 100)

	AFKMode.bottom.modelPet = CreateFrame("PlayerModel", nil, AFKMode.bottom.modelPetHolder)
	AFKMode.bottom.modelPet:SetPoint("CENTER", AFKMode.bottom.modelPetHolder, "CENTER")
	AFKMode.bottom.modelPet:SetSize(GetScreenWidth() * 2, GetScreenHeight() * 2)
	AFKMode.bottom.modelPet:SetCamDistanceScale(9)
	AFKMode.bottom.modelPet:SetFacing(6)
	AFKMode.bottom.modelPet:SetScript("OnUpdate", function(self)
		local timePassed = GetTime() - self.startTime
		if timePassed > self.duration and self.isIdle ~= true then
			self:SetAnimation(0)
			self.isIdle = true
			AFKMode.animTimer = C_Timer.NewTimer(self.idleDuration, function()
				LoopAnimations(self)
			end)
		end
	end)

	ToggleAFKMode()

	if IsMacClient() then
		printKeys[KEY_PRINTSCREEN_MAC] = true
	end
end
