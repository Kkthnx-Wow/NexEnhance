--[[
	NexEnhance - Unusable Items
	-------------------------------------------------------------------------
	Tints bag and bank item icons red when your class can't use them (wrong
	weapon/armor type or off-hand dual-wield restriction) or you're below the
	required level - the same cue Blizzard uses on unusable equipment.

	Class-restriction data from LibUnfit-1.0, embedded inline (no LibStub).
	Resolved to the player's class once at login; per-itemID cache for repeats.
	Class/level item data is never secret on 12.0.

	Coverage follows our ItemLevel module: discover item buttons when Blizzard
	rebuilds the pools...
	  * Bags / combined bags: ContainerFrame*:UpdateItemSlots
	  * Bank / warband bank: BankFrame.BankPanel:GenerateItemSlotsForSelectedTab
	...then post-hook each button's UpdateCooldown, which is the final call to set
	the icon vertex colour each refresh (it resets to white off-cooldown). Tinting
	anywhere earlier (e.g. IconBorder:SetShown) is silently overwritten by it.

	We only repaint slots we tinted, so Blizzard's locked / cooldown shading on
	other slots is left intact. Setup runs once and can't be undone (reload to
	disable).
--]]

-- luacheck: read_globals SetItemButtonTextureVertexColor UnitLevel UnitClassBase RED_FONT_COLOR Enum C_Container C_Item NUM_CONTAINER_FRAMES ContainerFrameCombinedBags BankFrame
---@diagnostic disable: undefined-global, undefined-field
local _, ns = ...
local F, L = ns.F, ns.L

local select = select
local hooksecurefunc = hooksecurefunc
local UnitLevel = UnitLevel
local UnitClassBase = UnitClassBase
local SetItemButtonTextureVertexColor = SetItemButtonTextureVertexColor
local C_Container_GetContainerItemInfo = C_Container.GetContainerItemInfo
local C_Item_GetItemInfo = C_Item.GetItemInfo
local C_Item_GetItemInfoInstant = C_Item.GetItemInfoInstant

local RED = _G.RED_FONT_COLOR or { r = 1, g = 0.1, b = 0.1 }

ns:RegisterDefaults({
	unusableItems = {
		enable = true,
	},
})

local UnusableItems = ns:NewModule("UnusableItems", "unusableItems", { group = "inventory", title = L["Unusable Items"], order = 55 })

local eventHandles = {}
local eventsRegistered = false

-- ---------------------------------------------------------------------------
-- Class-restriction data (resolved to the player's class at login).
--   playerUnusable[itemClassID][itemSubClassID] = true  -> unusable subtype
--   cannotDual                                          -> no off-hand weapon
-- ---------------------------------------------------------------------------
local playerUnusable
local cannotDual = false

local function BuildUnusable()
	local W = Enum and Enum.ItemWeaponSubclass
	local A = Enum and Enum.ItemArmorSubclass
	if not (W and A and Enum.ItemClass) then
		return
	end

	local byClass = {
		DEATHKNIGHT = { weapons = { W.Bows, W.Guns, W.Warglaive, W.Staff, W.Unarmed, W.Dagger, W.Thrown, W.Crossbow, W.Wand }, armor = { A.Shield } },
		DEMONHUNTER = { weapons = { W.Axe2H, W.Bows, W.Guns, W.Mace1H, W.Mace2H, W.Polearm, W.Sword2H, W.Staff, W.Thrown, W.Crossbow, W.Wand }, armor = { A.Mail, A.Plate, A.Shield } },
		DRUID = { weapons = { W.Axe1H, W.Axe2H, W.Bows, W.Guns, W.Sword1H, W.Sword2H, W.Warglaive, W.Thrown, W.Crossbow, W.Wand }, armor = { A.Mail, A.Plate, A.Shield }, cannotDual = true },
		EVOKER = { weapons = { W.Bows, W.Guns, W.Polearm, W.Warglaive, W.Thrown, W.Crossbow, W.Wand }, armor = { A.Plate, A.Shield }, cannotDual = true },
		HUNTER = { weapons = { W.Mace1H, W.Mace2H, W.Warglaive, W.Thrown, W.Wand }, armor = { A.Plate, A.Shield } },
		MAGE = { weapons = { W.Axe1H, W.Axe2H, W.Bows, W.Guns, W.Mace1H, W.Mace2H, W.Polearm, W.Sword2H, W.Warglaive, W.Unarmed, W.Thrown, W.Crossbow }, armor = { A.Leather, A.Mail, A.Plate, A.Shield }, cannotDual = true },
		MONK = { weapons = { W.Axe2H, W.Bows, W.Guns, W.Mace2H, W.Sword2H, W.Warglaive, W.Dagger, W.Thrown, W.Crossbow, W.Wand }, armor = { A.Mail, A.Plate, A.Shield } },
		PALADIN = { weapons = { W.Bows, W.Guns, W.Warglaive, W.Staff, W.Unarmed, W.Dagger, W.Thrown, W.Crossbow, W.Wand }, armor = {}, cannotDual = true },
		PRIEST = { weapons = { W.Axe1H, W.Axe2H, W.Bows, W.Guns, W.Mace2H, W.Polearm, W.Sword1H, W.Sword2H, W.Warglaive, W.Unarmed, W.Thrown, W.Crossbow }, armor = { A.Leather, A.Mail, A.Plate, A.Shield }, cannotDual = true },
		ROGUE = { weapons = { W.Axe2H, W.Mace2H, W.Polearm, W.Sword2H, W.Warglaive, W.Staff, W.Wand }, armor = { A.Mail, A.Plate, A.Shield } },
		SHAMAN = { weapons = { W.Bows, W.Guns, W.Polearm, W.Sword1H, W.Sword2H, W.Warglaive, W.Thrown, W.Crossbow, W.Wand }, armor = { A.Plate } },
		WARLOCK = { weapons = { W.Axe1H, W.Axe2H, W.Bows, W.Guns, W.Mace1H, W.Mace2H, W.Polearm, W.Sword2H, W.Warglaive, W.Unarmed, W.Thrown, W.Crossbow }, armor = { A.Leather, A.Mail, A.Plate, A.Shield }, cannotDual = true },
		WARRIOR = { weapons = { W.Warglaive, W.Wand }, armor = {} },
	}

	local entry = byClass[UnitClassBase("player")]
	if not entry then
		return
	end

	local lookup = { [Enum.ItemClass.Weapon] = {}, [Enum.ItemClass.Armor] = {} }
	local weapons, armor = lookup[Enum.ItemClass.Weapon], lookup[Enum.ItemClass.Armor]
	for i = 1, #entry.weapons do
		weapons[entry.weapons[i]] = true
	end
	for i = 1, #entry.armor do
		armor[entry.armor[i]] = true
	end

	playerUnusable = lookup
	cannotDual = entry.cannotDual or false
end

-- ---------------------------------------------------------------------------
-- Usability checks
-- ---------------------------------------------------------------------------
local playerLevel = 1
-- itemID -> bool (class restriction never changes per item). Written through
-- F.CacheSet so the table stays bounded over a long session, matching the
-- ItemLevel / AlreadyKnown modules.
local classCache = {}
local reqLevelCache = {}

local function GetRequiredLevel(link, itemID)
	if not link then
		return nil
	end
	if itemID and reqLevelCache[itemID] then
		return reqLevelCache[itemID]
	end
	local reqLevel = select(5, C_Item_GetItemInfo(link))
	if reqLevel then
		if itemID then
			reqLevelCache[itemID] = reqLevel
		end
		return reqLevel
	end
	if itemID and ns.RequestItemData then
		ns:RequestItemData(itemID, function()
			local loaded = select(5, C_Item_GetItemInfo(link)) or select(5, C_Item_GetItemInfo(itemID))
			if loaded and itemID then
				reqLevelCache[itemID] = loaded
			end
		end)
	end
	return reqLevel
end

local function IsClassUnusable(itemID)
	if not (playerUnusable and itemID) then
		return false
	end

	local cached = classCache[itemID]
	if cached ~= nil then
		return cached
	end

	local _, _, _, equipSlot, _, classID, subClassID = C_Item_GetItemInfoInstant(itemID)
	local result = false
	if classID and subClassID then
		local map = playerUnusable[classID]
		if equipSlot and equipSlot ~= "" and map and map[subClassID] then
			result = true
		elseif equipSlot == "INVTYPE_WEAPONOFFHAND" and cannotDual then
			result = true
		end
	end

	return F.CacheSet(classCache, itemID, result)
end

local function IsUnusable(link, itemID)
	if itemID and IsClassUnusable(itemID) then
		return true
	end

	if link then
		local reqLevel = GetRequiredLevel(link, itemID)
		if reqLevel and reqLevel > playerLevel then
			return true
		end
	end

	return false
end

-- ---------------------------------------------------------------------------
-- Tinting (only repaint slots we own)
-- ---------------------------------------------------------------------------
local function TintButton(button, info)
	if info and info.hyperlink and not info.isLocked and IsUnusable(info.hyperlink, info.itemID) then
		SetItemButtonTextureVertexColor(button, RED.r, RED.g, RED.b)
		button.nexUnfit = true
	elseif button.nexUnfit then
		SetItemButtonTextureVertexColor(button, 1, 1, 1)
		button.nexUnfit = nil
	end
end

-- Re-apply our tint for a single button. Reads live container info so it works
-- for both bag buttons (GetBagID/GetID) and bank buttons (GetBankTabID/
-- GetContainerSlotID). bagID 0 (backpack) is valid, so test against nil.
local function UpdateBagSlot(button)
	if not button then
		return
	end

	local bagID = button.GetBankTabID and button:GetBankTabID() or (button.GetBagID and button:GetBagID())
	local slotID = button.GetContainerSlotID and button:GetContainerSlotID() or (button.GetID and button:GetID())
	if bagID == nil or slotID == nil then
		if button.nexUnfit then
			SetItemButtonTextureVertexColor(button, 1, 1, 1)
			button.nexUnfit = nil
		end
		return
	end

	TintButton(button, C_Container_GetContainerItemInfo(bagID, slotID))
end

local function RefreshBagSlots()
	local function ScanFrame(frame)
		if not (frame and frame.itemButtonPool) then
			return
		end
		for button in frame.itemButtonPool:EnumerateActive() do
			UpdateBagSlot(button)
		end
	end

	local numFrames = _G.NUM_CONTAINER_FRAMES or 13
	for i = 1, numFrames do
		ScanFrame(_G["ContainerFrame" .. i])
	end
	ScanFrame(_G.ContainerFrameCombinedBags)

	local bank = _G.BankFrame
	if bank and bank.BankPanel then
		ScanFrame(bank.BankPanel)
	end
end

-- Blizzard's ItemButton:UpdateCooldown is the *last* call to set the icon vertex
-- colour during a refresh - it resets to white whenever an item is not on
-- cooldown - so post-hook it per button to get the final word. (Hooking earlier
-- triggers like IconBorder:SetShown gets silently overwritten by this.)
local function HandleBagSlots(frame)
	local pool = frame.itemButtonPool
	if not pool then
		return
	end
	for button in pool:EnumerateActive() do
		if not button.nexUnfitHooked and type(button.UpdateCooldown) == "function" then
			hooksecurefunc(button, "UpdateCooldown", UpdateBagSlot)
			button.nexUnfitHooked = true
		end
		UpdateBagSlot(button)
	end
end

function UnusableItems:HookBags()
	if self.bagsHooked then
		return
	end
	self.bagsHooked = true

	local numFrames = _G.NUM_CONTAINER_FRAMES or 13
	for i = 1, numFrames do
		local frame = _G["ContainerFrame" .. i]
		if frame and frame.UpdateItemSlots then
			hooksecurefunc(frame, "UpdateItemSlots", HandleBagSlots)
			HandleBagSlots(frame)
		end
	end

	local combined = _G.ContainerFrameCombinedBags
	if combined and combined.UpdateItemSlots then
		hooksecurefunc(combined, "UpdateItemSlots", HandleBagSlots)
		HandleBagSlots(combined)
	end

	local bank = _G.BankFrame
	if bank and bank.BankPanel and bank.BankPanel.GenerateItemSlotsForSelectedTab then
		hooksecurefunc(bank.BankPanel, "GenerateItemSlotsForSelectedTab", HandleBagSlots)
		if bank.BankPanel.RefreshAllItemsForSelectedTab then
			hooksecurefunc(bank.BankPanel, "RefreshAllItemsForSelectedTab", HandleBagSlots)
		end
		HandleBagSlots(bank.BankPanel)
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function UnusableItems:PLAYER_LEVEL_UP(level)
	playerLevel = level or UnitLevel("player")
	RefreshBagSlots()
end

function UnusableItems:OnEnable()
	if not ns.db.unusableItems.enable then
		return
	end

	BuildUnusable()
	playerLevel = UnitLevel("player") or 1

	self:HookBags()
	if not eventsRegistered then
		eventsRegistered = true
		self:TrackEvent(eventHandles, "PLAYER_LEVEL_UP")
	end
end

function UnusableItems:OnDisable()
	ns:UnregisterModuleEventHandles(eventHandles)
	eventsRegistered = false
end

function UnusableItems:OnSettingChanged(key, value)
	-- ApplyModuleSetting owns enable lifecycle.
	if key == "enable" then
		return
	end
end

function UnusableItems:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Colour Unusable Items"], L["Tint bag and bank icons red for items your class can't use or that you're too low level for (reload to disable)."])
end
