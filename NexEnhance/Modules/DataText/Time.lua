--[[
	NexEnhance - DataText: Clock
	-------------------------------------------------------------------------
	A minimap clock that follows Blizzard's own 12/24h and local/realm time
	CVars. Hovering it opens a tooltip with the full date, local & realm time,
	resets, saved raid / dungeon / world-boss lockouts, weekly quest checks,
	Delves, Delver keys, and Shift-held world-event details.

	Adapted from KkthnxUI's Time DataText by Josh "Kkthnx" Russell:
	  https://github.com/Kkthnx-Wow/KkthnxUI_Firestorm/blob/main/KkthnxUI/Modules/DataText/Elements/Time.lua
--]]

---@diagnostic disable: undefined-field, undefined-global
local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local _G = _G
local date, time = date, time
local format, find, match = string.format, string.find, string.match
local floor, fmod = math.floor, math.fmod
local ipairs, pairs, select, tonumber = ipairs, pairs, select, tonumber
local wipe = wipe

-- Shared tooltip palette (single source of truth in Constants.lua): gold section
-- headers, light-blue labels/hints, white values.
local HDR = C.Colors.header
local LBL = C.Colors.label

local CreateFrame = CreateFrame
local GetCVar = GetCVar
local GetCVarBool = GetCVarBool
local GetGameTime = GetGameTime
local GetQuestResetTime = GetQuestResetTime
local GetNumSavedInstances = GetNumSavedInstances
local GetNumSavedWorldBosses = GetNumSavedWorldBosses
local GetSavedInstanceInfo = GetSavedInstanceInfo
local GetSavedWorldBossInfo = GetSavedWorldBossInfo
local GameTime_GetGameTime = GameTime_GetGameTime
local GameTime_GetLocalTime = GameTime_GetLocalTime
local InCombatLockdown = InCombatLockdown
local IsShiftKeyDown = IsShiftKeyDown
local RequestRaidInfo = RequestRaidInfo
local SecondsToTime = SecondsToTime
local ToggleFrame = ToggleFrame
local UIParent = UIParent

local C_AddOns = C_AddOns
local C_AreaPoiInfo = C_AreaPoiInfo
local C_Calendar = C_Calendar
local C_CurrencyInfo = C_CurrencyInfo
local C_DateAndTime = C_DateAndTime
local C_Item = C_Item
local C_Map = C_Map
local C_QuestLog = C_QuestLog
local C_Spell = C_Spell
local C_Texture = C_Texture

ns:RegisterDefaults({
	timeText = {
		enable = true,
		classColor = false,
	},
})

local Clock = ns:NewModule("Clock", "timeText", { group = "datatext", title = L["Clock"], order = 30 })

local cfg
local clock
local entered
local isTimeWalker
local walkerTexture

local region = GetCVar and GetCVar("portal") or "US"
local keyInfo = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(3028)
local keyName = keyInfo and keyInfo.name or L["Restored Coffer Key"]

local DELVES_KEYS = { 91175, 91176, 91177, 91178 }
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

local mapAreaPoiIDs = {
	[630] = 5175, [641] = 5210, [650] = 5177, [634] = 5178,
	[862] = 5973, [863] = 5969, [864] = 5970, [896] = 5964, [942] = 5966, [895] = 5896,
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
	2393, 2424, 2405, 2413, 2395, 2437,
	2248, 2215, 2214, 2255, 2346, 2371,
}

local STORM_POI_IDS = {
	[2022] = { { 7249, 7250, 7251, 7252 }, { 7253, 7254, 7255, 7256 }, { 7257, 7258, 7259, 7260 } },
	[2023] = { { 7221, 7222, 7223, 7224 }, { 7225, 7226, 7227, 7228 } },
	[2024] = { { 7229, 7230, 7231, 7232 }, { 7233, 7234, 7235, 7236 }, { 7237, 7238, 7239, 7240 } },
	[2025] = { { 7245, 7246, 7247, 7248 }, { 7298, 7299, 7300, 7301 } },
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

-- World-event countdowns (invasions, storms, hunts) run for hours, so display
-- them as HH:MM. NDui reaches the same result by dividing seconds->minutes
-- before its MM:SS formatter; we convert straight from raw seconds here.
local function FormatShortTime(seconds)
	seconds = floor(seconds or 0)
	return format("%.2d:%.2d", floor(seconds / 3600), floor((seconds % 3600) / 60))
end

local function UpdateClock(self)
	local hour, minute
	if GetCVarBool("timeMgrUseLocalTime") then
		hour, minute = tonumber(date("%H")), tonumber(date("%M"))
	else
		hour, minute = GetGameTime()
	end

	local pending = (C_Calendar and C_Calendar.GetNumPendingInvites and C_Calendar.GetNumPendingInvites() or 0) > 0
	self.text:SetText(FormatClock(hour, minute, pending))
	self:SetWidth(self.text:GetStringWidth() + 8)
end

-- ---------------------------------------------------------------------------
-- Cached lookups
-- ---------------------------------------------------------------------------
local function TextureStringByAtlas(atlas, width, height)
	if not atlas or not C_Texture or not C_Texture.GetAtlasInfo then return "" end
	if not C_Texture.GetAtlasInfo(atlas) then return "" end
	return format("|A:%s:%d:%d|a", atlas, height or 16, width or 16)
end

local function GetElementalType(element)
	if not atlasCache[element] then
		atlasCache[element] = TextureStringByAtlas("ElementalStorm-Lesser-" .. element, 16, 16)
	end
	return atlasCache[element]
end

local function GetItemLink(itemID)
	if not C_Item or not C_Item.GetItemInfo then return nil end
	if not itemCache[itemID] then
		itemCache[itemID] = select(2, C_Item.GetItemInfo(itemID))
	end
	return itemCache[itemID]
end

-- ---------------------------------------------------------------------------
-- Calendar / quest data
-- ---------------------------------------------------------------------------
function Clock:CheckTimeWalker()
	if not C_Calendar or not C_DateAndTime or not find then return end
	if not C_Calendar.GetNumDayEvents or not C_Calendar.GetDayEvent or not C_Calendar.OpenCalendar or not C_Calendar.SetAbsMonth then return end

	local calDate = C_DateAndTime.GetCurrentCalendarTime()
	if not calDate then return end

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
	local daily = GetQuestResetTime and GetQuestResetTime()
	if daily and daily > 0 then
		GameTooltip:AddDoubleLine(L["Daily Reset"], SecondsToTime(daily, true, nil, 2), LBL[1], LBL[2], LBL[3], 1, 1, 1)
	end

	local weekly = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and C_DateAndTime.GetSecondsUntilWeeklyReset()
	if weekly and weekly > 0 then
		GameTooltip:AddDoubleLine(L["Weekly Reset"], SecondsToTime(weekly, true, nil, 2), LBL[1], LBL[2], LBL[3], 1, 1, 1)
	end
end

local function AddWorldBosses()
	local count = GetNumSavedWorldBosses and GetNumSavedWorldBosses() or 0
	if count == 0 then return end

	AddTooltipTitle(_G.RAID_INFO_WORLD_BOSS)
	for i = 1, count do
		local name, id, reset = GetSavedWorldBossInfo(i)
		if name and id ~= 11 and id ~= 12 and id ~= 13 then
			GameTooltip:AddDoubleLine(name, SecondsToTime(reset, true, nil, 2), 1, 1, 1, 0.75, 0.75, 0.75)
		end
	end
end

-- Locale-independent difficulty abbreviations keyed by difficultyID, so long
-- names like "Looking For Raid" / "40 Player" stay short in the tooltip.
local DIFF_ABBR = {
	[1] = "N", [2] = "H",
	[3] = "10N", [4] = "25N", [5] = "10H", [6] = "25H", [7] = "LFR",
	[9] = "40", [14] = "N", [15] = "H", [16] = "M", [17] = "LFR",
	[23] = "M", [24] = "TW", [33] = "TW",
}

-- Tier colours (gear-quality language: green/blue/purple) so the abbreviation
-- stands out at a glance. Keyed by difficultyID to stay locale-independent.
local DIFF_COLOR = {
	[1] = "1eff00", [3] = "1eff00", [4] = "1eff00", [14] = "1eff00", -- Normal: green
	[2] = "0070dd", [5] = "0070dd", [6] = "0070dd", [15] = "0070dd", -- Heroic: blue
	[16] = "a335ee", [23] = "a335ee", -- Mythic: purple
	[7] = "9d9d9d", [17] = "9d9d9d", -- LFR: grey
	[9] = "ff8000", -- 40 Player: orange
	[24] = "00ccff", [33] = "00ccff", -- Timewalking: light blue
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
	if not total or total <= 0 then return 1, 0, 0 end
	local ratio = (progress or 0) / total
	if ratio <= 0 then return 1, 0, 0 end
	if ratio >= 1 then return 0, 1, 0 end
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

local function AddLockouts()
	local count = GetNumSavedInstances and GetNumSavedInstances() or 0
	if count == 0 then return end

	local dungeonHeader, raidHeader
	for i = 1, count do
		local name, _, reset, diff, locked, extended, _, isRaid, _, diffName, numEncounters, progress = GetSavedInstanceInfo(i)
		if (locked or extended) and name then
			local r, g, b = extended and 0.3 or 0.75, extended and 1 or 0.75, extended and 0.3 or 0.75
			if not isRaid and (diff == 2 or diff == 23) then
				if not dungeonHeader then
					AddTooltipTitle(L["Saved Dungeon(s)"])
					dungeonHeader = true
				end
				GameTooltip:AddDoubleLine(format("%s - %s %s", name, AbbrDiff(diff, diffName), ProgressString(progress, numEncounters)), SecondsToTime(reset, true, nil, 2), 1, 1, 1, r, g, b)
			elseif isRaid then
				if not raidHeader then
					AddTooltipTitle(L["Saved Raid(s)"])
					raidHeader = true
				end
				GameTooltip:AddDoubleLine(format("%s - %s %s", name, AbbrDiff(diff, diffName), ProgressString(progress, numEncounters)), SecondsToTime(reset, true, nil, 2), 1, 1, 1, r, g, b)
			end
		end
	end
end

local function AddQuestCompletions()
	if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return end

	local header
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

	local keyCount = 0
	for _, questID in ipairs(DELVES_KEYS) do
		if C_QuestLog.IsQuestFlaggedCompleted(questID) then
			keyCount = keyCount + 1
		end
	end
	if keyCount > 0 then
		if not header then
			AddTooltipTitle(_G.QUESTS_LABEL)
		end
		local done = keyCount == #DELVES_KEYS
		GameTooltip:AddDoubleLine(keyName, format("%d/%d", keyCount, #DELVES_KEYS), 1, 1, 1, done and 1 or 0, done and 0 or 1, 0)
	end
end

-- A bountiful delve is the special weekly delve flagged with a "bountiful" atlas
-- (e.g. "delves-bountiful"). Plain delve entrances are everywhere and would
-- flood the tooltip, so we list only bountiful ones (matches NDui/KkthnxUI).
local function IsBountifulDelve(info)
	return info and info.atlasName and find(info.atlasName, "[Bb]ountiful") and true or false
end

local function AddDelveLine(uiMapID, info, header, seen)
	local id = info and (info.areaPoiID or info.poiID or info.delveID or info.name)
	if not info or (id and seen[id]) then return header, false end
	if id then
		seen[id] = true
	end

	if not header then
		AddTooltipTitle(info.description or L["Delves"])
		header = true
	end

	local mapInfo = C_Map.GetMapInfo(uiMapID)
	GameTooltip:AddDoubleLine(format("%s - %s", mapInfo and mapInfo.name or L["Unknown"], info.name or L["Unknown"]), SecondsToTime(GetQuestResetTime(), true, nil, 2), 1, 1, 1, 0.75, 0.75, 0.75)
	return header, true
end

-- Reused scratch buffer (avoid per-hover table churn).
local delveScanBuffer = {}

-- Walk from the player's current map up to its continent, then collect the
-- continent + all of its zone maps. This keeps delve detection patch-proof: we
-- never hardcode the current expansion's map IDs.
local function CollectContinentZones(result)
	if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetMapInfo then return end

	local mapID = C_Map.GetBestMapForUnit("player")
	local guard = 0
	while mapID and guard < 20 do
		guard = guard + 1
		local info = C_Map.GetMapInfo(mapID)
		if not info then return end
		if info.mapType == Enum.UIMapType.Continent then break end
		mapID = info.parentMapID
	end
	if not mapID then return end

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

-- Scan the given maps for bountiful delves using Blizzard's delve POI list.
local function ScanDelveMaps(maps, header, seen)
	if not C_AreaPoiInfo.GetDelvesForMap then return header, false end

	local found
	for _, uiMapID in ipairs(maps) do
		local poiIDs = C_AreaPoiInfo.GetDelvesForMap(uiMapID)
		if poiIDs then
			for _, poiID in ipairs(poiIDs) do
				local info = C_AreaPoiInfo.GetAreaPOIInfo(uiMapID, poiID)
				if IsBountifulDelve(info) then
					local added
					header, added = AddDelveLine(uiMapID, info, header, seen)
					found = found or added
				end
			end
		end
	end
	return header, found
end

local function AddDelves()
	if not C_AreaPoiInfo or not C_AreaPoiInfo.GetAreaPOIInfo then return end
	if not C_Map or not C_Map.GetMapInfo then return end

	local header, found
	local seen = {}

	-- 1) Dynamic scan of the player's current continent (current content).
	local maps = delveScanBuffer
	wipe(maps)
	CollectContinentZones(maps)
	header, found = ScanDelveMaps(maps, header, seen)
	if found then return end

	-- 2) Static known delve maps via the same delve API (for when the player is
	--    off-continent but we still want this week's bountiful delves).
	header, found = ScanDelveMaps(DELVE_SCAN_MAPS, header, seen)
	if found then return end

	-- 3) Legacy fallback: hardcoded POI IDs for older clients.
	for _, delve in ipairs(DELVE_LIST) do
		local info = C_AreaPoiInfo.GetAreaPOIInfo(delve.uiMapID, delve.delveID or 0)
		if info then
			header = AddDelveLine(delve.uiMapID, info, header, seen)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Shift-held world-event helpers
-- ---------------------------------------------------------------------------
local function GetInvasionInfo(mapID)
	if not C_AreaPoiInfo or not C_AreaPoiInfo.GetAreaPOISecondsLeft or not C_Map or not C_Map.GetMapInfo then return nil, nil end

	local areaPoiID = mapAreaPoiIDs[mapID]
	if not areaPoiID then return nil, nil end

	local secondsLeft = C_AreaPoiInfo.GetAreaPOISecondsLeft(areaPoiID)
	local mapData = C_Map.GetMapInfo(mapID)
	return secondsLeft, mapData and mapData.name
end

local function CheckInvasion(index)
	for _, mapID in ipairs(invIndex[index].maps) do
		local secondsLeft, zoneName = GetInvasionInfo(mapID)
		if secondsLeft and secondsLeft > 0 then
			return secondsLeft, zoneName
		end
	end
end

local function GetNextInvasionTime(baseTime, index)
	local duration = invIndex[index].duration
	local timeElapsed = fmod(time() - baseTime, duration)
	return duration - timeElapsed + time()
end

local function GetNextInvasionLocation(nextTime, index)
	if not C_Map or not C_Map.GetMapInfo then return _G.QUEUE_TIME_UNAVAILABLE end

	local inv = invIndex[index]
	if #inv.timeTable == 0 then
		return _G.QUEUE_TIME_UNAVAILABLE
	end

	local timeElapsed = nextTime - inv.baseTime
	local roundCount = fmod(floor(timeElapsed / inv.duration) + 1, #inv.timeTable)
	if roundCount == 0 then
		roundCount = #inv.timeTable
	end

	local map = C_Map.GetMapInfo(inv.maps[inv.timeTable[roundCount]])
	return map and map.name or _G.QUEUE_TIME_UNAVAILABLE
end

local function AddShiftWorldEvents()
	if not C_AreaPoiInfo or not C_AreaPoiInfo.GetAreaPOIInfo or not C_AreaPoiInfo.GetAreaPOISecondsLeft then return end
	if not C_Map or not C_Map.GetMapInfo then return end

	for mapID, group in pairs(STORM_POI_IDS) do
		for _, poiIDs in pairs(group) do
			for _, poiID in pairs(poiIDs) do
				local poi = C_AreaPoiInfo.GetAreaPOIInfo(mapID, poiID)
				local eType = poi and poi.atlasName and match(poi.atlasName, "ElementalStorm%-Lesser%-(.+)")
				if eType then
					AddTooltipTitle(poi.name)
					local secondsLeft = C_AreaPoiInfo.GetAreaPOISecondsLeft(poiID) or 0
					local map = C_Map.GetMapInfo(mapID)
					GameTooltip:AddDoubleLine((map and map.name or L["Unknown"]) .. GetElementalType(eType), FormatShortTime(secondsLeft), 1, 1, 1, secondsLeft < 3600 and 1 or 0, secondsLeft < 3600 and 0 or 1, 0)
					break
				end
			end
		end
	end

	for areaID, mapID in pairs(HUNT_AREA_TO_MAPID) do
		local poi = C_AreaPoiInfo.GetAreaPOIInfo(1978, areaID)
		if poi then
			AddTooltipTitle(poi.name)
			local secondsLeft = C_AreaPoiInfo.GetAreaPOISecondsLeft(areaID) or 0
			local map = C_Map.GetMapInfo(mapID)
			GameTooltip:AddDoubleLine(map and map.name or L["Unknown"], FormatShortTime(secondsLeft), 1, 1, 1, secondsLeft < 3600 and 1 or 0, secondsLeft < 3600 and 0 or 1, 0)
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

	for index, inv in ipairs(invIndex) do
		AddTooltipTitle(inv.title)
		local secondsLeft, zoneName = CheckInvasion(index)
		local nextTime = GetNextInvasionTime(inv.baseTime, index)
		if secondsLeft then
			GameTooltip:AddDoubleLine(L["Current Invasion"] .. (zoneName or ""), FormatShortTime(secondsLeft), 1, 1, 1, secondsLeft < 3600 and 1 or 0, secondsLeft < 3600 and 0 or 1, 0)
		end
		GameTooltip:AddDoubleLine(L["Next Invasion"] .. GetNextInvasionLocation(nextTime, index), date("%m/%d %H:%M", nextTime), 1, 1, 1, 0.75, 0.75, 0.75)
	end
end

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------
local function OnEnter(self)
	entered = true
	self:RegisterEvent("MODIFIER_STATE_CHANGED")
	RequestRaidInfo()

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
	AddLockouts()
	AddQuestCompletions()
	AddDelves()

	if IsShiftKeyDown() then
		AddShiftWorldEvents()
	else
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L["Hold SHIFT for info"], LBL[1], LBL[2], LBL[3])
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L["Left-Click: Calendar"], LBL[1], LBL[2], LBL[3])
	GameTooltip:AddLine(L["Middle-Click: Great Vault"], LBL[1], LBL[2], LBL[3])
	GameTooltip:AddLine(L["Right-Click: Time Manager"], LBL[1], LBL[2], LBL[3])
	GameTooltip:Show()
end

local function OnLeave()
	entered = false
	if clock then
		clock:UnregisterEvent("MODIFIER_STATE_CHANGED")
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
function Clock:Create()
	if clock then
		clock:Show()
		return
	end

	-- Parent and anchor to the minimap so the clock always rides with it (the
	-- minimap itself is moved via Edit Mode); an absolute anchor would get left
	-- behind whenever the minimap is repositioned or its cluster is resized.
	local minimap = _G["Minimap"]
	clock = CreateFrame("Button", nil, minimap or UIParent)
	clock:SetSize(60, 18)
	clock:RegisterForClicks("AnyUp")
	if minimap then
		clock:SetFrameLevel(minimap:GetFrameLevel() + 5)
		clock:SetPoint("BOTTOM", minimap, "BOTTOM", 0, 3)
	else
		clock:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end

	clock.text = clock:CreateFontString(nil, "OVERLAY")
	clock.text:SetFont(C.Media.Fonts.normal, 13, "")
	clock.text:SetShadowColor(0, 0, 0, 1)
	clock.text:SetShadowOffset(1, -1)
	clock.text:SetPoint("CENTER")

	clock:SetScript("OnEnter", OnEnter)
	clock:SetScript("OnLeave", OnLeave)
	clock:SetScript("OnMouseUp", OnMouseUp)
	clock:SetScript("OnEvent", function(self, event)
		if event == "MODIFIER_STATE_CHANGED" and entered then
			OnEnter(self)
		end
	end)

	local elapsed = 5
	clock:SetScript("OnUpdate", function(self, e)
		elapsed = elapsed + (e or 0)
		if elapsed < 5 then return end
		elapsed = 0
		UpdateClock(self)
		if entered then OnEnter(self) end
	end)

	UpdateClock(clock)
end

function Clock:OnEnable()
	cfg = ns.db.timeText
	if not cfg.enable then return end
	self:Create()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "CheckTimeWalker")
end

function Clock:OnSettingChanged(key, value)
	cfg = ns.db.timeText
	if key == "enable" then
		if value then
			self:Create()
		elseif clock then
			clock:Hide()
		end
	elseif clock then
		UpdateClock(clock)
	end
end

function Clock:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Clock"], L["Show a clock on the minimap with a lockout / reset tooltip (reload to disable)."])
	local _, classColorInit = builder:Checkbox(category, self, "classColor", L["Class-Coloured Numbers"], L["Colour the clock with your class colour."])

	builder:DependsOn(classColorInit, enableInit)
end
