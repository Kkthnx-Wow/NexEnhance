--[[
	NexEnhance - Cooldowns
	-------------------------------------------------------------------------
	Formats the numbers shown on cooldown swipes (action buttons, auras, items,
	etc.). Uses Blizzard's native SetCountdownFormatter API introduced in
	Midnight so the client does all per-frame rendering — we run zero OnUpdate
	timers of our own.

	Architecture
	  * Hook the shared Cooldown metatable once; every current and future
	    cooldown frame is covered with a handful of hooks.
	  * Each cooldown is tagged on first sighting so heavy init work (font,
	    formatter, size-changed hook, min-duration) only runs once per frame,
	    not on every subsequent SetCooldown event.
	  * UpdateFormat() handles the live-settings case (font, scale, formatter,
	    min-duration) for all already-tracked cooldowns when the user changes
	    a setting. OnCooldownSet itself is a cheap no-op after init.
	  * SetMinimumCountdownDuration suppresses text on GCDs and other
	    sub-threshold cooldowns so we only show text that is actually useful.
--]]

local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

-- Localised globals.
local C_StringUtil = C_StringUtil
local CreateColor = CreateColor
local hooksecurefunc = hooksecurefunc
local getmetatable = getmetatable
local SetCVar = SetCVar
local GetCVar = GetCVar
local pairs = pairs
local Enum = Enum
local C_Timer = C_Timer
local max = math.max
local min = math.min
local Round = Round or function(n)
	return math.floor(n + 0.5)
end

local ROUNDING_UP = Enum.NumericRuleFormatRounding.Up
local ROUNDING_NEAREST = Enum.NumericRuleFormatRounding.Nearest

-- Threshold colours: red under 3s, yellow under 10s, then a calmer tone.
local COLOR_RED = CreateColor(1, 0, 0, 1)
local COLOR_YELLOW = CreateColor(1, 1, 0, 1)
local COLOR_DARK = CreateColor(0.8, 0.8, 0.2, 1)

-- Colour escape applied to the m/h/d unit suffix (uses the class colour).
local UNIT = "|c" .. F.RGBToHex(C.ClassColor)
local R = "|r"

-- ---------------------------------------------------------------------------
-- Defaults & module
-- ---------------------------------------------------------------------------
ns:RegisterDefaults({
	cooldowns = {
		enable = true,
		style = 1, -- 1 colored+decimals, 2 colored, 3 plain+decimals, 4 plain
		mmssThreshold = 90, -- seconds: below this show raw seconds, then mm:ss
		minDuration = 3, -- hide text for cooldowns shorter than this many seconds
		scaleText = true, -- scale countdown text with button/cooldown width
		minScale = 0.5, -- hide text once relative scale drops below this
		fontSize = 15,
		fontOutline = "OUTLINE",
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

-- 12.0.7 SetFont rejects "NONE"; omit flags or pass "" instead.
local function NormalizeFontFlags(flags)
	if not flags or flags == "NONE" or flags == "None" then
		return ""
	end
	return flags
end

local function SetCountdownFontString(fs, fontSize, flags)
	flags = NormalizeFontFlags(flags)
	if flags == "" then
		fs:SetFont(C.Media.Fonts.number, fontSize)
	else
		fs:SetFont(C.Media.Fonts.number, fontSize, flags)
	end
end

local function ResolveCooldownWidth(cooldown)
	local width = cooldown:GetWidth()
	if F.CanAccessValue(width) and width and width > 0 then
		return width
	end
	local parent = cooldown:GetParent()
	if parent then
		width = parent:GetWidth()
		if F.CanAccessValue(width) and width and width > 0 then
			return width
		end
	end
	return nil
end

-- Width of the cooldown (or its parent button) times ancestor SetScale factors.
local function GetCooldownScaleFactor(cooldown)
	local factor = 1
	local width = ResolveCooldownWidth(cooldown)
	if width then
		factor = width / SCALE_BASE
	end
	local frame = cooldown:GetParent()
	while frame and frame ~= UIParent do
		local s = frame:GetScale()
		if F.CanAccessValue(s) and s then
			factor = factor * s
		end
		frame = frame:GetParent()
	end
	return factor
end

-- Apply font size, optional button scaling, and visibility on tiny cooldowns.
local function ApplyFont(cooldown)
	local fs = cooldown:GetCountdownFontString()
	if not fs then
		return
	end

	local cfg = ns.db.cooldowns
	local fontSize = cfg.fontSize or 15
	local flags = cfg.fontOutline

	if cfg.scaleText and Cooldowns:IsEnabled() then
		local factor = GetCooldownScaleFactor(cooldown)
		local minScale = cfg.minScale or 0
		if factor < minScale then
			fs:SetAlpha(0)
			return
		end
		fs:SetAlpha(1)
		fs:SetScale(1)
		fontSize = Round(max(8, min(40, fontSize * factor)))
	else
		fs:SetScale(1)
		fs:SetAlpha(1)
	end

	SetCountdownFontString(fs, fontSize, flags)
end

-- Apply the minimum-duration threshold. The client suppresses countdown text
-- for cooldowns shorter than this, keeping e.g. 1.5s GCDs quiet.
local function ApplyMinDuration(cooldown)
	if cooldown.SetMinimumCountdownDuration then
		cooldown:SetMinimumCountdownDuration(ns.db.cooldowns.minDuration or 3)
	end
end

-- HookScript passes (self, width, height); one shared handler, no per-frame
-- closure.
local function OnCooldownSizeChanged(cooldown)
	ApplyFont(cooldown)
end

-- Hook handler shared by all cooldown methods. hooksecurefunc passes the
-- cooldown as the first argument (extra args like start/duration are secret
-- values in Midnight — we intentionally ignore them here).
--
-- `noCooldownCount` is the shared opt-out flag other cooldown addons use too:
-- frames marked with it - e.g. percentage-display swipes - are left alone.
--
-- IMPORTANT: after the first sighting (init block) this function becomes a
-- cheap three-check no-op. All the heavy per-cooldown work lives in init and
-- in UpdateFormat (for live settings changes). The old code ran SetFont +
-- GetWidth + SetScale on every single SetCooldown call, which fires on every
-- GCD and every ability press.
local function OnCooldownSet(cooldown, arg2)
	if not cooldown or cooldown.noCooldownCount then
		return
	end
	if not Cooldowns:IsEnabled() then
		return
	end
	-- SetCooldown passes (start, duration) numbers; only DurationObject hooks
	-- carry a maskable object in arg2 (SetCooldownFromDurationObject, etc.).
	local argType = type(arg2)
	if (argType == "table" or argType == "userdata") and arg2.IsZero then
		F.MaskCooldownSwipeFromDurationObject(cooldown, arg2)
	end
	if hookedCooldowns[cooldown] then
		-- Blizzard may reset the countdown FontString each tick; keep our size.
		ApplyFont(cooldown)
		return
	end

	-- First sighting: set up the formatter, font, min-duration and size hook.
	hookedCooldowns[cooldown] = true
	cooldown:SetCountdownFormatter(formatter)
	ApplyFont(cooldown)
	ApplyMinDuration(cooldown)
	cooldown:HookScript("OnSizeChanged", OnCooldownSizeChanged)
	if ns.db.cooldowns.scaleText then
		-- Cooldown width is often 0 on the first SetCooldown; re-measure next frame.
		C_Timer.After(0, function()
			if cooldown and hookedCooldowns[cooldown] then
				ApplyFont(cooldown)
			end
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Public methods
-- ---------------------------------------------------------------------------
function Cooldowns:ApplyBreakpoints()
	local info = styleInfo[GetStyle()] or styleInfo[1]
	formatter:SetBreakpoints(BuildBreakpoints(info.colored, info.decimals, ns.db.cooldowns.mmssThreshold))
end

--- Toggle the native countdown CVar and (re)apply all settings to every
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
		if enabled then
			ApplyFont(cooldown)
			ApplyMinDuration(cooldown)
		end
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
	builder:Slider(category, self, "fontSize", L["Font Size"], L["Set the font size for the cooldown countdown text."], 10, 24, 1)
	builder:Dropdown(category, self, "fontOutline", L["Font Outline"], L["Set the outline style for the cooldown countdown text."], {
		{ value = "NONE", label = L["None"] },
		{ value = "OUTLINE", label = L["Outline"] },
		{ value = "THICKOUTLINE", label = L["Thick Outline"] },
		{ value = "MONOCHROME", label = L["Monochrome"] },
	})
	builder:Slider(category, self, "mmssThreshold", L["Minutes Format Threshold"], L["Below this many seconds the countdown shows raw seconds; at or above it switches to mm:ss."], 60, 300, 5)
	builder:Slider(category, self, "minDuration", L["Minimum Cooldown Duration"], L["Hide countdown text for cooldowns shorter than this many seconds. Keeps 1.5s GCDs and other short cooldowns quiet."], 0, 10, 0.5)
	builder:Checkbox(category, self, "scaleText", L["Scale Cooldown Text"], L["Grow or shrink countdown numbers with the button size. Turn off for a fixed font size on every cooldown."])
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
