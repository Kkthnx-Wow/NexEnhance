--[[
	NexEnhance - Cooldowns
	-------------------------------------------------------------------------
	Formats the numbers shown on cooldown swipes (action buttons, auras, items,
	etc.). Adapted from NDui's ActionBar/Cooldown module, reworked to fit the
	NexEnhance engine, database and live-apply options.

	Why this approach is fast:
	  * It uses Blizzard's native countdown text via C_StringUtil's
	    NumericRuleFormatter + Cooldown:SetCountdownFormatter. The client does
	    the per-frame rendering, so we run NO OnUpdate timer of our own.
	  * The shared Cooldown metatable methods are hooked once, so every current
	    and future cooldown frame is covered with a handful of hooks.
	  * Each cooldown frame is tagged the first time it is seen so the formatter
	    is only assigned once per frame.

	Reference:
	  NDui  - https://github.com/siweia/NDui (Modules/ActionBar/Cooldown.lua)
--]]

local _, ns = ...
local C, L = ns.C, ns.L

-- Localised globals.
local C_StringUtil = C_StringUtil
local CreateColor = CreateColor
local hooksecurefunc = hooksecurefunc
local getmetatable = getmetatable
local SetCVar = SetCVar
local pairs = pairs
local Enum = Enum

local ROUNDING_UP = Enum.NumericRuleFormatRounding.Up
local ROUNDING_NEAREST = Enum.NumericRuleFormatRounding.Nearest

-- Threshold colours: red under 3s, yellow under 10s, then a calmer tone.
local COLOR_RED = CreateColor(1, 0, 0, 1)
local COLOR_YELLOW = CreateColor(1, 1, 0, 1)
local COLOR_DARK = CreateColor(0.8, 0.8, 0.2, 1)

-- Colour escape applied to the m/h/d unit suffix (uses the brand colour).
local UNIT = "|c" .. C.BrandHex
local R = "|r"

-- ---------------------------------------------------------------------------
-- Defaults & module
-- ---------------------------------------------------------------------------
ns:RegisterDefaults({
	cooldowns = {
		enable = true,
		style = 1, -- 1 colored+decimals, 2 colored, 3 plain+decimals, 4 plain
	},
})

local Cooldowns = ns:NewModule("Cooldowns", "cooldowns", { group = "actionbars", title = L["Cooldown Text"], order = 20 })

-- ---------------------------------------------------------------------------
-- Breakpoint rulesets (one per style). Built once at file scope.
--   threshold  : minimum seconds this rule applies to
--   format     : format string (may embed colour codes)
--   components : how the value is divided/rounded before formatting
-- ---------------------------------------------------------------------------
local breakPoints = {
	-- Style 1: coloured, sub-3s shown with one decimal.
	[1] = {
		{ threshold = 0, format = COLOR_RED:WrapTextInColorCode("%.1f"), components = { { step = 0.1, rounding = ROUNDING_UP } } },
		{ threshold = 3, format = COLOR_YELLOW:WrapTextInColorCode("%d"), components = { { div = 1, step = 1, rounding = ROUNDING_UP } } },
		{ threshold = 10, format = COLOR_DARK:WrapTextInColorCode("%d"), components = { { div = 1, step = 1, rounding = ROUNDING_UP } } },
		{ threshold = 60, format = "%d:%02d", components = { { div = 60 }, { mod = 60 } } },
		{ threshold = 60 * 10, format = "%d" .. UNIT .. "m" .. R, components = { { div = 60, step = 1, rounding = ROUNDING_NEAREST } } },
		{ threshold = 3600 * 2, format = "%d" .. UNIT .. "h" .. R, components = { { div = 3600, step = 1, rounding = ROUNDING_NEAREST } } },
		{ threshold = 86400, format = "%d" .. UNIT .. "d" .. R, components = { { div = 86400, step = 1, rounding = ROUNDING_NEAREST } } },
	},
	-- Style 2: coloured, integers only.
	[2] = {
		{ threshold = 0, format = COLOR_RED:WrapTextInColorCode("%d"), components = { { div = 1, step = 1, rounding = ROUNDING_UP } } },
		{ threshold = 3, format = COLOR_YELLOW:WrapTextInColorCode("%d"), components = { { div = 1, step = 1, rounding = ROUNDING_UP } } },
		{ threshold = 10, format = COLOR_DARK:WrapTextInColorCode("%d"), components = { { div = 1, step = 1, rounding = ROUNDING_UP } } },
		{ threshold = 60, format = "%d:%02d", components = { { div = 60 }, { mod = 60 } } },
		{ threshold = 60 * 10, format = "%d" .. UNIT .. "m" .. R, components = { { div = 60, step = 1, rounding = ROUNDING_NEAREST } } },
		{ threshold = 3600 * 2, format = "%d" .. UNIT .. "h" .. R, components = { { div = 3600, step = 1, rounding = ROUNDING_NEAREST } } },
		{ threshold = 86400, format = "%d" .. UNIT .. "d" .. R, components = { { div = 86400, step = 1, rounding = ROUNDING_NEAREST } } },
	},
	-- Style 3: plain, sub-3s shown with one decimal.
	[3] = {
		{ threshold = 0, format = "%.1f", components = { { step = 0.1, rounding = ROUNDING_UP } } },
		{ threshold = 3, format = "%d", components = { { div = 1, step = 1, rounding = ROUNDING_UP } } },
		{ threshold = 60, format = "%d:%02d", components = { { div = 60 }, { mod = 60 } } },
		{ threshold = 60 * 10, format = "%dm", components = { { div = 60, step = 1, rounding = ROUNDING_NEAREST } } },
		{ threshold = 3600 * 2, format = "%dh", components = { { div = 3600, step = 1, rounding = ROUNDING_NEAREST } } },
		{ threshold = 86400, format = "%dd", components = { { div = 86400, step = 1, rounding = ROUNDING_NEAREST } } },
	},
	-- Style 4: plain, integers only.
	[4] = {
		{ threshold = 0, format = "%d", components = { { div = 1, step = 1, rounding = ROUNDING_UP } } },
		{ threshold = 60, format = "%d:%02d", components = { { div = 60 }, { mod = 60 } } },
		{ threshold = 60 * 10, format = "%dm", components = { { div = 60, step = 1, rounding = ROUNDING_NEAREST } } },
		{ threshold = 3600 * 2, format = "%dh", components = { { div = 3600, step = 1, rounding = ROUNDING_NEAREST } } },
		{ threshold = 86400, format = "%dd", components = { { div = 86400, step = 1, rounding = ROUNDING_NEAREST } } },
	},
}

-- One formatter shared by every cooldown. Switching styles just swaps its
-- breakpoints (no new allocations).
local formatter = C_StringUtil.CreateNumericRuleFormatter()

-- Weak keys: when a cooldown frame is collected, drop it from the set too.
local hookedCooldowns = setmetatable({}, { __mode = "k" })

local function GetStyle()
	return ns.db.cooldowns.style or 1
end

-- Hook handler shared by all cooldown methods. hooksecurefunc passes the
-- cooldown as the first argument, so one function covers every frame.
local function OnCooldownSet(cooldown)
	if not cooldown or hookedCooldowns[cooldown] then return end
	hookedCooldowns[cooldown] = true

	if Cooldowns:IsEnabled() then
		cooldown:SetCountdownFormatter(formatter)
	end
end

-- ---------------------------------------------------------------------------
-- Public methods
-- ---------------------------------------------------------------------------
function Cooldowns:ApplyBreakpoints()
	formatter:SetBreakpoints(breakPoints[GetStyle()] or breakPoints[1])
end

--- Toggle the native countdown CVar and (re)apply the formatter to every
--- tracked cooldown. Called on enable and whenever a setting changes.
function Cooldowns:UpdateFormat()
	local enabled = self:IsEnabled()

	-- This CVar drives Blizzard's built-in cooldown numbers.
	SetCVar("countdownForCooldowns", enabled and "1" or "0")

	if enabled then
		self:ApplyBreakpoints()
	end

	for cooldown in pairs(hookedCooldowns) do
		cooldown:SetCountdownFormatter(enabled and formatter or nil)
	end
end

function Cooldowns:OnSettingChanged()
	if self:IsEnabled() then
		self:InstallHooks()
	end
	self:UpdateFormat()
end

function Cooldowns:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Cooldown Text"], L["Show formatted countdown numbers on cooldowns."])
	builder:Dropdown(category, self, "style", L["Cooldown Style"], L["Choose how cooldown numbers are displayed."], {
		{ value = 1, label = L["Coloured (decimals)"] },
		{ value = 2, label = L["Coloured (integers)"] },
		{ value = 3, label = L["Plain (decimals)"] },
		{ value = 4, label = L["Plain (integers)"] },
	})
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function Cooldowns:InstallHooks()
	if self.hooksInstalled then return end

	-- All cooldown frames share one metatable; hooking it covers them all.
	local template = ActionButton1Cooldown
	if not template then return end

	self.hooksInstalled = true

	local cooldownMeta = getmetatable(template).__index
	local methods = { "SetCooldown", "SetCooldownDuration", "SetHideCountdownNumbers", "SetCooldownFromDurationObject" }
	for i = 1, #methods do
		if cooldownMeta[methods[i]] then
			hooksecurefunc(cooldownMeta, methods[i], OnCooldownSet)
		end
	end
	hooksecurefunc("CooldownFrame_SetDisplayAsPercentage", OnCooldownSet)
end

function Cooldowns:OnEnable()
	self:InstallHooks()
	self:UpdateFormat()
end
