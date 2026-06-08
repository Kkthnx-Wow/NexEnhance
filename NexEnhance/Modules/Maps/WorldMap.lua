--[[
	NexEnhance - World Map
	-------------------------------------------------------------------------
	Quality-of-life tweaks for the default world map:
	  * Player + cursor coordinates along the bottom of the map.
	  * A smaller, windowed map (scaled down) so it no longer swallows the
	    whole screen, draggable via an Edit Mode mover (LibEditMode).
	  * Optional fade while the player is moving, so the map gets out of the
	    way during travel.

	Adapted to the NexEnhance framework from KkthnxUI's Modules/Maps/WorldMap.lua
	(by Josh "Kkthnx" Russell):
	  https://github.com/Kkthnx-Wow/KkthnxUI/blob/master/KkthnxUI/Modules/Maps/WorldMap.lua

	K.* helpers are replaced with framework equivalents (F.ColorStr/F.UnitColor
	for the class-coloured numbers, C.Media for the coord-bar texture/font).
	All frame members are existence-guarded so a renamed Blizzard field degrades
	quietly instead of erroring.
--]]

-- luacheck: globals PlayerMovementFrameFader
---@diagnostic disable: undefined-global, undefined-field
local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local select, type = select, type
local CreateFrame, UIParent, hooksecurefunc = CreateFrame, UIParent, hooksecurefunc
local IsPlayerMoving, UIFrameFade = IsPlayerMoving, UIFrameFade
local C_Map_GetBestMapForUnit = C_Map.GetBestMapForUnit
local C_Map_GetPlayerMapPosition = C_Map.GetPlayerMapPosition
local PLAYER, MOUSE = PLAYER, (MOUSE_LABEL or "Mouse")

ns:RegisterDefaults({
	worldMap = {
		enable = true,
		coordinates = true,
		smallMap = true,
		smallMapScale = 0.8,
		fadeWhenMoving = false,
		alphaWhenMoving = 0.35,
	},
})

local WorldMap = ns:NewModule("WorldMap", "worldMap", { group = "maps", title = L["World Map"], order = 10 })

local cfg
local classColorStr = F.ColorStr(F.UnitColor("player"))
local currentMapID, cursorCoords, playerCoords, coordsUpdater, fadeFrame, mapAnchor

-- ---------------------------------------------------------------------------
-- Movable anchor (Edit Mode)
--   The windowed map follows an invisible anchor frame registered with our
--   LibEditMode mover, so it can be dragged like any other NexEnhance element.
--   We anchor the map to it (rather than make the giant map itself the mover)
--   so Blizzard's own Maximize/Minimize repositioning never fights the saved
--   position - we simply re-anchor whenever the windowed state is restored.
-- ---------------------------------------------------------------------------
local function GetAnchor()
	if mapAnchor then return mapAnchor end
	mapAnchor = CreateFrame("Frame", nil, UIParent)
	mapAnchor:SetSize(700, 466)
	F.CreateMover(mapAnchor, "worldMap", L["World Map"], "TOPLEFT", 16, -94)
	return mapAnchor
end

-- Pin the windowed map's top-left to the mover anchor and size the Edit Mode
-- box to match the map so the selection overlay lines up.
local function AnchorMapToMover(wmf)
	local anchor = GetAnchor()
	local w, h = wmf:GetSize()
	if w and w > 1 then
		anchor:SetSize(w, h)
	end
	wmf:ClearAllPoints()
	wmf:SetPoint("TOPLEFT", anchor, "TOPLEFT")
end

-- ---------------------------------------------------------------------------
-- Coordinates
-- ---------------------------------------------------------------------------
local function GetPlayerMapPos(mapID)
	if not mapID then return end
	local pos = C_Map_GetPlayerMapPosition(mapID, "player")
	if not pos then return end
	return pos:GetXY()
end

local function GetCursorCoords()
	local wmf = _G.WorldMapFrame
	local scroll = wmf and wmf.ScrollContainer
	if not scroll or not scroll:IsMouseOver() then return end

	local x, y = scroll:GetNormalizedCursorPosition()
	if x < 0 or x > 1 or y < 0 or y > 1 then return end
	return x, y
end

-- Owner label + class colour is constant for the session, so the only per-tick
-- variation is whether we have coordinates. Precompute all four strings once so
-- the throttled coord updater never rebuilds them via concatenation.
local mouseCoordsFmt = MOUSE .. classColorStr .. ": %.1f, %.1f"
local mouseNoneFmt = MOUSE .. classColorStr .. ": --, --"
local playerCoordsFmt = PLAYER .. classColorStr .. ": %.1f, %.1f"
local playerNoneFmt = PLAYER .. classColorStr .. ": --, --"

local function UpdateCoords(self, elapsed)
	if not _G.WorldMapFrame:IsShown() then return end

	self.elapsed = (self.elapsed or 0) + elapsed
	if self.elapsed < 0.2 then return end
	self.elapsed = 0

	local cursorX, cursorY = GetCursorCoords()
	cursorCoords:SetFormattedText(cursorX and mouseCoordsFmt or mouseNoneFmt, 100 * (cursorX or 0), 100 * (cursorY or 0))

	local x, y = GetPlayerMapPos(currentMapID)
	local havePlayerPos = currentMapID and x and (x ~= 0 or y ~= 0)
	playerCoords:SetFormattedText(havePlayerPos and playerCoordsFmt or playerNoneFmt, 100 * (x or 0), 100 * (y or 0))
end

local function UpdateMapID(self)
	if self:GetMapID() == C_Map_GetBestMapForUnit("player") then
		currentMapID = self:GetMapID()
	else
		currentMapID = nil
	end
end

-- ---------------------------------------------------------------------------
-- Smaller windowed map (scaled). Each handler is gated by cfg.smallMap so the
-- option can be toggled live (it applies on the next open / state change).
-- ---------------------------------------------------------------------------
local function SetLargeWorldMap()
	local wmf = _G.WorldMapFrame
	if not cfg.smallMap then return end

	wmf:SetParent(UIParent)
	wmf:SetScale(1)
	if wmf.ScrollContainer and wmf.ScrollContainer.Child then
		wmf.ScrollContainer.Child:SetScale(cfg.smallMapScale)
	end

	if wmf.OnFrameSizeChanged then wmf:OnFrameSizeChanged() end
	if wmf:GetMapID() and wmf.NavBar and wmf.NavBar.Refresh then
		wmf.NavBar:Refresh()
	end
end

local function UpdateMaximizedSize()
	local wmf = _G.WorldMapFrame
	if not cfg.smallMap then return end

	local width, height = wmf:GetSize()
	local magicNumber = (1 - cfg.smallMapScale) * 100
	wmf:SetSize((width * cfg.smallMapScale) - (magicNumber + 2), (height * cfg.smallMapScale) - 2)
end

local function SynchronizeDisplayState()
	local wmf = _G.WorldMapFrame
	if not cfg.smallMap then return end

	if wmf:IsMaximized() then
		wmf:ClearAllPoints()
		wmf:SetPoint("CENTER", UIParent)
	else
		-- Restore the saved mover position after a Blizzard state change.
		AnchorMapToMover(wmf)
	end
end

local function SetSmallWorldMap()
	local wmf = _G.WorldMapFrame
	if not cfg.smallMap or wmf:IsMaximized() then return end
	AnchorMapToMover(wmf)
end

-- ---------------------------------------------------------------------------
-- Fade while moving
-- ---------------------------------------------------------------------------
local function MapShouldFade()
	return cfg.fadeWhenMoving and not _G.WorldMapFrame:IsMouseOver()
end

local function MapFadeOnUpdate(self, elapsed)
	self.elapsed = (self.elapsed or 0) + elapsed
	if self.elapsed < 0.1 then return end
	self.elapsed = 0

	local wmf = _G.WorldMapFrame

	-- Option turned off while the map is open: restore full opacity and stop
	-- running. Re-enabling re-arms on the next map open (matches smallMap).
	if not cfg.fadeWhenMoving then
		wmf:SetAlpha(1)
		self:Hide()
		return
	end

	local fadeObject = self.FadeObject
	local settings = fadeObject and fadeObject.FadeSettings
	if not settings then return end

	local isFadingOut = IsPlayerMoving() and (not settings.fadePredicate or settings.fadePredicate())
	local endAlpha = (isFadingOut and (settings.minAlpha or 0.5)) or settings.maxAlpha or 1
	local startAlpha = wmf:GetAlpha()

	fadeObject.timeToFade = settings.durationSec or 0.5
	fadeObject.startAlpha = startAlpha
	fadeObject.endAlpha = endAlpha
	fadeObject.diffAlpha = endAlpha - startAlpha
	fadeObject.fadeTimer = nil

	UIFrameFade(wmf, fadeObject)
end

local function StopMapFromFading()
	if fadeFrame then fadeFrame:Hide() end
end

local function EnableMapFading(frame)
	if not fadeFrame then
		fadeFrame = CreateFrame("Frame")
		fadeFrame:SetScript("OnUpdate", MapFadeOnUpdate)
		frame:HookScript("OnHide", StopMapFromFading)
		fadeFrame.FadeObject = { FadeSettings = {} }
	end

	local settings = fadeFrame.FadeObject.FadeSettings
	settings.fadePredicate = MapShouldFade
	settings.durationSec = 0.2
	settings.minAlpha = cfg.alphaWhenMoving
	settings.maxAlpha = 1

	fadeFrame:Show()
end

-- Intercept Blizzard's frame fader so our predicate takes over for the map.
local function UpdateMapFade(...)
	local arg1, arg2 = ...

	local frame
	if type(arg1) == "table" and type(arg1.IsShown) == "function" and arg1 ~= PlayerMovementFrameFader then
		frame = arg1
	elseif arg1 == PlayerMovementFrameFader and type(arg2) == "table" and type(arg2.IsShown) == "function" then
		frame = arg2
	elseif type(arg2) == "table" and type(arg2.IsShown) == "function" then
		frame = arg2
	else
		return
	end

	local fadePredicate
	for i = 6, 1, -1 do
		local val = select(i, ...)
		if type(val) == "function" then
			fadePredicate = val
			break
		end
	end

	if frame == _G.WorldMapFrame and frame:IsShown() and fadePredicate ~= MapShouldFade then
		PlayerMovementFrameFader.RemoveFrame(frame)
		if cfg.fadeWhenMoving then
			EnableMapFading(frame)
		else
			frame:SetAlpha(1)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Coordinate widgets
-- ---------------------------------------------------------------------------
local function BuildCoords()
	if coordsUpdater then return end

	local wmf = _G.WorldMapFrame
	local scroll = wmf.ScrollContainer
	if not scroll then return end

	local bar = CreateFrame("Frame", nil, scroll)
	bar:SetSize(wmf:GetWidth(), 17)
	bar:SetPoint("BOTTOMLEFT", 17, 0)
	bar:SetPoint("BOTTOMRIGHT", 0, 0)

	local tex = bar:CreateTexture(nil, "BACKGROUND")
	tex:SetAllPoints()
	tex:SetTexture(C.Media.Textures.blank)
	tex:SetVertexColor(0.04, 0.04, 0.04, 0.5)

	cursorCoords = bar:CreateFontString(nil, "OVERLAY")
	cursorCoords:SetFont(C.Media.Fonts.normal, 13, "OUTLINE")
	cursorCoords:SetSize(200, 16)
	cursorCoords:SetPoint("BOTTOMLEFT", 152, 1)
	cursorCoords:SetTextColor(0.94, 0.77, 0)

	playerCoords = bar:CreateFontString(nil, "OVERLAY")
	playerCoords:SetFont(C.Media.Fonts.normal, 13, "OUTLINE")
	playerCoords:SetSize(200, 16)
	playerCoords:SetPoint("BOTTOMRIGHT", -132, 1)
	playerCoords:SetTextColor(0.94, 0.77, 0)

	hooksecurefunc(wmf, "OnFrameSizeChanged", UpdateMapID)
	hooksecurefunc(wmf, "OnMapChanged", UpdateMapID)

	coordsUpdater = CreateFrame("Frame", nil, scroll)
	coordsUpdater:SetScript("OnUpdate", UpdateCoords)
end

local function SetCoordsShown(shown)
	if not coordsUpdater then return end
	cursorCoords:SetShown(shown)
	playerCoords:SetShown(shown)
	coordsUpdater:SetScript("OnUpdate", shown and UpdateCoords or nil)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function WorldMap:Setup()
	if self.started then return end
	local wmf = _G.WorldMapFrame
	if not wmf then return end -- Blizzard_WorldMap not available yet
	self.started = true

	if cfg.coordinates then
		BuildCoords()
	end

	-- Small-map hooks are installed once; each is gated by cfg.smallMap so the
	-- option toggles live on the next open / maximize change.
	hooksecurefunc(wmf, "Maximize", SetLargeWorldMap)
	hooksecurefunc(wmf, "Minimize", SetSmallWorldMap)
	hooksecurefunc(wmf, "SynchronizeDisplayState", SynchronizeDisplayState)
	hooksecurefunc(wmf, "UpdateMaximizedSize", UpdateMaximizedSize)

	if PlayerMovementFrameFader and PlayerMovementFrameFader.AddDeferredFrame then
		hooksecurefunc(PlayerMovementFrameFader, "AddDeferredFrame", UpdateMapFade)
	end

	self:ClearBlackout()
	self:Apply()
end

-- Drop the full-screen black backdrop behind the map (and let clicks pass
-- through it) so the world shows through the smaller map. Irreversible without
-- a reload, so only done while the smaller map is enabled.
function WorldMap:ClearBlackout()
	if self.blackoutCleared or not cfg.smallMap then return end
	local blackout = _G.WorldMapFrame and _G.WorldMapFrame.BlackoutFrame
	if not blackout then return end

	if blackout.Blackout and blackout.Blackout.SetTexture then
		blackout.Blackout:SetTexture()
	end
	blackout:EnableMouse(false)
	self.blackoutCleared = true
end

-- Re-apply the current scale/position to an already-open map.
function WorldMap:Apply()
	local wmf = _G.WorldMapFrame
	if not wmf then return end

	if cfg.smallMap then
		if wmf:IsMaximized() then
			SetLargeWorldMap()
		else
			SetSmallWorldMap()
		end
	elseif wmf.ScrollContainer and wmf.ScrollContainer.Child then
		-- Restore Blizzard's full-size map if the option was turned off.
		wmf.ScrollContainer.Child:SetScale(1)
		if wmf.OnFrameSizeChanged then wmf:OnFrameSizeChanged() end
	end
end

function WorldMap:OnEnable()
	cfg = ns.db.worldMap
	if cfg.enable then self:Setup() end
end

function WorldMap:OnSettingChanged()
	cfg = ns.db.worldMap
	if not cfg.enable then return end

	self:Setup()
	if self.started then
		if cfg.coordinates then
			BuildCoords()
			SetCoordsShown(true)
		else
			SetCoordsShown(false)
		end
		self:ClearBlackout()
		self:Apply()
	end
end

function WorldMap:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable World Map"], L["Enable the world map enhancements (some changes apply on the next map open or after a reload)."])
	builder:Checkbox(category, self, "coordinates", L["Show Coordinates"], L["Show player and cursor coordinates along the bottom of the map."])
	builder:Checkbox(category, self, "smallMap", L["Smaller World Map"], L["Scale the windowed map down so it no longer covers the whole screen."])
	builder:Slider(category, self, "smallMapScale", L["Map Scale"], L["How large the windowed map is."], 0.5, 1, 0.05)
	builder:Checkbox(category, self, "fadeWhenMoving", L["Fade When Moving"], L["Fade the map out while your character is moving."])
	builder:Slider(category, self, "alphaWhenMoving", L["Alpha When Moving"], L["How transparent the map becomes while moving."], 0.1, 1, 0.05)
end
