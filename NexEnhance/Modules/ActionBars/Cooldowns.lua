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
local F, C, L = ns.F, ns.C, ns.L

-- Localised globals.
local C_StringUtil = C_StringUtil
local CreateColor = CreateColor
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc
local getmetatable = getmetatable
local SetCVar = SetCVar
local GetCVar = GetCVar
local pairs = pairs
local Enum = Enum
local InCombatLockdown = InCombatLockdown
local Round = Round or function(n)
	return math.floor(n + 0.5)
end

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
		mmssThreshold = 90, -- seconds: below this show raw seconds, then mm:ss
		scaleText = false, -- shrink text on small cooldowns (relative to a default button)
		minScale = 0.6, -- hide text once the relative scale drops below this
	},
})

local Cooldowns = ns:NewModule("Cooldowns", "cooldowns", { group = "actionbars", title = L["Cooldown Text"], order = 20 })

-- ---------------------------------------------------------------------------
-- Breakpoint builder
--   The rules are generated per style so the mm:ss switch point is configurable
--   and a weeks tier can sit above days. Only runs when the style or threshold
--   changes (on enable / setting change), never per frame.
--     threshold  : minimum seconds this rule applies to
--     format     : format string (may embed colour codes)
--     components : how the value is divided/rounded before formatting
-- ---------------------------------------------------------------------------
local MINUTE, HOUR, DAY, WEEK = 60, 3600, 86400, 604800

-- m/h/d/w suffix; coloured styles tint the suffix with the brand colour.
local function UnitFormat(colored, suffix)
	if colored then
		return "%d" .. UNIT .. suffix .. R
	end
	return "%d" .. suffix
end

-- style -> appearance flags
local styleInfo = {
	[1] = { colored = true, decimals = true },
	[2] = { colored = true, decimals = false },
	[3] = { colored = false, decimals = true },
	[4] = { colored = false, decimals = false },
}

local function BuildBreakpoints(colored, decimals, mmss)
	local function tint(color, fmt)
		return colored and color:WrapTextInColorCode(fmt) or fmt
	end

	-- mm:ss must stay above the integer-seconds tier (10s) and below the
	-- 10-minute minutes tier, so a bad value can never reorder the rules.
	mmss = mmss or MINUTE
	if mmss < MINUTE then
		mmss = MINUTE
	end
	if mmss > MINUTE * 9 then
		mmss = MINUTE * 9
	end

	return {
		{
			threshold = 0,
			format = tint(COLOR_RED, decimals and "%.1f" or "%d"),
			components = decimals and { { step = 0.1, rounding = ROUNDING_UP } } or { { div = 1, step = 1, rounding = ROUNDING_UP } },
		},
		{ threshold = 3, format = tint(COLOR_YELLOW, "%d"), components = { { div = 1, step = 1, rounding = ROUNDING_UP } } },
		-- 10s .. mm:ss threshold: raw integer seconds (so e.g. "90" still shows).
		{ threshold = 10, format = tint(COLOR_DARK, "%d"), components = { { div = 1, step = 1, rounding = ROUNDING_UP } } },
		{ threshold = mmss, format = "%d:%02d", components = { { div = MINUTE }, { mod = MINUTE } } },
		{ threshold = MINUTE * 10, format = UnitFormat(colored, "m"), components = { { div = MINUTE, step = 1, rounding = ROUNDING_NEAREST } } },
		{ threshold = HOUR * 2, format = UnitFormat(colored, "h"), components = { { div = HOUR, step = 1, rounding = ROUNDING_NEAREST } } },
		{ threshold = DAY, format = UnitFormat(colored, "d"), components = { { div = DAY, step = 1, rounding = ROUNDING_NEAREST } } },
		{ threshold = WEEK, format = UnitFormat(colored, "w"), components = { { div = WEEK, step = 1, rounding = ROUNDING_NEAREST } } },
	}
end

-- One formatter shared by every cooldown. Switching styles just swaps its
-- breakpoints (no new allocations).
local formatter = C_StringUtil.CreateNumericRuleFormatter()

-- Weak keys: when a cooldown frame is collected, drop it from the set too.
local hookedCooldowns = setmetatable({}, { __mode = "k" })

-- Width of a default action-button cooldown; the scale baseline. Re-read in
-- InstallHooks once the template frame is available.
local SCALE_BASE = 36

local function GetStyle()
	return ns.db.cooldowns.style or 1
end

-- Scale the countdown text relative to the button size and hide it on buttons
-- that end up too small (so 1-pixel aura cooldowns don't show unreadable text).
local function UpdateCooldownTextScale(cooldown, width)
	local fs = cooldown:GetCountdownFontString()
	if not fs then
		return
	end

	if not ns.db.cooldowns.scaleText or not Cooldowns:IsEnabled() then
		fs:SetScale(1)
		fs:SetAlpha(1)
		return
	end

	local scale, alpha = 1, 1
	if width == nil then
		width = cooldown:GetWidth()
	end
	-- Width can be a 12.0 secret value on some cooldown frames; gate reads on it.
	if F.CanAccessValue(width) and width and width > 0 then
		scale = Round(width) / SCALE_BASE
		local minScale = ns.db.cooldowns.minScale or 0
		alpha = (Round(scale * 100) >= Round(minScale * 100)) and 1 or 0
	end
	fs:SetScale(scale)
	fs:SetAlpha(alpha)
end

-- HookScript passes (self, width, height); one shared handler, no per-frame
-- closure.
local function OnCooldownSizeChanged(cooldown, width)
	UpdateCooldownTextScale(cooldown, width)
end

-- On action buttons the cooldown text draws below the hotkey / stack count.
-- Reparent it into a high-frame-level container so it sits on top. Only action
-- buttons expose TextOverlayContainer, and reparenting is skipped in combat to
-- stay taint-safe (it retries on the next out-of-combat SetCooldown).
local function SetupTextContainer(cooldown)
	if cooldown.nexTextContainer or InCombatLockdown() then
		return
	end

	local parent = cooldown:GetParent()
	if not (parent and parent.TextOverlayContainer) then
		return
	end

	local fs = cooldown:GetCountdownFontString()
	if not fs then
		return
	end

	-- Park the countdown text on a very-high-level child so it always draws
	-- above the cooldown swipe/edge and the icon's own overlay textures.
	local container = CreateFrame("Frame", nil, cooldown)
	container:SetAllPoints(cooldown)
	container:SetFrameLevel(777)
	fs:SetParent(container)
	cooldown.nexTextContainer = container
end

-- Hook handler shared by all cooldown methods. hooksecurefunc passes the
-- cooldown as the first argument, so one function covers every frame.
--   `noCooldownCount` is the shared opt-out flag (OmniCC/tullaCTC convention):
--   frames marked with it - e.g. percentage-display swipes - are left alone.
local function OnCooldownSet(cooldown)
	if not cooldown or cooldown.noCooldownCount then
		return
	end
	if not Cooldowns:IsEnabled() then
		return
	end

	if not hookedCooldowns[cooldown] then
		hookedCooldowns[cooldown] = true
		cooldown:SetCountdownFormatter(formatter)
		cooldown:HookScript("OnSizeChanged", OnCooldownSizeChanged)
	end

	SetupTextContainer(cooldown)
	UpdateCooldownTextScale(cooldown, cooldown:GetWidth())
end

-- ---------------------------------------------------------------------------
-- Public methods
-- ---------------------------------------------------------------------------
function Cooldowns:ApplyBreakpoints()
	local info = styleInfo[GetStyle()] or styleInfo[1]
	formatter:SetBreakpoints(BuildBreakpoints(info.colored, info.decimals, ns.db.cooldowns.mmssThreshold))
end

--- Toggle the native countdown CVar and (re)apply the formatter to every
--- tracked cooldown. Called on enable and whenever a setting changes.
-- Snapshot the player's own countdownForCooldowns choice the first time we
-- touch it, so turning the module off restores their value instead of always
-- forcing it to "0".
local originalCountdownCVar

function Cooldowns:UpdateFormat()
	local enabled = self:IsEnabled()

	-- This CVar drives Blizzard's built-in cooldown numbers.
	if originalCountdownCVar == nil then
		originalCountdownCVar = GetCVar("countdownForCooldowns") or "0"
	end
	SetCVar("countdownForCooldowns", enabled and "1" or originalCountdownCVar)

	if enabled then
		self:ApplyBreakpoints()
	end

	for cooldown in pairs(hookedCooldowns) do
		cooldown:SetCountdownFormatter(enabled and formatter or nil)
		UpdateCooldownTextScale(cooldown, cooldown:GetWidth())
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
	builder:Slider(category, self, "mmssThreshold", L["Minutes Format Threshold"], L["Below this many seconds the countdown shows raw seconds; at or above it switches to mm:ss."], 60, 300, 5)
	builder:Checkbox(category, self, "scaleText", L["Scale Cooldown Text"], L["Scale the countdown text with the button size and hide it on very small cooldowns."])
	builder:Slider(category, self, "minScale", L["Minimum Text Scale"], L["Hide the countdown text once its scale drops below this fraction of a normal button (needs Scale Cooldown Text)."], 0, 1, 0.05)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function Cooldowns:InstallHooks()
	if self.hooksInstalled then
		return
	end

	-- All cooldown frames share one metatable; hooking it covers them all.
	local template = ActionButton1Cooldown
	if not template then
		return
	end

	self.hooksInstalled = true

	-- Baseline for relative text scaling: a default action button cooldown.
	local baseWidth = template:GetWidth()
	if baseWidth and baseWidth > 0 then
		SCALE_BASE = Round(baseWidth)
	end

	local cooldownMeta = getmetatable(template).__index
	local methods = {
		"SetCooldown",
		"SetCooldownDuration",
		"SetHideCountdownNumbers",
		"SetCooldownFromDurationObject",
		"SetCooldownFromExpirationTime",
		"SetCooldownUNIX",
	}
	for i = 1, #methods do
		if cooldownMeta[methods[i]] then
			hooksecurefunc(cooldownMeta, methods[i], OnCooldownSet)
		end
	end

	-- Percentage-display cooldowns (e.g. some enchant/aura swipes) want the
	-- swipe, not a numeric countdown. Flag them so OnCooldownSet skips them and
	-- hide any number Blizzard would otherwise draw.
	hooksecurefunc("CooldownFrame_SetDisplayAsPercentage", function(cooldown)
		if not cooldown or cooldown.noCooldownCount then
			return
		end
		cooldown.noCooldownCount = true
		cooldown:SetHideCountdownNumbers(true)
	end)
end

function Cooldowns:OnEnable()
	self:InstallHooks()
	self:UpdateFormat()
end
