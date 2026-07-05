--[[
	NexEnhance - Max Camera Zoom
	-------------------------------------------------------------------------
	Raises the camera's maximum zoom-out distance via the
	"cameraDistanceMaxZoomFactor" CVar. Blizzard clamps this between 1.0 and
	2.6, so the value is bounded to that range before it is applied.
--]]

local _, ns = ...
local L = ns.L

local tonumber = tonumber
local min, max = math.min, math.max
local SetCVar = SetCVar
local GetCVar = GetCVar

ns:RegisterDefaults({
	cameraZoom = {
		enable = true,
		value = 2.6,
	},
})

local CameraZoom = ns:NewModule("CameraZoom", "cameraZoom", { group = "camera", title = L["Camera Zoom"], order = 10 })

local MIN_ZOOM, MAX_ZOOM = 1.0, 2.6

-- Remember the player's pre-addon zoom factor so disabling the module hands it
-- back instead of stranding them at whatever we raised it to until the next /reload.
local originalZoom

local function Apply()
	if originalZoom == nil then
		originalZoom = GetCVar("cameraDistanceMaxZoomFactor")
	end
	if not ns.db.cameraZoom.enable then
		if originalZoom then
			SetCVar("cameraDistanceMaxZoomFactor", originalZoom)
		end
		return
	end
	local value = tonumber(ns.db.cameraZoom.value) or MAX_ZOOM
	value = min(max(value, MIN_ZOOM), MAX_ZOOM)
	SetCVar("cameraDistanceMaxZoomFactor", value)
end

function CameraZoom:OnEnable()
	Apply()
end

function CameraZoom:OnSettingChanged()
	Apply()
end

function CameraZoom:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Camera Zoom"], L["Raise the maximum camera zoom-out distance."])
	local _, valueInit = builder:Slider(category, self, "value", L["Max Zoom Distance"], L["How far out the camera can zoom (Blizzard limit is 2.6)."], MIN_ZOOM, MAX_ZOOM, 0.1)

	builder:DependsOn(valueInit, enableInit)
end
