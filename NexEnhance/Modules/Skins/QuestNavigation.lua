--[[
	NexEnhance - Quest Navigation (skin)
	-------------------------------------------------------------------------
	Adds an estimated time of arrival under the Blizzard waypoint/super-track
	arrow (SuperTrackedFrame) and gives its distance/ETA text the addon font.

	The ETA is derived from how fast the tracked distance is shrinking,
	smoothed with an exponential moving average so it doesn't flicker. It is
	hidden whenever the arrow is clamped to screen edge or we aren't actually
	getting closer (e.g. standing still or walking away).

	Adapted from KkthnxUI by Josh "Kkthnx" Russell:
	  https://github.com/Kkthnx-Wow/KkthnxUI_Firestorm/blob/main/KkthnxUI/Modules/Skins/Blizzard/QuestNavigation.lua

	Integration notes:
	  * SuperTrackedFrame lives in the load-on-demand Blizzard_QuestNavigation
	    addon, so we style on its ADDON_LOADED if it isn't ready yet.
	  * Purely cosmetic / read-only: the OnUpdate is throttled to 0.5s and we
	    only hook via HookScript / hooksecurefunc, so it stays taint-safe.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local C, L = ns.C, ns.L

local _G = _G
local abs, floor, max = math.abs, math.floor, math.max
local hooksecurefunc = hooksecurefunc
local C_AddOns = C_AddOns
local C_Navigation = C_Navigation
local TIMER_MINUTES_DISPLAY = TIMER_MINUTES_DISPLAY

local GetDistance = C_Navigation and C_Navigation.GetDistance
local WasClampedToScreen = C_Navigation and C_Navigation.WasClampedToScreen

ns:RegisterDefaults({
	questNavigation = {
		enable = true,
	},
})

local QuestNavigation = ns:NewModule("QuestNavigation", "questNavigation", { group = "skins", title = L["Quest Navigation"], order = 50 })

-- Smoothing/throttle state for the distance -> speed -> ETA conversion.
local lastDistance, lastUpdate, emaSpeed = nil, 0, nil

local function HideTime(self)
	if self.TimeText then
		self.TimeText:Hide()
	end
end

local function UpdateArrival(self, elapsed)
	if not GetDistance then return end

	-- No reliable distance while the arrow is clamped to the screen edge.
	if WasClampedToScreen and WasClampedToScreen() then
		HideTime(self)
		lastDistance, lastUpdate, emaSpeed = nil, 0, nil
		return
	end

	lastUpdate = lastUpdate + (elapsed or 0)
	if lastUpdate < 0.5 then return end

	local distance = GetDistance() or 0
	if distance <= 0 then
		HideTime(self)
		lastDistance, lastUpdate = distance, 0
		return
	end

	local prev = lastDistance or distance
	local instSpeed = (prev - distance) / lastUpdate -- yards/s; positive when approaching
	lastDistance = distance
	lastUpdate = 0

	if instSpeed <= 0 then
		HideTime(self)
		return
	end

	-- Exponential moving average to keep the readout from jittering.
	emaSpeed = emaSpeed and (emaSpeed * 0.6 + instSpeed * 0.4) or instSpeed

	local eta = abs(distance / max(emaSpeed, 0.1))
	if self.TimeText then
		self.TimeText:SetFormattedText(TIMER_MINUTES_DISPLAY, floor(eta / 60), floor(eta % 60))
		self.TimeText:Show()
	end
end

local function UpdateAlpha(self)
	if not (WasClampedToScreen and GetDistance) then return end
	if not WasClampedToScreen() and (GetDistance() or 0) > 0 then
		self:SetAlpha(1)
	end
end

function QuestNavigation:Style()
	if self.styled then return end
	local frame = _G.SuperTrackedFrame
	if not (frame and frame.DistanceText) then return end
	self.styled = true

	-- Match the addon font on the existing distance text.
	local _, size, flags = frame.DistanceText:GetFont()
	frame.DistanceText:SetFont(C.Media.Fonts.normal, size or 12, flags)

	local time = frame:CreateFontString(nil, "BACKGROUND")
	time:SetFont(C.Media.Fonts.normal, size or 12, flags)
	time:SetShadowColor(0, 0, 0, 1)
	time:SetShadowOffset(1, -1)
	time:SetPoint("TOP", frame.DistanceText, "BOTTOM", 0, -2)
	time:SetHeight(20)
	time:SetJustifyV("TOP")
	time:SetWordWrap(false)
	frame.TimeText = time

	frame:HookScript("OnUpdate", UpdateArrival)
	if frame.UpdateAlpha then
		hooksecurefunc(frame, "UpdateAlpha", UpdateAlpha)
	end
	frame:HookScript("OnHide", HideTime)
end

function QuestNavigation:ADDON_LOADED(addon)
	if addon == "Blizzard_QuestNavigation" then
		self:Style()
		self:UnregisterEvent("ADDON_LOADED")
	end
end

function QuestNavigation:OnEnable()
	if _G.SuperTrackedFrame or C_AddOns.IsAddOnLoaded("Blizzard_QuestNavigation") then
		self:Style()
	else
		self:RegisterEvent("ADDON_LOADED")
	end
end

function QuestNavigation:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Quest Navigation"], L["Show an estimated arrival time under the waypoint arrow (reload to disable)."])
end
