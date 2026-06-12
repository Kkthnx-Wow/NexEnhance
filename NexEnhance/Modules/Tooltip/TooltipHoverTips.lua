--[[
	NexEnhance - Tooltip Hover Tips
	-------------------------------------------------------------------------
	Shows a tooltip when the mouse hovers a hyperlink in a chat frame (items,
	spells, quests, achievements, battle pets, dungeon-journal links, ...).

	Ported from NDui's HoverTips.lua by siweia.
--]]

local _, ns = ...
local C, L = ns.C, ns.L
local Tooltip = ns:GetModule("Tooltip")
if not Tooltip then
	return
end

-- luacheck: globals GameTooltip
local _G = _G
local strmatch, strsplit, tonumber = string.match, string.split, tonumber
local INSTANCE, BOSS = INSTANCE, BOSS
local BattlePetToolTip_Show = BattlePetToolTip_Show
local C_EncounterJournal_GetSectionInfo = C_EncounterJournal and C_EncounterJournal.GetSectionInfo
local EJ_GetInstanceInfo, EJ_GetEncounterInfo, GetDifficultyInfo = EJ_GetInstanceInfo, EJ_GetEncounterInfo, GetDifficultyInfo

local orig1, orig2, sectionInfo = {}, {}, {}
local linkTypes = {
	item = true,
	enchant = true,
	spell = true,
	quest = true,
	unit = true,
	talent = true,
	achievement = true,
	glyph = true,
	instancelock = true,
	currency = true,
	keystone = true,
	azessence = true,
	mawpower = true,
	conduit = true,
	mount = true,
}

local function HyperLink_SetPet(self, link)
	GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT", -3, 5)
	GameTooltip:Show()
	local _, speciesID, level, breedQuality, maxHealth, power, speed = strsplit(":", link)
	BattlePetToolTip_Show(tonumber(speciesID), tonumber(level), tonumber(breedQuality), tonumber(maxHealth), tonumber(power), tonumber(speed))
end

local function HyperLink_GetSectionInfo(id)
	local info = sectionInfo[id]
	if not info and C_EncounterJournal_GetSectionInfo then
		info = C_EncounterJournal_GetSectionInfo(id)
		sectionInfo[id] = info
	end
	return info
end

local function HyperLink_SetJournal(self, link)
	local _, idType, idStr, diffStr = strsplit(":", link)
	local id, diffID = tonumber(idStr), tonumber(diffStr) or 0
	if not id then
		return
	end
	local name, description, icon, idString
	if idType == "0" then
		name, description = EJ_GetInstanceInfo(id)
		idString = INSTANCE .. "ID:"
	elseif idType == "1" then
		name, description = EJ_GetEncounterInfo(id)
		idString = BOSS .. "ID:"
	elseif idType == "2" then
		local info = HyperLink_GetSectionInfo(id)
		if info then
			name, description, icon = info.title, info.description, info.abilityIcon
			name = icon and "|T" .. icon .. ":20:20:0:0:64:64:5:59:5:59:20|t " .. name or name
		end
		idString = L["Section"] .. "ID:"
	end
	if not name then
		return
	end

	GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT", -3, 5)
	GameTooltip:AddDoubleLine(name, GetDifficultyInfo(diffID))
	if description then
		GameTooltip:AddLine(description, 1, 1, 1, 1)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine(idString, C.InfoColor .. id)
	GameTooltip:Show()
end

local function HyperLink_SetTypes(self, link)
	GameTooltip.__isHoverTip = true
	GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT", -3, 5)
	GameTooltip:SetHyperlink(link)
	GameTooltip:Show()
end

local function HyperLink_OnEnter(self, link, ...)
	local linkType = strmatch(link, "^([^:]+)")
	if linkType then
		if linkType == "battlepet" then
			HyperLink_SetPet(self, link)
		elseif linkType == "journal" then
			HyperLink_SetJournal(self, link)
		elseif linkTypes[linkType] then
			HyperLink_SetTypes(self, link)
		end
	end
	if orig1[self] then
		return orig1[self](self, link, ...)
	end
end

local function HyperLink_OnLeave(self, ...)
	if BattlePetTooltip then
		BattlePetTooltip:Hide()
	end
	GameTooltip:Hide()
	GameTooltip.__isHoverTip = nil
	if orig2[self] then
		return orig2[self](self, ...)
	end
end

function Tooltip:SetupHoverTips()
	for i = 1, NUM_CHAT_WINDOWS do
		local frame = _G["ChatFrame" .. i]
		if frame then
			orig1[frame] = frame:GetScript("OnHyperlinkEnter")
			frame:SetScript("OnHyperlinkEnter", HyperLink_OnEnter)
			orig2[frame] = frame:GetScript("OnHyperlinkLeave")
			frame:SetScript("OnHyperlinkLeave", HyperLink_OnLeave)
		end
	end

	local function hookMessageFrame()
		if CommunitiesFrame and CommunitiesFrame.Chat then
			local messageFrame = CommunitiesFrame.Chat.MessageFrame
			orig1[messageFrame] = messageFrame:GetScript("OnHyperlinkEnter")
			messageFrame:SetScript("OnHyperlinkEnter", HyperLink_OnEnter)
			orig2[messageFrame] = messageFrame:GetScript("OnHyperlinkLeave")
			messageFrame:SetScript("OnHyperlinkLeave", HyperLink_OnLeave)
		end
	end

	if C_AddOns.IsAddOnLoaded("Blizzard_Communities") then
		hookMessageFrame()
	else
		Tooltip:RegisterTooltips("Blizzard_Communities", hookMessageFrame)
	end
end
