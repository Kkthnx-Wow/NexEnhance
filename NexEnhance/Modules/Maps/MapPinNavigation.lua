--[[
	NexEnhance - Map Pin Navigation
	-------------------------------------------------------------------------
	Enhances Blizzard's super-track arrow (SuperTrackedFrame):
	  * Unlimited map-pin render distance (distance-based alpha override)
	  * Custom distance text (yards/meters, abbreviated thousands)
	  * ETA under the arrow (smoothed speed estimate)
	  * /way-style chat commands for user waypoints

	Blizzard refs (Resources 12.0.7): Blizzard_QuestNavigation/SuperTrackedFrame.lua,
	C_Navigation, C_SuperTrack, C_Map.SetUserWaypoint.

	SuperTrackedFrame lives in load-on-demand Blizzard_QuestNavigation. Frame
	method overrides gate on IsEnabled(); full visual revert needs /reload.
	C_Navigation.GetDistance has no secret tags (Resources 12.0.7) — plain math.
	ETA FontString copies DistanceText shadow (not CreatePlainFS) — Slug shadow
	regression on 12.0.7 if we used our plain-font helper here.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local C, L, F = ns.C, ns.L, ns.F

local _G = _G
local abs, floor, max = math.abs, math.floor, math.max
local format, lower, match, gsub = string.format, string.lower, string.match, string.gsub
local tinsert, tconcat = table.insert, table.concat
local strtrim = strtrim
local GetCVar = GetCVar
local GetTime = GetTime
local GetCursorPosition = GetCursorPosition
local Round = Round
local FrameDeltaLerp = FrameDeltaLerp
local ClampedPercentageBetween = ClampedPercentageBetween
local TIMER_MINUTES_DISPLAY = TIMER_MINUTES_DISPLAY
local UiMapPoint = UiMapPoint

local C_AddOns = C_AddOns
local C_Map = C_Map
local C_Navigation = C_Navigation
local C_SuperTrack = C_SuperTrack
local C_Timer_After = C_Timer.After

local GetDistance = C_Navigation and C_Navigation.GetDistance
local WasClampedToScreen = C_Navigation and C_Navigation.WasClampedToScreen
local HasValidScreenPosition = C_Navigation and C_Navigation.HasValidScreenPosition

ns:RegisterDefaults({
	mapPinNavigation = {
		enable = true,
		showEta = true,
		respectNavigationCVar = true,
		minDistance = 0,
		maxDistance = 0, -- 0 = no upper limit
		fadeDistance = 1000,
		pinAlphaShort = 100,
		pinAlphaLong = 60,
		pinAlphaClamped = 100,
		fadeMouseOver = true,
		useMeters = false,
		shortNumbers = true,
		autoTrackWaypoints = true,
		waypointSlash = true,
	},
})

local MapPinNavigation = ns:NewModule("MapPinNavigation", "mapPinNavigation", {
	group = "maps",
	title = L["Map Pin Navigation"],
	order = 44,
})

local styled
local navCvarEnabled = true
local lastDistance, lastUpdate, emaSpeed = nil, 0, nil
local origMethods
local slashRegistered
local eventHandles = {}
local lastAlphaSkipReason
local debugSnapshotKey
local lastSnapshotTime
local lastEtaLogKey
local lastEtaState

local ETA_SAMPLE_INTERVAL = 0.5
local ETA_RETREAT_SPEED = -3 -- yd/s; hide when clearly moving away
local ETA_APPROACH_SPEED = 0.5 -- yd/s; below this, hold ETA on smoothed speed

local function db()
	return ns.db.mapPinNavigation
end

local function NavCvarEnabled()
	if not db().respectNavigationCVar then
		return true
	end
	return navCvarEnabled
end

local function DistanceInRange(distance)
	local cfg = db()
	local minD = cfg.minDistance or 0
	local maxD = cfg.maxDistance or 0
	if distance < minD then
		return false
	end
	if maxD > 0 and distance > maxD then
		return false
	end
	return true
end

local function FormatDistance(distance)
	local cfg = db()
	local measure = " yds"
	if cfg.useMeters then
		distance = distance * 0.9144
		measure = " m"
	end
	if cfg.shortNumbers and distance > 1000 then
		return format("%sK%s", Round(distance / 100) / 10, measure)
	end
	return format("%d%s", Round(distance), measure)
end

local function DebugAlphaSkip(reason, detail)
	if lastAlphaSkipReason == reason then
		return
	end
	lastAlphaSkipReason = reason
	if reason == "active" then
		MapPinNavigation:DebugLog("info", "alpha path active%s", detail or "")
	else
		MapPinNavigation:DebugLog("info", "alpha hidden: %s%s", reason, detail or "")
	end
end

local function DebugNavSnapshot(frame)
	if not (frame and frame:IsShown()) then
		return
	end
	local now = GetTime()
	if now - (lastSnapshotTime or 0) < 3 then
		return
	end
	lastSnapshotTime = now

	local distance = GetDistance and GetDistance()
	local distStr = (distance == nil and "nil") or tostring(Round(distance))
	local clamped = WasClampedToScreen and WasClampedToScreen() or false
	local inRange = distance and DistanceInRange(distance) or false
	local targetAlpha = frame.GetTargetAlphaBaseValue and frame:GetTargetAlphaBaseValue() or -1
	local key = format("%s|%s|%s|%.2f", distStr, tostring(clamped), tostring(inRange), targetAlpha)
	if key == debugSnapshotKey then
		return
	end
	debugSnapshotKey = key
	MapPinNavigation:DebugLog(
		"info",
		"snapshot dist=%s clamped=%s inRange=%s targetAlpha=%.2f navCvar=%s emaSpeed=%s",
		distStr,
		tostring(clamped),
		tostring(inRange),
		targetAlpha,
		tostring(NavCvarEnabled()),
		emaSpeed and format("%.1f", emaSpeed) or "nil"
	)
end

local function HideEta(frame)
	if frame.TimeText then
		frame.TimeText:Hide()
	end
	lastDistance, lastUpdate, emaSpeed = nil, 0, nil
	lastEtaLogKey = nil
	lastEtaState = nil
end

local function ShowEta(frame, distance, speed, state)
	if not (frame.TimeText and speed and speed > 0) then
		return
	end
	local eta = abs(distance / max(speed, 0.1))
	local etaMin, etaSec = floor(eta / 60), floor(eta % 60)
	frame.TimeText:SetFormattedText(TIMER_MINUTES_DISPLAY, etaMin, etaSec)
	frame.TimeText:Show()
	lastEtaState = state or "active"
	local etaKey = format("%d:%d|%s", etaMin, etaSec, lastEtaState)
	if etaKey ~= lastEtaLogKey then
		lastEtaLogKey = etaKey
		MapPinNavigation:DebugLog("info", "eta %dm %ds dist=%d speed=%.1f", etaMin, etaSec, Round(distance), speed)
	end
end

local function UpdateEta(frame, elapsed)
	if not MapPinNavigation:IsEnabled() or not db().enable or not db().showEta then
		HideEta(frame)
		return
	end
	if not GetDistance then
		return
	end
	if WasClampedToScreen and WasClampedToScreen() then
		if frame.TimeText then
			frame.TimeText:Hide()
		end
		return
	end

	lastUpdate = lastUpdate + (elapsed or 0)
	if lastUpdate < ETA_SAMPLE_INTERVAL then
		return
	end

	local distance = GetDistance()
	if distance == nil then
		return
	end
	if distance <= 0 then
		HideEta(frame)
		return
	end

	-- Seed the first sample; `prev = lastDistance or distance` would always yield zero speed.
	if lastDistance == nil then
		lastDistance = distance
		lastUpdate = 0
		if lastEtaState ~= "seed" then
			lastEtaState = "seed"
			MapPinNavigation:DebugLog("info", "eta seed dist=%d (walk toward pin)", Round(distance))
		end
		return
	end

	local prev = lastDistance
	local instSpeed = (prev - distance) / lastUpdate
	lastDistance = distance
	lastUpdate = 0

	if instSpeed < ETA_RETREAT_SPEED then
		if frame.TimeText then
			frame.TimeText:Hide()
		end
		lastEtaLogKey = nil
		emaSpeed = nil
		if lastEtaState ~= "retreat" then
			lastEtaState = "retreat"
			MapPinNavigation:DebugLog("info", "eta hidden (moving away) dist=%d speed=%.1f", Round(distance), instSpeed)
		end
		return
	end

	if instSpeed >= ETA_APPROACH_SPEED then
		emaSpeed = emaSpeed and (emaSpeed * 0.6 + instSpeed * 0.4) or instSpeed
		ShowEta(frame, distance, emaSpeed, "active")
	elseif emaSpeed and emaSpeed > 0 then
		emaSpeed = emaSpeed * 0.95
		ShowEta(frame, distance, emaSpeed, "stalled")
	else
		if frame.TimeText then
			frame.TimeText:Hide()
		end
		lastEtaLogKey = nil
		if lastEtaState ~= "stalled" then
			lastEtaState = "stalled"
			MapPinNavigation:DebugLog("info", "eta stalled (no speed) dist=%d", Round(distance))
		end
	end
	DebugNavSnapshot(frame)
end

local function GetTargetAlphaBaseValue(frame)
	if not origMethods then
		return 0
	end
	if not MapPinNavigation:IsEnabled() or not db().enable then
		DebugAlphaSkip("module_disabled")
		return origMethods.GetTargetAlphaBaseValue(frame)
	end
	if not NavCvarEnabled() then
		DebugAlphaSkip("nav_cvar_off", " (showInGameNavigation)")
		return 0
	end

	local distance = GetDistance and GetDistance()
	if distance == nil then
		DebugAlphaSkip("distance_unavailable")
		return origMethods.GetTargetAlphaBaseValue(frame)
	end

	if not DistanceInRange(distance) then
		DebugAlphaSkip("out_of_range", format(" dist=%d min=%d max=%d", Round(distance), db().minDistance or 0, db().maxDistance or 0))
		return 0
	end

	DebugAlphaSkip("active")
	local cfg = db()
	if frame.isClamped then
		return (cfg.pinAlphaClamped or 100) / 100
	end
	if distance > (cfg.fadeDistance or 1000) then
		return (cfg.pinAlphaLong or 60) / 100
	end
	return (cfg.pinAlphaShort or 100) / 100
end

local function UpdateDistanceText(frame)
	if not origMethods then
		return
	end
	if not MapPinNavigation:IsEnabled() or not db().enable then
		return origMethods.UpdateDistanceText(frame)
	end

	if not frame.isClamped then
		local distance = GetDistance and GetDistance()
		if distance ~= nil then
			frame.DistanceText:SetText(FormatDistance(distance))
			frame.distance = distance
		end
	end

	frame.DistanceText:SetShown(not frame.isClamped)
	if frame.TimeText then
		frame.TimeText:SetShown(not frame.isClamped and db().showEta)
	end
end

local function GetTargetAlpha(frame)
	if not origMethods then
		return 0
	end
	if not HasValidScreenPosition or not HasValidScreenPosition() then
		return 0
	end

	if frame.transparentUntil and frame.transparentUntil > GetTime() then
		return 0
	end
	frame.transparentUntil = nil

	local additionalFade = 1.0
	if MapPinNavigation:IsEnabled() and db().enable and db().fadeMouseOver and frame:IsMouseOver() then
		local mouseX, mouseY = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale()
		mouseX = mouseX / scale
		mouseY = mouseY / scale
		local centerX, centerY = frame:GetCenter()
		frame.mouseToNavVec:SetXY(mouseX - centerX, mouseY - centerY)
		local mouseToNavDistanceSq = frame.mouseToNavVec:GetLengthSquared()
		additionalFade = ClampedPercentageBetween(mouseToNavDistanceSq, 0, frame.navFrameRadiusSq * 2)
	elseif not (MapPinNavigation:IsEnabled() and db().enable) then
		return origMethods.GetTargetAlpha(frame)
	end

	return FrameDeltaLerp(frame:GetAlpha(), GetTargetAlphaBaseValue(frame) * additionalFade, 0.1)
end

local function InstallFrameOverrides(frame)
	if frame.__nexMapPinInstalled or not origMethods then
		return
	end
	frame.__nexMapPinInstalled = true

	frame.GetTargetAlphaBaseValue = GetTargetAlphaBaseValue
	frame.UpdateDistanceText = UpdateDistanceText
	frame.GetTargetAlpha = GetTargetAlpha
end

local function StyleSuperTrackedFrame(frame)
	if styled or not (frame and frame.DistanceText) then
		return
	end
	styled = true

	if not origMethods then
		origMethods = {
			GetTargetAlphaBaseValue = frame.GetTargetAlphaBaseValue,
			UpdateDistanceText = frame.UpdateDistanceText,
			GetTargetAlpha = frame.GetTargetAlpha,
		}
	end

	local _, size, flags = frame.DistanceText:GetFont()
	frame.DistanceText:SetFont(C.Media.Fonts.normal, size or 12, flags)

	local time = frame:CreateFontString(nil, "BACKGROUND")
	time:SetFont(C.Media.Fonts.normal, size or 12, flags)
	local sox, soy = frame.DistanceText:GetShadowOffset()
	time:SetShadowOffset(sox, soy)
	local sr, sg, sb, sa = frame.DistanceText:GetShadowColor()
	time:SetShadowColor(sr, sg, sb, sa)
	local tr, tg, tb = frame.DistanceText:GetTextColor()
	time:SetTextColor(tr, tg, tb)
	time:SetPoint("TOP", frame.DistanceText, "BOTTOM", 0, -2)
	time:SetHeight(20)
	time:SetJustifyV("TOP")
	time:SetWordWrap(false)
	time:Hide()
	frame.TimeText = time

	InstallFrameOverrides(frame)

	MapPinNavigation:DebugLog("info", "SuperTrackedFrame styled overrides=%s", tostring(frame.__nexMapPinInstalled))

	frame:HookScript("OnUpdate", function(self, elapsed)
		UpdateEta(self, elapsed)
	end)
	frame:HookScript("OnHide", HideEta)
end

local function EnsureSuperTrackStyled()
	local frame = _G.SuperTrackedFrame
	if frame then
		StyleSuperTrackedFrame(frame)
		return
	end
	ns:RegisterAddOnLoadedCallback("Blizzard_QuestNavigation", function()
		StyleSuperTrackedFrame(_G.SuperTrackedFrame)
	end)
end

-- ---------------------------------------------------------------------------
-- Zone lookup for /way parsing (UMPD-compatible scan)
-- ---------------------------------------------------------------------------

local function FindZoneId(zoneName, parentMapID)
	zoneName = lower(strtrim(zoneName or ""))
	if zoneName == "" then
		return 0
	end
	parentMapID = parentMapID or 0
	for mapID = 0, 4000 do
		local info = C_Map.GetMapInfo(mapID)
		if info and info.name and lower(info.name) == zoneName then
			if parentMapID == 0 or info.parentMapID == parentMapID then
				return mapID
			end
		end
	end
	return 0
end

function MapPinNavigation:HandleWaypointSlash(msg)
	if not db().enable or not db().waypointSlash then
		return
	end
	if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and C_SuperTrack) then
		return
	end

	msg = lower(msg or "")
	local wrongSep = "(%d)" .. (tonumber("1.1") and "," or ".") .. "(%d)"
	local rightSep = "%1" .. (tonumber("1.1") and "." or ",") .. "%2"

	local tokens = {}
	msg = msg:gsub("(%d)[%.,] (%d)", "%1 %2"):gsub(wrongSep, rightSep)
	for token in msg:gmatch("%S+") do
		tinsert(tokens, token)
	end

	local zoneIndex = 0
	for i = 1, #tokens do
		if tonumber(tokens[i]) then
			zoneIndex = i - 1
			break
		end
	end

	local zoneText = zoneIndex > 0 and tconcat(tokens, " ", 1, zoneIndex) or nil
	local x = tonumber(tokens[zoneIndex + 1])
	local y = tonumber(tokens[zoneIndex + 2])
	if not (x and y) then
		self:DebugLog("warn", "waypoint parse failed: %q", msg)
		return
	end

	local mapID = C_Map.GetBestMapForUnit("player")
	if zoneText and #zoneText > 1 then
		local tier = match(zoneText, "%#([0-9]+)")
		if tier then
			mapID = tonumber(tier)
		else
			local subName = match(zoneText, ":([a-z%s'`]+)")
			local cleanZone = match(zoneText, "([a-z%s'`]+)")
			cleanZone = gsub(cleanZone or "", "[ \t]+%f[\r\n%z]", "")
			local subMap = 0
			if subName and #subName > 0 then
				subName = gsub(subName, "[ \t]+%f[\r\n%z]", "")
				subMap = FindZoneId(subName, 0)
			end
			local zoneMap = FindZoneId(cleanZone, subMap)
			if zoneMap ~= 0 then
				mapID = zoneMap
			end
		end
	end

	if not mapID then
		return
	end

	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
	if C_SuperTrack.SetSuperTrackedUserWaypoint then
		C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	end
	self:DebugLog("info", "waypoint set mapID=%s xy=%.2f,%.2f", tostring(mapID), x, y)
end

local function RegisterWaypointSlash()
	if slashRegistered or not db().waypointSlash then
		return
	end
	slashRegistered = true
	MapPinNavigation:DebugLog("info", "slash registered nexway=%s way=%s pin=%s", "yes", tostring(not C_AddOns.IsAddOnLoaded("TomTom")), tostring(not C_AddOns.IsAddOnLoaded("SlashPin")))
	_G.SLASH_NEXWAY1 = "/nexway"
	_G.SlashCmdList["NEXWAY"] = function(msg)
		MapPinNavigation:HandleWaypointSlash(msg)
	end

	if not C_AddOns.IsAddOnLoaded("TomTom") then
		_G.SLASH_NEXMAPWAY1 = "/way"
		_G.SlashCmdList["NEXMAPWAY"] = function(msg)
			MapPinNavigation:HandleWaypointSlash(msg)
		end
	end

	if not C_AddOns.IsAddOnLoaded("SlashPin") then
		_G.SLASH_NEXMAPPIN1 = "/pin"
		_G.SlashCmdList["NEXMAPPIN"] = function(msg)
			MapPinNavigation:HandleWaypointSlash(msg)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

function MapPinNavigation:USER_WAYPOINT_UPDATED()
	if not db().enable or not db().autoTrackWaypoints then
		self:DebugLog("info", "USER_WAYPOINT_UPDATED skipped enable=%s auto=%s", tostring(db().enable), tostring(db().autoTrackWaypoints))
		return
	end
	if C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() then
		self:DebugLog("info", "USER_WAYPOINT_UPDATED auto-track scheduled")
		C_Timer_After(0, function()
			if db().autoTrackWaypoints and C_SuperTrack.SetSuperTrackedUserWaypoint then
				C_SuperTrack.SetSuperTrackedUserWaypoint(true)
			end
		end)
	end
end

function MapPinNavigation:SUPER_TRACKING_CHANGED()
	if not db().enable then
		return
	end
	local quest = C_SuperTrack.IsSuperTrackingQuest and C_SuperTrack.IsSuperTrackingQuest()
	local waypoint = C_SuperTrack.IsSuperTrackingUserWaypoint and C_SuperTrack.IsSuperTrackingUserWaypoint()
	local anything = C_SuperTrack.IsSuperTrackingAnything and C_SuperTrack.IsSuperTrackingAnything()
	self:DebugLog("info", "SUPER_TRACKING_CHANGED quest=%s waypoint=%s anything=%s", tostring(quest), tostring(waypoint), tostring(anything))
	HideEta(_G.SuperTrackedFrame or {})
	lastAlphaSkipReason = nil
	debugSnapshotKey = nil
	lastEtaLogKey = nil
	lastEtaState = nil
	if quest then
		if C_SuperTrack.SetSuperTrackedUserWaypoint then
			C_SuperTrack.SetSuperTrackedUserWaypoint(false)
		end
	end
end

function MapPinNavigation:CVAR_UPDATE(_, cvarName)
	if cvarName == "showInGameNavigation" or cvarName == "SHOW_IN_GAME_NAVIGATION" then
		navCvarEnabled = GetCVar("showInGameNavigation") == "1"
		self:DebugLog("info", "showInGameNavigation=%s", tostring(navCvarEnabled))
	end
end

function MapPinNavigation:RefreshNavCvar()
	navCvarEnabled = GetCVar("showInGameNavigation") == "1"
end

function MapPinNavigation:RegisterModuleEvents()
	if #eventHandles > 0 then
		return
	end
	self:TrackEvent(eventHandles, "USER_WAYPOINT_UPDATED")
	self:TrackEvent(eventHandles, "SUPER_TRACKING_CHANGED")
	self:TrackEvent(eventHandles, "CVAR_UPDATE")
end

function MapPinNavigation:UnregisterModuleEvents()
	ns:UnregisterModuleEventHandles(eventHandles)
end

function MapPinNavigation:OnEnable()
	if not db().enable then
		return
	end
	self:DebugLog("info", "OnEnable")
	self:RefreshNavCvar()
	RegisterWaypointSlash()
	EnsureSuperTrackStyled()
	self:RegisterModuleEvents()
end

function MapPinNavigation:OnDisable()
	self:DebugLog("info", "OnDisable")
	self:UnregisterModuleEvents()
	HideEta(_G.SuperTrackedFrame or {})
	lastDistance, lastUpdate, emaSpeed = nil, 0, nil
end

function MapPinNavigation:OnSettingChanged(key, value)
	-- ApplyModuleSetting owns enable lifecycle.
	if key == "enable" then
		return
	elseif key == "waypointSlash" and value then
		RegisterWaypointSlash()
	elseif key == "showEta" and not value then
		HideEta(_G.SuperTrackedFrame or {})
	end
end

function MapPinNavigation:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Map Pin Navigation"], L["Unlimited super-track distance, custom distance text, ETA, and waypoint slash commands."])
	local _, etaInit = builder:Checkbox(category, self, "showEta", L["Show Arrival ETA"], L["Estimated time to reach the tracked pin under the arrow."])
	local _, cvarInit = builder:Checkbox(category, self, "respectNavigationCVar", L["Require In-Game Navigation"], L["Only show the super-track arrow when Interface > Show In-Game Navigation is enabled."])
	local _, metersInit = builder:Checkbox(category, self, "useMeters", L["Use Meters"], L["Show distance in meters instead of yards."])
	local _, shortInit = builder:Checkbox(category, self, "shortNumbers", L["Abbreviate Distance"], L["Show 1.2K-style distance above 1000."])
	local _, fadeMouseInit = builder:Checkbox(category, self, "fadeMouseOver", L["Fade on Mouse Over"], L["Fade the arrow while the cursor is over it."])
	local _, autoInit = builder:Checkbox(category, self, "autoTrackWaypoints", L["Auto-Track New Waypoints"], L["Super-track user waypoints when you place them."])
	local _, slashInit = builder:Checkbox(category, self, "waypointSlash", L["Waypoint Slash Commands"], L["Register /way and /pin when TomTom is not loaded (/nexway always)."])

	builder:DependsOn(etaInit, enableInit)
	builder:DependsOn(cvarInit, enableInit)
	builder:DependsOn(metersInit, enableInit)
	builder:DependsOn(shortInit, enableInit)
	builder:DependsOn(fadeMouseInit, enableInit)
	builder:DependsOn(autoInit, enableInit)
	builder:DependsOn(slashInit, enableInit)

	local _, minInit = builder:Slider(category, self, "minDistance", L["Minimum Pin Distance"], L["Hide the arrow when closer than this (yards)."], 0, 500, 25)
	local _, maxInit = builder:Slider(category, self, "maxDistance", L["Maximum Pin Distance"], L["Hide beyond this distance; 0 = unlimited."], 0, 10000, 100)
	local _, fadeInit = builder:Slider(category, self, "fadeDistance", L["Long-Range Fade Starts"], L["Beyond this distance the Long Range Alpha applies (yards)."], 0, 5000, 100)
	local _, alphaShortInit = builder:Slider(category, self, "pinAlphaShort", L["Close Range Alpha"], L["Arrow opacity within fade distance (%)."], 0, 100, 5)
	local _, alphaLongInit = builder:Slider(category, self, "pinAlphaLong", L["Long Range Alpha"], L["Arrow opacity beyond fade distance (%)."], 0, 100, 5)
	local _, alphaClampInit = builder:Slider(category, self, "pinAlphaClamped", L["Edge Arrow Alpha"], L["Opacity when the arrow is clamped to screen edge (%)."], 0, 100, 5)

	builder:DependsOn(minInit, enableInit)
	builder:DependsOn(maxInit, enableInit)
	builder:DependsOn(fadeInit, enableInit)
	builder:DependsOn(alphaShortInit, enableInit)
	builder:DependsOn(alphaLongInit, enableInit)
	builder:DependsOn(alphaClampInit, enableInit)
end

local function SuperTrackTypeLabel()
	if not C_SuperTrack or not C_SuperTrack.GetHighestPrioritySuperTrackingType then
		return "nil"
	end
	local t = C_SuperTrack.GetHighestPrioritySuperTrackingType()
	if not t then
		return "none"
	end
	if Enum and Enum.SuperTrackingType then
		for name, value in pairs(Enum.SuperTrackingType) do
			if value == t then
				return name
			end
		end
	end
	return tostring(t)
end

function MapPinNavigation:OnInitialize()
	ns.Debug.BindModule(self, "mapPinNavigation", {
		title = L["Map Pin Navigation"],
		expectations = {
			{
				name = "module events match enable toggle",
				test = function()
					local en = ns.db and ns.db.mapPinNavigation and ns.db.mapPinNavigation.enable
					return en and (#eventHandles > 0) or not (#eventHandles > 0)
				end,
				detail = function()
					local en = ns.db and ns.db.mapPinNavigation and ns.db.mapPinNavigation.enable
					return format("enable=%s eventHandles=%d", tostring(en), #eventHandles)
				end,
			},
			{
				name = "SuperTrackedFrame styled when QuestNavigation UI loaded",
				test = function()
					if not (ns.db and ns.db.mapPinNavigation and ns.db.mapPinNavigation.enable) then
						return true
					end
					if not C_AddOns.IsAddOnLoaded("Blizzard_QuestNavigation") then
						return true
					end
					return styled == true
				end,
				detail = function()
					return format("styled=%s ahNavLoaded=%s", tostring(styled), tostring(C_AddOns.IsAddOnLoaded("Blizzard_QuestNavigation")))
				end,
			},
		},
		dump = function()
			local cfg = ns.db and ns.db.mapPinNavigation
			local frame = _G.SuperTrackedFrame
			F.Print(format("  enable=%s showEta=%s respectNavigationCVar=%s", tostring(cfg and cfg.enable), tostring(cfg and cfg.showEta), tostring(cfg and cfg.respectNavigationCVar)))
			F.Print(format("  fadeDistance=%s pinAlphaShort=%s pinAlphaLong=%s pinAlphaClamped=%s", tostring(cfg and cfg.fadeDistance), tostring(cfg and cfg.pinAlphaShort), tostring(cfg and cfg.pinAlphaLong), tostring(cfg and cfg.pinAlphaClamped)))
			F.Print(format("  styled=%s overrides=%s slashRegistered=%s eventHandles=%d", tostring(styled), tostring(frame and frame.__nexMapPinInstalled), tostring(slashRegistered), #eventHandles))
			F.Print(format("  questNavLoaded=%s navCvar=%s TomTom=%s SlashPin=%s", tostring(C_AddOns.IsAddOnLoaded("Blizzard_QuestNavigation")), tostring(navCvarEnabled), tostring(C_AddOns.IsAddOnLoaded("TomTom")), tostring(C_AddOns.IsAddOnLoaded("SlashPin"))))
			if frame then
				local distance = GetDistance and GetDistance()
				local distStr = (distance == nil and "nil") or tostring(Round(distance))
				local distNum = distance and Round(distance) or nil
				local fadeDist = cfg and cfg.fadeDistance or 1000
				local longAlpha = (cfg and cfg.pinAlphaLong or 60) / 100
				local unlimited = distNum and distNum > fadeDist and frame:GetAlpha() > 0.01
				F.Print(format(
					"  SuperTrackedFrame shown=%s clamped=%s dist=%s alpha=%.2f trackType=%s",
					tostring(frame:IsShown()),
					tostring(WasClampedToScreen and WasClampedToScreen()),
					distStr,
					frame:GetAlpha(),
					SuperTrackTypeLabel()
				))
				F.Print(format(
					"  unlimitedRange=%s (dist>%d uses long alpha %.0f%%; yours=%.0f%%)",
					unlimited and "YES" or (distNum and distNum <= fadeDist and "n/a (within fade distance)" or "no"),
					fadeDist,
					longAlpha * 100,
					frame:GetAlpha() * 100
				))
				if frame.TimeText then
					F.Print(format("  TimeText shown=%s text=%q emaSpeed=%s", tostring(frame.TimeText:IsShown()), frame.TimeText:GetText() or "", emaSpeed and format("%.1f", emaSpeed) or "nil"))
				end
			else
				F.Print("  SuperTrackedFrame=nil (open map / track something to load Blizzard_QuestNavigation)")
			end
			F.Print(L["Map Pin Navigation debug tip"])
		end,
	})
end
