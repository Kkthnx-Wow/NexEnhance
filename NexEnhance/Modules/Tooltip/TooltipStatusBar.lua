--[[
	NexEnhance - Tooltip Status Bar
	-------------------------------------------------------------------------
	Unit-tooltip identity resolution and GameTooltipStatusBar paint/style.
	Split from Tooltip.lua so the Midnight GUID/reaction paint path is easier
	to audit. Fetches the Tooltip module and attaches methods, OnEnable calls
	Tooltip:SetupStatusBar().
--]]

local _, ns = ...
local F, C = ns.F, ns.C
local Tooltip = ns:GetModule("Tooltip")
if not Tooltip then
	return
end

local _G = _G
local pcall = pcall
local unpack = unpack
local hooksecurefunc = hooksecurefunc
local CreateFrame = CreateFrame

local UnitExists = UnitExists
local UnitGUID = UnitGUID
local UnitTokenFromGUID = UnitTokenFromGUID
local UnitIsPlayer = UnitIsPlayer
local UnitClass = UnitClass
local UnitReaction = UnitReaction
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local GetPlayerInfoByGUID = GetPlayerInfoByGUID
local IsInRaid, IsInGroup = IsInRaid, IsInGroup
local GetNumGroupMembers, GetNumSubgroupMembers = GetNumGroupMembers, GetNumSubgroupMembers
local UnitHealthPercent = _G["UnitHealthPercent"]
local CurveConstants = _G["CurveConstants"]
local ScaleTo100 = CurveConstants and CurveConstants.ScaleTo100
local DEAD = DEAD

local function GetCfg()
	return ns.db and ns.db.tooltip
end

local ResolveTipIdentity
local PaintStatusBar
local MatchLiveTokenForGUID
local UpdateHealthText

-- Retail unit-frame fill atlas ("-Status" is neutral/tintable). Desaturate
-- before SetStatusBarColor (same as ClassColors HUD bars) or the green atlas
-- muddies every tint. Classic UI-StatusBar is the fallback only.
local UNITFRAME_ATLAS = "UI-HUD-UnitFrame-Player-PortraitOff-Bar-Health-Status"
local function ApplyBarTexture(bar)
	if _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(UNITFRAME_ATLAS) then
		bar:SetStatusBarTexture(UNITFRAME_ATLAS)
	else
		bar:SetStatusBarTexture(C.Media.Textures.statusbar)
	end
end

local function SetBarColor(bar, r, g, b)
	if bar.SetStatusBarDesaturated then
		bar:SetStatusBarDesaturated(true)
	end
	bar:SetStatusBarColor(r, g, b)
end

-- ---------------------------------------------------------------------------
-- Unit resolution (secret-safe)
-- ---------------------------------------------------------------------------
-- Build a clean literal raid/party token for a GUID. On Midnight, secure frame
-- tooltips can return secret unit tokens even when the GUID is readable.
local function CleanTokenForGUID(guid)
	if not guid or F.IsSecret(guid) then
		return
	end
	if UnitGUID("player") == guid then
		return "player"
	end
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local tk = "raid" .. i
			local tg = UnitGUID(tk)
			if tg and F.NotSecret(tg) and tg == guid then
				return tk
			end
		end
	elseif IsInGroup() then
		for i = 1, GetNumSubgroupMembers() do
			local tk = "party" .. i
			local tg = UnitGUID(tk)
			if tg and F.NotSecret(tg) and tg == guid then
				return tk
			end
		end
	end
end

-- Live tokens Blizzard still hands us while GetUnit()/UnitTokenFromGUID are
-- restricted. Match GUID only - never assume mouseover/target identity.
MatchLiveTokenForGUID = function(guid)
	if not guid then
		return
	end
	local candidates = { "mouseover", "target", "focus", "targettarget" }
	for i = 1, #candidates do
		local cand = candidates[i]
		if UnitExists(cand) then
			local cg = UnitGUID(cand)
			if cg and F.NotSecret(cg) and cg == guid then
				return cand
			end
		end
	end
end

-- Authoritative identity for a unit tooltip: data.guid first, then a token that
-- provably maps to that GUID. Never trust a stale mouseover token alone.
ResolveTipIdentity = function(tt, data)
	if not tt or (tt.IsForbidden and tt:IsForbidden()) then
		return
	end

	local guid = data and data.guid
	if guid and F.IsSecret(guid) then
		guid = nil
	end
	if not guid and tt.GetPrimaryTooltipData then
		local primary = tt:GetPrimaryTooltipData()
		guid = primary and primary.guid
		if guid and F.IsSecret(guid) then
			guid = nil
		end
	end

	-- GameTooltipStatusBar stores the watched GUID via SetAttribute (secret-safe
	-- path Blizzard uses for UnitPercentHealthFromGUID). Prefer it when tip data
	-- GUID is missing/secret - that was why NPC tips fell to green.
	if not guid then
		local bar = (tt and tt.StatusBar) or GameTooltipStatusBar
		if bar and bar.GetAttribute then
			local bg = bar:GetAttribute("guid")
			if bg and F.NotSecret(bg) then
				guid = bg
			end
		end
	end

	local token
	local ok, _, u = pcall(function()
		return tt:GetUnit()
	end)
	-- GetUnit can return a *secret* token even when UnitGUID(u) is readable
	-- (secure nameplate/unit-frame tips). Never keep a secret token - APIs like
	-- UnitRealmRelationship are SecretArguments AllowedWhenUntainted.
	if ok and u and F.NotSecret(u) and UnitExists(u) then
		local g = UnitGUID(u)
		if g and F.NotSecret(g) then
			if not guid then
				guid = g
			end
			if g == guid then
				token = u
			end
		end
	elseif ok and u and F.IsSecret(u) then
		-- Still harvest a plain GUID if the secret token can feed UnitGUID
		-- (UnitGUID: SecretArguments AllowedWhenTainted on many paths).
		local gOk, g = pcall(UnitGUID, u)
		if gOk and g and F.NotSecret(g) and not guid then
			guid = g
		end
	end

	if guid and not token then
		token = CleanTokenForGUID(guid)
	end

	if guid and not token and UnitTokenFromGUID then
		-- UnitTokenFromGUID returns a plain token string.
		local tu = UnitTokenFromGUID(guid)
		if tu and F.NotSecret(tu) and UnitExists(tu) then
			token = tu
		end
	end

	-- Live tokens Blizzard still hands us while GetUnit()/UnitTokenFromGUID are
	-- restricted. Match GUID only - never assume mouseover/target identity.
	if guid and not token then
		token = MatchLiveTokenForGUID(guid)
	end

	local owner = tt.GetOwner and tt:GetOwner()
	local ownerUnit = owner and owner.GetAttribute and owner:GetAttribute("unit")
	if not token and ownerUnit and F.NotSecret(ownerUnit) and UnitExists(ownerUnit) then
		local g = UnitGUID(ownerUnit)
		if g and F.NotSecret(g) and (not guid or g == guid) then
			if not guid then
				guid = g
			end
			token = ownerUnit
		end
	end

	return guid, token
end

-- Own the fill colour: we wipe OnValueChanged for health-text flicker, so colour
-- is our job. Atlas bars need desaturation or every tint looks wrong.
PaintStatusBar = function(bar, data)
	if not bar then
		return
	end

	ApplyBarTexture(bar)
	bar.lockColor = true

	local guid, unit = ResolveTipIdentity(GameTooltip, data)

	-- Health-bar watch GUID is authoritative during UpdateUnitHealth ticks.
	if bar.GetAttribute then
		local bg = bar:GetAttribute("guid")
		if bg and F.NotSecret(bg) then
			guid = guid or bg
			local ug = unit and UnitGUID(unit)
			if not unit or not ug or F.IsSecret(ug) or ug ~= bg then
				unit = MatchLiveTokenForGUID(bg) or unit
			end
		end
	end

	local classFile
	if guid and GetPlayerInfoByGUID then
		local _, eClass = GetPlayerInfoByGUID(guid)
		if eClass and F.NotSecret(eClass) then
			classFile = eClass
		end
	end
	if not classFile and unit and UnitIsPlayer(unit) then
		local _, cf = UnitClass(unit)
		if cf and F.NotSecret(cf) then
			classFile = cf
		end
	end

	if classFile then
		local color = (_G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS)[classFile]
		if color then
			SetBarColor(bar, color.r, color.g, color.b)
			return
		end
	end

	if unit then
		local r, g, b = F.GetNpcReactionColor(unit)
		if r then
			SetBarColor(bar, r, g, b)
			return
		end
		if _G.GameTooltip_UnitColor then
			r, g, b = _G.GameTooltip_UnitColor(unit)
			if r and F.NotSecret(r) then
				SetBarColor(bar, r, g, b)
				return
			end
		end
		-- UnitReaction alone - keeps hostile red when selection APIs flake.
		local reaction = UnitReaction(unit, "player")
		local faction = reaction and _G.FACTION_BAR_COLORS and _G.FACTION_BAR_COLORS[reaction]
		if faction then
			SetBarColor(bar, faction.r, faction.g, faction.b)
			return
		end
	end

	-- Restricted identity: keep last paint, only seed green once so we never
	-- sit on an undyed atlas (dark grey). Prefer not stomping a good reaction.
	local cr, cg, cb = bar:GetStatusBarColor()
	if not cr or (cr == 1 and cg == 1 and cb == 1) or (cr == 0 and cg == 0 and cb == 0) then
		SetBarColor(bar, 0, 1, 0)
	end
end

function Tooltip:ResolveTipIdentity(tt, data)
	return ResolveTipIdentity(tt or self, data)
end

function Tooltip:GetDisplayedUnit(tt)
	local _, unit = ResolveTipIdentity(tt or self, nil)
	return unit
end

function Tooltip:GetUnitToken(tt)
	local _, unit = ResolveTipIdentity(tt or self, nil)
	return unit
end

-- Status bar -----------------------------------------------------------------
-- Colour + health text. Unit post-call paints once, UpdateUnitHealth re-paints
-- so we stay correct after SetWatch / percent updates.
--
-- Incident (Tooltip, Jul 2026): wiped OnValueChanged for text flicker -> no
-- Blizzard green + unit-frame atlas -> dark grey in instances. Classic status
-- texture + lockColor + always paint (class / reaction / green fallback).
function Tooltip:UpdateStatusBarColor(data)
	if not Tooltip:IsEnabled() then
		return
	end
	local bar = self.StatusBar or GameTooltipStatusBar
	if not bar then
		return
	end

	PaintStatusBar(bar, data)
	UpdateHealthText(bar)
end

-- Health text fontstring on the status bar.
local function EnsureStatusBarText(bar)
	if not bar or bar.Text then
		return
	end

	bar.Text = F.CreateFS(bar, 12, "")
	bar.Text:SetPoint("CENTER", bar, "CENTER", 0, 0)
	bar.Text:SetTextColor(1, 1, 1)
	bar.Text:SetDrawLayer("OVERLAY", 7)
end

-- Frame the health/status bar with our classic look without BackdropTemplate.
-- Blizzard's backdrop mixin calls GetWidth()/GetHeight() and divides those values
-- in Lua (Resources/Blizzard_SharedXML/Backdrop.lua:221+). Tooltip/statusbar sizes
-- can be Secret under Midnight, so even a plain child frame that ends up feeding
-- that math can crash while the world-cursor tooltip updates. Border pulled for
-- now while we confirm that's the culprit, just the dark fill remains.
local function StyleStatusBar(bar)
	bar = bar or GameTooltipStatusBar
	if not bar or bar.nexStyled then
		return
	end
	bar.nexStyled = true

	ApplyBarTexture(bar)

	local level = bar:GetFrameLevel()

	local bg = CreateFrame("Frame", nil, bar)
	bg:SetPoint("TOPLEFT", bar, "TOPLEFT", -0, 0)
	bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
	bg:SetFrameLevel(level > 0 and level - 1 or 0)
	local bgTexture = bg:CreateTexture(nil, "BACKGROUND")
	bgTexture:SetAllPoints()
	bgTexture:SetColorTexture(0.06, 0.06, 0.06, 0.9)
	bar.nexBG = bg

	EnsureStatusBarText(bar)
end

-- Optional health-bar placement. We capture Blizzard's default anchors once so
-- the "bottom" choice can restore them exactly, "top" re-anchors the bar above
-- the tooltip (it auto-tracks size since it pins to GameTooltip's top edge).
local savedBarPoints
local function RepositionStatusBar()
	if not Tooltip:IsEnabled() then
		return
	end
	local bar = GameTooltipStatusBar
	if not bar then
		return
	end

	if not savedBarPoints then
		savedBarPoints = {}
		for i = 1, bar:GetNumPoints() do
			savedBarPoints[i] = { bar:GetPoint(i) }
		end
	end

	bar:ClearAllPoints()
	local cfg = GetCfg()
	if cfg and cfg.statusBarPosition == "top" then
		bar:SetPoint("BOTTOMLEFT", GameTooltip, "TOPLEFT", 2, 2)
		bar:SetPoint("BOTTOMRIGHT", GameTooltip, "TOPRIGHT", -3, 2)
	elseif #savedBarPoints > 0 then
		for i = 1, #savedBarPoints do
			bar:SetPoint(unpack(savedBarPoints[i]))
		end
	else
		bar:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 2, -2)
		bar:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", -3, -2)
	end

	-- The bar is anchored on one edge only, so SetHeight drives its thickness.
	local cfg = GetCfg()
	bar:SetHeight((cfg and cfg.statusBarHeight) or 14)
end

-- Health text on the status bar. AbbreviateNumbers is whitelisted for secret
-- values and returns a secret string SetText accepts - we never inspect the
-- number. Falls back to UnitHealthPercent, then DEAD for corpses.
UpdateHealthText = function(bar)
	if not Tooltip:IsEnabled() then
		return
	end
	bar = bar or GameTooltipStatusBar
	if not bar then
		return
	end
	EnsureStatusBarText(bar)
	local text = bar.Text
	if not text then
		return
	end

	local unit = Tooltip.GetUnitToken(bar:GetParent())
	if not unit then
		text:SetText("")
		return
	end

	-- UnitIsDeadOrGhost: SecretArguments only.
	if UnitIsDeadOrGhost(unit) then
		text:SetText(DEAD)
		return
	end

	local okCur, cur = pcall(UnitHealth, unit)
	local okMax, maxHP = pcall(UnitHealthMax, unit)
	if okCur and okMax and cur and maxHP then
		local cfg = GetCfg()
		if cfg and cfg.healthBarText == "current" then
			text:SetText(F.ShortValue(cur))
		else
			text:SetFormattedText("%s / %s", F.ShortValue(cur), F.ShortValue(maxHP))
		end
		return
	end

	if UnitHealthPercent then
		-- UnitHealthPercent: SecretReturns - keep guard.
		local ok, percent = pcall(UnitHealthPercent, unit, true, ScaleTo100)
		if ok and percent and F.NotSecret(percent) then
			text:SetFormattedText("%d%%", percent)
			return
		end
	end

	text:SetText("")
end

-- Drive health text + fill colour. On modern clients UpdateUnitHealth is the
-- reliable path, we clear OnValueChanged (HealthBar_OnValueChanged) to stop
-- text flicker, so PaintStatusBar must run here every tick.
local function OnBarHealthUpdated(bar)
	if not Tooltip:IsEnabled() then
		return
	end
	PaintStatusBar(bar, nil)
	UpdateHealthText(bar)
end

local function HookBarHealth(bar)
	if not bar or bar.nexHealthHooked then
		return
	end
	bar.nexHealthHooked = true

	if bar.UpdateUnitHealth then
		bar:SetScript("OnValueChanged", nil)
		hooksecurefunc(bar, "UpdateUnitHealth", OnBarHealthUpdated)
	else
		bar:HookScript("OnValueChanged", OnBarHealthUpdated)
	end
end

function Tooltip:RepositionStatusBar()
	RepositionStatusBar()
end

function Tooltip:RefreshHealthText()
	UpdateHealthText(GameTooltipStatusBar)
end

function Tooltip:SetupStatusBar()
	StyleStatusBar()
	local GT = GameTooltip
	if GT.StatusBar and GT.StatusBar ~= GameTooltipStatusBar then
		StyleStatusBar(GT.StatusBar)
	end
	HookBarHealth(GameTooltipStatusBar)
	HookBarHealth(GT.StatusBar)
	if _G["GameTooltip_SetDefaultAnchor"] then
		hooksecurefunc("GameTooltip_SetDefaultAnchor", RepositionStatusBar)
	end
end
