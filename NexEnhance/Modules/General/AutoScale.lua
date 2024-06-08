local _, Module = ...

-- Auto Scale The Interface
local function GetBestScale()
	local scale = max(0.4, min(1.15, 768 / Module.ScreenHeight))
	return Module:Round(scale, 2)
end

function Module:SetupUIScale()
	if Module.db.profile.general.AutoScale then
		Module.db.profile.general.UIScale = GetBestScale()
	end
	local scale = Module.db.profile.general.UIScale
	if not InCombatLockdown() then
		UIParent:SetScale(scale)
	end
end

local isScaling = false
function Module:UI_SCALE_CHANGED()
	if isScaling then
		return
	end
	isScaling = true

	Module.ScreenWidth, Module.ScreenHeight = GetPhysicalScreenSize()
	Module:SetupUIScale()

	isScaling = false
end

function Module:PLAYER_LOGIN()
	self:SetupUIScale()
end
