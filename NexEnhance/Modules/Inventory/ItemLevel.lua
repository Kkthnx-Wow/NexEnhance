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
local strsub = string.sub
local hooksecurefunc = hooksecurefunc
local C_Timer = C_Timer
local C_Item = C_Item
local C_Container = C_Container
local UnitExists = UnitExists
local UnitGUID = UnitGUID
local GetInventoryItemLink = GetInventoryItemLink

local QUALITY_COLORS = _G["ITEM_QUALITY_COLORS"]
local TEX_COORD = { 0.08, 0.92, 0.08, 0.92 }
local FONT = C.Media.Fonts.normal

ns:RegisterDefaults({
	itemLevel = {
		enable = true,
		gemsEnchants = true,
		showBindText = true,
	},
})

local ItemLevel = ns:NewModule("ItemLevel", "itemLevel", { group = "inventory", title = L["Item Level"], order = 20 })

-- Inventory-slot ID -> slot name. The numeric index doubles as the inventory
-- slot id passed to GetInventoryItemLink / C_TooltipInfo.GetInventoryItem.
local inspectSlots = {
	"Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet",
	"Wrist", "Hands", "Finger0", "Finger1", "Trinket0", "Trinket1", "Back",
	"MainHand", "SecondaryHand",
}

-- ---------------------------------------------------------------------------
-- Small widget helpers (kept local: specific to this module's overlays)
-- ---------------------------------------------------------------------------
local function CreateFS(parent, size)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(FONT, size, "OUTLINE")
	fs:SetShadowOffset(1, -1)
	fs:SetWordWrap(false)
	return fs
end

-- A gem/socket icon with a thin 1px border that we toggle with the icon.
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
	bg:Hide()
	icon.bg = bg

	return icon
end

local function GetQualityColor(quality)
	local color = quality and QUALITY_COLORS and QUALITY_COLORS[quality]
	if not color then return 1, 1, 1 end
	return color.r, color.g, color.b
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
	if not index then return "BOTTOMLEFT", 40, 20 end
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

local function ItemString_Expand(self) self:SetWidth(0) end
local function ItemString_Collapse(self) self:SetWidth(100) end

-- ---------------------------------------------------------------------------
-- Per-slot overlay construction (Character / Inspect)
-- ---------------------------------------------------------------------------
function ItemLevel:CreateItemStrings(frame, strType)
	if frame.nexItemStringsDone then return end
	frame.nexItemStringsDone = true

	for index, slot in pairs(inspectSlots) do
		if index ~= 4 then -- skip Shirt
			local slotFrame = _G[strType .. slot .. "Slot"]
			if slotFrame then
				slotFrame.iLvlText = CreateFS(slotFrame, 14)
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
			end
		end
	end
end

function ItemLevel:UpdateSlotInfo(slotFrame, info, quality)
	if not slotFrame or not slotFrame.iLvlText then return end

	local infoType = type(info)
	local level = infoType == "table" and info.iLvl or info

	if level and level > 1 and quality and quality > 1 then
		slotFrame.iLvlText:SetText(level)
		slotFrame.iLvlText:SetTextColor(GetQualityColor(quality))
	end

	if infoType ~= "table" then return end

	local enchant = info.enchantText
	if enchant then
		enchant = enchant:gsub("^.-%s%-%s", "") -- strip any "Source - " prefix
		slotFrame.enchantText:SetText(enchant)
	end

	local gemStep = 1
	for i = 1, 10 do
		local icon = slotFrame["nexGem" .. i]
		local bg = icon.bg
		local gem = info.gems and info.gems[gemStep]
		local color = info.gemsColor and info.gemsColor[gemStep]
		if gem then
			icon:SetTexture(gem)
			if color then
				bg:SetBackdropBorderColor(color.r, color.g, color.b)
			else
				bg:SetBackdropBorderColor(0, 0, 0)
			end
			bg:Show()
			gemStep = gemStep + 1
		else
			icon:SetTexture(nil)
			bg:Hide()
		end
	end
end

function ItemLevel:RefreshSlotInfo(unit, index, slotFrame, fullScan)
	C_Timer.After(0.1, function()
		if not UnitExists(unit) then return end
		local link = GetInventoryItemLink(unit, index)
		if not link then return end
		local quality = select(3, C_Item.GetItemInfo(link))
		local info = F.GetItemLevel(link, unit, index, fullScan)
		self:UpdateSlotInfo(slotFrame, info, quality)
	end)
end

function ItemLevel:SetupSlots(frame, strType, unit)
	if not UnitExists(unit) then return end

	self:CreateItemStrings(frame, strType)
	local fullScan = ns.db.itemLevel.gemsEnchants

	for index, slot in pairs(inspectSlots) do
		if index ~= 4 then
			local slotFrame = _G[strType .. slot .. "Slot"]
			if slotFrame and slotFrame.iLvlText then
				slotFrame.iLvlText:SetText("")
				slotFrame.enchantText:SetText("")
				for i = 1, 10 do
					local icon = slotFrame["nexGem" .. i]
					icon:SetTexture(nil)
					icon.bg:Hide()
				end

				local link = GetInventoryItemLink(unit, index)
				if link then
					local quality = select(3, C_Item.GetItemInfo(link))
					if not quality then
						self:RefreshSlotInfo(unit, index, slotFrame, fullScan)
					else
						local info = F.GetItemLevel(link, unit, index, fullScan)
						self:UpdateSlotInfo(slotFrame, info, quality)
					end
				end
			end
		end
	end
end

function ItemLevel:UpdatePlayerSlots()
	self:SetupSlots(_G["CharacterFrame"], "Character", "player")
end

function ItemLevel:INSPECT_READY(guid)
	local InspectFrame = _G["InspectFrame"]
	if InspectFrame and InspectFrame.unit and UnitGUID(InspectFrame.unit) == guid then
		self:SetupSlots(InspectFrame, "Inspect", InspectFrame.unit)
	end
end

-- ---------------------------------------------------------------------------
-- Generic single-link overlay (flyout / merchant / trade / loot / bags)
-- ---------------------------------------------------------------------------
local function SetSimpleLevel(button, link, quality, bagID, slotID)
	if not button.nexILvl then
		button.nexILvl = CreateFS(button, 14)
		button.nexILvl:SetPoint("BOTTOMLEFT", 1, 1)
	end

	if not link or (quality and quality <= 1) then
		button.nexILvl:SetText("")
		return
	end

	local level = F.GetItemLevel(link, bagID, slotID)
	if level and quality and quality > 1 then
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
	if not button.nexILvl then
		button.nexILvl = CreateFS(button, 14)
		button.nexILvl:SetPoint("BOTTOMLEFT", 1, 1)
	end
	button.nexILvl:SetText("")

	local location = button.location
	if not location then return end

	local EquipmentManager_GetLocationData = _G["EquipmentManager_GetLocationData"]
	local EquipmentManager_GetItemInfoByLocation = _G["EquipmentManager_GetItemInfoByLocation"]
	local special = _G["EQUIPMENTFLYOUT_FIRST_SPECIAL_LOCATION"]

	if type(location) == "number" then
		if special and location >= special then return end
		if not EquipmentManager_GetLocationData then return end

		local locationData = EquipmentManager_GetLocationData(location)
		if not locationData then return end
		local quality = EquipmentManager_GetItemInfoByLocation and select(13, EquipmentManager_GetItemInfoByLocation(location))
		if locationData.isBags then
			SetSimpleLevel(button, C_Container.GetContainerItemLink(locationData.bag, locationData.slot), quality, locationData.bag, locationData.slot)
		else
			SetSimpleLevel(button, GetInventoryItemLink("player", locationData.slot), quality)
		end
	elseif button.GetItemLocation then
		local itemLocation = button:GetItemLocation()
		if not itemLocation then return end
		local quality = C_Item.GetItemQuality(itemLocation)
		if itemLocation:IsBagAndSlot() then
			local bag, slot = itemLocation:GetBagAndSlot()
			SetSimpleLevel(button, C_Container.GetContainerItemLink(bag, slot), quality, bag, slot)
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
	local button = _G[self:GetName() .. "ItemButton"]
	if not button then return end
	local quality = link and select(3, C_Item.GetItemInfo(link))
	SetSimpleLevel(button, link, quality)
end

-- ---------------------------------------------------------------------------
-- Trade
-- ---------------------------------------------------------------------------
local function UpdateTradeItem(prefix, index, link)
	local button = _G[prefix .. index]
	if not button then return end
	local quality = link and select(3, C_Item.GetItemInfo(link))
	SetSimpleLevel(button, link, quality)
end

-- ---------------------------------------------------------------------------
-- Loot
-- ---------------------------------------------------------------------------
function ItemLevel:UpdateLoot()
	local scrollTarget = self.ScrollTarget
	if not scrollTarget then return end

	for i = 1, scrollTarget:GetNumChildren() do
		local button = select(i, scrollTarget:GetChildren())
		-- During the loot frame's hide animation the ScrollBox still runs Update,
		-- but the recycled children have no element data yet (GetElementData is
		-- nil / returns nil), so read the slot index defensively.
		local elementData = button and button.Item and button.GetElementData and button:GetElementData()
		local slotIndex = elementData and elementData.slotIndex
		if slotIndex then
			if not button.nexILvl then
				button.nexILvl = CreateFS(button.Item, 14)
				button.nexILvl:SetPoint("BOTTOMLEFT", 1, 1)
			end
			local quality = select(5, _G.GetLootSlotInfo(slotIndex))
			if quality and quality > 1 then
				local level = F.GetItemLevel(_G.GetLootSlotLink(slotIndex))
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
-- ---------------------------------------------------------------------------
local function UpdateBagSlot(iconBorder)
	local button = iconBorder.nexOwner
	if not button then return end

	if not button.nexILvl then
		button.nexILvl = CreateFS(button, 14)
		button.nexILvl:SetPoint("BOTTOMLEFT", 1, 1)
	end

	local bagID = button.GetBankTabID and button:GetBankTabID() or (button.GetBagID and button:GetBagID())
	local slotID = button.GetContainerSlotID and button:GetContainerSlotID() or button:GetID()
	if not bagID then
		button.nexILvl:SetText("")
		if button.nexBind then button.nexBind:SetText("") end
		return
	end

	local info = C_Container.GetContainerItemInfo(bagID, slotID)
	local quality = info and info.quality
	local link = info and info.hyperlink

	if quality and quality > 1 then
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

local function RefreshBagSlots()
	local function ScanFrame(frame)
		if not frame or not frame.itemButtonPool then return end
		for bagButton in frame.itemButtonPool:EnumerateActive() do
			if bagButton.IconBorder and bagButton.IconBorder.nexOwner then
				UpdateBagSlot(bagButton.IconBorder)
			end
		end
	end
	for i = 1, 13 do
		ScanFrame(_G["ContainerFrame" .. i])
	end
	ScanFrame(_G["ContainerFrameCombinedBags"])
	local bank = _G["BankFrame"]
	if bank and bank.BankPanel then
		ScanFrame(bank.BankPanel)
	end
end

local function HandleBagSlots(frame)
	if not frame.EnumerateValidItems and not frame.itemButtonPool then return end
	local pool = frame.itemButtonPool
	if not pool then return end
	for button in pool:EnumerateActive() do
		if button.IconBorder and not button.nexBagHooked then
			button.IconBorder.nexOwner = button
			hooksecurefunc(button.IconBorder, "SetShown", UpdateBagSlot)
			button.nexBagHooked = true
		end
	end
end

function ItemLevel:HookBags()
	for i = 1, 13 do
		local frame = _G["ContainerFrame" .. i]
		if frame and frame.UpdateItemSlots then
			hooksecurefunc(frame, "UpdateItemSlots", HandleBagSlots)
		end
	end
	local combined = _G["ContainerFrameCombinedBags"]
	if combined and combined.UpdateItemSlots then
		hooksecurefunc(combined, "UpdateItemSlots", HandleBagSlots)
	end
	local bank = _G["BankFrame"]
	if bank and bank.BankPanel and bank.BankPanel.GenerateItemSlotsForSelectedTab then
		hooksecurefunc(bank.BankPanel, "GenerateItemSlotsForSelectedTab", HandleBagSlots)
	end
end

-- ---------------------------------------------------------------------------
-- Scrapping machine (load-on-demand)
-- ---------------------------------------------------------------------------
local function ScrappingButtonUpdate(button)
	if not button.nexILvl then
		button.nexILvl = CreateFS(button, 14)
		button.nexILvl:SetPoint("BOTTOMLEFT", 1, 1)
	end
	if not button.itemLink then button.nexILvl:SetText(""); return end

	local quality = 1
	if button.item and not button.item:IsItemEmpty() and button.item:GetItemName() then
		quality = button.item:GetItemQuality()
	end
	local level = F.GetItemLevel(button.itemLink)
	button.nexILvl:SetText(level)
	button.nexILvl:SetTextColor(GetQualityColor(quality))
end

local function ScrappingSetup(frame)
	if not frame.ItemSlots or not frame.ItemSlots.scrapButtons then return end
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
	if not link then return end
	local modLink = newsCache[link]
	if not modLink then
		local level = F.GetItemLevel(link)
		if level then
			modLink = link:gsub("|h%[(.-)%]|h", "|h(" .. level .. ")" .. name .. "|h")
			newsCache[link] = modLink
		end
	end
	return modLink
end

local function GuildNewsSetText(button)
	if not button.text then return end
	local newText = button.text:GetText()
	if not newText then return end
	newText = newText:gsub("(|Hitem:%d+:.-|h%[(.-)%]|h)", ReplaceNewsLink)
	if newText then button.text:SetText(newText) end
end

-- ---------------------------------------------------------------------------
-- Hook installation
-- ---------------------------------------------------------------------------
function ItemLevel:InstallHooks()
	if self.hooksInstalled then return end
	self.hooksInstalled = true

	-- Character frame.
	local CharacterFrame = _G["CharacterFrame"]
	if CharacterFrame then
		CharacterFrame:HookScript("OnShow", function() self:UpdatePlayerSlots() end)
		self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "UpdatePlayerSlots")
	end

	-- Inspect frame.
	self:RegisterEvent("INSPECT_READY")

	-- Equipment flyout.
	if _G["EquipmentFlyout_UpdateItems"] then
		hooksecurefunc("EquipmentFlyout_UpdateItems", function()
			local flyout = _G["EquipmentFlyoutFrame"]
			if not flyout or not flyout.buttons then return end
			for _, button in pairs(flyout.buttons) do
				if button:IsShown() then self:FlyoutButton(button) end
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

	-- Bags & bank.
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

	-- Wait for load-on-demand UIs we couldn't hook yet.
	self:RegisterEvent("ADDON_LOADED")
end

function ItemLevel:ADDON_LOADED(addon)
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
	self:InstallHooks()
end

function ItemLevel:OnSettingChanged(key, value)
	if key == "enable" and value then
		self:InstallHooks()
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
	builder:Checkbox(category, self, "showBindText", L["Show Bind Status"], L["Show BoE, BoA and WuE labels on bag and bank items that are not yet bound."])
end
