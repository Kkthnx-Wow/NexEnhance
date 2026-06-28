--[[
	NexEnhance - Tooltip Pawn integration
	-------------------------------------------------------------------------
	When our tooltip icons or quality-coloured border are enabled, suppress
	Pawn's overlapping features (corner icon frames and green upgrade borders)
	via PawnRegisterThirdPartyTooltip and a post-hook on PawnAttachIconToTooltip.
--]]

local _, ns = ...
local L = ns.L
local Tooltip = ns:GetModule("Tooltip")
if not Tooltip then
	return
end

local ipairs = ipairs
local hooksecurefunc = hooksecurefunc
local C_AddOns = C_AddOns

local PAWN_ADDON = "Pawn"
local PAWN_REGISTRY = "NexEnhance"

-- Tooltips Pawn may attach corner icons to (see PawnToggleTooltipIcons).
local PAWN_ICON_TOOLTIPS = {
	"ItemRefTooltip",
	"ItemRefTooltip2",
	"ItemRefTooltip3",
	"ItemRefTooltip4",
	"ItemRefTooltip5",
	"ShoppingTooltip1",
	"ShoppingTooltip2",
	"ComparisonTooltip1",
	"ComparisonTooltip2",
}

local installed
local pawnRegistered

local function PawnEnabled()
	if C_AddOns.IsAddOnLoaded(PAWN_ADDON) then
		return true
	end
	local name, _, _, enabled = C_AddOns.GetAddOnInfo(PAWN_ADDON)
	return name == PAWN_ADDON and enabled
end

local function ShouldOverrideIcons()
	return ns.db.tooltip.showIcons
end

local function ShouldOverrideBorder()
	return ns.db.tooltip.qualityBorder
end

local function SetTooltipBorderColor(tooltip, r, g, b, a)
	local nineSlice = tooltip and tooltip.NineSlice
	if nineSlice and nineSlice.SetBorderColor then
		nineSlice:SetBorderColor(r, g, b, a or 1)
	end
end

local function HidePawnIconFrame(tooltip)
	if tooltip and tooltip.PawnIconFrame then
		tooltip.PawnIconFrame:Hide()
	end
end

local function HideAllPawnIcons()
	if _G.PawnHideTooltipIcon then
		for i = 1, #PAWN_ICON_TOOLTIPS do
			PawnHideTooltipIcon(PAWN_ICON_TOOLTIPS[i])
		end
		return
	end
	for i = 1, #PAWN_ICON_TOOLTIPS do
		HidePawnIconFrame(_G[PAWN_ICON_TOOLTIPS[i]])
	end
end

local function OnPawnBorderColor(tooltip, r, g, b, a)
	if not tooltip or tooltip:IsForbidden() then
		return
	end

	if ShouldOverrideBorder() then
		-- Pawn's green upgrade tint — NexEnhance quality border owns item frames.
		if r == 0 and g == 1 and b == 0 then
			return
		end
		-- White reset on hide / non-upgrade: honour unless our quality tint is active.
		if r == 1 and g == 1 and b == 1 and tooltip.nexQualityBorder then
			return
		end
	end

	SetTooltipBorderColor(tooltip, r, g, b, a)
end

local function OnPawnAttachIcon(tooltip)
	if ShouldOverrideIcons() then
		HidePawnIconFrame(tooltip)
	end
end

local function RegisterPawnTooltip()
	if pawnRegistered or not _G.PawnRegisterThirdPartyTooltip then
		return
	end
	PawnRegisterThirdPartyTooltip(PAWN_REGISTRY, {
		SetBackdropBorderColor = OnPawnBorderColor,
	})
	pawnRegistered = true
end

function Tooltip:RefreshPawnIntegration()
	if not installed then
		return
	end
	if ShouldOverrideIcons() then
		HideAllPawnIcons()
	elseif _G.PawnToggleTooltipIcons then
		PawnToggleTooltipIcons()
	end
	if GameTooltip and GameTooltip:IsShown() and GameTooltip.RefreshData then
		GameTooltip:RefreshData()
	end
end

function Tooltip:SetupPawnIntegration()
	local function Install()
		if installed or not C_AddOns.IsAddOnLoaded(PAWN_ADDON) then
			return
		end
		if not (_G.PawnRegisterThirdPartyTooltip or _G.PawnAttachIconToTooltip) then
			return
		end

		installed = true
		RegisterPawnTooltip()
		if PawnAttachIconToTooltip then
			hooksecurefunc("PawnAttachIconToTooltip", OnPawnAttachIcon)
		end
		Tooltip.RefreshPawnIntegration(Tooltip)
	end

	if C_AddOns.IsAddOnLoaded(PAWN_ADDON) then
		Install()
	else
		Tooltip:RegisterTooltips(PAWN_ADDON, Install)
	end
end

function Tooltip:PawnIsAvailable()
	return PawnEnabled()
end

function Tooltip:GetPawnIconsOverrideTip(baseTip)
	if not self:PawnIsAvailable() then
		return baseTip
	end
	return baseTip .. " " .. L["Tooltip Pawn Icons Override"]
end

function Tooltip:GetPawnBorderOverrideTip(baseTip)
	if not self:PawnIsAvailable() then
		return baseTip
	end
	return baseTip .. " " .. L["Tooltip Pawn Border Override"]
end
