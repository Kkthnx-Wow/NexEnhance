--[[
	NexEnhance - Auto Role
	-------------------------------------------------------------------------
	Keeps your party/raid role in sync with your active specialization and
	optionally answers role polls without the popup — aligned with Blizzard's
	RolePollPopup flow (UnitGetAvailableRoles, GetSpecializationRoleEnum,
	UnitSetRoleEnum) rather than legacy string roles.

	Skips LFG-restricted groups, scenarios, combat, and sub-level-10 characters
	(the same conditions Blizzard uses before showing Set Role UI).
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local L = ns.L

local wipe = wipe
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local IsInGroup = IsInGroup
local IsPartyLFG = IsPartyLFG
local UnitLevel = UnitLevel
local UnitSetRoleEnum = UnitSetRoleEnum
local UnitGroupRolesAssignedEnum = UnitGroupRolesAssignedEnum
local GetSpecializationRoleEnum = GetSpecializationRoleEnum
local UnitGetAvailableRoles = UnitGetAvailableRoles
local AreClassRolesSoftSuggestions = AreClassRolesSoftSuggestions
local CanShowSetRoleButton = CanShowSetRoleButton
local HasLFGRestrictions = HasLFGRestrictions
local StaticPopupSpecial_Hide = StaticPopupSpecial_Hide
local C_Timer_After = C_Timer.After

local C_SpecializationInfo_GetSpecialization = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
local C_Scenario_IsInScenario = C_Scenario and C_Scenario.IsInScenario

local LFGRole = Enum.LFGRole
local NO_ROLE = Constants.LFG_ROLEConstants.LFG_ROLE_NO_ROLE

local MIN_SPEC_LEVEL = 10
local SYNC_DELAY = 0.25
local RETRY_INTERVAL = 2

ns:RegisterDefaults({
	autoRole = {
		enable = false,
		answerRolePoll = true,
	},
})

local AutoRole = ns:NewModule("AutoRole", "autoRole", { group = "automation", title = L["Auto Role"], order = 85, since = "1.5.0" })

local syncPending
local lastSetAttempt
local eventsRegistered
local eventHandles = {}

local function IsConfigured()
	return ns.db.autoRole.enable
end

local function ShouldManageRole()
	if not IsConfigured() then
		return false
	end
	if InCombatLockdown() then
		return false
	end
	if not IsInGroup() then
		return false
	end
	if UnitLevel("player") < MIN_SPEC_LEVEL then
		return false
	end
	if CanShowSetRoleButton and not CanShowSetRoleButton() then
		return false
	end
	if IsPartyLFG and IsPartyLFG() then
		return false
	end
	if HasLFGRestrictions and HasLFGRestrictions() then
		return false
	end
	if C_Scenario_IsInScenario and C_Scenario_IsInScenario() then
		return false
	end
	return true
end

local function RoleIsAvailable(roleEnum)
	if not roleEnum then
		return true
	end
	if AreClassRolesSoftSuggestions and AreClassRolesSoftSuggestions() then
		return true
	end
	local canTank, canHeal, canDps = UnitGetAvailableRoles("player")
	if roleEnum == LFGRole.Tank then
		return canTank
	elseif roleEnum == LFGRole.Healer then
		return canHeal
	elseif roleEnum == LFGRole.Damage then
		return canDps
	end
	return false
end

local function GetDesiredRoleEnum()
	if not C_SpecializationInfo_GetSpecialization then
		return nil
	end
	local spec = C_SpecializationInfo_GetSpecialization()
	if not spec then
		return nil
	end
	local role = GetSpecializationRoleEnum(spec)
	if not role or not RoleIsAvailable(role) then
		return nil
	end
	return role
end

local function NormalizeAssignedRole(roleEnum)
	if roleEnum == nil or roleEnum == NO_ROLE then
		return nil
	end
	return roleEnum
end

local function RolesMatch(currentEnum, desiredEnum)
	return NormalizeAssignedRole(currentEnum) == NormalizeAssignedRole(desiredEnum)
end

function AutoRole:TrySyncRole(force)
	if not ShouldManageRole() then
		return
	end

	local desired = GetDesiredRoleEnum()
	if not desired then
		return
	end

	local current = UnitGroupRolesAssignedEnum("player")
	if RolesMatch(current, desired) then
		return
	end

	local now = GetTime()
	if not force and lastSetAttempt and now - lastSetAttempt < RETRY_INTERVAL then
		return
	end
	lastSetAttempt = now

	UnitSetRoleEnum("player", desired)
end

function AutoRole:ScheduleSync(force)
	if syncPending then
		return
	end
	syncPending = true
	C_Timer_After(SYNC_DELAY, function()
		syncPending = false
		AutoRole:TrySyncRole(force and true or false)
	end)
end

function AutoRole:OnRoleDriverEvent()
	if InCombatLockdown() then
		return
	end
	self:ScheduleSync(false)
end

function AutoRole:PLAYER_REGEN_ENABLED()
	self:ScheduleSync(false)
end

function AutoRole:ROLE_POLL_BEGIN()
	if not IsConfigured() or not ns.db.autoRole.answerRolePoll then
		return
	end
	self:TrySyncRole(true)
	if RolePollPopup and RolePollPopup:IsShown() then
		StaticPopupSpecial_Hide(RolePollPopup)
	end
end

local function SetRolePollSuppressed(suppress)
	local popup = RolePollPopup
	if not popup then
		return
	end
	if suppress then
		popup:UnregisterEvent("ROLE_POLL_BEGIN")
	else
		popup:RegisterEvent("ROLE_POLL_BEGIN")
	end
end

function AutoRole:ApplyRolePollSuppression()
	SetRolePollSuppressed(IsConfigured() and ns.db.autoRole.answerRolePoll)
end

local function TrackEvent(event, callback)
	eventHandles[#eventHandles + 1] = { event = event, cb = callback }
end

function AutoRole:RegisterModuleEvents()
	if eventsRegistered then
		return
	end
	eventsRegistered = true

	TrackEvent("PLAYER_SPECIALIZATION_CHANGED", self:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "OnRoleDriverEvent", "player"))
	TrackEvent("ACTIVE_TALENT_GROUP_CHANGED", self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", "OnRoleDriverEvent"))
	TrackEvent("GROUP_ROSTER_UPDATE", self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRoleDriverEvent"))
	TrackEvent("PLAYER_LEVEL_CHANGED", self:RegisterEvent("PLAYER_LEVEL_CHANGED", "OnRoleDriverEvent"))
	TrackEvent("PLAYER_ENTERING_WORLD", self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnRoleDriverEvent"))
	TrackEvent("PLAYER_REGEN_ENABLED", self:RegisterEvent("PLAYER_REGEN_ENABLED", "PLAYER_REGEN_ENABLED"))
	TrackEvent("ROLE_POLL_BEGIN", self:RegisterEvent("ROLE_POLL_BEGIN", "ROLE_POLL_BEGIN"))

	self:ApplyRolePollSuppression()
	self:ScheduleSync(false)
end

function AutoRole:UnregisterModuleEvents()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	syncPending = false

	for i = 1, #eventHandles do
		local handle = eventHandles[i]
		if handle.event and handle.cb then
			ns:UnregisterEvent(handle.event, handle.cb)
		end
	end
	wipe(eventHandles)

	self:ApplyRolePollSuppression()
end

function AutoRole:OnSettingChanged(key, value)
	if key == "enable" then
		if value then
			self:RegisterModuleEvents()
			self:ScheduleSync(false)
		else
			self:UnregisterModuleEvents()
		end
	elseif key == "answerRolePoll" then
		self:ApplyRolePollSuppression()
	end
end

function AutoRole:OnEnable()
	self:RegisterModuleEvents()
end

function AutoRole:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Auto Role"], L["Automatically set your party role to match your specialization when you join a group or change talents. Skips LFG dungeon groups and scenarios."])
	local _, pollInit = builder:Checkbox(category, self, "answerRolePoll", L["Answer Role Polls"], L["When the group leader starts a role poll, set your role immediately and skip Blizzard's popup."])

	builder:DependsOn(pollInit, enableInit)
end
