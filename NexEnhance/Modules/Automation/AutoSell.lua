local NexEnhance, NE_AutoSell = ...

-- WoW API references for convenience
local wipe = table.wipe
local C_Timer_After = C_Timer.After
local IsShiftKeyDown = IsShiftKeyDown
local C_TransmogCollection_GetItemInfo = C_TransmogCollection.GetItemInfo
local C_Container_UseContainerItem = C_Container.UseContainerItem
local C_Container_GetContainerNumSlots = C_Container.GetContainerNumSlots
local C_Container_GetContainerItemInfo = C_Container.GetContainerItemInfo

-- Auto sell junk configuration and state
local isSellingPaused = true
local itemSellCache = {}
local vendorCannotBuyError = _G.ERR_VENDOR_DOESNT_BUY

-- Function to start selling junk items
local function startSelling()
	if isSellingPaused then
		return
	end

	for bag = 0, 5 do
		for slot = 1, C_Container_GetContainerNumSlots(bag) do
			if isSellingPaused then
				return
			end

			local info = C_Container_GetContainerItemInfo(bag, slot)
			if info then
				local itemKey = "b" .. bag .. "s" .. slot
				if not itemSellCache[itemKey] and info.hyperlink and not info.hasNoValue and info.quality == 0 then
					local isUnknownTransmog = not C_TransmogCollection_GetItemInfo(info.hyperlink) or not NE_AutoSell.IsUnknownTransmog(bag, slot)
					if isUnknownTransmog then
						itemSellCache[itemKey] = true
						C_Container_UseContainerItem(bag, slot)
						C_Timer_After(0.15, startSelling) -- Continue selling after a short delay
						return
					end
				end
			end
		end
	end
end

function NE_AutoSell:MERCHANT_SHOW()
	if IsShiftKeyDown() then
		return
	end

	isSellingPaused = false
	wipe(itemSellCache)
	startSelling()
end

function NE_AutoSell:MERCHANT_CLOSED()
	isSellingPaused = true
end

function NE_AutoSell:UI_ERROR_MESSAGE(_, message)
	if message == vendorCannotBuyError then
		print(arg)
		isSellingPaused = true
	end
end
