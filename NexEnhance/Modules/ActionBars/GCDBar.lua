--[[
	NexEnhance - GCD Bar
	-------------------------------------------------------------------------
	A simple class-coloured bar that sweeps during the Global Cooldown.
	Hides completely between GCDs.

	Layout (cross-section, total frame = bar body + SHADOW_H):
	┌──────────────────── barFrame ────────────────────────┐
	│ ████████████ trough (dark bg) + fill (class colour)  │  ← bar body (db.height)
	│───────────────────────────────────────────────────── │
	│           shadow strip (SHADOW_H pixels)             │  ← dark, shows below bar
	└──────────────────────────────────────────────────────┘

	The shadow is simply the bottom SHADOW_H pixels of barFrame not covered
	by the trough. Both trough and fill stop SHADOW_H pixels short of the
	barFrame bottom edge using a positive Y offset on their BOTTOMRIGHT point.
	This is guaranteed to render — no outside-frame clipping issues.

	Spark pattern (from ExpRep.lua):
	  spark:SetPoint("CENTER", fill:GetStatusBarTexture(), "RIGHT", 0, 0)
	  Rides the fill's right edge automatically as SetTimerDuration depletes.

	Midnight: GCD timing is driven by C_Spell.GetSpellCooldownDuration +
	SetTimerDuration so addon code never performs arithmetic on secret cooldown
	values.
--]]

local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local math_max = math.max

local GCD_SPELL_ID = 61304
local SHADOW_H = 6 -- pixels of shadow below the bar body
local SPARK_TEX = "Interface\\CastingBar\\UI-CastingBar-Spark"

local C_Spell_GetSpellCooldownDuration = C_Spell and C_Spell.GetSpellCooldownDuration
local Enum_StatusBarInterpolation = Enum.StatusBarInterpolation.Immediate
local Enum_StatusBarTimerDirection = Enum.StatusBarTimerDirection.RemainingTime

-- ---------------------------------------------------------------------------
-- Defaults & module
-- ---------------------------------------------------------------------------
local DEFAULTS = {
	enable = false,
	width = 220,
	height = 8,
	showSpark = true,
}

ns:RegisterDefaults({ gcdBar = DEFAULTS })

local GCDBar = ns:NewModule("GCDBar", "gcdBar", {
	group = "actionbars",
	title = L["GCD Bar"],
	order = 50,
})

local spellCooldownDispatchId
local eventsRegistered = false
local eventHandles = {}

-- Poll while the bar is shown: SPELL_UPDATE_COOLDOWN alone does not always fire
-- when the GCD finishes, leaving an empty bar + spark visible (stuck state).
local pollFrame
local pollElapsed = 0
local POLL_INTERVAL = 0.05

-- ---------------------------------------------------------------------------
-- Frame handles and GCD state
-- ---------------------------------------------------------------------------
local barFrame
local trough -- dark bg texture covering bar body portion
local fillBar -- StatusBar covering bar body portion
local sparkTex

-- ---------------------------------------------------------------------------
-- Bar show / hide
-- ---------------------------------------------------------------------------
-- IsZero() can be Secret in combat — never branch on the raw return.
-- nil (secret) → treat as non-zero so we don't wipe an active swipe mid-fight.
local function DurationIsZero(durObj)
	if not durObj then
		return true
	end
	if not durObj.IsZero then
		return false
	end
	local z = F.BooleanIsTrue(durObj:IsZero())
	if z == nil then
		return false
	end
	return z
end

local function IsGCDInactive()
	if not C_Spell_GetSpellCooldownDuration then
		return true
	end
	return DurationIsZero(C_Spell_GetSpellCooldownDuration(GCD_SPELL_ID))
end

local function StopPoll()
	if pollFrame then
		pollFrame:SetScript("OnUpdate", nil)
		pollFrame:Hide()
	end
	pollElapsed = 0
end

local function StopGCD()
	if fillBar then
		if fillBar.SetToTargetValue then
			fillBar:SetToTargetValue()
		end
		fillBar:SetValue(0)
	end
	if sparkTex then
		sparkTex:Hide()
	end
	if barFrame then
		barFrame:Hide()
	end
	StopPoll()
end

local function StartPoll()
	if not pollFrame then
		pollFrame = CreateFrame("Frame")
		pollFrame:Hide()
	end
	pollElapsed = 0
	pollFrame:SetScript("OnUpdate", function(_, elapsed)
		pollElapsed = pollElapsed + (elapsed or 0)
		if pollElapsed < POLL_INTERVAL then
			return
		end
		pollElapsed = 0
		if not (barFrame and barFrame:IsShown()) then
			StopPoll()
			return
		end
		if IsGCDInactive() then
			StopGCD()
		end
	end)
	pollFrame:Show()
end

-- ---------------------------------------------------------------------------
-- SPELL_UPDATE_COOLDOWN handler
-- ---------------------------------------------------------------------------
local function OnSpellCooldownUpdate()
	if not ns.db or not ns.db.gcdBar.enable then
		return
	end
	if not (fillBar and barFrame and C_Spell_GetSpellCooldownDuration) then
		return
	end

	local durObj = C_Spell_GetSpellCooldownDuration(GCD_SPELL_ID)
	if IsGCDInactive() then
		StopGCD()
		return
	end

	barFrame:Show()
	fillBar:SetMinMaxValues(0, 1)
	fillBar:SetTimerDuration(durObj, Enum_StatusBarInterpolation, Enum_StatusBarTimerDirection)
	if sparkTex then
		sparkTex:SetShown(ns.db.gcdBar.showSpark)
	end
	StartPoll()
end

function GCDBar:ACTIONBAR_UPDATE_COOLDOWN()
	OnSpellCooldownUpdate()
end

-- ---------------------------------------------------------------------------
-- Update trough + fill anchor to current height
-- ---------------------------------------------------------------------------
-- The trough and fill cover only the TOP (db.height) pixels of barFrame.
-- Their BOTTOMRIGHT stops SHADOW_H pixels above the barFrame's own bottom,
-- leaving SHADOW_H uncovered — that strip shows the shadow texture beneath.
local function ApplyBodyAnchors(h)
	if trough then
		trough:ClearAllPoints()
		trough:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
		trough:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", 0, SHADOW_H)
	end
	if fillBar then
		fillBar:ClearAllPoints()
		fillBar:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
		fillBar:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", 0, SHADOW_H)
	end
end

-- ---------------------------------------------------------------------------
-- Bar construction
-- ---------------------------------------------------------------------------
local function BuildBar()
	if barFrame then
		return
	end

	local db = ns.db.gcdBar
	local w = db.width or DEFAULTS.width
	local h = db.height or DEFAULTS.height

	-- Total frame height = bar body + shadow strip.
	barFrame = CreateFrame("Frame", "NexEnhanceGCDBar", ns.UIParent)
	barFrame:SetSize(w, h + SHADOW_H)
	barFrame:SetFrameStrata("LOW")
	barFrame:EnableMouse(false)

	local base = barFrame:GetFrameLevel()

	-- Trough: near-black background, bar body only (not shadow strip).
	trough = barFrame:CreateTexture(nil, "BACKGROUND", nil, -4)
	trough:SetColorTexture(0.06, 0.06, 0.06, 0.95)
	barFrame.trough = trough

	-- Class-colour fill StatusBar: same bounds as trough.
	fillBar = CreateFrame("StatusBar", nil, barFrame)
	fillBar:SetFrameLevel(base + 2)
	fillBar:SetStatusBarTexture(C.Media.Textures.statusbar)
	fillBar:SetMinMaxValues(0, 1)
	fillBar:SetValue(0)
	local cc = C.ClassColor
	fillBar:SetStatusBarColor(cc[1], cc[2], cc[3], 0.90)

	-- Spark: anchored to fill's right edge — auto-tracks as fill depletes.
	sparkTex = fillBar:CreateTexture(nil, "OVERLAY")
	sparkTex:SetTexture(SPARK_TEX)
	sparkTex:SetBlendMode("ADD")
	sparkTex:SetAlpha(0.85)
	sparkTex:SetWidth(16)
	sparkTex:SetHeight(math_max(h * 4, 16))
	sparkTex:SetPoint("CENTER", fillBar:GetStatusBarTexture(), "RIGHT", 0, 0)
	sparkTex:Hide()

	ApplyBodyAnchors(h)

	barFrame:Hide()

	F.CreateMover(barFrame, "GCDBar", L["GCD Bar"], "BOTTOM", 0, 112)
end

-- ---------------------------------------------------------------------------
-- Apply current DB settings to the frame
-- ---------------------------------------------------------------------------
function GCDBar:ApplyLayout()
	if not barFrame then
		return
	end
	local db = ns.db.gcdBar
	local w = db.width or DEFAULTS.width
	local h = db.height or DEFAULTS.height

	barFrame:SetSize(w, h + SHADOW_H)
	ApplyBodyAnchors(h)

	if sparkTex then
		sparkTex:SetHeight(math_max(h * 4, 16))
	end

	local cc = C.ClassColor
	if fillBar then
		fillBar:SetStatusBarColor(cc[1], cc[2], cc[3], 0.90)
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function GCDBar:RegisterModuleEvents()
	if eventsRegistered then
		return
	end
	eventsRegistered = true
	spellCooldownDispatchId = ns:RegisterCooldownDispatchCallback(OnSpellCooldownUpdate, "SPELL_UPDATE_COOLDOWN")
	self:TrackEvent(eventHandles, "ACTIONBAR_UPDATE_COOLDOWN")
end

function GCDBar:UnregisterModuleEvents()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	if spellCooldownDispatchId then
		ns:UnregisterCooldownDispatchCallback(spellCooldownDispatchId)
		spellCooldownDispatchId = nil
	end
	ns:UnregisterModuleEventHandles(eventHandles)
	StopGCD()
end

function GCDBar:OnEnable()
	if not ns.db.gcdBar.enable then
		return
	end
	BuildBar()
	GCDBar:ApplyLayout()
	self:RegisterModuleEvents()
end

function GCDBar:OnDisable()
	self:UnregisterModuleEvents()
end

function GCDBar:OnSettingChanged(key, value)
	-- ApplyModuleSetting owns enable lifecycle.
	if key == "enable" then
		return
	end
	GCDBar:ApplyLayout()
end

function GCDBar:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable GCD Bar"], L["Show a bar that sweeps during the Global Cooldown. Hides completely between GCDs. Drag to position in Edit Mode."])

	local _, widthInit = builder:Slider(category, self, "width", L["GCD Bar Width"], L["Width of the GCD bar. Match to your action bar width for a seamless feel."], 50, 600, 2)

	local _, heightInit = builder:Slider(category, self, "height", L["GCD Bar Height"], L["Height of the GCD bar body in pixels. A 6-pixel shadow is always drawn below it."], 2, 30, 1)

	local _, sparkInit = builder:Checkbox(category, self, "showSpark", L["GCD Bar Spark"], L["Show the glowing spark that tracks the leading edge of the GCD sweep."])

	builder:DependsOn(widthInit, enableInit)
	builder:DependsOn(heightInit, enableInit)
	builder:DependsOn(sparkInit, enableInit)
end
