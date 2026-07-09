--[[
	NexEnhance - Cursor Ring
	-------------------------------------------------------------------------
	A circular cooldown swipe that follows the mouse during the Global Cooldown
	and (optionally) while you cast/channel.

	Midnight: GCD uses C_Spell.GetSpellCooldownDuration(61304) +
	SetCooldownFromDurationObject — no GetTime() arithmetic. Cast uses
	UnitCastingDuration / UnitChannelDuration the same way.

	Art: Media/Cursor/CursorRing.tga — soft white donut (class-tinted). Used as
	both chrome and Cooldown swipe so progress stays circular, not a square fill.
	Cursor tracking OnUpdate only while visible.
--]]

local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local GetCursorPosition = GetCursorPosition
local CreateFrame = CreateFrame
local UIParent = UIParent
local UnitAffectingCombat = UnitAffectingCombat
local UnitCastingDuration = UnitCastingDuration
local UnitChannelDuration = UnitChannelDuration
local floor = math.floor

local GCD_SPELL_ID = 61304
local C_Spell_GetSpellCooldownDuration = C_Spell and C_Spell.GetSpellCooldownDuration

local POLL_INTERVAL = 0.05

ns:RegisterDefaults({
	cursorRing = {
		enable = false,
		showCast = true,
		size = 48,
		combatOnly = false,
	},
})

local CursorRing = ns:NewModule("CursorRing", "cursorRing", {
	group = "cursor",
	title = L["Cursor Ring"],
	order = 10,
	since = "1.6.0",
})

local spellCooldownDispatchId
local eventsRegistered = false
local eventHandles = {}

local root
local ringArt
local gcdCooldown
local castCooldown
local pollFrame
local pollElapsed = 0
local trackFrame
local lastX, lastY, lastScale
local gcdActive, castActive

local function RingTexture()
	return C.Media.Textures.cursorRing
end

local function db()
	return ns.db.cursorRing
end

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
	local durObj = C_Spell_GetSpellCooldownDuration(GCD_SPELL_ID)
	return DurationIsZero(durObj)
end

local function StopTrack()
	if trackFrame then
		trackFrame:SetScript("OnUpdate", nil)
		trackFrame:Hide()
	end
	lastX, lastY, lastScale = nil, nil, nil
end

local function StopPoll()
	if pollFrame then
		pollFrame:SetScript("OnUpdate", nil)
		pollFrame:Hide()
	end
	pollElapsed = 0
end

local function UpdateVisibility()
	if not root then
		return
	end
	local show = gcdActive or castActive
	if show and db().combatOnly and not UnitAffectingCombat("player") then
		show = false
	end
	root:SetShown(show)
	if show then
		if not trackFrame then
			trackFrame = CreateFrame("Frame")
		end
		trackFrame:SetScript("OnUpdate", function()
			if not (root and root:IsShown()) then
				StopTrack()
				return
			end
			local x, y = GetCursorPosition()
			local scale = UIParent:GetEffectiveScale()
			if scale == 0 then
				return
			end
			x, y = x / scale, y / scale
			if x == lastX and y == lastY and scale == lastScale then
				return
			end
			lastX, lastY, lastScale = x, y, scale
			root:ClearAllPoints()
			root:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
		end)
		trackFrame:Show()
	else
		StopTrack()
	end
end

local function ClearGCD()
	gcdActive = false
	if gcdCooldown then
		gcdCooldown:Clear()
		gcdCooldown:Hide()
	end
	UpdateVisibility()
	if not castActive then
		StopPoll()
	end
end

local function ClearCast()
	castActive = false
	if castCooldown then
		castCooldown:Clear()
		castCooldown:Hide()
	end
	UpdateVisibility()
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
		if gcdActive and IsGCDInactive() then
			ClearGCD()
		end
	end)
	pollFrame:Show()
end

local function ApplyGCD(durObj)
	if not (gcdCooldown and durObj) then
		return
	end
	if db().combatOnly and not UnitAffectingCombat("player") then
		ClearGCD()
		return
	end

	gcdCooldown:Show()
	gcdCooldown:SetCooldownFromDurationObject(durObj)
	F.MaskCooldownSwipeFromDurationObject(gcdCooldown, durObj)
	gcdActive = true
	UpdateVisibility()
	StartPoll()
end

local function OnSpellCooldownUpdate()
	if not db().enable then
		return
	end
	if not C_Spell_GetSpellCooldownDuration then
		return
	end

	local durObj = C_Spell_GetSpellCooldownDuration(GCD_SPELL_ID)
	if IsGCDInactive() then
		ClearGCD()
		return
	end
	ApplyGCD(durObj)
end

local function ApplyCastDuration(durObj)
	if not (castCooldown and durObj and db().showCast) then
		ClearCast()
		return
	end
	if DurationIsZero(durObj) then
		ClearCast()
		return
	end
	if db().combatOnly and not UnitAffectingCombat("player") then
		ClearCast()
		return
	end

	castCooldown:Show()
	castCooldown:SetCooldownFromDurationObject(durObj)
	F.MaskCooldownSwipeFromDurationObject(castCooldown, durObj)
	castActive = true
	UpdateVisibility()
end

local function RefreshCast()
	if not db().enable or not db().showCast then
		ClearCast()
		return
	end

	-- Prefer active cast, then channel. DurationObjects — no ms arithmetic.
	if UnitCastingDuration then
		local castDur = UnitCastingDuration("player")
		if castDur and not DurationIsZero(castDur) then
			ApplyCastDuration(castDur)
			return
		end
	end
	if UnitChannelDuration then
		local channelDur = UnitChannelDuration("player")
		if channelDur and not DurationIsZero(channelDur) then
			ApplyCastDuration(channelDur)
			return
		end
	end
	ClearCast()
end

function CursorRing:ACTIONBAR_UPDATE_COOLDOWN()
	OnSpellCooldownUpdate()
end

function CursorRing:UNIT_SPELLCAST_START()
	RefreshCast()
end

function CursorRing:UNIT_SPELLCAST_CHANNEL_START()
	RefreshCast()
end

function CursorRing:UNIT_SPELLCAST_DELAYED()
	RefreshCast()
end

function CursorRing:UNIT_SPELLCAST_CHANNEL_UPDATE()
	RefreshCast()
end

function CursorRing:UNIT_SPELLCAST_STOP()
	ClearCast()
end

function CursorRing:UNIT_SPELLCAST_FAILED()
	ClearCast()
end

function CursorRing:UNIT_SPELLCAST_INTERRUPTED()
	ClearCast()
end

function CursorRing:UNIT_SPELLCAST_CHANNEL_STOP()
	ClearCast()
end

function CursorRing:PLAYER_REGEN_ENABLED()
	if db().combatOnly then
		ClearGCD()
		ClearCast()
	end
end

local function StyleRingArt()
	if not ringArt then
		return
	end
	ringArt:SetTexture(RingTexture())
	ringArt:SetAllPoints()
	ringArt:SetBlendMode("ADD")
	local cc = C.ClassColor
	ringArt:SetVertexColor(cc[1], cc[2], cc[3], 1)
	ringArt:SetAlpha(0.55)
end

local function StyleCooldown(cd, alpha, inset)
	cd:ClearAllPoints()
	if inset and inset > 0 then
		cd:SetPoint("TOPLEFT", inset, -inset)
		cd:SetPoint("BOTTOMRIGHT", -inset, inset)
	else
		cd:SetAllPoints()
	end
	cd:SetDrawBling(false)
	cd:SetDrawEdge(false)
	cd:SetHideCountdownNumbers(true)
	cd:SetReverse(true)
	if cd.SetUseCircularEdge then
		cd:SetUseCircularEdge(true)
	end

	local cc = C.ClassColor
	local r, g, b, a = cc[1], cc[2], cc[3], alpha or 0.90
	-- Same donut as chrome — swipe reveals the ring, never a square fill.
	cd:SetSwipeTexture(RingTexture(), r, g, b, a)
	cd:SetSwipeColor(r, g, b, a)
end

local function BuildFrames()
	if root then
		return
	end

	local size = db().size or 48
	root = CreateFrame("Frame", "NexEnhanceCursorRing", UIParent)
	root:SetSize(size, size)
	root:SetFrameStrata("TOOLTIP")
	root:EnableMouse(false)
	root:Hide()

	-- Soft ring chrome (always visible while GCD/cast is active).
	ringArt = root:CreateTexture(nil, "BACKGROUND", nil, 0)
	StyleRingArt()

	-- Outer GCD swipe.
	gcdCooldown = CreateFrame("Cooldown", nil, root, "CooldownFrameTemplate")
	StyleCooldown(gcdCooldown, 0.90, 0)
	gcdCooldown:Hide()

	-- Inner cast swipe (slightly inset so both read as concentric).
	castCooldown = CreateFrame("Cooldown", nil, root, "CooldownFrameTemplate")
	StyleCooldown(castCooldown, 1.0, floor(size * 0.12))
	castCooldown:Hide()
end

function CursorRing:ApplyLayout()
	if not root then
		return
	end
	local size = db().size or 48
	root:SetSize(size, size)
	StyleRingArt()
	StyleCooldown(gcdCooldown, 0.90, 0)
	StyleCooldown(castCooldown, 1.0, floor(size * 0.12))
end

function CursorRing:RegisterModuleEvents()
	if eventsRegistered then
		return
	end
	eventsRegistered = true
	spellCooldownDispatchId = ns:RegisterCooldownDispatchCallback(OnSpellCooldownUpdate, "SPELL_UPDATE_COOLDOWN")
	self:TrackEvent(eventHandles, "ACTIONBAR_UPDATE_COOLDOWN")
	self:TrackEvent(eventHandles, "PLAYER_REGEN_ENABLED")
	self:TrackUnitEvent(eventHandles, "UNIT_SPELLCAST_START", nil, "player")
	self:TrackUnitEvent(eventHandles, "UNIT_SPELLCAST_CHANNEL_START", nil, "player")
	self:TrackUnitEvent(eventHandles, "UNIT_SPELLCAST_DELAYED", nil, "player")
	self:TrackUnitEvent(eventHandles, "UNIT_SPELLCAST_CHANNEL_UPDATE", nil, "player")
	self:TrackUnitEvent(eventHandles, "UNIT_SPELLCAST_STOP", nil, "player")
	self:TrackUnitEvent(eventHandles, "UNIT_SPELLCAST_FAILED", nil, "player")
	self:TrackUnitEvent(eventHandles, "UNIT_SPELLCAST_INTERRUPTED", nil, "player")
	self:TrackUnitEvent(eventHandles, "UNIT_SPELLCAST_CHANNEL_STOP", nil, "player")
end

function CursorRing:UnregisterModuleEvents()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	if spellCooldownDispatchId then
		ns:UnregisterCooldownDispatchCallback(spellCooldownDispatchId)
		spellCooldownDispatchId = nil
	end
	ns:UnregisterModuleEventHandles(eventHandles)
	ClearGCD()
	ClearCast()
	StopPoll()
	StopTrack()
	if root then
		root:Hide()
	end
end

function CursorRing:OnEnable()
	if not db().enable then
		return
	end
	BuildFrames()
	self:ApplyLayout()
	self:RegisterModuleEvents()
	-- Catch a GCD/cast already in flight when the module is toggled on.
	OnSpellCooldownUpdate()
	RefreshCast()
end

function CursorRing:OnDisable()
	self:UnregisterModuleEvents()
end

function CursorRing:OnSettingChanged(key, value)
	-- enable toggles go through OnEnable / OnDisable (Commands.ApplyModuleSetting).
	if key == "enable" then
		return
	end
	if key == "showCast" and not value then
		ClearCast()
	end
	self:ApplyLayout()
	if key == "combatOnly" and db().enable then
		OnSpellCooldownUpdate()
		RefreshCast()
	end
end

function CursorRing:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(
		category,
		self,
		"enable",
		L["Enable Cursor Ring"],
		L["Show a class-coloured cooldown ring under your cursor during the Global Cooldown (and optionally while casting)."]
	)

	local _, castInit = builder:Checkbox(
		category,
		self,
		"showCast",
		L["Show Cast Ring"],
		L["Also show an inner ring while you cast or channel."]
	)

	local _, combatInit = builder:Checkbox(
		category,
		self,
		"combatOnly",
		L["Combat Only"],
		L["Only show the cursor ring while you are in combat."]
	)

	local _, sizeInit = builder:Slider(
		category,
		self,
		"size",
		L["Cursor Ring Size"],
		L["Diameter of the cursor ring in pixels."],
		24,
		96,
		2
	)

	builder:DependsOn(castInit, enableInit)
	builder:DependsOn(combatInit, enableInit)
	builder:DependsOn(sizeInit, enableInit)
end
