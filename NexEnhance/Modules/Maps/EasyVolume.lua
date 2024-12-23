local _, Module = ...

-- Helper function to get the color based on the volume level
local function GetVolumeColor(volume)
	return Module:RGBColorGradient(volume, 100, 1, 1, 1, 1, 0.8, 0, 1, 0, 0)
end

-- Helper function to get the current master volume as a percentage
local function GetCurrentVolume()
	return Module:Round(GetCVar("Sound_MasterVolume") * 100)
end

-- Function to create the sound volume display on the minimap
function Module:CreateSoundVolume()
	local frame = CreateFrame("Frame", nil, Minimap)
	frame:SetAllPoints()
	local volumeText = self.CreateFontString(frame, 30)

	local animGroup = frame:CreateAnimationGroup()
	animGroup:SetScript("OnPlay", function()
		frame:SetAlpha(1)
	end)

	animGroup:SetScript("OnFinished", function()
		frame:SetAlpha(0)
	end)

	local fadeAnim = animGroup:CreateAnimation("Alpha")
	fadeAnim:SetFromAlpha(1)
	fadeAnim:SetToAlpha(0)
	fadeAnim:SetDuration(3)
	fadeAnim:SetSmoothing("OUT")
	fadeAnim:SetStartDelay(1)

	Module.VolumeText = volumeText
	Module.VolumeAnim = animGroup
end

-- Event handler for mouse wheel scrolling on the minimap
function Module:Minimap_OnMouseWheel(delta)
	if IsControlKeyDown() and Module.VolumeText then
		local currentVolume = GetCurrentVolume()
		local increment = IsAltKeyDown() and 100 or 2
		local newVolume = currentVolume + delta * increment

		newVolume = math.max(0, math.min(newVolume, 100))

		SetCVar("Sound_MasterVolume", tostring(newVolume / 100))
		Module.VolumeText:SetText(newVolume .. "%")
		Module.VolumeText:SetTextColor(GetVolumeColor(newVolume))
		Module.VolumeAnim:Stop()
		Module.VolumeAnim:Play()
	else
		if delta > 0 then
			Minimap_ZoomIn()
		else
			Minimap_ZoomOut()
		end
	end
end

-- Event handler for player login
function Module:PLAYER_LOGIN()
	if not Module.NexConfig.minimap.EasyVolume then
		return
	end

	Minimap:EnableMouseWheel(true)
	Minimap:SetScript("OnMouseWheel", Module.Minimap_OnMouseWheel)
	Module:CreateSoundVolume()
end
