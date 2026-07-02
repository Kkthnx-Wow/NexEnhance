--[[
	NexEnhance - Hide Combat Errors
	-------------------------------------------------------------------------
	Suppresses the red center-screen error spam while in combat ("Not enough
	mana", "Ability is not ready yet", etc.) by unregistering UI_ERROR_MESSAGE
	on Blizzard's UIErrorsFrame for the duration of combat.

	Matches the ElvUI /uierrorsoff approach (see Blizzard SlashCommands.lua).
	Only UI_ERROR_MESSAGE is muted — yellow UI_INFO_MESSAGE and SYSMSG still
	flow. AddMessage / AddExternalErrorMessage from addons are unaffected.
	Restores the event on combat end and when the option is turned off.
--]]

local _, ns = ...
local L = ns.L

local InCombatLockdown = InCombatLockdown
local UIErrorsFrame = _G.UIErrorsFrame

ns:RegisterDefaults({
	hideCombatErrors = {
		enable = false,
	},
})

local HideCombatErrors = ns:NewModule("HideCombatErrors", "hideCombatErrors", {
	group = "general",
	title = L["Hide Combat Errors"],
	order = 42,
	since = "1.5.0",
})

local active = false
local eventsRegistered = false
local errorsSuppressed = false
local evtRegenDisabled
local evtRegenEnabled
local evtEnteringWorld

local function GetErrorsFrame()
	return UIErrorsFrame
end

local function SetErrorsSuppressed(suppress)
	local frame = GetErrorsFrame()
	if not frame then
		return
	end
	if suppress then
		if not errorsSuppressed then
			frame:UnregisterEvent("UI_ERROR_MESSAGE")
			errorsSuppressed = true
		end
	else
		if errorsSuppressed then
			frame:RegisterEvent("UI_ERROR_MESSAGE")
			errorsSuppressed = false
		end
	end
end

local function SyncToCombatState()
	if not active then
		SetErrorsSuppressed(false)
		return
	end
	SetErrorsSuppressed(InCombatLockdown())
end

local function EnsureEvents()
	if eventsRegistered then
		return
	end
	eventsRegistered = true
	evtRegenDisabled = HideCombatErrors:RegisterEvent("PLAYER_REGEN_DISABLED")
	evtRegenEnabled = HideCombatErrors:RegisterEvent("PLAYER_REGEN_ENABLED")
	evtEnteringWorld = HideCombatErrors:RegisterEvent("PLAYER_ENTERING_WORLD", "Sync")
end

local function UnregisterModuleEvents()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	ns:UnregisterEvent("PLAYER_REGEN_DISABLED", evtRegenDisabled)
	ns:UnregisterEvent("PLAYER_REGEN_ENABLED", evtRegenEnabled)
	ns:UnregisterEvent("PLAYER_ENTERING_WORLD", evtEnteringWorld)
	evtRegenDisabled = nil
	evtRegenEnabled = nil
	evtEnteringWorld = nil
end

-- Incident (HideCombatErrors, Jun 2026): shared OnCombatRegen(event) never received
-- the event name — module RegisterEvent passes payload only, so event was always
-- nil and suppress never toggled correctly. Split per-event methods instead.
function HideCombatErrors:PLAYER_REGEN_DISABLED()
	if not active then
		return
	end
	SetErrorsSuppressed(true)
end

function HideCombatErrors:PLAYER_REGEN_ENABLED()
	if not active then
		return
	end
	SetErrorsSuppressed(false)
end

function HideCombatErrors:Sync()
	SyncToCombatState()
end

local function Activate()
	active = true
	EnsureEvents()
	SyncToCombatState()
end

local function Deactivate()
	active = false
	SetErrorsSuppressed(false)
	UnregisterModuleEvents()
end

function HideCombatErrors:OnEnable()
	Activate()
end

function HideCombatErrors:OnDisable()
	Deactivate()
end

function HideCombatErrors:OnSettingChanged(key, value)
	if key ~= "enable" then
		return
	end
	if value then
		Activate()
	else
		Deactivate()
	end
end

function HideCombatErrors:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Hide Combat Errors"], L["Hide red error messages while in combat (Not enough mana, Ability not ready, etc.). Yellow info messages still show."])
end
