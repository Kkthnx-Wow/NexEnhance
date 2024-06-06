local NexEnhance, NE_AutoSell = ...

local wipe = table.wipe
local C_Timer_After, IsShiftKeyDown = C_Timer.After, IsShiftKeyDown
local C_TransmogCollection_GetItemInfo = C_TransmogCollection.GetItemInfo
local C_Container_UseContainerItem = C_Container.UseContainerItem
local C_Container_GetContainerNumSlots = C_Container.GetContainerNumSlots
local C_Container_GetContainerItemInfo = C_Container.GetContainerItemInfo

-- Auto selljunk
local stop, cache = true, {}
local errorText = _G.ERR_VENDOR_DOESNT_BUY

local function startSelling()
	if stop then
		return
	end
	for bag = 0, 5 do
		for slot = 1, C_Container_GetContainerNumSlots(bag) do
			if stop then
				return
			end
			local info = C_Container_GetContainerItemInfo(bag, slot)
			if info then
				if not cache["b" .. bag .. "s" .. slot] and info.hyperlink and not info.hasNoValue and info.quality == 0 and (not C_TransmogCollection_GetItemInfo(info.hyperlink) or not NE_AutoSell.IsUnknownTransmog(bag, slot)) then
					cache["b" .. bag .. "s" .. slot] = true
					C_Container_UseContainerItem(bag, slot)
					C_Timer_After(0.15, startSelling)
					return
				end
			end
		end
	end
end

local function updateSelling(event, ...)
	if not NE_AutoSell.db.profile.automation.AutoSell then
		return
	end

	local _, arg = ...
	if event == "MERCHANT_SHOW" then
		print(event)
		if IsShiftKeyDown() then
			return
		end
		stop = false
		wipe(cache)
		startSelling()
		NE_AutoSell.eventMixin:RegisterEvent("UI_ERROR_MESSAGE", updateSelling)
	elseif event == "UI_ERROR_MESSAGE" and arg == errorText or event == "MERCHANT_CLOSED" then
		stop = true
	end
end

NE_AutoSell.eventMixin:RegisterEvent("MERCHANT_SHOW", updateSelling)
NE_AutoSell.eventMixin:RegisterEvent("MERCHANT_CLOSED", updateSelling)
