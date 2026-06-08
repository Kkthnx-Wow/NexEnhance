--[[
	NexEnhance - AFK Camera
	-------------------------------------------------------------------------
	Immersive AFK overlay: rotating camera, character (and pet) model, clock,
	30-minute logout countdown, rotating account statistics and a whisper chat
	log. Exits on combat, LFG/battlefield popups, or any key press.

	Originally from ElvUI by the Tukui team:
	  https://github.com/tukui-org/ElvUI/blob/main/ElvUI/Game/Shared/Modules/Misc/AFK.lua
	Model animation cycle and holder offsets adapted from GW2 UI by Mortalknight:
	  https://github.com/Mortalknight/GW2_UI/blob/main/Games/Shared/Misc/afk.lua
--]]

-- luacheck: globals CloseAllWindows MoveViewLeftStart MoveViewLeftStop GetColoredName RemoveExtraSpaces
-- luacheck: globals ChatTypeInfo Chat_GetChatCategory ChatHistory_GetAccessID ChatFrame_GetMobileEmbeddedTexture
-- luacheck: globals CALENDAR_WEEKDAY_NAMES CALENDAR_FULLDATE_MONTH_NAMES TIMEMANAGER_TICKER_12HOUR TIMEMANAGER_TICKER_24HOUR
-- luacheck: globals PVEFrame PVEFrame_ToggleFrame KEY_PRINTSCREEN_MAC NONE
---@diagnostic disable: undefined-field
local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local _G = _G
local math_floor = math.floor
local math_random = math.random
local pcall = pcall
local select = select
local format = string.format
local gsub = string.gsub
local sub = string.sub
local tonumber = tonumber
local tostring = tostring
local date = date

local CreateFrame = CreateFrame
local GetTime = GetTime
local GetGameTime = GetGameTime
local GetCVarBool = GetCVarBool
local SetCVar = SetCVar
local UIParent = UIParent
local UnitIsAFK = UnitIsAFK
local UnitExists = UnitExists
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local InCombatLockdown = InCombatLockdown
local IsShiftKeyDown = IsShiftKeyDown
local IsInGuild = IsInGuild
local GetGuildInfo = GetGuildInfo
local GetScreenWidth = GetScreenWidth
local GetScreenHeight = GetScreenHeight
local GetAchievementInfo = GetAchievementInfo
local GetStatistic = GetStatistic
local GetBattlefieldStatus = GetBattlefieldStatus
local GetClampedCurrentExpansionLevel = GetClampedCurrentExpansionLevel
local GetExpansionDisplayInfo = GetExpansionDisplayInfo
local Screenshot = Screenshot
local IsMacClient = IsMacClient
local C_Timer = C_Timer
local C_Calendar = C_Calendar
local C_DateAndTime = C_DateAndTime
local C_PetBattles = C_PetBattles

local FONT = C.Media.Fonts.normal
local CLASS_COLOR = C.ClassColor
local BRAND = C.Colors.brand
local LOGO_TEX = C.Media.Textures.logo256
local LOGOUT_SECONDS = 1800 -- 30 minutes; matches default AFK logout timing
local CAMERA_SPEED = 0.035
local CAST_RECHECK_DELAY = 30
local KEY_RECHECK_DELAY = 60

-- Player model animations; holder position follows each entry (GW2 UI / ElvUI pattern).
local ANIMATIONS = {
	wave = { id = 67, facing = 6, wait = 5, offsetX = -200, offsetY = 220, duration = 2.3 },
	dance = { id = 69, facing = 6, wait = 30, offsetX = -200, offsetY = 220, duration = 300 },
	sleep = { id = 71, facing = 1, wait = 30, offsetX = -200, offsetY = 220, duration = 3000 },
}

local PET_MODEL = { offsetX = -500, offsetY = 100, camScale = 9, facing = 6 }

local function CancelTimer(handle)
	if handle and handle.Cancel then
		handle:Cancel()
	end
end

-- Classic Blizzard tooltip chrome (matches Install, Chat Copy, Changelog, etc.).
local BLIZZARD_BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true,
	tileSize = 16,
	edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

-- Letterbox layout (top bar); bottom bar.
local TOP_BAR = { height = 58, padX = 16, fontSize = 16 }
local BOTTOM_BAR = {
	heightScale = 0.10,
	heightTrim = 20,
	fontSize = 20,
	lineGap = 6,
}

local IGNORE_KEYS = {
	LALT = true,
	LSHIFT = true,
	RSHIFT = true,
}

local PRINT_KEYS = {
	PRINTSCREEN = true,
}

-- Statistics achievement IDs (GetStatistic accepts these directly on retail).
local STAT_IDS = {
	60, 94, 97, 98, 107, 112, 114, 115, 319, 320, 326, 328, 329, 331, 332, 333, 334, 338,
	345, 349, 353, 588, 812, 837, 838, 839, 840, 919, 932, 933, 934, 1042, 1045, 1047, 1065,
	1066, 1197, 1198, 1336, 1339, 1487, 1491, 1518, 1776, 2277, 5692, 5693, 5694, 5695, 7399,
	8278,
}

ns:RegisterDefaults({
	afkCam = {
		enable = true,
	},
})

local AFKCam = ns:NewModule("AFKCam", "afkCam", { group = "misc", title = L["AFK Camera"], order = 50 })

local afkFrame

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function IsEventInList(event, ...)
	for i = 1, select("#", ...) do
		if event == select(i, ...) then
			return true
		end
	end
end

local function CreateFS(parent, size, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(FONT, size or 14, "OUTLINE")
	fs:SetShadowOffset(1, -1)
	if justify then
		fs:SetJustifyH(justify)
	end
	return fs
end

local function CreateBar(parent)
	local bar = CreateFrame("StatusBar", nil, parent, "BackdropTemplate")
	bar:SetStatusBarTexture(C.Media.Textures.statusbar)
	bar:SetMinMaxValues(0, LOGOUT_SECONDS)
	bar:SetStatusBarColor(BRAND[1], BRAND[2], BRAND[3], 1)
	bar:SetBackdrop(BLIZZARD_BACKDROP)
	bar:SetBackdropColor(0, 0, 0, 0.35)
	bar:SetBackdropBorderColor(1, 1, 1)
	return bar
end

local function StylePanelBackdrop(panel, alpha)
	panel:SetBackdrop(BLIZZARD_BACKDROP)
	panel:SetBackdropColor(0.06, 0.06, 0.06, alpha or 0.9)
	panel:SetBackdropBorderColor(1, 1, 1)
end

local function FormatClock(hour, minute)
	local useMilitary = GetCVarBool("timeMgrUseMilitaryTime")
	local pending = C_Calendar.GetNumPendingInvites() > 0
	local color = pending and "|cffFF0000" or ""

	if useMilitary then
		local pattern = _G.TIMEMANAGER_TICKER_24HOUR or "%02d:%02d"
		return format("%s" .. pattern, color, hour, minute)
	end

	local suffix = hour >= 12 and " PM" or " AM"
	local displayHour = hour
	if displayHour > 12 then
		displayHour = displayHour - 12
	elseif displayHour == 0 then
		displayHour = 12
	end

	local classHex = F.RGBToHex(CLASS_COLOR[1], CLASS_COLOR[2], CLASS_COLOR[3])
	return format("%s%d:%02d|c%s%s|r", color, displayHour, minute, classHex, suffix)
end

local function FormatCalendarDate(calendarTime)
	local weekday = _G.CALENDAR_WEEKDAY_NAMES and _G.CALENDAR_WEEKDAY_NAMES[calendarTime.weekday]
	local monthName = _G.CALENDAR_FULLDATE_MONTH_NAMES and _G.CALENDAR_FULLDATE_MONTH_NAMES[calendarTime.month]
	if weekday and monthName then
		return format("%s, %s %d, %d", weekday, monthName, calendarTime.monthDay, calendarTime.year)
	end
	return format("%d/%d/%d", calendarTime.monthDay, calendarTime.month, calendarTime.year)
end

local function GetAnimation(model, key)
	if not key then
		local current = model.curAnimation
		if current == "wave" then
			key = "dance"
		elseif current == "dance" then
			key = "sleep"
		else
			key = "wave"
		end
	end
	return ANIMATIONS[key], key
end

local function ApplyAFKAnimation(frame, key)
	local model = frame.bottom.model
	local options, usedKey = GetAnimation(model, key)
	if not options then return end

	model.curAnimation = usedKey
	model.duration = options.duration
	model.idleDuration = options.wait
	model.startTime = GetTime()
	model.isIdle = nil
	model:SetFacing(options.facing)
	model:SetAnimation(options.id)

	local holder = frame.bottom.modelHolder
	if holder then
		holder:ClearAllPoints()
		holder:SetPoint("BOTTOMRIGHT", frame.bottom, "BOTTOMRIGHT", options.offsetX, options.offsetY)
	end
end

local function Model_OnUpdate(self)
	if self.isIdle then return end

	if GetTime() - self.startTime < self.duration then return end

	self:SetAnimation(0)
	self.isIdle = true

	local frame = self.afkFrame
	if not frame or not frame.isAFK then return end

	CancelTimer(frame.animTimer)
	frame.animTimer = C_Timer.After(self.idleDuration, function()
		if frame.isAFK then
			ApplyAFKAnimation(frame)
		end
	end)
end

-- Faction crest + text offsets
local function GetFactionLayout(faction)
	if faction == "Horde" then
		return "Horde", 140, -20, -10, -10, -36
	elseif faction == "Neutral" then
		return "Panda", 90, 15, 10, 20, -5
	end
	return "Alliance", 140, -20, -10, -10, -36
end

local function CreateRandomStatMessage()
	for _ = 1, 8 do
		local statID = STAT_IDS[math_random(#STAT_IDS)]
		local _, name = GetAchievementInfo(statID)
		if name then
			local result = GetStatistic(statID)
			if not result or result == "" or result == "--" then
				result = _G.NONE or "None"
			end
			return format("%s: |cfff0ff00%s|r", name, result)
		end
	end
	return L["AFK Random Stats"]
end

-- ---------------------------------------------------------------------------
-- Timers
-- ---------------------------------------------------------------------------
local function UpdateClock(frame)
	local hour
	local minute
	if GetCVarBool("timeMgrUseLocalTime") then
		hour, minute = tonumber(date("%H")), tonumber(date("%M"))
	else
		hour, minute = GetGameTime()
	end

	if minute ~= frame.lastMinute then
		frame.lastMinute = minute
		frame.top.time:SetText(FormatClock(hour, minute))
		local calendarTime = C_DateAndTime.GetCurrentCalendarTime()
		frame.top.date:SetText(FormatCalendarDate(calendarTime))
	end
end

local function UpdateLogout(frame)
	local elapsed = GetTime() - frame.startTime
	local remaining = LOGOUT_SECONDS - elapsed
	if remaining < 0 then remaining = 0 end

	frame.top.status:SetValue(remaining)

	local minutes = math_floor(remaining / 60)
	local seconds = math_floor(remaining % 60)
	if minutes <= 0 and seconds <= 0 then
		frame.countdown.text:SetFormattedText("%s |cffff000000:00|r", L["AFK Logout Timer"])
	else
		frame.countdown.text:SetFormattedText("%s |cfff0ff00-%02d:%02d|r", L["AFK Logout Timer"], minutes, seconds)
	end
end

local function UpdateStatMessage(frame)
	if frame.stat.info:GetAlpha() < 0.01 then
		frame.stat.info:SetAlpha(1)
	end
	frame.stat.info:SetText(CreateRandomStatMessage())
end

-- ---------------------------------------------------------------------------
-- Mode toggle
-- ---------------------------------------------------------------------------
local function SetAFKMode(frame, enable)
	if enable then
		if frame.isAFK then return end

		MoveViewLeftStart(CAMERA_SPEED)
		frame:Show()
		CloseAllWindows()
		UIParent:Hide()

		if IsInGuild() then
			local guildName, guildRank = GetGuildInfo("player")
			frame.bottom.guild:SetFormattedText("%s - %s", guildName or "", guildRank or "")
		else
			frame.bottom.guild:SetText(_G.GUILD_NOT_IN_GUILD or "No Guild")
		end

		local model = frame.bottom.model
		model:SetUnit("player")
		ApplyAFKAnimation(frame, "wave")

		local petModel = frame.bottom.modelPet
		if UnitExists("pet") then
			petModel:Show()
			petModel:SetUnit("pet")
			petModel:SetAnimation(0)
		else
			petModel:Hide()
		end

		frame.startTime = GetTime()
		frame.lastMinute = -1

		CancelTimer(frame.clockTimer)
		frame.clockTimer = C_Timer.NewTicker(1, function()
			UpdateClock(frame)
		end)
		UpdateClock(frame)

		CancelTimer(frame.statsTimer)
		frame.statsTimer = C_Timer.NewTicker(5, function()
			UpdateStatMessage(frame)
		end)
		UpdateStatMessage(frame)

		CancelTimer(frame.logoffTimer)
		frame.logoffTimer = C_Timer.NewTicker(1, function()
			UpdateLogout(frame)
		end)
		UpdateLogout(frame)

		frame.chat:RegisterEvent("CHAT_MSG_WHISPER")
		frame.chat:RegisterEvent("CHAT_MSG_BN_WHISPER")
		frame.chat:RegisterEvent("CHAT_MSG_GUILD")
		frame.chat:RegisterEvent("CHAT_MSG_PARTY")
		frame.chat:RegisterEvent("CHAT_MSG_RAID")

		frame.isAFK = true
		return
	end

	if not frame.isAFK then return end

	UIParent:Show()
	frame:Hide()
	MoveViewLeftStop()

	frame.startTime = nil
	CancelTimer(frame.clockTimer)
	CancelTimer(frame.statsTimer)
	CancelTimer(frame.logoffTimer)
	CancelTimer(frame.animTimer)
	if frame.bottom.model then
		frame.bottom.model.isIdle = true
	end

	frame.countdown.text:SetFormattedText("%s |cfff0ff00-30:00|r", L["AFK Logout Timer"])
	frame.stat.info:SetText(L["AFK Random Stats"])
	frame.stat.info:SetAlpha(1)

	frame.chat:UnregisterAllEvents()
	frame.chat:Clear()

	local pve = _G.PVEFrame
	if pve and pve:IsShown() and _G.PVEFrame_ToggleFrame then
		_G.PVEFrame_ToggleFrame()
		_G.PVEFrame_ToggleFrame()
	end

	frame.isAFK = false
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local function OnAFKEvent(frame, event, ...)
	if IsEventInList(event, "PLAYER_REGEN_DISABLED", "LFG_PROPOSAL_SHOW", "UPDATE_BATTLEFIELD_STATUS") then
		if event == "UPDATE_BATTLEFIELD_STATUS" then
			if GetBattlefieldStatus(...) ~= "confirm" then
				return
			end
		end
		SetAFKMode(frame, false)
		if event == "PLAYER_REGEN_DISABLED" then
			frame:RegisterEvent("PLAYER_REGEN_ENABLED")
		end
		return
	end

	if event == "PLAYER_REGEN_ENABLED" then
		frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
		OnAFKEvent(frame, "PLAYER_FLAGS_CHANGED")
		return
	end

	if not ns.db.afkCam.enable then return end

	if InCombatLockdown()
		or (_G.CinematicFrame and _G.CinematicFrame:IsShown())
		or (_G.MovieFrame and _G.MovieFrame:IsShown()) then
		return
	end

	if UnitCastingInfo("player") or UnitChannelInfo("player") then
		C_Timer.After(CAST_RECHECK_DELAY, function()
			OnAFKEvent(frame, "PLAYER_FLAGS_CHANGED")
		end)
		return
	end

	-- UnitIsAFK can return a secret boolean (e.g. in instances); we can't branch
	-- on a secret, so treat that as "not AFK" and bail out of the AFK camera.
	local isAFK = UnitIsAFK("player")
	if F.IsSecret(isAFK) then
		SetAFKMode(frame, false)
		return
	end

	if isAFK and not (C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle()) then
		SetAFKMode(frame, true)
	else
		SetAFKMode(frame, false)
	end
end

local function OnKeyDown(frame, key)
	if IGNORE_KEYS[key] then return end
	if PRINT_KEYS[key] then
		Screenshot()
		return
	end
	SetAFKMode(frame, false)
	C_Timer.After(KEY_RECHECK_DELAY, function()
		OnAFKEvent(frame, "PLAYER_FLAGS_CHANGED")
	end)
end

local function OnChatEvent(self, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14)
	local coloredName = _G.GetColoredName(event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14)
	local chatType = sub(event, 10)
	local chatInfo = _G.ChatTypeInfo[chatType]
	if not chatInfo then return end

	if event == "CHAT_MSG_BN_WHISPER" then
		local priest = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS.PRIEST
		if priest then
			coloredName = format("|c%s%s|r", priest.colorStr, arg2)
		else
			coloredName = arg2
		end
	end

	arg1 = _G.RemoveExtraSpaces(arg1)

	local chatGroup = _G.Chat_GetChatCategory(chatType)
	local chatTarget
	if chatGroup == "BN_CONVERSATION" then
		chatTarget = tostring(arg8)
	elseif chatGroup == "WHISPER" or chatGroup == "BN_WHISPER" then
		if sub(arg2, 1, 2) ~= "|K" then
			chatTarget = arg2:upper()
		else
			chatTarget = arg2
		end
	end

	local playerLink
	if chatType ~= "BN_WHISPER" and chatType ~= "BN_CONVERSATION" then
		playerLink = format("|Hplayer:%s:%s:%s%s|h", arg2, arg11, chatGroup, chatTarget and (":" .. chatTarget) or "")
	else
		playerLink = format("|HBNplayer:%s:%s:%s:%s%s|h", arg2, arg13, arg11, chatGroup, chatTarget and (":" .. chatTarget) or "")
	end

	local message = arg1
	if arg14 then
		message = _G.ChatFrame_GetMobileEmbeddedTexture(chatInfo.r, chatInfo.g, chatInfo.b) .. message
	end
	message = gsub(message, "%%", "%%%%")

	local pattern = _G["CHAT_" .. chatType .. "_GET"]
	if not pattern then return end

	local ok, body = pcall(format, pattern .. message, playerLink .. "[" .. coloredName .. "]" .. "|h")
	if not ok or not body then return end

	local accessID = _G.ChatHistory_GetAccessID(chatGroup, chatTarget)
	local typeID = _G.ChatHistory_GetAccessID(chatType, chatTarget, arg12 == "" and arg13 or arg12)
	self:AddMessage(body, chatInfo.r, chatInfo.g, chatInfo.b, chatInfo.id, false, accessID, typeID)
end

local function OnChatMouseWheel(self, delta)
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

-- ---------------------------------------------------------------------------
-- UI construction
-- ---------------------------------------------------------------------------
local function BuildFrame()
	if afkFrame then return afkFrame end

	-- Must NOT be parented to UIParent: SetAFKMode hides UIParent, which would
	-- hide every child frame and leave only the world-camera spin visible.
	local frame = CreateFrame("Frame", nil, nil, "BackdropTemplate")
	frame:SetFrameStrata("FULLSCREEN")
	frame:SetFrameLevel(100)
	frame:SetScale(UIParent:GetScale())
	frame:SetAllPoints(UIParent)
	frame:Hide()
	frame:EnableKeyboard(true)
	if frame.SetPropagateKeyboardInput then
		frame:SetPropagateKeyboardInput(false)
	end
	frame:SetScript("OnKeyDown", function(self, key)
		OnKeyDown(self, key)
	end)

	local chat = CreateFrame("ScrollingMessageFrame", nil, frame)
	chat:SetSize(500, 200)
	chat:SetFont(FONT, 14, "OUTLINE")
	chat:SetJustifyH("LEFT")
	chat:SetMaxLines(100)
	chat:EnableMouseWheel(true)
	chat:SetFading(false)
	chat:SetMovable(true)
	chat:EnableMouse(true)
	chat:RegisterForDrag("LeftButton")
	chat:SetScript("OnDragStart", chat.StartMoving)
	chat:SetScript("OnDragStop", chat.StopMovingOrSizing)
	chat:SetScript("OnMouseWheel", OnChatMouseWheel)
	chat:SetScript("OnEvent", OnChatEvent)
	frame.chat = chat

	local top = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	top:SetPoint("TOP", frame, "TOP", 0, 4)
	top:SetSize(UIParent:GetWidth() + 12, TOP_BAR.height)
	StylePanelBackdrop(top)
	frame.top = top

	chat:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 10, -6)

	local factionKey, factionSize, offsetX, offsetY, nameOffsetX, nameOffsetY = GetFactionLayout(C.Player.faction)

	local bottom = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	bottom:SetPoint("BOTTOM", frame, "BOTTOM", 0, -C.Mult)
	bottom:SetWidth(GetScreenWidth() + (C.Mult * 2))
	bottom:SetHeight(GetScreenHeight() * BOTTOM_BAR.heightScale - BOTTOM_BAR.heightTrim)
	bottom:SetClipsChildren(false)
	StylePanelBackdrop(bottom)
	frame.bottom = bottom

	local logo = bottom:CreateTexture(nil, "OVERLAY")
	logo:SetSize(256 / 1.4, 256 / 1.4)
	logo:SetPoint("CENTER", bottom, "CENTER", 0, 60)
	logo:SetTexture(LOGO_TEX)

	top.time = CreateFS(top, TOP_BAR.fontSize, "LEFT")
	top.time:SetPoint("RIGHT", top, "RIGHT", -TOP_BAR.padX, 0)
	top.time:SetTextColor(0.7, 0.7, 0.7)

	local wowLogo = CreateFrame("Frame", nil, frame)
	wowLogo:SetPoint("TOP", top, "TOP", 0, -6)
	wowLogo:SetFrameLevel(frame:GetFrameLevel() + 5)
	wowLogo:SetSize(300, 150)
	local wowTex = wowLogo:CreateTexture(nil, "OVERLAY")
	wowTex:SetAllPoints()
	local displayInfo = GetExpansionDisplayInfo(GetClampedCurrentExpansionLevel())
	if displayInfo and displayInfo.logo then
		wowTex:SetTexture(displayInfo.logo)
	end

	top.date = CreateFS(top, TOP_BAR.fontSize, "RIGHT")
	top.date:SetPoint("LEFT", top, "LEFT", TOP_BAR.padX, 0)
	top.date:SetTextColor(0.7, 0.7, 0.7)

	top.status = CreateBar(top)
	top.status:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, 8)
	top.status:SetPoint("BOTTOMLEFT", top, "BOTTOMLEFT", 0, 5)
	top.status:SetValue(LOGOUT_SECONDS)

	bottom.faction = bottom:CreateTexture(nil, "OVERLAY")
	bottom.faction:SetSize(factionSize, factionSize)
	bottom.faction:SetPoint("BOTTOMLEFT", bottom, "BOTTOMLEFT", offsetX, offsetY)
	bottom.faction:SetTexture("Interface/Timer/" .. factionKey .. "-Logo")

	bottom.name = CreateFS(bottom, BOTTOM_BAR.fontSize)
	bottom.name:SetFormattedText("%s-%s", C.Player.name, C.Player.realm)
	bottom.name:SetPoint("TOPLEFT", bottom.faction, "TOPRIGHT", nameOffsetX, nameOffsetY)
	bottom.name:SetTextColor(CLASS_COLOR[1], CLASS_COLOR[2], CLASS_COLOR[3])

	bottom.playerInfo = CreateFS(bottom, BOTTOM_BAR.fontSize)
	local classHex = F.RGBToHex(CLASS_COLOR[1], CLASS_COLOR[2], CLASS_COLOR[3])
	bottom.playerInfo:SetFormattedText(
		"|c%s%s %d|r |cff888888%s|r |c%s%s|r",
		C.BrandHex, _G.LEVEL or "Level", C.Player.level, C.Player.raceName or C.Player.race,
		classHex, C.Player.className or C.Player.class
	)
	bottom.playerInfo:SetPoint("TOPLEFT", bottom.name, "BOTTOMLEFT", 0, -BOTTOM_BAR.lineGap)

	bottom.guild = CreateFS(bottom, BOTTOM_BAR.fontSize)
	bottom.guild:SetText(_G.GUILD_NOT_IN_GUILD or "No Guild")
	bottom.guild:SetPoint("TOPLEFT", bottom.playerInfo, "BOTTOMLEFT", 0, -BOTTOM_BAR.lineGap)
	bottom.guild:SetTextColor(0.7, 0.7, 0.7)

	local stat = CreateFrame("Frame", nil, frame)
	stat:SetSize(418, 72)
	stat:SetPoint("CENTER", 0, 260)
	frame.stat = stat

	stat.bg = stat:CreateTexture(nil, "BACKGROUND")
	stat.bg:SetTexture([[Interface\LevelUp\LevelUpTex]])
	stat.bg:SetPoint("BOTTOM")
	stat.bg:SetSize(326, 103)
	stat.bg:SetTexCoord(0.00195313, 0.63867188, 0.03710938, 0.23828125)
	stat.bg:SetVertexColor(1, 1, 1, 0.7)

	stat.lineTop = stat:CreateTexture(nil, "BACKGROUND")
	stat.lineTop:SetDrawLayer("BACKGROUND", 2)
	stat.lineTop:SetTexture([[Interface\LevelUp\LevelUpTex]])
	stat.lineTop:SetPoint("TOP")
	stat.lineTop:SetSize(418, 7)
	stat.lineTop:SetTexCoord(0.00195313, 0.81835938, 0.01953125, 0.03320313)

	stat.lineBottom = stat:CreateTexture(nil, "BACKGROUND")
	stat.lineBottom:SetDrawLayer("BACKGROUND", 2)
	stat.lineBottom:SetTexture([[Interface\LevelUp\LevelUpTex]])
	stat.lineBottom:SetPoint("BOTTOM")
	stat.lineBottom:SetSize(418, 7)
	stat.lineBottom:SetTexCoord(0.00195313, 0.81835938, 0.01953125, 0.03320313)

	stat.info = CreateFS(stat, 18, "CENTER")
	stat.info:SetPoint("CENTER", stat, "CENTER", 0, -2)
	stat.info:SetTextColor(0.7, 0.7, 0.7)
	stat.info:SetText(L["AFK Random Stats"])

	local countdown = CreateFrame("Frame", nil, frame)
	countdown:SetSize(418, 36)
	countdown:SetPoint("TOP", stat.lineBottom, "BOTTOM")
	frame.countdown = countdown

	countdown.bg = countdown:CreateTexture(nil, "BACKGROUND")
	countdown.bg:SetTexture([[Interface\LevelUp\LevelUpTex]])
	countdown.bg:SetPoint("BOTTOM")
	countdown.bg:SetSize(326, 56)
	countdown.bg:SetTexCoord(0.00195313, 0.63867188, 0.03710938, 0.23828125)
	countdown.bg:SetVertexColor(1, 1, 1, 0.7)

	countdown.lineBottom = countdown:CreateTexture(nil, "BACKGROUND")
	countdown.lineBottom:SetDrawLayer("BACKGROUND", 2)
	countdown.lineBottom:SetTexture([[Interface\LevelUp\LevelUpTex]])
	countdown.lineBottom:SetPoint("BOTTOM")
	countdown.lineBottom:SetSize(418, 7)
	countdown.lineBottom:SetTexCoord(0.00195313, 0.81835938, 0.01953125, 0.03320313)

	countdown.text = CreateFS(countdown, 16, "CENTER")
	countdown.text:SetPoint("CENTER")
	countdown.text:SetTextColor(0.7, 0.7, 0.7)
	countdown.text:SetFormattedText("%s |cfff0ff00-30:00|r", L["AFK Logout Timer"])

	local wave = ANIMATIONS.wave

	bottom.modelHolder = CreateFrame("Frame", nil, bottom)
	bottom.modelHolder:SetSize(150, 150)
	bottom.modelHolder:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT", wave.offsetX, wave.offsetY)

	bottom.model = CreateFrame("PlayerModel", nil, bottom.modelHolder)
	bottom.model:SetPoint("CENTER")
	bottom.model:SetSize(GetScreenWidth() * 2, GetScreenHeight() * 2)
	bottom.model:SetCamDistanceScale(4.5)
	bottom.model:SetUnit("player")
	bottom.model.afkFrame = frame
	bottom.model:SetScript("OnUpdate", Model_OnUpdate)

	bottom.modelPetHolder = CreateFrame("Frame", nil, bottom)
	bottom.modelPetHolder:SetSize(150, 150)
	bottom.modelPetHolder:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT", PET_MODEL.offsetX, PET_MODEL.offsetY)

	bottom.modelPet = CreateFrame("PlayerModel", nil, bottom.modelPetHolder)
	bottom.modelPet:SetPoint("CENTER")
	bottom.modelPet:SetSize(GetScreenWidth() * 2, GetScreenHeight() * 2)
	bottom.modelPet:SetCamDistanceScale(PET_MODEL.camScale)
	bottom.modelPet:SetFacing(PET_MODEL.facing)

	frame:RegisterEvent("PLAYER_FLAGS_CHANGED")
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:RegisterEvent("LFG_PROPOSAL_SHOW")
	frame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
	frame:SetScript("OnEvent", OnAFKEvent)

	if IsMacClient() and _G.KEY_PRINTSCREEN_MAC then
		PRINT_KEYS[_G.KEY_PRINTSCREEN_MAC] = true
	end

	afkFrame = frame
	return frame
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function AFKCam:InstallHooks()
	if self.hooksInstalled then return end
	self.hooksInstalled = true
	BuildFrame()
	SetCVar("autoClearAFK", "1")
end

function AFKCam:OnEnable()
	if not ns.db.afkCam.enable then return end
	self:InstallHooks()
end

function AFKCam:OnSettingChanged(key, value)
	if key == "enable" then
		if value then
			self:InstallHooks()
		elseif afkFrame and afkFrame.isAFK then
			SetAFKMode(afkFrame, false)
		end
	end
end

function AFKCam:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable AFK Camera"], L["Immersive AFK overlay with camera spin, character model, clock and random stats."])
end
