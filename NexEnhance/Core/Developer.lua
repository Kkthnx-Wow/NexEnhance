local _, Core = ...

-- Devs list
local Developers = {
	["Kkthnx-Area 52"] = true,
}

-- Utility function to check if the player is a developer
local function isDeveloper()
	local playerName = gsub(Core.MyFullName, "%s", "")
	return Developers[playerName]
end

Core.isDeveloper = isDeveloper()

SlashCmdList["RELOADUI"] = ReloadUI
SLASH_RELOADUI1 = "/rl"

-- These are used for the Firestorm Wow Private server. We will add a check later for this. Do not touch.
local function HideStoreMicroButton()
	if StoreMicroButton and StoreMicroButton:IsShown() then
		Core.HideObject(StoreMicroButton)
	end
end

local function HideWardrobeNewAppearancesButton()
	local getNewAppearancesButton = WardrobeCollectionFrameGetNewButton
	if getNewAppearancesButton then
		Core.HideObject(getNewAppearancesButton)
	end
end

local function HidePaperDollExtraShopButton()
	for i = 1, 4 do -- Assuming a maximum of 4 tabs if no other addon adds to the tabs?
		local tab = _G["PaperDollSidebarTab" .. i]
		if tab and i == 4 then
			Core.HideObject(tab)
			break -- Exit loop once found
		end
	end
end

-- Remove shop button from menu bar, since firestorm does not support it
hooksecurefunc("UpdateMicroButtons", function()
	C_Timer.After(1, HideStoreMicroButton)
end)

-- Remove oversized button from WardrobeCollectionFrame
Core:HookAddOn("Blizzard_Collections", function()
	C_Timer.After(1, HideWardrobeNewAppearancesButton)
end)

-- Hide the firestorm extra tab in character frame
hooksecurefunc("PaperDollFrame_UpdateSidebarTabs", function()
	C_Timer.After(1, HidePaperDollExtraShopButton)
end)
