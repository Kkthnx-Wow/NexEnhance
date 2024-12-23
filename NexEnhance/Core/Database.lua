-- Database management for NexEnhance addon
local AddOn, Core = ...

Core.Title = C_AddOns.GetAddOnMetadata(AddOn, "Title")
Core.Version = C_AddOns.GetAddOnMetadata(AddOn, "Version")

Core.ScreenWidth, Core.ScreenHeight = GetPhysicalScreenSize()

-- Define font settings
Core.Font = { STANDARD_TEXT_FONT, 12, "OUTLINE" }

Core.MyClass = select(2, UnitClass("player"))
Core.MyFaction = UnitFactionGroup("player")
Core.MyLevel = UnitLevel("player")
Core.MyName = UnitName("player")
Core.MyRace = select(2, UnitRace("player"))
Core.MyRealm = GetRealmName()
Core.MySex = UnitSex("player")

Core.MyFullName = Core.MyName .. "-" .. Core.MyRealm

-- Define info color
Core.InfoColor = "|CFF5bc0be"
Core.SystemColor = "|CFFFFCC66"

Core.Media = "Interface\\AddOns\\NexEnhance\\Media\\"

Core.NexEnhance = Core.Media .. "NexEnhance.tga"

Core.Logo256 = Core.Media .. "Logos\\Logo256.blp"
Core.Logo128 = Core.Media .. "Logos\\Logo128.blp"
Core.Logo64 = Core.Media .. "Logos\\Logo64.blp"

Core.Discord64 = Core.Media .. "Icons\\Discord64.blp"
Core.Patreon64 = Core.Media .. "Icons\\Patreon64.blp"
Core.PayPal64 = Core.Media .. "Icons\\PayPal64.blp"

Core.White8x8 = "Interface\\BUTTONS\\WHITE8X8.BLP"
Core.StatusBarTexture = Core.Media .. "Statusbar.tga"

Core.EasyMenu = CreateFrame("Frame", "NexEnhance_EasyMenu", UIParent, "UIDropDownMenuTemplate")

-- Initialize tables for class colors/list and item quality colors
Core.ClassList = {}
Core.ClassColors = {}
Core.QualityColors = {}

for k, v in pairs(LOCALIZED_CLASS_NAMES_MALE) do
	Core.ClassList[v] = k
end
for k, v in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do
	Core.ClassList[v] = k
end

-- Populate ClassColors table with class colors
local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
for class, value in pairs(colors) do
	Core.ClassColors[class] = {}
	Core.ClassColors[class].r = value.r
	Core.ClassColors[class].g = value.g
	Core.ClassColors[class].b = value.b
	Core.ClassColors[class].colorStr = value.colorStr
end

-- Get RGB values for player's class color
Core.r, Core.g, Core.b = Core.ClassColors[Core.MyClass].r, Core.ClassColors[Core.MyClass].g, Core.ClassColors[Core.MyClass].b

-- Convert RGB values to hexadecimal color string
Core.MyClassColor = format("|cff%02x%02x%02x", Core.r * 255, Core.g * 255, Core.b * 255)

-- Populate QualityColors table with item quality colors
local qualityColors = BAG_ITEM_QUALITY_COLORS
for index, value in pairs(qualityColors) do
	Core.QualityColors[index] = { r = value.r, g = value.g, b = value.b }
end

-- Set default colors for specific item qualities
Core.QualityColors[-1] = { r = 1, g = 1, b = 1 }
Core.QualityColors[Enum.ItemQuality.Poor] = { r = 0.61, g = 0.61, b = 0.61 }
Core.QualityColors[Enum.ItemQuality.Common] = { r = 1, g = 1, b = 1 } -- Default color

-- Register NexEnhance statusbar
local media = LibStub and LibStub("LibSharedMedia-3.0", true)
if media then
	media:Register("statusbar", "NexEnhance", Core.NexEnhance)
end
