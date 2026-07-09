--[[
	NexEnhance - Auto Keystone
	-------------------------------------------------------------------------
	Automatically slots your Mythic+ keystone when the Challenge Mode UI
	(ChallengesKeystoneFrame) opens, so you don't have to drag it in by hand.

	Blizzard_ChallengesUI is load-on-demand, so we hook the keystone frame's
	OnShow when that addon loads (or immediately if already loaded). We bow out
	if AngryKeystones is present. Enable toggle reads live — no reload needed.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local F, L = ns.F, ns.L

local select = select
local C_AddOns_IsAddOnLoaded = C_AddOns.IsAddOnLoaded
local C_ChallengeMode_SlotKeystone = C_ChallengeMode.SlotKeystone
local C_Container_GetContainerItemID = C_Container.GetContainerItemID
local C_Container_GetContainerNumSlots = C_Container.GetContainerNumSlots
local C_Container_PickupContainerItem = C_Container.PickupContainerItem
local C_Cursor_GetCursorItem = C_Cursor.GetCursorItem
local C_Item_GetItemInfoInstant = C_Item.GetItemInfoInstant
local Enum_ItemClass_Reagent = Enum.ItemClass.Reagent
local Enum_ItemReagentSubclass_Keystone = Enum.ItemReagentSubclass.Keystone

-- Last bag to scan: the reagent bag (index 5) when the enum is present, else
-- fall back to the regular bag count.
local LAST_BAG = (Enum.BagIndex and Enum.BagIndex.ReagentBag) or (NUM_BAG_FRAMES + 1)

ns:RegisterDefaults({
	autoKeystone = {
		enable = true,
	},
})

local AutoKeystone = ns:NewModule("AutoKeystone", "autoKeystone", { group = "automation", title = L["Auto Keystone"], order = 90 })

local eventHandles = {}
local eventsRegistered = false

-- GetItemInfoInstant is synchronous (no item-cache dependency), returning
-- classID/subclassID at positions 6/7 - more reliable than GetItemInfo here.
local function IsKeystone(itemID)
	local classID, subClassID = select(6, C_Item_GetItemInfoInstant(itemID))
	return classID == Enum_ItemClass_Reagent and subClassID == Enum_ItemReagentSubclass_Keystone
end

local function SlotKeystoneFromBags()
	for bag = 0, LAST_BAG do
		for slot = 1, C_Container_GetContainerNumSlots(bag) do
			local itemID = C_Container_GetContainerItemID(bag, slot)
			if itemID and IsKeystone(itemID) then
				C_Container_PickupContainerItem(bag, slot)
				-- Only slot once the keystone is actually on the cursor.
				if C_Cursor_GetCursorItem() then
					C_ChallengeMode_SlotKeystone()
					return true
				end
			end
		end
	end
	return false
end

function AutoKeystone:OnKeystoneFrameShown()
	if not ns.db.autoKeystone.enable then
		return
	end

	if SlotKeystoneFromBags() then
		F.Print(L["Keystone automatically placed."])
	end
end

function AutoKeystone:HookKeystoneFrame()
	if self.hooked then
		return
	end
	local frame = _G["ChallengesKeystoneFrame"]
	if not frame then
		return
	end

	self.hooked = true
	frame:HookScript("OnShow", function()
		AutoKeystone:OnKeystoneFrameShown()
	end)
end

function AutoKeystone:ADDON_LOADED(addon)
	if addon == "Blizzard_ChallengesUI" then
		self:HookKeystoneFrame()
	end
end

function AutoKeystone:OnEnable()
	if not ns.db.autoKeystone.enable then
		return
	end
	-- AngryKeystones already auto-slots keystones; don't fight it.
	if C_AddOns_IsAddOnLoaded("AngryKeystones") then
		return
	end

	if C_AddOns_IsAddOnLoaded("Blizzard_ChallengesUI") then
		self:HookKeystoneFrame()
	elseif not eventsRegistered then
		eventsRegistered = true
		self:TrackEvent(eventHandles, "ADDON_LOADED")
	end
end

function AutoKeystone:OnDisable()
	ns:UnregisterModuleEventHandles(eventHandles)
	eventsRegistered = false
end

function AutoKeystone:OnSettingChanged(key, value)
	-- ApplyModuleSetting owns enable lifecycle.
	if key == "enable" then
		return
	end
end

function AutoKeystone:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Auto Keystone"], L["Automatically slot your Mythic+ keystone when the Challenge Mode UI opens."])
end
