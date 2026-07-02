--[[
	NexEnhance - Delete Cheapest
	-------------------------------------------------------------------------
	Adds a small button to the bag frame (just left of Blizzard's bag sort
	button) that finds and destroys the cheapest vendor-sellable item in your
	bags - a quick way to free a slot when you're full and the nearest vendor
	is far away.

	  * Left-click  : find the cheapest sellable item and prompt to delete it.
	  * Right-click : just report the cheapest item in chat (no deletion).

	"Cheapest" is the lowest total vendor value (unit sell price x stack count).
	Items with no sell value (most quest items, soulbound junk, etc.) are
	skipped outright, and optional per-item-class filters let you protect whole
	categories (quest items are protected by default).

	The concept is borrowed from Hydra's "DeleteCheapest" snippet, rebuilt from
	scratch for the NexEnhance module/options architecture.

	Midnight note: vendor sell price comes from C_Item.GetItemInfo (static item
	data, never Secret), but a bag slot's stack count can be Secret in combat,
	so we gate that read with F.IsSecret and fall back to treating it as a
	single item rather than performing arithmetic on a Secret.
--]]

-- luacheck: read_globals C_Container C_Item Enum NUM_BAG_SLOTS BACKPACK_CONTAINER BagItemAutoSortButton DeleteCursorItem
---@diagnostic disable: undefined-global, undefined-field
local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local select = select
local unpack = unpack
local format = string.format
local CreateFrame = CreateFrame

local C_Container = C_Container
local C_Container_GetContainerNumSlots = C_Container.GetContainerNumSlots
local C_Container_GetContainerItemInfo = C_Container.GetContainerItemInfo
local C_Container_PickupContainerItem = C_Container.PickupContainerItem
local C_Item_GetItemInfo = C_Item.GetItemInfo
local DeleteCursorItem = DeleteCursorItem
local GameTooltip = GameTooltip
local StaticPopupDialogs = StaticPopupDialogs
local StaticPopup_Show = StaticPopup_Show

local BACKPACK_CONTAINER = BACKPACK_CONTAINER
local NUM_BAG_SLOTS = NUM_BAG_SLOTS

-- Item-class IDs (Enum.ItemClass) -> the setting that protects that class.
local FILTER_KEYS = {
	[Enum.ItemClass.Consumable] = "filterConsumable",
	[Enum.ItemClass.Container] = "filterContainer",
	[Enum.ItemClass.Weapon] = "filterWeapon",
	[Enum.ItemClass.Armor] = "filterArmor",
	[Enum.ItemClass.Reagent] = "filterReagent",
	[Enum.ItemClass.Tradegoods] = "filterTradeskill",
	[Enum.ItemClass.Questitem] = "filterQuest",
}

ns:RegisterDefaults({
	deleteCheapest = {
		enable = true,
		filterConsumable = false,
		filterContainer = false,
		filterWeapon = false,
		filterArmor = false,
		filterReagent = false,
		filterTradeskill = false,
		filterQuest = true,
	},
})

local DeleteCheapest = ns:NewModule("DeleteCheapest", "deleteCheapest", { group = "inventory", title = L["Delete Cheapest"], order = 60 })

local eventHandles = {}
local eventsRegistered = false

local function ItemIDFromLink(link)
	return link and tonumber(link:match("item:(%d+)"))
end

-- ---------------------------------------------------------------------------
-- Scan
-- ---------------------------------------------------------------------------
-- True when the item's class is excluded by the user's protection filters.
local function IsFiltered(link)
	local classID = select(12, C_Item_GetItemInfo(link))
	if not classID then
		local itemID = ItemIDFromLink(link)
		if itemID and ns.RequestItemData then
			ns:RequestItemData(itemID, function() end)
		end
		return false
	end
	local key = FILTER_KEYS[classID]
	return key ~= nil and ns.db.deleteCheapest[key]
end

-- Walk every carried bag and return the slot with the lowest total vendor
-- value. Returns link, value, count, bag, slot (or nil when nothing qualifies).
local function FindCheapest()
	local bestLink, bestValue, bestCount, bestBag, bestSlot

	for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
		for slot = 1, C_Container_GetContainerNumSlots(bag) do
			local info = C_Container_GetContainerItemInfo(bag, slot)
			if info and not info.hasNoValue and info.hyperlink then
				local sellPrice = select(11, C_Item_GetItemInfo(info.hyperlink))
				if not sellPrice then
					local itemID = ItemIDFromLink(info.hyperlink)
					if itemID and ns.RequestItemData then
						ns:RequestItemData(itemID, function() end)
					end
				end
				-- sellPrice is static item data (not Secret); guard anyway.
				if sellPrice and F.NotSecret(sellPrice) and sellPrice > 0 and not IsFiltered(info.hyperlink) then
					-- Stack count can be Secret in combat; only multiply when
					-- it is a plain number, otherwise price the single item.
					local count = info.stackCount
					local total = sellPrice
					if count and F.NotSecret(count) and count > 1 then
						total = sellPrice * count
					else
						count = 1
					end

					if not bestValue or total < bestValue then
						bestLink, bestValue, bestCount, bestBag, bestSlot = info.hyperlink, total, count, bag, slot
					end
				end
			end
		end
	end

	return bestLink, bestValue, bestCount, bestBag, bestSlot
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------
local function ReportCheapest()
	local link, value, count = FindCheapest()
	if not (link and value) then
		F.Print(L["No sellable items were found in your bags."])
		return
	end
	if count and count > 1 then
		F.Print(format(L["Cheapest item: %s x%d, worth %s."], link, count, F.FormatMoney(value)))
	else
		F.Print(format(L["Cheapest item: %s, worth %s."], link, F.FormatMoney(value)))
	end
end

StaticPopupDialogs["NEXENHANCE_DELETE_CHEAPEST"] = {
	text = L["Delete the cheapest item in your bags?"] .. "|n|n%s",
	button1 = _G.YES,
	button2 = _G.NO,
	OnAccept = function(_, data)
		if not (data and data.bag and data.slot) then
			return
		end
		-- Re-verify the slot still holds the same item before destroying it, so
		-- a bag shuffle between prompt and confirm can't delete the wrong thing.
		local info = C_Container_GetContainerItemInfo(data.bag, data.slot)
		if not info or info.hyperlink ~= data.link then
			F.Print(L["The item moved before it could be deleted - nothing was destroyed."])
			return
		end
		C_Container_PickupContainerItem(data.bag, data.slot)
		DeleteCursorItem()
		if data.count and data.count > 1 then
			F.Print(format(L["Deleted %s x%d, worth %s."], data.link, data.count, F.FormatMoney(data.value)))
		else
			F.Print(format(L["Deleted %s, worth %s."], data.link, F.FormatMoney(data.value)))
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	showAlert = true,
	preferredIndex = 3,
}

local function PromptDeleteCheapest()
	local link, value, count, bag, slot = FindCheapest()
	if not (link and bag and slot) then
		F.Print(L["No sellable items were found in your bags."])
		return
	end

	-- The item link (text_arg1 -> %s in the dialog text) renders as the usual
	-- clickable, quality-coloured link, so the player sees what's at stake.
	StaticPopup_Show("NEXENHANCE_DELETE_CHEAPEST", link, nil, { link = link, value = value, count = count, bag = bag, slot = slot })
end

-- ---------------------------------------------------------------------------
-- Bag button
-- ---------------------------------------------------------------------------
-- Parented to BagItemSearchBox, which Blizzard reparents to whichever bag frame
-- is active (combined bags or the standalone backpack), so our button follows
-- it for both layouts and shows/hides with the bags automatically. It sits just
-- off the left edge of the search box - the opposite side from Blizzard's
-- cleanup/sort button, which lives to the right of the search box.
local GOBLIN_ICON = 463874 -- Achievement_GoblinHead: goblins hoard, we purge.

-- Modern square push-button frame (normal / pressed / hover). We probe it at
-- runtime and only use it when registered in-game, otherwise we fall back to a
-- flat icon button so we never end up with an invisible button.
local BUTTON_ATLAS = {
	normal = "common-button-tertiary-square-normal",
	pushed = "common-button-tertiary-square-pressed",
	hover = "common-button-tertiary-square-hover",
}

local C_Texture = _G.C_Texture
local function AtlasOK(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local button

local function Button_OnEnter(self)
	-- Match Blizzard's "Clean Up Bags" tooltip: a white title over a gold,
	-- word-wrapped description (no blank spacer lines).
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(L["Delete Cheapest Item"], 1, 1, 1)
	GameTooltip:AddLine(L["Left-click: destroy the cheapest sellable item in your bags."], 1, 0.82, 0, true)
	GameTooltip:AddLine(L["Right-click: show the cheapest item without deleting it."], 1, 0.82, 0, true)
	GameTooltip:Show()
end

local function Button_OnLeave()
	GameTooltip:Hide()
end

local function Button_OnClick(_, mouseButton)
	if mouseButton == "RightButton" then
		ReportCheapest()
	else
		PromptDeleteCheapest()
	end
end

local function CreateButton()
	if button then
		return
	end
	local searchBox = _G["BagItemSearchBox"]
	if not searchBox then
		return
	end

	button = CreateFrame("Button", "NexEnhanceDeleteCheapestButton", searchBox)
	button:SetSize(26, 24)
	button:SetPoint("TOPLEFT", searchBox, "TOPLEFT", -34, 1)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	if AtlasOK(BUTTON_ATLAS.normal) then
		-- Real square push-button frame with the goblin face inset on top.
		button:SetNormalAtlas(BUTTON_ATLAS.normal)
		if AtlasOK(BUTTON_ATLAS.pushed) then
			button:SetPushedAtlas(BUTTON_ATLAS.pushed)
		end
		if AtlasOK(BUTTON_ATLAS.hover) then
			button:SetHighlightAtlas(BUTTON_ATLAS.hover)
		end

		-- OVERLAY (above the BORDER/ARTWORK button-frame atlas, below the
		-- HIGHLIGHT glow) so the face is never painted over by the frame art.
		local icon = button:CreateTexture(nil, "OVERLAY")
		local function PlaceIcon(dx, dy)
			icon:ClearAllPoints()
			icon:SetPoint("TOPLEFT", 4 + dx, -4 + dy)
			icon:SetPoint("BOTTOMRIGHT", -4 + dx, 4 + dy)
		end
		PlaceIcon(0, 0)
		icon:SetTexture(GOBLIN_ICON)
		icon:SetTexCoord(unpack(C.TexCoord))
		button.icon = icon

		-- Translate the face 1px down-right while pressed so it tracks the frame.
		button:SetScript("OnMouseDown", function()
			PlaceIcon(1, -1)
		end)
		button:SetScript("OnMouseUp", function()
			PlaceIcon(0, 0)
		end)
	else
		-- Fallback: flat icon button (icon doubles as the face), square glow.
		button:SetNormalTexture(GOBLIN_ICON)
		local normal = button:GetNormalTexture()
		if normal then
			normal:SetTexCoord(unpack(C.TexCoord))
		end

		button:SetPushedTexture(GOBLIN_ICON)
		local pushed = button:GetPushedTexture()
		if pushed then
			pushed:SetTexCoord(unpack(C.TexCoord))
			pushed:SetVertexColor(0.8, 0.8, 0.8)
		end

		button:SetHighlightTexture([[Interface\Buttons\ButtonHilight-Square]], "ADD")
	end

	button:SetScript("OnEnter", Button_OnEnter)
	button:SetScript("OnLeave", Button_OnLeave)
	button:SetScript("OnClick", Button_OnClick)

	-- A tiny goblin face that quietly destroys gear is exactly the kind of
	-- button people either never notice or panic-click. Point it out once, on
	-- top so the bubble never lands on the bag grid below.
	button:HookScript("OnShow", function(self)
		local point = HelpTip and HelpTip.Point and HelpTip.Point.TopEdgeCenter
		F.ShowHelpTip(self, "DeleteCheapest", L["DeleteCheapestHelpTip"], { targetPoint = point })
	end)
end

-- ---------------------------------------------------------------------------
-- Options & lifecycle
-- ---------------------------------------------------------------------------
function DeleteCheapest:OnSettingChanged(key, value)
	if key ~= "enable" then
		return
	end
	if value then
		self:OnEnable()
	else
		self:OnDisable()
	end
end

function DeleteCheapest:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Delete Cheapest"], L["Add a button to the bag frame that finds and deletes the cheapest sellable item. Left-click to delete (with a confirmation), right-click to preview."])

	builder:Header(L["Protected Item Types"])
	local _, consumableInit = builder:Checkbox(category, self, "filterConsumable", L["Protect Consumables"], L["Never offer to delete consumable items."])
	local _, containerInit = builder:Checkbox(category, self, "filterContainer", L["Protect Containers"], L["Never offer to delete bags and other containers."])
	local _, weaponInit = builder:Checkbox(category, self, "filterWeapon", L["Protect Weapons"], L["Never offer to delete weapons."])
	local _, armorInit = builder:Checkbox(category, self, "filterArmor", L["Protect Armor"], L["Never offer to delete armor."])
	local _, reagentInit = builder:Checkbox(category, self, "filterReagent", L["Protect Reagents"], L["Never offer to delete reagents."])
	local _, tradeskillInit = builder:Checkbox(category, self, "filterTradeskill", L["Protect Trade Goods"], L["Never offer to delete trade goods / crafting materials."])
	local _, questInit = builder:Checkbox(category, self, "filterQuest", L["Protect Quest Items"], L["Never offer to delete quest items."])

	builder:DependsOn(consumableInit, enableInit)
	builder:DependsOn(containerInit, enableInit)
	builder:DependsOn(weaponInit, enableInit)
	builder:DependsOn(armorInit, enableInit)
	builder:DependsOn(reagentInit, enableInit)
	builder:DependsOn(tradeskillInit, enableInit)
	builder:DependsOn(questInit, enableInit)
end

-- Retry hook for the rare case the sort button isn't up yet (load order /
-- bag-replacement addons). Once the button exists this is a cheap no-op, so
-- there's no need to tear the registration down.
function DeleteCheapest:BAG_UPDATE_DELAYED()
	CreateButton()
end

function DeleteCheapest:OnEnable()
	if not ns.db.deleteCheapest.enable then
		return
	end
	CreateButton()
	if button then
		button:Show()
		return
	end
	if not eventsRegistered then
		eventsRegistered = true
		self:TrackEvent(eventHandles, "BAG_UPDATE_DELAYED")
	end
end

function DeleteCheapest:OnDisable()
	ns:UnregisterModuleEventHandles(eventHandles)
	eventsRegistered = false
	if button then
		button:Hide()
	end
end
