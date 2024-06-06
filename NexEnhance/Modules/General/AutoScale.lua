local NexEnhance, NE_AutoScale = ...

-- Auto Scale The Interface
local function GetBestScale()
	local scale = max(0.4, min(1.15, 768 / NE_AutoScale.ScreenHeight))
	return NE_AutoScale:Round(scale, 2)
end

function NE_AutoScale:SetupUIScale(init)
	if NE_AutoScale.db.profile.general.AutoScale then
		NE_AutoScale.db.profile.general.UIScale = GetBestScale()
	end
	local scale = NE_AutoScale.db.profile.general.UIScale
	if init then
		local pixel = 1
		local ratio = 768 / NE_AutoScale.ScreenHeight
	elseif not InCombatLockdown() then
		UIParent:SetScale(scale)
	end
end

local isScaling = false
local function UpdatePixelScale(_, event)
	if isScaling then
		return
	end
	isScaling = true

	if event == "UI_SCALE_CHANGED" then
		print(event)
		NE_AutoScale.ScreenWidth, NE_AutoScale.ScreenHeight = GetPhysicalScreenSize()
	end
	NE_AutoScale:SetupUIScale(true)
	NE_AutoScale:SetupUIScale()

	isScaling = false
end

function NE_AutoScale:PLAYER_LOGIN()
	self:SetupUIScale()
	self.eventMixin:RegisterEvent("UI_SCALE_CHANGED", UpdatePixelScale)
end
