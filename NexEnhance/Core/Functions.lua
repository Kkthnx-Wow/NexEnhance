-- Functions management for NexEnhance addon
local NexEnhance, NE_Functions = ...
local cr, cg, cb = NE_Functions.r, NE_Functions.g, NE_Functions.b

-- Frame to hide UI elements
NE_Functions.UIFrameHider = CreateFrame("Frame")
NE_Functions.UIFrameHider:Hide()

-- Movable Frame
function NE_Functions:CreateMoverFrame(parent, saved)
	local frame = parent or self
	frame:SetMovable(true)
	frame:SetUserPlaced(true)
	frame:SetClampedToScreen(true)

	self:EnableMouse(true)
	self:RegisterForDrag("LeftButton")
	self:SetScript("OnDragStart", function()
		frame:StartMoving()
	end)
	self:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		if not saved then
			return
		end
		local orig, _, tar, x, y = frame:GetPoint()
		x, y = NE_Functions:Round(x), NE_Functions:Round(y)
		NE_Functions.db.profile["tempanchor"][frame:GetName()] = { orig, "UIParent", tar, x, y }
	end)
end

function NE_Functions:RestoreMoverFrame()
	local name = self:GetName()
	if name and NE_Functions.db.profile["tempanchor"][name] then
		self:ClearAllPoints()
		self:SetPoint(unpack(NE_Functions.db.profile["tempanchor"][name]))
	end
end

do
	-- Function to shorten numerical values
	function NE_Functions.ShortValue(n)
		local prefixStyle = 1
		local abs_n = abs(n)
		local suffix, div = "", 1

		if abs_n >= 1e12 then
			suffix, div = (prefixStyle == 1 and "t" or "z"), 1e12
		elseif abs_n >= 1e9 then
			suffix, div = (prefixStyle == 1 and "b" or "y"), 1e9
		elseif abs_n >= 1e6 then
			suffix, div = (prefixStyle == 1 and "m" or "w"), 1e6
		elseif abs_n >= 1e3 then
			suffix, div = (prefixStyle == 1 and "k" or "w"), 1e3
		end

		local val = n / div
		if div > 1 and val < 10 then
			return string.format("%.1f%s", val, suffix)
		else
			return string.format("%d%s", val, suffix)
		end
	end

	function NE_Functions:Round(number, idp)
		idp = idp or 0
		local mult = 10 ^ idp
		return floor(number * mult + 0.5) / mult
	end
end

-- Color conversion functions
do
	-- Converts RGB values to a hexadecimal color string
	function NE_Functions.RGBToHex(r, g, b)
		if r then
			if type(r) == "table" then
				if r.r then
					r, g, b = r.r, r.g, r.b
				else
					r, g, b = unpack(r)
				end
			end
			return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
		end
	end

	-- Returns the class color for a given class
	function NE_Functions.ClassColor(class)
		local color = NE_Functions.ClassColors[class]
		if not color then
			return 1, 1, 1
		end
		return color.r, color.g, color.b
	end

	-- Returns the color for a given unit
	function NE_Functions.UnitColor(unit)
		local r, g, b = 1, 1, 1
		if UnitIsPlayer(unit) then
			local class = select(2, UnitClass(unit))
			if class then
				r, g, b = NE_Functions.ClassColor(class)
			end
		elseif UnitIsTapDenied(unit) then
			r, g, b = 0.6, 0.6, 0.6
		else
			local reaction = UnitReaction(unit, "player")
			if reaction then
				local color = FACTION_BAR_COLORS[reaction]
				r, g, b = color.r, color.g, color.b
			end
		end
		return r, g, b
	end
end

-- Function to disable and hide UI elements
function NE_Functions.DisableUIElement(element)
	if element.UnregisterAllEvents then
		element:UnregisterAllEvents()
		element:SetParent(NE_Functions.UIFrameHider)
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
function NE_Functions.RemoveTextures(element, removeCompletely)
	local elementName = element.GetName and element:GetName()

	for _, textureName in pairs(BlizzardTextures) do
		local textureElement = element[textureName] or (elementName and _G[elementName .. textureName])
		if textureElement then
			NE_Functions.RemoveTextures(textureElement, removeCompletely)
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
	local itemLevelString = "^" .. gsub(ITEM_LEVEL, "%%d", "")
	local enchantString = gsub(ENCHANTED_TOOLTIP_LINE, "%%s", "(.+)")
	local isUnknownString = {
		[TRANSMOGRIFY_TOOLTIP_APPEARANCE_UNKNOWN] = true,
		[TRANSMOGRIFY_TOOLTIP_ITEM_UNKNOWN_APPEARANCE_KNOWN] = true,
	}

	local slotData = { gems = {}, gemsColor = {} }
	function NE_Functions.GetItemLevel(link, arg1, arg2, fullScan)
		if fullScan then
			local data = C_TooltipInfo.GetInventoryItem(arg1, arg2)
			if not data then
				return
			end

			wipe(slotData.gems)
			wipe(slotData.gemsColor)
			slotData.iLvl = nil
			slotData.enchantText = nil

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
				elseif data.id == 158075 then -- heart of azeroth
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

	local pendingNPCs, nameCache, callbacks = {}, {}, {}
	local loadingStr = "..."
	local pendingFrame = CreateFrame("Frame")
	pendingFrame:Hide()
	pendingFrame:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = (self.elapsed or 0) + elapsed
		if self.elapsed > 1 then
			if next(pendingNPCs) then
				for npcID, count in pairs(pendingNPCs) do
					if count > 2 then
						nameCache[npcID] = UNKNOWN
						if callbacks[npcID] then
							callbacks[npcID](UNKNOWN)
						end
						pendingNPCs[npcID] = nil
					else
						local name = NE_Functions.GetNPCName(npcID, callbacks[npcID])
						if name and name ~= loadingStr then
							pendingNPCs[npcID] = nil
						else
							pendingNPCs[npcID] = pendingNPCs[npcID] + 1
						end
					end
				end
			else
				self:Hide()
			end

			self.elapsed = 0
		end
	end)

	function NE_Functions.GetNPCName(npcID, callback)
		local name = nameCache[npcID]
		if not name then
			name = loadingStr
			local data = C_TooltipInfo.GetHyperlink(format("unit:Creature-0-0-0-0-%d", npcID))
			local lineData = data and data.lines
			if lineData then
				name = lineData[1] and lineData[1].leftText
			end
			if name == loadingStr then
				if not pendingNPCs[npcID] then
					pendingNPCs[npcID] = 1
					pendingFrame:Show()
				end
			else
				nameCache[npcID] = name
			end
		end
		if callback then
			callback(name)
			callbacks[npcID] = callback
		end

		return name
	end

	function NE_Functions.IsUnknownTransmog(bagID, slotID)
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

do
	-- Sets font size for a font string
	function NE_Functions:SetFontSize(fontString, size)
		fontString:SetFont(NE_Functions.Font[1], size, NE_Functions.Font[3])
	end

	-- Creates a font string with specified properties
	function NE_Functions:CreateFontString(size, text, color, style, anchor, x, y)
		local FontString = self:CreateFontString(nil, "OVERLAY")
		NE_Functions:SetFontSize(FontString, size)

		style = style or ""

		if style == "OUTLINE" then
			FontString:SetFont(NE_Functions.Font[1], size, style)
			FontString:SetShadowOffset(0, 0)
		else
			FontString:SetFont(NE_Functions.Font[1], size, "")
			FontString:SetShadowOffset(1, -0.5)
		end

		FontString:SetText(text)
		FontString:SetWordWrap(false)

		if type(color) == "boolean" and color then
			FontString:SetTextColor(cr, cg, cb)
		elseif color == "system" then
			FontString:SetTextColor(1, 0.8, 0)
		end

		if anchor and x and y then
			FontString:SetPoint(anchor, x, y)
		else
			FontString:SetPoint("CENTER", 1, 0)
		end

		return FontString
	end
end

do
	-- function NE_Functions:GetMoneyString(amount)
	-- 	local coppername = "|cffeda55fc|r"
	-- 	local goldname = "|cffffd700g|r"
	-- 	local silvername = "|cffc7c7cfs|r"

	-- 	local value = math.abs(amount)
	-- 	local gold = math.floor(value / 10000)
	-- 	local silver = math.floor(mod(value / 100, 100))
	-- 	local copper = math.floor(mod(value, 100))

	-- 	if gold > 0 then
	-- 		return string.format("%s%s %02d%s %02d%s", BreakUpLargeNumbers(gold), goldname, silver, silvername, copper, coppername)
	-- 	elseif silver > 0 then
	-- 		return string.format("%d%s %02d%s", silver, silvername, copper, coppername)
	-- 	else
	-- 		return string.format("%d%s", copper, coppername)
	-- 	end
	-- end

	function NE_Functions:GetMoneyString(money, full)
		if money >= 1e6 and not full then
			return BreakUpLargeNumbers(format("%d", money / 1e4)) .. GOLD_AMOUNT_SYMBOL
		else
			if money > 0 then
				local moneyString = ""
				local gold, silver, copper = floor(money / 1e4), floor(money / 100) % 100, money % 100
				if gold > 0 then
					moneyString = " " .. gold .. GOLD_AMOUNT_SYMBOL
				end
				if silver > 0 then
					moneyString = moneyString .. " " .. silver .. SILVER_AMOUNT_SYMBOL
				end
				if copper > 0 then
					moneyString = moneyString .. " " .. copper .. COPPER_AMOUNT_SYMBOL
				end
				return moneyString
			else
				return " 0" .. COPPER_AMOUNT_SYMBOL
			end
		end
	end
end
