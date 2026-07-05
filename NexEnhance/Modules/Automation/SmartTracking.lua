--[[
	NexEnhance - Smart Minimap Tracking
	-------------------------------------------------------------------------
	Auto-enables repair-vendor minimap tracking when gear is damaged, and mailbox
	tracking when mail is pending.

	Blizzard refs: C_Minimap.GetTrackingInfo / SetTracking, UPDATE_INVENTORY_DURABILITY,
	UPDATE_PENDING_MAIL, MINIMAP_TRACKING_REPAIR / MINIMAP_TRACKING_MAILBOX.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local L = ns.L

local wipe = wipe
local INVENTORY_ALERT_STATUS_SLOTS = INVENTORY_ALERT_STATUS_SLOTS
local GetInventoryAlertStatus = GetInventoryAlertStatus
local HasNewMail = HasNewMail
local MINIMAP_TRACKING_REPAIR = MINIMAP_TRACKING_REPAIR
local MINIMAP_TRACKING_MAILBOX = MINIMAP_TRACKING_MAILBOX

ns:RegisterDefaults({
	smartTracking = {
		enable = true,
	},
})

local SmartTracking = ns:NewModule("SmartTracking", "smartTracking", { group = "automation", title = L["Smart Minimap Tracking"], order = 37 })

local trackingIndexByName = {}
local eventHandles = {}
local eventsRegistered = false

local function ResolveTrackingIndex(name)
	if trackingIndexByName[name] then
		return trackingIndexByName[name]
	end
	if not C_Minimap or not C_Minimap.GetNumTrackingTypes then
		return
	end
	for index = 1, C_Minimap.GetNumTrackingTypes() do
		local info = C_Minimap.GetTrackingInfo(index)
		if info and info.name == name then
			trackingIndexByName[name] = index
			return index
		end
	end
end

function SmartTracking:UPDATE_INVENTORY_DURABILITY()
	if not ns.db.smartTracking.enable then
		return
	end
	local worst = 0
	for slot in pairs(INVENTORY_ALERT_STATUS_SLOTS) do
		local status = GetInventoryAlertStatus(slot)
		if status and status > worst then
			worst = status
		end
	end
	local index = ResolveTrackingIndex(MINIMAP_TRACKING_REPAIR)
	if index then
		C_Minimap.SetTracking(index, worst > 0)
	end
end

function SmartTracking:UPDATE_PENDING_MAIL()
	if not ns.db.smartTracking.enable then
		return
	end
	local index = ResolveTrackingIndex(MINIMAP_TRACKING_MAILBOX)
	if index then
		C_Minimap.SetTracking(index, HasNewMail())
	end
end

function SmartTracking:PLAYER_ENTERING_WORLD()
	self:UPDATE_INVENTORY_DURABILITY()
	self:UPDATE_PENDING_MAIL()
end

function SmartTracking:OnEnable()
	if not ns.db.smartTracking.enable or eventsRegistered then
		return
	end
	eventsRegistered = true
	wipe(trackingIndexByName)
	self:TrackEvent(eventHandles, "UPDATE_INVENTORY_DURABILITY")
	self:TrackEvent(eventHandles, "UPDATE_PENDING_MAIL")
	self:TrackEvent(eventHandles, "PLAYER_ENTERING_WORLD")
	self:PLAYER_ENTERING_WORLD()
end

function SmartTracking:OnDisable()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	wipe(trackingIndexByName)
	ns:UnregisterModuleEventHandles(eventHandles)
end

function SmartTracking:OnSettingChanged(key, value)
	if key == "enable" then
		if value then
			self:OnEnable()
		else
			self:OnDisable()
		end
	end
end

function SmartTracking:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Smart Minimap Tracking"], L["Auto-enable repair-vendor tracking when gear is damaged, and mailbox tracking when you have pending mail."])
end
