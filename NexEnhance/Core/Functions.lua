-- Functions management for NexEnhance addon
local _, Core = ...
local cr, cg, cb = Core.r, Core.g, Core.b

local debugMode = true

-- Debugging function
function Core:DebugPrint(...)
	if debugMode then
		local message = string.format(...)
		Core.Print("|cffFF4500[NexEnhance Debug]:|r", message)
	end
end

-- Movable Frame
do
	function Core:CreateMoverFrame(parent, saved)
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
			x, y = Core:Round(x), Core:Round(y)
			Core.db.profile["tempanchor"][frame:GetName()] = { orig, "UIParent", tar, x, y }
		end)
	end

	function Core:RestoreMoverFrame()
		local name = self:GetName()
		if name and Core.db.profile["tempanchor"][name] then
			self:ClearAllPoints()
			self:SetPoint(unpack(Core.db.profile["tempanchor"][name]))
		end
	end
end

do
	-- Function to update the prefix style
	function Core:UpdateNumberPrefixStyle()
		return Core.db.profile.general.numberPrefixStyle
	end

	-- Function to force update prefix style and use it immediately
	function Core:ForceUpdatePrefixStyle()
		self:UpdateNumberPrefixStyle() -- Update prefixStyle immediately
	end

	-- Function to shorten numerical values
	function Core.ShortValue(n)
		local prefixStyle = Core.db.profile.general.numberPrefixStyle -- Get the current prefix style

		if prefixStyle == "STANDARD" then
			if n >= 1e12 then
				return format("%.2ft", n / 1e12)
			elseif n >= 1e9 then
				return format("%.2fb", n / 1e9)
			elseif n >= 1e6 then
				return format("%.2fm", n / 1e6)
			elseif n >= 1e3 then
				return format("%.1fk", n / 1e3)
			else
				return format("%.0f", n)
			end
		elseif prefixStyle == "ASIAN" then
			if n >= 1e12 then
				return format("%.2f" .. "z", n / 1e12) -- Need local for z,y,w
			elseif n >= 1e8 then
				return format("%.2f" .. "y", n / 1e8) -- Need local for z,y,w
			elseif n >= 1e4 then
				return format("%.1f" .. "w", n / 1e4) -- Need local for z,y,w
			else
				return format("%.0f", n)
			end
		else
			return format("%.0f", n)
		end
	end

	function Core:Round(number, idp)
		idp = idp or 0
		local mult = 10 ^ idp
		return floor(number * mult + 0.5) / mult
	end
end

-- Color conversion functions
do
	-- Converts RGB values to a hexadecimal color string
	function Core.RGBToHex(r, g, b)
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
	function Core.ClassColor(class)
		local color = Core.ClassColors[class]
		if not color then
			return 1, 1, 1
		end
		return color.r, color.g, color.b
	end

	-- Returns the color for a given unit
	function Core.UnitColor(unit)
		local r, g, b = 1, 1, 1
		if UnitIsPlayer(unit) then
			local class = select(2, UnitClass(unit))
			if class then
				r, g, b = Core.ClassColor(class)
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

	-- Helper function to calculate the color gradient and percentage
	local function calculateColorGradient(a, b, ...)
		if a <= 0 or b == 0 then
			return nil, ...
		elseif a >= b then
			return nil, select(-3, ...)
		end

		local numSegments = select("#", ...) / 3
		local segment, relperc = math.modf((a / b) * (numSegments - 1))
		return relperc, select((segment * 3) + 1, ...)
	end

	-- Function to compute the RGB color gradient based on the percentage
	function Core:RGBColorGradient(a, b, ...)
		local relperc, r1, g1, b1, r2, g2, b2 = calculateColorGradient(a, b, ...)
		if relperc then
			return r1 + (r2 - r1) * relperc, g1 + (g2 - g1) * relperc, b1 + (b2 - b1) * relperc
		else
			return r1, g1, b1
		end
	end
end

-- Kill regions
do
	function Core:Dummy()
		return
	end

	Core.HiddenFrame = CreateFrame("Frame")
	Core.HiddenFrame:Hide()

	function Core:HideObject()
		if self.UnregisterAllEvents then
			self:UnregisterAllEvents()
			self:SetParent(Core.HiddenFrame)
		else
			self.Show = self.Hide
		end
		self:Hide()
	end

	function Core:HideOption()
		self:SetAlpha(0)
		self:SetScale(0.0001)
	end

	local blizzTextures = {
		"Inset",
		"inset",
		"InsetFrame",
		"LeftInset",
		"RightInset",
		"NineSlice",
		"BG",
		"Bg",
		"border",
		"Border",
		"Background",
		"BorderFrame",
		"bottomInset",
		"BottomInset",
		"bgLeft",
		"bgRight",
		"FilligreeOverlay",
		"PortraitOverlay",
		"ArtOverlayFrame",
		"Portrait",
		"portrait",
		"ScrollFrameBorder",
		"ScrollUpBorder",
		"ScrollDownBorder",
	}
	function Core:StripTextures(kill)
		local frameName = self.GetName and self:GetName()
		for _, texture in pairs(blizzTextures) do
			local blizzFrame = self[texture] or (frameName and _G[frameName .. texture])
			if blizzFrame then
				Core.StripTextures(blizzFrame, kill)
			end
		end

		if self.GetNumRegions then
			for i = 1, self:GetNumRegions() do
				local region = select(i, self:GetRegions())
				if region and region.IsObjectType and region:IsObjectType("Texture") then
					if kill and type(kill) == "boolean" then
						Core.HideObject(region)
					elseif tonumber(kill) then
						if kill == 0 then
							region:SetAlpha(0)
						elseif i ~= kill then
							region:SetTexture("")
							region:SetAtlas("")
						end
					else
						region:SetTexture("")
						region:SetAtlas("")
					end
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
	function Core.GetItemLevel(link, arg1, arg2, fullScan)
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
						local name = Core.GetNPCName(npcID, callbacks[npcID])
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

	function Core.GetNPCName(npcID, callback)
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

	function Core.IsUnknownTransmog(bagID, slotID)
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
	function Core:SetFontSize(fontString, size)
		fontString:SetFont(Core.Font[1], size, Core.Font[3])
	end

	-- Creates a font string with specified properties
	function Core:CreateFontString(size, text, color, style, anchor, x, y)
		local FontString = self:CreateFontString(nil, "OVERLAY")
		Core:SetFontSize(FontString, size)

		style = style or ""

		if style == "OUTLINE" then
			FontString:SetFont(Core.Font[1], size, style)
			FontString:SetShadowOffset(0, 0)
		else
			FontString:SetFont(Core.Font[1], size, "")
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
	function Core:GetMoneyString(money, full)
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

do
	function Core:CreateBackdropFrame(offsetA, offsetB, offsetC, offsetD)
		local targetFrame = self

		-- Use default offsets if none provided
		offsetA = offsetA or 0
		offsetB = offsetB or 0
		offsetC = offsetC or 0
		offsetD = offsetD or 0

		-- Adjust targetFrame if the provided object is a texture
		if targetFrame:IsObjectType("Texture") then
			targetFrame = targetFrame:GetParent()
		end

		-- Ensure targetFrame is valid
		if not targetFrame then
			return nil
		end

		-- Check if backdrop frame already exists
		if targetFrame.backdropFrame then
			return targetFrame.backdropFrame
		end

		-- Get the frame level, defaulting to 0 if necessary
		local targetFrameLevel = targetFrame:GetFrameLevel() + 1 or 0
		local backdropFrameLevel = (targetFrameLevel > 0) and (targetFrameLevel - 1) or 0

		-- Create the backdrop frame
		local backdropFrame = CreateFrame("Frame", nil, targetFrame, "TooltipBackdropTemplate")
		backdropFrame:SetPoint("TOPLEFT", targetFrame, "TOPLEFT", -offsetA, offsetB)
		backdropFrame:SetPoint("BOTTOMRIGHT", targetFrame, "BOTTOMRIGHT", offsetC, -offsetD)
		backdropFrame:SetFrameLevel(backdropFrameLevel)
		backdropFrame:SetFrameStrata(targetFrame:GetFrameStrata())

		-- Store reference to the backdrop frame
		targetFrame.backdropFrame = backdropFrame

		return backdropFrame
	end

	function Core:CreateAtlasBackdrop(anchor, borderSize, parent, atlas)
		local parentFrame = parent or anchor
		local size = borderSize or 16

		-- Check if backdrop frame already exists
		if parentFrame.backdropFrame then
			return parentFrame.backdropFrame
		end

		-- Determine the frame level
		local frameLevel = parentFrame:GetFrameLevel()
		local backdropFrameLevel = (frameLevel > 0) and (frameLevel - 1) or 0

		-- Create the backdrop frame
		local backdropFrame = CreateFrame("Frame", nil, parentFrame, "BackdropTemplate")
		backdropFrame:SetFrameLevel(backdropFrameLevel)
		backdropFrame:SetPoint("TOPLEFT", anchor, "TOPLEFT", -size, size)
		backdropFrame:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", size, -size)

		-- Create and set texture (example using a default atlas)
		backdropFrame.texture = backdropFrame:CreateTexture(nil, "BACKGROUND")
		backdropFrame.texture:SetAllPoints(backdropFrame)
		backdropFrame.texture:SetAtlas(atlas, true)

		-- Store reference to the backdrop frame in the parent frame
		parentFrame.backdropFrame = backdropFrame

		return backdropFrame
	end
end
