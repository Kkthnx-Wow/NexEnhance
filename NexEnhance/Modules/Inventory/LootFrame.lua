--[[
	NexEnhance - Loot Frame
	-------------------------------------------------------------------------
	Lets the default loot window grow taller so more items fit on a single
	page instead of being capped and forced to scroll (handy when you loot a
	big pile of mobs manually). Raises LootFrame.panelMaxHeight to a share of
	the screen height and keeps it in sync when the display size changes.

	Inspired by Cybeloras' Improved Loot Frame; rewritten for NexEnhance and
	the modern (scrollbox) loot frame, with a configurable height and a live
	toggle.
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

function LootFrameModule:OnEnable()
	-- Re-anchor to screen size live; registered regardless of the toggle so a
	-- later enable still tracks resolution/scale changes without a reload.
	self:RegisterEvent("DISPLAY_SIZE_CHANGED")
	self:RegisterEvent("UI_SCALE_CHANGED")

	if _G.LootFrame then
		Apply()
	else
		self:RegisterEvent("ADDON_LOADED")
	end
end

function LootFrameModule:OnSettingChanged()
	Apply()
end

function LootFrameModule:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Loot Frame"], L["Let the loot window expand to fit more items on one page instead of scrolling."])
	local _, heightInit = builder:Slider(category, self, "maxHeight", L["Max Loot Height"], L["How tall the loot window may grow, as a percentage of the screen height."], MIN_PERCENT, MAX_PERCENT, 5)

	builder:DependsOn(heightInit, enableInit)
end
