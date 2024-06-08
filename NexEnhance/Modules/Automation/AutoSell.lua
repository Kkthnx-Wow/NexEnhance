local _, Module = ...

-- WoW API references for convenience
local wipe = table.wipe
local C_Timer_After = C_Timer.After
local IsShiftKeyDown = IsShiftKeyDown
local C_TransmogCollection_GetItemInfo = C_TransmogCollection.GetItemInfo
local C_Container_UseContainerItem = C_Container.UseContainerItem
local C_Container_GetContainerNumSlots = C_Container.GetContainerNumSlots
local C_Container_GetContainerItemInfo = C_Container.GetContainerItemInfo

-- Auto sell junk functionality
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
				if not cache["b" .. bag .. "s" .. slot] and info.hyperlink and not info.hasNoValue and info.quality == 0 and (not C_TransmogCollection_GetItemInfo(info.hyperlink) or not Module.IsUnknownTransmog(bag, slot)) then
					cache["b" .. bag .. "s" .. slot] = true
					C_Container_UseContainerItem(bag, slot)
					C_Timer_After(0.15, startSelling)
					return
				end
			end
		end
	end
end

local function uiErrorMessage(_, message)
	if not Module.db.profile.automation.AutoSell then
		return
	end

	if message == errorText then
		stop = true
	end
end

local function merchantShow()
	if not Module.db.profile.automation.AutoSell then
		return
	end

	if IsShiftKeyDown() then
		return
	end

	stop = false
	wipe(cache)
	startSelling()
	Module:RegisterEvent("UI_ERROR_MESSAGE", uiErrorMessage)
end

local function merchantClosed()
	if not Module.db.profile.automation.AutoSell then
		return
	end

	stop = true
end

Module:RegisterEvent("MERCHANT_SHOW", merchantShow)
Module:RegisterEvent("MERCHANT_CLOSED", merchantClosed)
