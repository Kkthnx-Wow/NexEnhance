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
	-- Semantic tooltip text roles. Single source of truth so every GameTooltip
	-- the addon builds shares one palette: gold section headers, light-blue
	-- key/label text, and white values. Change these here, not per-module.
	header = { 1.00, 0.82, 0.00 }, -- section titles ("Latency", "Saved Raid(s):")
	label = { 0.60, 0.80, 1.00 }, -- left-hand keys / instructions
	value = { 1.00, 1.00, 1.00 }, -- right-hand values
}

-- Pre-built brand colour escape sequence for chat output (built once).
C.BrandHex = ("ff%02x%02x%02x"):format(C.Colors.brand[1] * 255, C.Colors.brand[2] * 255, C.Colors.brand[3] * 255)
C.HeaderHex = ("ff%02x%02x%02x"):format(C.Colors.header[1] * 255, C.Colors.header[2] * 255, C.Colors.header[3] * 255)

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
		-- Minimap region reskins (calendar button + instance-difficulty flags).
		calendar = "Interface\\AddOns\\NexEnhance\\Media\\Minimap\\Calendar",
		flag = "Interface\\AddOns\\NexEnhance\\Media\\Minimap\\Flag",
		-- Soft white donut for Cursor Ring (class-tinted at runtime).
		cursorRing = "Interface\\AddOns\\NexEnhance\\Media\\Cursor\\CursorRing",
		-- Soft filled glow for Cursor Trail dots (class/custom/rainbow tint).
		cursorTrailDot = "Interface\\AddOns\\NexEnhance\\Media\\Cursor\\CursorTrailDot",
	},
	-- Chat emoji textures — Media/Emojis/*.tga (Unicode-style names, spaces → _).
	Emojis = {
		Angry_Face = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Angry_Face",
		Broken_Heart = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Broken_Heart",
		Confused_Face = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Confused_Face",
		Crying_Face = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Crying_Face",
		Death_knight = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Death_knight",
		Demon_hunter = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Demon_hunter",
		Druid = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Druid",
		Evoker = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Evoker",
		Expressionless_Face = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Expressionless_Face",
		Eyes = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Eyes",
		Face_Blowing_a_Kiss = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Face_Blowing_a_Kiss",
		Face_Savoring_Food = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Face_Savoring_Food",
		Face_with_Open_Mouth = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Face_with_Open_Mouth",
		Face_with_Symbols_on_Mouth = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Face_with_Symbols_on_Mouth",
		Face_with_Tears_of_Joy = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Face_with_Tears_of_Joy",
		Face_with_Tongue = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Face_with_Tongue",
		Grinning_Face_with_Big_Eyes = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Grinning_Face_with_Big_Eyes",
		Grinning_Squinting_Face = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Grinning_Squinting_Face",
		Hunter = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Hunter",
		Kissing_Face = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Kissing_Face",
		Mage = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Mage",
		Monk = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Monk",
		OK_Hand = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\OK_Hand",
		Paladin = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Paladin",
		Priest = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Priest",
		Red_Heart = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Red_Heart",
		Relieved_Face = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Relieved_Face",
		Rogue = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Rogue",
		Shaman = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Shaman",
		Slightly_Frowning_Face = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Slightly_Frowning_Face",
		Slightly_Smiling_Face = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Slightly_Smiling_Face",
		Smiling_Face_with_Heart_Eyes = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Smiling_Face_with_Heart_Eyes",
		Smiling_Face_with_Smiling_Eyes = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Smiling_Face_with_Smiling_Eyes",
		Smiling_Face_with_Sweat = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Smiling_Face_with_Sweat",
		Sparkles = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Sparkles",
		Thumbs_Down = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Thumbs_Down",
		Thumbs_Up = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Thumbs_Up",
		Warlock = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Warlock",
		Warning = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Warning",
		Warrior = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Warrior",
		Waving_Hand = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Waving_Hand",
		Winking_Face = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Winking_Face",
		Winking_Face_with_Tongue = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Winking_Face_with_Tongue",
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

-- ---------------------------------------------------------------------------
-- Backdrop presets
--   Shared SetBackdrop tables for the standalone windows and input panels
--   (Changelog, Credits, Profiles, Install, the chat edit box and copy frame).
--   These use Blizzard's stock tooltip background/border art and are kept here
--   as one source of truth so every panel frames the same way. SetBackdrop
--   copies the values into the C++ backdrop, so sharing a single read-only table
--   across frames is safe.
-- ---------------------------------------------------------------------------
C.Backdrops = {
	window = {
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\AddOns\\NexEnhance\\Media\\Border\\NexBorder",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	},
}
