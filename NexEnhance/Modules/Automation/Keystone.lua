local _, Module = ...

local ITEM_CLASS_REAGENT = Enum.ItemClass.Reagent
local ITEM_SUBCLASS_KEYSTONE = Enum.ItemReagentSubclass.Keystone
local NUM_BAGS = NUM_BAG_FRAMES

-- Scan bags for Keystone and slot it
local function SlotMythicKeystone()
	for bag = 0, NUM_BAGS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local itemID = C_Container.GetContainerItemID(bag, slot)
			if itemID then
				local _, _, _, _, _, _, _, _, _, _, _, classID, subClassID = C_Item.GetItemInfo(itemID)
				if classID == ITEM_CLASS_REAGENT and subClassID == ITEM_SUBCLASS_KEYSTONE then
					C_Container.PickupContainerItem(bag, slot)
					if CursorHasItem() then
						C_ChallengeMode.SlotKeystone()
						return
					else
						Module:Print("SlotMythicKeystone: Failed to pick up the Keystone.")
					end
				end
			end
		end
	end

	Module:Print("SlotMythicKeystone: No valid Keystone found in bags.")
end

-- Make ChallengesKeystoneFrame draggable
local function EnableKeystoneFrameDragging(keystoneFrame)
	if not keystoneFrame:IsMovable() then
		keystoneFrame:SetMovable(true)
		keystoneFrame:SetClampedToScreen(true)
		keystoneFrame:RegisterForDrag("LeftButton")
		keystoneFrame:SetScript("OnDragStart", keystoneFrame.StartMoving)
		keystoneFrame:SetScript("OnDragStop", keystoneFrame.StopMovingOrSizing)
	end
end

-- Hook the ChallengesKeystoneFrame for auto keystone slotting and dragging
local function HookKeystoneFrame()
	if not Module.db.profile.automation.AutoKeystoneSlotting then
		return
	end

	local keystoneFrame = ChallengesKeystoneFrame
	if keystoneFrame then
		if not keystoneFrame.isHooked then
			keystoneFrame:HookScript("OnShow", SlotMythicKeystone)
			keystoneFrame.isHooked = true
		end

		EnableKeystoneFrameDragging(keystoneFrame)
	else
		Module:Print("HookKeystoneFrame: ChallengesKeystoneFrame not found!")
	end
end

-- Load and hook Keystone frame when Blizzard Challenges UI is loaded
function Module:OnLoad()
	self:HookAddOn("Blizzard_ChallengesUI", HookKeystoneFrame)
end
