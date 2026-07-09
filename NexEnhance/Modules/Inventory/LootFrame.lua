--[[
	NexEnhance - Loot Frame
	-------------------------------------------------------------------------
	Lets the default loot window grow taller so more items fit on a single
	page instead of being capped and forced to scroll (handy when you loot a
	big pile of mobs manually). Raises LootFrame.panelMaxHeight to a share of
	the screen height and keeps it in sync when the display size changes.
	Configurable height percentage with a live toggle (no reload to flip off).
--]]

-- luacheck: globals LootFrame
---@diagnostic disable: undefined-field
local _, ns = ...
local L = ns.L

local _G = _G
local tonumber = tonumber
local min, max = math.min, math.max

local UIParent = UIParent

ns:RegisterDefaults({
	lootFrame = {
		enable = true,
		maxHeight = 70,
	},
})

local LootFrameModule = ns:NewModule("LootFrame", "lootFrame", { group = "inventory", title = L["Loot Frame"], order = 60 })

local MIN_PERCENT, MAX_PERCENT = 40, 90

-- Blizzard's stock cap, captured the first time we touch the frame so a live
-- disable can put things back exactly as they were (no reload needed).
local originalMaxHeight

local eventHandles = {}
local eventsRegistered = false

local function Apply()
	local frame = _G.LootFrame
	if not frame then
		return
	end

	if not ns.db.lootFrame.enable then
		if originalMaxHeight ~= nil then
			frame.panelMaxHeight = originalMaxHeight
		end
		return
	end

	if originalMaxHeight == nil then
		originalMaxHeight = frame.panelMaxHeight
	end

	local percent = tonumber(ns.db.lootFrame.maxHeight) or 70
	percent = min(max(percent, MIN_PERCENT), MAX_PERCENT)
	frame.panelMaxHeight = UIParent:GetHeight() * (percent / 100)
end

function LootFrameModule:DISPLAY_SIZE_CHANGED()
	Apply()
end

function LootFrameModule:UI_SCALE_CHANGED()
	Apply()
end

-- The loot UI can be load-on-demand; apply once it actually exists.
function LootFrameModule:ADDON_LOADED(addon)
	if addon == "Blizzard_Loot" or _G.LootFrame then
		Apply()
	end
end

function LootFrameModule:RegisterModuleEvents()
	if eventsRegistered then
		return
	end
	eventsRegistered = true
	self:TrackEvent(eventHandles, "DISPLAY_SIZE_CHANGED", "DISPLAY_SIZE_CHANGED")
	self:TrackEvent(eventHandles, "UI_SCALE_CHANGED", "UI_SCALE_CHANGED")
	if not _G.LootFrame then
		self:TrackEvent(eventHandles, "ADDON_LOADED", "ADDON_LOADED")
	end
end

function LootFrameModule:UnregisterModuleEvents()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
end

function LootFrameModule:Stop()
	self:UnregisterModuleEvents()
	Apply()
end

function LootFrameModule:OnEnable()
	if not ns.db.lootFrame.enable then
		return
	end
	self:RegisterModuleEvents()
	Apply()
end

function LootFrameModule:OnDisable()
	self:Stop()
end

function LootFrameModule:OnSettingChanged(key)
	if key == "enable" then
		-- ApplyModuleSetting owns enable lifecycle.
		return
	end
	Apply()
end

function LootFrameModule:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Loot Frame"], L["Let the loot window expand to fit more items on one page instead of scrolling."])
	local _, heightInit = builder:Slider(category, self, "maxHeight", L["Max Loot Height"], L["How tall the loot window may grow, as a percentage of the screen height."], MIN_PERCENT, MAX_PERCENT, 5)

	builder:DependsOn(heightInit, enableInit)
end
