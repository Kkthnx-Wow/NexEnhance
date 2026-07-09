--[[
	NexEnhance - Nameplate Target Resource
	-------------------------------------------------------------------------
	Puts your class resource (combo points, holy power, runes, shards, chi,
	arcane charges, essence) under the *current target's* nameplate.

	Blizzard already owns the bar (`NamePlateDriverFrame:GetClassNameplateBar`)
	and keeps it updated — we only reparent it after SetupClassNameplateBars
	sticks it on the personal plate. No UnitPower reads, no custom points,
	no Secret arithmetic. Off by default.
--]]

local _, ns = ...
local F, L = ns.F, ns.L

local C_NamePlate = C_NamePlate
local UnitExists = UnitExists
local hooksecurefunc = hooksecurefunc
local C_Timer_After = C_Timer.After

ns:RegisterDefaults({
	nameplateTargetResource = {
		enable = false,
		offsetY = -4,
	},
})

local Module = ns:NewModule("NameplateTargetResource", "nameplateTargetResource", {
	group = "nameplates",
	title = L["Target Resource"],
	order = 25,
	since = "1.6.0",
})

local running = false
local hookInstalled = false
local eventHandles = {}
local applyScheduled = false
-- Guard: RestoreBlizzardPlacement calls SetupClassNameplateBars, which re-enters
-- our post-hook — without this we'd recurse forever on target clear.
local restoring = false
local InstallHook -- forward: ApplyPlacement / OnEnable call before definition

-- ---------------------------------------------------------------------------
-- Placement
-- ---------------------------------------------------------------------------
local function HealthAnchor(unitFrame)
	if not unitFrame then
		return nil
	end
	-- Same container Blizzard uses for personal-plate class bars.
	return unitFrame.HealthBarsContainer or unitFrame.healthBar
end

local function GetMechanicBar(driver)
	if not driver then
		return nil
	end
	if driver.GetClassNameplateBar then
		return driver:GetClassNameplateBar()
	end
	return driver.classNamePlateMechanicFrame
end

local function RestoreBlizzardPlacement()
	local driver = _G.NamePlateDriverFrame
	if not (driver and driver.SetupClassNameplateBars) then
		return
	end
	restoring = true
	driver:SetupClassNameplateBars()
	restoring = false
end

function Module:ApplyPlacement(driver)
	if not running or not ns.db.nameplateTargetResource.enable or restoring then
		return
	end

	-- NamePlateDriverFrame can lag first login; keep trying until the hook sticks.
	if not hookInstalled then
		InstallHook()
	end

	driver = driver or _G.NamePlateDriverFrame
	local bar = GetMechanicBar(driver)
	if not bar then
		return
	end

	-- No target / no plate: give the bar back to Blizzard's personal plate.
	-- Incident (TargetResource, Jul 2026): early return left the bar orphaned on
	-- the previous nameplate after Esc-clearing target.
	if not UnitExists("target") then
		RestoreBlizzardPlacement()
		return
	end

	local plate = C_NamePlate.GetNamePlateForUnit("target")
	if not plate or plate:IsForbidden() then
		RestoreBlizzardPlacement()
		return
	end

	local health = HealthAnchor(plate.UnitFrame)
	if not health then
		RestoreBlizzardPlacement()
		return
	end

	local offsetY = ns.db.nameplateTargetResource.offsetY
	if type(offsetY) ~= "number" then
		offsetY = bar.paddingOverride or -4
	end

	-- Blizzard just parented this to the player plate; steal it for the target.
	bar:SetParent(plate)
	bar:ClearAllPoints()
	bar:SetPoint("TOP", health, "BOTTOM", 0, offsetY)
	bar:Show()
	if bar.OnSizeChanged then
		bar:OnSizeChanged()
	end
end

-- End-of-frame coalesce: plate add + target change often fire together.
local function ScheduleApply()
	if applyScheduled or not running then
		return
	end
	applyScheduled = true
	C_Timer_After(0, function()
		applyScheduled = false
		if running then
			Module:ApplyPlacement()
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Hook — Blizzard always wins first; we re-apply after.
-- Incident: SetupClassNameplateBars runs on every plate add/remove/target
-- change and hard-codes the personal plate. Post-hook is the only durable fix.
-- ---------------------------------------------------------------------------
InstallHook = function()
	if hookInstalled then
		return true
	end
	local driver = _G.NamePlateDriverFrame
	if not driver or not driver.SetupClassNameplateBars then
		return false
	end

	hooksecurefunc(driver, "SetupClassNameplateBars", function(self)
		if restoring or not Module:IsEnabled() or not ns.db.nameplateTargetResource.enable then
			return
		end
		Module:ApplyPlacement(self)
	end)
	hookInstalled = true
	return true
end

-- ---------------------------------------------------------------------------
-- Events (refresh when the target plate appears after Blizzard's setup)
-- ---------------------------------------------------------------------------
function Module:PLAYER_TARGET_CHANGED()
	ScheduleApply()
end

function Module:NAME_PLATE_UNIT_ADDED(unit)
	if F.SafeUnitIsUnit(unit, "target") then
		ScheduleApply()
	end
end

function Module:EnsureEvents()
	if self.eventsRegistered then
		return
	end
	self.eventsRegistered = true
	self:TrackEvent(eventHandles, "PLAYER_TARGET_CHANGED")
	self:TrackEvent(eventHandles, "NAME_PLATE_UNIT_ADDED")
end

function Module:UnregisterModuleEvents()
	if not self.eventsRegistered then
		return
	end
	self.eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function Module:OnEnable()
	if not ns.db.nameplateTargetResource.enable then
		return
	end
	running = true
	InstallHook()
	self:EnsureEvents()
	ScheduleApply()
end

function Module:OnDisable()
	running = false
	self:UnregisterModuleEvents()
	-- Let Blizzard put the bar back on the personal plate.
	RestoreBlizzardPlacement()
end

function Module:OnSettingChanged(key, value)
	-- enable toggles go through OnEnable / OnDisable (Commands.ApplyModuleSetting).
	if key == "enable" then
		return
	end
	if not running then
		return
	end
	if key == "offsetY" then
		ScheduleApply()
	end
end

function Module:RegisterOptions(category, builder)
	builder:Checkbox(
		category,
		self,
		"enable",
		L["Enable Target Resource"],
		L["Show your class resource (combo points, holy power, runes, etc.) under the current target's nameplate instead of the personal plate."]
	)
	builder:Slider(category, self, "offsetY", L["Offset Y"], L["Pixels below the target health bar (negative = further down)."], -20, 10, 1)
end
