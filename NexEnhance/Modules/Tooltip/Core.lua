local _, Module = ...

local strfind, format, strupper, strlen, pairs, unpack = string.find, string.format, string.upper, string.len, pairs, unpack
local ICON_LIST = ICON_LIST
local HIGHLIGHT_FONT_COLOR = HIGHLIGHT_FONT_COLOR
local PVP, LEVEL, FACTION_HORDE, FACTION_ALLIANCE = PVP, LEVEL, FACTION_HORDE, FACTION_ALLIANCE
local YOU, TARGET, AFK, DND, DEAD, PLAYER_OFFLINE = YOU, TARGET, AFK, DND, DEAD, PLAYER_OFFLINE
local FOREIGN_SERVER_LABEL, INTERACTIVE_SERVER_LABEL = FOREIGN_SERVER_LABEL, INTERACTIVE_SERVER_LABEL
local LE_REALM_RELATION_COALESCED, LE_REALM_RELATION_VIRTUAL = LE_REALM_RELATION_COALESCED, LE_REALM_RELATION_VIRTUAL
local UnitIsPVP, UnitFactionGroup, UnitRealmRelationship = UnitIsPVP, UnitFactionGroup, UnitRealmRelationship
local UnitIsConnected, UnitIsDeadOrGhost, UnitIsAFK, UnitIsDND, UnitReaction = UnitIsConnected, UnitIsDeadOrGhost, UnitIsAFK, UnitIsDND, UnitReaction
local InCombatLockdown, IsShiftKeyDown, GetItemInfo = InCombatLockdown, IsShiftKeyDown, GetItemInfo
local GetCreatureDifficultyColor, UnitCreatureType, UnitClassification = GetCreatureDifficultyColor, UnitCreatureType, UnitClassification
local UnitIsWildBattlePet, UnitIsBattlePetCompanion, UnitBattlePetLevel = UnitIsWildBattlePet, UnitIsBattlePetCompanion, UnitBattlePetLevel
local UnitIsPlayer, UnitName, UnitPVPName, UnitClass, UnitRace, UnitLevel = UnitIsPlayer, UnitName, UnitPVPName, UnitClass, UnitRace, UnitLevel
local GetRaidTargetIndex, UnitGroupRolesAssigned, GetGuildInfo, IsInGuild = GetRaidTargetIndex, UnitGroupRolesAssigned, GetGuildInfo, IsInGuild
local C_ChallengeMode_GetDungeonScoreRarityColor = C_ChallengeMode.GetDungeonScoreRarityColor
local C_PlayerInfo_GetPlayerMythicPlusRatingSummary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary
local GameTooltip_ClearMoney, GameTooltip_ClearStatusBars, GameTooltip_ClearProgressBars, GameTooltip_ClearWidgetSet = GameTooltip_ClearMoney, GameTooltip_ClearStatusBars, GameTooltip_ClearProgressBars, GameTooltip_ClearWidgetSet

local classification = {
	worldboss = format("|cffAF5050 %s|r", BOSS),
	rareelite = format("|cffAF5050+ %s|r", ITEM_QUALITY3_DESC),
	elite = "|cffAF5050+|r",
	rare = format("|cffAF5050 %s|r", ITEM_QUALITY3_DESC),
}
local npcIDstring = "%s " .. Module.InfoColor .. "%s"
local specPrefix = "|cffFFCC00" .. SPECIALIZATION .. ": " .. Module.InfoColor

function Module:GetUnit()
	local data = self:GetTooltipData()
	local guid = data and data.guid
	local unit = guid and UnitTokenFromGUID(guid)
	return unit, guid
end

local FACTION_COLORS = {
	[FACTION_ALLIANCE] = "|cff4080ff%s|r",
	[FACTION_HORDE] = "|cffff5040%s|r",
}

local function replaceSpecInfo(str)
	return strfind(str, "%s") and specPrefix .. str or str
end

function Module:UpdateFactionLine(lineData)
	if self:IsForbidden() then
		return
	end
	if not self:IsTooltipType(Enum.TooltipDataType.Unit) then
		return
	end

	local unit = Module.GetUnit(self)
	local unitClass = unit and UnitIsPlayer(unit) and UnitClass(unit)
	local unitCreature = unit and UnitCreatureType(unit)
	local linetext = lineData.leftText

	if linetext == PVP then
		return true
	elseif FACTION_COLORS[linetext] then
		if Module.db.profile.tooltip.factionIcon then
			return true
		else
			lineData.leftText = format(FACTION_COLORS[linetext], linetext)
		end
	elseif unitClass and strfind(linetext, unitClass) then
		lineData.leftText = gsub(linetext, "(.-)%S+$", replaceSpecInfo)
	elseif unitCreature and linetext == unitCreature then
		return true
	end
end

function Module:GetLevelLine()
	for i = 2, self:NumLines() do
		local tiptext = _G[self:GetName() .. "TextLeft" .. i]
		if not tiptext then
			break
		end

		local linetext = tiptext:GetText()
		if linetext and strfind(linetext, LEVEL) then
			return tiptext
		end
	end
end

function Module:GetTarget(unit)
	if UnitIsUnit(unit, "player") then
		return format("|cffff0000%s|r", ">" .. strupper(YOU) .. "<")
	else
		return Module.RGBToHex(Module.UnitColor(unit)) .. UnitName(unit) .. "|r"
	end
end

function Module:InsertFactionFrame(faction)
	if not self.factionFrame then
		local f = self:CreateTexture(nil, "OVERLAY")
		f:SetPoint("TOPRIGHT", -10, -10)
		f:SetBlendMode("ADD")
		self.factionFrame = f
	end
	self.factionFrame:SetAtlas("MountJournalIcons-" .. faction, true)
	self.factionFrame:Show()
end

function Module:OnTooltipCleared()
	if self:IsForbidden() then
		return
	end

	if self.factionFrame and self.factionFrame:IsShown() then
		self.factionFrame:Hide()
	end

	GameTooltip_ClearMoney(self)
	GameTooltip_ClearStatusBars(self)
	GameTooltip_ClearProgressBars(self)
	GameTooltip_ClearWidgetSet(self)

	if self.StatusBar then
		self.StatusBar:ClearWatch()
	end
end

function Module.GetDungeonScore(score)
	local color = C_ChallengeMode_GetDungeonScoreRarityColor(score) or HIGHLIGHT_FONT_COLOR
	return color:WrapTextInColorCode(score)
end

function Module:ShowUnitMythicPlusScore(unit)
	if not Module.db.profile.tooltip.mdScore then
		return
	end

	local summary = C_PlayerInfo_GetPlayerMythicPlusRatingSummary(unit)
	local score = summary and summary.currentSeasonScore
	if score and score > 0 then
		GameTooltip:AddLine(format(DUNGEON_SCORE_LEADER, Module.GetDungeonScore(score)))
	end
end

function Module:OnTooltipSetUnit()
	if self:IsForbidden() or self ~= GameTooltip then
		return
	end
	if Module.db.profile.tooltip.combatHide and InCombatLockdown() then
		self:Hide()
		return
	end

	local unit, guid = Module.GetUnit(self)
	if not unit or not UnitExists(unit) then
		return
	end

	local isShiftKeyDown = IsShiftKeyDown()
	local isPlayer = UnitIsPlayer(unit)
	if isPlayer then
		local name, realm = UnitName(unit)
		local pvpName = UnitPVPName(unit)
		local relationship = UnitRealmRelationship(unit)
		if not Module.db.profile.tooltip.hideTitle and pvpName then
			name = pvpName
		end

		if realm and realm ~= "" then
			if isShiftKeyDown or not Module.db.profile.tooltip.hideRealm then
				name = name .. "-" .. realm
			elseif relationship == LE_REALM_RELATION_COALESCED then
				name = name .. FOREIGN_SERVER_LABEL
			elseif relationship == LE_REALM_RELATION_VIRTUAL then
				name = name .. INTERACTIVE_SERVER_LABEL
			end
		end

		local status = (UnitIsAFK(unit) and AFK) or (UnitIsDND(unit) and DND) or (not UnitIsConnected(unit) and PLAYER_OFFLINE)
		if status then
			status = format(" |cffffcc00[%s]|r", status)
		end
		GameTooltipTextLeft1:SetFormattedText("%s", name .. (status or ""))

		if Module.db.profile.tooltip.factionIcon then
			local faction = UnitFactionGroup(unit)
			if faction and faction ~= "Neutral" then
				Module.InsertFactionFrame(self, faction)
			end
		end

		if Module.db.profile.tooltip.lfdRole then
			local unitColor
			local unitRole = UnitGroupRolesAssigned(unit)
			if IsInGroup() and (UnitInParty(unit) or UnitInRaid(unit)) and (unitRole ~= "NONE") then
				if unitRole == "HEALER" then
					unitRole = HEALER
					unitColor = "|cff00ff96" -- RGB: 0, 255, 150
				elseif unitRole == "TANK" then
					unitRole = TANK
					unitColor = "|cff2850a0" -- RGB: 40, 80, 160
				elseif unitRole == "DAMAGER" then
					unitRole = DAMAGE
					unitColor = "|cffc41f3b" -- RGB: 196, 31, 59
				end

				self:AddLine(ROLE .. ": " .. unitColor .. unitRole .. "|r")
			end
		end

		local guildName, rank, rankIndex, guildRealm = GetGuildInfo(unit)
		local hasText = GameTooltipTextLeft2:GetText()
		if guildName and hasText then
			local myGuild, _, _, myGuildRealm = GetGuildInfo("player")
			if IsInGuild() and guildName == myGuild and guildRealm == myGuildRealm then
				GameTooltipTextLeft2:SetTextColor(0.25, 1, 0.25)
			else
				GameTooltipTextLeft2:SetTextColor(0.6, 0.8, 1)
			end

			rankIndex = rankIndex + 1
			if Module.db.profile.tooltip.hideRank then
				rank = ""
			end

			if guildRealm and isShiftKeyDown then
				guildName = guildName .. "-" .. guildRealm
			end

			if Module.db.profile.tooltip.hideJunkGuild and not isShiftKeyDown then
				if strlen(guildName) > 31 then
					guildName = "..."
				end
			end

			GameTooltipTextLeft2:SetText("<" .. guildName .. "> " .. rank .. "(" .. rankIndex .. ")")
		end
	end

	local r, g, b = Module.UnitColor(unit)
	local hexColor = Module.RGBToHex(r, g, b)
	local text = GameTooltipTextLeft1:GetText()
	if text then
		local ricon = GetRaidTargetIndex(unit)
		if ricon and ricon > 8 then
			ricon = nil
		end

		ricon = ricon and ICON_LIST[ricon] .. "18|t " or ""
		GameTooltipTextLeft1:SetFormattedText("%s%s%s", ricon, hexColor, text)
	end

	local alive = not UnitIsDeadOrGhost(unit)
	local level
	if UnitIsWildBattlePet(unit) or UnitIsBattlePetCompanion(unit) then
		level = UnitBattlePetLevel(unit)
	else
		level = UnitLevel(unit)
	end

	if level then
		local boss
		if level == -1 then
			boss = "|cffff0000??|r"
		end

		local diff = GetCreatureDifficultyColor(level)
		local classify = UnitClassification(unit)
		local textLevel = format("%s%s%s|r", Module.RGBToHex(diff), boss or format("%d", level), classification[classify] or "")
		local tiptextLevel = Module.GetLevelLine(self)
		if tiptextLevel then
			local reaction = UnitReaction(unit, "player")
			local standingText = not isPlayer and reaction and hexColor .. _G["FACTION_STANDING_LABEL" .. reaction] .. "|r " or ""
			local pvpFlag = isPlayer and UnitIsPVP(unit) and format(" |cffff0000%s|r", PVP) or ""
			local unitClass = isPlayer and format("%s %s", UnitRace(unit) or "", hexColor .. (UnitClass(unit) or "") .. "|r") or UnitCreatureType(unit) or ""

			tiptextLevel:SetFormattedText("%s%s %s %s", textLevel, pvpFlag, standingText .. unitClass, (not alive and "|cffCCCCCC" .. DEAD .. "|r" or ""))
		end
	end

	if UnitExists(unit .. "target") then
		local tarRicon = GetRaidTargetIndex(unit .. "target")
		if tarRicon and tarRicon > 8 then
			tarRicon = nil
		end
		local tar = format("%s%s", (tarRicon and ICON_LIST[tarRicon] .. "10|t") or "", Module:GetTarget(unit .. "target"))
		self:AddLine(TARGET .. ": " .. tar)
	end

	if not isPlayer and isShiftKeyDown then
		local npcID = Module:ExtractIDFromGUID(guid)
		if npcID then
			self:AddLine(format(npcIDstring, "NpcID:", npcID))
		end
	end

	if isPlayer then
		Module.InspectUnitItemLevel(self, unit)
		Module.ShowUnitMythicPlusScore(self, unit)
	end
	-- Module.ScanTargets(self, unit)
	-- Module.CreatePetInfo(self, unit)
end

function Module:RefreshStatusBar(value)
	if not self.text then
		self.text = Module.CreateFontString(self, 11, nil, "")
	end
	local unit = self.guid and UnitTokenFromGUID(self.guid)
	local unitHealthMax = unit and UnitHealthMax(unit)
	if unitHealthMax and unitHealthMax ~= 0 then
		self.text:SetText(Module.ShortValue(value * unitHealthMax) .. " - " .. Module.ShortValue(unitHealthMax))
		self:SetStatusBarColor(Module.UnitColor(unit))
	else
		self.text:SetFormattedText("%d%%", value * 100)
	end
end

function Module:ReskinStatusBar()
	self.StatusBar:ClearAllPoints()
	self.StatusBar:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 4, 4)
	self.StatusBar:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", -4, 4)
	self.StatusBar:SetHeight(11)

	Module.CreateBackdropFrame(self.StatusBar, 4, 4, 4, 4)
end

-- A wrapper for Tooltip:SetBackdropBorderColor that continues to work in WoW 9.1.5+. -- Thanks pawn
function Module:SetTooltipBorderColor(Tooltip, r, g, b, a)
	if a == nil then
		a = 1
	end
	if Tooltip.SetBackdropBorderColor then
		Tooltip:SetBackdropBorderColor(r, g, b, a)
	elseif Tooltip.NineSlice.TopEdge then
		-- Seems like this SHOULD work:
		-- Tooltip.NineSlice:SetBorderColor(r, g, b, a)
		-- ...but for some reason it doesn't (in the 9.1.5 PTR), so just do it manually for now.
		Tooltip.NineSlice.TopLeftCorner:SetVertexColor(r, g, b, a)
		Tooltip.NineSlice.TopRightCorner:SetVertexColor(r, g, b, a)
		Tooltip.NineSlice.BottomLeftCorner:SetVertexColor(r, g, b, a)
		Tooltip.NineSlice.BottomRightCorner:SetVertexColor(r, g, b, a)
		Tooltip.NineSlice.TopEdge:SetVertexColor(r, g, b, a)
		Tooltip.NineSlice.BottomEdge:SetVertexColor(r, g, b, a)
		Tooltip.NineSlice.LeftEdge:SetVertexColor(r, g, b, a)
		Tooltip.NineSlice.RightEdge:SetVertexColor(r, g, b, a)
	else
		Module:Print("doesn't know how to change tooltip border colors in this version of WoW.")
	end
end

-- Anchor and mover
local cursorIndex = {
	["DISABLE"] = "ANCHOR_NONE",
	["LEFT"] = "ANCHOR_CURSOR_LEFT",
	["TOP"] = "ANCHOR_CURSOR",
	["RIGHT"] = "ANCHOR_CURSOR_RIGHT",
}

function Module:GameTooltip_SetDefaultAnchor(parent)
	if self:IsForbidden() or not parent then
		return
	end

	local mode = Module.db.profile.tooltip.cursorPosition
	self:SetOwner(parent, cursorIndex[mode])
end

-- Tooltip skin
function Module:ReskinTooltip()
	if not self then
		-- if K.isDeveloper then
		-- 	print("Unknown tooltip spotted.")
		-- end
		return
	end

	if self:IsForbidden() then
		return
	end

	self:SetScale(1)

	if not self.tipStyled then
		if self.StatusBar then
			Module.ReskinStatusBar(self)
		end

		self.tipStyled = true
	end

	Module:SetTooltipBorderColor(self, 1, 1, 1, 1)

	local data = self.GetTooltipData and self:GetTooltipData()
	if data then
		local link = data.guid and C_Item.GetItemLinkByGUID(data.guid) or data.hyperlink
		if link then
			local quality = select(3, GetItemInfo(link))
			local color = Module.QualityColors[quality or 1]
			if color and Module.db.profile.tooltip.qualityColor then
				Module:SetTooltipBorderColor(self, color.r, color.g, color.b, 1)
			end
		end
	end
end

function Module:FixRecipeItemNameWidth()
	if not self.GetName then
		return
	end

	local name = self:GetName()
	for i = 1, self:NumLines() do
		local line = _G[name .. "TextLeft" .. i]
		if line and line:GetHeight() > 40 then
			line:SetWidth(line:GetWidth() + 2)
		end
	end
end

function Module:MODIFIER_STATE_CHANGED(btn)
	if btn == "LSHIFT" and UnitExists("mouseover") then
		GameTooltip:RefreshData()
	end
end

function Module:FixStoneSoupError()
	local blockTooltips = {
		[556] = true, -- Stone Soup
	}
	hooksecurefunc(_G.UIWidgetTemplateStatusBarMixin, "Setup", function(self)
		if self:IsForbidden() and blockTooltips[self.widgetSetID] and self.Bar then
			self.Bar.tooltip = nil
		end
	end)
end

function Module:PLAYER_LOGIN()
	GameTooltip:HookScript("OnTooltipCleared", self.OnTooltipCleared)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, self.OnTooltipSetUnit)
	hooksecurefunc(GameTooltip.StatusBar, "SetValue", self.RefreshStatusBar)
	TooltipDataProcessor.AddLinePreCall(Enum.TooltipDataLineType.None, self.UpdateFactionLine)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, self.FixRecipeItemNameWidth)
	hooksecurefunc("GameTooltip_SetDefaultAnchor", self.GameTooltip_SetDefaultAnchor)

	Module:FixStoneSoupError()

	-- Elements
	local loadTooltipModules = {
		"CreateTooltipIcons",
		"CreateTooltipID",
		"CreateMountSource",
	}

	for _, funcName in ipairs(loadTooltipModules) do
		local func = self[funcName]
		if type(func) == "function" then
			local success, err = pcall(func, self)
			if not success then
				error("Error in function " .. funcName .. ": " .. tostring(err), 2)
			end
		end
	end
end

-- Tooltip Skin Registration
local tipTable = {}
function Module:RegisterTooltips(addon, func)
	tipTable[addon] = func
end

function Module:ADDON_LOADED(addon)
	if tipTable[addon] then
		tipTable[addon]()
		tipTable[addon] = nil
	end
end

Module:RegisterTooltips("NexEnhance", function()
	local tooltips = {
		ChatMenu,
		EmoteMenu,
		LanguageMenu,
		VoiceMacroMenu,
		GameTooltip,
		EmbeddedItemTooltip,
		ItemRefTooltip,
		ItemRefShoppingTooltip1,
		ItemRefShoppingTooltip2,
		ShoppingTooltip1,
		ShoppingTooltip2,
		AutoCompleteBox,
		FriendsTooltip,
		QuestScrollFrame.StoryTooltip,
		QuestScrollFrame.CampaignTooltip,
		GeneralDockManagerOverflowButtonList,
		NamePlateTooltip,
		QueueStatusFrame,
		FloatingGarrisonFollowerTooltip,
		FloatingGarrisonFollowerAbilityTooltip,
		FloatingGarrisonMissionTooltip,
		GarrisonFollowerAbilityTooltip,
		GarrisonFollowerTooltip,
		FloatingGarrisonShipyardFollowerTooltip,
		GarrisonShipyardFollowerTooltip,
		BattlePetTooltip,
		PetBattlePrimaryAbilityTooltip,
		PetBattlePrimaryUnitTooltip,
		FloatingBattlePetTooltip,
		FloatingPetBattleAbilityTooltip,
		IMECandidatesFrame,
		QuickKeybindTooltip,
		GameSmallHeaderTooltip,
	}
	for _, f in pairs(tooltips) do
		f:HookScript("OnShow", Module.ReskinTooltip)
	end

	if SettingsTooltip then
		Module.ReskinTooltip(SettingsTooltip)
		SettingsTooltip:SetScale(UIParent:GetScale())
	end
end)
