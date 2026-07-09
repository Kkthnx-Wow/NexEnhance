--[[
	NexEnhance - DataText: Clock
	-------------------------------------------------------------------------
	A minimap clock that follows Blizzard's own 12/24h and local/realm time
	CVars. Hovering it opens a tooltip with the full date, local & realm time,
	resets, saved raid / dungeon / world-boss lockouts, weekly quest checks,
	Delves, the weekly "Choose Your Path" meta, and Shift-held world-event details.
--]]

---@diagnostic disable: undefined-field, undefined-global
local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local _G = _G
local date, time = date, time
local format, find, match = string.format, string.find, string.match
local floor, fmod = math.floor, math.fmod
local ipairs, pairs, select, tonumber = ipairs, pairs, select, tonumber
local sort = table.sort
local wipe = wipe

-- Shared tooltip palette (single source of truth in Constants.lua): gold section
-- headers, light-blue labels/hints, white values.
local HDR = C.Colors.header
local LBL = C.Colors.label

local CreateFrame = CreateFrame
local GetCVar = GetCVar
local GetCVarBool = GetCVarBool
local GetGameTime = GetGameTime
local GetTime = GetTime
local GetQuestResetTime = GetQuestResetTime
local GetNumSavedInstances = GetNumSavedInstances
local GetNumSavedWorldBosses = GetNumSavedWorldBosses
local GetSavedInstanceInfo = GetSavedInstanceInfo
local GetSavedWorldBossInfo = GetSavedWorldBossInfo
local EJ_GetInstanceInfo = EJ_GetInstanceInfo
local GameTime_GetGameTime = GameTime_GetGameTime
local GameTime_GetLocalTime = GameTime_GetLocalTime
local InCombatLockdown = InCombatLockdown
local IsShiftKeyDown = IsShiftKeyDown
local RequestRaidInfo = RequestRaidInfo
local ToggleFrame = ToggleFrame
local UIParent = UIParent
local UnitLevel = UnitLevel
local GetMaxLevelForPlayerExpansion = GetMaxLevelForPlayerExpansion

local C_AddOns = C_AddOns
local C_AreaPoiInfo = C_AreaPoiInfo
local C_Calendar = C_Calendar
local C_DateAndTime = C_DateAndTime
local C_EncounterJournal = C_EncounterJournal
local C_Item = C_Item
local C_Map = C_Map
local C_QuestLog = C_QuestLog
local C_Spell = C_Spell
local C_TaskQuest = C_TaskQuest
local C_Texture = C_Texture
local C_UIWidgetManager = C_UIWidgetManager

ns:RegisterDefaults({
	timeText = {
		enable = true,
		classColor = false,
		-- Pre-Midnight world events (Legion invasions, BfA faction assaults,
		-- Dragonflight elemental storms / Grand Hunt / Community Feast) and the
		-- legacy daily-quest checklist. Off by default now that the live content
		-- is Midnight; flip on to keep tracking the old timers.
		showLegacy = false,
	},
})
ns:RegisterDefaults({
	invasionTimers = {
		legionStart = 0,
		bfaStart = 0,
		bfaZone = 0,
	},
}, "global")

local Clock = ns:NewModule("Clock", "timeText", { group = "datatext", title = L["Clock"], order = 30 })

local cfg
local clock
local eventHandles = {}
local eventsRegistered = false
local entered
local isTimeWalker
local walkerTexture
local tooltipElapsed = 0
local clockElapsed = 0
local CLOCK_TICK = 5
local TOOLTIP_REFRESH = 1
local INVASION_SCAN_INTERVAL = 30
local LOCKOUT_PREVIEW_MAX = 5
local raidLockoutScratch = {}
local dungeonLockoutScratch = {}

-- Forward-declared; defined with legacy invasion timer helpers below.
local ScanInvasionAnchors, GetInvasionTimers, CheckLegionInvasion, CheckBFAInvasion
local invasionScanAt = 0

local region = GetCVar and GetCVar("portal") or "US"

local LEGION_ZONE_TIME = { EU = 1762434000, US = 1762421400, CN = 1762450200 }
local BFA_ZONE_TIME = { CN = 1546743600, EU = 1546768800, US = 1546769340 }
local COMMUNITY_FEAST_TIME = { CN = 1679747400, TW = 1679747400, KR = 1679747400, EU = 1679749200, US = 1679751000 }

local invIndex = {
	{
		title = L["Legion Invasion"],
		duration = 52200,
		maps = { 630, 641, 650, 634 },
		timeTable = {},
		baseTime = LEGION_ZONE_TIME[region] or LEGION_ZONE_TIME.CN,
	},
	{
		title = L["Faction Assault"],
		duration = 68400,
		maps = { 862, 863, 864, 896, 942, 895 },
		timeTable = { 4, 1, 6, 2, 5, 3 },
		baseTime = BFA_ZONE_TIME[region] or BFA_ZONE_TIME.CN,
	},
}

-- LegionInvasionTimer / BFAInvasionTimer POI order and durations.
local LEGION_ACTIVE_DURATION = 21600 -- 6h assault
local LEGION_CYCLE_DURATION = 52200 -- 14.5h cycle
local BFA_ACTIVE_DURATION = 25200 -- 7h assault
local BFA_CYCLE_DURATION = 68400 -- 19h cycle

local LEGION_ZONES = {
	{ mapID = 650, poiID = 5177 }, -- Highmountain
	{ mapID = 634, poiID = 5178 }, -- Stormheim
	{ mapID = 641, poiID = 5210 }, -- Val'sharah
	{ mapID = 630, poiID = 5175 }, -- Azsuna
}

local BFA_ZONES = {
	{ mapID = 864, poiID = 5970 }, -- Vol'dun
	{ mapID = 896, poiID = 5964 }, -- Drustvar
	{ mapID = 862, poiID = 5973 }, -- Zuldazar
	{ mapID = 895, poiID = 5896 }, -- Tiragarde Sound
	{ mapID = 863, poiID = 5969 }, -- Nazmir
	{ mapID = 942, poiID = 5966 }, -- Stormsong Valley
}

local QUEST_LIST = {
	{ name = L["Feast of Winter Veil"], id = 6983 },
	{ name = L["Blingtron Daily Gift"], id = 34774 },
	{ name = L["500 Timewarped Badges"], id = 83285, texture = 6006158, twBadge = true },
	{ name = L["500 Timewarped Badges"], id = 40168, texture = 1129674, twBadge = true },
	{ name = L["500 Timewarped Badges"], id = 40173, texture = 1129686, twBadge = true },
	{ name = L["500 Timewarped Badges"], id = 40786, texture = 1304688, twBadge = true },
	{ name = L["500 Timewarped Badges"], id = 45563, texture = 1530590, twBadge = true },
	{ name = L["500 Timewarped Badges"], id = 55499, texture = 1129683, twBadge = true },
	{ name = L["500 Timewarped Badges"], id = 64710, texture = 1467047, twBadge = true },
	{ name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(388945), id = 70866 },
	{ name = L["Grand Hunt"], id = 70906, itemID = 200468 },
	{ name = L["Community Feast"], id = 70893, questName = true },
	{ name = L["The Big Dig"], id = 79226, questName = true },
	{ name = L["The Superbloom"], id = 78319, questName = true },
	-- TWW weekly/event quests. Title is left blank on purpose: questName = true
	-- resolves the live name via C_QuestLog, so the label always matches the
	-- player's locale and a stale ID simply omits the line instead of erroring.
	-- /run print(C_QuestLog.GetTitleForQuestID(76586), C_QuestLog.GetTitleForQuestID(82946), C_QuestLog.GetTitleForQuestID(83240))
	{ name = "", id = 76586, questName = true },
	{ name = "", id = 82946, questName = true },
	{ name = "", id = 83240, questName = true },
	{ name = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(15141), id = 83333 },
}

local HUNT_AREA_TO_MAPID = { [7342] = 2023, [7343] = 2022, [7344] = 2025, [7345] = 2024 }
local DELVE_LIST = {
	{ uiMapID = 2393, delveID = 8426 },
	{ uiMapID = 2424, delveID = 8428 },
	{ uiMapID = 2405, delveID = 8430 },
	{ uiMapID = 2405, delveID = 8432 },
	{ uiMapID = 2413, delveID = 8434 },
	{ uiMapID = 2413, delveID = 8436 },
	{ uiMapID = 2395, delveID = 8438 },
	{ uiMapID = 2393, delveID = 8440 },
	{ uiMapID = 2437, delveID = 8442 },
	{ uiMapID = 2437, delveID = 8444 },
}
local DELVE_SCAN_MAPS = {
	-- Current + older TWW delve zones. Dynamic POI scanning decides which ones
	-- are actually active on the player's client/content patch.
	2393,
	2424,
	2405,
	2413,
	2395,
	2437,
	2248,
	2215,
	2214,
	2255,
	2346,
	2371,
}
local MAX_BOUNTIFUL_DELVES = 4

local STORM_POI_IDS = {
	[2022] = { { 7249, 7250, 7251, 7252 }, { 7253, 7254, 7255, 7256 }, { 7257, 7258, 7259, 7260 } },
	[2023] = { { 7221, 7222, 7223, 7224 }, { 7225, 7226, 7227, 7228 } },
	[2024] = { { 7229, 7230, 7231, 7232 }, { 7233, 7234, 7235, 7236 }, { 7237, 7238, 7239, 7240 } },
	[2025] = { { 7245, 7246, 7247, 7248 }, { 7298, 7299, 7300, 7301 } },
}

-- Void Assaults (Midnight 12.0.x current content). One zone is active per weekly
-- rotation (Eversong Woods <-> Zul'Aman); the meta-quest gates the weekly Spark
-- of Radiance. Quest IDs are from 12.0.5 datamining: IsQuestFlaggedCompleted
-- returns false for an unknown ID and the on-quest check returns nil, so a stale
-- ID fails safe (the line is simply omitted) rather than erroring or lying.
-- Verify live with: /run print(C_QuestLog.IsQuestFlaggedCompleted(95842))
local VOID_ASSAULT_META = 95842
local VOID_ASSAULTS = {
	{ id = 94385, fallback = "Void Assaults: Eversong Woods" },
	{ id = 94386, fallback = "Void Assaults: Zul'Aman" },
}

-- Midnight's headline weekly: the "Choose Your Path" meta quest "Unity Against
-- the Void" from Lady Liadrin. It auto-completes when any one of its offered path
-- quests is finished, so its completed flag is the single source of truth for the
-- weekly. The path quests below let us show progress for whichever path the
-- player picked (e.g. "Midnight: Delves  1/3"). Prey / World Boss IDs aren't
-- needed for completion (the meta flag covers them); they only miss the optional
-- progress line, which fails safe. Verify with:
--   /run print(C_QuestLog.IsQuestFlaggedCompleted(93744))
local WEEKLY_META_QUEST = 93744 -- Unity Against the Void
local WEEKLY_PATH_QUESTS = {
	93909, -- Midnight: Delves
	93766, -- Midnight: World Quests
	93891, -- Midnight: Legends of the Haranir
}

local WORLD_BOSS_NAMES = {
	"Lu'ashal",
	"Lu’ashal",
	"Thorm'belan",
	"Thorm'Belan",
	"Thorm’belan",
	"Predaxas",
	"Cragpine",
}

-- Curated current-content POIs for events whose tooltip/timer is split across
-- sibling event POIs. The dynamic scanner below still finds new events, while
-- these IDs let us query alternate timers when Blizzard's visible event pin
-- only reports "active" through GetAreaPOISecondsLeft.
local CURRENT_WORLD_EVENT_POIS = {
	{ name = "Stormarion Assault", mapID = 2405, ids = { 8419, 8421, 8422 } },
}

local atlasCache = {}
local itemCache = {}

-- ---------------------------------------------------------------------------
-- Time formatting (follows Blizzard's clock CVars)
-- ---------------------------------------------------------------------------
local function ClassPrefix()
	return "|c" .. F.RGBToHex(F.UnitColor("player"))
end

local function FormatClock(hour, minute, pending)
	if GetCVarBool("timeMgrUseMilitaryTime") then
		-- 24h has no AM/PM unit, so only a pending calendar invite recolours it.
		if pending then
			return format("|cffff0000" .. _G.TIMEMANAGER_TICKER_24HOUR .. "|r", hour, minute)
		end
		return format(_G.TIMEMANAGER_TICKER_24HOUR, hour, minute)
	end

	local suffix = (hour < 12) and _G.TIMEMANAGER_AM or _G.TIMEMANAGER_PM
	local h = (hour % 12 == 0) and 12 or (hour % 12)

	-- A pending calendar invite flashes the whole readout red; otherwise the
	-- class colour (when enabled) tints only the AM/PM unit, never the digits.
	if pending then
		return format("|cffff0000" .. _G.TIMEMANAGER_TICKER_12HOUR .. " %s|r", h, minute, suffix)
	end
	if cfg and cfg.classColor then
		suffix = ClassPrefix() .. suffix .. "|r"
	end
	return format(_G.TIMEMANAGER_TICKER_12HOUR .. " %s", h, minute, suffix)
end

-- Compact, unit-suffixed countdown used for every tooltip timer (resets, saved
-- lockouts, delves, world events) so they all read the same: "6d 10h", "10h 30m",
-- "32m", "45s". Two largest units only, mirroring the examples requested.
local function FormatTimer(seconds)
	seconds = floor(seconds or 0)
	if seconds >= 86400 then
		return format("%dd %dh", floor(seconds / 86400), floor((seconds % 86400) / 3600))
	elseif seconds >= 3600 then
		return format("%dh %dm", floor(seconds / 3600), floor((seconds % 3600) / 60))
	elseif seconds >= 60 then
		return format("%dm", floor(seconds / 60))
	end
	return format("%ds", seconds)
end

local function UpdateClock(self)
	local hour, minute
	if GetCVarBool("timeMgrUseLocalTime") then
		hour, minute = tonumber(date("%H")), tonumber(date("%M"))
	else
		hour, minute = GetGameTime()
	end

	local pending = (C_Calendar and C_Calendar.GetNumPendingInvites and C_Calendar.GetNumPendingInvites() or 0) > 0
	F.SetPlainText(self.text, FormatClock(hour, minute, pending))
	self:SetWidth(self.text:GetStringWidth() + 8)
end

-- ---------------------------------------------------------------------------
-- Cached lookups
-- ---------------------------------------------------------------------------
local function TextureStringByAtlas(atlas, width, height)
	if not atlas or not C_Texture or not C_Texture.GetAtlasInfo then
		return ""
	end
	if not C_Texture.GetAtlasInfo(atlas) then
		return ""
	end
	return format("|A:%s:%d:%d|a", atlas, height or 16, width or 16)
end

local function GetElementalType(element)
	if not atlasCache[element] then
		atlasCache[element] = TextureStringByAtlas("ElementalStorm-Lesser-" .. element, 16, 16)
	end
	return atlasCache[element]
end

local function GetItemLink(itemID)
	if not C_Item or not C_Item.GetItemInfo then
		return nil
	end
	if itemCache[itemID] then
		return itemCache[itemID]
	end
	local link = select(2, C_Item.GetItemInfo(itemID))
	if link then
		itemCache[itemID] = link
		return link
	end
	if ns.RequestItemData then
		ns:RequestItemData(itemID, function()
			local loaded = select(2, C_Item.GetItemInfo(itemID))
			if loaded then
				itemCache[itemID] = loaded
			end
		end)
	end
	return itemCache[itemID]
end

-- ---------------------------------------------------------------------------
-- Calendar / quest data
-- ---------------------------------------------------------------------------
function Clock:CheckTimeWalker()
	isTimeWalker = false
	walkerTexture = nil

	if cfg and cfg.showLegacy then
		ScanInvasionAnchors(true)
	end

	if not C_Calendar or not C_DateAndTime or not find then
		return
	end
	if not C_Calendar.GetNumDayEvents or not C_Calendar.GetDayEvent or not C_Calendar.OpenCalendar or not C_Calendar.SetAbsMonth then
		return
	end

	local calDate = C_DateAndTime.GetCurrentCalendarTime()
	if not calDate then
		return
	end

	C_Calendar.SetAbsMonth(calDate.month, calDate.year)
	C_Calendar.OpenCalendar()

	local numEvents = C_Calendar.GetNumDayEvents(0, calDate.monthDay) or 0
	for i = 1, numEvents do
		local info = C_Calendar.GetDayEvent(0, calDate.monthDay, i)
		if info and info.title and find(info.title, _G.PLAYER_DIFFICULTY_TIMEWALKER or "") and info.sequenceType ~= "END" then
			isTimeWalker = true
			walkerTexture = info.iconTexture
			return
		end
	end
end

local function AddTooltipTitle(text)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(text .. ":", HDR[1], HDR[2], HDR[3])
end

local function AddResets()
	GameTooltip:AddLine(" ")
	local daily = F.GetSecondsUntilDailyReset()
	if daily then
		GameTooltip:AddDoubleLine(L["Daily Reset"], FormatTimer(daily), LBL[1], LBL[2], LBL[3], 1, 1, 1)
	end

	local weekly = F.GetSecondsUntilWeeklyReset()
	if weekly then
		GameTooltip:AddDoubleLine(L["Weekly Reset"], FormatTimer(weekly), LBL[1], LBL[2], LBL[3], 1, 1, 1)
	end
end

-- Walk from the player's current map up to its continent, then collect the
-- continent + all of its zone maps. Current-content scans stay patch-proof this
-- way: no static map-ID table is needed when the player is in the right region.
local function CollectContinentZones(result)
	if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetMapInfo then
		return
	end

	local mapID = C_Map.GetBestMapForUnit("player")
	local guard = 0
	while mapID and guard < 20 do
		guard = guard + 1
		local info = C_Map.GetMapInfo(mapID)
		if not info then
			return
		end
		if info.mapType == Enum.UIMapType.Continent then
			break
		end
		mapID = info.parentMapID
	end
	if not mapID then
		return
	end

	result[#result + 1] = mapID
	if C_Map.GetMapChildrenInfo then
		local children = C_Map.GetMapChildrenInfo(mapID, Enum.UIMapType.Zone, true)
		if children then
			for _, child in ipairs(children) do
				if child.mapID then
					result[#result + 1] = child.mapID
				end
			end
		end
	end
end

local worldBossScanBuffer = {}

local function IsMidnightWorldBossName(name)
	if not name then
		return false
	end
	for _, bossName in ipairs(WORLD_BOSS_NAMES) do
		if find(name, bossName, 1, true) then
			return true
		end
	end
	return false
end

local function GetSavedWorldBossReset(name)
	local count = GetNumSavedWorldBosses and GetNumSavedWorldBosses() or 0
	for i = 1, count do
		local savedName, id, reset = GetSavedWorldBossInfo(i)
		if savedName == name and id ~= 11 and id ~= 12 and id ~= 13 then
			return reset
		end
	end
end

local function FindActiveWorldBoss()
	if not (C_TaskQuest and C_TaskQuest.GetQuestsOnMap) then
		return
	end

	local maps = worldBossScanBuffer
	wipe(maps)
	CollectContinentZones(maps)

	for _, mapID in ipairs(maps) do
		local tasks = C_TaskQuest.GetQuestsOnMap(mapID)
		if tasks then
			for _, task in ipairs(tasks) do
				local questID = task and (task.questID or task.questId)
				local name = questID and _G.QuestUtils_GetQuestName and _G.QuestUtils_GetQuestName(questID)
				if IsMidnightWorldBossName(name) then
					return name, questID
				end
			end
		end
	end
end

local function AddWorldBosses()
	local activeName = FindActiveWorldBoss()
	local activeReset = activeName and GetSavedWorldBossReset(activeName)
	local header

	if activeName then
		AddTooltipTitle(_G.RAID_INFO_WORLD_BOSS)
		header = true
		if activeReset then
			GameTooltip:AddDoubleLine(activeName, _G.QUEST_COMPLETE, 1, 1, 1, 0, 1, 0)
		else
			GameTooltip:AddDoubleLine(activeName, L["Available"], 1, 1, 1, 1, 0.82, 0)
		end
	end

	local count = GetNumSavedWorldBosses and GetNumSavedWorldBosses() or 0
	for i = 1, count do
		local name, id, reset = GetSavedWorldBossInfo(i)
		if name and id ~= 11 and id ~= 12 and id ~= 13 and name ~= activeName then
			if not header then
				AddTooltipTitle(_G.RAID_INFO_WORLD_BOSS)
				header = true
			end
			GameTooltip:AddDoubleLine(name, FormatTimer(reset), 1, 1, 1, 0.75, 0.75, 0.75)
		end
	end
end

-- Locale-independent difficulty abbreviations keyed by difficultyID, so long
-- names like "Looking For Raid" / "40 Player" stay short in the tooltip.
local DIFF_ABBR = {
	[1] = "N",
	[2] = "H",
	[3] = "10N",
	[4] = "25N",
	[5] = "10H",
	[6] = "25H",
	[7] = "LFR",
	[9] = "40",
	[14] = "N",
	[15] = "H",
	[16] = "M",
	[17] = "LFR",
	[23] = "M",
	[24] = "TW",
	[33] = "TW",
}

-- Tier colours (gear-quality language: green/blue/purple) so the abbreviation
-- stands out at a glance. Keyed by difficultyID to stay locale-independent.
local DIFF_COLOR = {
	[1] = "1eff00",
	[3] = "1eff00",
	[4] = "1eff00",
	[14] = "1eff00", -- Normal: green
	[2] = "0070dd",
	[5] = "0070dd",
	[6] = "0070dd",
	[15] = "0070dd", -- Heroic: blue
	[16] = "a335ee",
	[23] = "a335ee", -- Mythic: purple
	[7] = "9d9d9d",
	[17] = "9d9d9d", -- LFR: grey
	[9] = "ff8000", -- 40 Player: orange
	[24] = "00ccff",
	[33] = "00ccff", -- Timewalking: light blue
}

local function AbbrDiff(diff, diffName)
	local abbr = DIFF_ABBR[diff] or diffName or ""
	local color = DIFF_COLOR[diff]
	if color and abbr ~= "" then
		return "|cff" .. color .. abbr .. "|r"
	end
	return abbr
end

-- Smooth red (none) -> orange/yellow (partial) -> green (cleared) by ratio.
local function ProgressColor(progress, total)
	if not total or total <= 0 then
		return 1, 0, 0
	end
	local ratio = (progress or 0) / total
	if ratio <= 0 then
		return 1, 0, 0
	end
	if ratio >= 1 then
		return 0, 1, 0
	end
	if ratio <= 0.5 then
		return 1, ratio * 2, 0 -- red -> yellow
	end
	return 2 - ratio * 2, 1, 0 -- yellow -> green
end

-- Coloured "(p/n)" plus a green checkmark atlas once every boss is down.
local function ProgressString(progress, total)
	progress, total = progress or 0, total or 0
	local hex = F.RGBToHex(ProgressColor(progress, total))
	local str = format("|c%s(%d/%d)|r", hex, progress, total)
	if total > 0 and progress >= total then
		local check = TextureStringByAtlas("achievementcompare-GreenCheckmark", 9, 11)
		if check ~= "" then
			str = str .. " " .. check
		end
	end
	return str
end

-- GetSavedInstanceInfo: since 10.0.5 return #2 is lockoutId; map InstanceID is #14.
-- Classify with EJ when api isRaid lies; render raids and dungeons in two passes
-- because API index order is not grouped by instance type.
local function ReadSavedInstance(index)
	local name, _, reset, diff, locked, extended, _, isRaid, maxPlayers, diffName, numEncounters, progress, _, gameInstanceID =
		GetSavedInstanceInfo(index)
	return {
		name = name,
		reset = reset,
		diff = diff,
		locked = locked,
		extended = extended,
		isRaid = isRaid,
		maxPlayers = maxPlayers,
		diffName = diffName,
		numEncounters = numEncounters,
		progress = progress,
		gameInstanceID = gameInstanceID,
	}
end

local function LookupJournalRaid(gameInstanceID)
	if not (gameInstanceID and gameInstanceID > 0 and C_EncounterJournal and C_EncounterJournal.GetInstanceForGameMap and EJ_GetInstanceInfo) then
		return nil
	end
	local journalID = C_EncounterJournal.GetInstanceForGameMap(gameInstanceID)
	if not journalID then
		return nil
	end
	local ejName, _, _, _, _, _, _, _, _, _, _, ejIsRaid = EJ_GetInstanceInfo(journalID)
	if not ejName then
		return nil
	end
	return ejIsRaid
end

local function IsSavedInstanceRaid(info)
	if info.isRaid then
		return true
	end

	local ejIsRaid = LookupJournalRaid(info.gameInstanceID)
	if ejIsRaid == true then
		return true
	end
	if ejIsRaid == false then
		if info.maxPlayers and info.maxPlayers > 5 then
			return true
		end
		if info.numEncounters and info.numEncounters > 8 then
			return true
		end
		return false
	end

	if info.maxPlayers and info.maxPlayers > 5 then
		return true
	end
	if info.numEncounters and info.numEncounters > 8 then
		return true
	end
	return false
end

local function AddLockoutTooltipLine(info)
	local r, g, b = info.extended and 0.3 or 0.75, info.extended and 1 or 0.75, info.extended and 0.3 or 0.75
	GameTooltip:AddDoubleLine(
		format("%s - %s %s", info.name, AbbrDiff(info.diff, info.diffName), ProgressString(info.progress, info.numEncounters)),
		FormatTimer(info.reset),
		1, 1, 1, r, g, b
	)
end

local function AddLockouts()
	local count = GetNumSavedInstances and GetNumSavedInstances() or 0
	if count == 0 then
		return false
	end

	wipe(raidLockoutScratch)
	wipe(dungeonLockoutScratch)

	for i = 1, count do
		local info = ReadSavedInstance(i)
		if (info.locked or info.extended) and info.name then
			if IsSavedInstanceRaid(info) then
				raidLockoutScratch[#raidLockoutScratch + 1] = info
			elseif info.diff == 2 or info.diff == 23 then
				dungeonLockoutScratch[#dungeonLockoutScratch + 1] = info
			end
		end
	end

	local showAll = IsShiftKeyDown()
	local truncated = false

	if #raidLockoutScratch > 0 then
		AddTooltipTitle(L["Saved Raid(s)"])
		local limit = showAll and #raidLockoutScratch or math.min(#raidLockoutScratch, LOCKOUT_PREVIEW_MAX)
		for j = 1, limit do
			AddLockoutTooltipLine(raidLockoutScratch[j])
		end
		if not showAll and #raidLockoutScratch > LOCKOUT_PREVIEW_MAX then
			truncated = true
			GameTooltip:AddLine(format(L["and %d more"], #raidLockoutScratch - LOCKOUT_PREVIEW_MAX), LBL[1], LBL[2], LBL[3])
		end
	end
	if #dungeonLockoutScratch > 0 then
		AddTooltipTitle(L["Saved Dungeon(s)"])
		local limit = showAll and #dungeonLockoutScratch or math.min(#dungeonLockoutScratch, LOCKOUT_PREVIEW_MAX)
		for j = 1, limit do
			AddLockoutTooltipLine(dungeonLockoutScratch[j])
		end
		if not showAll and #dungeonLockoutScratch > LOCKOUT_PREVIEW_MAX then
			truncated = true
			GameTooltip:AddLine(format(L["and %d more"], #dungeonLockoutScratch - LOCKOUT_PREVIEW_MAX), LBL[1], LBL[2], LBL[3])
		end
	end

	return truncated
end

-- Localized quest title (falls back to the raw quest API or nil). Returns nil for
-- the empty string the quest APIs hand back before a quest name is cached.
local function QuestName(questID)
	local name = _G.QuestUtils_GetQuestName and _G.QuestUtils_GetQuestName(questID)
	if (not name or name == "") and C_QuestLog.GetTitleForQuestID then
		name = C_QuestLog.GetTitleForQuestID(questID)
	end
	if name and name ~= "" then
		return name
	end
end

-- Returns the in-log "Choose Your Path" path quest's name and objective progress
-- ("1/3"), or nil when no tracked path is in the quest log. Objective counts are
-- guarded against 12.0 secret values (they can be secret inside instances), in
-- which case the progress string is omitted but the path name still shows.
local function GetActivePathProgress()
	if not C_QuestLog.GetLogIndexForQuestID then
		return
	end
	for _, questID in ipairs(WEEKLY_PATH_QUESTS) do
		if C_QuestLog.GetLogIndexForQuestID(questID) then
			local progress
			local objectives = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(questID)
			local o = objectives and objectives[1]
			if o and o.numFulfilled and o.numRequired and F.NotSecret(o.numFulfilled) and F.NotSecret(o.numRequired) and o.numRequired > 0 then
				progress = format("%d/%d", o.numFulfilled, o.numRequired)
			end
			return QuestName(questID), progress
		end
	end
end

-- The weekly "Choose Your Path" meta (Unity Against the Void, Lady Liadrin).
-- This is the headline Midnight weekly, so it always shows at max level as a
-- reminder (hidden on leveling alts). Green = done, red = not yet; an indented
-- line shows the picked path's progress while it's in the quest log.
local function AddWeeklyMeta()
	if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then
		return
	end
	-- Max-level content only - don't nag leveling alts with a weekly they can't do.
	if GetMaxLevelForPlayerExpansion and UnitLevel("player") < GetMaxLevelForPlayerExpansion() then
		return
	end

	local metaDone = C_QuestLog.IsQuestFlaggedCompleted(WEEKLY_META_QUEST)
	local pathName, pathProgress = GetActivePathProgress()

	AddTooltipTitle(L["Weekly Quest"])
	GameTooltip:AddDoubleLine(QuestName(WEEKLY_META_QUEST) or L["Choose Your Path"], metaDone and _G.QUEST_COMPLETE or _G.INCOMPLETE, 1, 1, 1, metaDone and 0 or 1, metaDone and 1 or 0, 0)
	if not metaDone and pathName then
		GameTooltip:AddDoubleLine("  " .. pathName, pathProgress or _G.INCOMPLETE, LBL[1], LBL[2], LBL[3], 1, 1, 1)
	end
end

local function AddQuestCompletions()
	if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then
		return
	end

	-- The QUEST_LIST entries are all pre-Midnight dailies/weeklies (Winter Veil,
	-- Blingtron, Timewarped, Grand Hunt, Community Feast, Big Dig, Superbloom...),
	-- so they only show when legacy tracking is enabled. Midnight's current
	-- weekly is handled by AddWeeklyMeta below.
	local header
	if cfg and cfg.showLegacy then
		for _, q in ipairs(QUEST_LIST) do
			if q.id and C_QuestLog.IsQuestFlaggedCompleted(q.id) then
				if (not q.twBadge) or (isTimeWalker and (walkerTexture == q.texture or walkerTexture == (q.texture and q.texture - 1))) then
					local name = q.itemID and GetItemLink(q.itemID) or (q.questName and _G.QuestUtils_GetQuestName and _G.QuestUtils_GetQuestName(q.id)) or q.name
					if name and name ~= "" then
						if not header then
							AddTooltipTitle(_G.QUESTS_LABEL)
							header = true
						end
						GameTooltip:AddDoubleLine(name, _G.QUEST_COMPLETE, 1, 1, 1, 1, 0, 0)
					end
				end
			end
		end
	end
end

-- A bountiful delve is the special weekly delve flagged with a "bountiful" atlas
-- (e.g. "delves-bountiful"). Plain delve entrances are everywhere and would
-- flood the tooltip, so we list only bountiful ones.
local function IsBountifulDelve(info)
	return info and info.atlasName and find(info.atlasName, "[Bb]ountiful") and true or false
end

local function AddDelveLine(uiMapID, info, header, seen)
	-- Dedup by delve NAME, not POI id: the same bountiful delve is returned by
	-- both the continent map and its child zone map with *different* areaPoiIDs,
	-- so keying on the id would list each daily delve twice. The name is stable
	-- across those duplicate listings, so it collapses them to one entry.
	local id = info and (info.name or info.areaPoiID or info.poiID or info.delveID)
	if not info or (id and seen[id]) then
		return header, false
	end
	if id then
		seen[id] = true
	end

	if not header then
		AddTooltipTitle(info.description or L["Delves"])
		header = true
	end

	local mapInfo = C_Map.GetMapInfo(uiMapID)
	local dailyLeft = F.GetSecondsUntilDailyReset()
	GameTooltip:AddDoubleLine(
		format("%s - %s", mapInfo and mapInfo.name or L["Unknown"], info.name or L["Unknown"]),
		dailyLeft and FormatTimer(dailyLeft) or "—",
		1, 1, 1, 1, 1, 1
	)
	return header, true
end

-- Reused scratch buffer (avoid per-hover table churn).
local delveScanBuffer = {}

-- Scan the given maps for bountiful delves using Blizzard's delve POI list.
local function ScanDelveMaps(maps, header, seen, shown)
	if not C_AreaPoiInfo.GetDelvesForMap then
		return header, false, shown
	end

	local found
	for _, uiMapID in ipairs(maps) do
		if shown >= MAX_BOUNTIFUL_DELVES then
			break
		end
		local poiIDs = C_AreaPoiInfo.GetDelvesForMap(uiMapID)
		if poiIDs then
			for _, poiID in ipairs(poiIDs) do
				if shown >= MAX_BOUNTIFUL_DELVES then
					break
				end
				local info = C_AreaPoiInfo.GetAreaPOIInfo(uiMapID, poiID)
				if IsBountifulDelve(info) then
					local added
					header, added = AddDelveLine(uiMapID, info, header, seen)
					found = found or added
					if added then
						shown = shown + 1
					end
				end
			end
		end
	end
	return header, found, shown
end

local function AddDelves()
	if not C_AreaPoiInfo or not C_AreaPoiInfo.GetAreaPOIInfo then
		return
	end
	if not C_Map or not C_Map.GetMapInfo then
		return
	end

	-- `header` is a sentinel: nil/false means "section title not emitted yet".
	-- AddDelveLine flips it to true on the first line so the title prints once
	-- across all three fallback passes. Seeded false (not nil) to keep linters quiet.
	local header = false
	local found
	local seen = {}
	local shown = 0

	-- 1) Dynamic scan of the player's current continent (current content).
	local maps = delveScanBuffer
	wipe(maps)
	CollectContinentZones(maps)
	header, found, shown = ScanDelveMaps(maps, header, seen, shown)
	if found then
		return
	end

	-- 2) Static known delve maps via the same delve API (for when the player is
	--    off-continent but we still want this week's bountiful delves).
	header, found, shown = ScanDelveMaps(DELVE_SCAN_MAPS, header, seen, shown)
	if found then
		return
	end

	-- 3) Legacy fallback: hardcoded POI IDs for older clients.
	for _, delve in ipairs(DELVE_LIST) do
		if shown >= MAX_BOUNTIFUL_DELVES then
			break
		end
		local info = C_AreaPoiInfo.GetAreaPOIInfo(delve.uiMapID, delve.delveID or 0)
		if info then
			local added
			header, added = AddDelveLine(delve.uiMapID, info, header, seen)
			if added then
				shown = shown + 1
			end
		end
	end
end

-- Current-content weekly: Void Assaults. Only the active zone's weekly (and the
-- meta) is shown, and only once the player has it in their log or has completed
-- it, so the tooltip never lists an irrelevant rotation. Green = done, red = not.
local function VoidQuestName(id, fallback)
	local name = _G.QuestUtils_GetQuestName and _G.QuestUtils_GetQuestName(id)
	if name and name ~= "" then
		return name
	end
	return fallback
end

local function AddVoidAssaults()
	if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then
		return
	end
	local getLogIndex = C_QuestLog.GetLogIndexForQuestID

	local header
	for _, q in ipairs(VOID_ASSAULTS) do
		local done = C_QuestLog.IsQuestFlaggedCompleted(q.id)
		if done or (getLogIndex and getLogIndex(q.id)) then
			if not header then
				AddTooltipTitle(L["Void Assaults"])
				header = true
			end
			GameTooltip:AddDoubleLine(VoidQuestName(q.id, q.fallback), done and _G.QUEST_COMPLETE or _G.INCOMPLETE, 1, 1, 1, done and 0 or 1, done and 1 or 0, 0)
		end
	end

	local metaDone = C_QuestLog.IsQuestFlaggedCompleted(VOID_ASSAULT_META)
	if metaDone or (getLogIndex and getLogIndex(VOID_ASSAULT_META)) then
		if not header then
			AddTooltipTitle(L["Void Assaults"])
		end
		GameTooltip:AddDoubleLine(VoidQuestName(VOID_ASSAULT_META, L["Weekly Meta"]), metaDone and _G.QUEST_COMPLETE or _G.INCOMPLETE, LBL[1], LBL[2], LBL[3], metaDone and 0 or 1, metaDone and 1 or 0, 0)
	end
end

-- Current-content world events (Stormarion Assault, Abundance Harvest, Void
-- Incursions...). Blizzard exposes these through GetEventsForMap; we scan the
-- player's continent and merge duplicates by name (the same event can appear on
-- multiple zone maps with different POI IDs). World bosses are omitted here
-- because AddWorldBosses already tracks them. Ambient always-on POIs such as
-- Prey or Legends of the Haranir are filtered out unless they carry a timer.
local worldEventScanBuffer = {}
local worldEventByName = {}

local function ParseWidgetTextSeconds(text)
	if not text or text == "" or F.IsSecret(text) then
		return
	end
	-- WoW pluralization tokens like "|4Min:Min;" can sit between the number and
	-- its unit word (e.g. "Time Left: 2 |4Min:Min; 38 |4Sec:Sec;"). Match a number
	-- followed by optional space / pipe / digit noise, then the unit, so this
	-- handles both the escaped form and plain "5 Min 45 Sec".
	local days = match(text, "(%d+)[%s|%d]*[Dd]ay")
	local hours = match(text, "(%d+)[%s|%d]*[Hh]our")
	local mins = match(text, "(%d+)[%s|%d]*[Mm]in")
	local secs = match(text, "(%d+)[%s|%d]*[Ss]ec")
	if days or hours or mins or secs then
		local total = (tonumber(days) or 0) * 86400 + (tonumber(hours) or 0) * 3600 + (tonumber(mins) or 0) * 60 + (tonumber(secs) or 0)
		if total > 0 then
			return total
		end
	end
	local h, m, s = match(text, "(%d+):(%d+):(%d+)")
	if h then
		local total = tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
		if total > 0 then
			return total
		end
	end
end

local function WidgetTimerSeconds(info)
	if not info or info.shownState == Enum.WidgetShownState.Hidden then
		return
	end
	if info.timerValue and info.timerMin and F.NotSecret(info.timerValue) and F.NotSecret(info.timerMin) then
		local remaining = info.timerValue - info.timerMin
		if remaining > 0 then
			return remaining
		end
	end
	if info.hasTimer and info.barValue and info.barMin and F.NotSecret(info.barValue) and F.NotSecret(info.barMin) then
		local remaining = info.barValue - info.barMin
		if remaining > 0 then
			return remaining
		end
		if info.barMax and F.NotSecret(info.barMax) then
			remaining = info.barMax - info.barValue
			if remaining > 0 then
				return remaining
			end
		end
	end
	return ParseWidgetTextSeconds(info.text) or ParseWidgetTextSeconds(info.headerText) or ParseWidgetTextSeconds(info.overrideBarText)
end

local function WidgetProgressPercent(info)
	if not info or info.shownState == Enum.WidgetShownState.Hidden then
		return
	end
	if not (info.barValue and info.barMin and info.barMax) then
		return
	end
	if F.IsSecret(info.barValue) or F.IsSecret(info.barMin) or F.IsSecret(info.barMax) then
		return
	end

	local range = info.barMax - info.barMin
	if range <= 0 then
		return
	end
	local pct = ((info.barValue - info.barMin) / range) * 100
	if pct >= 0 and pct <= 100 then
		return pct
	end
end

local function GetWidgetVisInfo(widgetID, widgetType)
	local widgetManager = _G.UIWidgetManager
	if widgetManager then
		local typeInfo = widgetManager:GetWidgetTypeInfo(widgetType)
		if typeInfo and typeInfo.visInfoDataFunction then
			return typeInfo.visInfoDataFunction(widgetID)
		end
	end
	if not C_UIWidgetManager then
		return
	end
	if widgetType == Enum.UIWidgetVisualizationType.ScenarioHeaderTimer then
		return C_UIWidgetManager.GetScenarioHeaderTimerWidgetVisualizationInfo(widgetID)
	end
	if widgetType == Enum.UIWidgetVisualizationType.StatusBar then
		return C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo(widgetID)
	end
	if widgetType == Enum.UIWidgetVisualizationType.TextWithState then
		return C_UIWidgetManager.GetTextWithStateWidgetVisualizationInfo(widgetID)
	end
	if widgetType == Enum.UIWidgetVisualizationType.IconAndText and C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo then
		return C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo(widgetID)
	end
	if widgetType == Enum.UIWidgetVisualizationType.TextureAndText and C_UIWidgetManager.GetTextureAndTextVisualizationInfo then
		return C_UIWidgetManager.GetTextureAndTextVisualizationInfo(widgetID)
	end
end

local function GetPoiWidgetSecondsLeft(poi)
	local setID = poi and poi.tooltipWidgetSet
	if not setID or not C_UIWidgetManager or not C_UIWidgetManager.GetAllWidgetsBySetID then
		return
	end
	local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(setID)
	if not widgets then
		return
	end

	local best
	for _, widget in ipairs(widgets) do
		local info = GetWidgetVisInfo(widget.widgetID, widget.widgetType)
		local secs = info and WidgetTimerSeconds(info)
		if secs and F.NotSecret(secs) and secs > 0 and (not best or secs < best) then
			best = secs
		end
	end
	return best
end

local function GetPoiWidgetProgressPercent(poi)
	local setID = poi and poi.tooltipWidgetSet
	if not setID or not C_UIWidgetManager or not C_UIWidgetManager.GetAllWidgetsBySetID then
		return
	end
	local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(setID)
	if not widgets then
		return
	end

	for _, widget in ipairs(widgets) do
		local info = GetWidgetVisInfo(widget.widgetID, widget.widgetType)
		local pct = info and WidgetProgressPercent(info)
		if pct then
			return pct
		end
	end
end

local function GetPoiSecondsLeft(poiID, poi)
	local secondsLeft = C_AreaPoiInfo.GetAreaPOISecondsLeft and C_AreaPoiInfo.GetAreaPOISecondsLeft(poiID)
	if secondsLeft and F.NotSecret(secondsLeft) and secondsLeft > 0 then
		return secondsLeft
	end
	if poi then
		return GetPoiWidgetSecondsLeft(poi)
	end
end

local function IsImpendingVoidIncursion(name)
	if not name then
		return false
	end
	local lowerName = name:lower()
	return find(lowerName, "impending", 1, true) and find(lowerName, "incursion", 1, true)
end

local function IsActiveVoidIncursion(name)
	if not name then
		return false
	end
	local lowerName = name:lower()
	return find(lowerName, "void incursion", 1, true) and not find(lowerName, "impending", 1, true)
end

local function IsTrackedWorldEvent(name, atlasName, secs)
	if not name or name == "" then
		return false
	end
	if IsMidnightWorldBossName(name) then
		return false
	end
	if secs and F.NotSecret(secs) and secs > 0 then
		return true
	end
	local lowerName = name:lower()
	if find(lowerName, "stormarion", 1, true) then
		return true
	end
	if find(lowerName, "abundance", 1, true) then
		return true
	end
	if find(lowerName, "incursion", 1, true) then
		return true
	end
	if find(lowerName, "impending", 1, true) then
		return true
	end
	if atlasName then
		local lowerAtlas = atlasName:lower()
		if find(lowerAtlas, "stormarion", 1, true) or find(lowerAtlas, "abundance", 1, true) then
			return true
		end
	end
	return false
end

local function MergeWorldEvent(byName, name, secs, pct)
	local entry = byName[name]
	if not entry then
		byName[name] = { name = name, secs = secs, pct = pct }
		return
	end
	if secs and F.NotSecret(secs) and secs > 0 then
		if not entry.secs or entry.secs <= 0 or secs < entry.secs then
			entry.secs = secs
		end
	end
	if pct and F.NotSecret(pct) then
		entry.pct = pct
	end
end

local function AddConfiguredWorldEvents(byName)
	for _, event in ipairs(CURRENT_WORLD_EVENT_POIS) do
		local found
		for _, poiID in ipairs(event.ids) do
			local poi = C_AreaPoiInfo.GetAreaPOIInfo(event.mapID, poiID)
			if poi then
				found = true
				MergeWorldEvent(byName, event.name or poi.name, GetPoiSecondsLeft(poiID, poi))
			end
		end
		if found and not byName[event.name] then
			MergeWorldEvent(byName, event.name)
		end
	end
end

local function AddWorldEvents()
	if not (C_AreaPoiInfo and C_AreaPoiInfo.GetEventsForMap and C_AreaPoiInfo.GetAreaPOIInfo) then
		return
	end
	if not (C_Map and C_Map.GetMapInfo) then
		return
	end

	local maps = worldEventScanBuffer
	wipe(maps)
	CollectContinentZones(maps)

	local byName = worldEventByName
	wipe(byName)
	AddConfiguredWorldEvents(byName)

	for _, uiMapID in ipairs(maps) do
		local events = C_AreaPoiInfo.GetEventsForMap(uiMapID)
		if events then
			for _, poiID in ipairs(events) do
				local poi = C_AreaPoiInfo.GetAreaPOIInfo(uiMapID, poiID)
				if poi and poi.name then
					local secs = GetPoiSecondsLeft(poiID, poi)
					local pct = IsImpendingVoidIncursion(poi.name) and GetPoiWidgetProgressPercent(poi)
					if IsTrackedWorldEvent(poi.name, poi.atlasName, secs) then
						MergeWorldEvent(byName, poi.name, secs, pct)
					end
				end
			end
		end
	end

	local list = maps
	wipe(list)
	for _, entry in pairs(byName) do
		list[#list + 1] = entry
	end
	if #list == 0 then
		return
	end

	sort(list, function(a, b)
		local aTimed = a.secs and a.secs > 0
		local bTimed = b.secs and b.secs > 0
		if aTimed ~= bTimed then
			return aTimed
		end
		if aTimed and bTimed and a.secs ~= b.secs then
			return a.secs < b.secs
		end
		return a.name < b.name
	end)

	AddTooltipTitle(L["World Events"])
	for _, entry in ipairs(list) do
		local secs = entry.secs
		if entry.pct and F.NotSecret(entry.pct) then
			GameTooltip:AddDoubleLine(entry.name, format("%d%%", floor(entry.pct + 0.5)), 1, 1, 1, 1, 0.82, 0)
		elseif IsActiveVoidIncursion(entry.name) then
			GameTooltip:AddDoubleLine(entry.name, L["Active"], 1, 1, 1, 0.75, 0.75, 0.75)
		elseif secs and F.NotSecret(secs) and secs > 0 then
			-- Same compact format/color as Daily/Weekly Reset and Delves.
			GameTooltip:AddDoubleLine(entry.name, FormatTimer(secs), 1, 1, 1, 1, 1, 1)
		else
			GameTooltip:AddDoubleLine(entry.name, L["Active"], 1, 1, 1, 0.75, 0.75, 0.75)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Shift-held world-event helpers (Legion / BfA invasion timers)
-- ---------------------------------------------------------------------------
local function ValidInvasionSeconds(secondsLeft, maxDuration)
	return secondsLeft and F.NotSecret(secondsLeft) and secondsLeft > 60 and secondsLeft <= maxDuration + 1
end

function GetInvasionTimers()
	if not ns.global then
		return nil
	end
	ns.global.invasionTimers = ns.global.invasionTimers or {}
	return ns.global.invasionTimers
end

local function ImportLegacyInvasionAnchors()
	local timers = GetInvasionTimers()
	if not timers then
		return
	end
	if (not timers.legionStart or timers.legionStart == 0) and type(LegionInvasionTime) == "number" and LegionInvasionTime > 0 then
		timers.legionStart = LegionInvasionTime
	end
	if (not timers.bfaStart or timers.bfaStart == 0) and type(BFAInvasionData) == "table" and BFAInvasionData[1] and BFAInvasionData[1] > 0 then
		timers.bfaStart = BFAInvasionData[1]
		timers.bfaZone = BFAInvasionData[2] or 0
	end
end

local function GetZoneName(mapID)
	if not C_Map or not C_Map.GetMapInfo then
		return nil
	end
	local info = C_Map.GetMapInfo(mapID)
	return info and info.name
end

local function AdvanceBFAZone(zone)
	zone = zone + 1
	if zone > #BFA_ZONES then
		zone = 1
	end
	return zone
end

function ScanInvasionAnchors(force)
	if not C_AreaPoiInfo or not C_AreaPoiInfo.GetAreaPOISecondsLeft then
		return
	end

	local now = time()
	if not force and now - invasionScanAt < INVASION_SCAN_INTERVAL then
		return
	end
	invasionScanAt = now

	ImportLegacyInvasionAnchors()
	local timers = GetInvasionTimers()
	if not timers then
		return
	end

	for _, zone in ipairs(LEGION_ZONES) do
		local left = C_AreaPoiInfo.GetAreaPOISecondsLeft(zone.poiID)
		if ValidInvasionSeconds(left, LEGION_ACTIVE_DURATION) then
			timers.legionStart = now - (LEGION_ACTIVE_DURATION - left)
			break
		end
	end

	for i, zone in ipairs(BFA_ZONES) do
		local left = C_AreaPoiInfo.GetAreaPOISecondsLeft(zone.poiID)
		if ValidInvasionSeconds(left, BFA_ACTIVE_DURATION) then
			timers.bfaStart = now - (BFA_ACTIVE_DURATION - left)
			timers.bfaZone = i
			break
		end
	end
end

function CheckLegionInvasion()
	if not C_AreaPoiInfo or not C_AreaPoiInfo.GetAreaPOISecondsLeft then
		return
	end
	for _, zone in ipairs(LEGION_ZONES) do
		local left = C_AreaPoiInfo.GetAreaPOISecondsLeft(zone.poiID)
		if ValidInvasionSeconds(left, LEGION_ACTIVE_DURATION) then
			return left, GetZoneName(zone.mapID)
		end
	end
end

function CheckBFAInvasion()
	if not C_AreaPoiInfo or not C_AreaPoiInfo.GetAreaPOISecondsLeft then
		return
	end
	for _, zone in ipairs(BFA_ZONES) do
		local left = C_AreaPoiInfo.GetAreaPOISecondsLeft(zone.poiID)
		if ValidInvasionSeconds(left, BFA_ACTIVE_DURATION) then
			return left, GetZoneName(zone.mapID)
		end
	end
end

local function CheckInvasion(index)
	if index == 1 then
		return CheckLegionInvasion()
	end
	if index == 2 then
		return CheckBFAInvasion()
	end
end

local function GetBFACycleElapsed()
	local timers = GetInvasionTimers()
	if not timers or not timers.bfaStart or timers.bfaStart == 0 then
		return
	end
	local elapsed = time() - timers.bfaStart
	while elapsed > BFA_CYCLE_DURATION do
		elapsed = elapsed - BFA_CYCLE_DURATION
	end
	return elapsed, timers.bfaZone
end

-- When the POI API lags, infer an active assault from the saved anchor (BFAInvasionTimer pattern).
local function GetLegionInferredActive()
	local timers = GetInvasionTimers()
	if not timers or not timers.legionStart or timers.legionStart == 0 then
		return
	end
	local elapsed = fmod(time() - timers.legionStart, LEGION_CYCLE_DURATION)
	if elapsed < LEGION_ACTIVE_DURATION then
		return LEGION_ACTIVE_DURATION - elapsed
	end
end

local function GetBFAInferredActive()
	local elapsed, zoneIndex = GetBFACycleElapsed()
	if not elapsed or not zoneIndex or zoneIndex == 0 then
		return
	end
	if elapsed < BFA_ACTIVE_DURATION then
		local zone = BFA_ZONES[zoneIndex]
		return BFA_ACTIVE_DURATION - elapsed, zone and GetZoneName(zone.mapID)
	end
end

local function GetNextInvasionEpochFromStatic(baseTime, duration)
	local timeElapsed = fmod(time() - baseTime, duration)
	return duration - timeElapsed + time()
end

local function GetNextInvasionLocationLegacy(nextEpoch, index)
	if not C_Map or not C_Map.GetMapInfo then
		return _G.QUEUE_TIME_UNAVAILABLE
	end

	local inv = invIndex[index]
	if #inv.timeTable == 0 then
		return _G.QUEUE_TIME_UNAVAILABLE
	end

	local timeElapsed = nextEpoch - inv.baseTime
	local roundCount = fmod(floor(timeElapsed / inv.duration) + 1, #inv.timeTable)
	if roundCount == 0 then
		roundCount = #inv.timeTable
	end

	local map = C_Map.GetMapInfo(inv.maps[inv.timeTable[roundCount]])
	return map and map.name or _G.QUEUE_TIME_UNAVAILABLE
end

local function GetLegionNextEpoch()
	local timers = GetInvasionTimers()
	if timers and timers.legionStart and timers.legionStart > 0 then
		local elapsed = fmod(time() - timers.legionStart, LEGION_CYCLE_DURATION)
		return time() + (LEGION_CYCLE_DURATION - elapsed)
	end
	return GetNextInvasionEpochFromStatic(invIndex[1].baseTime, LEGION_CYCLE_DURATION)
end

local function GetBFANextInfo()
	local timers = GetInvasionTimers()
	if timers and timers.bfaStart and timers.bfaStart > 0 and timers.bfaZone and timers.bfaZone > 0 then
		local elapsed = time() - timers.bfaStart
		local zone = timers.bfaZone
		while elapsed > BFA_CYCLE_DURATION do
			elapsed = elapsed - BFA_CYCLE_DURATION
			zone = AdvanceBFAZone(zone)
		end
		local nextEpoch = time() + (BFA_CYCLE_DURATION - elapsed)
		local nextZone = AdvanceBFAZone(zone)
		local zoneName = BFA_ZONES[nextZone] and GetZoneName(BFA_ZONES[nextZone].mapID)
		return nextEpoch, zoneName
	end

	local nextEpoch = GetNextInvasionEpochFromStatic(invIndex[2].baseTime, BFA_CYCLE_DURATION)
	return nextEpoch, GetNextInvasionLocationLegacy(nextEpoch, 2)
end

local function AddLegionUpcomingRows()
	local timers = GetInvasionTimers()
	if not timers or not timers.legionStart or timers.legionStart == 0 then
		return
	end

	local elapsed = time() - timers.legionStart
	while elapsed > LEGION_CYCLE_DURATION do
		elapsed = elapsed - LEGION_CYCLE_DURATION
	end
	local t = LEGION_CYCLE_DURATION - elapsed + time()
	local minute = date("%M", t)
	if minute == "29" or minute == "59" then
		t = t + 60
	end

	GameTooltip:AddLine(L["Upcoming Invasions"], LBL[1], LBL[2], LBL[3])
	for _ = 1, 2 do
		GameTooltip:AddDoubleLine(
			date("%a %H:%M", t),
			date("%a %H:%M", t + LEGION_CYCLE_DURATION),
			1, 1, 1, 0.6, 0.6, 0.6
		)
		t = t + LEGION_CYCLE_DURATION + LEGION_CYCLE_DURATION
	end
end

local function AddShiftWorldEvents()
	if not C_AreaPoiInfo or not C_AreaPoiInfo.GetAreaPOIInfo or not C_AreaPoiInfo.GetAreaPOISecondsLeft then
		return
	end
	if not C_Map or not C_Map.GetMapInfo then
		return
	end

	for mapID, group in pairs(STORM_POI_IDS) do
		for _, poiIDs in pairs(group) do
			for _, poiID in pairs(poiIDs) do
				local poi = C_AreaPoiInfo.GetAreaPOIInfo(mapID, poiID)
				local eType = poi and poi.atlasName and match(poi.atlasName, "ElementalStorm%-Lesser%-(.+)")
				if eType then
					AddTooltipTitle(poi.name)
					local secondsLeft = C_AreaPoiInfo.GetAreaPOISecondsLeft(poiID)
					local map = C_Map.GetMapInfo(mapID)
					local timerText = (secondsLeft and F.NotSecret(secondsLeft) and secondsLeft > 0) and FormatTimer(secondsLeft) or L["Active"]
					GameTooltip:AddDoubleLine((map and map.name or L["Unknown"]) .. GetElementalType(eType), timerText, 1, 1, 1, 1, 1, 1)
					break
				end
			end
		end
	end

	for areaID, mapID in pairs(HUNT_AREA_TO_MAPID) do
		local poi = C_AreaPoiInfo.GetAreaPOIInfo(1978, areaID)
		if poi then
			AddTooltipTitle(poi.name)
			local secondsLeft = C_AreaPoiInfo.GetAreaPOISecondsLeft(areaID)
			local map = C_Map.GetMapInfo(mapID)
			local timerText = (secondsLeft and F.NotSecret(secondsLeft) and secondsLeft > 0) and FormatTimer(secondsLeft) or L["Active"]
			GameTooltip:AddDoubleLine(map and map.name or L["Unknown"], timerText, 1, 1, 1, 1, 1, 1)
			break
		end
	end

	local feastStart = COMMUNITY_FEAST_TIME[region]
	if feastStart and C_Spell and C_Spell.GetSpellName then
		local duration = 5400
		local now = time()
		local nextFeast = duration - fmod(now - feastStart, duration) + now
		local feastName = C_Spell.GetSpellName(388961)
		if feastName then
			AddTooltipTitle(feastName)
			local active = now - (nextFeast - duration) < 900
			GameTooltip:AddDoubleLine(date("%m/%d %H:%M", nextFeast - duration * 2), date("%m/%d %H:%M", nextFeast - duration), 1, 1, 1, active and 0 or 0.6, active and 1 or 0.6, active and 0 or 0.6)
			GameTooltip:AddDoubleLine(date("%m/%d %H:%M", nextFeast), date("%m/%d %H:%M", nextFeast + duration), 1, 1, 1, 1, 1, 1)
		end
	end

	ScanInvasionAnchors(true)

	for index, inv in ipairs(invIndex) do
		AddTooltipTitle(inv.title)
		local secondsLeft, zoneName = CheckInvasion(index)
		if not secondsLeft then
			if index == 1 then
				secondsLeft = GetLegionInferredActive()
			else
				secondsLeft, zoneName = GetBFAInferredActive()
			end
		end
		local nextTime, nextZoneName
		if index == 1 then
			nextTime = GetLegionNextEpoch()
		else
			nextTime, nextZoneName = GetBFANextInfo()
		end
		if secondsLeft then
			GameTooltip:AddDoubleLine(L["Current Invasion"] .. (zoneName or ""), FormatTimer(secondsLeft), 1, 1, 1, 1, 1, 1)
		end
		local location = (nextZoneName and nextZoneName ~= _G.QUEUE_TIME_UNAVAILABLE) and nextZoneName or ""
		GameTooltip:AddDoubleLine(L["Next Invasion"] .. location, date("%m/%d %H:%M", nextTime), 1, 1, 1, 0.75, 0.75, 0.75)
		if index == 1 then
			AddLegionUpcomingRows()
		end
	end
end

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------
local function ShowClockTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_NONE")
	GameTooltip:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -6)
	GameTooltip:ClearLines()

	local d = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
	if d then
		GameTooltip:AddLine(format(_G.FULLDATE, _G.CALENDAR_WEEKDAY_NAMES[d.weekday], _G.CALENDAR_FULLDATE_MONTH_NAMES[d.month], d.monthDay, d.year), HDR[1], HDR[2], HDR[3])
	else
		GameTooltip:AddLine(_G.TIMEMANAGER_TITLE, HDR[1], HDR[2], HDR[3])
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine(L["Local Time"], GameTime_GetLocalTime(true), LBL[1], LBL[2], LBL[3], 1, 1, 1)
	GameTooltip:AddDoubleLine(L["Realm Time"], GameTime_GetGameTime(true), LBL[1], LBL[2], LBL[3], 1, 1, 1)

	AddResets()
	AddWorldBosses()
	local lockoutsTruncated = AddLockouts()
	AddQuestCompletions()
	AddWeeklyMeta()
	AddDelves()
	AddVoidAssaults()
	AddWorldEvents()

	-- Legacy world-event timers live behind SHIFT as well. When the lockout list
	-- is capped, SHIFT also expands raids/dungeons to the full saved list.
	if lockoutsTruncated and not IsShiftKeyDown() then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L["Hold SHIFT for all lockouts"], LBL[1], LBL[2], LBL[3])
	end

	if cfg and cfg.showLegacy then
		if IsShiftKeyDown() then
			AddShiftWorldEvents()
		else
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(L["Hold SHIFT for info"], LBL[1], LBL[2], LBL[3])
		end
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L["Left-Click: Calendar"], LBL[1], LBL[2], LBL[3])
	GameTooltip:AddLine(L["Middle-Click: Great Vault"], LBL[1], LBL[2], LBL[3])
	GameTooltip:AddLine(L["Right-Click: Time Manager"], LBL[1], LBL[2], LBL[3])
	GameTooltip:Show()
end

local function OnEnter(self)
	entered = true
	tooltipElapsed = 0
	self:RegisterEvent("MODIFIER_STATE_CHANGED")
	self:RegisterEvent("UPDATE_INSTANCE_INFO")
	RequestRaidInfo()
	ShowClockTooltip(self)
end

local function OnLeave()
	entered = false
	if clock then
		clock:UnregisterEvent("MODIFIER_STATE_CHANGED")
		clock:UnregisterEvent("UPDATE_INSTANCE_INFO")
	end
	GameTooltip:Hide()
end

local function OnMouseUp(_, button)
	if button == "RightButton" then
		if _G.ToggleTimeManager then
			_G.ToggleTimeManager()
		end
	elseif button == "MiddleButton" then
		if not _G.WeeklyRewardsFrame and C_AddOns and C_AddOns.LoadAddOn then
			C_AddOns.LoadAddOn("Blizzard_WeeklyRewards")
		end
		if _G.WeeklyRewardsFrame and not InCombatLockdown() then
			ToggleFrame(_G.WeeklyRewardsFrame)
		end
		if _G.WeeklyRewardExpirationWarningDialog and _G.WeeklyRewardExpirationWarningDialog:IsShown() then
			_G.WeeklyRewardExpirationWarningDialog:Hide()
		end
	else
		if _G.ToggleCalendar then
			_G.ToggleCalendar()
		end
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
local function DumpTimeDiagnostics()
	F.Print(format("  time()=%s GetTime()=%s", time(), GetTime and GetTime() or "?"))
	F.Print(format("  local=%s realm=%s", date("%H:%M:%S"), select(1, GetGameTime()) and format("%02d:%02d", GetGameTime()) or "?"))

	local rawDaily = GetQuestResetTime and GetQuestResetTime()
	if rawDaily then
		F.Print(format("  GetQuestResetTime(raw)=%s", FormatTimer(rawDaily)))
	end
	local daily = F.GetSecondsUntilDailyReset()
	local weekly = F.GetSecondsUntilWeeklyReset()
	F.Print(format("  dailyReset=%s weeklyReset=%s", daily and FormatTimer(daily) or "n/a", weekly and FormatTimer(weekly) or "n/a"))

	local offsetH = F.GetServerOffsetHours()
	local offsetSec = offsetH * 3600
	F.Print(format("  serverOffset=%sh", offsetH))

	local nextDaily = F.GetNextDailyResetTime()
	local nextWeekly = F.GetNextWeeklyResetTime()
	if nextDaily then
		F.Print(format("  nextDaily: local %s | realm %s", date("%Y-%m-%d %H:%M", nextDaily), date("%Y-%m-%d %H:%M", nextDaily + offsetSec)))
	end
	if nextWeekly then
		F.Print(format("  nextWeekly: local %s | realm %s", date("%Y-%m-%d %H:%M", nextWeekly), date("%Y-%m-%d %H:%M", nextWeekly + offsetSec)))
	end

	if cfg and cfg.showLegacy then
		ScanInvasionAnchors(true)
		local timers = GetInvasionTimers()
		if timers then
			local legionStart = timers.legionStart or 0
			local bfaStart = timers.bfaStart or 0
			F.Print(format(
				"  legionAnchor=%s bfaAnchor=%s bfaZone=%s",
				legionStart > 0 and date("%Y-%m-%d %H:%M", legionStart) or "none",
				bfaStart > 0 and date("%Y-%m-%d %H:%M", bfaStart) or "none",
				tostring(timers.bfaZone or 0)
			))
			local legionLeft, legionZone = CheckLegionInvasion()
			local bfaLeft, bfaZone = CheckBFAInvasion()
			F.Print(format(
				"  legionActive=%s bfaActive=%s",
				legionLeft and format("%s (%s)", FormatTimer(legionLeft), legionZone or "?") or "no",
				bfaLeft and format("%s (%s)", FormatTimer(bfaLeft), bfaZone or "?") or "no"
			))
		end
	end
end

local function StartClockTicker(self)
	clockElapsed = 0
	tooltipElapsed = 0
	self:SetScript("OnUpdate", function(frame, e)
		local dt = e or 0
		if entered then
			tooltipElapsed = tooltipElapsed + dt
			if tooltipElapsed >= TOOLTIP_REFRESH then
				tooltipElapsed = 0
				ShowClockTooltip(frame)
			end
		else
			tooltipElapsed = 0
		end

		clockElapsed = clockElapsed + dt
		if clockElapsed < CLOCK_TICK then
			return
		end
		clockElapsed = 0
		UpdateClock(frame)
	end)
end

function Clock:Create()
	if clock then
		StartClockTicker(clock)
		clock:Show()
		UpdateClock(clock)
		return
	end

	-- Parent and anchor to the minimap so the clock always rides with it (the
	-- minimap itself is moved via Edit Mode); an absolute anchor would get left
	-- behind whenever the minimap is repositioned or its cluster is resized.
	local minimap = _G["Minimap"]
	clock = CreateFrame("Button", nil, minimap or UIParent)
	clock.nexBinSelf = true -- never sweep our own clock into the minimap button tray
	clock:SetSize(60, 18)
	clock:RegisterForClicks("AnyUp")
	if minimap then
		clock:SetFrameLevel(minimap:GetFrameLevel() + 5)
		clock:SetPoint("BOTTOM", minimap, "BOTTOM", 0, 3)
	else
		clock:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end

	clock.text = F.CreatePlainFS(clock, 13)
	clock.text:SetPoint("CENTER")

	clock:SetScript("OnEnter", OnEnter)
	clock:SetScript("OnLeave", OnLeave)
	clock:SetScript("OnMouseUp", OnMouseUp)
	clock:SetScript("OnEvent", function(self, event)
		if not entered then
			return
		end
		if event == "MODIFIER_STATE_CHANGED" or event == "UPDATE_INSTANCE_INFO" then
			ShowClockTooltip(self)
		end
	end)

	StartClockTicker(clock)

	UpdateClock(clock)
end

function Clock:RegisterModuleEvents()
	if eventsRegistered then
		return
	end
	eventsRegistered = true
	self:TrackEvent(eventHandles, "PLAYER_ENTERING_WORLD", "CheckTimeWalker")
end

function Clock:UnregisterModuleEvents()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
end

function Clock:Stop()
	self:UnregisterModuleEvents()
	entered = false
	if clock then
		clock:UnregisterEvent("MODIFIER_STATE_CHANGED")
		clock:UnregisterEvent("UPDATE_INSTANCE_INFO")
		clock:SetScript("OnUpdate", nil)
		clock:Hide()
	end
end

function Clock:OnInitialize()
	ns.Debug.BindModule(self, "clock", {
		title = L["Clock"],
		expectations = {
			{
				name = "clock frame matches enable toggle",
				test = function()
					if not cfg or not cfg.enable then
						return not eventsRegistered
					end
					return clock ~= nil and eventsRegistered
				end,
				detail = function()
					return format("enable=%s eventsRegistered=%s clock=%s", tostring(cfg and cfg.enable), tostring(eventsRegistered), clock and "yes" or "no")
				end,
			},
		},
		dump = function()
			F.Print(format("  enable=%s showLegacy=%s entered=%s", tostring(cfg and cfg.enable), tostring(cfg and cfg.showLegacy), tostring(entered)))
			DumpTimeDiagnostics()
			if RequestRaidInfo then
				RequestRaidInfo()
			end
			local count = GetNumSavedInstances and GetNumSavedInstances() or 0
			F.Print(format("  savedInstanceCount=%d", count))
			for i = 1, count do
				local info = ReadSavedInstance(i)
				if info.name then
					local isRaid = IsSavedInstanceRaid(info)
					local bucket = isRaid and "raid" or ((info.diff == 2 or info.diff == 23) and "dungeon" or "hidden")
					F.Print(format(
						"  [%d] %q shown=%s bucket=%s apiIsRaid=%s mapId=%s maxP=%s diff=%s",
						i,
						info.name,
						tostring(info.locked or info.extended),
						bucket,
						tostring(info.isRaid),
						tostring(info.gameInstanceID),
						tostring(info.maxPlayers),
						tostring(info.diff)
					))
				end
			end
		end,
	})
end

function Clock:OnEnable()
	cfg = ns.db.timeText
	if not cfg.enable then
		return
	end
	self:Create()
	self:RegisterModuleEvents()
end

function Clock:OnDisable()
	self:Stop()
end

function Clock:OnSettingChanged(key, value)
	cfg = ns.db.timeText
	if key == "enable" then
		-- ApplyModuleSetting owns enable lifecycle.
		return
	end
	if key == "showLegacy" and value then
		invasionScanAt = 0
		ScanInvasionAnchors(true)
	end
	if clock and cfg.enable then
		UpdateClock(clock)
	end
end

function Clock:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Clock"], L["Show a clock on the minimap with a lockout / reset tooltip."])
	local _, classColorInit = builder:Checkbox(category, self, "classColor", L["Class-Coloured Numbers"], L["Colour the clock with your class colour."])
	local _, legacyInit = builder:Checkbox(category, self, "showLegacy", L["Show Legacy World Events"], L["Track pre-Midnight world events (Legion invasions, faction assaults, elemental storms, Grand Hunt, Community Feast) and the old daily-quest checklist. Hold SHIFT over the clock to see the timers."])

	builder:DependsOn(classColorInit, enableInit)
	builder:DependsOn(legacyInit, enableInit)
end
