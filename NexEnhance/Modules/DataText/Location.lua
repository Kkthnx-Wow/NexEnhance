--[[
	NexEnhance - DataText: Location
	-------------------------------------------------------------------------
	Zone and sub-zone text pinned inside the top of the minimap, tinted by the
	zone's PvP status (sanctuary blue, friendly green, hostile/contested, ...).
	Replaces the default zone-text button we strip from the minimap cluster.
	Can be shown always or only on mouseover.
--]]

---@diagnostic disable: undefined-field, undefined-global
local _, ns = ...
local F, L = ns.F, ns.L

local _G = _G
local unpack = unpack
local format = string.format

local CreateFrame = CreateFrame
local MouseIsOver = MouseIsOver
local GetZoneText = GetZoneText
local GetSubZoneText = GetSubZoneText
local GetMinimapZoneText = GetMinimapZoneText
local GetZonePVPInfo = _G.C_PvP and _G.C_PvP.GetZonePVPInfo

ns:RegisterDefaults({
	location = {
		enable = true,
		mouseover = true,
	},
})

local Location = ns:NewModule("Location", "location", { group = "datatext", title = L["Location"], order = 40 })

local cfg
local frame
local eventHandles = {}
local eventsRegistered = false

-- Zone text colour by PvP status (sanctuary, friendly, hostile, contested).
local PVP_COLORS = {
	arena = { 0.84, 0.03, 0.03 },
	combat = { 0.84, 0.03, 0.03 },
	contested = { 0.9, 0.85, 0.05 },
	friendly = { 0.05, 0.85, 0.03 },
	hostile = { 0.84, 0.03, 0.03 },
	neutral = { 0.9, 0.85, 0.05 },
	sanctuary = { 0.035, 0.58, 0.84 },
}

function Location:Update()
	if not cfg or not cfg.enable or not frame then
		return
	end

	local zone = GetZoneText()
	if not zone or zone == "" then
		zone = GetMinimapZoneText and GetMinimapZoneText() or ""
	end
	local subZone = GetSubZoneText()
	if subZone == zone then
		subZone = ""
	end

	local pvpType = (GetZonePVPInfo and GetZonePVPInfo()) or "neutral"
	local r, g, b = unpack(PVP_COLORS[pvpType] or { 1, 1, 1 })

	F.SetPlainText(frame.zone, zone)
	frame.zone:SetTextColor(r, g, b)
	F.SetPlainText(frame.subZone, subZone)
	frame.subZone:SetTextColor(r, g, b)
end

-- Throttled mouseover poll: we watch MouseIsOver(Minimap) rather than hooking
-- the minimap's OnEnter/OnLeave so the text stays up while the cursor passes
-- over the clock, calendar, queue icons and other child frames on top of it.
local mouseThrottle = 0
local function MouseoverOnUpdate(self, elapsed)
	mouseThrottle = mouseThrottle + (elapsed or 0)
	if mouseThrottle < 0.05 then
		return
	end
	mouseThrottle = 0
	self:SetAlpha(MouseIsOver(_G["Minimap"]) and 1 or 0)
end

-- The frame itself stays shown; in mouseover mode we run the poll and fade the
-- text via alpha, in always-on mode we drop the OnUpdate entirely (the best
-- throttle is not running a handler at all).
local function ApplyVisibility()
	if not frame or not cfg or not cfg.enable then
		return
	end
	frame:Show()
	if cfg.mouseover then
		frame:SetAlpha(MouseIsOver(_G["Minimap"]) and 1 or 0)
		frame:SetScript("OnUpdate", MouseoverOnUpdate)
	else
		frame:SetScript("OnUpdate", nil)
		frame:SetAlpha(1)
	end
end

function Location:Create()
	if frame then
		ApplyVisibility()
		return
	end

	local minimap = _G["Minimap"]
	if not minimap then
		return
	end

	frame = CreateFrame("Frame", nil, minimap)
	frame:SetFrameLevel(minimap:GetFrameLevel() + 5)
	frame:SetPoint("TOPLEFT", minimap, "TOPLEFT", 2, -4)
	frame:SetPoint("TOPRIGHT", minimap, "TOPRIGHT", -2, -4)
	frame:SetHeight(13)

	frame.zone = F.CreatePlainFS(frame, 12)
	frame.zone:SetPoint("TOP", frame, "TOP", 0, 0)
	frame.zone:SetWidth(minimap:GetWidth() - 6)
	frame.zone:SetWordWrap(true)
	frame.zone:SetNonSpaceWrap(false)
	frame.zone:SetMaxLines(2)

	frame.subZone = F.CreatePlainFS(frame, 11)
	frame.subZone:SetPoint("TOP", frame.zone, "BOTTOM", 0, -2)
	frame.subZone:SetWidth(minimap:GetWidth() - 6)
	frame.subZone:SetWordWrap(true)
	frame.subZone:SetNonSpaceWrap(false)
	frame.subZone:SetMaxLines(1)

	ApplyVisibility()
	self:Update()
end

function Location:RegisterModuleEvents()
	if eventsRegistered then
		return
	end
	eventsRegistered = true
	self:TrackEvent(eventHandles, "PLAYER_ENTERING_WORLD", "Update")
	self:TrackEvent(eventHandles, "ZONE_CHANGED", "Update")
	self:TrackEvent(eventHandles, "ZONE_CHANGED_INDOORS", "Update")
	self:TrackEvent(eventHandles, "ZONE_CHANGED_NEW_AREA", "Update")
end

function Location:UnregisterModuleEvents()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
end

function Location:Stop()
	self:UnregisterModuleEvents()
	if frame then
		frame:SetScript("OnUpdate", nil)
		frame:Hide()
	end
end

function Location:OnEnable()
	cfg = ns.db.location
	if not cfg.enable then
		return
	end
	self:Create()
	self:RegisterModuleEvents()
	self:Update()

	ns.Debug.BindModule(self, "location", {
		title = L["Location"],
		expectations = {
			{
				name = "events and frame match enable toggle",
				test = function()
					if not cfg or not cfg.enable then
						return not eventsRegistered
					end
					return frame ~= nil and eventsRegistered
				end,
				detail = function()
					return format("enable=%s eventsRegistered=%s frame=%s", tostring(cfg and cfg.enable), tostring(eventsRegistered), frame and "yes" or "no")
				end,
			},
		},
		dump = function()
			F.Print(format("  enable=%s mouseover=%s eventsRegistered=%s frame=%s", tostring(cfg.enable), tostring(cfg.mouseover), tostring(eventsRegistered), frame and "yes" or "no"))
		end,
	})
end

function Location:OnDisable()
	self:Stop()
end

function Location:OnSettingChanged(key, value)
	cfg = ns.db.location
	if key == "enable" then
		if value then
			self:Create()
			self:RegisterModuleEvents()
			self:Update()
		else
			self:Stop()
		end
	elseif key == "mouseover" and cfg.enable then
		ApplyVisibility()
	end
end

function Location:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Location"], L["Show zone and sub-zone text at the top of the minimap."])
	local _, mouseoverInit = builder:Checkbox(category, self, "mouseover", L["Show on Mouseover"], L["Only show the zone text while hovering the minimap."])

	builder:DependsOn(mouseoverInit, enableInit)
end
