--[[
	NexEnhance - ItemLevel
	-------------------------------------------------------------------------
	Paints effective item levels (and, optionally, gem/enchant icons) across
	the equipped, inventory and item-display surfaces:
	  * Character & Inspect equipped slots (item level + gems + sockets + enchant).
	  * Equipment-manager flyout buttons.
	  * Merchant buttons.
	  * Trade window (your side + their side).
	  * Loot window.
	  * Bags & bank slots (item level + BoE/BoA/WuE bind labels).
	  * Scrapping machine (load-on-demand).
	  * Guild News links (load-on-demand).

	Adapted to the NexEnhance architecture from NDui's Misc/ItemLevel (by yleaf):
	  https://github.com/siweia/NDui/blob/master/Interface/AddOns/NDui/Modules/Misc/ItemLevel.lua

	Bag bind-status labels (BoE / BoA / WuE) borrow the idea from Lars Norberg's
	BlizzardBags_BoE (GoldpawsStuff) — thanks, friend:
	  https://github.com/GoldpawsStuff/BlizzardBags_BoE

	Item level / gem / enchant data comes from F.GetItemLevel (Core/Functions),
	which uses the structured C_TooltipInfo API. Hooks are existence-guarded so
	the module degrades quietly when a frame/addon is absent.
--]]

local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

-- Localised globals / API.
local _G = _G
local pairs, select, type = pairs, select, type
local strsub, strupper, format = string.sub, string.upper, string.format
local hooksecurefunc = hooksecurefunc
local C_Timer = C_Timer
local C_Item = C_Item
local C_Item_GetItemGem = C_Item.GetItemGem
local C_Container = C_Container
local C_Container_GetContainerItemInfo = C_Container.GetContainerItemInfo
local C_Container_GetContainerItemLink = C_Container.GetContainerItemLink
local UnitExists = UnitExists
local UnitGUID = UnitGUID
local GetInventoryItemLink = GetInventoryItemLink
local GameTooltip = GameTooltip

local QUALITY_COLORS = _G["ITEM_QUALITY_COLORS"]
local TEX_COORD = C.TexCoord -- shared icon-zoom crop (Core/Constants)
local FONT = C.Media.Fonts.normal
local MISSING_ENCHANT_ICON = 134400 -- inv_misc_questionmark

ns:RegisterDefaults({
	itemLevel = {
		enable = true,
		gemsEnchants = true,
		missingEnchant = true,
		showBindText = true,
		fontSize = 12,
	},
})

local ItemLevel = ns:NewModule("ItemLevel", "itemLevel", { group = "inventory", title = L["Item Level"], order = 10 })

local eventHandles = {}
local eventsRegistered = false

local function IsActive()
	return ns.db and ns.db.itemLevel and ns.db.itemLevel.enable
end

-- Inventory-slot ID -> slot name. The numeric index doubles as the inventory
-- slot id passed to GetInventoryItemLink / C_TooltipInfo.GetInventoryItem.
local inspectSlots = {
	"Head",
	"Neck",
	"Shoulder",
	"Shirt",
	"Chest",
	"Waist",
	"Legs",
	"Feet",
	"Wrist",
	"Hands",
	"Finger0",
	"Finger1",
	"Trinket0",
	"Trinket1",
	"Back",
	"MainHand",
	"SecondaryHand",
}

-- Equipment slots that take a permanent enchant in current retail; used to flag
-- an equipped item that is missing one. Indices match inspectSlots / inventory
-- slot ids. Adjust if Blizzard changes which slots are enchantable.
-- Midnight (11.x) reworked enchant slots: Wrist and Back/Cloak enchants were
-- removed, and Head and Shoulder enchants were (re)added.
local enchantableSlots = {
	[1] = true, -- Head
	[3] = true, -- Shoulder
	[5] = true, -- Chest
	[7] = true, -- Legs
	[8] = true, -- Feet
	[11] = true, -- Finger 1
	[12] = true, -- Finger 2
	[16] = true, -- Main Hand
	[17] = true, -- Off Hand
}

-- ---------------------------------------------------------------------------
-- Small widget helpers (kept local: specific to this module's overlays)
-- ---------------------------------------------------------------------------
local function CreateFS(parent, size)
	local fs = F.CreatePlainFS(parent, size)
	fs:SetFont(FONT, size, "OUTLINE")
	fs:SetWordWrap(false)
	if fs.nexShadow then
		fs.nexShadow:SetFont(FONT, size, "OUTLINE")
	end
	return fs
end

-- Item-level fontstrings use a user-configurable size. They are tracked here so
-- the size slider can re-apply to every existing label live (created once per
-- button/slot, so the table only grows as new surfaces are seen).
local iLvlStrings = {}

local function GetILvlFontSize()
	return (ns.db and ns.db.itemLevel and ns.db.itemLevel.fontSize) or 12
end

local function CreateILvlFS(parent)
	local fs = CreateFS(parent, GetILvlFontSize())
	iLvlStrings[#iLvlStrings + 1] = fs
	return fs
end

local function ApplyILvlFontSize()
	local size = GetILvlFontSize()
	for i = 1, #iLvlStrings do
		F.SetFontSize(iLvlStrings[i], size)
	end
end

-- Gem socket hover: show the socketed gem's own tooltip (link resolved at scan
-- time and stashed on the border frame, which carries the mouse region).
local function GemIcon_OnEnter(self)
	if not self.gemLink then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink(self.gemLink)
	GameTooltip:Show()
end

local function GemIcon_OnLeave()
	GameTooltip:Hide()
end

-- A gem/socket icon with a thin 1px border that we toggle with the icon. The
-- border frame doubles as the mouse region for the gem tooltip.
local function CreateGemIcon(parent, point, x, y)
	local icon = parent:CreateTexture(nil, "OVERLAY")
	icon:SetPoint(point, x, y)
	icon:SetSize(14, 14)
	icon:SetTexCoord(TEX_COORD[1], TEX_COORD[2], TEX_COORD[3], TEX_COORD[4])

	local bg = _G.CreateFrame("Frame", nil, parent, "BackdropTemplate")
	bg:SetBackdrop({ edgeFile = C.Media.Textures.blank, edgeSize = 1 })
	bg:SetBackdropBorderColor(0, 0, 0)
	bg:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
	bg:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
	bg:SetFrameLevel(parent:GetFrameLevel() + 3)
	bg:EnableMouse(true)
	bg:SetScript("OnEnter", GemIcon_OnEnter)
	bg:SetScript("OnLeave", GemIcon_OnLeave)
	bg:Hide()
	icon.bg = bg

	return icon
end

-- Missing-enchant warning: a red-tinted icon whose tooltip names its slot.
local function MissingEnchant_OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(format(L["Missing Enchant: %s"], self.slotName or ""), 1, 0.2, 0.2)
	GameTooltip:Show()
end

-- Built with the same icon + 1px border box as the gem icons so the marker
-- matches them exactly in size and shape. The border frame carries the mouse.
local function CreateMissingIcon(parent, point, x, y, slotName)
	local icon = parent:CreateTexture(nil, "OVERLAY")
	icon:SetPoint(point, x, y)
	icon:SetSize(14, 14)
	icon:SetTexCoord(TEX_COORD[1], TEX_COORD[2], TEX_COORD[3], TEX_COORD[4])
	icon:SetTexture(MISSING_ENCHANT_ICON)
	icon:Hide()

	local bg = _G.CreateFrame("Frame", nil, parent, "BackdropTemplate")
	bg:SetBackdrop({ edgeFile = C.Media.Textures.blank, edgeSize = 1 })
	bg:SetBackdropBorderColor(0, 0, 0)
	bg:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
	bg:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
	bg:SetFrameLevel(parent:GetFrameLevel() + 4)
	bg:EnableMouse(true)
	bg.slotName = slotName
	bg:SetScript("OnEnter", MissingEnchant_OnEnter)
	bg:SetScript("OnLeave", GemIcon_OnLeave)
	bg:Hide()
	icon.bg = bg

	return icon
end

-- Quality and item level can both read Secret inside instances on 12.0 (Blizzard
-- locks loot/bag data to thwart automation). A secret poisons every >, <= and
-- table-index it touches, so we gate before comparing. A skipped overlay beats a
-- Lua error mid-loot any day of the week.
local function GetQualityColor(quality)
	if F.IsSecret(quality) then
		return 1, 1, 1
	end
	local color = quality and QUALITY_COLORS and QUALITY_COLORS[quality]
	if not color then
		return 1, 1, 1
	end
	return color.r, color.g, color.b
end

-- True only when both reads are non-secret and worth painting (quality above
-- Common, real item level). Either being secret short-circuits to false.
local function LevelIsShowable(level, quality)
	if F.IsSecret(level) or F.IsSecret(quality) then
		return false
	end
	return level and level > 1 and quality and quality > 1
end

local function SetBindLabelColor(fs, label)
	if label == "BoA" or label == "WuE" then
		fs:SetTextColor(0, 0.8, 1)
	else
		fs:SetTextColor(1, 1, 1)
	end
end

-- ---------------------------------------------------------------------------
-- Anchors for the per-slot enchant text (mirrors NDui's layout)
-- ---------------------------------------------------------------------------
local function GetSlotAnchor(index)
	if not index then
		return "BOTTOMLEFT", 40, 20
	end
	if index <= 5 or index == 9 or index == 15 then
		return "BOTTOMLEFT", 40, 20
	elseif index == 16 then
		return "BOTTOMRIGHT", -40, 2
	elseif index == 17 then
		return "BOTTOMLEFT", 40, 2
	else
		return "BOTTOMRIGHT", -40, 20
	end
end

local function ItemString_Expand(self)
	self:SetWidth(0)
end
local function ItemString_Collapse(self)
	self:SetWidth(100)
end

-- ---------------------------------------------------------------------------
-- Per-slot overlay construction (Character / Inspect)
-- ---------------------------------------------------------------------------
function ItemLevel:CreateItemStrings(frame, strType)
	if frame.nexItemStringsDone then
		return
	end
	frame.nexItemStringsDone = true

	for index, slot in pairs(inspectSlots) do
		if index ~= 4 then -- skip Shirt
			local slotFrame = _G[strType .. slot .. "Slot"]
			if slotFrame then
				slotFrame.iLvlText = CreateILvlFS(slotFrame)
				slotFrame.iLvlText:ClearAllPoints()
				slotFrame.iLvlText:SetPoint("BOTTOMLEFT", slotFrame, "BOTTOMLEFT", 1, 1)

				local point, x, y = GetSlotAnchor(index)
				slotFrame.enchantText = CreateFS(slotFrame, 13)
				slotFrame.enchantText:ClearAllPoints()
				slotFrame.enchantText:SetPoint(point, slotFrame, point, x, y)
				slotFrame.enchantText:SetTextColor(0, 1, 0)
				slotFrame.enchantText:SetJustifyH(strsub(point, 7))
				slotFrame.enchantText:SetWidth(100)
				slotFrame.enchantText:EnableMouse(true)
				slotFrame.enchantText:HookScript("OnEnter", ItemString_Expand)
				slotFrame.enchantText:HookScript("OnLeave", ItemString_Collapse)
				slotFrame.enchantText:HookScript("OnShow", ItemString_Collapse)

				for i = 1, 10 do
					local offset = (i - 1) * 18 + 5
					local iconX = x > 0 and x + offset or x - offset
					local iconY = index > 15 and 20 or 2
					slotFrame["nexGem" .. i] = CreateGemIcon(slotFrame, point, iconX, iconY)
				end

				-- Missing-enchant marker, built only for enchantable slots. Same size
				-- as the gem icons and pushed out the same distance (the first gem's
				-- x offset), but kept on the enchant-text row so it clears the gems.
				if enchantableSlots[index] then
					slotFrame.nexEnchantable = true
					slotFrame.nexSlotName = _G[strupper(slot) .. "SLOT"] or slot
					local markX = x > 0 and x + 5 or x - 5
					slotFrame.enchantMissing = CreateMissingIcon(slotFrame, point, markX, y, slotFrame.nexSlotName)
				end
			end
		end
	end
end

function ItemLevel:UpdateSlotInfo(slotFrame, info, quality, link)
	if not slotFrame or not slotFrame.iLvlText then
		return
	end

	local infoType = type(info)
	local level = infoType == "table" and info.iLvl or info

	if LevelIsShowable(level, quality) then
		slotFrame.iLvlText:SetText(level)
		slotFrame.iLvlText:SetTextColor(GetQualityColor(quality))
	end

	if infoType ~= "table" then
		return
	end

	local showGems = ns.db.itemLevel.gemsEnchants
	local enchant = info.enchantText

	-- Enchant text only when the user wants gem/enchant detail shown.
	if showGems and enchant then
		slotFrame.enchantText:SetText((enchant:gsub("^.-%s%-%s", ""))) -- strip "Source - " prefix
	else
		slotFrame.enchantText:SetText("")
	end

	local gemStep = 1
	for i = 1, 10 do
		local icon = slotFrame["nexGem" .. i]
		local bg = icon.bg
		local gem = showGems and info.gems and info.gems[gemStep]
		local color = info.gemsColor and info.gemsColor[gemStep]
		if gem then
			icon:SetTexture(gem)
			-- Resolve the gem's link for its hover tooltip. Socket order matches
			-- the scan order; empty sockets / essences return nil (no tooltip).
			bg.gemLink = link and C_Item_GetItemGem and select(2, C_Item_GetItemGem(link, gemStep)) or nil
			if color then
				bg:SetBackdropBorderColor(color.r, color.g, color.b)
			else
				bg:SetBackdropBorderColor(0, 0, 0)
			end
			bg:Show()
			gemStep = gemStep + 1
		else
			icon:SetTexture(nil)
			bg.gemLink = nil
			bg:Hide()
		end
	end

	-- Flag an enchantable slot whose item has no enchant.
	local missing = slotFrame.enchantMissing
	if missing then
		local show = ns.db.itemLevel.missingEnchant and slotFrame.nexEnchantable and not enchant
		missing:SetShown(show)
		missing.bg:SetShown(show)
	end
end

function ItemLevel:RefreshSlotInfo(unit, index, slotFrame, fullScan)
	C_Timer.After(0.1, function()
		if not UnitExists(unit) then
			return
		end
		local link = GetInventoryItemLink(unit, index)
		if not link then
			return
		end
		local quality = select(3, C_Item.GetItemInfo(link))
		local info = F.GetItemLevel(link, unit, index, fullScan)
		self:UpdateSlotInfo(slotFrame, info, quality, link)
	end)
end

function ItemLevel:SetupSlots(frame, strType, unit)
	if not UnitExists(unit) then
		return
	end

	self:CreateItemStrings(frame, strType)
	-- The enchant scan needs the full tooltip read, so run it when either the
	-- gem/enchant display or the missing-enchant warning is enabled.
	local fullScan = ns.db.itemLevel.gemsEnchants or ns.db.itemLevel.missingEnchant

	for index, slot in pairs(inspectSlots) do
		if index ~= 4 then
			local slotFrame = _G[strType .. slot .. "Slot"]
			if slotFrame and slotFrame.iLvlText then
				slotFrame.iLvlText:SetText("")
				slotFrame.enchantText:SetText("")
				if slotFrame.enchantMissing then
					slotFrame.enchantMissing:Hide()
					slotFrame.enchantMissing.bg:Hide()
				end
				for i = 1, 10 do
					local icon = slotFrame["nexGem" .. i]
					icon:SetTexture(nil)
					icon.bg.gemLink = nil
					icon.bg:Hide()
				end

				local link = GetInventoryItemLink(unit, index)
				if link then
					local quality = select(3, C_Item.GetItemInfo(link))
					if not quality then
						self:RefreshSlotInfo(unit, index, slotFrame, fullScan)
					else
						local info = F.GetItemLevel(link, unit, index, fullScan)
						self:UpdateSlotInfo(slotFrame, info, quality, link)
					end
				end
			end
		end
	end
end

function ItemLevel:UpdatePlayerSlots()
	if not IsActive() then
		return
	end
	self:SetupSlots(_G["CharacterFrame"], "Character", "player")
end

function ItemLevel:INSPECT_READY(guid)
	if not IsActive() then
		return
	end
	local InspectFrame = _G["InspectFrame"]
	if not (InspectFrame and InspectFrame.unit) then
		return
	end
	-- UnitGUID (and the event's guid) can be secret while inspecting in an
	-- instance; comparing two secrets throws, so confirm both are readable first.
	local inspectGUID = UnitGUID(InspectFrame.unit)
	if F.NotSecret(inspectGUID) and F.NotSecret(guid) and inspectGUID == guid then
		self:SetupSlots(InspectFrame, "Inspect", InspectFrame.unit)
	end
end

-- ---------------------------------------------------------------------------
-- Generic single-link overlay (flyout / merchant / trade / loot / bags)
-- ---------------------------------------------------------------------------
local function SetSimpleLevel(button, link, quality, bagID, slotID)
	if not button.nexILvl then
		button.nexILvl = CreateILvlFS(button)
		button.nexILvl:SetPoint("BOTTOMLEFT", 1, 1)
	end

	-- Secret quality means "instance loot we can't reason about" -> clear, bail.
	if not link or F.IsSecret(quality) or (quality and quality <= 1) then
		button.nexILvl:SetText("")
		return
	end

	local level = F.GetItemLevel(link, bagID, slotID)
	if LevelIsShowable(level, quality) then
		button.nexILvl:SetText(level)
		button.nexILvl:SetTextColor(GetQualityColor(quality))
	else
		button.nexILvl:SetText("")
	end
end

-- ---------------------------------------------------------------------------
-- Equipment-manager flyout
-- ---------------------------------------------------------------------------
function ItemLevel:FlyoutButton(button)
	if not IsActive() then
		return
	end
	if not button.nexILvl then
		button.nexILvl = CreateILvlFS(button)
		button.nexILvl:SetPoint("BOTTOMLEFT", 1, 1)
	end
	button.nexILvl:SetText("")

	local location = button.location
	if not location then
		return
	end

	local EquipmentManager_GetLocationData = _G["EquipmentManager_GetLocationData"]
	local EquipmentManager_GetItemInfoByLocation = _G["EquipmentManager_GetItemInfoByLocation"]
	local special = _G["EQUIPMENTFLYOUT_FIRST_SPECIAL_LOCATION"]

	if type(location) == "number" then
		if special and location >= special then
			return
		end
		if not EquipmentManager_GetLocationData then
			return
		end

		local locationData = EquipmentManager_GetLocationData(location)
		if not locationData then
			return
		end
		local quality = EquipmentManager_GetItemInfoByLocation and select(13, EquipmentManager_GetItemInfoByLocation(location))
		if locationData.isBags then
			SetSimpleLevel(button, C_Container_GetContainerItemLink(locationData.bag, locationData.slot), quality, locationData.bag, locationData.slot)
		else
			SetSimpleLevel(button, GetInventoryItemLink("player", locationData.slot), quality)
		end
	elseif button.GetItemLocation then
		local itemLocation = button:GetItemLocation()
		if not itemLocation then
			return
		end
		local quality = C_Item.GetItemQuality(itemLocation)
		if itemLocation:IsBagAndSlot() then
			local bag, slot = itemLocation:GetBagAndSlot()
			SetSimpleLevel(button, C_Container_GetContainerItemLink(bag, slot), quality, bag, slot)
		elseif itemLocation:IsEquipmentSlot() then
			local slot = itemLocation:GetEquipmentSlot()
			SetSimpleLevel(button, GetInventoryItemLink("player", slot), quality)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Merchant
-- ---------------------------------------------------------------------------
function ItemLevel:MerchantButton(link)
	if not IsActive() then
		return
	end
	local button = _G[self:GetName() .. "ItemButton"]
	if not button then
		return
	end
	local quality = link and select(3, C_Item.GetItemInfo(link))
	SetSimpleLevel(button, link, quality)
end

-- ---------------------------------------------------------------------------
-- Trade
-- ---------------------------------------------------------------------------
local function UpdateTradeItem(prefix, index, link)
	local button = _G[prefix .. index]
	if not button then
		return
	end
	local quality = link and select(3, C_Item.GetItemInfo(link))
	SetSimpleLevel(button, link, quality)
end

-- ---------------------------------------------------------------------------
-- Loot
-- ---------------------------------------------------------------------------
function ItemLevel:UpdateLoot()
	if not IsActive() then
		return
	end
	local scrollTarget = self.ScrollTarget
	if not scrollTarget then
		return
	end

	for i = 1, scrollTarget:GetNumChildren() do
		local button = select(i, scrollTarget:GetChildren())
		-- During the loot frame's hide animation the ScrollBox still runs Update,
		-- but the recycled children have no element data yet (GetElementData is
		-- nil / returns nil), so read the slot index defensively.
		local elementData = button and button.Item and button.GetElementData and button:GetElementData()
		local slotIndex = elementData and elementData.slotIndex
		if slotIndex then
			if not button.nexILvl then
				button.nexILvl = CreateILvlFS(button.Item)
				button.nexILvl:SetPoint("BOTTOMLEFT", 1, 1)
			end
			local quality = select(5, _G.GetLootSlotInfo(slotIndex))
			local link = _G.GetLootSlotLink(slotIndex)
			local level = link and F.GetItemLevel(link)
			if LevelIsShowable(level, quality) then
				button.nexILvl:SetText(level)
				button.nexILvl:SetTextColor(GetQualityColor(quality))
			elseif button.nexILvl then
				button.nexILvl:SetText("")
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Bags & bank
--   Bind overlay (nexBind) follows GoldpawsStuff's BlizzardBags_BoE approach;
--   see the module header for credit and link.
--
--   We post-hook each item button's UpdateCooldown - the final call Blizzard
--   makes when refreshing a slot - so the item-level and bind overlays repaint
--   on every refresh for bags, the character bank and the warband bank alike.
--   (Triggering off IconBorder:SetShown instead, as we used to, misses the
--   bank/warband refresh path: it updates item buttons without toggling the
--   quality border, so those overlays never populated. Mirrors the proven
--   UnusableItems coverage.)
-- ---------------------------------------------------------------------------
local function UpdateBagSlot(button)
	if not IsActive() or not button then
		return
	end

	if not button.nexILvl then
		button.nexILvl = CreateILvlFS(button)
		button.nexILvl:SetPoint("BOTTOMLEFT", 1, 1)
	end

	-- bagID 0 (backpack) is valid, so test for nil rather than falsiness.
	local bagID = button.GetBankTabID and button:GetBankTabID() or (button.GetBagID and button:GetBagID())
	local slotID = button.GetContainerSlotID and button:GetContainerSlotID() or (button.GetID and button:GetID())
	if bagID == nil or slotID == nil then
		button.nexILvl:SetText("")
		if button.nexBind then
			button.nexBind:SetText("")
		end
		return
	end

	local info = C_Container_GetContainerItemInfo(bagID, slotID)
	local quality = info and info.quality
	local link = info and info.hyperlink

	if F.NotSecret(quality) and quality and quality > 1 then
		local level = F.GetItemLevel(link, bagID, slotID)
		button.nexILvl:SetText(level)
		button.nexILvl:SetTextColor(GetQualityColor(quality))
	else
		button.nexILvl:SetText("")
	end

	if ns.db.itemLevel.showBindText and link then
		if not button.nexBind then
			button.nexBind = CreateFS(button, 12)
			button.nexBind:SetPoint("TOPRIGHT", -1, -1)
		end
		local label = F.GetItemBindLabel(link, bagID, slotID)
		if label then
			button.nexBind:SetText(label)
			SetBindLabelColor(button.nexBind, label)
		else
			button.nexBind:SetText("")
		end
	elseif button.nexBind then
		button.nexBind:SetText("")
	end
end

local function ScanFramePool(frame)
	local pool = frame and frame.itemButtonPool
	if not pool then
		return
	end
	for button in pool:EnumerateActive() do
		UpdateBagSlot(button)
	end
end

local function RefreshBagSlots()
	for i = 1, 13 do
		ScanFramePool(_G["ContainerFrame" .. i])
	end
	ScanFramePool(_G["ContainerFrameCombinedBags"])
	local bank = _G["BankFrame"]
	if bank and bank.BankPanel then
		ScanFramePool(bank.BankPanel)
	end
end

-- Discover the active item buttons in a pool, post-hook each one's
-- UpdateCooldown once, and paint it immediately so overlays show up on the
-- first open instead of waiting for the next refresh.
local function HandleBagSlots(frame)
	if not IsActive() then
		return
	end
	local pool = frame and frame.itemButtonPool
	if not pool then
		return
	end
	for button in pool:EnumerateActive() do
		if not button.nexBagHooked and type(button.UpdateCooldown) == "function" then
			hooksecurefunc(button, "UpdateCooldown", UpdateBagSlot)
			button.nexBagHooked = true
		end
		UpdateBagSlot(button)
	end
end

-- Bank hooking is split out and guarded so it can run from HookBags (if the
-- bank UI is already present) or lazily from BANKFRAME_OPENED (the bank panel
-- is load-on-demand, so it usually doesn't exist when the module first loads).
local bankHooked = false
local function HookBank()
	if bankHooked then
		return
	end
	local bank = _G["BankFrame"]
	local panel = bank and bank.BankPanel
	if not (panel and panel.GenerateItemSlotsForSelectedTab) then
		return
	end
	bankHooked = true
	hooksecurefunc(panel, "GenerateItemSlotsForSelectedTab", HandleBagSlots)
	-- Switching to an already-built tab (and most warband-bank refreshes) only
	-- calls RefreshAllItemsForSelectedTab, not GenerateItemSlots, so hook both.
	if panel.RefreshAllItemsForSelectedTab then
		hooksecurefunc(panel, "RefreshAllItemsForSelectedTab", HandleBagSlots)
	end
	HandleBagSlots(panel)
end

function ItemLevel:HookBags()
	for i = 1, 13 do
		local frame = _G["ContainerFrame" .. i]
		if frame and frame.UpdateItemSlots then
			hooksecurefunc(frame, "UpdateItemSlots", HandleBagSlots)
			HandleBagSlots(frame)
		end
	end
	local combined = _G["ContainerFrameCombinedBags"]
	if combined and combined.UpdateItemSlots then
		hooksecurefunc(combined, "UpdateItemSlots", HandleBagSlots)
		HandleBagSlots(combined)
	end
	HookBank()
end

-- Install the bank hooks the first time the bank opens (covers the load-on-
-- demand bank UI) and repaint the visible tab.
function ItemLevel:BANKFRAME_OPENED()
	if not IsActive() then
		return
	end
	HookBank()
	local bank = _G["BankFrame"]
	if bank and bank.BankPanel then
		HandleBagSlots(bank.BankPanel)
	end
end

-- ---------------------------------------------------------------------------
-- Scrapping machine (load-on-demand)
-- ---------------------------------------------------------------------------
local function ScrappingButtonUpdate(button)
	if not IsActive() then
		return
	end
	if not button.nexILvl then
		button.nexILvl = CreateILvlFS(button)
		button.nexILvl:SetPoint("BOTTOMLEFT", 1, 1)
	end
	if not button.itemLink then
		button.nexILvl:SetText("")
		return
	end

	local quality = 1
	if button.item and not button.item:IsItemEmpty() and button.item:GetItemName() then
		quality = button.item:GetItemQuality()
	end
	local level = F.GetItemLevel(button.itemLink)
	button.nexILvl:SetText(level)
	button.nexILvl:SetTextColor(GetQualityColor(quality))
end

local function ScrappingSetup(frame)
	if not IsActive() then
		return
	end
	if not frame.ItemSlots or not frame.ItemSlots.scrapButtons then
		return
	end
	for button in frame.ItemSlots.scrapButtons:EnumerateActive() do
		if button and not button.nexScrapHooked and button.RefreshIcon then
			hooksecurefunc(button, "RefreshIcon", ScrappingButtonUpdate)
			button.nexScrapHooked = true
		end
	end
end

-- ---------------------------------------------------------------------------
-- Guild News (load-on-demand): prepend item level to news item links
-- ---------------------------------------------------------------------------
local newsCache = {}
local function ReplaceNewsLink(link, name)
	if not link then
		return
	end
	local modLink = newsCache[link]
	if not modLink then
		local level = F.GetItemLevel(link)
		if level then
			modLink = link:gsub("|h%[(.-)%]|h", "|h(" .. level .. ")" .. name .. "|h")
			F.CacheSet(newsCache, link, modLink)
		end
	end
	return modLink
end

local function GuildNewsSetText(button)
	if not IsActive() then
		return
	end
	if not button.text then
		return
	end
	local newText = button.text:GetText()
	if not newText then
		return
	end
	newText = newText:gsub("(|Hitem:%d+:.-|h%[(.-)%]|h)", ReplaceNewsLink)
	if newText then
		button.text:SetText(newText)
	end
end

-- ---------------------------------------------------------------------------
-- Hook installation
-- ---------------------------------------------------------------------------
function ItemLevel:InstallHooks()
	if self.hooksInstalled then
		return
	end
	self.hooksInstalled = true

	-- Character frame.
	local CharacterFrame = _G["CharacterFrame"]
	if CharacterFrame then
		CharacterFrame:HookScript("OnShow", function()
			if IsActive() then
				ItemLevel:UpdatePlayerSlots()
			end
		end)
	end

	-- Inspect frame.

	-- Equipment flyout.
	if _G["EquipmentFlyout_UpdateItems"] then
		hooksecurefunc("EquipmentFlyout_UpdateItems", function()
			if not IsActive() then
				return
			end
			local flyout = _G["EquipmentFlyoutFrame"]
			if not flyout or not flyout.buttons then
				return
			end
			for _, button in pairs(flyout.buttons) do
				if button:IsShown() then
					ItemLevel:FlyoutButton(button)
				end
			end
		end)
	end

	-- Merchant.
	if _G["MerchantFrameItem_UpdateQuality"] then
		hooksecurefunc("MerchantFrameItem_UpdateQuality", self.MerchantButton)
	end

	-- Trade.
	if _G["TradeFrame_UpdatePlayerItem"] then
		hooksecurefunc("TradeFrame_UpdatePlayerItem", function(index)
			UpdateTradeItem("TradePlayerItem", index, _G["GetTradePlayerItemLink"](index))
		end)
	end
	if _G["TradeFrame_UpdateTargetItem"] then
		hooksecurefunc("TradeFrame_UpdateTargetItem", function(index)
			UpdateTradeItem("TradeRecipientItem", index, _G["GetTradeTargetItemLink"](index))
		end)
	end

	-- Loot.
	local LootFrame = _G["LootFrame"]
	if LootFrame and LootFrame.ScrollBox then
		hooksecurefunc(LootFrame.ScrollBox, "Update", self.UpdateLoot)
	end

	-- Bags & bank. The bank panel is load-on-demand, so also (re)hook it the
	-- first time the bank is opened.
	self:HookBags()

	-- Guild News (if Communities/GuildUI already present).
	if _G["GuildNewsButton_SetText"] then
		hooksecurefunc("GuildNewsButton_SetText", GuildNewsSetText)
	end

	-- Scrapping machine (if already present).
	local scrapper = _G["ScrappingMachineFrame"]
	if scrapper and scrapper.UpdateScrapButtonState then
		hooksecurefunc(scrapper, "UpdateScrapButtonState", ScrappingSetup)
	end

	-- Wait for load-on-demand UIs we couldn't hook yet (event registered in RegisterModuleEvents).
end

function ItemLevel:RegisterModuleEvents()
	if eventsRegistered then
		return
	end
	eventsRegistered = true
	self:TrackEvent(eventHandles, "PLAYER_EQUIPMENT_CHANGED", "UpdatePlayerSlots")
	self:TrackEvent(eventHandles, "INSPECT_READY", "INSPECT_READY")
	self:TrackEvent(eventHandles, "BANKFRAME_OPENED", "BANKFRAME_OPENED")
	self:TrackEvent(eventHandles, "ADDON_LOADED", "ADDON_LOADED")
end

function ItemLevel:UnregisterModuleEvents()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
end

function ItemLevel:ADDON_LOADED(addon)
	if not IsActive() then
		return
	end
	if addon == "Blizzard_ScrappingMachineUI" then
		local scrapper = _G["ScrappingMachineFrame"]
		if scrapper and scrapper.UpdateScrapButtonState then
			hooksecurefunc(scrapper, "UpdateScrapButtonState", ScrappingSetup)
		end
	elseif addon == "Blizzard_GuildUI" or addon == "Blizzard_Communities" then
		if _G["GuildNewsButton_SetText"] and not self.guildNewsHooked then
			self.guildNewsHooked = true
			hooksecurefunc("GuildNewsButton_SetText", GuildNewsSetText)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function ItemLevel:OnEnable()
	if not ns.db.itemLevel.enable then
		return
	end
	self:InstallHooks()
	self:RegisterModuleEvents()
end

function ItemLevel:OnDisable()
	self:UnregisterModuleEvents()
end

function ItemLevel:OnSettingChanged(key, value)
	if key == "enable" then
		if value then
			self:InstallHooks()
			self:RegisterModuleEvents()
		else
			self:UnregisterModuleEvents()
		end
	end
	if key == "fontSize" then
		ApplyILvlFontSize()
	end
	if key == "showBindText" then
		RefreshBagSlots()
	end
	-- Re-scan the character sheet if it is open so a toggle applies live.
	local CharacterFrame = _G["CharacterFrame"]
	if CharacterFrame and CharacterFrame:IsShown() then
		self:UpdatePlayerSlots()
	end
end

function ItemLevel:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Item Level"], L["Show item levels on equipped, bag, merchant, trade and loot items."])
	builder:Checkbox(category, self, "gemsEnchants", L["Show Gems & Enchants"], L["Also show gem, socket and enchant info on Character and Inspect slots."])
	builder:Checkbox(category, self, "missingEnchant", L["Warn Missing Enchants"], L["Show a red icon on Character and Inspect slots that can be enchanted but aren't."])
	builder:Checkbox(category, self, "showBindText", L["Show Bind Status"], L["Show BoE, BoA and WuE labels on bag and bank items that are not yet bound."])
	builder:Slider(category, self, "fontSize", L["Item Level Font Size"], L["Font size for the item level numbers on equipped, bag, merchant, trade and loot items."], 12, 14, 1)
end
