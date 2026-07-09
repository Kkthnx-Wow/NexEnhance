--[[
	NexEnhance - Already Known
	-------------------------------------------------------------------------
	Tints items you already know a soft green so you can skip re-buying them.
	Covers recipes, pets, toys/mounts and cosmetics across:
	  * the Merchant frame (and its Buyback tab)
	  * the Auction House browse results
	  * the Guild Bank
	  * housing decor items
--]]

-- luacheck: globals MerchantFrame MERCHANT_ITEMS_PER_PAGE BUYBACK_ITEMS_PER_PAGE AuctionHouseFrame GuildBankFrame MAX_GUILDBANK_SLOTS_PER_TAB NUM_SLOTS_PER_GUILDBANK_GROUP SetItemButtonTextureVertexColor COLLECTED ITEM_SPELL_KNOWN
---@diagnostic disable: undefined-field, redundant-parameter, param-type-mismatch
local _, ns = ...
local F, L = ns.F, ns.L

local _G = _G
local select, tonumber, pcall = select, tonumber, pcall
local strmatch, strfind, format = string.match, string.find, string.format
local ceil = math.ceil

local C_AddOns = C_AddOns
local C_Timer = C_Timer
local SetItemButtonTextureVertexColor = SetItemButtonTextureVertexColor
local GetMerchantNumItems, GetMerchantItemLink = GetMerchantNumItems, GetMerchantItemLink
local GetNumBuybackItems, GetBuybackItemInfo, GetBuybackItemLink = GetNumBuybackItems, GetBuybackItemInfo, GetBuybackItemLink
local GetCurrentGuildBankTab, GetGuildBankItemInfo, GetGuildBankItemLink = GetCurrentGuildBankTab, GetGuildBankItemInfo, GetGuildBankItemLink
local C_MerchantFrame_GetItemInfo = C_MerchantFrame.GetItemInfo
local C_Item_GetItemInfo = C_Item.GetItemInfo
local C_Item_IsCosmeticItem = C_Item.IsCosmeticItem
local C_TooltipInfo_GetHyperlink = C_TooltipInfo.GetHyperlink
local C_TooltipInfo_GetGuildBankItem = C_TooltipInfo.GetGuildBankItem
local C_PetJournal_GetNumCollectedInfo = C_PetJournal.GetNumCollectedInfo
local C_TransmogCollection_GetItemInfo = C_TransmogCollection and C_TransmogCollection.GetItemInfo
local C_TransmogCollection_PlayerHasTransmogItemModifiedAppearance = C_TransmogCollection and C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance
local C_HousingCatalog = _G.C_HousingCatalog
local C_HousingCatalog_GetCatalogEntryInfoByItem = C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem
local C_HousingCatalog_GetCatalogEntryInfo = C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfo
local C_HousingCatalog_GetDecorTotalOwnedCount = C_HousingCatalog and C_HousingCatalog.GetDecorTotalOwnedCount
local C_HousingCatalog_RequestHousingMarketInfoRefresh = C_HousingCatalog and C_HousingCatalog.RequestHousingMarketInfoRefresh
local C_HousingCatalog_SearchCatalogCategories = C_HousingCatalog and C_HousingCatalog.SearchCatalogCategories
local C_HousingCatalog_SearchCatalogSubcategories = C_HousingCatalog and C_HousingCatalog.SearchCatalogSubcategories

local MERCHANT_ITEMS_PER_PAGE = _G.MERCHANT_ITEMS_PER_PAGE or 10
local BUYBACK_ITEMS_PER_PAGE = _G.BUYBACK_ITEMS_PER_PAGE or 12
local MAX_GUILDBANK_SLOTS_PER_TAB = _G.MAX_GUILDBANK_SLOTS_PER_TAB or 98
local NUM_SLOTS_PER_GUILDBANK_GROUP = _G.NUM_SLOTS_PER_GUILDBANK_GROUP or 14
local COLLECTED = _G.COLLECTED
local ITEM_SPELL_KNOWN = _G.ITEM_SPELL_KNOWN

local COLOR = { r = 0.1, g = 1, b = 0.1 }
local HOUSING_WARMUP_SEARCH_OPTIONS = { withOwnedEntriesOnly = true, includeFeaturedCategory = false }

-- Housing catalog "owned stack" subtypes (a record you actually own).
local OWNED_MODIFIED_STACK, OWNED_UNMODIFIED_STACK
do
	local sub = Enum and Enum.HousingCatalogEntrySubtype
	if sub then
		OWNED_MODIFIED_STACK = sub.OwnedModifiedStack
		OWNED_UNMODIFIED_STACK = sub.OwnedUnmodifiedStack
	end
end

-- Item classes whose "known" state is worth checking via a tooltip scan.
local knowables = {
	[Enum.ItemClass.Consumable] = true,
	[Enum.ItemClass.Recipe] = true,
	[Enum.ItemClass.Miscellaneous] = true,
	[Enum.ItemClass.ItemEnhancement] = true,
}

-- Memoise links we have already proven known (cheap to keep for the session).
local knowns = {}

ns:RegisterDefaults({
	alreadyKnown = {
		enable = true,
	},
})

local AlreadyKnown = ns:NewModule("AlreadyKnown", "alreadyKnown", { group = "inventory", title = L["Already Known"], order = 40 })

local eventHandles = {}
local eventsRegistered = false
local merchantHooksInstalled = false

-- Forward declaration: IsAlreadyKnown's item-data callback runs after load.
local RefreshVisibleItems

-- ---------------------------------------------------------------------------
-- Detection
-- ---------------------------------------------------------------------------
local function IsPetCollected(speciesID)
	if not speciesID or speciesID == 0 then
		return
	end
	local numOwned = C_PetJournal_GetNumCollectedInfo(speciesID)
	return numOwned and numOwned > 0
end

-- Cosmetic / transmog appearances don't report "known" through the tooltip
-- COLLECTED / ITEM_SPELL_KNOWN lines, so resolve the item's transmog source and
-- ask the collection directly. Source-based (not PlayerHasTransmogByItemInfo,
-- which over-claims for items with link variants). Returns:
--   true / false  - appearance resolved and (un)collected
--   nil           - no transmog source (not an appearance, or data not cached
--                   yet) so the caller should fall back to the tooltip scan.
local function IsCosmeticCollected(link)
	if not (C_TransmogCollection_GetItemInfo and C_TransmogCollection_PlayerHasTransmogItemModifiedAppearance) then
		return
	end
	local _, sourceID = C_TransmogCollection_GetItemInfo(link)
	if sourceID and sourceID ~= 0 then
		return C_TransmogCollection_PlayerHasTransmogItemModifiedAppearance(sourceID) and true or false
	end
end

-- True when a housing catalog entry represents something the player owns:
-- stored copies (totalNumStored), placed copies (totalNumPlaced), unredeemed
-- copies (remainingRedeemable), or an "owned stack" subtype. Falls back to
-- deprecated quantity/numPlaced when Blizzard's compat bridge isn't loaded.
local function OwnedCount(info, primaryField, legacyField)
	local v = info[primaryField]
	if v == nil then
		v = info[legacyField]
	end
	return F.NotSecret(v) and v > 0
end

local function EntryInfoOwned(info)
	if not info then
		return false
	end
	if OwnedCount(info, "totalNumStored", "quantity") or OwnedCount(info, "totalNumPlaced", "numPlaced") or (F.NotSecret(info.remainingRedeemable) and info.remainingRedeemable > 0) then
		return true
	end

	local entryID = info.entryID
	if entryID and (entryID.entrySubtype == OWNED_MODIFIED_STACK or entryID.entrySubtype == OWNED_UNMODIFIED_STACK) then
		return true
	end

	return false
end

-- Reused so the owned-stack re-query below doesn't allocate per item/subtype.
local entryQuery = {}

local function QueryOwnedEntryInfo(entryType, recordID, subtype)
	if not subtype then
		return false
	end

	entryQuery.entryType = entryType
	entryQuery.entrySubtype = subtype
	entryQuery.recordID = recordID
	entryQuery.subtypeIdentifier = 0
	return EntryInfoOwned(C_HousingCatalog_GetCatalogEntryInfo(entryQuery))
end

-- Housing decor items have a collection state separate from recipes/toys and
-- transmog, so ask the Midnight housing catalog. The by-item lookup frequently
-- returns the *Unowned* catalog entry (zero counts) even for decor you own, so
-- when that happens re-query the owned stacks (subtypeIdentifier 0) directly to
-- confirm ownership. Mirrors CaerdonWardrobe's HousingMixin. Returns:
--   true / false - resolved as a housing entry and (un)owned
--   nil          - not a housing catalog item, fall back to other checks.
local function IsDecorCollected(link)
	if not C_HousingCatalog_GetCatalogEntryInfoByItem then
		return
	end

	local info = C_HousingCatalog_GetCatalogEntryInfoByItem(link)
	if not info then
		return
	end

	if EntryInfoOwned(info) then
		return true
	end

	local entryID = info.entryID
	if entryID and C_HousingCatalog_GetCatalogEntryInfo then
		local entryType, recordID = entryID.entryType, entryID.recordID
		if entryType and recordID then
			if QueryOwnedEntryInfo(entryType, recordID, OWNED_UNMODIFIED_STACK) or QueryOwnedEntryInfo(entryType, recordID, OWNED_MODIFIED_STACK) then
				return true
			end
		end
	end

	return false
end

local function IsAlreadyKnown(link, index)
	if not link then
		return
	end

	local linkType, linkID = strmatch(link, "|H(%a+):(%d+)")
	linkID = tonumber(linkID)

	if linkType == "battlepet" then
		return IsPetCollected(linkID)
	elseif linkType == "item" then
		local name, _, _, _, _, _, _, _, _, _, _, itemClassID = C_Item_GetItemInfo(link)
		if not name then
			if linkID and ns.RequestItemData then
				ns:RequestItemData(linkID, function(success)
					if success == false or not ns.db.alreadyKnown.enable then
						return
					end
					RefreshVisibleItems()
				end)
			end
			return
		end

		if knowns[link] then
			return true
		end

		local decorCollected = IsDecorCollected(link)
		if decorCollected ~= nil then
			if decorCollected then
				F.CacheSet(knowns, link, true)
			end
			return decorCollected
		end

		-- Caged battle pets in the guild bank carry their species in tooltip data.
		if itemClassID == Enum.ItemClass.Battlepet and index then
			local data = C_TooltipInfo_GetGuildBankItem(GetCurrentGuildBankTab(), index)
			if data then
				return data.battlePetSpeciesID and IsPetCollected(data.battlePetSpeciesID)
			end
			return
		end

		-- Cosmetics / transmog: ask the appearance collection directly; only
		-- fall back to the tooltip scan if the source can't be resolved.
		if C_Item_IsCosmeticItem(link) then
			local collected = IsCosmeticCollected(link)
			if collected ~= nil then
				if collected then
					F.CacheSet(knowns, link, true)
				end
				return collected
			end
		end

		if not knowables[itemClassID] and not C_Item_IsCosmeticItem(link) then
			return
		end

		local data = C_TooltipInfo_GetHyperlink(link, nil, nil, true)
		if data then
			for i = 1, #data.lines do
				local lineData = data.lines[i]
				local text = lineData and lineData.leftText
				if text and ((COLLECTED and strfind(text, COLLECTED)) or text == ITEM_SPELL_KNOWN) then
					F.CacheSet(knowns, link, true)
					return true
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Merchant frame
-- ---------------------------------------------------------------------------
local function UpdateMerchantInfo()
	local numItems = GetMerchantNumItems()
	for i = 1, MERCHANT_ITEMS_PER_PAGE do
		local index = (MerchantFrame.page - 1) * MERCHANT_ITEMS_PER_PAGE + i
		if index > numItems then
			return
		end

		local button = _G["MerchantItem" .. i .. "ItemButton"]
		if button and button:IsShown() then
			local info = C_MerchantFrame_GetItemInfo(index)
			local numAvailable = info and info.numAvailable
			local isUsable = info and info.isUsable
			if isUsable and IsAlreadyKnown(GetMerchantItemLink(index)) then
				local r, g, b = COLOR.r, COLOR.g, COLOR.b
				if numAvailable and F.NotSecret(numAvailable) and numAvailable == 0 then
					r, g, b = r * 0.5, g * 0.5, b * 0.5
				end
				SetItemButtonTextureVertexColor(button, r, g, b)
			end
		end
	end
end

local function UpdateBuybackInfo()
	local numItems = GetNumBuybackItems()
	for index = 1, BUYBACK_ITEMS_PER_PAGE do
		if index > numItems then
			return
		end

		local button = _G["MerchantItem" .. index .. "ItemButton"]
		if button and button:IsShown() then
			local isUsable = select(6, GetBuybackItemInfo(index))
			if isUsable and IsAlreadyKnown(GetBuybackItemLink(index)) then
				SetItemButtonTextureVertexColor(button, COLOR.r, COLOR.g, COLOR.b)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Auction House (load-on-demand)
-- ---------------------------------------------------------------------------
local function UpdateAuctionItems(self)
	for i = 1, self.ScrollTarget:GetNumChildren() do
		local child = select(i, self.ScrollTarget:GetChildren())
		if child.cells then
			local button = child.cells[2]
			local itemKey = button and button.rowData and button.rowData.itemKey
			if itemKey and itemKey.itemID then
				local itemLink
				if itemKey.itemID == 82800 then -- "Pet Cage"
					itemLink = format("|Hbattlepet:%d::::::|h[Dummy]|h", itemKey.battlePetSpeciesID)
				else
					itemLink = format("|Hitem:%d", itemKey.itemID)
				end

				if itemLink and IsAlreadyKnown(itemLink) then
					child.SelectedHighlight:Show()
					child.SelectedHighlight:SetVertexColor(COLOR.r, COLOR.g, COLOR.b)
					child.SelectedHighlight:SetAlpha(0.25)
					button.Icon:SetVertexColor(COLOR.r, COLOR.g, COLOR.b)
					button.IconBorder:SetVertexColor(COLOR.r, COLOR.g, COLOR.b)
				else
					child.SelectedHighlight:SetVertexColor(1, 1, 1)
					button.Icon:SetVertexColor(1, 1, 1)
					button.IconBorder:SetVertexColor(1, 1, 1)
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Guild Bank (load-on-demand)
-- ---------------------------------------------------------------------------
local function GuildBankFrame_Update(self)
	if self.mode ~= "bank" then
		return
	end

	local tab = GetCurrentGuildBankTab()
	for i = 1, MAX_GUILDBANK_SLOTS_PER_TAB do
		local index = i % NUM_SLOTS_PER_GUILDBANK_GROUP
		if index == 0 then
			index = NUM_SLOTS_PER_GUILDBANK_GROUP
		end

		local column = ceil((i - 0.5) / NUM_SLOTS_PER_GUILDBANK_GROUP)
		local button = self.Columns[column].Buttons[index]
		if button and button:IsShown() then
			local texture, _, locked = GetGuildBankItemInfo(tab, i)
			if texture and not locked then
				if IsAlreadyKnown(GetGuildBankItemLink(tab, i), i) then
					SetItemButtonTextureVertexColor(button, COLOR.r, COLOR.g, COLOR.b)
				else
					SetItemButtonTextureVertexColor(button, 1, 1, 1)
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Housing data warmup
-- ---------------------------------------------------------------------------
function RefreshVisibleItems()
	if MerchantFrame and MerchantFrame:IsShown() then
		UpdateMerchantInfo()
		UpdateBuybackInfo()
	end

	local list = AuctionHouseFrame and AuctionHouseFrame:IsShown() and AuctionHouseFrame.BrowseResultsFrame and AuctionHouseFrame.BrowseResultsFrame.ItemList
	if list and list.ScrollBox and list.ScrollBox.ScrollTarget then
		UpdateAuctionItems(list.ScrollBox)
	end

	if GuildBankFrame and GuildBankFrame:IsShown() then
		GuildBankFrame_Update(GuildBankFrame)
	end
end

function AlreadyKnown:WarmHousingData()
	if self.housingWarmed or not C_HousingCatalog_GetCatalogEntryInfoByItem then
		return
	end

	-- Blizzard lazy-loads owned decor counts; opening the catalog does this too.
	if C_AddOns and C_AddOns.LoadAddOn then
		pcall(C_AddOns.LoadAddOn, "Blizzard_HousingEventHandler")
	elseif _G.LoadAddOn then
		pcall(_G.LoadAddOn, "Blizzard_HousingEventHandler")
	end

	if C_HousingCatalog_RequestHousingMarketInfoRefresh then
		pcall(C_HousingCatalog_RequestHousingMarketInfoRefresh)
	end
	if C_HousingCatalog_GetDecorTotalOwnedCount then
		pcall(C_HousingCatalog_GetDecorTotalOwnedCount)
	end
	if C_HousingCatalog_SearchCatalogCategories then
		pcall(C_HousingCatalog_SearchCatalogCategories, HOUSING_WARMUP_SEARCH_OPTIONS)
	end
	if C_HousingCatalog_SearchCatalogSubcategories then
		pcall(C_HousingCatalog_SearchCatalogSubcategories, HOUSING_WARMUP_SEARCH_OPTIONS)
	end

	self.housingWarmed = true
end

local function FlushHousingRefresh()
	AlreadyKnown.housingRefreshQueued = false
	RefreshVisibleItems()
end

function AlreadyKnown:RefreshHousingItems()
	if self.housingRefreshQueued then
		return
	end
	self.housingRefreshQueued = true
	if C_Timer then
		C_Timer.After(0.1, FlushHousingRefresh)
	else
		FlushHousingRefresh()
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function AlreadyKnown:HookAuctionHouse()
	if self.auctionHooked then
		return
	end
	local list = AuctionHouseFrame and AuctionHouseFrame.BrowseResultsFrame and AuctionHouseFrame.BrowseResultsFrame.ItemList
	if list and list.ScrollBox then
		hooksecurefunc(list.ScrollBox, "Update", UpdateAuctionItems)
		self.auctionHooked = true
	end
end

function AlreadyKnown:HookGuildBank()
	if self.guildBankHooked then
		return
	end
	if GuildBankFrame then
		hooksecurefunc(GuildBankFrame, "Update", GuildBankFrame_Update)
		self.guildBankHooked = true
	end
end

function AlreadyKnown:ADDON_LOADED(addon)
	if addon == "Blizzard_AuctionHouseUI" then
		self:HookAuctionHouse()
	elseif addon == "Blizzard_GuildBankUI" then
		self:HookGuildBank()
	end
end

function AlreadyKnown:HOUSING_MARKET_AVAILABILITY_UPDATED()
	self:RefreshHousingItems()
end

function AlreadyKnown:HOUSING_STORAGE_UPDATED()
	self:RefreshHousingItems()
end

function AlreadyKnown:HOUSING_STORAGE_ENTRY_UPDATED()
	self:RefreshHousingItems()
end

function AlreadyKnown:HOUSE_DECOR_ADDED_TO_CHEST()
	self:RefreshHousingItems()
end

function AlreadyKnown:RegisterModuleEvents()
	if eventsRegistered then
		return
	end
	eventsRegistered = true

	if not (self.auctionHooked and self.guildBankHooked) then
		self:TrackEvent(eventHandles, "ADDON_LOADED")
	end

	if C_HousingCatalog_GetCatalogEntryInfoByItem then
		self:TrackEvent(eventHandles, "HOUSING_MARKET_AVAILABILITY_UPDATED")
		self:TrackEvent(eventHandles, "HOUSING_STORAGE_UPDATED")
		self:TrackEvent(eventHandles, "HOUSING_STORAGE_ENTRY_UPDATED")
		self:TrackEvent(eventHandles, "HOUSE_DECOR_ADDED_TO_CHEST")
	end
end

function AlreadyKnown:UnregisterModuleEvents()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
end

function AlreadyKnown:OnEnable()
	if not ns.db.alreadyKnown.enable then
		return
	end

	-- Merchant + Buyback live in base FrameXML, so hook straight away.
	if not merchantHooksInstalled then
		merchantHooksInstalled = true
		hooksecurefunc("MerchantFrame_UpdateMerchantInfo", UpdateMerchantInfo)
		hooksecurefunc("MerchantFrame_UpdateBuybackInfo", UpdateBuybackInfo)
	end

	-- The AH and Guild Bank are load-on-demand; hook now if present, else wait.
	if C_AddOns.IsAddOnLoaded("Blizzard_AuctionHouseUI") then
		self:HookAuctionHouse()
	end
	if C_AddOns.IsAddOnLoaded("Blizzard_GuildBankUI") then
		self:HookGuildBank()
	end

	if C_HousingCatalog_GetCatalogEntryInfoByItem then
		self:WarmHousingData()
	end

	self:RegisterModuleEvents()
end

function AlreadyKnown:OnDisable()
	self:UnregisterModuleEvents()
end

function AlreadyKnown:OnSettingChanged(key, value)
	-- ApplyModuleSetting owns enable lifecycle.
	if key == "enable" then
		return
	end
end

function AlreadyKnown:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Already Known"], L["Tint already-known recipes, pets, toys, cosmetics and housing decor green at vendors, the Auction House and Guild Bank (reload to disable)."])
end
