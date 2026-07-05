--[[
	NexEnhance - Action Bar Range Coloring
	-------------------------------------------------------------------------
	Tints action-button icons (and optionally hotkey text) when an action is out
	of range, out of power, or unusable.

	Event-driven, no per-button OnUpdate:
	  * Post-hook each button's UpdateUsable with one shared handler
	  * Range flips via ACTION_RANGE_CHECK_UPDATE / ActionButton_UpdateRangeIndicator
	  * Discover buttons through ActionBarButtonEventsFrame (+ hook RegisterFrame)

	12.0: IsUsableAction / IsActionInRange can return secret booleans in combat.
	We gate with F.IsSecret and fall back to the neutral tint instead of erroring.
	Hooks install once; an `active` flag lets the feature toggle live.
--]]

local _, ns = ...
local F, L = ns.F, ns.L

-- Localised globals (UpdateUsable / range hooks fire on a per-button basis).
local _G = _G
local pairs = pairs
local strbyte = string.byte
local hooksecurefunc = hooksecurefunc
local IsSecret = F.IsSecret

local IsUsableAction = IsUsableAction
local IsActionInRange = IsActionInRange
local GetActionInfo = GetActionInfo
local GetMacroInfo = GetMacroInfo
local GetMacroSpell = GetMacroSpell
local GetPetActionInfo = GetPetActionInfo
local GetPetActionSlotUsable = GetPetActionSlotUsable
local PetHasActionBar = PetHasActionBar
local C_Spell_IsSpellUsable = C_Spell and C_Spell.IsSpellUsable

-- ---------------------------------------------------------------------------
-- Defaults & module
--   Colours are stored as "AARRGGBB" hex (the Color swatch format); converted
--   to a 0-1 quad once whenever the profile changes (RebuildColors).
-- ---------------------------------------------------------------------------
ns:RegisterDefaults({
	actionRange = {
		enable = false,
		petActions = true,
		colorHotkey = true,
		oor = "FFFF4D1A", -- out of range  -> red-orange   (1.00, 0.30, 0.10)
		oom = "FF1A4DFF", -- out of power  -> blue         (0.10, 0.30, 1.00)
		unusable = "FF666666", -- unusable -> grey          (0.40, 0.40, 0.40)
	},
})

local RangeColors = ns:NewModule("ActionBarRange", "actionRange", { group = "actionbars", title = L["Range Coloring"], order = 20 })

local function db()
	return ns.db.actionRange
end

-- ---------------------------------------------------------------------------
-- Runtime state
-- ---------------------------------------------------------------------------
-- Resolved colours per state. `normal` is plain white; optional `desaturate`
-- greys the icon when out of range. Unusable keeps Blizzard's own desaturation.
local colors = {
	normal = { 1, 1, 1, 1, desaturate = false },
	oor = { 1, 0.30, 0.10, 1, desaturate = true },
	oom = { 0.10, 0.30, 1, 1, desaturate = true },
	unusable = { 0.40, 0.40, 0.40, 1, desaturate = false },
}

local states = {} -- region (icon / hotkey) -> last applied state string
local registered = {} -- button -> true (every button we've hooked)
local active = false -- feature currently on?
local hooksInstalled = false -- one-time secure hooks in place?
local eventsRegistered = false -- one-time module events in place?
local eventHandles = {} -- tracked for teardown when deactivated

local function RebuildColors()
	local cfg = db()
	local function set(state, hex, desaturate)
		local c = colors[state]
		c[1], c[2], c[3], c[4] = F.HexToRGBA(hex)
		c.desaturate = desaturate
	end
	set("oor", cfg.oor, true)
	set("oom", cfg.oom, true)
	set("unusable", cfg.unusable, false)
end

-- ---------------------------------------------------------------------------
-- State resolution (secret-guarded usability / range reads)
-- ---------------------------------------------------------------------------
local function GetActionState(slot)
	local isUsable, notEnoughMana

	-- For macros whose name starts with '#', prefer the spell-cost usability
	-- Also check power cost so out-of-power tint is accurate.
	local actionType, id = GetActionInfo(slot)
	if actionType == "macro" and GetMacroInfo and GetMacroSpell and C_Spell_IsSpellUsable then
		local name = GetMacroInfo(id)
		if name and strbyte(name, 1) == 35 then -- 35 == '#', no substring alloc
			local spellID = GetMacroSpell(id)
			if spellID then
				isUsable, notEnoughMana = C_Spell_IsSpellUsable(spellID)
			end
		end
	end

	if isUsable == nil then
		isUsable, notEnoughMana = IsUsableAction(slot)
	end

	-- Range: only an explicit `false` is out-of-range. A secret result can't be
	-- compared, so treat it as "no range info" (leave the action in range).
	local outOfRange = false
	local inRange = IsActionInRange(slot)
	if not IsSecret(inRange) then
		outOfRange = inRange == false
	end

	-- Secret usability in combat: skip the usable/oom/unusable buckets and fall
	-- back to neutral; branching on a secret boolean would error.
	if IsSecret(isUsable) or IsSecret(notEnoughMana) then
		return "normal", outOfRange
	end

	if isUsable then
		return outOfRange and "oor" or "normal", outOfRange
	end
	return notEnoughMana and "oom" or "unusable", outOfRange
end

local function GetPetActionState(index)
	local _, _, _, _, _, _, spellID, checksRange, inRange = GetPetActionInfo(index)

	local outOfRange = false
	if not (IsSecret(checksRange) or IsSecret(inRange)) then
		outOfRange = (checksRange and not inRange) or false
	end

	local isUsable, notEnoughMana
	if spellID and C_Spell_IsSpellUsable then
		isUsable, notEnoughMana = C_Spell_IsSpellUsable(spellID)
	elseif GetPetActionSlotUsable then
		isUsable, notEnoughMana = GetPetActionSlotUsable(index), false
	end

	if IsSecret(isUsable) or IsSecret(notEnoughMana) then
		return "normal"
	end

	if isUsable then
		return outOfRange and "oor" or "normal"
	end
	return notEnoughMana and "oom" or "unusable"
end

-- ---------------------------------------------------------------------------
-- Colour application
-- ---------------------------------------------------------------------------
local function ApplyIconColor(icon, state)
	states[icon] = state
	local c = colors[state]
	icon:SetVertexColor(c[1], c[2], c[3], c[4])
	icon:SetDesaturated(c.desaturate)
end

local function ApplyHotkeyColor(hotkey, state)
	states[hotkey] = state
	local c = colors[state]
	hotkey:SetVertexColor(c[1], c[2], c[3])
end

-- Full repaint of one action button (hooked onto UpdateUsable).
local function Button_Update(button)
	if not active then
		return
	end
	local icon = button.icon
	if not icon then
		return
	end

	local iconState, outOfRange = GetActionState(button.action)
	ApplyIconColor(icon, iconState)

	local hotkey = button.HotKey
	if hotkey and db().colorHotkey then
		ApplyHotkeyColor(hotkey, outOfRange and "oor" or "normal")
	end
end

-- Incremental range flip (hooked onto ActionButton_UpdateRangeIndicator). The
-- engine hands us plain booleans here in the normal case; in combat they may be
-- secret, in which case we leave the last applied state untouched.
local function Button_UpdateRange(button, checksRange, inRange)
	if not active or not registered[button] then
		return
	end
	if IsSecret(checksRange) or IsSecret(inRange) then
		return
	end

	local oor = (checksRange and not inRange) or false

	local icon = button.icon
	if icon then
		local cur = states[icon]
		if cur == "normal" and oor then
			ApplyIconColor(icon, "oor")
		elseif cur == "oor" and not oor then
			ApplyIconColor(icon, "normal")
		end
	end

	local hotkey = button.HotKey
	if hotkey and db().colorHotkey then
		local cur = states[hotkey]
		if cur == "normal" and oor then
			ApplyHotkeyColor(hotkey, "oor")
		elseif cur == "oor" and not oor then
			ApplyHotkeyColor(hotkey, "normal")
		end
	end
end

local function PetBar_Update(bar)
	if not active or not db().petActions then
		return
	end
	if not (bar and bar.actionButtons and PetHasActionBar and PetHasActionBar()) then
		return
	end

	for index, button in pairs(bar.actionButtons) do
		local icon = button.icon
		if icon and icon:IsVisible() then
			ApplyIconColor(icon, GetPetActionState(index))
		end
	end
end

-- Repaint every registered button (used on enable and after a colour change).
function RangeColors:RefreshAll()
	if not active then
		return
	end

	local eventsFrame = _G["ActionBarButtonEventsFrame"]
	if eventsFrame and eventsFrame.ForEachFrame then
		eventsFrame:ForEachFrame(Button_Update)
	end

	local petBar = _G["PetActionBar"]
	if petBar then
		PetBar_Update(petBar)
	end
end

-- Repaint pet buttons when the pet's power changes (out-of-power tint).
function RangeColors:UNIT_POWER_UPDATE()
	local petBar = _G["PetActionBar"]
	if petBar then
		PetBar_Update(petBar)
	end
end

-- Restore every button we've touched back to plain/undesaturated. Blizzard
-- reasserts its own colours on the next UpdateUsable regardless, so this just
-- avoids leaving a stale tint behind when the feature is switched off live.
local function RestoreAll()
	for button in pairs(registered) do
		local icon = button.icon
		if icon then
			icon:SetVertexColor(1, 1, 1, 1)
			icon:SetDesaturated(false)
			states[icon] = nil
		end
		local hotkey = button.HotKey
		if hotkey then
			hotkey:SetVertexColor(1, 1, 1)
			states[hotkey] = nil
		end
	end
end

-- ---------------------------------------------------------------------------
-- Hook installation (once)
-- ---------------------------------------------------------------------------
local function RegisterButton(button)
	if registered[button] then
		return
	end
	registered[button] = true
	-- UpdateUsable is the method Blizzard calls whenever an action's usable /
	-- power state may have changed - the ideal place to recolour.
	if button.UpdateUsable then
		hooksecurefunc(button, "UpdateUsable", Button_Update)
	end
end

local function InstallHooks()
	if hooksInstalled then
		return
	end

	local eventsFrame = _G["ActionBarButtonEventsFrame"]
	if not (eventsFrame and eventsFrame.ForEachFrame) then
		return -- API not present (e.g. very old client); try again on next enable
	end
	hooksInstalled = true

	-- Existing action buttons, plus any bar created later.
	eventsFrame:ForEachFrame(RegisterButton)
	if eventsFrame.RegisterFrame then
		hooksecurefunc(eventsFrame, "RegisterFrame", function(_, button)
			RegisterButton(button)
		end)
	end

	-- Event-driven range updates (10.1.5+ ACTION_RANGE_CHECK_UPDATE plumbing).
	if _G["ActionButton_UpdateRangeIndicator"] then
		hooksecurefunc("ActionButton_UpdateRangeIndicator", Button_UpdateRange)
	end

	-- Pet bar.
	local petBar = _G["PetActionBar"]
	if petBar then
		if petBar.actionButtons then
			for _, button in pairs(petBar.actionButtons) do
				registered[button] = true
			end
		end
		if petBar.Update then
			hooksecurefunc(petBar, "Update", PetBar_Update)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
local function UnregisterEvents()
	if not eventsRegistered then
		return
	end
	ns:UnregisterModuleEventHandles(eventHandles)
	eventsRegistered = false
end

local function Activate()
	RebuildColors()
	if active then
		RangeColors:RefreshAll()
		return
	end
	active = true
	InstallHooks()

	if not eventsRegistered then
		eventsRegistered = true
		RangeColors:TrackUnitEvent(eventHandles, "UNIT_POWER_UPDATE", "UNIT_POWER_UPDATE", "pet")
		RangeColors:TrackEvent(eventHandles, "PLAYER_ENTERING_WORLD", "RefreshAll")
	end

	RangeColors:RefreshAll()
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	UnregisterEvents()
	RestoreAll()
end

function RangeColors:OnEnable()
	if db().enable then
		Activate()
	end
end

function RangeColors:OnDisable()
	Deactivate()
end

function RangeColors:OnSettingChanged(key, value)
	if key == "enable" then
		if value then
			Activate()
		else
			Deactivate()
		end
		return
	end

	-- Colour / hotkey / pet toggles: rebuild and repaint if we're running.
	if active then
		RebuildColors()
		self:RefreshAll()
	end
end

function RangeColors:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Range Coloring"], L["Tint action buttons when an action is out of range, out of power, or unusable."])
	local _, hotkeyInit = builder:Checkbox(category, self, "colorHotkey", L["Color Hotkeys"], L["Also tint the keybind text red when the action is out of range."])
	local _, petInit = builder:Checkbox(category, self, "petActions", L["Color Pet Actions"], L["Apply range and usability coloring to pet action buttons too."])

	local _, oorInit = builder:Color(category, self, "oor", L["Out Of Range Color"], L["Color used when an action's target is out of range."])
	local _, oomInit = builder:Color(category, self, "oom", L["Out Of Power Color"], L["Color used when you lack the mana / energy / focus for an action."])
	local _, unusableInit = builder:Color(category, self, "unusable", L["Unusable Color"], L["Color used when an action cannot be used (no target, wrong stance, etc.)."])

	builder:DependsOn(hotkeyInit, enableInit)
	builder:DependsOn(petInit, enableInit)
	if oorInit then
		builder:DependsOn(oorInit, enableInit)
	end
	if oomInit then
		builder:DependsOn(oomInit, enableInit)
	end
	if unusableInit then
		builder:DependsOn(unusableInit, enableInit)
	end
end
