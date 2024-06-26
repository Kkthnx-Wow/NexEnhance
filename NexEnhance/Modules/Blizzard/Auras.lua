local AddOnName, Module = ...

-- Importing required functions and constants
local string_format = string.format
local math_floor = math.floor

local day, hour, minute = 86400, 3600, 60

-- Function to get formatted time
local function GetFormattedTime(s)
	if s >= day then
		return string_format("%d" .. Module.MyClassColor .. "d", s / day), s % day
	elseif s >= 2 * hour then
		return string_format("%d" .. Module.MyClassColor .. "h", s / hour), s % hour
	elseif s >= 10 * minute then
		return string_format("%d" .. Module.MyClassColor .. "m", s / minute), s % minute
	elseif s >= minute then
		return string_format("%d:%.2d", s / minute, s % minute), s - math_floor(s)
	elseif s > 10 then
		return string_format("%d" .. Module.MyClassColor .. "s", s), s - math_floor(s)
	elseif s > 5 then
		return string_format("|cffffff00%.1f|r", s), s - string_format("%.1f", s)
	else
		return string_format("|cffff0000%.1f|r", s), s - string_format("%.1f", s)
	end
end

-- Function to update duration
local function UpdateDuration(aura, timeLeft)
	if timeLeft then
		aura.Duration:SetFormattedText(GetFormattedTime(timeLeft))
	else
		aura.Duration:Hide()
	end
end

-- Function to apply skin to an aura
local function ApplySkin(aura)
	if not aura.isAuraAnchor and not aura.styled then
		local durationFont, durationFontSize = aura.Duration:GetFont()
		aura.Duration:SetFont(durationFont, durationFontSize + 1, "OUTLINE")
		aura.Duration:SetShadowOffset(0, 0)

		if not aura.hook then
			hooksecurefunc(aura, "UpdateDuration", function(aura, timeLeft)
				UpdateDuration(aura, timeLeft)
			end)
			aura.hook = true
		end

		if aura.Count then
			local countFont, countFontSize = aura.Count:GetFont()
			aura.Count:SetFont(countFont, countFontSize, "OUTLINE")
			aura.Count:SetShadowOffset(0, 0)
			aura.Count:ClearAllPoints()
			aura.Count:SetPoint("TOPRIGHT", 2, 2)
		end

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
