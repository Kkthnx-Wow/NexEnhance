--[[
	NexEnhance - ActionBars
	-------------------------------------------------------------------------
	Restyles the default action buttons: abbreviates hotkey text, applies the
	framework font, and toggles macro name / stack count visibility from the
	active profile.

	Notes on the approach (per the best-practice reports):
	  * The replacement and button-set tables are built once at file scope, not
	    rebuilt on every refresh, so styling allocates nothing.
	  * A shared (non-anonymous) hook handler is reused for every hotkey to
	    avoid one closure per button.
	  * Each hotkey's SetText is hooked at most once (guarded by a flag) so
	    repeated refreshes never stack secure hooks.
	  * hooksecurefunc is used instead of overriding SetText, keeping the path
	    taint-free.
--]]

local _, ns = ...
local C, L = ns.C, ns.L

-- Localised globals (hot-path friendly).
local _G = _G
local ipairs = ipairs
local gsub = string.gsub
local hooksecurefunc = hooksecurefunc

local KEY_BUTTON4, KEY_NUMPAD1, RANGE_INDICATOR = KEY_BUTTON4, KEY_NUMPAD1, RANGE_INDICATOR
local KEY_BUTTON3, KEY_SPACE = KEY_BUTTON3, KEY_SPACE
local KEY_MOUSEWHEELUP, KEY_MOUSEWHEELDOWN = KEY_MOUSEWHEELUP, KEY_MOUSEWHEELDOWN

local FONT_NORMAL = C.Media.Fonts.normal
local FONT_NUMBER = C.Media.Fonts.number

-- ---------------------------------------------------------------------------
-- Defaults & module
-- ---------------------------------------------------------------------------
ns:RegisterDefaults({
	actionbars = {
		enable = true,
		showName = false,
		showCount = true,
		showHotkey = true,
		nameSize = 12,
		countSize = 14,
		hotkeySize = 12,
	},
})

local ActionBars = ns:NewModule("ActionBars", "actionbars", { group = "actionbars", title = L["Action Bars"], order = 10 })

-- ---------------------------------------------------------------------------
-- Hotkey abbreviation
--   Built once. Localised key names (e.g. KEY_BUTTON4) are stripped of their
--   trailing digit so a single rule covers all numbered variants.
-- ---------------------------------------------------------------------------
local keyButton = gsub(KEY_BUTTON4 or "", "%d", "")
local keyNumpad = gsub(KEY_NUMPAD1 or "", "%d", "")

local replaces = {
	{ "(" .. keyButton .. ")", "M" },
	{ "(" .. keyNumpad .. ")", "N" },
	{ "(a%-)", "a" },
	{ "(c%-)", "c" },
	{ "(s%-)", "s" },
	{ KEY_BUTTON3 or "", "M3" },
	{ KEY_MOUSEWHEELUP or "", "MU" },
	{ KEY_MOUSEWHEELDOWN or "", "MD" },
	{ KEY_SPACE or "", "Sp" },
	{ "CAPSLOCK", "CL" },
	{ "Capslock", "CL" },
	{ "BUTTON", "M" },
	{ "NUMPAD", "N" },
	{ "(ALT%-)", "a" },
	{ "(CTRL%-)", "c" },
	{ "(SHIFT%-)", "s" },
	{ "MOUSEWHEELUP", "MU" },
	{ "MOUSEWHEELDOWN", "MD" },
	{ "SPACE", "Sp" },
}

function ActionBars:UpdateHotKey(hotkey)
	if not hotkey then return end

	local text = hotkey:GetText()
	if not text or text == "" then return end

	if text == RANGE_INDICATOR then
		text = ""
	else
		for i = 1, #replaces do
			local rule = replaces[i]
			text = gsub(text, rule[1], rule[2])
		end
	end

	-- SetFormattedText does not fire the SetText hook, so no recursion.
	hotkey:SetFormattedText("%s", text)
end

-- Shared hook handler: hooksecurefunc passes the hooked object as the first
-- argument, so one function serves every hotkey (no per-button closure).
local function OnHotKeySetText(hotkey)
	ActionBars:UpdateHotKey(hotkey)
end

-- ---------------------------------------------------------------------------
-- Button styling
-- ---------------------------------------------------------------------------
local function StyleActionButton(button, config)
	if not button then return end

	local count = button.Count
	local hotkey = button.HotKey
	local name = button.Name
	local slotbg = button.SlotBackground

	if name then
		name:SetShown(config.showName)
		if config.showName then
			name:SetFont(FONT_NORMAL, config.nameSize, "OUTLINE")
		end
		name:ClearAllPoints()
		name:SetPoint("BOTTOMLEFT", 0, 0)
		name:SetPoint("BOTTOMRIGHT", 0, 0)
	end

	if slotbg then
		slotbg:SetAtlas("UI-HUD-ActionBar-IconFrame-Slot")
	end

	if count then
		count:SetShown(config.showCount)
		if config.showCount then
			count:SetFont(FONT_NUMBER, config.countSize, "OUTLINE")
		end
		count:ClearAllPoints()
		count:SetPoint("BOTTOMRIGHT", 2, 0)
	end

	if hotkey then
		hotkey:SetShown(config.showHotkey)
		if config.showHotkey then
			hotkey:SetFont(FONT_NORMAL, config.hotkeySize, "OUTLINE")
		end
		hotkey:ClearAllPoints()
		hotkey:SetPoint("TOPRIGHT", 0, -3)
		hotkey:SetPoint("TOPLEFT", 0, -3)

		ActionBars:UpdateHotKey(hotkey)

		-- Hook once per hotkey so refreshes never stack secure hooks.
		if not hotkey.nexHotkeyHooked then
			hotkey.nexHotkeyHooked = true
			hooksecurefunc(hotkey, "SetText", OnHotKeySetText)
		end
	end
end

-- Built once: prefix + count for every default action-button family.
local actionButtonSets = {
	{ prefix = "ActionButton", count = 12 },
	{ prefix = "MultiBarBottomLeftButton", count = 12 },
	{ prefix = "MultiBarLeftButton", count = 12 },
	{ prefix = "MultiBarRightButton", count = 12 },
	{ prefix = "MultiBarBottomRightButton", count = 12 },
	{ prefix = "MultiBar5Button", count = 12 },
	{ prefix = "MultiBar6Button", count = 12 },
	{ prefix = "MultiBar7Button", count = 12 },
	{ prefix = "StanceButton", count = 10 },
	{ prefix = "PetActionButton", count = 10 },
}

function ActionBars:RefreshActionBarStyling()
	if not self:IsEnabled() then return end

	local config = ns.db.actionbars

	for _, set in ipairs(actionButtonSets) do
		local prefix = set.prefix
		for i = 1, set.count do
			local button = _G[prefix .. i]
			if button then
				StyleActionButton(button, config)
			end
		end
	end

	if ExtraActionButton1 then
		StyleActionButton(ExtraActionButton1, config)
	end
end

--- Re-apply styling after a settings change (called from the options panel).
function ActionBars:UpdateStylingConfig()
	self:RefreshActionBarStyling()
end

function ActionBars:OnSettingChanged(key, value)
	-- Most action-bar appearance settings are safe to apply immediately. A
	-- full disable cannot unhook secure post-hooks, but re-enabling can restyle
	-- right away.
	if key == "enable" and not value then return end
	if key == "enable" and value then
		self:RegisterModuleEvents()
	end
	self:RefreshActionBarStyling()
end

function ActionBars:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Action Bars"], L["Style Blizzard action buttons and abbreviate hotkeys."])
	builder:Checkbox(category, self, "showName", L["Show Macro Names"], L["Show macro/action names on action buttons."])
	builder:Checkbox(category, self, "showCount", L["Show Counts"], L["Show stack counts and charges on action buttons."])
	builder:Checkbox(category, self, "showHotkey", L["Show Hotkeys"], L["Show abbreviated keybind text on action buttons."])

	builder:Slider(category, self, "nameSize", L["Macro Name Size"], L["Font size for macro/action names."], 8, 24, 1)
	builder:Slider(category, self, "countSize", L["Count Size"], L["Font size for stack counts and charges."], 8, 28, 1)
	builder:Slider(category, self, "hotkeySize", L["Hotkey Size"], L["Font size for keybind text."], 8, 24, 1)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function ActionBars:RegisterModuleEvents()
	if self.eventsRegistered then return end
	self.eventsRegistered = true

	-- Re-style when bars are toggled/created (e.g. entering/leaving a vehicle
	-- or when the player enables extra bars). Cheap and event-driven.
	self:RegisterEvent("UPDATE_BINDINGS", "RefreshActionBarStyling")
	self:RegisterEvent("ACTIONBAR_PAGE_CHANGED", "RefreshActionBarStyling")
end

function ActionBars:OnEnable()
	self:RefreshActionBarStyling()
	self:RegisterModuleEvents()
end
