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
	},
	-- Chat emoji textures bundled under Media/Emojis/*.tga.
	Emojis = {
		Angry = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Angry",
		Blush = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Blush",
		BrokenHeart = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\BrokenHeart",
		CallMe = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\CallMe",
		Cry = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Cry",
		Facepalm = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Facepalm",
		Grin = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Grin",
		Heart = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Heart",
		HeartEyes = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\HeartEyes",
		Joy = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Joy",
		Kappa = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Kappa",
		Meaw = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Meaw",
		MiddleFinger = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\MiddleFinger",
		Murloc = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Murloc",
		OkHand = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\OkHand",
		OpenMouth = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\OpenMouth",
		Poop = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Poop",
		Rage = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Rage",
		SadKitty = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\SadKitty",
		Scream = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Scream",
		ScreamCat = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\ScreamCat",
		SemiColon = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\SemiColon",
		SlightFrown = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\SlightFrown",
		SlightSmile = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\SlightSmile",
		Smile = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Smile",
		Smirk = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Smirk",
		Sob = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Sob",
		StuckOutTongue = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\StuckOutTongue",
		StuckOutTongueClosedEyes = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\StuckOutTongueClosedEyes",
		Sunglasses = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Sunglasses",
		Thinking = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Thinking",
		ThumbsUp = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\ThumbsUp",
		Wink = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\Wink",
		ZZZ = "Interface\\AddOns\\NexEnhance\\Media\\Emojis\\ZZZ",
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
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	},
}
