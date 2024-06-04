local _, addon = ...
local cr, cg, cb = addon.r, addon.g, addon.b

addon.Font = { STANDARD_TEXT_FONT, 12, "OUTLINE" }
addon.Class = select(2, UnitClass("player"))

-- Frame to hide UI elements
addon.UIFrameHider = CreateFrame("Frame")
addon.UIFrameHider:Hide()

-- Function to disable and hide UI elements
function addon.DisableUIElement(element)
	if element.UnregisterAllEvents then
		element:UnregisterAllEvents()
		element:SetParent(addon.UIFrameHider)
	else
		element.Show = element.Hide
	end
	element:Hide()
end

-- List of common Blizzard UI textures to be removed
local BlizzardTextures = {
	"Inset",
	"inset",
	"InsetFrame",
	"LeftInset",
	"RightInset",
	"NineSlice",
	"BG",
	"border",
	"Border",
	"Background",
	"BorderFrame",
	"bottomInset",
	"BottomInset",
	"bgLeft",
	"bgRight",
	"Portrait",
	"portrait",
	"ScrollFrameBorder",
	"ScrollUpBorder",
	"ScrollDownBorder",
}

-- Function to remove textures from UI elements
function addon.RemoveTextures(element, removeCompletely)
	local elementName = element.GetName and element:GetName()

	for _, textureName in pairs(BlizzardTextures) do
		local textureElement = element[textureName] or (elementName and _G[elementName .. textureName])
		if textureElement then
			addon.RemoveTextures(textureElement, removeCompletely)
		end
	end

	if element.GetNumRegions then
		for i = 1, element:GetNumRegions() do
			local region = select(i, element:GetRegions())
			if region and region.IsObjectType and region:IsObjectType("Texture") then
				if removeCompletely and type(removeCompletely) == "boolean" then
					region:Hide()
				elseif tonumber(removeCompletely) then
					if removeCompletely == 0 then
						region:SetAlpha(0)
					elseif i ~= removeCompletely then
						region:SetTexture(nil)
					end
				else
					region:SetTexture(nil)
				end
			end
		end
	end
end

-- Item Level Functions
do
	local iLvlDB = {}
	local enchantString = string.gsub(ENCHANTED_TOOLTIP_LINE, "%%s", "(.+)")
	local itemLevelString = "^" .. string.gsub(ITEM_LEVEL, "%%d", "")
	local isUnknownString = {
		[TRANSMOGRIFY_TOOLTIP_APPEARANCE_UNKNOWN] = true,
		[TRANSMOGRIFY_TOOLTIP_ITEM_UNKNOWN_APPEARANCE_KNOWN] = true,
	}

	local slotData = { gems = {}, gemsColor = {} }
	function addon.GetItemLevel(link, arg1, arg2, fullScan)
		if fullScan then
			local data = C_TooltipInfo.GetInventoryItem(arg1, arg2)
			if not data then
				return
			end

			table.wipe(slotData.gems)
			table.wipe(slotData.gemsColor)
			slotData.iLvl = nil
			slotData.enchantText = nil

			local isHoA = data.id == 158075
			local num = 0
			for i = 2, #data.lines do
				local lineData = data.lines[i]
				if not slotData.iLvl then
					local text = lineData.leftText
					local found = text and strfind(text, itemLevelString)
					if found then
						local level = strmatch(text, "(%d+)%)?$")
						slotData.iLvl = tonumber(level) or 0
					end
				elseif isHoA then
					if lineData.essenceIcon then
						num = num + 1
						slotData.gems[num] = lineData.essenceIcon
						slotData.gemsColor[num] = lineData.leftColor
					end
				else
					if lineData.enchantID then
						slotData.enchantText = strmatch(lineData.leftText, enchantString)
					elseif lineData.gemIcon then
						num = num + 1
						slotData.gems[num] = lineData.gemIcon
					elseif lineData.socketType then
						num = num + 1
						slotData.gems[num] = format("Interface\\ItemSocketingFrame\\UI-EmptySocket-%s", lineData.socketType)
					end
				end
			end

			return slotData
		else
			if iLvlDB[link] then
				return iLvlDB[link]
			end

			local data
			if arg1 and type(arg1) == "string" then
				data = C_TooltipInfo.GetInventoryItem(arg1, arg2)
			elseif arg1 and type(arg1) == "number" then
				data = C_TooltipInfo.GetBagItem(arg1, arg2)
			else
				data = C_TooltipInfo.GetHyperlink(link, nil, nil, true)
			end
			if not data then
				return
			end

			for i = 2, 5 do
				local lineData = data.lines[i]
				if not lineData then
					break
				end
				local text = lineData.leftText
				local found = text and strfind(text, itemLevelString)
				if found then
					local level = strmatch(text, "(%d+)%)?$")
					iLvlDB[link] = tonumber(level)
					break
				end
			end
			return iLvlDB[link]
		end
	end

	function addon.IsUnknownTransmog(bagID, slotID)
		local data = C_TooltipInfo.GetBagItem(bagID, slotID)
		local lineData = data and data.lines
		if not lineData then
			return
		end

		for i = #lineData, 1, -1 do
			local line = lineData[i]
			if line.price then
				return false
			end
			return line.leftText and isUnknownString[line.leftText]
		end
	end
end

addon.ClassColors = {}
addon.QualityColors = {}

local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
for class, value in pairs(colors) do
	addon.ClassColors[class] = {}
	addon.ClassColors[class].r = value.r
	addon.ClassColors[class].g = value.g
	addon.ClassColors[class].b = value.b
	addon.ClassColors[class].colorStr = value.colorStr
end
addon.r, addon.g, addon.b = addon.ClassColors[addon.Class].r, addon.ClassColors[addon.Class].g, addon.ClassColors[addon.Class].b
addon.MyColor = format("|cff%02x%02x%02x", addon.r * 255, addon.g * 255, addon.b * 255)

-- Populate the QualityColors table with the colors of each item quality
local qualityColors = BAG_ITEM_QUALITY_COLORS
for index, value in pairs(qualityColors) do
	addon.QualityColors[index] = { r = value.r, g = value.g, b = value.b }
end
addon.QualityColors[-1] = { r = 1, g = 1, b = 1 }
addon.QualityColors[Enum.ItemQuality.Poor] = { r = 0.61, g = 0.61, b = 0.61 }
addon.QualityColors[Enum.ItemQuality.Common] = { r = 1, g = 1, b = 1 } -- This is the default color, but it's included here for completeness.

do
	-- Fontstring
	function addon:SetFontSize(size)
		self:SetFont(addon.Font[1], size, addon.Font[3])
	end

	function addon:CreateFontString(size, text, color, style, anchor, x, y)
		local fs = self:CreateFontString(nil, "OVERLAY")
		addon.SetFontSize(fs, size)

		-- Default style is an empty string if not provided
		style = style or ""

		-- Set font and shadow based on style
		if style == "OUTLINE" then
			fs:SetFont(addon.Font[1], size, style)
			fs:SetShadowOffset(0, 0)
		else
			fs:SetFont(addon.Font[1], size, "")
			fs:SetShadowOffset(1, -0.5)
		end

		fs:SetText(text)
		fs:SetWordWrap(false)

		-- Set color
		if type(color) == "boolean" and color then
			-- Placeholder for setting text color when color is a boolean
			fs:SetTextColor(cr, cg, cb)
		elseif color == "system" then
			fs:SetTextColor(1, 0.8, 0)
		end

		-- Set anchor point
		if anchor and x and y then
			fs:SetPoint(anchor, x, y)
		else
			fs:SetPoint("CENTER", 1, 0)
		end

		return fs
	end
end
