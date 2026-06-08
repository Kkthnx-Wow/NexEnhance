--[[
	NexEnhance - Junk Icon
	-------------------------------------------------------------------------
	Blizzard only draws the little coin "junk" overlay on Poor-quality bag
	items while a merchant window is open. This forces that overlay to show all
	the time, so you can spot vendor trash at a glance anywhere.

	Implementation: post-hook ContainerFrameItemButtonMixin:UpdateJunkItem and
	re-apply Blizzard's own show logic minus the MerchantFrame:IsShown() gate.
	It's a pure display hook on the bag item buttons (not a protected action),
	so there's no taint or combat concern.
--]]

-- luacheck: globals ContainerFrameItemButtonMixin
-- luacheck: read_globals ItemLocation C_Item Enum
---@diagnostic disable: undefined-global, undefined-field
local _, ns = ...
local L, F = ns.L, ns.F

local hooksecurefunc = hooksecurefunc
local ItemLocation = ItemLocation
local C_Item = C_Item
local Enum = Enum

ns:RegisterDefaults({
	junkIcon = {
		enable = true,
	},
})

local JunkIcon = ns:NewModule("JunkIcon", "junkIcon", { group = "inventory", title = L["Junk Icon"], order = 50 })

-- Runs after Blizzard's own UpdateJunkItem. Blizzard hides the icon unless a
-- merchant is open; we re-show it for Poor-quality, sellable items regardless.
local function ForceJunkIcon(button, quality, noValue)
	local icon = button.JunkIcon
	if not icon or icon:IsShown() then return end -- already shown by Blizzard

	-- Quality is a plain enum on bag items (not Secret), but guard anyway.
	if F.IsSecret(quality) then return end
	if quality ~= Enum.ItemQuality.Poor or noValue then return end

	local itemLocation = ItemLocation:CreateFromBagAndSlot(button:GetBagID(), button:GetID())
	if C_Item.DoesItemExist(itemLocation) then
		icon:Show()
	end
end

function JunkIcon:OnEnable()
	local mixin = ContainerFrameItemButtonMixin
	if not (mixin and type(mixin.UpdateJunkItem) == "function") then return end

	hooksecurefunc(mixin, "UpdateJunkItem", ForceJunkIcon)
end

function JunkIcon:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Junk Icon"], L["Always show the coin icon on Poor-quality bag items, not just when a merchant is open (reload to disable)."])
end
