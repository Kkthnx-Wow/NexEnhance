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

local SetCVar = SetCVar
local InCombatLockdown = InCombatLockdown

ns:RegisterDefaults({
	actionKeyDown = {
		enable = true,
	},
})

local ActionKeyDown = ns:NewModule("ActionKeyDown", "actionKeyDown", { group = "general", title = L["Cast On Key Down"], order = 30 })

local function Apply()
	if InCombatLockdown() then
		ActionKeyDown.pending = true
		return
	end
	SetCVar("ActionButtonUseKeyDown", ns.db.actionKeyDown.enable and 1 or 0)
end

function ActionKeyDown:PLAYER_REGEN_ENABLED()
	if self.pending then
		self.pending = nil
		Apply()
	end
end

function ActionKeyDown:OnEnable()
	Apply()
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function ActionKeyDown:OnSettingChanged()
	Apply()
end

function ActionKeyDown:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Cast On Key Down"], L["Action buttons fire when a key is pressed instead of when it is released."])
end
