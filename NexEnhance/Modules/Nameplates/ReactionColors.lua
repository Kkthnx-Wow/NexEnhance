--[[
	NexEnhance - Nameplate Reaction Colors
	-------------------------------------------------------------------------
	Re-tints NPC/mob nameplate health bars with F.GetNpcReactionColor (same darker
	reaction palette as target frame and tooltips). Player nameplates are left
	alone — Blizzard class-color CVars handle those.

	Post-hooks CompactUnitFrame_UpdateHealthColor so we run after Blizzard sets
	UnitSelectionColor (or combat-hostile bright red), then replace only NPC
	nameplate bars with our darker palette. Skips forbidden plates, secret
	healthBar handles, tap-denied/dead/disconnected gray, and
	nameplateThreatDisplay health-bar threat tinting only.

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
local ipairs = ipairs

local UnitIsPlayer = UnitIsPlayer
local UnitIsConnected = UnitIsConnected
local UnitIsDead = UnitIsDead
local UnitThreatSituation = UnitThreatSituation
local UnitTreatAsPlayerForDisplay = UnitTreatAsPlayerForDisplay
local CompactUnitFrame_UpdateHealthColor = CompactUnitFrame_UpdateHealthColor
local CompactUnitFrame_IsTapDenied = CompactUnitFrame_IsTapDenied
local C_NamePlate = C_NamePlate

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
local function UsesThreatHealthBarColor(frame, unit)
	if not frame.displayThreatHealthBarColor then
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

	return CanAccess(threat) and threat and threat > 0
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
	if IsSecret(isPlayer) then
		return true
	end
	if isPlayer then
		return true
	end

	if UnitTreatAsPlayerForDisplay then
		local treatAsPlayer = UnitTreatAsPlayerForDisplay(unit)
		if IsSecret(treatAsPlayer) or treatAsPlayer then
			return true
		end
	end

	local connected = UnitIsConnected(unit)
	if IsSecret(connected) or not connected then
		return true
	end

	local isDead = UnitIsDead(unit)
	if IsSecret(isDead) or isDead then
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

local function ApplyNpcReactionColor(frame)
	if not running or not ns.db.nameplateReactionColors.enable then
		return
	end

	local unit = frame.displayedUnit or frame.unit
	if not IsNameplateUnit(unit) or ShouldSkipNpcNameplate(frame, unit) then
		return
	end

	local r, g, b = F.GetNpcReactionColor(unit)
	if r then
		frame.healthBar:SetStatusBarColor(r, g, b)
	end
end

local function RefreshVisibleNameplates()
	if not C_NamePlate or not C_NamePlate.GetNamePlates or not CompactUnitFrame_UpdateHealthColor then
		return
	end

	local plates = C_NamePlate.GetNamePlates(false)
	if not plates then
		return
	end

	for i = 1, #plates do
		local nameplate = plates[i]
		local unitFrame = nameplate and nameplate.UnitFrame
		if unitFrame and not IsFrameForbidden(nameplate) and not IsFrameForbidden(unitFrame) then
			CompactUnitFrame_UpdateHealthColor(unitFrame)
		end
	end
end

function Module:InstallHook()
	if self.hookInstalled then
		return
	end
	self.hookInstalled = true

	hooksecurefunc("CompactUnitFrame_UpdateHealthColor", ApplyNpcReactionColor)
end

function Module:OnEnable()
	running = ns.db.nameplateReactionColors.enable and true or false
	self:InstallHook()
	-- Combat drop can clear threat before every plate gets a unit threat event;
	-- batch-refresh so pulled neutrals return to yellow without retargeting.
	self:RegisterEvent("PLAYER_REGEN_ENABLED", RefreshVisibleNameplates)
	if running then
		RefreshVisibleNameplates()
	end
end

function Module:OnSettingChanged(key, value)
	if key == "enable" then
		running = value and true or false
		if running then
			self:InstallHook()
		end
		RefreshVisibleNameplates()
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
