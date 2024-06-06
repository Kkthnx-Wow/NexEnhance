local NexEnhance, NE_AutoScale = ...

-- Auto Scale The Interface
local function GetBestScale()
	local scale = max(0.4, min(1.15, 768 / NE_AutoScale.ScreenHeight))
	return NE_AutoScale:Round(scale, 2)
end

function NE_AutoScale:SetupUIScale()
	if NE_AutoScale.db.profile.general.AutoScale then
		NE_AutoScale.db.profile.general.UIScale = GetBestScale()
	end
	local scale = NE_AutoScale.db.profile.general.UIScale
	if not InCombatLockdown() then
		UIParent:SetScale(scale)
	end
end

local isScaling = false
function NE_AutoScale:UI_SCALE_CHANGED()
	if isScaling then
		return
	end
	isScaling = true

	NE_AutoScale.ScreenWidth, NE_AutoScale.ScreenHeight = GetPhysicalScreenSize()
	NE_AutoScale:SetupUIScale()

	isScaling = false
end

function NE_AutoScale:PLAYER_LOGIN()
	self:SetupUIScale()
end
