--[[
	NexEnhance - Constants
	-------------------------------------------------------------------------
	Static, read-mostly data: client/player info, colour palette and media
	paths. Anything looked up once at login and reused everywhere lives here
	so modules never re-query the API for values that cannot change mid-
	session.
--]]

local _, ns = ...
local C = ns.C

-- Localised API (top-of-file caching, per best-practice reports).
local UnitName = UnitName
local UnitClass = UnitClass
local UnitRace = UnitRace
local UnitSex = UnitSex
local UnitLevel = UnitLevel
local UnitFactionGroup = UnitFactionGroup
local GetRealmName = GetRealmName
local GetLocale = GetLocale
local GetBuildInfo = GetBuildInfo

-- ---------------------------------------------------------------------------
-- Client information
-- ---------------------------------------------------------------------------
do
	local version, build, _, interface = GetBuildInfo()
	C.Client = {
		version = version, -- e.g. "12.0.5"
		build = build, -- e.g. "61491"
		interface = interface, -- e.g. 120005
		locale = GetLocale(), -- e.g. "enUS"
		isRetail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE,
	}
end

-- ---------------------------------------------------------------------------
-- Player information (constant for the session; name/realm never change while
-- logged in, and class/race only change across logins).
-- ---------------------------------------------------------------------------
do
	local className, classFile, classID = UnitClass("player")
	local raceName, raceFile = UnitRace("player")

	C.Player = {
		name = UnitName("player"),
		realm = GetRealmName(),
		level = UnitLevel("player"),
		class = classFile, -- "MAGE", "WARRIOR", ...
		className = className, -- localised
		classID = classID,
		race = raceFile,
		raceName = raceName,
		sex = UnitSex("player"), -- 2 = male, 3 = female
		faction = UnitFactionGroup("player"), -- "Alliance" / "Horde" / "Neutral"
	}

	-- "Name - Realm" key, handy for per-character settings and tables.
	C.Player.key = C.Player.name .. " - " .. C.Player.realm
end

-- ---------------------------------------------------------------------------
-- Colours
--   `C.Colors` is a palette of {r, g, b} tables. `C.ClassColor` is the local
--   player's class colour. RAID_CLASS_COLORS is the canonical source.
-- ---------------------------------------------------------------------------
local classColor = (_G["CUSTOM_CLASS_COLORS"] or RAID_CLASS_COLORS)[C.Player.class]

C.ClassColor = { classColor.r, classColor.g, classColor.b }

C.Colors = {
	red = { 0.90, 0.30, 0.30 },
	green = { 0.40, 0.78, 0.40 },
	yellow = { 1.00, 0.82, 0.00 },
	orange = { 0.95, 0.55, 0.20 },
	gray = { 0.55, 0.55, 0.55 },
	white = { 1.00, 1.00, 1.00 },
	-- Brand colour used for the addon prefix and headers.
	brand = { 0.36, 0.55, 0.81 }, -- #5C8BCF
	class = C.ClassColor,
}

-- Pre-built brand colour escape sequence for chat output (built once).
C.BrandHex = ("ff%02x%02x%02x"):format(C.Colors.brand[1] * 255, C.Colors.brand[2] * 255, C.Colors.brand[3] * 255)

-- ---------------------------------------------------------------------------
-- Media
--   Default to Blizzard's built-in assets so the addon works with zero extra
--   files shipped. Replace these paths if you add custom media later.
-- ---------------------------------------------------------------------------
C.Media = {
	Textures = {
		blank = "Interface\\Buttons\\WHITE8x8",
		statusbar = "Interface\\TargetingFrame\\UI-StatusBar",
		-- Branded logo, shipped at three power-of-two sizes. `logo` is the
		-- high-res default; pick a size-specific path for small UI elements.
		logo = "Interface\\AddOns\\NexEnhance\\Media\\Logos\\Logo256",
		logo64 = "Interface\\AddOns\\NexEnhance\\Media\\Logos\\Logo64",
		logo128 = "Interface\\AddOns\\NexEnhance\\Media\\Logos\\Logo128",
		logo256 = "Interface\\AddOns\\NexEnhance\\Media\\Logos\\Logo256",
	},
	Fonts = {
		normal = STANDARD_TEXT_FONT,
		number = "Fonts\\ARIALN.TTF",
	},
}

-- ---------------------------------------------------------------------------
-- Skinning constants
--   Shared values used by the skin/tooltip modules: a 1px pixel offset, the
--   default icon-zoom tex-coords, an "info" colour escape for appended data,
--   and a direct handle to Blizzard's item-quality colour table.
-- ---------------------------------------------------------------------------
C.Mult = 1
C.TexCoord = { 0.08, 0.92, 0.08, 0.92 }
C.InfoColor = "|c" .. C.BrandHex
C.QualityColors = _G["ITEM_QUALITY_COLORS"]
