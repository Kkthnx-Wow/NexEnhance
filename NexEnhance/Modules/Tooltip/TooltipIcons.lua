--[[
	NexEnhance - Tooltip Icons
	-------------------------------------------------------------------------
	Adds an icon next to the tooltip title (and tidies inline/reward icons) for
	items, toys, spells and mounts.
--]]

local _, ns = ...
local F, C = ns.F, ns.C
local Tooltip = ns:GetModule("Tooltip")
if not Tooltip then
	return
end

local _G = _G
local gsub, strfind, unpack, select, next = string.gsub, string.find, unpack, select, next
local hooksecurefunc = hooksecurefunc
local C_MountJournal_GetMountInfoByID = C_MountJournal and C_MountJournal.GetMountInfoByID
local C_Item_GetItemIconByID = C_Item.GetItemIconByID
local C_Spell_GetSpellTexture = C_Spell.GetSpellTexture
-- |T texcoord tail: full 64x64 texture, cropped 5..59 on both axes to shave the
-- ugly default icon border. Looks like keyboard mashing; it isn't. Reused for
-- every inline icon rewrite below so they all crop identically.
local newString = "0:0:64:64:5:59:5:59"

function Tooltip:SetupTooltipIcon(icon)
	if not Tooltip:IsEnabled() or not ns.db.tooltip.showIcons then
		return
	end
	local title = icon and _G[self:GetName() .. "TextLeft1"]
	local titleText = title and title:GetText()
	if titleText and F.NotSecret(titleText) and not strfind(titleText, ":20:20:") then
		title:SetFormattedText("|T%s:20:20:" .. newString .. ":%d|t %s", icon, 20, titleText)
	end

	for i = 2, self:NumLines() do
		local line = _G[self:GetName() .. "TextLeft" .. i]
		if not line then
			break
		end
		local text = line:GetText()
		-- Secret check FIRST: string ops (strfind/gsub) error on secret strings
		-- (e.g. aura tooltips in instances). Only then the cheap |T pre-filter so
		-- we skip the gsub on lines without a texture escape.
		if text and F.NotSecret(text) and text ~= " " and strfind(text, "|T", 1, true) then
			local newText, count = gsub(text, "|T([^:]-):[%d+:]+|t", "|T%1:14:14:" .. newString .. "|t")
			if count > 0 then
				line:SetText(newText)
			end
		end
	end
end

local function ReskinRewardIcon(frame)
	if not frame or not frame.Icon then
		return
	end
	frame.Icon:SetTexCoord(unpack(C.TexCoord))
	if frame.IconBorder then
		frame.IconBorder:SetAlpha(0)
	end
end

local GetTooltipTextureByType = {
	[Enum.TooltipDataType.Item] = function(id)
		return C_Item_GetItemIconByID(id)
	end,
	[Enum.TooltipDataType.Toy] = function(id)
		return C_Item_GetItemIconByID(id)
	end,
	[Enum.TooltipDataType.Spell] = function(id)
		return C_Spell_GetSpellTexture(id)
	end,
	[Enum.TooltipDataType.Mount] = function(id)
		if C_MountJournal_GetMountInfoByID then
			return select(3, C_MountJournal_GetMountInfoByID(id))
		end
	end,
}

function Tooltip:ReskinTooltipIcons()
	local tooltips = {
		[GameTooltip] = true,
		[ItemRefTooltip] = true,
		[ShoppingTooltip1] = true,
		[ShoppingTooltip2] = true,
	}

	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
		for tooltipType, getTex in next, GetTooltipTextureByType do
			TooltipDataProcessor.AddTooltipPostCall(tooltipType, function(tip)
				if tooltips[tip] then
					local data = tip:GetTooltipData()
					local id = data and data.id
					if id then
						Tooltip.SetupTooltipIcon(tip, getTex(id))
					end
				end
			end)
		end
	end

	-- These tooltip setters may be absent on some clients; guard each hook so a
	-- missing method degrades quietly instead of erroring during setup.
	if GameTooltip.SetUnitAura then
		hooksecurefunc(GameTooltip, "SetUnitAura", function(tip)
			Tooltip.SetupTooltipIcon(tip)
		end)
	end
	if GameTooltip.SetAzeriteEssence then
		hooksecurefunc(GameTooltip, "SetAzeriteEssence", function(tip)
			Tooltip.SetupTooltipIcon(tip)
		end)
	end
	if GameTooltip.SetAzeriteEssenceSlot then
		hooksecurefunc(GameTooltip, "SetAzeriteEssenceSlot", function(tip)
			Tooltip.SetupTooltipIcon(tip)
		end)
	end

	local gt = GameTooltip ---@type any
	local eit = EmbeddedItemTooltip ---@type any
	if gt.ItemTooltip then
		ReskinRewardIcon(gt.ItemTooltip)
	end
	if eit and eit.ItemTooltip then
		ReskinRewardIcon(eit.ItemTooltip)
	end
end
