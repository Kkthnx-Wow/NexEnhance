--[[
	NexEnhance - Tooltip (core)
	-------------------------------------------------------------------------
	Reskins the game tooltips with our backdrop/border, rewrites the unit
	tooltip (class-coloured name, difficulty-coloured level, target line, NPC
	id, role/faction icons, mythic+ score), tidies the health/status bars and
	fonts, and provides a registration table so per-addon tooltips get skinned
	as they load.

	Ported from NDui's Tooltip suite by siweia (Tip.lua / TooltipID.lua /
	TooltipIcons.lua / ItemLevel.lua / HoverTips.lua), adapted to the NexEnhance
	framework and hardened for Patch 12.0 Secret Values.

	This file owns the module; the sibling files (TooltipID, TooltipIcons,
	TooltipItemLevel, TooltipHoverTips) fetch it with ns:GetModule("Tooltip")
	and add their own methods, all wired up from OnEnable.
--]]

local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

-- Localised globals.
local _G = _G
local format, strfind, strupper, strlen = string.format, string.find, string.upper, string.len
local gsub, pairs, select = string.gsub, pairs, select
local unpack = unpack
local hooksecurefunc = hooksecurefunc

local UnitExists = UnitExists
local UnitIsPlayer, UnitName, UnitPVPName, UnitClass = UnitIsPlayer, UnitName, UnitPVPName, UnitClass
local UnitRace, UnitLevel, UnitCreatureType, UnitClassification = UnitRace, UnitLevel, UnitCreatureType, UnitClassification
local UnitIsAFK, UnitIsDND, UnitIsConnected, UnitIsDeadOrGhost = UnitIsAFK, UnitIsDND, UnitIsConnected, UnitIsDeadOrGhost
local UnitReaction, UnitIsPVP, UnitFactionGroup, UnitRealmRelationship = UnitReaction, UnitIsPVP, UnitFactionGroup, UnitRealmRelationship
local UnitGroupRolesAssigned, GetRaidTargetIndex, GetGuildInfo, IsInGuild = UnitGroupRolesAssigned, GetRaidTargetIndex, GetGuildInfo, IsInGuild
local UnitIsWildBattlePet, UnitIsBattlePetCompanion, UnitBattlePetLevel = UnitIsWildBattlePet, UnitIsBattlePetCompanion, UnitBattlePetLevel
local UnitIsUnit, UnitTokenFromGUID, UnitHealth = UnitIsUnit, UnitTokenFromGUID, UnitHealth
local GetCreatureDifficultyColor = GetCreatureDifficultyColor
local InCombatLockdown, IsShiftKeyDown = InCombatLockdown, IsShiftKeyDown

local C_ChallengeMode_GetDungeonScoreRarityColor = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor
local C_PlayerInfo_GetPlayerMythicPlusRatingSummary = C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary
local C_Secrets = _G["C_Secrets"]
local ShouldUnitIdentityBeSecret = C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret
local GetDisplayedItem = TooltipUtil and TooltipUtil.GetDisplayedItem

-- GameTooltip cast for fields the type stubs don't expose (money/shopping/etc).
local GT = GameTooltip ---@type any

local ICON_LIST = ICON_LIST
local HIGHLIGHT_FONT_COLOR = HIGHLIGHT_FONT_COLOR

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
		showIDs = true,
		showIcons = true,
		showItemLevel = true,
		itemLevelByShift = true,
		hoverTips = true,
	},
})

local Tooltip = ns:NewModule("Tooltip", "tooltip", { group = "tooltip", title = L["Tooltip"], order = 10 })

-- Active settings table; bound in OnEnable, read live everywhere.
local cfg

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
-- Unit resolution (secret-safe)
-- ---------------------------------------------------------------------------
function Tooltip:GetUnit()
	local data = self.GetTooltipData and self:GetTooltipData()
	local guid = data and F.NotSecret(data.guid) and data.guid
	local mouseover = UnitExists("mouseover") and "mouseover"
	local unit = (guid and UnitTokenFromGUID(guid)) or mouseover
	return unit, guid
end

function Tooltip:UnitExists(unit)
	if ShouldUnitIdentityBeSecret and ShouldUnitIdentityBeSecret(unit) then return end
	return unit and UnitExists(unit)
end

local function replaceSpecInfo(str)
	return strfind(str, "%s") and specPrefix .. str or str
end

-- Difficulty/level helpers ---------------------------------------------------
function Tooltip:GetLevelLine()
	for i = 2, self:NumLines() do
		local tiptext = _G["GameTooltipTextLeft" .. i]
		if not tiptext then break end
		local linetext = tiptext:GetText()
		if linetext and F.NotSecret(linetext) and strfind(linetext, LEVEL) then
			return tiptext, i
		end
	end
end

function Tooltip:GetTarget(unit)
	if F.IsSecret(unit) then return "" end
	local isYou = UnitIsUnit(unit, "player")
	if F.NotSecret(isYou) and isYou then
		return format("|cffff0000%s|r", ">" .. strupper(YOU) .. "<")
	end
	local name = UnitName(unit)
	if not name or F.IsSecret(name) then name = "" end
	return F.ColorStr(F.UnitColor(unit)) .. name .. "|r"
end

-- Faction / role frames ------------------------------------------------------
function Tooltip:InsertFactionFrame(faction)
	if not self.factionFrame then
		local f = self:CreateTexture(nil, "OVERLAY")
		f:SetPoint("TOPRIGHT", 0, -5)
		f:SetBlendMode("ADD")
		f:SetScale(0.3)
		f:SetAlpha(0.7)
		self.factionFrame = f
	end
	self.factionFrame:SetTexture("Interface\\Timer\\" .. faction .. "-Logo")
	self.factionFrame:Show()
end

local roleTexCoord = {
	TANK = { 0, 19 / 64, 22 / 64, 41 / 64 },
	HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
	DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}

function Tooltip:InsertRoleFrame(role)
	local coord = roleTexCoord[role]
	if not coord then return end
	if not self.roleFrame then
		local f = self:CreateTexture(nil, "OVERLAY")
		f:SetPoint("TOPRIGHT", self, -2, -2)
		f:SetSize(18, 18)
		f:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
		self.roleFrame = f
	end
	self.roleFrame:SetTexCoord(coord[1], coord[2], coord[3], coord[4])
	self.roleFrame:Show()
end

-- Faction line rewrite (AddLinePreCall) -------------------------------------
function Tooltip:UpdateFactionLine(lineData)
	if self:IsForbidden() then return end
	if not self:IsTooltipType(Enum.TooltipDataType.Unit) then return end

	local unit = Tooltip.GetUnit(self)
	if not unit then return end
	-- Guard the secret check BEFORE boolean-testing the result (12.0.5 can make
	-- UnitIsPlayer return a secret value under restricted identity).
	local isPlayer = UnitIsPlayer(unit)
	isPlayer = F.NotSecret(isPlayer) and isPlayer
	local unitClass = isPlayer and UnitClass(unit)
	local unitCreature = UnitCreatureType(unit)

	local linetext = lineData.leftText
	if not linetext or F.IsSecret(linetext) then return end

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

-- Cleared ---------------------------------------------------------------------
function Tooltip:OnTooltipCleared()
	if self:IsForbidden() then return end
	if self.factionFrame and self.factionFrame:IsShown() then self.factionFrame:Hide() end
	if self.roleFrame and self.roleFrame:IsShown() then self.roleFrame:Hide() end
	-- Restore Blizzard's default border tint (we only ever recolour it).
	SetDefaultBorderColor(self)
end

-- Mythic+ score --------------------------------------------------------------
local function GetDungeonScore(score)
	local color = (C_ChallengeMode_GetDungeonScoreRarityColor and C_ChallengeMode_GetDungeonScoreRarityColor(score)) or HIGHLIGHT_FONT_COLOR
	return color:WrapTextInColorCode(score)
end

function Tooltip:ShowUnitMythicPlusScore(unit)
	if not cfg.mythicScore or not C_PlayerInfo_GetPlayerMythicPlusRatingSummary then return end
	local summary = C_PlayerInfo_GetPlayerMythicPlusRatingSummary(unit)
	local score = summary and summary.currentSeasonScore
	if score and score > 0 then
		self:AddLine(format(L["Mythic+ Score: %s"], GetDungeonScore(score)))
	end
end

-- Combat hide ----------------------------------------------------------------
local function ShouldHideInCombat()
	-- Hide in combat unless Shift is held (Shift always reveals).
	if not cfg.hideInCombat then return false end
	return not IsShiftKeyDown()
end

local function CheckUnitStatus(func, unit, text)
	local status = func(unit)
	return F.NotSecret(status) and status and text
end

-- The main unit tooltip rewrite ---------------------------------------------
function Tooltip:OnTooltipSetUnit()
	if self:IsForbidden() or self ~= GameTooltip then return end

	if ShouldHideInCombat() and InCombatLockdown() then
		self:Hide()
		return
	end

	local unit, guid = Tooltip.GetUnit(self)
	if not unit then return end

	local isShiftKeyDown = IsShiftKeyDown()
	local isPlayer = UnitIsPlayer(unit)
	isPlayer = F.NotSecret(isPlayer) and isPlayer

	if isPlayer then
		local name, realm = UnitName(unit)
		-- Under restricted identity the name can be secret; fall back so the
		-- concatenations below never operate on a secret value.
		if not name or F.IsSecret(name) then name = UNKNOWN or "Unknown" end
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
			if faction and faction ~= "Neutral" then
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
			if IsInGuild() and guildName == myGuild and guildRealm == myGuildRealm then
				GameTooltipTextLeft2:SetTextColor(0.25, 1, 0.25)
			else
				GameTooltipTextLeft2:SetTextColor(0.6, 0.8, 1)
			end

			rankIndex = (rankIndex or 0) + 1
			if cfg.hideRank then rank = "" end
			if guildRealm and isShiftKeyDown then guildName = guildName .. "-" .. guildRealm end
			if strlen(guildName) > 31 and not isShiftKeyDown then guildName = "..." end
			GameTooltipTextLeft2:SetText("<" .. guildName .. "> " .. (rank or "") .. "(" .. rankIndex .. ")")
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
	if UnitIsWildBattlePet(unit) or UnitIsBattlePetCompanion(unit) then
		level = UnitBattlePetLevel(unit)
	else
		level = UnitLevel(unit)
	end

	if level and F.NotSecret(level) then
		local boss
		if level == -1 then boss = "|cffff0000??|r" end

		local diff = GetCreatureDifficultyColor(level)
		local classify = UnitClassification(unit)
		local textLevel = format("%s%s%s|r", F.ColorStr(diff.r, diff.g, diff.b), boss or format("%d", level), classification[classify] or "")
		local tiptextLevel = Tooltip.GetLevelLine(self)
		local unitClass = isPlayer and select(1, UnitClass(unit))
		if tiptextLevel then
			local reaction = UnitReaction(unit, "player")
			local standingText = (not isPlayer and reaction and F.NotSecret(reaction) and hexColor .. (_G["FACTION_STANDING_LABEL" .. reaction] or "") .. "|r ") or ""
			local pvpFlag = (isPlayer and UnitIsPVP(unit) and format(" |cffff0000%s|r", PVP)) or ""
			local unitClassStr = (isPlayer and format("%s %s", UnitRace(unit) or "", hexColor .. (unitClass or "") .. "|r")) or UnitCreatureType(unit) or ""

			tiptextLevel:SetFormattedText("%s%s %s %s", textLevel, pvpFlag, standingText .. unitClassStr, (not alive and "|cffCCCCCC" .. DEAD .. "|r" or ""))
		end
	end

	if UnitExists(unit .. "target") then
		local targetIcon = GetRaidTargetIndex(unit .. "target")
		local targetIconStr
		if targetIcon and F.NotSecret(targetIcon) and targetIcon <= 8 then
			targetIconStr = ICON_LIST[targetIcon] .. "10|t"
		end
		self:AddLine(TARGET .. ": " .. format("%s%s", targetIconStr or "", Tooltip.GetTarget(self, unit .. "target")))
	end

	if not isPlayer and isShiftKeyDown then
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
function Tooltip:UpdateStatusBarColor()
	local unit = Tooltip.GetUnit(self)
	if not unit then return end
	if F.IsSecret(unit) then
		self.StatusBar:SetStatusBarColor(0, 1, 0)
	else
		self.StatusBar:SetStatusBarColor(F.UnitColor(unit))
	end
end

-- Optional health-bar placement. We capture Blizzard's default anchors once so
-- the "bottom" choice can restore them exactly; "top" re-anchors the bar above
-- the tooltip (it auto-tracks size since it pins to GameTooltip's top edge).
local savedBarPoints
local function RepositionStatusBar()
	local bar = GameTooltipStatusBar
	if not bar then return end

	if not savedBarPoints then
		savedBarPoints = {}
		for i = 1, bar:GetNumPoints() do
			savedBarPoints[i] = { bar:GetPoint(i) }
		end
	end

	bar:ClearAllPoints()
	if cfg and cfg.statusBarPosition == "top" then
		bar:SetPoint("BOTTOMLEFT", GameTooltip, "TOPLEFT", 0, 2)
		bar:SetPoint("BOTTOMRIGHT", GameTooltip, "TOPRIGHT", 0, 2)
	elseif #savedBarPoints > 0 then
		for i = 1, #savedBarPoints do
			bar:SetPoint(unpack(savedBarPoints[i]))
		end
	else
		-- Fallback to Blizzard's standard bottom placement.
		bar:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, 0)
		bar:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", 0, 0)
	end
end

function Tooltip:RefreshStatusBar()
	if not self.text then
		self.text = F.CreateFS(self, 12, "")
		self.text:ClearAllPoints()
		self.text:SetPoint("CENTER", self, "CENTER", 0, 0)
	end

	RepositionStatusBar()
	-- Prefer the bar's own watched GUID (set by Blizzard's SetWatch), then fall
	-- back to the parent tooltip's unit.
	local guid = self.guid
	local unit = (guid and F.NotSecret(guid) and UnitTokenFromGUID(guid)) or Tooltip.GetUnit(self:GetParent())
	local ok, value = pcall(UnitHealth, unit)
	if ok and value and F.NotSecret(value) then
		self.text:SetText(F.ShortValue(value))
	else
		self.text:SetText("")
	end
end

-- Quality border -------------------------------------------------------------
-- We never reskin or reposition the tooltip; we only tint Blizzard's own
-- default (NineSlice) border by item quality. FixRecipeItemNameWidth runs as
-- the Item post-call and doubles as the quality-border updater.
function Tooltip:FixRecipeItemNameWidth()
	if self.GetName then
		local name = self:GetName()
		for i = 1, self:NumLines() do
			local line = _G[name .. "TextLeft" .. i]
			if line and F.NotSecret(line:GetWidth()) and line:GetHeight() > 40 then
				line:SetWidth(line:GetWidth() + 2)
			end
		end
	end

	if cfg.qualityBorder and GetDisplayedItem then
		local _, link = GetDisplayedItem(self)
		if link then
			local quality = C_Item.GetItemQualityByID(link)
			local color = C.QualityColors[quality or 1]
			if color then
				SetDefaultBorderColor(self, color.r, color.g, color.b)
				return
			end
		end
	end
	SetDefaultBorderColor(self)
end

function Tooltip:ResetUnit(btn)
	if GameTooltip:IsForbidden() then return end
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

	if GameTooltipStatusBar then
		GameTooltipStatusBar:SetScript("OnValueChanged", nil)
	end
	GameTooltip:HookScript("OnTooltipCleared", Tooltip.OnTooltipCleared)

	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, Tooltip.OnTooltipSetUnit)
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, Tooltip.UpdateStatusBarColor)
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, Tooltip.FixRecipeItemNameWidth)
		if TooltipDataProcessor.AddLinePreCall then
			TooltipDataProcessor.AddLinePreCall(Enum.TooltipDataLineType.None, Tooltip.UpdateFactionLine)
		end
	end

	if GT.StatusBar and GT.StatusBar.UpdateUnitHealth then
		hooksecurefunc(GT.StatusBar, "UpdateUnitHealth", Tooltip.RefreshStatusBar)
	end

	-- Capture Blizzard's default bar anchors and apply the chosen placement.
	RepositionStatusBar()

	-- Element add-ons (defined in sibling files).
	if cfg.showIcons and Tooltip.ReskinTooltipIcons then Tooltip:ReskinTooltipIcons() end
	if cfg.showIDs and Tooltip.SetupTooltipID then Tooltip:SetupTooltipID() end
	if cfg.showItemLevel and Tooltip.SetupItemLevel then Tooltip:SetupItemLevel() end
	if cfg.hoverTips and Tooltip.SetupHoverTips then Tooltip:SetupHoverTips() end

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
	if key == "statusBarPosition" then
		RepositionStatusBar()
	end
end

function Tooltip:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Tooltip"], L["Enhance the game tooltips with extra info (reload to fully disable)."])
	builder:Dropdown(category, self, "statusBarPosition", L["Health Bar Position"], L["Place the unit health bar at the top or bottom of the tooltip."], {
		{ value = "bottom", label = L["Bottom"] },
		{ value = "top", label = L["Top"] },
	})
	builder:Checkbox(category, self, "factionIcon", L["Show Faction Icon"], L["Show an Alliance/Horde icon on player tooltips."])
	builder:Checkbox(category, self, "lfdRole", L["Show Role Icon"], L["Show the group role (tank/healer/dps) icon on player tooltips."])
	builder:Checkbox(category, self, "hideRealm", L["Hide Realm Name"], L["Hide the realm name on players from other realms (hold Shift to reveal)."])
	builder:Checkbox(category, self, "hideTitle", L["Hide Player Title"], L["Hide PvP/guild titles on player names."])
	builder:Checkbox(category, self, "mythicScore", L["Show Mythic+ Score"], L["Show the player's current-season Mythic+ rating."])
	builder:Checkbox(category, self, "qualityBorder", L["Quality-Coloured Border"], L["Tint Blizzard's default tooltip border by item quality."])
	builder:Checkbox(category, self, "showItemLevel", L["Show Item Level"], L["Show the inspected player's item level on their tooltip."])
	builder:Checkbox(category, self, "itemLevelByShift", L["Item Level on Shift"], L["Only show the inspected item level while holding Shift."])
	builder:Checkbox(category, self, "showIDs", L["Show IDs"], L["Append spell, item, quest and other IDs to tooltips."])
	builder:Checkbox(category, self, "showIcons", L["Show Icons"], L["Show an icon next to the tooltip title for spells, items and more."])
	builder:Checkbox(category, self, "hoverTips", L["Hyperlink Hover Tips"], L["Show a tooltip when hovering item/spell links in chat."])
end
