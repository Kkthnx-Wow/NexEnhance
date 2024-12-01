local _, Module = ...

-- Auto Scale The Interface
local function GetBestScale()
	local scale = max(0.4, min(1.15, 768 / Module.ScreenHeight))
	return Module:Round(scale, 2)
end

function Module:SetupUIScale(init)
	local generalDB = Module.NexConfig.general
	if generalDB["AutoScale"] then
		generalDB["UIScale"] = GetBestScale()
	end
	local scale = generalDB["UIScale"]
	if init then
		local pixel = 1
		local ratio = 768 / Module.ScreenHeight
		Module.Multi = (pixel / scale) - ((pixel - ratio) / scale)
	elseif not InCombatLockdown() then
		UIParent:SetScale(scale)
	end
end

local isScaling = false
local function UpdatePixelScale(event)
	print(event)
	if isScaling then
		return
	end
	isScaling = true

	if event == "UI_SCALE_CHANGED" then
		Module.ScreenWidth, Module.ScreenHeight = GetPhysicalScreenSize()
	end

	Module:SetupUIScale(true)
	Module:SetupUIScale()

	isScaling = false
end

function Module:OnLogin()
	Module:SetupUIScale()
	Module:RegisterEvent("UI_SCALE_CHANGED", UpdatePixelScale)
end
