--[[
	NexEnhance - AFK Camera
	-------------------------------------------------------------------------
	Immersive AFK overlay: rotating camera, character (and pet) model, clock,
	30-minute logout countdown, rotating account statistics and a whisper chat
	log. Exits on combat, LFG/battlefield popups, or any key press.

	Originally from ElvUI by the Tukui team:
	  https://github.com/tukui-org/ElvUI/blob/main/ElvUI/Game/Shared/Modules/Misc/AFK.lua
	Model animation cycle adapted from GW2 UI by Mortalknight:
	  https://github.com/Mortalknight/GW2_UI/blob/main/Games/Shared/Misc/afk.lua
	Layout reworked as a resolution-independent cinematic letterbox (gradient
	fades, edge-anchored elements, fixed model holders).
--]]

-- luacheck: globals CloseAllWindows MoveViewLeftStart MoveViewLeftStop RemoveExtraSpaces
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
local CreateColor = CreateColor
local GetTime = GetTime
local GetGameTime = GetGameTime
local GetCVarBool = GetCVarBool
local SetCVar = SetCVar
local GetCVar = GetCVar
local UIParent = UIParent
local UnitIsAFK = UnitIsAFK
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local InCombatLockdown = InCombatLockdown
local IsShiftKeyDown = IsShiftKeyDown
local IsInGuild = IsInGuild
local GetGuildInfo = GetGuildInfo
local GetAchievementInfo = GetAchievementInfo
local GetStatistic = GetStatistic
local GetBattlefieldStatus = GetBattlefieldStatus
local GetClampedCurrentExpansionLevel = GetClampedCurrentExpansionLevel
local GetExpansionDisplayInfo = GetExpansionDisplayInfo
local Screenshot = Screenshot
local IsMacClient = IsMacClient
local GetPlayerInfoByGUID = GetPlayerInfoByGUID
local C_Timer = C_Timer
local C_Calendar = C_Calendar
local C_DateAndTime = C_DateAndTime
local C_PetBattles = C_PetBattles

local FONT = C.Media.Fonts.normal
local BLANK_TEX = C.Media.Textures.blank
local CLASS_COLOR = C.ClassColor
local BRAND = C.Colors.brand
local LOGO_TEX = C.Media.Textures.logo256
local LOGOUT_SECONDS = 1800 -- 30 minutes; matches default AFK logout timing
local CAMERA_SPEED = 0.035
local CAST_RECHECK_DELAY = 30
local KEY_RECHECK_DELAY = 60

-- Cinematic letterbox layout (fixed sizes; anchored to screen edges).
local TOP_FADE = { height = 72, padX = 20, fontSize = 16 }
local BOTTOM_FADE = { height = 160, padX = 20, fontSize = 22, lineGap = 4 }
local NAME_CARD = { crestSize = 120, insetX = 24, insetY = 18 }
local WOW_LOGO = { width = 256, height = 128 }
-- Hero-shot character: large fixed model region rising from the bottom-right.
local MODEL_LAYOUT = {
	width = 600,
	height = 820,
	camScale = 0.9,
	insetX = 30,
	insetY = 0,
}

-- Player model animations; small nudges within the bottom-left holder.
local ANIMATIONS = {
	wave = { id = 67, facing = 6, wait = 5, offsetX = 0, offsetY = 0, duration = 2.3 },
	dance = { id = 69, facing = 6, wait = 30, offsetX = 0, offsetY = 0, duration = 300 },
	sleep = { id = 71, facing = 1, wait = 30, offsetX = 0, offsetY = 16, duration = 3000 },
}

-- Companion pet: a random collected battle pet idles beside the hero. Pets
-- auto-frame to the holder, so a fixed holder keeps every species a sensible
-- on-screen size. Anchored to the player's left/front, near their feet.
local PET_LAYOUT = {
	width = 300,
	height = 340,
	camScale = 1.0,
	insetX = 470, -- from the frame's right edge: sits to the hero's left/front
	insetY = 10,
	facing = 0.3, -- slightly angled toward the hero/camera
}

-- Fallback companions when the player owns no battle pets (creature IDs).
local PET_FALLBACK = {
	Horde = 113984, -- Legionnaire Murky
	Alliance = 113983, -- Knight-Captain Murky
}
local C_PetJournal = C_PetJournal

-- Class artifact background runes (mirrors the faction crest on the right).
local CLASS_RUNE = {
	DEMONHUNTER = "Artifacts-DemonHunter-BG-Rune",
	DEATHKNIGHT = "Artifacts-DeathKnightFrost-BG-Rune",
	DRUID = "Artifacts-Druid-BG-Rune",
	HUNTER = "Artifacts-Hunter-BG-Rune",
	MAGE = "Artifacts-MageArcane-BG-Rune",
	MONK = "Artifacts-Monk-BG-Rune",
	PALADIN = "Artifacts-Paladin-BG-Rune",
	PRIEST = "Artifacts-Priest-BG-Rune",
	ROGUE = "Artifacts-Rogue-BG-Rune",
	SHAMAN = "Artifacts-Shaman-BG-Rune",
	WARLOCK = "Artifacts-Warlock-BG-Rune",
	WARRIOR = "Artifacts-Warrior-BG-Rune",
}

local function CancelTimer(handle)
	if handle and handle.Cancel then
		handle:Cancel()
	end
end

local IGNORE_KEYS = {
	LALT = true,
	LSHIFT = true,
	RSHIFT = true,
}

local PRINT_KEYS = {
	PRINTSCREEN = true,
}

local STAT_IDS = {
	60,
	94,
	97,
	98,
	107,
	112,
	114,
	115,
	319,
	320,
	326,
	328,
	329,
	331,
	332,
	333,
	334,
	338,
	345,
	349,
	353,
	588,
	812,
	837,
	838,
	839,
	840,
	919,
	932,
	933,
	934,
	1042,
	1045,
	1047,
	1065,
	1066,
	1197,
	1198,
	1336,
	1339,
	1487,
	1491,
	1518,
	1776,
	2277,
	5692,
	5693,
	5694,
	5695,
	7399,
	8278,
}

ns:RegisterDefaults({
	afkCam = {
		enable = true,
	},
})

local AFKCam = ns:NewModule("AFKCam", "afkCam", { group = "camera", title = L["AFK Camera"], order = 20 })

local afkFrame
local manualPreview

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

local function CreateVerticalFade(parent, height, opaqueAtTop)
	local fade = parent:CreateTexture(nil, "BACKGROUND", nil, -2)
	fade:SetTexture(BLANK_TEX)
	fade:SetHeight(height)
	if opaqueAtTop then
		fade:SetPoint("TOPLEFT", parent, "TOPLEFT")
		fade:SetPoint("TOPRIGHT", parent, "TOPRIGHT")
		fade:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.88), CreateColor(0, 0, 0, 0))
	else
		fade:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT")
		fade:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT")
		fade:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.88))
	end
	return fade
end

local function CreateGoldAccent(parent, anchorTo, atTop)
	local accent = parent:CreateTexture(nil, "ARTWORK", nil, 1)
	accent:SetTexture(BLANK_TEX)
	accent:SetHeight(2)
	accent:SetGradient("HORIZONTAL", CreateColor(BRAND[1], BRAND[2], BRAND[3], 0), CreateColor(BRAND[1], BRAND[2], BRAND[3], 0.85))
	if atTop then
		accent:SetPoint("BOTTOMLEFT", anchorTo, "BOTTOMLEFT")
		accent:SetPoint("BOTTOMRIGHT", anchorTo, "BOTTOMRIGHT")
	else
		accent:SetPoint("TOPLEFT", anchorTo, "TOPLEFT")
		accent:SetPoint("TOPRIGHT", anchorTo, "TOPRIGHT")
	end
	return accent
end

local function GetFactionCrestKey(faction)
	if faction == "Horde" then
		return "Horde"
	elseif faction == "Neutral" then
		return "Panda"
	end
	return "Alliance"
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
	local model = frame.model
	local options, usedKey = GetAnimation(model, key)
	if not options then
		return
	end

	model.curAnimation = usedKey
	model.duration = options.duration
	model.idleDuration = options.wait
	model.startTime = GetTime()
	model.isIdle = nil
	model:SetFacing(options.facing)
	model:SetAnimation(options.id)

	local holder = frame.modelHolder
	if holder then
		holder:ClearAllPoints()
		holder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(MODEL_LAYOUT.insetX + options.offsetX), MODEL_LAYOUT.insetY + options.offsetY)
	end
end

local function Model_OnUpdate(self)
	if self.isIdle then
		return
	end

	if GetTime() - self.startTime < self.duration then
		return
	end

	self:SetAnimation(0)
	self.isIdle = true

	local frame = self.afkFrame
	if not frame or not frame.isAFK then
		return
	end

	CancelTimer(frame.animTimer)
	frame.animTimer = C_Timer.After(self.idleDuration, function()
		if frame.isAFK then
			ApplyAFKAnimation(frame)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Companion pet: a random collected battle pet idles beside the hero
-- ---------------------------------------------------------------------------
-- Returns a random owned petID from the journal, or nil if none are collected.
-- Uses reservoir sampling so the scan does not allocate a temporary pet list.
local function GetRandomOwnedPet()
	local petJournal = C_PetJournal
	if not (petJournal and petJournal.GetNumPets and petJournal.GetPetInfoByIndex) then
		return nil
	end

	local num = petJournal.GetNumPets()
	if not num or num == 0 then
		return nil
	end

	local selected, count
	for i = 1, num do
		local petID, _, isOwned = petJournal.GetPetInfoByIndex(i)
		if isOwned and petID then
			count = (count or 0) + 1
			if math_random(count) == 1 then
				selected = petID
			end
		end
	end

	return selected
end

local function Pet_Start(frame)
	local pet = frame.pet
	if not pet then
		return
	end

	pet:ClearModel()

	local applied = false
	local petJournal = C_PetJournal
	local petID = GetRandomOwnedPet()
	if petID and petJournal and petJournal.GetPetInfoByPetID then
		local _, _, _, _, _, displayID = petJournal.GetPetInfoByPetID(petID)
		if displayID and displayID > 0 then
			applied = pcall(pet.SetDisplayInfo, pet, displayID)
		end
	end

	if not applied then
		local fallback = (C.Player.faction == "Horde") and PET_FALLBACK.Horde or PET_FALLBACK.Alliance
		pcall(pet.SetCreature, pet, fallback)
	end

	pet:SetFacing(PET_LAYOUT.facing)
	pcall(pet.SetAnimation, pet, 0)
end

local function Pet_Stop(frame)
	local pet = frame.pet
	if not pet then
		return
	end
	pet:ClearModel()
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
		frame.time:SetText(FormatClock(hour, minute))
		local calendarTime = C_DateAndTime.GetCurrentCalendarTime()
		frame.date:SetText(FormatCalendarDate(calendarTime))
	end
end

local function UpdateLogout(frame)
	local elapsed = GetTime() - frame.startTime
	local remaining = LOGOUT_SECONDS - elapsed
	if remaining < 0 then
		remaining = 0
	end

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
		if frame.isAFK then
			return
		end

		MoveViewLeftStart(CAMERA_SPEED)
		frame:Show()
		CloseAllWindows()
		UIParent:Hide()

		if IsInGuild() then
			local guildName, guildRank = GetGuildInfo("player")
			frame.guild:SetFormattedText("%s - %s", guildName or "", guildRank or "")
		else
			frame.guild:SetText(_G.GUILD_NOT_IN_GUILD or "No Guild")
		end

		local model = frame.model
		model:SetUnit("player")
		ApplyAFKAnimation(frame, "wave")

		Pet_Start(frame)

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

	if not frame.isAFK then
		return
	end

	UIParent:Show()
	frame:Hide()
	MoveViewLeftStop()

	frame.startTime = nil
	CancelTimer(frame.clockTimer)
	CancelTimer(frame.statsTimer)
	CancelTimer(frame.logoffTimer)
	CancelTimer(frame.animTimer)
	if frame.model then
		frame.model.isIdle = true
	end

	Pet_Stop(frame)

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
		if manualPreview then
			manualPreview = false
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

	if manualPreview then
		return
	end

	if not ns.db.afkCam.enable then
		return
	end

	if InCombatLockdown() or (_G.CinematicFrame and _G.CinematicFrame:IsShown()) or (_G.MovieFrame and _G.MovieFrame:IsShown()) then
		return
	end

	if UnitCastingInfo("player") or UnitChannelInfo("player") then
		C_Timer.After(CAST_RECHECK_DELAY, function()
			OnAFKEvent(frame, "PLAYER_FLAGS_CHANGED")
		end)
		return
	end

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
	if IGNORE_KEYS[key] then
		return
	end
	if PRINT_KEYS[key] then
		Screenshot()
		return
	end
	if manualPreview then
		manualPreview = false
	end
	SetAFKMode(frame, false)
	C_Timer.After(KEY_RECHECK_DELAY, function()
		OnAFKEvent(frame, "PLAYER_FLAGS_CHANGED")
	end)
end

-- Patch 12.0 moved several chat helpers into the ChatFrameUtil namespace (the
-- old globals are now nil on Midnight, which is what crashed OnChatEvent). Mirror
-- ElvUI's AFK module: resolve each from ChatFrameUtil first, then fall back to the
-- pre-12.0 global, and guard usage so a missing helper degrades quietly.
local ChatFrameUtil = _G.ChatFrameUtil
local GetColoredName = (ChatFrameUtil and ChatFrameUtil.GetColoredName) or _G.GetColoredName
local GetChatCategory = (ChatFrameUtil and ChatFrameUtil.GetChatCategory) or _G.Chat_GetChatCategory
local GetMobileEmbeddedTexture = (ChatFrameUtil and ChatFrameUtil.GetMobileEmbeddedTexture) or _G.ChatFrame_GetMobileEmbeddedTexture
local GetAccessID = (ChatFrameUtil and ChatFrameUtil.GetAccessID) or _G.ChatHistory_GetAccessID
local RemoveExtraSpaces = _G.RemoveExtraSpaces

local function GetChatColoredName(event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14)
	if GetColoredName then
		local ok, coloredName = pcall(GetColoredName, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14)
		if ok and coloredName then
			return coloredName
		end
	end

	if not arg2 then
		return ""
	end

	-- Fallback: class-colour the sender from their GUID (secret-safe).
	local guid = arg12
	if guid and F.NotSecret(guid) and guid ~= "" and GetPlayerInfoByGUID then
		local _, classFileName = GetPlayerInfoByGUID(guid)
		local classColors = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
		local color = classFileName and classColors and classColors[classFileName]
		if color and color.colorStr then
			return format("|c%s%s|r", color.colorStr, arg2)
		end
	end

	return arg2
end

local function OnChatEvent(self, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14)
	if F.IsSecret(arg1) then
		return
	end

	local coloredName = GetChatColoredName(event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14)
	local chatType = sub(event, 10)
	local chatInfo = _G.ChatTypeInfo[chatType]
	if not chatInfo then
		return
	end

	if event == "CHAT_MSG_BN_WHISPER" then
		local priest = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS.PRIEST
		if priest then
			coloredName = format("|c%s%s|r", priest.colorStr, arg2)
		else
			coloredName = arg2
		end
	end

	if RemoveExtraSpaces then
		arg1 = RemoveExtraSpaces(arg1)
	end

	-- Without a chat-category resolver we can't build the player link safely.
	if not GetChatCategory then
		return
	end

	local chatGroup = GetChatCategory(chatType)
	local chatTarget
	if chatGroup == "BN_CONVERSATION" then
		chatTarget = tostring(arg8)
	elseif chatGroup == "WHISPER" or chatGroup == "BN_WHISPER" then
		-- arg2 (sender) can be a Secret string in instances; only upper-case it
		-- when it is safe to inspect (mirrors ElvUI's NotSecretValue guard).
		if F.NotSecret(arg2) and sub(arg2, 1, 2) ~= "|K" then
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
	if arg14 and GetMobileEmbeddedTexture then
		message = GetMobileEmbeddedTexture(chatInfo.r, chatInfo.g, chatInfo.b) .. message
	end
	message = gsub(message, "%%", "%%%%")

	local pattern = _G["CHAT_" .. chatType .. "_GET"]
	if not pattern then
		return
	end

	local ok, body = pcall(format, pattern .. message, playerLink .. "[" .. coloredName .. "]" .. "|h")
	if not ok or not body then
		return
	end

	local accessID, typeID
	if GetAccessID then
		accessID = GetAccessID(chatGroup, chatTarget)
		typeID = GetAccessID(chatType, chatTarget, arg12 == "" and arg13 or arg12)
	end
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
	if afkFrame then
		return afkFrame
	end

	local frame = CreateFrame("Frame", nil, nil)
	frame:SetFrameStrata("FULLSCREEN")
	frame:SetFrameLevel(100)
	frame:SetScale(UIParent:GetEffectiveScale())
	frame:SetAllPoints(UIParent)
	frame:Hide()
	frame:EnableKeyboard(true)
	if frame.SetPropagateKeyboardInput then
		frame:SetPropagateKeyboardInput(false)
	end
	frame:SetScript("OnKeyDown", function(self, key)
		OnKeyDown(self, key)
	end)

	local topFade = CreateVerticalFade(frame, TOP_FADE.height, true)
	frame.topFade = topFade
	CreateGoldAccent(frame, topFade, true)

	local bottomFade = CreateVerticalFade(frame, BOTTOM_FADE.height, false)
	frame.bottomFade = bottomFade
	CreateGoldAccent(frame, bottomFade, false)

	local chat = CreateFrame("ScrollingMessageFrame", nil, frame)
	chat:SetSize(420, 200)
	chat:SetPoint("RIGHT", frame, "RIGHT", -24, 40)
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

	frame.date = CreateFS(frame, TOP_FADE.fontSize, "LEFT")
	frame.date:SetPoint("TOPLEFT", frame, "TOPLEFT", TOP_FADE.padX, -TOP_FADE.padX - 4)
	frame.date:SetTextColor(0.7, 0.7, 0.7)

	frame.time = CreateFS(frame, TOP_FADE.fontSize, "RIGHT")
	frame.time:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -TOP_FADE.padX, -TOP_FADE.padX - 4)
	frame.time:SetTextColor(0.7, 0.7, 0.7)

	local wowLogo = CreateFrame("Frame", nil, frame)
	wowLogo:SetPoint("TOP", frame, "TOP", 0, 4)
	wowLogo:SetFrameLevel(frame:GetFrameLevel() + 5)
	wowLogo:SetSize(WOW_LOGO.width, WOW_LOGO.height)
	local wowTex = wowLogo:CreateTexture(nil, "OVERLAY")
	wowTex:SetAllPoints()
	wowTex:SetTexCoord(0, 1, 0, 1)
	local displayInfo = GetExpansionDisplayInfo(GetClampedCurrentExpansionLevel())
	if displayInfo and displayInfo.logo then
		wowTex:SetTexture(displayInfo.logo)
	end
	frame.wowLogo = wowLogo

	local crestSize = NAME_CARD.crestSize
	local nameCard = CreateFrame("Frame", nil, frame)
	nameCard:SetSize(420, crestSize)
	nameCard:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", NAME_CARD.insetX, NAME_CARD.insetY)
	frame.nameCard = nameCard

	frame.faction = nameCard:CreateTexture(nil, "OVERLAY")
	frame.faction:SetSize(crestSize, crestSize)
	frame.faction:SetPoint("LEFT", nameCard, "LEFT", 0, 0)
	frame.faction:SetTexture("Interface/Timer/" .. GetFactionCrestKey(C.Player.faction) .. "-Logo")

	-- Class artifact rune: mirrors the faction crest on the opposite (right) edge.
	local runeAtlas = CLASS_RUNE[C.Player.class]
	if runeAtlas then
		frame.classRune = frame:CreateTexture(nil, "ARTWORK")
		frame.classRune:SetSize(crestSize, crestSize)
		frame.classRune:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -NAME_CARD.insetX, NAME_CARD.insetY)
		frame.classRune:SetAtlas(runeAtlas, false)
	end

	-- Vertically center the three text rows against the crest.
	local blockHeight = (BOTTOM_FADE.fontSize * 3) + (BOTTOM_FADE.lineGap * 2)
	local topInset = -((crestSize - blockHeight) / 2)

	frame.name = CreateFS(nameCard, BOTTOM_FADE.fontSize, "LEFT")
	frame.name:SetFormattedText("%s-%s", C.Player.name, C.Player.realm)
	frame.name:SetPoint("TOPLEFT", frame.faction, "TOPRIGHT", 10, topInset)
	frame.name:SetTextColor(CLASS_COLOR[1], CLASS_COLOR[2], CLASS_COLOR[3])

	frame.playerInfo = CreateFS(nameCard, BOTTOM_FADE.fontSize, "LEFT")
	local classHex = F.RGBToHex(CLASS_COLOR[1], CLASS_COLOR[2], CLASS_COLOR[3])
	frame.playerInfo:SetFormattedText("|c%s%s %d|r |cff888888%s|r |c%s%s|r", C.BrandHex, _G.LEVEL or "Level", C.Player.level, C.Player.raceName or C.Player.race, classHex, C.Player.className or C.Player.class)
	frame.playerInfo:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -BOTTOM_FADE.lineGap)

	frame.guild = CreateFS(nameCard, BOTTOM_FADE.fontSize, "LEFT")
	frame.guild:SetText(_G.GUILD_NOT_IN_GUILD or "No Guild")
	frame.guild:SetPoint("TOPLEFT", frame.playerInfo, "BOTTOMLEFT", 0, -BOTTOM_FADE.lineGap)
	frame.guild:SetTextColor(0.7, 0.7, 0.7)

	local nexLogo = frame:CreateTexture(nil, "OVERLAY")
	nexLogo:SetSize(160, 160)
	nexLogo:SetPoint("CENTER", frame.bottomFade, "TOP", 0, 0)
	nexLogo:SetTexture(LOGO_TEX)
	frame.nexLogo = nexLogo

	local stat = CreateFrame("Frame", nil, frame)
	stat:SetSize(418, 72)
	stat:SetPoint("CENTER", frame, "CENTER", 0, 200)
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

	frame.modelHolder = CreateFrame("Frame", nil, frame)
	frame.modelHolder:SetSize(MODEL_LAYOUT.width, MODEL_LAYOUT.height)
	frame.modelHolder:SetFrameLevel(frame:GetFrameLevel() + 2)
	frame.modelHolder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(MODEL_LAYOUT.insetX + wave.offsetX), MODEL_LAYOUT.insetY + wave.offsetY)

	frame.model = CreateFrame("PlayerModel", nil, frame.modelHolder)
	frame.model:SetAllPoints(frame.modelHolder)
	frame.model:SetCamDistanceScale(MODEL_LAYOUT.camScale)
	frame.model:SetUnit("player")
	frame.model.afkFrame = frame
	frame.model:SetScript("OnUpdate", Model_OnUpdate)

	frame.petHolder = CreateFrame("Frame", nil, frame)
	frame.petHolder:SetSize(PET_LAYOUT.width, PET_LAYOUT.height)
	frame.petHolder:SetFrameLevel(frame:GetFrameLevel() + 3)
	frame.petHolder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PET_LAYOUT.insetX, PET_LAYOUT.insetY)

	frame.pet = CreateFrame("PlayerModel", nil, frame.petHolder)
	frame.pet:SetAllPoints(frame.petHolder)
	frame.pet:SetCamDistanceScale(PET_LAYOUT.camScale)
	frame.pet.afkFrame = frame

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
-- Stash the player's autoClearAFK choice before we force it on, so disabling the
-- module puts it back the way they had it.
local originalAutoClearAFK

function AFKCam:InstallHooks()
	if self.hooksInstalled then
		return
	end
	self.hooksInstalled = true
	BuildFrame()
	if originalAutoClearAFK == nil then
		originalAutoClearAFK = GetCVar("autoClearAFK") or "1"
	end
	SetCVar("autoClearAFK", "1")
end

function AFKCam:OnEnable()
	if not ns.db.afkCam.enable then
		return
	end
	self:InstallHooks()
end

function AFKCam:OnSettingChanged(key, value)
	if key == "enable" then
		if value then
			self:InstallHooks()
		else
			if afkFrame and afkFrame.isAFK then
				if manualPreview then
					manualPreview = false
				end
				SetAFKMode(afkFrame, false)
			end
			if originalAutoClearAFK ~= nil then
				SetCVar("autoClearAFK", originalAutoClearAFK)
			end
		end
	end
end

function AFKCam:ToggleTest()
	if InCombatLockdown() then
		F.Print(L["Cannot preview AFK mode during combat."])
		return
	end
	self:InstallHooks()
	manualPreview = not manualPreview
	if manualPreview then
		SetAFKMode(afkFrame, true)
		F.Print(L["AFK test mode on - press any key to exit."])
	else
		SetAFKMode(afkFrame, false)
		F.Print(L["AFK test mode off."])
	end
end

function AFKCam:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable AFK Camera"], L["Immersive AFK overlay with camera spin, character model, clock and random stats."])
end
