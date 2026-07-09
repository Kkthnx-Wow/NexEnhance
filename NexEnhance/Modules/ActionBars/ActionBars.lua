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
local C, L, F = ns.C, ns.L, ns.F

-- Localised globals (hot-path friendly).
local _G = _G
local ipairs = ipairs
local wipe = wipe
local gsub = string.gsub
local hooksecurefunc = hooksecurefunc
local InCombatLockdown = InCombatLockdown
local UnitExists = UnitExists
local C_Timer = C_Timer
-- NOTE: UIFrameFadeIn / UIFrameFadeOut are intentionally NOT used here.
-- In Midnight 12.0, action bar frames (MultiBarLeft, etc.) are
-- EditModeActionBarMixin instances whose Show() method is overridden to
-- ShowOverride(). UIFrameFade() always calls frame:Show() after setting
-- alpha, which triggers ShowOverride() → UpdateVisibility() → HideBase()
-- (the saved, protected C-level Hide). Calling a protected function from
-- addon-tainted code produces ADDON_ACTION_BLOCKED, and that taint then
-- spreads to Blizzard's own ActionButton_UpdateCooldown in the same tick,
-- causing the secondary "Secret values only allowed during untainted
-- execution" error on SetCooldown. We use our own FadeBar() instead, which
-- only ever touches SetAlpha() and never calls Show() or Hide().

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
		equipGlow = true,
		extraButtonScale = 120,
		nameSize = 12,
		countSize = 14,
		hotkeySize = 12,
		-- Mouseover options
		fadedAlpha = 0,
		mouseoverShowAll = false,
		visibilityMain = "ALWAYS",
		visibilityBottomLeft = "ALWAYS",
		visibilityBottomRight = "ALWAYS",
		visibilityRight = "ALWAYS",
		visibilityLeft = "ALWAYS",
		visibilityBar5 = "ALWAYS",
		visibilityBar6 = "ALWAYS",
		visibilityBar7 = "ALWAYS",
		visibilityPet = "ALWAYS",
		visibilityStance = "ALWAYS",
	},
})

local ActionBars = ns:NewModule("ActionBars", "actionbars", { group = "actionbars", title = L["Action Bars"], order = 10 })
local eventHandles = {}
local zoneAbilityHooked
local pendingStyling = false

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
	-- hooksecurefunc stays forever — gate when Action Bars is off.
	if not self:IsEnabled() or not hotkey then
		return
	end

	local text = hotkey:GetText()
	if not text or text == "" or F.IsSecret(text) then
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
	if abbr ~= text and not F.IsSecret(abbr) then
		hotkey:SetFormattedText("%s", abbr)
	end
end

-- Shared hook handler: hooksecurefunc passes the hooked object as the first
-- argument, so one function serves every hotkey (no per-button closure).
local function OnHotKeySetText(hotkey)
	if InCombatLockdown() then
		return
	end
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
local HUD_ICON_FRAME_MOUSEOVER = "UI-HUD-ActionBar-IconFrame-Mouseover"
-- Same mask Blizzard's ActionButtonTemplate/ExtraActionBar use to round the icon
-- to the IconFrame opening (CLAMPTOBLACKADDITIVE in the XML).
local HUD_ICON_MASK = "UI-HUD-ActionBar-IconFrame-Mask"
local FRAME_WIDTH_RATIO = 46 / 45
-- Blizzard draws the 64px mask atlas centered over a 45px icon (and 76 over the
-- 52px Extra Action button), i.e. the mask is ~1.42x larger than the icon so its
-- feathered border sits outside the icon. Match that ratio or the icon shrinks.
local MASK_SIZE_RATIO = 64 / 45

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
end

-- The Extra Action icon is drawn larger than its button and anchored top-left,
-- so it spills past our button-sized frame. Pin it to the button so the icon and
-- the gold frame share the same bounds (matching the default buttons), then round
-- it with the HUD icon mask so the corners can't poke past the rounded frame.
local function NormalizeButtonIcon(button)
	local icon = button.icon or button.Icon
	if not icon then
		return
	end
	icon:SetDrawLayer("ARTWORK")
	icon:ClearAllPoints()
	icon:SetAllPoints(button)
	icon:SetTexCoord(0, 1, 0, 1)

	-- Mask the icon like Blizzard's ActionButtonTemplate instead of a square
	-- texcoord crop, so the rounded gold frame fully contains the art. The mask
	-- is sized larger than the icon (Blizzard's 64/45 ratio) and centered, so the
	-- icon fills the frame instead of shrinking inside the mask's feathered edge.
	if not button.nexIconMask then
		local mask = button:CreateMaskTexture(nil, "ARTWORK")
		mask:SetAtlas(HUD_ICON_MASK)
		icon:AddMaskTexture(mask)
		button.nexIconMask = mask
	end
	local w, h = button:GetSize()
	if not w or w == 0 then
		w = 45
	end
	if not h or h == 0 then
		h = 45
	end
	button.nexIconMask:ClearAllPoints()
	button.nexIconMask:SetPoint("CENTER", button, "CENTER", 0, 0)
	button.nexIconMask:SetSize(w * MASK_SIZE_RATIO, h * MASK_SIZE_RATIO)
	button.nexIconMask:Show()
end

-- The Extra Action button hovers with an additive blue glow; the regular bars use
-- this same atlas at full strength with no additive blend. Match the bars so a
-- skinned special button hovers like the rest of the action bar.
local function NormalizeButtonHighlight(button)
	local highlight = button:GetHighlightTexture()
	if not highlight then
		return
	end
	highlight:SetAtlas(HUD_ICON_FRAME_MOUSEOVER)
	highlight:SetBlendMode("BLEND")
	highlight:SetAlpha(1)

	local w, h = button:GetSize()
	if not w or w == 0 then
		w = 45
	end
	if not h or h == 0 then
		h = 45
	end
	highlight:ClearAllPoints()
	highlight:SetPoint("CENTER", button, "CENTER", 0, 0)
	highlight:SetSize(w * FRAME_WIDTH_RATIO, h)
end

-- Dress a special button (Extra Action / Zone Ability) in the same HUD art the
-- default action buttons use, so it stops looking like a one-off.
local function ApplyHudButtonArt(button)
	if not button or not button.SetNormalAtlas then
		return
	end

	NormalizeButtonIcon(button)
	NormalizeButtonHighlight(button)

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
	if not button then
		return
	end
	if button.nexSlotArt then
		button.nexSlotArt:Hide()
	end
	if button.nexIconMask then
		local icon = button.icon or button.Icon
		if icon then
			icon:RemoveMaskTexture(button.nexIconMask)
		end
		button.nexIconMask:Hide()
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
	if InCombatLockdown() then
		pendingStyling = true
		return
	end

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

-- ---------------------------------------------------------------------------
-- Equipped-item border
--   Blizzard marks an action that holds an equipped item with its IconFrame
--   Border atlas vertex-coloured a faint green (see ActionBarActionButtonMixin:Update
--   -> self.Border, colour 0,1,0,0.5). We draw our own copy of that same border art
--   (UI-HUD-ActionBar-IconFrame-Border, the atlas the gold frame uses) at full green
--   so it matches our skin and reads clearly. Post-hooking the shared mixin keeps us
--   on the correct, taint-free path and covers every action button at once; the
--   handler runs only when an action changes (event-driven), and the work is trivial.
-- ---------------------------------------------------------------------------
local EQUIP_BORDER_ATLAS = "UI-HUD-ActionBar-IconFrame-Border"

local function GetEquipGlow(button)
	local glow = button.nexEquipGlow
	if not glow then
		-- Creating child textures on secure action buttons is blocked in combat.
		if InCombatLockdown() then
			return nil
		end
		glow = button:CreateTexture(nil, "OVERLAY", nil, 7)
		glow:SetAtlas(EQUIP_BORDER_ATLAS)
		glow:SetBlendMode("BLEND")
		glow:SetVertexColor(0, 1, 0)
		glow:SetPoint("CENTER", button, "CENTER", 0, 0)
		local _, h = button:GetSize()
		if not h or h == 0 then
			h = 45
		end
		-- Grow 2px on every edge over the button, and keep the width 1px wider than
		-- the height (matches the IconFrame art's slight horizontal overhang).
		local size = h + 4
		glow:SetSize(size + 1, size)
		glow:Hide()
		button.nexEquipGlow = glow
	end
	return glow
end

-- Post-hook for ActionBarActionButtonMixin:Update (and our refresh pass). Blizzard
-- sets Border show/hide in the same Update() immediately before this hook runs.
-- Do NOT call C_ActionBar.IsEquippedAction here — SecretArguments
-- AllowedWhenUntainted means tainted addon code can get a secret boolean and we
-- would early-return with a stale glow still visible.
local function ApplyEquipGlow(button)
	if InCombatLockdown() then
		pendingStyling = true
		return
	end

	local border = button.Border
	if not border then
		return
	end

	local borderVisible = border:IsShown()
	if F.IsSecret(borderVisible) then
		if button.nexEquipGlow then
			button.nexEquipGlow:Hide()
		end
		return
	end

	if ns.db.actionbars.equipGlow and borderVisible then
		border:Hide()
		local glow = GetEquipGlow(button)
		if glow then
			glow:Show()
		end
		return
	end

	if button.nexEquipGlow then
		button.nexEquipGlow:Hide()
	end
	if borderVisible then
		border:SetVertexColor(0, 1.0, 0, 0.5)
		border:Show()
	end
end

-- ---------------------------------------------------------------------------
-- Safe alpha fade (SetAlpha-only, no Show/Hide)
--   A minimal OnUpdate-based fader that only ever calls frame:SetAlpha().
--   This is the correct approach for Midnight 12.0 action bar frames, which
--   override Show()/Hide() with protected secure functions. UIFrameFadeIn/Out
--   call frame:Show() internally and must never be used on these frames.
-- ---------------------------------------------------------------------------
local activeFades = {} -- frame -> { start, target, duration, elapsed }

local fadeFrame = CreateFrame("Frame")

local function FadeFrame_OnUpdate(self, elapsed)
	local anyActive = false
	for frame, info in pairs(activeFades) do
		info.elapsed = info.elapsed + elapsed
		local progress = math.min(info.elapsed / info.duration, 1.0)
		frame:SetAlpha(info.start + (info.target - info.start) * progress)
		if progress >= 1.0 then
			activeFades[frame] = nil
		else
			anyActive = true
		end
	end
	if not anyActive then
		self:SetScript("OnUpdate", nil)
	end
end

--- Fade `frame` toward `targetAlpha` over `duration` seconds using only
--- SetAlpha. Cancels any in-progress fade for the same frame. Safe to call on
--- EditModeActionBarMixin frames where Show()/Hide() are protected.
local function FadeBar(frame, targetAlpha, duration)
	local current = frame:GetAlpha()
	if math.abs(current - targetAlpha) < 0.002 then
		activeFades[frame] = nil -- cancel any stale pending fade
		return
	end
	if not duration or duration <= 0 then
		frame:SetAlpha(targetAlpha)
		activeFades[frame] = nil
		return
	end
	local wasEmpty = not next(activeFades)
	activeFades[frame] = { start = current, target = targetAlpha, duration = duration, elapsed = 0 }
	if wasEmpty then
		fadeFrame:SetScript("OnUpdate", FadeFrame_OnUpdate)
	end
end

-- ---------------------------------------------------------------------------
-- Mouseover & Visibility
-- ---------------------------------------------------------------------------
local actionBarsInfo = {
	{ name = "MainMenuBar", key = "visibilityMain", prefix = "ActionButton", count = 12 },
	{ name = "MultiBarBottomLeft", key = "visibilityBottomLeft", prefix = "MultiBarBottomLeftButton", count = 12 },
	{ name = "MultiBarBottomRight", key = "visibilityBottomRight", prefix = "MultiBarBottomRightButton", count = 12 },
	{ name = "MultiBarRight", key = "visibilityRight", prefix = "MultiBarRightButton", count = 12 },
	{ name = "MultiBarLeft", key = "visibilityLeft", prefix = "MultiBarLeftButton", count = 12 },
	{ name = "MultiBar5", key = "visibilityBar5", prefix = "MultiBar5Button", count = 12 },
	{ name = "MultiBar6", key = "visibilityBar6", prefix = "MultiBar6Button", count = 12 },
	{ name = "MultiBar7", key = "visibilityBar7", prefix = "MultiBar7Button", count = 12 },
	{ name = "PetActionBar", key = "visibilityPet", prefix = "PetActionButton", count = 10 },
	{ name = "StanceBar", key = "visibilityStance", prefix = "StanceButton", count = 10 },
}

local function IsFrameOrChildrenHovered(barInfo)
	local barFrame = _G[barInfo.name]
	if barFrame and barFrame:IsShown() and barFrame:IsMouseOver() then
		return true
	end
	for i = 1, barInfo.count do
		local button = _G[barInfo.prefix .. i]
		if button and button:IsShown() and button:IsMouseOver() then
			return true
		end
	end
	return false
end

function ActionBars:UpdateMouseoverVisibility()
	if not self:IsEnabled() then
		return
	end

	local config = ns.db.actionbars
	local inCombat = InCombatLockdown()
	local hasTarget = UnitExists("target")

	local isFlyoutOpen = _G.SpellFlyout and _G.SpellFlyout:IsShown()
	local flyoutOwnerButton = isFlyoutOpen and _G.SpellFlyout:GetParent()
	local isFlyoutHovered = isFlyoutOpen and _G.SpellFlyout:IsMouseOver()

	local barHovered = {}
	for _, barInfo in ipairs(actionBarsInfo) do
		local isHovered = false
		if IsFrameOrChildrenHovered(barInfo) then
			isHovered = true
		elseif isFlyoutOpen and isFlyoutHovered and flyoutOwnerButton then
			-- If the flyout is hovered, check if the button that opened it belongs to this bar
			for i = 1, barInfo.count do
				local button = _G[barInfo.prefix .. i]
				if button == flyoutOwnerButton then
					isHovered = true
					break
				end
			end
		end
		barHovered[barInfo.name] = isHovered
	end

	local anyHovered = false
	for _, barInfo in ipairs(actionBarsInfo) do
		local mode = config[barInfo.key] or "ALWAYS"
		local isMouseoverMode = (mode ~= "ALWAYS" and mode ~= "HIDDEN")
		if isMouseoverMode and barHovered[barInfo.name] then
			anyHovered = true
			break
		end
	end

	for _, barInfo in ipairs(actionBarsInfo) do
		local barFrame = _G[barInfo.name]
		if barFrame then
			local mode = config[barInfo.key] or "ALWAYS"
			local targetAlpha

			if mode == "ALWAYS" then
				targetAlpha = 1
			elseif mode == "HIDDEN" then
				targetAlpha = 0
			else
				-- Mouseover modes
				if (mode == "COMBAT" or mode == "COMBAT_TARGET") and inCombat then
					targetAlpha = 1
				elseif (mode == "TARGET" or mode == "COMBAT_TARGET") and hasTarget then
					targetAlpha = 1
				elseif barHovered[barInfo.name] then
					targetAlpha = 1
				elseif config.mouseoverShowAll and anyHovered then
					targetAlpha = 1
				else
					targetAlpha = (config.fadedAlpha or 0) / 100
				end
			end

			local currentAlpha = barFrame:GetAlpha()
			if math.abs(currentAlpha - targetAlpha) > 0.001 then
				FadeBar(barFrame, targetAlpha, 0.25)
			end
		end
	end
end

local refreshTimer
local function RequestVisibilityRefresh()
	if refreshTimer then
		refreshTimer:Cancel()
	end
	refreshTimer = C_Timer.NewTimer(0.05, function()
		ActionBars:UpdateMouseoverVisibility()
		refreshTimer = nil
	end)
end

local function HookFrameMouseover(frame, isButton)
	if not frame or frame.nexMouseoverHooked then
		return
	end
	frame.nexMouseoverHooked = true

	-- Hook script handlers in-place securely. Do NOT use SetScript here because
	-- replacing the script of a secure action button taints it and blocks Blizzard's
	-- own attribute/cooldown calls during combat. Slay the taint!
	if frame.HasScript and frame:HasScript("OnEnter") then
		frame:HookScript("OnEnter", function()
			ActionBars:UpdateMouseoverVisibility()
		end)
	end

	if frame.HasScript and frame:HasScript("OnLeave") then
		if isButton and frame.EnableMouse then
			frame:EnableMouse(true)
		end
		frame:HookScript("OnLeave", function()
			RequestVisibilityRefresh()
		end)
	end
end

local function HookSpellFlyout()
	local flyout = _G.SpellFlyout
	if not flyout or flyout.nexMouseoverHooked then
		return
	end
	flyout.nexMouseoverHooked = true

	flyout:HookScript("OnEnter", function()
		ActionBars:UpdateMouseoverVisibility()
	end)
	flyout:HookScript("OnLeave", function()
		RequestVisibilityRefresh()
	end)
	flyout:HookScript("OnHide", function()
		RequestVisibilityRefresh()
	end)
end

function ActionBars:SetupMouseoverHooks()
	for _, barInfo in ipairs(actionBarsInfo) do
		local barFrame = _G[barInfo.name]
		if barFrame then
			HookFrameMouseover(barFrame)
			for i = 1, barInfo.count do
				local button = _G[barInfo.prefix .. i]
				if button then
					HookFrameMouseover(button, true)
				end
			end
		end
	end
	HookSpellFlyout()
end

-- Built once: prefix + count for every default action-button family. `equip`
-- marks the families that use ActionBarActionButtonMixin (the ones that can hold
-- an equipped item); stance/pet buttons have no equipped-item border.
local actionButtonSets = {
	{ prefix = "ActionButton", count = 12, equip = true },
	{ prefix = "MultiBarBottomLeftButton", count = 12, equip = true },
	{ prefix = "MultiBarLeftButton", count = 12, equip = true },
	{ prefix = "MultiBarRightButton", count = 12, equip = true },
	{ prefix = "MultiBarBottomRightButton", count = 12, equip = true },
	{ prefix = "MultiBar5Button", count = 12, equip = true },
	{ prefix = "MultiBar6Button", count = 12, equip = true },
	{ prefix = "MultiBar7Button", count = 12, equip = true },
	{ prefix = "StanceButton", count = 10 },
	{ prefix = "PetActionButton", count = 10 },
}

local function RefreshEquippedGlowOnButtons()
	if InCombatLockdown() then
		pendingStyling = true
		return
	end
	for _, set in ipairs(actionButtonSets) do
		if set.equip then
			for i = 1, set.count do
				local button = _G[set.prefix .. i]
				if button and button.Update then
					button:Update()
				end
			end
		end
	end
end

function ActionBars:RefreshActionBarStyling()
	if not self:IsEnabled() then
		return
	end

	-- SetShown / ClearAllPoints on action-button overlays are protected in combat.
	if InCombatLockdown() then
		pendingStyling = true
		return
	end

	local config = ns.db.actionbars

	for _, set in ipairs(actionButtonSets) do
		local prefix = set.prefix
		for i = 1, set.count do
			local button = _G[prefix .. i]
			if button then
				StyleActionButton(button, config)
				if set.equip and button.Update then
					-- Update() runs Blizzard's equip border logic, then our post-hook.
					button:Update()
				end
			end
		end
	end

	if ExtraActionButton1 then
		StyleActionButton(ExtraActionButton1, config)
	end

	StyleExtraActionArt(config)
	self:StyleZoneAbilityArt()
	self:UpdateMouseoverVisibility()
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
		self:OnDisable()
		return
	end
	if key == "enable" and value then
		self:InstallEquipGlowHook()
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
	builder:Checkbox(category, self, "equipGlow", L["Equipped Item Border"], L["Replace Blizzard's faint equipped-item border with a brighter green border that matches the action-bar frame."])

	builder:Slider(category, self, "extraButtonScale", L["Extra Button Scale"], L["Scale of the Extra Action and Zone Ability buttons, as a percent (applied out of combat)."], 100, 200, 1)

	builder:Slider(category, self, "nameSize", L["Macro Name Size"], L["Font size for macro/action names."], 8, 24, 1)
	builder:Slider(category, self, "countSize", L["Count Size"], L["Font size for stack counts and charges."], 8, 28, 1)
	builder:Slider(category, self, "hotkeySize", L["Hotkey Size"], L["Font size for keybind text."], 8, 24, 1)

	builder:Header(L["Mouseover & Visibility"])
	builder:Checkbox(category, self, "mouseoverShowAll", L["Show All on Hover"], L["Hovering any mouseover action bar reveals all of them."])
	builder:Slider(category, self, "fadedAlpha", L["Faded Alpha"], L["The opacity of action bars when they are not hovered."], 0, 100, 5)

	local visibilityChoices = {
		{ value = "ALWAYS", label = L["Always Show"] },
		{ value = "MOUSEOVER", label = L["Mouseover Only"] },
		{ value = "COMBAT", label = L["Mouseover (Show in Combat)"] },
		{ value = "TARGET", label = L["Mouseover (Show with Target)"] },
		{ value = "COMBAT_TARGET", label = L["Mouseover (Combat & Target)"] },
		{ value = "HIDDEN", label = L["Always Hide"] },
	}

	builder:Dropdown(category, self, "visibilityMain", L["Action Bar 1"], L["Set the visibility scenario for Action Bar 1."], visibilityChoices)
	builder:Dropdown(category, self, "visibilityBottomLeft", L["Action Bar 2 (Bottom Left)"], L["Set the visibility scenario for Action Bar 2 (Bottom Left)."], visibilityChoices)
	builder:Dropdown(category, self, "visibilityBottomRight", L["Action Bar 3 (Bottom Right)"], L["Set the visibility scenario for Action Bar 3 (Bottom Right)."], visibilityChoices)
	builder:Dropdown(category, self, "visibilityRight", L["Action Bar 4 (Right)"], L["Set the visibility scenario for Action Bar 4 (Right)."], visibilityChoices)
	builder:Dropdown(category, self, "visibilityLeft", L["Action Bar 5 (Left)"], L["Set the visibility scenario for Action Bar 5 (Left)."], visibilityChoices)
	builder:Dropdown(category, self, "visibilityBar5", L["Action Bar 6"], L["Set the visibility scenario for Action Bar 6."], visibilityChoices)
	builder:Dropdown(category, self, "visibilityBar6", L["Action Bar 7"], L["Set the visibility scenario for Action Bar 7."], visibilityChoices)
	builder:Dropdown(category, self, "visibilityBar7", L["Action Bar 8"], L["Set the visibility scenario for Action Bar 8."], visibilityChoices)
	builder:Dropdown(category, self, "visibilityPet", L["Pet Action Bar"], L["Set the visibility scenario for the pet action bar."], visibilityChoices)
	builder:Dropdown(category, self, "visibilityStance", L["Stance Bar"], L["Set the visibility scenario for the stance bar."], visibilityChoices)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
-- Hook the shared action-button mixin once so the equipped-item glow follows
-- live action changes (drag/drop, equips) without us polling. hooksecurefunc
-- keeps the secure update path clean.
function ActionBars:InstallEquipGlowHook()
	if self.equipGlowHooked then
		return
	end
	local mixin = _G.ActionBarActionButtonMixin
	if not (mixin and mixin.Update) then
		return
	end
	self.equipGlowHooked = true
	hooksecurefunc(mixin, "Update", ApplyEquipGlow)
end

function ActionBars:RegisterModuleEvents()
	if self.eventsRegistered then
		return
	end
	self.eventsRegistered = true

	self:TrackEvent(eventHandles, "UPDATE_BINDINGS", "RefreshActionBarStyling")
	self:TrackEvent(eventHandles, "ACTIONBAR_PAGE_CHANGED", "RefreshActionBarStyling")
	self:TrackEvent(eventHandles, "PLAYER_ENTERING_WORLD", "RefreshActionBarStyling")
	self:TrackEvent(eventHandles, "PLAYER_EQUIPMENT_CHANGED", "RefreshEquipGlow")
	self:TrackEvent(eventHandles, "PLAYER_REGEN_ENABLED")
	self:TrackEvent(eventHandles, "PLAYER_REGEN_DISABLED", "UpdateMouseoverVisibility")
	self:TrackEvent(eventHandles, "PLAYER_TARGET_CHANGED", "UpdateMouseoverVisibility")
end

function ActionBars:UnregisterModuleEvents()
	if not self.eventsRegistered then
		return
	end
	self.eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
end

function ActionBars:OnDisable()
	self:UnregisterModuleEvents()
	-- Stop in-flight mouseover fades so SetAlpha doesn't keep running after off.
	wipe(activeFades)
	if fadeFrame then
		fadeFrame:SetScript("OnUpdate", nil)
	end
end

function ActionBars:RefreshEquipGlow()
	if not self:IsEnabled() then
		return
	end
	RefreshEquippedGlowOnButtons()
end

-- Re-apply any scale, styling, or equip-glow change that was blocked in combat.
function ActionBars:PLAYER_REGEN_ENABLED()
	local pending = self.pendingScale or pendingStyling
	if self.pendingScale then
		self.pendingScale = nil
	end
	if pendingStyling then
		pendingStyling = false
	end
	if pending then
		self:RefreshActionBarStyling()
	else
		self:UpdateMouseoverVisibility()
	end
end

function ActionBars:OnEnable()
	self:InstallEquipGlowHook()
	self:SetupMouseoverHooks()
	self:RefreshActionBarStyling()
	self:RegisterModuleEvents()
end
