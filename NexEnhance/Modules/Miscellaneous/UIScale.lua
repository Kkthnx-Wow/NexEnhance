--[[
	NexEnhance - UI Scale
	-------------------------------------------------------------------------
	Pixel-perfect auto-scaling for UIParent. Picks the scale that maps 1 UI
	pixel onto 1 physical pixel for the current resolution, and exposes the
	matching pixel multiplier (C.Mult) that the backdrop/border system uses
	to draw crisp 1px borders at any resolution.

	Ported from NDui's SetupUIScale logic (Init.lua, by siweia), adapted to the
	NexEnhance framework. Computed in OnInitialize so C.Mult is correct before
	any module builds a backdrop, and re-applied on UI_SCALE_CHANGED.

	Settings live in the active profile:
	  * enable    - apply our scale to UIParent (off = only compute C.Mult)
	  * autoScale - lock to the pixel-perfect best scale for this resolution
	  * scale     - manual scale used when autoScale is off
--]]

local _, ns = ...
local C, L = ns.C, ns.L

local floor, min, max = math.floor, math.min, math.max
local InCombatLockdown = InCombatLockdown
local GetPhysicalScreenSize = GetPhysicalScreenSize
local UIParent = UIParent

ns:RegisterDefaults({
	uiScale = {
		enable = true,
		autoScale = true,
		scale = 0.71,
	},
})

local UIScale = ns:NewModule("UIScale", "uiScale", { group = "general", title = L["UI Scale"], order = 1 })

local MIN_SCALE, MAX_SCALE = 0.40, 1.15

-- Physical screen height (refreshed on UI_SCALE_CHANGED); 768 is the pixel
-- baseline Blizzard's UI is authored against.
local screenHeight = select(2, GetPhysicalScreenSize())

local function Round(value, places)
	local mult = 10 ^ (places or 0)
	return floor(value * mult + 0.5) / mult
end

-- The scale at which 1 UI unit == 1 physical pixel for this resolution.
local function GetBestScale()
	return Round(max(MIN_SCALE, min(MAX_SCALE, 768 / screenHeight)), 2)
end

-- Compute the effective scale, refresh the pixel multiplier, and (when enabled
-- and out of combat) apply it to UIParent. `pixelOnly` skips the SetScale so we
-- can update C.Mult without touching the live scale (e.g. before login).
function UIScale:Refresh(pixelOnly)
	local cfg = ns.db.uiScale

	local scale
	if cfg.enable then
		scale = cfg.autoScale and GetBestScale() or cfg.scale
	else
		-- Not driving the scale ourselves: derive the multiplier from whatever
		-- scale the UI is currently using so borders still land on pixels.
		scale = UIParent:GetScale()
	end

	-- NDui's pixel-multiplier: how many UI units make one physical pixel.
	C.Mult = (768 / screenHeight) / scale

	if cfg.enable and not pixelOnly and not InCombatLockdown() then
		UIParent:SetScale(scale)
	end
end

local function ApplyScale()
	UIScale:Refresh(true) -- multiplier first
	UIScale:Refresh() -- then the live scale

	-- SetScale is blocked in combat; flag a retry for when it ends.
	if ns.db.uiScale.enable and InCombatLockdown() then
		UIScale.pending = true
	end
end

function UIScale:UI_SCALE_CHANGED()
	screenHeight = select(2, GetPhysicalScreenSize())
	ApplyScale()
end

-- Apply a scale change that was requested/needed during combat.
function UIScale:PLAYER_REGEN_ENABLED()
	if self.pending then
		self.pending = nil
		ApplyScale()
	end
end

-- Runs for every module before any OnEnable, so C.Mult is ready in time for
-- the first backdrop a module creates.
function UIScale:OnInitialize()
	ApplyScale()
	self:RegisterEvent("UI_SCALE_CHANGED")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function UIScale:OnSettingChanged()
	ApplyScale()
end

function UIScale:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable UI Scale"], L["Let NexEnhance set the UIParent scale (reload-safe; ignores changes made in combat)."])
	builder:Checkbox(category, self, "autoScale", L["Auto (Pixel-Perfect)"], L["Automatically pick the scale that maps 1 UI pixel to 1 screen pixel for your resolution."])
	builder:Slider(category, self, "scale", L["Manual Scale"], L["Scale used when Auto is disabled."], MIN_SCALE, MAX_SCALE, 0.01)
end
