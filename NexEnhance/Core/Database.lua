-- Database management for NexEnhance addon
local NexEnhance, NE_Database = ...

NE_Database.ScreenWidth, NE_Database.ScreenHeight = GetPhysicalScreenSize()

-- Define font settings
NE_Database.Font = { STANDARD_TEXT_FONT, 12, "OUTLINE" }

NE_Database.Name = UnitName("player") -- Get player's name
NE_Database.Class = select(2, UnitClass("player")) -- Get player's class

-- Define info color
NE_Database.InfoColor = "|CFF5bc0be"
NE_Database.SystemColor = "|CFFFFCC66"

-- Initialize tables for class colors and item quality colors
NE_Database.ClassColors = {}
NE_Database.QualityColors = {}

-- Populate ClassColors table with class colors
local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
for class, value in pairs(colors) do
	NE_Database.ClassColors[class] = {}
	NE_Database.ClassColors[class].r = value.r
	NE_Database.ClassColors[class].g = value.g
	NE_Database.ClassColors[class].b = value.b
	NE_Database.ClassColors[class].colorStr = value.colorStr
end

-- Get RGB values for player's class color
NE_Database.r, NE_Database.g, NE_Database.b = NE_Database.ClassColors[NE_Database.Class].r, NE_Database.ClassColors[NE_Database.Class].g, NE_Database.ClassColors[NE_Database.Class].b

-- Convert RGB values to hexadecimal color string
NE_Database.MyColor = format("|cff%02x%02x%02x", NE_Database.r * 255, NE_Database.g * 255, NE_Database.b * 255)

-- Populate QualityColors table with item quality colors
local qualityColors = BAG_ITEM_QUALITY_COLORS
for index, value in pairs(qualityColors) do
	NE_Database.QualityColors[index] = { r = value.r, g = value.g, b = value.b }
end

-- Set default colors for specific item qualities
NE_Database.QualityColors[-1] = { r = 1, g = 1, b = 1 }
NE_Database.QualityColors[Enum.ItemQuality.Poor] = { r = 0.61, g = 0.61, b = 0.61 }
NE_Database.QualityColors[Enum.ItemQuality.Common] = { r = 1, g = 1, b = 1 } -- Default color
