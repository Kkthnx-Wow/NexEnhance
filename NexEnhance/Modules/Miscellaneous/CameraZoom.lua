--[[
	NexEnhance - Max Camera Zoom
	-------------------------------------------------------------------------
	Raises the camera's maximum zoom-out distance via the
	"cameraDistanceMaxZoomFactor" CVar. Blizzard clamps this between 1.0 and
	2.6, so the value is bounded to that range before it is applied.

	Adapted from KkthnxUI's UpdateMaxCameraZoom (by Josh "Kkthnx" Russell):
	  https://github.com/Kkthnx-Wow/KkthnxUI_Firestorm
--]]

local _, ns = ...
local L = ns.L

local tonumber = tonumber
local min, max = math.min, math.max
local SetCVar = SetCVar

ns:RegisterDefaults({
	cameraZoom = {
		enable = true,
		value = 2.6,
	},
})

local CameraZoom = ns:NewModule("CameraZoom", "cameraZoom", { group = "general", title = L["Camera Zoom"], order = 2 })

local MIN_ZOOM, MAX_ZOOM = 1.0, 2.6

local function Apply()
	if not ns.db.cameraZoom.enable then return end
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
