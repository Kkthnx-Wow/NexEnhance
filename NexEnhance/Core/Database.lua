-- Database management for NexEnhance addon
local _, Core = ...

Core.ScreenWidth, Core.ScreenHeight = GetPhysicalScreenSize()

-- Define font settings
Core.Font = { STANDARD_TEXT_FONT, 12, "OUTLINE" }

Core.Name = UnitName("player") -- Get player's name
Core.Class = select(2, UnitClass("player")) -- Get player's class

-- Define info color
Core.InfoColor = "|CFF5bc0be"
Core.SystemColor = "|CFFFFCC66"

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
Core.r, Core.g, Core.b = Core.ClassColors[Core.Class].r, Core.ClassColors[Core.Class].g, Core.ClassColors[Core.Class].b

-- Convert RGB values to hexadecimal color string
Core.MyColor = format("|cff%02x%02x%02x", Core.r * 255, Core.g * 255, Core.b * 255)

-- Populate QualityColors table with item quality colors
local qualityColors = BAG_ITEM_QUALITY_COLORS
for index, value in pairs(qualityColors) do
	Core.QualityColors[index] = { r = value.r, g = value.g, b = value.b }
end

-- Set default colors for specific item qualities
Core.QualityColors[-1] = { r = 1, g = 1, b = 1 }
Core.QualityColors[Enum.ItemQuality.Poor] = { r = 0.61, g = 0.61, b = 0.61 }
Core.QualityColors[Enum.ItemQuality.Common] = { r = 1, g = 1, b = 1 } -- Default color
