--[[
	NexEnhance - Action Cast On Key Down
	-------------------------------------------------------------------------
	Toggles the "ActionButtonUseKeyDown" CVar so action buttons fire the moment
	a key is pressed (down) instead of when it is released (up). Casting on key
	down feels more responsive for most players.

	The CVar can be protected while in combat, so a change requested in combat is
	deferred until PLAYER_REGEN_ENABLED.
--]]

local _, ns = ...
local L = ns.L

local GetCVar = GetCVar
local SetCVar = SetCVar
local InCombatLockdown = InCombatLockdown

ns:RegisterDefaults({
	actionKeyDown = {
		enable = true,
	},
})

local ActionKeyDown = ns:NewModule("ActionKeyDown", "actionKeyDown", { group = "actionbars", title = L["Cast On Key Down"], order = 30 })

local originalKeyDown
local eventHandles = {}
local eventsRegistered = false

local function RestoreKeyDown()
	if originalKeyDown == nil then
		return
	end
	if InCombatLockdown() then
		ActionKeyDown.pendingRestore = originalKeyDown
		return
	end
	SetCVar("ActionButtonUseKeyDown", originalKeyDown)
end

local function Apply()
	if originalKeyDown == nil then
		originalKeyDown = GetCVar("ActionButtonUseKeyDown") or "0"
	end
	if InCombatLockdown() then
		ActionKeyDown.pending = true
		return
	end
	if not ns.db.actionKeyDown.enable then
		SetCVar("ActionButtonUseKeyDown", originalKeyDown)
		return
	end
	SetCVar("ActionButtonUseKeyDown", "1")
end

function ActionKeyDown:PLAYER_REGEN_ENABLED()
	if self.pendingRestore then
		SetCVar("ActionButtonUseKeyDown", self.pendingRestore)
		self.pendingRestore = nil
	end
	if self.pending then
		self.pending = nil
		Apply()
	end
end

function ActionKeyDown:RegisterModuleEvents()
	if eventsRegistered then
		return
	end
	eventsRegistered = true
	self:TrackEvent(eventHandles, "PLAYER_REGEN_ENABLED")
end

function ActionKeyDown:UnregisterModuleEvents()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
end

function ActionKeyDown:OnEnable()
	if not ns.db.actionKeyDown.enable then
		return
	end
	self:RegisterModuleEvents()
	Apply()
end

function ActionKeyDown:OnDisable()
	self:UnregisterModuleEvents()
	self.pending = nil
	RestoreKeyDown()
end

function ActionKeyDown:OnSettingChanged(key)
	if key == "enable" then
		if ns.db.actionKeyDown.enable then
			self:RegisterModuleEvents()
			Apply()
		else
			self:UnregisterModuleEvents()
			self.pending = nil
			RestoreKeyDown()
		end
		return
	end
	Apply()
end

function ActionKeyDown:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Cast On Key Down"], L["Action buttons fire when a key is pressed instead of when it is released."])
end
