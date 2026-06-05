--[[
	NexEnhance - Tooltip IDs
	-------------------------------------------------------------------------
	Appends spell / item / quest / talent / achievement / currency / trait IDs
	(and item bag/bank counts and stack caps) to tooltips.

	Ported from NDui's TooltipID.lua by siweia.
--]]

local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L
local Tooltip = ns:GetModule("Tooltip")
if not Tooltip then return end

local _G = _G
local strmatch, format, tonumber, select = string.match, string.format, tonumber, select
local hooksecurefunc = hooksecurefunc
local GetUnitName = GetUnitName
local IsPlayerSpell = IsPlayerSpell
local C_MountJournal_GetMountFromSpell = C_MountJournal and C_MountJournal.GetMountFromSpell
local BAGSLOT, BANK, UNKNOWN = BAGSLOT, BANK, UNKNOWN
local LEARNT_STRING = "|cffff0000" .. ALREADY_LEARNED .. "|r"

local types = {
	spell = SPELLS .. "ID:",
	item = ITEMS .. "ID:",
	quest = QUESTS_LABEL .. "ID:",
	talent = TALENT .. "ID:",
	achievement = ACHIEVEMENTS .. "ID:",
	currency = CURRENCY .. "ID:",
	azerite = L["Trait"] .. "ID:",
}

function Tooltip:AddLineForID(id, linkType, noadd)
	if self:IsForbidden() then return end

	for i = 1, self:NumLines() do
		local line = _G[self:GetName() .. "TextLeft" .. i]
		if not line then break end
		local text = line:GetText()
		if text and F.NotSecret(text) and text == linkType then return end
	end

	if self.__isHoverTip and linkType == types.spell and IsPlayerSpell(id) and C_MountJournal_GetMountFromSpell and C_MountJournal_GetMountFromSpell(id) then
		self:AddLine(LEARNT_STRING)
	end

	if not noadd then self:AddLine(" ") end

	if linkType == types.item then
		local bagCount = C_Item.GetItemCount(id)
		local bankCount = C_Item.GetItemCount(id, true, nil, true, true) - bagCount
		local itemStackCount = select(8, C_Item.GetItemInfo(id))
		if bankCount > 0 then
			self:AddDoubleLine(BAGSLOT .. "/" .. BANK .. ":", C.InfoColor .. bagCount .. "/" .. bankCount)
		elseif bagCount > 0 then
			self:AddDoubleLine(BAGSLOT .. ":", C.InfoColor .. bagCount)
		end
		if itemStackCount and itemStackCount > 1 then
			self:AddDoubleLine(L["Stack Cap"] .. ":", C.InfoColor .. itemStackCount)
		end
	end

	self:AddDoubleLine(linkType, format(C.InfoColor .. "%s|r", id))
	self:Show()
end

function Tooltip:SetHyperLinkID(link)
	if self:IsForbidden() or not link then return end

	local linkType, id = strmatch(link, "^(%a+):(%d+)")
	if not linkType or not id then return end

	if linkType == "spell" or linkType == "enchant" or linkType == "trade" then
		Tooltip.AddLineForID(self, id, types.spell)
	elseif linkType == "talent" then
		Tooltip.AddLineForID(self, id, types.talent, true)
	elseif linkType == "quest" then
		Tooltip.AddLineForID(self, id, types.quest)
	elseif linkType == "achievement" then
		Tooltip.AddLineForID(self, id, types.achievement)
	elseif linkType == "item" then
		Tooltip.AddLineForID(self, id, types.item)
	elseif linkType == "currency" then
		Tooltip.AddLineForID(self, id, types.currency)
	end
end

function Tooltip:SetupTooltipID()
	hooksecurefunc(GameTooltip, "SetHyperlink", Tooltip.SetHyperLinkID)
	hooksecurefunc(ItemRefTooltip, "SetHyperlink", Tooltip.SetHyperLinkID)

	local function HandleAuraData(tip, data)
		local id, caster = data.spellId, data.sourceUnit
		if id then
			Tooltip.AddLineForID(tip, id, types.spell)
		end
		if caster then
			if F.IsSecret(caster) then
				local ok, name = pcall(UnitName, caster)
				if ok and F.NotSecret(name) then
					tip:AddDoubleLine(L["From"] .. ":", name)
					tip:Show()
				end
			else
				local name = GetUnitName(caster, true)
				local hexColor = F.ColorStr(F.UnitColor(caster))
				tip:AddDoubleLine(L["From"] .. ":", hexColor .. (name or UNKNOWN))
				tip:Show()
			end
		end
	end

	hooksecurefunc(GameTooltip, "SetUnitAura", function(tip, ...)
		if tip:IsForbidden() then return end
		local data = C_UnitAuras.GetAuraDataByIndex(...)
		if data then HandleAuraData(tip, data) end
	end)

	local function UpdateAuraTip(tip, ...)
		if tip:IsForbidden() then return end
		local data = C_UnitAuras.GetAuraDataByAuraInstanceID(...)
		if data then HandleAuraData(tip, data) end
	end
	hooksecurefunc(GameTooltip, "SetUnitBuffByAuraInstanceID", UpdateAuraTip)
	hooksecurefunc(GameTooltip, "SetUnitDebuffByAuraInstanceID", UpdateAuraTip)
	hooksecurefunc(GameTooltip, "SetUnitAuraByAuraInstanceID", UpdateAuraTip)

	hooksecurefunc("SetItemRef", function(link)
		local id = tonumber(strmatch(link, "spell:(%d+)"))
		if id then Tooltip.AddLineForID(ItemRefTooltip, id, types.spell) end
	end)

	if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall) then return end

	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tip, data)
		if tip:IsForbidden() then return end
		if data.id then Tooltip.AddLineForID(tip, data.id, types.spell) end
	end)

	local function UpdateActionTooltip(tip, data)
		if tip:IsForbidden() then return end
		local lineData = data.lines and data.lines[1]
		local tooltipType = lineData and lineData.tooltipType
		if not tooltipType then return end
		if tooltipType == 0 then
			Tooltip.AddLineForID(tip, lineData.tooltipID, types.item)
		elseif tooltipType == 1 then
			Tooltip.AddLineForID(tip, lineData.tooltipID, types.spell)
		end
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Macro, UpdateActionTooltip)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.PetAction, UpdateActionTooltip)

	local function addItemID(tip, data)
		if tip:IsForbidden() then return end
		if data.id then Tooltip.AddLineForID(tip, data.id, types.item) end
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, addItemID)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Toy, addItemID)

	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Currency, function(tip, data)
		if tip:IsForbidden() then return end
		if data.id then Tooltip.AddLineForID(tip, data.id, types.currency) end
	end)

	hooksecurefunc(GameTooltip, "SetAzeritePower", function(tip, _, _, id)
		if id then Tooltip.AddLineForID(tip, id, types.azerite, true) end
	end)

	if _G["QuestMapLogTitleButton_OnEnter"] then
		hooksecurefunc("QuestMapLogTitleButton_OnEnter", function(btn)
			if btn.questID then
				Tooltip.AddLineForID(GameTooltip, btn.questID, types.quest)
			end
		end)
	end
end
