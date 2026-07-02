--[[
	NexEnhance - Nameplate Target Arrows
	-------------------------------------------------------------------------
	Left/right or top arrow indicators on the current target's nameplate, plus optional
	friendly-player nameplate CVars Blizzard reads through CVarCallbackRegistry:

	  * nameplateShowFriendlyPlayers
	  * nameplateShowOnlyNameForFriendlyPlayerUnits
	  * nameplateUseClassColorForFriendlyPlayerUnitNames

	Arrows attach only to attackable targets (same rule as NameplateEnhancer).
	Event-driven on PLAYER_TARGET_CHANGED; refreshes when the target nameplate
	spawns later via NAME_PLATE_UNIT_ADDED. No OnUpdate.
--]]

local _, ns = ...
local C, F, L = ns.C, ns.F, ns.L

local C_NamePlate = C_NamePlate
local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack
local UnitIsUnit = UnitIsUnit
local GetCVar = GetCVar
local SetCVar = SetCVar
local pcall = pcall
local rad = math.rad
local InCombatLockdown = InCombatLockdown
local CanAccess = F.CanAccessValue

-- UI-HUD-Minimap-Arrow-Corpse points down at rotation 0; side arrows are rotated inward.
-- Azerite-PointingArrow also points down at rotation 0 — no rotation needed for Top style.
local STYLE_HORIZONTAL, STYLE_TOP = 1, 2
local STYLES = {
	[STYLE_HORIZONTAL] = {
		atlas = "UI-HUD-Minimap-Arrow-Corpse",
		defaultDirection = 180,
	},
	[STYLE_TOP] = {
		atlas = "UI-HUD-Minimap-Arrow-Vignettes",
		defaultDirection = 0,
	},
}
local DIR_RIGHT, DIR_LEFT, DIR_DOWN = 90, 270, 180

local FRIENDLY_CVARS = {
	"nameplateShowFriendlyPlayers",
	"nameplateShowOnlyNameForFriendlyPlayerUnits",
	"nameplateUseClassColorForFriendlyPlayerUnitNames",
}

ns:RegisterDefaults({
	targetArrows = {
		enable = true,
		showArrows = true,
		style = STYLE_HORIZONTAL,
		size = 22,
		padding = 6,
		color = F.RGBAToHex(C.Colors.brand), -- #5C8BCF
		friendlyPlayerNameplates = true,
	},
})

local Module = ns:NewModule("TargetArrows", "targetArrows", {
	group = "nameplates",
	title = L["Target Arrows"],
	order = 20,
	since = "1.5.0",
})

local running = false
local eventHandles = {}
local previousUnitFrame
local savedCVars = {}
local pendingCVars = false
local arrowColor = { C.Colors.brand[1], C.Colors.brand[2], C.Colors.brand[3] }

-- ---------------------------------------------------------------------------
-- CVar apply (Blizzard NamePlateUnitFrameMixin listens via CVarCallbackRegistry)
-- ---------------------------------------------------------------------------
local function SetCVarSafe(name, value)
	pcall(SetCVar, name, value)
end

local function ApplyFriendlyCVars()
	if InCombatLockdown() then
		pendingCVars = true
		return
	end
	pendingCVars = false

	local want = running and ns.db.targetArrows.friendlyPlayerNameplates
	for i = 1, #FRIENDLY_CVARS do
		local name = FRIENDLY_CVARS[i]
		if savedCVars[name] == nil then
			savedCVars[name] = GetCVar(name) or "0"
		end
		SetCVarSafe(name, want and "1" or savedCVars[name])
	end
end

-- ---------------------------------------------------------------------------
-- Arrow widgets
-- ---------------------------------------------------------------------------
local function HealthBarOf(unitFrame)
	local hbc = unitFrame.HealthBarsContainer
	return (hbc and hbc.healthBar) or unitFrame.healthBar
end

local function StyleInfo()
	local style = ns.db.targetArrows.style or STYLE_HORIZONTAL
	return STYLES[style] or STYLES[STYLE_HORIZONTAL], style
end

local function RebuildArrowColor()
	local r, g, b = F.HexToRGBA(ns.db.targetArrows.color or F.RGBAToHex(C.Colors.brand))
	arrowColor[1], arrowColor[2], arrowColor[3] = r, g, b
end

local function ApplyArrowColor(tex)
	if not tex then
		return
	end
	tex:SetDesaturated(true)
	tex:SetVertexColor(arrowColor[1], arrowColor[2], arrowColor[3], 1)
end

local function ColorizeArrows(arrows)
	if not arrows then
		return
	end
	ApplyArrowColor(arrows.left)
	ApplyArrowColor(arrows.right)
	ApplyArrowColor(arrows.top)
end

local function CreateArrow(parent, size, styleInfo)
	local tex = parent:CreateTexture(nil, "OVERLAY")
	tex:SetAtlas(styleInfo.atlas, true)
	tex:SetSize(size, size)
	ApplyArrowColor(tex)
	return tex
end

local function RemoveArrows(unitFrame, destroy)
	if not unitFrame or not unitFrame.nexTargetArrows then
		return
	end

	local arrows = unitFrame.nexTargetArrows
	for _, key in ipairs({ "left", "right", "top" }) do
		local tex = arrows[key]
		if tex then
			tex:Hide()
			if destroy then
				tex:SetAtlas(nil)
			end
		end
	end
	unitFrame.nexTargetArrows = nil
end

local function LayoutArrows(unitFrame, arrows, style, styleInfo)
	local db = ns.db.targetArrows
	local size = db.size or 22
	local padding = db.padding or 6
	local healthBar = HealthBarOf(unitFrame)

	if style == STYLE_TOP then
		arrows.top:SetSize(size, size)
		arrows.top:ClearAllPoints()
		arrows.top:SetPoint("BOTTOM", healthBar, "TOP", 0, padding + 10)
		arrows.top:SetRotation((rad(DIR_DOWN - styleInfo.defaultDirection)))
		return
	end

	arrows.left:SetSize(size, size)
	arrows.left:ClearAllPoints()
	arrows.left:SetPoint("RIGHT", healthBar, "LEFT", -padding, 0)
	arrows.left:SetRotation(rad(DIR_RIGHT - styleInfo.defaultDirection))

	arrows.right:SetSize(size, size)
	arrows.right:ClearAllPoints()
	arrows.right:SetPoint("LEFT", healthBar, "RIGHT", padding, 0)
	arrows.right:SetRotation(rad(DIR_LEFT - styleInfo.defaultDirection))
end

local function ShowArrows(arrows, style)
	if style == STYLE_TOP then
		arrows.top:Show()
		return
	end
	arrows.left:Show()
	arrows.right:Show()
end

local function AttachArrows(unitFrame)
	if not unitFrame then
		return
	end

	local styleInfo, style = StyleInfo()
	local healthBar = HealthBarOf(unitFrame)
	if not healthBar then
		return
	end

	local existing = unitFrame.nexTargetArrows
	if existing and existing.style ~= style then
		RemoveArrows(unitFrame, true)
	end

	local db = ns.db.targetArrows
	local size = db.size or 22
	local arrows = unitFrame.nexTargetArrows

	if not arrows then
		if style == STYLE_TOP then
			arrows = {
				style = style,
				top = CreateArrow(unitFrame, size, styleInfo),
			}
		else
			arrows = {
				style = style,
				left = CreateArrow(healthBar, size, styleInfo),
				right = CreateArrow(healthBar, size, styleInfo),
			}
		end
		unitFrame.nexTargetArrows = arrows
	end

	LayoutArrows(unitFrame, arrows, style, styleInfo)
	ColorizeArrows(arrows)
	ShowArrows(arrows, style)
end

local function ShouldDecorateTarget(unit)
	if not unit or not UnitExists(unit) then
		return false
	end
	local canAttack = UnitCanAttack("player", unit)
	return CanAccess(canAttack) and canAttack
end

function Module:UpdateTarget()
	if not running or not ns.db.targetArrows.showArrows then
		return
	end

	if previousUnitFrame then
		RemoveArrows(previousUnitFrame)
		previousUnitFrame = nil
	end

	if not UnitExists("target") or not ShouldDecorateTarget("target") then
		return
	end

	local nameplate = C_NamePlate.GetNamePlateForUnit("target")
	if not nameplate or nameplate:IsForbidden() then
		return
	end

	local unitFrame = nameplate.UnitFrame
	if not unitFrame then
		return
	end

	previousUnitFrame = unitFrame
	AttachArrows(unitFrame)
end

function Module:ClearArrows()
	if previousUnitFrame then
		RemoveArrows(previousUnitFrame)
		previousUnitFrame = nil
	end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
function Module:PLAYER_TARGET_CHANGED()
	self:UpdateTarget()
end

function Module:NAME_PLATE_UNIT_ADDED(unit)
	if not running or not ns.db.targetArrows.showArrows then
		return
	end
	if F.SafeUnitIsUnit(unit, "target") then
		self:UpdateTarget()
	end
end

function Module:PLAYER_REGEN_ENABLED()
	if pendingCVars then
		ApplyFriendlyCVars()
	end
end

function Module:PLAYER_ENTERING_WORLD()
	ApplyFriendlyCVars()
end

function Module:EnsureEvents()
	if self.eventsRegistered then
		return
	end
	self.eventsRegistered = true
	self:TrackEvent(eventHandles, "PLAYER_TARGET_CHANGED")
	self:TrackEvent(eventHandles, "NAME_PLATE_UNIT_ADDED")
	self:TrackEvent(eventHandles, "PLAYER_ENTERING_WORLD")
	self:TrackEvent(eventHandles, "PLAYER_REGEN_ENABLED")
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
	self:ClearArrows()
	ApplyFriendlyCVars()
	self:UnregisterModuleEvents()
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function Module:Apply()
	RebuildArrowColor()
	ApplyFriendlyCVars()
	if ns.db.targetArrows.showArrows then
		self:UpdateTarget()
	else
		self:ClearArrows()
	end
end

function Module:OnEnable()
	running = true
	self:EnsureEvents()
	self:Apply()
end

function Module:OnSettingChanged(key, value)
	if key == "enable" then
		if value then
			running = true
			self:EnsureEvents()
			self:Apply()
		else
			self:OnDisable()
		end
		return
	end
	if key == "friendlyPlayerNameplates" then
		ApplyFriendlyCVars()
		return
	end
	if not running then
		return
	end
	if key == "showArrows" then
		if value then
			self:UpdateTarget()
		else
			self:ClearArrows()
		end
		return
	end
	if key == "style" then
		self:ClearArrows()
		self:UpdateTarget()
		return
	end
	if key == "color" then
		RebuildArrowColor()
		if previousUnitFrame and previousUnitFrame.nexTargetArrows then
			ColorizeArrows(previousUnitFrame.nexTargetArrows)
		end
		return
	end
	if key == "size" or key == "padding" then
		if previousUnitFrame and previousUnitFrame.nexTargetArrows then
			local styleInfo, style = StyleInfo()
			LayoutArrows(previousUnitFrame, previousUnitFrame.nexTargetArrows, style, styleInfo)
		else
			self:ClearArrows()
			self:UpdateTarget()
		end
	end
end

function Module:RegisterOptions(category, builder)
	local _, master = builder:Checkbox(category, self, "enable", L["Enable Target Arrows"], L["Enable nameplate target arrows and friendly-player nameplate options."])

	local _, arrows = builder:Checkbox(category, self, "showArrows", L["Show Target Arrows"], L["Show arrow indicators on your current target's nameplate."])
	builder:DependsOn(arrows, master)

	local styleChoices = {
		{ value = STYLE_HORIZONTAL, label = L["Horizontal"] },
		{ value = STYLE_TOP, label = L["Top (Azerite Arrow)"] },
	}
	local _, style = builder:Dropdown(category, self, "style", L["Arrow Style"], L["Horizontal places arrows on both sides of the health bar; Top places a single Azerite arrow above the nameplate."], styleChoices)
	builder:DependsOn(style, arrows)

	local _, color = builder:Color(category, self, "color", L["Arrow Color"], L["Tint color for the target arrow textures."])
	builder:DependsOn(color, arrows)

	local _, size = builder:Slider(category, self, "size", L["Arrow Size"], L["Size of the target arrow textures, in pixels."], 12, 40, 1)
	builder:DependsOn(size, arrows)

	local _, pad = builder:Slider(category, self, "padding", L["Arrow Padding"], L["Gap between the health bar and the arrows."], 0, 30, 1)
	builder:DependsOn(pad, arrows)

	local _, friendly = builder:Checkbox(category, self, "friendlyPlayerNameplates", L["Enable Friendly Player Nameplates"], L["Show friendly player nameplates as name-only with class-colored names (sets nameplateShowFriendlyPlayers, nameplateShowOnlyNameForFriendlyPlayerUnits, and nameplateUseClassColorForFriendlyPlayerUnitNames)."])
	builder:DependsOn(friendly, master)
end
