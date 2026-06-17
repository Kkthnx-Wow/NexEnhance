--[[
	NexEnhance - Tooltip (core)
	-------------------------------------------------------------------------
	Reskins the game tooltips with our backdrop/border, rewrites the unit
	tooltip (class-coloured name, difficulty-coloured level, target line, NPC
	id, role/faction icons, mythic+ score), tidies the health/status bars and
	fonts, and provides a registration table so per-addon tooltips get skinned
	as they load.

	Originally ported from NDui's Tooltip suite by siweia, then reworked against
	ElvUI's Patch 12.0 Secret-Value model: secret-safety is concentrated in a
	couple of tiny primitives (F.IsSecret / IsSecretUnit) plus targeted checks at
	the read sites that actually need them - no global function wrappers, no
	OnSizeChanged backdrop guards. Untainted Blizzard code is allowed to read
	secrets, so we avoid tainting its layout path; status-bar chrome uses plain
	textures instead of BackdropTemplate because Blizzard's backdrop mixin does
	width / edgeSize in Lua. Midnight said "surprise, that's a secret now."

	This file owns the module; the sibling files (TooltipID, TooltipIcons,
	TooltipItemLevel, TooltipHoverTips, TooltipMountSource) fetch it with
	ns:GetModule("Tooltip") and add their own methods, all wired from OnEnable.
--]]

local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

-- Shared tooltip palette (single source of truth in Constants.lua): light-blue
-- labels used for the non-guildmate guild line below.
local LBL = C.Colors.label

-- Localised globals.
local _G = _G
local format, strfind, strupper, strlen = string.format, string.find, string.upper, string.len
local gsub, pairs, pcall, select = string.gsub, pairs, pcall, select
local C_Item_GetItemQualityByID = C_Item.GetItemQualityByID
local unpack = unpack
local hooksecurefunc = hooksecurefunc

local UnitExists = UnitExists
local UnitIsPlayer, UnitName, UnitPVPName, UnitClass = UnitIsPlayer, UnitName, UnitPVPName, UnitClass
local UnitRace, UnitLevel, UnitCreatureType, UnitClassification = UnitRace, UnitLevel, UnitCreatureType, UnitClassification
local UnitIsAFK, UnitIsDND, UnitIsConnected, UnitIsDeadOrGhost = UnitIsAFK, UnitIsDND, UnitIsConnected, UnitIsDeadOrGhost
local UnitReaction, UnitIsPVP, UnitFactionGroup, UnitRealmRelationship = UnitReaction, UnitIsPVP, UnitFactionGroup, UnitRealmRelationship
local UnitGroupRolesAssigned, GetRaidTargetIndex, GetGuildInfo, IsInGuild = UnitGroupRolesAssigned, GetRaidTargetIndex, GetGuildInfo, IsInGuild
local UnitIsWildBattlePet, UnitIsBattlePetCompanion, UnitBattlePetLevel = UnitIsWildBattlePet, UnitIsBattlePetCompanion, UnitBattlePetLevel
local UnitTokenFromGUID, UnitGUID, UnitHealth, UnitHealthMax = UnitTokenFromGUID, UnitGUID, UnitHealth, UnitHealthMax
local UnitIsUnit = UnitIsUnit
local UnitHealthPercent = _G["UnitHealthPercent"]
local GetCreatureDifficultyColor = GetCreatureDifficultyColor
local InCombatLockdown, IsShiftKeyDown = InCombatLockdown, IsShiftKeyDown

local C_ChallengeMode_GetDungeonScoreRarityColor = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor
local C_PlayerInfo_GetPlayerMythicPlusRatingSummary = C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary
local CurveConstants = _G["CurveConstants"]
local ScaleTo100 = CurveConstants and CurveConstants.ScaleTo100
local GetDisplayedItem = TooltipUtil and TooltipUtil.GetDisplayedItem

-- GameTooltip cast for fields the type stubs don't expose (status bar/etc).
local GT = GameTooltip ---@type any

local ICON_LIST = ICON_LIST
local HIGHLIGHT_FONT_COLOR = HIGHLIGHT_FONT_COLOR

-- A unit is "secret" to us when the token itself is a secret value or when its
-- identity is currently hidden (instances / restricted). Both checks live in the
-- shared F secret API (modelled on oUF's, by Simpy).
local function IsSecretUnit(unit)
	return F.IsSecret(unit) or F.IsSecretUnit(unit)
end

-- Retail unit-frame fill atlas, matching the experience bar. The "-Status"
-- variant is neutral/tintable, so the per-unit SetStatusBarColor still reads
-- correctly. Falls back to our shared statusbar texture if unavailable.
local UNITFRAME_ATLAS = "UI-HUD-UnitFrame-Player-PortraitOff-Bar-Health-Status"
local function ApplyBarTexture(bar)
	if _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(UNITFRAME_ATLAS) then
		bar:SetStatusBarTexture(UNITFRAME_ATLAS)
	else
		bar:SetStatusBarTexture(C.Media.Textures.statusbar)
	end
end

ns:RegisterDefaults({
	tooltip = {
		enable = true,
		hideInCombat = false,
		factionIcon = true,
		lfdRole = true,
		hideTitle = false,
		hideRealm = false,
		hideRank = false,
		mythicScore = true,
		qualityBorder = true,
		statusBarPosition = "bottom", -- "bottom" | "top"
		statusBarHeight = 6,
		healthBarText = "both", -- "current" | "both"
		showIDs = true,
		showIcons = true,
		showItemLevel = true,
		itemLevelByShift = true,
		hoverTips = true,
		mountSource = true,
	},
})

local Tooltip = ns:NewModule("Tooltip", "tooltip", { group = "tooltip", title = L["Tooltip"], order = 10 })

-- Active settings table; bound in OnEnable, read live everywhere.
local cfg

-- Forward declaration: the health-text updater is defined below but referenced
-- by the unit post-call above it.
local UpdateHealthText

local classification = {
	elite = " |cffcc8800" .. ELITE .. "|r",
	rare = " |cffff99cc" .. L["Rare"] .. "|r",
	rareelite = " |cffff99cc" .. L["Rare"] .. "|r " .. "|cffcc8800" .. ELITE .. "|r",
	worldboss = " |cffff0000" .. BOSS .. "|r",
}
local npcIDstring = "%s " .. C.InfoColor .. "%s|r"
local specPrefix = "|cffFFCC00" .. SPECIALIZATION .. ": " .. C.InfoColor

local FACTION_COLORS = {
	[FACTION_ALLIANCE] = "|cff4080ff%s|r",
	[FACTION_HORDE] = "|cffff5040%s|r",
}

-- ---------------------------------------------------------------------------
-- Unit resolution (secret-safe, ElvUI-style)
-- ---------------------------------------------------------------------------
function Tooltip:GetDisplayedUnit(tt)
	tt = tt or self
	if tt.GetPrimaryTooltipData then
		if tt.IsTooltipType and not tt:IsTooltipType(Enum.TooltipDataType.Unit) then
			return
		end
		local data = tt:GetPrimaryTooltipData()
		local guid = data and data.guid
		if guid and F.NotSecret(guid) then
			return UnitTokenFromGUID(guid)
		end
		return
	end

	local _, unit = tt:GetUnit()
	return unit
end

function Tooltip:GetUnitToken(tt)
	tt = tt or self
	if not tt or tt:IsForbidden() then
		return
	end

	local mouseoverExists = UnitExists("mouseover")
	local mouseover = (F.NotSecret(mouseoverExists) and mouseoverExists) and "mouseover" or nil

	local unit = Tooltip.GetDisplayedUnit(tt)
	if unit then
		local exists = F.NotSecret(unit) and UnitExists(unit)
		return (F.NotSecret(exists) and exists and unit) or mouseover
	end

	local owner = tt.GetOwner and tt:GetOwner()
	local ownerUnit = owner and owner.GetAttribute and owner:GetAttribute("unit")
	if ownerUnit then
		local exists = F.NotSecret(ownerUnit) and UnitExists(ownerUnit)
		return (F.NotSecret(exists) and exists and ownerUnit) or mouseover
	end

	return mouseover
end

-- Kept for the sibling item-level module.
function Tooltip:UnitExists(unit)
	if not unit or IsSecretUnit(unit) then
		return
	end
	local exists = UnitExists(unit)
	return F.NotSecret(exists) and exists
end

local function replaceSpecInfo(str)
	return strfind(str, "%s") and specPrefix .. str or str
end

-- Difficulty/level helpers ---------------------------------------------------
function Tooltip:GetLevelLine()
	local info = self.GetTooltipData and self:GetTooltipData()
	if info and info.lines then
		for i = 2, #info.lines do
			local line = info.lines[i]
			local linetext = line and line.leftText
			if linetext and F.NotSecret(linetext) and strfind(linetext, LEVEL) then
				return _G["GameTooltipTextLeft" .. i], i
			end
		end
	end

	for i = 2, self:NumLines() do
		local tiptext = _G["GameTooltipTextLeft" .. i]
		if not tiptext then
			break
		end
		local linetext = tiptext:GetText()
		if linetext and F.NotSecret(linetext) and strfind(linetext, LEVEL) then
			return tiptext, i
		end
	end
end

function Tooltip:GetTarget(unit)
	if F.IsSecret(unit) then
		return ""
	end
	local isPlayerTarget = UnitIsUnit(unit, "player")
	if F.NotSecret(isPlayerTarget) and isPlayerTarget then
		return format("|cffff0000%s|r", ">" .. strupper(YOU) .. "<")
	end
	local name = UnitName(unit)
	if not name or F.IsSecret(name) then
		name = ""
	end
	return F.ColorStr(F.UnitColor(unit)) .. name .. "|r"
end

-- Faction / role frames ------------------------------------------------------
function Tooltip:InsertFactionFrame(faction)
	if not self.factionFrame then
		local f = self:CreateTexture(nil, "OVERLAY")
		f:SetPoint("TOPRIGHT", -10, -10)
		f:SetBlendMode("ADD")
		f:SetSize(46, 44)
		self.factionFrame = f
	end
	-- Clean Alliance/Horde crests from the Mount Journal filter buttons.
	self.factionFrame:SetAtlas("MountJournalIcons-" .. faction)
	self.factionFrame:Show()
end

local roleAtlas = {
	TANK = "UI-LFG-RoleIcon-Tank-Background",
	HEALER = "UI-LFG-RoleIcon-Healer-Background",
	DAMAGER = "UI-LFG-RoleIcon-DPS-Background",
}

function Tooltip:InsertRoleFrame(role)
	local atlas = roleAtlas[role]
	if not atlas then
		return
	end
	if not self.roleFrame then
		local f = self:CreateTexture(nil, "OVERLAY")
		f:SetPoint("TOPRIGHT", self, -2, -2)
		f:SetSize(24, 24)
		self.roleFrame = f
	end
	self.roleFrame:SetAtlas(atlas)
	self.roleFrame:Show()
end

-- Faction line rewrite (AddLinePreCall) -------------------------------------
function Tooltip:UpdateFactionLine(lineData)
	if self:IsForbidden() or not self:IsTooltipType(Enum.TooltipDataType.Unit) then
		return
	end

	local unit = Tooltip.GetUnitToken(self)
	if not unit then
		return
	end

	local isPlayer = UnitIsPlayer(unit)
	isPlayer = F.NotSecret(isPlayer) and isPlayer
	local unitClass = isPlayer and UnitClass(unit)
	if unitClass and F.IsSecret(unitClass) then
		unitClass = nil
	end
	local unitCreature = UnitCreatureType(unit)
	if unitCreature and F.IsSecret(unitCreature) then
		unitCreature = nil
	end

	local linetext = lineData.leftText
	if not linetext or F.IsSecret(linetext) then
		return
	end

	if linetext == PVP then
		return true
	elseif FACTION_COLORS[linetext] then
		if cfg.factionIcon then
			return true
		else
			lineData.leftText = format(FACTION_COLORS[linetext], linetext)
		end
	elseif unitClass and F.NotSecret(unitClass) and strfind(linetext, unitClass) then
		lineData.leftText = gsub(linetext, "(.-)%S+$", replaceSpecInfo)
	elseif unitCreature and F.NotSecret(unitCreature) and linetext == unitCreature then
		return true
	end
end

-- Default-border tint --------------------------------------------------------
-- The default Blizzard tooltip is NOT a TooltipBackdropTemplate, so it has no
-- :SetBackdropBorderColor. It does own a NineSlice panel whose border pieces we
-- can tint directly. Passing no colour (or white) restores Blizzard's default.
local function SetDefaultBorderColor(tip, r, g, b)
	local nineSlice = tip and tip.NineSlice
	if nineSlice and nineSlice.SetBorderColor then
		nineSlice:SetBorderColor(r or 1, g or 1, b or 1)
	end
end

-- Reset transient tooltip state here (ElvUI does the same on cleared, not hide).
function Tooltip:OnTooltipCleared()
	if self:IsForbidden() then
		return
	end

	if self.nexQualityBorder then
		self.nexQualityBorder = nil
		SetDefaultBorderColor(self)
	end

	if self.factionFrame and self.factionFrame:IsShown() then
		self.factionFrame:Hide()
	end
	if self.roleFrame and self.roleFrame:IsShown() then
		self.roleFrame:Hide()
	end

	local bar = GameTooltipStatusBar
	if bar and bar.Text then
		bar.Text:SetText("")
	end
end

local function OnGameTooltipHide()
	if GameTooltip:IsForbidden() then
		return
	end
	-- Hide unconditionally: Hide() is a no-op when already hidden, and once a
	-- secret health value is pushed into the bar IsShown() may itself be secret.
	local bar = GameTooltipStatusBar
	if bar then
		bar:Hide()
	end
end

-- Mythic+ score --------------------------------------------------------------
local function GetDungeonScore(score)
	local color = (C_ChallengeMode_GetDungeonScoreRarityColor and C_ChallengeMode_GetDungeonScoreRarityColor(score)) or HIGHLIGHT_FONT_COLOR
	return color:WrapTextInColorCode(score)
end

function Tooltip:ShowUnitMythicPlusScore(unit)
	if not cfg.mythicScore or not C_PlayerInfo_GetPlayerMythicPlusRatingSummary then
		return
	end
	local summary = C_PlayerInfo_GetPlayerMythicPlusRatingSummary(unit)
	local score = summary and summary.currentSeasonScore
	if score and score > 0 then
		self:AddLine(format(L["Mythic+ Score: %s"], GetDungeonScore(score)))
	end
end

-- Combat hide ----------------------------------------------------------------
local function ShouldHideInCombat()
	-- Hide in combat unless Shift is held (Shift always reveals).
	if not cfg.hideInCombat then
		return false
	end
	return not IsShiftKeyDown()
end

local function CheckUnitStatus(func, unit, text)
	local status = func(unit)
	return F.NotSecret(status) and status and text
end

-- The main unit tooltip rewrite ---------------------------------------------
function Tooltip:OnTooltipSetUnit(data)
	if self:IsForbidden() or self ~= GameTooltip then
		return
	end

	if ShouldHideInCombat() and InCombatLockdown() then
		self:Hide()
		return
	end

	local unit = Tooltip.GetUnitToken(self)
	if not unit then
		return
	end

	local isShiftKeyDown = IsShiftKeyDown()
	local isPlayer = UnitIsPlayer(unit)
	isPlayer = F.NotSecret(isPlayer) and isPlayer

	if isPlayer then
		local name, realm = UnitName(unit)
		-- Under restricted identity the name can be secret; fall back so the
		-- concatenations below never operate on a secret value.
		if not name or F.IsSecret(name) then
			name = UNKNOWN or "Unknown"
		end
		local pvpName = UnitPVPName(unit)
		local relationship = UnitRealmRelationship(unit)
		if not cfg.hideTitle and pvpName and F.NotSecret(pvpName) and pvpName ~= "" then
			name = pvpName
		end
		if realm and F.NotSecret(realm) and realm ~= "" then
			if isShiftKeyDown or not cfg.hideRealm then
				name = name .. "-" .. realm
			elseif relationship == LE_REALM_RELATION_COALESCED then
				name = name .. FOREIGN_SERVER_LABEL
			elseif relationship == LE_REALM_RELATION_VIRTUAL then
				name = name .. INTERACTIVE_SERVER_LABEL
			end
		end

		local connected = UnitIsConnected(unit)
		local offline = F.NotSecret(connected) and not connected and PLAYER_OFFLINE
		local status = CheckUnitStatus(UnitIsAFK, unit, AFK) or CheckUnitStatus(UnitIsDND, unit, DND) or offline
		if status then
			status = format(" |cffffcc00[%s]|r", status)
		end
		GameTooltipTextLeft1:SetFormattedText("%s", name .. (status or ""))

		if cfg.factionIcon then
			local faction = UnitFactionGroup(unit)
			if F.NotSecret(faction) and faction ~= "Neutral" then
				Tooltip.InsertFactionFrame(self, faction)
			end
		end

		if cfg.lfdRole then
			local role = UnitGroupRolesAssigned(unit)
			if role and role ~= "NONE" then
				Tooltip.InsertRoleFrame(self, role)
			end
		end

		local guildName, rank, rankIndex, guildRealm = GetGuildInfo(unit)
		local hasText = GameTooltipTextLeft2:GetText()
		if guildName and F.NotSecret(guildName) and hasText then
			local myGuild, _, _, myGuildRealm = GetGuildInfo("player")
			local sameGuild = IsInGuild() and F.NotSecret(myGuild) and guildName == myGuild
			if sameGuild and guildRealm and myGuildRealm then
				sameGuild = F.NotSecret(guildRealm) and F.NotSecret(myGuildRealm) and guildRealm == myGuildRealm
			end
			if sameGuild then
				GameTooltipTextLeft2:SetTextColor(0.25, 1, 0.25)
			else
				GameTooltipTextLeft2:SetTextColor(LBL[1], LBL[2], LBL[3])
			end

			if F.NotSecret(rankIndex) then
				rankIndex = (rankIndex or 0) + 1
				local rankText = (not cfg.hideRank and rank and F.NotSecret(rank) and rank) or ""
				local displayGuild = guildName
				if guildRealm and F.NotSecret(guildRealm) and isShiftKeyDown then
					displayGuild = guildName .. "-" .. guildRealm
				end
				if F.NotSecret(displayGuild) and strlen(displayGuild) > 31 and not isShiftKeyDown then
					displayGuild = "..."
				end
				GameTooltipTextLeft2:SetText("<" .. displayGuild .. "> " .. rankText .. "(" .. rankIndex .. ")")
			end
		end
	end

	local hexColor = F.ColorStr(F.UnitColor(unit))
	local text = GameTooltipTextLeft1:GetText()
	if text then
		local ricon = GetRaidTargetIndex(unit)
		local rionStr = ""
		if ricon and F.NotSecret(ricon) and ricon <= 8 then
			rionStr = ICON_LIST[ricon] .. "18|t "
		end
		GameTooltipTextLeft1:SetFormattedText("%s%s%s", rionStr, hexColor, text)
	end

	local dead = UnitIsDeadOrGhost(unit)
	local alive = F.NotSecret(dead) and not dead
	local level
	local isWildPet = UnitIsWildBattlePet(unit)
	local isPetCompanion = UnitIsBattlePetCompanion(unit)
	if (F.NotSecret(isWildPet) and isWildPet) or (F.NotSecret(isPetCompanion) and isPetCompanion) then
		level = UnitBattlePetLevel(unit)
	else
		level = UnitLevel(unit)
	end

	if level and F.NotSecret(level) then
		local boss
		if level == -1 then
			boss = "|cffff0000??|r"
		end

		local diff = GetCreatureDifficultyColor(level)
		local classify = UnitClassification(unit)
		local classifySuffix = (classify and F.NotSecret(classify) and classification[classify]) or ""
		local textLevel = format("%s%s%s|r", F.ColorStr(diff.r, diff.g, diff.b), boss or format("%d", level), classifySuffix)
		local tiptextLevel = Tooltip.GetLevelLine(self)
		local unitClass = isPlayer and select(1, UnitClass(unit))
		if unitClass and F.IsSecret(unitClass) then
			unitClass = nil
		end
		if tiptextLevel then
			local reaction = UnitReaction(unit, "player")
			local standingText = (not isPlayer and reaction and F.NotSecret(reaction) and hexColor .. (_G["FACTION_STANDING_LABEL" .. reaction] or "") .. "|r ") or ""
			local pvp = UnitIsPVP(unit)
			local pvpFlag = (isPlayer and F.NotSecret(pvp) and pvp and format(" |cffff0000%s|r", PVP)) or ""
			local race = isPlayer and UnitRace(unit)
			local creatureType = (not isPlayer) and UnitCreatureType(unit)
			local unitClassStr = ""
			if isPlayer and F.NotSecret(race) and F.NotSecret(unitClass) then
				unitClassStr = format("%s %s", race or "", hexColor .. (unitClass or "") .. "|r")
			elseif creatureType and F.NotSecret(creatureType) then
				unitClassStr = creatureType
			end

			tiptextLevel:SetFormattedText("%s%s %s %s", textLevel, pvpFlag, standingText .. unitClassStr, (not alive and "|cffCCCCCC" .. DEAD .. "|r" or ""))
		end
	end

	local targetUnit = unit .. "target"
	local targetExists = UnitExists(targetUnit)
	if F.NotSecret(targetExists) and targetExists then
		local targetIcon = GetRaidTargetIndex(targetUnit)
		local targetIconStr
		if targetIcon and F.NotSecret(targetIcon) and targetIcon <= 8 then
			targetIconStr = ICON_LIST[targetIcon] .. "10|t"
		end
		self:AddLine(TARGET .. ": " .. format("%s%s", targetIconStr or "", Tooltip.GetTarget(self, targetUnit)))
	end

	if not isPlayer and isShiftKeyDown then
		local guid = (data and data.guid) or UnitGUID(unit)
		local npcID = F.GetNPCID(guid)
		if npcID then
			self:AddLine(format(npcIDstring, "NpcID:", npcID))
		end
	end

	if isPlayer then
		if cfg.showItemLevel and Tooltip.InspectUnitItemLevel then
			Tooltip.InspectUnitItemLevel(self, unit)
		end
		Tooltip.ShowUnitMythicPlusScore(self, unit)
	end
end

-- Status bar -----------------------------------------------------------------
-- Colour the bar from the unit, and seed the health text. Runs as the Unit
-- post-call, which gives us the exact tooltip Blizzard is updating.
function Tooltip:UpdateStatusBarColor()
	local bar = self.StatusBar or GameTooltipStatusBar
	if not bar then
		return
	end

	local unit = Tooltip.GetUnitToken(self)
	if unit then
		bar:SetStatusBarColor(F.UnitColor(unit))
	else
		bar:SetStatusBarColor(0.6, 0.6, 0.6)
	end

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
-- now while we confirm that's the culprit; just the dark fill remains.
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
-- the "bottom" choice can restore them exactly; "top" re-anchors the bar above
-- the tooltip (it auto-tracks size since it pins to GameTooltip's top edge).
local savedBarPoints
local function RepositionStatusBar()
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
	bar:SetHeight((cfg and cfg.statusBarHeight) or 14)
end

-- Health text on the status bar (modelled on ElvUI's UpdateUnitHealth). Shows
-- current / max via AbbreviateNumbers, which is whitelisted for secret values
-- and returns a secret string SetText accepts, so we never inspect the number.
-- Falls back to a normalised percent, and to DEAD for corpses.
function UpdateHealthText(bar)
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

	-- Dead/ghost flag may itself be a secret boolean in combat; only act on it
	-- when readable, otherwise fall through to the numeric display.
	local dead = UnitIsDeadOrGhost(unit)
	if F.NotSecret(dead) and dead then
		text:SetText(DEAD)
		return
	end

	local okCur, cur = pcall(UnitHealth, unit)
	local okMax, maxHP = pcall(UnitHealthMax, unit)
	if okCur and okMax and cur and maxHP then
		if cfg and cfg.healthBarText == "current" then
			text:SetText(F.ShortValue(cur))
		else
			text:SetFormattedText("%s / %s", F.ShortValue(cur), F.ShortValue(maxHP))
		end
		return
	end

	if UnitHealthPercent then
		local ok, percent = pcall(UnitHealthPercent, unit, true, ScaleTo100)
		if ok and percent and F.NotSecret(percent) then
			text:SetFormattedText("%d%%", percent)
			return
		end
	end

	text:SetText("")
end

-- Drive a status bar's health text. On modern clients the bar exposes
-- UpdateUnitHealth (the path Blizzard calls reliably); we post-hook it and clear
-- the default OnValueChanged handler that otherwise causes flicker. On older
-- clients we post-hook OnValueChanged instead (never replace it).
local function HookBarHealth(bar)
	if not bar or bar.nexHealthHooked then
		return
	end
	bar.nexHealthHooked = true

	if bar.UpdateUnitHealth then
		bar:SetScript("OnValueChanged", nil)
		hooksecurefunc(bar, "UpdateUnitHealth", UpdateHealthText)
	else
		bar:HookScript("OnValueChanged", UpdateHealthText)
	end
end

-- Quality border -------------------------------------------------------------
-- We never reskin or reposition the tooltip; we only tint Blizzard's own
-- default (NineSlice) border by item quality.
function Tooltip:UpdateItemQualityBorder()
	if cfg.qualityBorder and GetDisplayedItem then
		local _, link = GetDisplayedItem(self)
		if link then
			local quality = C_Item_GetItemQualityByID(link)
			local color = C.QualityColors[quality or 1]
			if color then
				self.nexQualityBorder = true
				SetDefaultBorderColor(self, color.r, color.g, color.b)
				return
			end
		end
	end
	self.nexQualityBorder = nil
	SetDefaultBorderColor(self)
end

function Tooltip:ResetUnit(btn)
	if GameTooltip:IsForbidden() then
		return
	end
	if GameTooltip:IsShown() and btn == "LSHIFT" and Tooltip:UnitExists("mouseover") then
		GT:RefreshData()
	end
end

-- ---------------------------------------------------------------------------
-- Per-addon registration (sibling modules hook addons as they load, e.g. hover
-- tips for Blizzard_Communities). No reskinning happens here.
-- ---------------------------------------------------------------------------
local tipTable = {}
function Tooltip:RegisterTooltips(addon, func)
	tipTable[addon] = func
end

function Tooltip:ADDON_LOADED(addon)
	if tipTable[addon] then
		tipTable[addon]()
		tipTable[addon] = nil
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function Tooltip:OnEnable()
	cfg = ns.db.tooltip

	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, Tooltip.OnTooltipSetUnit)
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, Tooltip.UpdateStatusBarColor)
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, Tooltip.UpdateItemQualityBorder)
		if TooltipDataProcessor.AddLinePreCall then
			TooltipDataProcessor.AddLinePreCall(Enum.TooltipDataLineType.None, Tooltip.UpdateFactionLine)
		end
	end

	-- Frame the health/status bar and create its health-text fontstring.
	StyleStatusBar()
	if GT.StatusBar and GT.StatusBar ~= GameTooltipStatusBar then
		StyleStatusBar(GT.StatusBar)
	end

	-- Drive the health text the same way ElvUI does on retail. HookBarHealth is
	-- self-guarded, so passing the same bar twice is a no-op.
	HookBarHealth(GameTooltipStatusBar)
	HookBarHealth(GT.StatusBar)

	-- Blizzard re-anchors the status bar whenever the tooltip takes its default
	-- anchor, so re-apply our placement there instead of on every health tick.
	if _G["GameTooltip_SetDefaultAnchor"] then
		hooksecurefunc("GameTooltip_SetDefaultAnchor", RepositionStatusBar)
	end

	GameTooltip:HookScript("OnTooltipCleared", Tooltip.OnTooltipCleared)
	hooksecurefunc(GameTooltip, "Hide", OnGameTooltipHide)

	-- Element add-ons (defined in sibling files).
	if cfg.showIcons and Tooltip.ReskinTooltipIcons then
		Tooltip:ReskinTooltipIcons()
	end
	if cfg.showIDs and Tooltip.SetupTooltipID then
		Tooltip:SetupTooltipID()
	end
	if cfg.showItemLevel and Tooltip.SetupItemLevel then
		Tooltip:SetupItemLevel()
	end
	if cfg.hoverTips and Tooltip.SetupHoverTips then
		Tooltip:SetupHoverTips()
	end
	if cfg.mountSource and Tooltip.SetupMountSource then
		Tooltip:SetupMountSource()
	end

	self:RegisterEvent("MODIFIER_STATE_CHANGED", "ResetUnit")

	self:RegisterEvent("ADDON_LOADED")
	-- Run any registrations for addons already loaded this session.
	for addon, func in pairs(tipTable) do
		if C_AddOns.IsAddOnLoaded(addon) then
			func()
			tipTable[addon] = nil
		end
	end
end

function Tooltip:OnSettingChanged(key)
	if key == "statusBarPosition" or key == "statusBarHeight" then
		RepositionStatusBar()
	elseif key == "healthBarText" then
		local bar = GameTooltipStatusBar
		if bar and bar:IsShown() then
			UpdateHealthText()
		end
	end
end

function Tooltip:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Tooltip"], L["Enhance the game tooltips with extra info (reload to fully disable)."])
	local _, barPosInit = builder:Dropdown(category, self, "statusBarPosition", L["Health Bar Position"], L["Place the unit health bar at the top or bottom of the tooltip."], {
		{ value = "bottom", label = L["Bottom"] },
		{ value = "top", label = L["Top"] },
	})
	local _, barHeightInit = builder:Slider(category, self, "statusBarHeight", L["Health Bar Height"], L["Set the thickness of the unit health bar."], 12, 24, 1)
	local _, barTextInit = builder:Dropdown(category, self, "healthBarText", L["Health Bar Text"], L["Choose whether the health bar shows current health only or current / max."], {
		{ value = "current", label = L["Current Health"] },
		{ value = "both", label = L["Current / Max"] },
	})
	local _, factionInit = builder:Checkbox(category, self, "factionIcon", L["Show Faction Icon"], L["Show an Alliance/Horde icon on player tooltips."])
	local _, roleInit = builder:Checkbox(category, self, "lfdRole", L["Show Role Icon"], L["Show the group role (tank/healer/dps) icon on player tooltips."])
	local _, realmInit = builder:Checkbox(category, self, "hideRealm", L["Hide Realm Name"], L["Hide the realm name on players from other realms (hold Shift to reveal)."])
	local _, titleInit = builder:Checkbox(category, self, "hideTitle", L["Hide Player Title"], L["Hide PvP/guild titles on player names."])
	local _, scoreInit = builder:Checkbox(category, self, "mythicScore", L["Show Mythic+ Score"], L["Show the player's current-season Mythic+ rating."])
	local _, borderInit = builder:Checkbox(category, self, "qualityBorder", L["Quality-Coloured Border"], L["Tint Blizzard's default tooltip border by item quality."])
	local _, ilvlInit = builder:Checkbox(category, self, "showItemLevel", L["Show Item Level"], L["Show the inspected player's item level on their tooltip."])
	local _, ilvlShiftInit = builder:Checkbox(category, self, "itemLevelByShift", L["Item Level on Shift"], L["Only show the inspected item level while holding Shift."])
	local _, idsInit = builder:Checkbox(category, self, "showIDs", L["Show IDs"], L["Append spell, item, quest and other IDs to tooltips."])
	local _, iconsInit = builder:Checkbox(category, self, "showIcons", L["Show Icons"], L["Show an icon next to the tooltip title for spells, items and more."])
	local _, hoverInit = builder:Checkbox(category, self, "hoverTips", L["Hyperlink Hover Tips"], L["Show a tooltip when hovering item/spell links in chat."])
	local _, mountInit = builder:Checkbox(category, self, "mountSource", L["Show Mount Source"], L["Show a mount's collection status and source on aura tooltips (hold Shift over another player's mount buff)."])

	-- Every tooltip extra is meaningless while the module is off.
	builder:DependsOn(barPosInit, enableInit)
	builder:DependsOn(barHeightInit, enableInit)
	builder:DependsOn(barTextInit, enableInit)
	builder:DependsOn(factionInit, enableInit)
	builder:DependsOn(roleInit, enableInit)
	builder:DependsOn(realmInit, enableInit)
	builder:DependsOn(titleInit, enableInit)
	builder:DependsOn(scoreInit, enableInit)
	builder:DependsOn(borderInit, enableInit)
	builder:DependsOn(ilvlInit, enableInit)
	builder:DependsOn(idsInit, enableInit)
	builder:DependsOn(iconsInit, enableInit)
	builder:DependsOn(hoverInit, enableInit)
	builder:DependsOn(mountInit, enableInit)
	-- "Item Level on Shift" only applies when item level is shown at all.
	builder:DependsOn(ilvlShiftInit, ilvlInit)
end
