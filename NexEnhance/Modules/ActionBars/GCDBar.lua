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
	  Rides the fill's right edge automatically as SetValue depletes.
--]]

local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local GetTime = GetTime
local math_max = math.max

local GCD_SPELL_ID = 61304
local SHADOW_H = 6 -- pixels of shadow below the bar body
local SPARK_TEX = "Interface\\CastingBar\\UI-CastingBar-Spark"

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

-- ---------------------------------------------------------------------------
-- Frame handles and GCD state
-- ---------------------------------------------------------------------------
local barFrame
local trough -- dark bg texture covering bar body portion
local fillBar -- StatusBar covering bar body portion
local sparkTex

local gcdActive = false
local gcdStart = 0
local gcdDuration = 0

-- ---------------------------------------------------------------------------
-- GCD timing helper
-- ---------------------------------------------------------------------------
local C_Spell_GetSpellCooldown = C_Spell and C_Spell.GetSpellCooldown

local function GetGCDTiming()
	if not C_Spell_GetSpellCooldown then
		return nil, nil
	end
	local info = C_Spell_GetSpellCooldown(GCD_SPELL_ID)
	if type(info) ~= "table" then
		return nil, nil
	end
	local start = info.startTime
	local dur = info.duration
	if F.IsSecret(start) or F.IsSecret(dur) then
		return nil, nil
	end
	if not start or not dur or dur <= 0 or start <= 0 then
		return nil, nil
	end
	return start, dur
end

-- ---------------------------------------------------------------------------
-- Bar show / hide
-- ---------------------------------------------------------------------------
local function StopGCD()
	gcdActive = false
	if fillBar then
		fillBar:SetValue(0)
	end
	if sparkTex then
		sparkTex:Hide()
	end
	if barFrame then
		barFrame:Hide()
	end
end

-- ---------------------------------------------------------------------------
-- SPELL_UPDATE_COOLDOWN handler
-- ---------------------------------------------------------------------------
local function OnSpellCooldownUpdate()
	if not ns.db or not ns.db.gcdBar.enable then
		return
	end
	local start, dur = GetGCDTiming()
	if not start then
		StopGCD()
		return
	end
	if GetTime() >= start + dur then
		StopGCD()
		return
	end
	gcdStart = start
	gcdDuration = dur
	if not gcdActive then
		gcdActive = true
		if barFrame then
			barFrame:Show()
		end
	end
end

-- ---------------------------------------------------------------------------
-- OnUpdate — drives the fill; spark tracks automatically
-- ---------------------------------------------------------------------------
local function OnBarUpdate()
	if not gcdActive then
		return
	end
	local elapsed = GetTime() - gcdStart
	if elapsed >= gcdDuration then
		StopGCD()
		return
	end
	fillBar:SetValue(1 - (elapsed / gcdDuration))
	sparkTex:SetShown(ns.db.gcdBar.showSpark)
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

	-- Shadow: fills entire barFrame. The uncovered strip at the bottom
	-- (where trough/fill don't reach) is visible as a dark shadow.
	-- local shadow = barFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
	-- shadow:SetAllPoints()
	-- shadow:SetColorTexture(0, 0, 0, 0.65)
	-- barFrame.shadow = shadow

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

	barFrame:SetScript("OnUpdate", OnBarUpdate)
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
local eventFrame

local function EnsureEventFrame()
	if eventFrame then
		return
	end
	eventFrame = CreateFrame("Frame")
	eventFrame:SetScript("OnEvent", function(_, event)
		if event == "SPELL_UPDATE_COOLDOWN" then
			OnSpellCooldownUpdate()
		end
	end)
end

function GCDBar:OnEnable()
	BuildBar()
	GCDBar:ApplyLayout()
	EnsureEventFrame()
	eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
end

function GCDBar:OnSettingChanged(key, value)
	if key == "enable" then
		if value then
			BuildBar()
			GCDBar:ApplyLayout()
			EnsureEventFrame()
			eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
		else
			StopGCD()
			if eventFrame then
				eventFrame:UnregisterAllEvents()
			end
		end
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
