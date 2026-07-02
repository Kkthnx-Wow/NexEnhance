--[[
	NexEnhance - Hide DPS Role Icon
	-------------------------------------------------------------------------
	Hides the DPS (sword/DAMAGER) role icon from party and raid frames. Tank and
	healer icons remain visible — they carry actionable information (where to
	stand, who to keep alive). The DPS icon is noise: everyone who isn't a tank
	or healer is already understood to be DPS.

	Implementation:
	  * Compact raid / raid-style party: post-hook
	    `CompactUnitFrame_UpdateRoleIcon` (Shared/CompactUnitFrame.lua).
	  * Standard party HUD (PartyFrame portraits): per-frame post-hooks on pooled
	    `PartyMemberFrameTemplate` instances (`UpdateAssignedRoles`,
	    `UpdateMember`) plus PartyFrame refresh hooks. Pooled frames copy mixin
	    methods at acquire time, so hooking `PartyMemberFrameMixin` alone does
	    not run on live party frames.

	Default: OFF (opt-in).
--]]

local _, ns = ...
local L = ns.L

local Enum = Enum
local UnitInVehicle = UnitInVehicle
local UnitHasVehicleUI = UnitHasVehicleUI
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitGroupRolesAssignedEnum = UnitGroupRolesAssignedEnum
local hooksecurefunc = hooksecurefunc
local C_Timer = C_Timer

local DPS_ROLE_ATLAS = "roleicon-tiny-dps"

ns:RegisterDefaults({
	hideDpsRole = {
		enable = false,
	},
})

local HideDpsRole = ns:NewModule("HideDpsRole", "hideDpsRole", {
	group = "unitframes",
	title = L["Hide DPS Role Icon"],
	order = 50,
})

local hookedCompact = false
local hookedPartyFrame = false
local eventHandles = {}
local eventsRegistered = false

local function SettingEnabled()
	return ns.db and ns.db.hideDpsRole.enable
end

local function IsDamagerRole(unit)
	if UnitGroupRolesAssignedEnum then
		local roleEnum = UnitGroupRolesAssignedEnum(unit)
		if roleEnum == Enum.LFGRole.Damage then
			return true
		end
	end
	if UnitGroupRolesAssigned then
		return UnitGroupRolesAssigned(unit) == "DAMAGER"
	end
	return false
end

local function IsDpsRoleIcon(icon)
	if not icon or not icon:IsShown() then
		return false
	end
	local atlas = icon.GetAtlas and icon:GetAtlas()
	if atlas == DPS_ROLE_ATLAS then
		return true
	end
	return false
end

local function HidePartyDpsRoleOnFrame(self)
	if not SettingEnabled() or not self then
		return
	end
	local icon = self.PartyMemberOverlay and self.PartyMemberOverlay.RoleIcon
	if not icon or not icon:IsShown() then
		return
	end
	local unit = self.GetUnit and self:GetUnit()
	if IsDpsRoleIcon(icon) or (unit and IsDamagerRole(unit)) then
		icon:Hide()
	end
end

local function EnsurePartyMemberHooked(frame)
	if not frame or frame.nexHideDpsRoleHooked then
		return
	end
	frame.nexHideDpsRoleHooked = true
	if type(frame.UpdateAssignedRoles) == "function" then
		hooksecurefunc(frame, "UpdateAssignedRoles", HidePartyDpsRoleOnFrame)
	end
	if type(frame.UpdateMember) == "function" then
		hooksecurefunc(frame, "UpdateMember", HidePartyDpsRoleOnFrame)
	end
end

local function ApplyToAllPartyMembers()
	local partyFrame = _G.PartyFrame
	if not partyFrame or not partyFrame.PartyMemberFramePool then
		return
	end
	for member in partyFrame.PartyMemberFramePool:EnumerateActive() do
		EnsurePartyMemberHooked(member)
		HidePartyDpsRoleOnFrame(member)
	end
end

local function RefreshPartyMemberRoles()
	local partyFrame = _G.PartyFrame
	if not partyFrame or not partyFrame.PartyMemberFramePool then
		return
	end
	for member in partyFrame.PartyMemberFramePool:EnumerateActive() do
		EnsurePartyMemberHooked(member)
		if member.UpdateAssignedRoles then
			member:UpdateAssignedRoles()
		end
		HidePartyDpsRoleOnFrame(member)
	end
end

local function OnCompactUnitFrame_UpdateRoleIcon(frame)
	if not SettingEnabled() then
		return
	end
	if not frame or not frame.roleIcon then
		return
	end
	if not frame.roleIcon:IsShown() then
		return
	end
	if not frame.unit then
		return
	end

	-- Leave vehicle icons alone — they're shown by the same code path.
	if UnitInVehicle and UnitHasVehicleUI and UnitInVehicle(frame.unit) and UnitHasVehicleUI(frame.unit) then
		return
	end

	local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(frame.unit)
	if role == "DAMAGER" or IsDamagerRole(frame.unit) then
		frame.roleIcon:Hide()
		-- Restore Blizzard's expected hidden dimensions: width = 1, height stays.
		local h = frame.roleIcon:GetHeight()
		if h and h > 0 then
			frame.roleIcon:SetSize(1, h)
		end
	end
end

local function InstallCompactHook()
	if hookedCompact then
		return
	end
	if not _G.CompactUnitFrame_UpdateRoleIcon then
		return
	end
	hooksecurefunc("CompactUnitFrame_UpdateRoleIcon", OnCompactUnitFrame_UpdateRoleIcon)
	hookedCompact = true
end

local function InstallPartyFrameHooks()
	if hookedPartyFrame then
		return
	end
	local partyFrame = _G.PartyFrame
	if not partyFrame then
		return
	end

	local function AfterPartyRefresh()
		if SettingEnabled() then
			ApplyToAllPartyMembers()
		end
	end

	if type(partyFrame.InitializePartyMemberFrames) == "function" then
		hooksecurefunc(partyFrame, "InitializePartyMemberFrames", function()
			C_Timer.After(0, AfterPartyRefresh)
		end)
	end
	if type(partyFrame.UpdatePartyFrames) == "function" then
		hooksecurefunc(partyFrame, "UpdatePartyFrames", AfterPartyRefresh)
	end
	if type(partyFrame.UpdateMemberFrames) == "function" then
		hooksecurefunc(partyFrame, "UpdateMemberFrames", AfterPartyRefresh)
	end

	hookedPartyFrame = true
end

local function Install()
	InstallCompactHook()
	InstallPartyFrameHooks()
end

local function RefreshAllFrames()
	if _G.CompactUnitFrame_UpdateRoleIcon then
		for i = 1, 4 do
			local f = _G["CompactPartyFrameMember" .. i]
			if f and f.unit then
				_G.CompactUnitFrame_UpdateRoleIcon(f)
			end
			local p = _G["CompactPartyFramePet" .. i]
			if p and p.unit then
				_G.CompactUnitFrame_UpdateRoleIcon(p)
			end
		end
		for i = 1, 40 do
			local f = _G["CompactRaidFrame" .. i]
			if f and f.unit then
				_G.CompactUnitFrame_UpdateRoleIcon(f)
			end
		end
	end

	RefreshPartyMemberRoles()
end

function HideDpsRole:OnEnable()
	if eventsRegistered then
		return
	end
	eventsRegistered = true
	Install()
	self:TrackEvent(eventHandles, "GROUP_ROSTER_UPDATE")
	self:TrackEvent(eventHandles, "PLAYER_ENTERING_WORLD")
	if SettingEnabled() then
		RefreshAllFrames()
		-- PartyFrame members are created on first show; catch late init.
		C_Timer.After(0.5, ApplyToAllPartyMembers)
	end
end

function HideDpsRole:GROUP_ROSTER_UPDATE()
	if SettingEnabled() then
		C_Timer.After(0, ApplyToAllPartyMembers)
	end
end

function HideDpsRole:PLAYER_ENTERING_WORLD()
	if SettingEnabled() then
		C_Timer.After(0, ApplyToAllPartyMembers)
	end
end

function HideDpsRole:OnDisable()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
	RefreshAllFrames()
end

function HideDpsRole:OnSettingChanged(key, value)
	if key == "enable" then
		if value then
			self:OnEnable()
		else
			self:OnDisable()
		end
		return
	end
end

function HideDpsRole:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Hide DPS Role Icon"], L["Hide the DPS (sword) role icon from standard party portraits and compact party/raid frames. Tank and healer icons remain visible."])
end
