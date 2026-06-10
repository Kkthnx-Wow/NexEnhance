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
local InCombatLockdown = InCombatLockdown

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
		skinExtraButtons = true,
		extraButtonScale = 120,
		nameSize = 12,
		countSize = 14,
		hotkeySize = 12,
	},
})

local ActionBars = ns:NewModule("ActionBars", "actionbars", { group = "actionbars", title = L["Action Bars"], order = 10 })
local zoneAbilityHooked

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

-- raw keybind text -> abbreviated form. The set of possible keybind strings is
-- tiny and bounded, so this memo turns the 19-rule gsub pass into a single
-- table lookup on every refresh after the first sighting of each bind.
local hotkeyCache = {}

function ActionBars:UpdateHotKey(hotkey)
	if not hotkey then
		return
	end

	local text = hotkey:GetText()
	if not text or text == "" then
		return
	end

	local abbr = hotkeyCache[text]
	if not abbr then
		if text == RANGE_INDICATOR then
			abbr = ""
		else
			abbr = text
			for i = 1, #replaces do
				local rule = replaces[i]
				abbr = gsub(abbr, rule[1], rule[2])
			end
		end
		hotkeyCache[text] = abbr
	end

	-- SetFormattedText does not fire the SetText hook, so no recursion. Skip the
	-- write when the text already matches (nothing to abbreviate).
	if abbr ~= text then
		hotkey:SetFormattedText("%s", abbr)
	end
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
	if not button then
		return
	end

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

-- Blizzard's standard action-button chrome (see
-- BaseActionButtonMixin:UpdateButtonArt). The IconFrame atlas is 46x45 over a
-- 45px button, so we keep that slight horizontal overhang when scaling to the
-- larger Extra Action / Zone Ability buttons.
local HUD_ICON_FRAME = "UI-HUD-ActionBar-IconFrame"
local HUD_ICON_FRAME_DOWN = "UI-HUD-ActionBar-IconFrame-Down"
local HUD_ICON_FRAME_SLOT = "UI-HUD-ActionBar-IconFrame-Slot"
local FRAME_WIDTH_RATIO = 46 / 45
local FRAME_TINT = C.Colors.yellow -- gold border to make the special buttons pop

local function SetStyleRegionHidden(region, hidden)
	if region then
		region:SetAlpha(hidden and 0 or 1)
	end
end

local function SizeArtTexture(texture, button)
	if not texture then
		return
	end
	local w, h = button:GetSize()
	if not w or w == 0 then
		w = 45
	end
	if not h or h == 0 then
		h = 45
	end
	texture:SetDrawLayer("OVERLAY")
	texture:ClearAllPoints()
	texture:SetPoint("CENTER", button, "CENTER", 0, 0)
	texture:SetSize(w * FRAME_WIDTH_RATIO, h)
	texture:SetVertexColor(FRAME_TINT[1], FRAME_TINT[2], FRAME_TINT[3])
end

-- The Extra Action icon is drawn larger than its button and anchored top-left,
-- so it spills past our button-sized frame. Pin it to the button so the icon and
-- the gold frame share the same bounds (matching the default buttons).
local function NormalizeButtonIcon(button)
	local icon = button.icon or button.Icon
	if not icon then
		return
	end
	icon:SetDrawLayer("ARTWORK")
	icon:ClearAllPoints()
	icon:SetAllPoints(button)
	-- Crop the baked-in icon edge so the art sits cleanly inside the gold frame.
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

-- Dress a special button (Extra Action / Zone Ability) in the same HUD art the
-- default action buttons use, so it stops looking like a one-off.
local function ApplyHudButtonArt(button)
	if not button or not button.SetNormalAtlas then
		return
	end

	NormalizeButtonIcon(button)

	button:SetNormalAtlas(HUD_ICON_FRAME)
	SizeArtTexture(button:GetNormalTexture(), button)

	button:SetPushedAtlas(HUD_ICON_FRAME_DOWN)
	SizeArtTexture(button:GetPushedTexture(), button)

	if not button.nexSlotArt then
		local slot = button:CreateTexture(nil, "BACKGROUND")
		slot:SetAtlas(HUD_ICON_FRAME_SLOT)
		slot:SetAllPoints(button)
		button.nexSlotArt = slot
	end
	button.nexSlotArt:Show()
end

local function RemoveHudButtonArt(button)
	if button and button.nexSlotArt then
		button.nexSlotArt:Hide()
	end
end

-- SetScale is a protected method on these secure buttons, so it can only be
-- changed out of combat. A change requested in combat is flagged and re-applied
-- on PLAYER_REGEN_ENABLED.
local function ApplyButtonScale(button)
	if not button then
		return
	end

	if InCombatLockdown() then
		ActionBars.pendingScale = true
		return
	end

	local scale = (ns.db.actionbars.extraButtonScale or 100) / 100
	button:SetScale(scale)
end

local function StyleSpecialButton(button, enabled, styleRegion)
	if not button then
		return
	end

	SetStyleRegionHidden(styleRegion, enabled)

	if enabled then
		ApplyHudButtonArt(button)
	else
		RemoveHudButtonArt(button)
	end

	ApplyButtonScale(button)
end

local function StyleExtraActionArt(config)
	local button = ExtraActionButton1
	if not button then
		return
	end

	StyleSpecialButton(button, config.skinExtraButtons, button.style)
end

function ActionBars:StyleZoneAbilityArt()
	local frame = _G["ZoneAbilityFrame"]
	if not frame then
		return
	end

	local enabled = ns.db.actionbars.skinExtraButtons
	-- The frame-level Style is the surrounding decoration; the actual spell
	-- buttons live in a pooled container and get the HUD art instead.
	SetStyleRegionHidden(frame.Style, enabled)

	local container = frame.SpellButtonContainer
	if container and container.EnumerateActive then
		for button in container:EnumerateActive() do
			StyleSpecialButton(button, enabled, button.Style)
		end
	end

	if not zoneAbilityHooked and frame.UpdateDisplayedZoneAbilities then
		zoneAbilityHooked = true
		hooksecurefunc(frame, "UpdateDisplayedZoneAbilities", function()
			ActionBars:StyleZoneAbilityArt()
		end)
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
	if not self:IsEnabled() then
		return
	end

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

	StyleExtraActionArt(config)
	self:StyleZoneAbilityArt()
end

--- Re-apply styling after a settings change (called from the options panel).
function ActionBars:UpdateStylingConfig()
	self:RefreshActionBarStyling()
end

function ActionBars:OnSettingChanged(key, value)
	-- Most action-bar appearance settings are safe to apply immediately. A
	-- full disable cannot unhook secure post-hooks, but re-enabling can restyle
	-- right away.
	if key == "enable" and not value then
		return
	end
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
	builder:Checkbox(category, self, "skinExtraButtons", L["Skin Extra Buttons"], L["Give the Extra Action and Zone Ability buttons the standard action-bar button frame (reload to restore Blizzard's art)."])

	builder:Slider(category, self, "extraButtonScale", L["Extra Button Scale"], L["Scale of the Extra Action and Zone Ability buttons, as a percent (applied out of combat)."], 100, 200, 1)

	builder:Slider(category, self, "nameSize", L["Macro Name Size"], L["Font size for macro/action names."], 8, 24, 1)
	builder:Slider(category, self, "countSize", L["Count Size"], L["Font size for stack counts and charges."], 8, 28, 1)
	builder:Slider(category, self, "hotkeySize", L["Hotkey Size"], L["Font size for keybind text."], 8, 24, 1)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function ActionBars:RegisterModuleEvents()
	if self.eventsRegistered then
		return
	end
	self.eventsRegistered = true

	-- Re-style when bars are toggled/created (e.g. entering/leaving a vehicle
	-- or when the player enables extra bars). Cheap and event-driven.
	self:RegisterEvent("UPDATE_BINDINGS", "RefreshActionBarStyling")
	self:RegisterEvent("ACTIONBAR_PAGE_CHANGED", "RefreshActionBarStyling")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "RefreshActionBarStyling")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- Re-apply any scale change that was blocked while in combat.
function ActionBars:PLAYER_REGEN_ENABLED()
	if self.pendingScale then
		self.pendingScale = nil
		self:RefreshActionBarStyling()
	end
end

function ActionBars:OnEnable()
	self:RefreshActionBarStyling()
	self:RegisterModuleEvents()
end
