local AddOnName, Module = ...

-- Imports and constants
local string_format = string.format
local math_floor = math.floor
local day, hour, minute = 86400, 3600, 60
local DebuffTypeColor = DebuffTypeColor -- Ensure DebuffTypeColor is defined

-- Function to get formatted time
local function GetFormattedTime(s)
	if s >= day then
		return string_format("%d%sd", s / day, Module.MyClassColor), s % day
	elseif s >= 2 * hour then
		return string_format("%d%sh", s / hour, Module.MyClassColor), s % hour
	elseif s >= 10 * minute then
		return string_format("%d%sm", s / minute, Module.MyClassColor), s % minute
	elseif s >= minute then
		return string_format("%d:%.2d", s / minute, s % minute), s - math_floor(s)
	elseif s > 10 then
		return string_format("|cffffff00%.1f|r", s), s - math_floor(s)
	else
		return string_format("|cffff0000%.1f|r", s), s - math_floor(s)
	end
end

-- Function to update duration
local function UpdateDuration(aura, timeLeft)
	if aura then
		if timeLeft then
			aura.Duration:SetFormattedText(GetFormattedTime(timeLeft))
		else
			aura.Duration:SetText("")
		end
	end
end

-- Function to apply skin to an aura
local function ApplySkin(aura)
	if aura and not aura.isAuraAnchor and not aura.styled then
		aura.Icon:SetTexCoord(0.04, 0.96, 0.04, 0.96)

		local durationFont, durationSize = aura.Duration:GetFont()
		aura.Duration:SetFont(durationFont, durationSize + 1, "OUTLINE")
		aura.Duration:SetShadowOffset(0, 0)
		aura.Duration:ClearAllPoints()
		aura.Duration:SetPoint("BOTTOM", 0, -4)

		if aura.Count then
			local countFont, countSize = aura.Count:GetFont()
			aura.Count:SetFont(countFont, countSize + 1, "OUTLINE")
			aura.Count:SetShadowOffset(0, 0)
			aura.Count:ClearAllPoints()
			aura.Count:SetPoint("TOPRIGHT", 2, 4)
		end

		if not aura.hook then
			hooksecurefunc(aura, "UpdateDuration", function(aura, timeLeft)
				UpdateDuration(aura, timeLeft)
			end)
			aura.hook = true
		end

		aura.bd = Module:CreateAtlasBackdrop(aura.Icon, 2, aura, "UI-HUD-ActionBar-IconFrame")
		aura.bd:SetFrameLevel(aura:GetFrameLevel() + 1)

		hooksecurefunc(aura, "UpdateAuraType", function(self, auraType)
			self.DebuffBorder:Hide()
			self.TempEnchantBorder:Hide()
			if self.auraType == "Buff" then
				self.bd.texture:SetVertexColor(1, 1, 1)
			elseif self.auraType == "Debuff" or self.auraType == "DeadlyDebuff" then
				local color = DebuffTypeColor["none"] or { r = 0.8, g = 0.1, b = 0.1 } -- Default color if 'none' is not defined
				self.bd.texture:SetVertexColor(color.r, color.g, color.b)
			elseif self.auraType == "TempEnchant" then
				self.bd.texture:SetVertexColor(0.5, 0, 1)
			end
		end)

		aura.styled = true
	end
end

-- Function to update the buff layout
local function UpdateBuffLayout()
	for _, aura in ipairs(BuffFrame.auraFrames) do
		ApplySkin(aura)
	end
end

-- Function to update the debuff layout
local function UpdateDebuffLayout()
	for _, aura in ipairs(DebuffFrame.auraFrames) do
		ApplySkin(aura)
	end
end

-- Event handler for ADDON_LOADED
function Module:ADDON_LOADED(name)
	if name == AddOnName then
		hooksecurefunc(BuffFrame.AuraContainer, "UpdateGridLayout", UpdateBuffLayout)
		hooksecurefunc(DebuffFrame.AuraContainer, "UpdateGridLayout", UpdateDebuffLayout)
	end
end
