--[[
	NexEnhance - Nameplate Reaction Colors
	-------------------------------------------------------------------------
	Re-tints NPC/mob nameplate health bars with F.GetNpcReactionColor (same darker
	reaction palette as target frame and tooltips). Player nameplates are left
	alone — Blizzard class-color CVars handle those.

	Post-hooks CompactUnitFrame_UpdateHealthColor so we run after Blizzard sets
	UnitSelectionColor (or combat-hostile bright red), then replace only NPC
	nameplate bars with our darker palette. Skips forbidden plates, secret
	healthBar handles, tap-denied/dead gray, and nameplateThreatDisplay
	health-bar threat tinting in combat only.

	When reaction APIs are unreadable on nameplate unit tokens (Midnight), we
	fallback-map the bar RGB Blizzard just applied via F.GetNpcReactionColorFromRGB.

	Blizzard references (12.0.7):
	  * CompactUnitFrame_UpdateHealthColor — selection/threat/tap/dead paths
	  * NamePlateUnitFrameMixin:UpdateThreatDisplay — displayThreatHealthBarColor
	  * GetAggroHighlightThreatSituation — UnitThreatSituation("player", displayedUnit)
	    on enemy nameplates (usePlayerForAggroHighlightThreat)
--]]

local _, ns = ...
local F, L = ns.F, ns.L

local hooksecurefunc = hooksecurefunc
local strfind = string.find

local InCombatLockdown = InCombatLockdown
local UnitIsPlayer = UnitIsPlayer
local UnitIsDead = UnitIsDead
local UnitThreatSituation = UnitThreatSituation
local UnitTreatAsPlayerForDisplay = UnitTreatAsPlayerForDisplay
local CompactUnitFrame_UpdateHealthColor = CompactUnitFrame_UpdateHealthColor
local CompactUnitFrame_IsTapDenied = CompactUnitFrame_IsTapDenied
local C_NamePlate = C_NamePlate
local C_Timer = C_Timer

local IsSecret = F.IsSecret
local CanAccess = F.CanAccessValue

ns:RegisterDefaults({
	nameplateReactionColors = {
		enable = true,
	},
})

local Module = ns:NewModule("NameplateReactionColors", "nameplateReactionColors", {
	group = "nameplates",
	title = L["Nameplate Reaction Colors"],
	order = 15,
	since = "1.5.0",
})

local running = false
local eventHandles = {}
local regenRefreshPending = false
local unitAddedRefreshPending = {}

local function IsNameplateUnit(unit)
	return unit and not IsSecret(unit) and strfind(unit, "nameplate") ~= nil
end

-- IsForbidden can return a secret ObjectSecurity value on restricted frames.
local function IsFrameForbidden(frame)
	if not frame or not frame.IsForbidden then
		return false
	end
	local forbidden = frame:IsForbidden()
	if IsSecret(forbidden) or not CanAccess(forbidden) then
		return true
	end
	return forbidden
end

-- Mirrors ShouldUseThreatHealthBarColor + GetAggroHighlightThreatSituation for
-- enemy nameplates (NamePlateEnemyFrameOptions.usePlayerForAggroHighlightThreat).
-- Out of combat we always re-tint: threat health-bar colors are combat-only and
-- lingering threat after PLAYER_REGEN_ENABLED was leaving default Blizzard tints.
local function UsesThreatHealthBarColor(frame, unit)
	if not frame.displayThreatHealthBarColor then
		return false
	end
	if not InCombatLockdown() then
		return false
	end

	local displayedUnit = frame.displayedUnit or unit
	local threat
	local opts = frame.optionTable
	if opts and opts.usePlayerForAggroHighlightThreat then
		threat = UnitThreatSituation("player", displayedUnit)
	else
		threat = UnitThreatSituation(displayedUnit)
	end

	if F.IsSecret(threat) or F.CanNotAccessValue(threat) then
		return true
	end

	return threat and threat > 0
end

local function ShouldSkipNpcNameplate(frame, unit)
	if not frame or not unit then
		return true
	end

	if IsFrameForbidden(frame) then
		return true
	end

	local healthBar = frame.healthBar
	if not healthBar or IsSecret(healthBar) then
		return true
	end

	local isPlayer = UnitIsPlayer(unit)
	if F.NotSecret(isPlayer) and isPlayer then
		return true
	end

	if UnitTreatAsPlayerForDisplay then
		local treatAsPlayer = UnitTreatAsPlayerForDisplay(unit)
		if F.NotSecret(treatAsPlayer) and treatAsPlayer then
			return true
		end
	end

	local isDead = UnitIsDead(unit)
	if F.NotSecret(isDead) and isDead then
		return true
	end

	if CompactUnitFrame_IsTapDenied and CompactUnitFrame_IsTapDenied(frame) then
		return true
	end

	if UsesThreatHealthBarColor(frame, unit) then
		return true
	end

	return false
end

local function ResolveNpcReactionTint(unit, healthBar)
	local r, g, b = F.GetNpcReactionColor(unit)
	if r then
		return r, g, b
	end

	-- Nameplate tokens may not expose UnitReaction/UnitSelectionType to tainted
	-- code OOC, but Blizzard's UpdateHealthColor just wrote readable bar RGB.
	if healthBar and healthBar.GetStatusBarColor then
		local sr, sg, sb = healthBar:GetStatusBarColor()
		return F.GetNpcReactionColorFromRGB(sr, sg, sb)
	end

	return nil
end

local function ApplyNpcReactionColor(frame)
	if not running or not ns.db.nameplateReactionColors.enable then
		return
	end

	local unit = frame.displayedUnit or frame.unit
	if not IsNameplateUnit(unit) or ShouldSkipNpcNameplate(frame, unit) then
		return
	end

	local healthBar = frame.healthBar
	local r, g, b = ResolveNpcReactionTint(unit, healthBar)
	if r and healthBar then
		healthBar:SetStatusBarColor(r, g, b)
	end
end

local function RefreshNameplateUnitFrame(unitFrame)
	if not unitFrame or IsFrameForbidden(unitFrame) then
		return
	end
	if CompactUnitFrame_UpdateHealthColor then
		CompactUnitFrame_UpdateHealthColor(unitFrame)
	end
	ApplyNpcReactionColor(unitFrame)
end

local function RefreshNameplateForUnit(unit)
	if not running or not ns.db.nameplateReactionColors.enable then
		return
	end
	if unit and IsNameplateUnit(unit) and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
		local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
		if nameplate and not IsFrameForbidden(nameplate) then
			RefreshNameplateUnitFrame(nameplate.UnitFrame)
			return
		end
	end
	Module:RefreshVisibleNameplates()
end

function Module:RefreshVisibleNameplates()
	if not C_NamePlate or not C_NamePlate.GetNamePlates then
		return
	end

	local plates = C_NamePlate.GetNamePlates(false)
	if not plates then
		return
	end

	for i = 1, #plates do
		local nameplate = plates[i]
		if nameplate and not IsFrameForbidden(nameplate) then
			RefreshNameplateUnitFrame(nameplate.UnitFrame)
		end
	end
end

local function ScheduleRegenRefresh()
	if regenRefreshPending or not C_Timer or not C_Timer.After then
		return
	end
	regenRefreshPending = true
	-- Threat list can clear a tick after regen; batch again next frame + shortly after.
	C_Timer.After(0, function()
		regenRefreshPending = false
		Module:RefreshVisibleNameplates()
	end)
	C_Timer.After(0.1, function()
		if running and ns.db.nameplateReactionColors.enable then
			Module:RefreshVisibleNameplates()
		end
	end)
end

function Module:OnRegenEnabled()
	self:RefreshVisibleNameplates()
	ScheduleRegenRefresh()
end

function Module:OnThreatOrFactionEvent(unit)
	RefreshNameplateForUnit(unit)
end

function Module:NAME_PLATE_UNIT_ADDED(unit)
	if not running then
		return
	end
	-- Plate frame may not be wired when the event fires; defer one frame.
	if unitAddedRefreshPending[unit] then
		return
	end
	unitAddedRefreshPending[unit] = true
	C_Timer.After(0, function()
		unitAddedRefreshPending[unit] = nil
		if running and ns.db.nameplateReactionColors.enable then
			RefreshNameplateForUnit(unit)
		end
	end)
end

function Module:InstallHook()
	if self.hookInstalled then
		return
	end
	self.hookInstalled = true

	hooksecurefunc("CompactUnitFrame_UpdateHealthColor", ApplyNpcReactionColor)

	-- Belt-and-suspenders: apply after Blizzard finishes SetUnit on a plate.
	if NamePlateBaseMixin and NamePlateBaseMixin.SetUnit then
		hooksecurefunc(NamePlateBaseMixin, "SetUnit", function(namePlateBase)
			if not running or not ns.db.nameplateReactionColors.enable then
				return
			end
			C_Timer.After(0, function()
				local unitFrame = namePlateBase and namePlateBase.UnitFrame
				if unitFrame then
					ApplyNpcReactionColor(unitFrame)
				end
			end)
		end)
	end
end

function Module:EnsureEvents()
	if self.eventsRegistered then
		return
	end
	self.eventsRegistered = true
	self:TrackEvent(eventHandles, "PLAYER_REGEN_ENABLED", "OnRegenEnabled")
	self:TrackEvent(eventHandles, "PLAYER_REGEN_DISABLED", "RefreshVisibleNameplates")
	self:TrackEvent(eventHandles, "PLAYER_ENTERING_WORLD", "RefreshVisibleNameplates")
	self:TrackEvent(eventHandles, "UNIT_THREAT_LIST_UPDATE", "OnThreatOrFactionEvent")
	self:TrackEvent(eventHandles, "UNIT_THREAT_SITUATION_UPDATE", "OnThreatOrFactionEvent")
	self:TrackEvent(eventHandles, "UNIT_FACTION", "OnThreatOrFactionEvent")
	self:TrackEvent(eventHandles, "UNIT_CONNECTION", "OnThreatOrFactionEvent")
	self:TrackEvent(eventHandles, "NAME_PLATE_UNIT_ADDED")
end

function Module:UnregisterModuleEvents()
	if not self.eventsRegistered then
		return
	end
	self.eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
end

function Module:OnDisable()
	running = false
	self:RefreshVisibleNameplates()
	self:UnregisterModuleEvents()
end

function Module:OnEnable()
	running = ns.db.nameplateReactionColors.enable and true or false
	self:InstallHook()
	self:EnsureEvents()
	if running then
		self:RefreshVisibleNameplates()
	end
end

function Module:OnSettingChanged(key, value)
	if key == "enable" then
		if value then
			running = true
			self:InstallHook()
			self:EnsureEvents()
			self:RefreshVisibleNameplates()
		else
			self:OnDisable()
		end
	end
end

function Module:RegisterOptions(category, builder)
	builder:Checkbox(
		category,
		self,
		"enable",
		L["Enable Nameplate Reaction Colors"],
		L["Tint NPC and mob nameplate health bars with the same darker reaction colors as the target frame. Player nameplates are not changed."]
	)
end
