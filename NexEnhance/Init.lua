-- NexEnhance Initialization File
local _, Init = ...

-- Initialize addon modules
Init.Data = Init.Data or {}
Init.Actionbars = Init.Actionbars or {}
Init.Automation = Init.Automation or {}
Init.Blizzard = Init.Blizzard or {}
Init.BugFixes = Init.BugFixes or {}
Init.Chat = Init.Chat or {}
Init.General = Init.General or {}
Init.Inventory = Init.Inventory or {}
Init.Loot = Init.Loot or {}
Init.Maps = Init.Maps or {}
Init.Miscellaneous = Init.Miscellaneous or {}
Init.Skins = Init.Skins or {}
Init.Unitframes = Init.Unitframes or {}

-- Helper function to disable an addon and reload UI
local function ForceAddOnDisable(addonName)
	C_AddOns.DisableAddOn(addonName)
	ReloadUI()
end

-- Popup dialog to resolve addon conflicts
local function ShowAddonConflictPopup()
	StaticPopupDialogs["ADDON_CONFLICT"] = {
		text = "Both KkthnxUI and NexEnhance are loaded. You can only use one at a time. Please choose which addon to disable.",
		button1 = "Disable |cff669DFFKkthnxUI|r",
		button2 = "Disable |cff5bc0beNexEnhance|r",
		OnAccept = function()
			ForceAddOnDisable("KkthnxUI")
		end,
		OnCancel = function()
			ForceAddOnDisable("NexEnhance")
		end,
		timeout = 10,
		whileDead = true,
		hideOnEscape = false,
		preferredIndex = 3, -- Avoids tainting other UI elements
	}

	StaticPopup_Show("ADDON_CONFLICT")
end

-- Check for conflicting addons (KkthnxUI and NexEnhance)
local function CheckForConflictingAddons()
	if Init:IsAddOnEnabled("KkthnxUI") and Init:IsAddOnEnabled("NexEnhance") then
		ShowAddonConflictPopup()

		-- Auto-disable NexEnhance after 10 seconds if no choice is made
		C_Timer.After(10, function()
			if StaticPopup_Visible("ADDON_CONFLICT") then
				ForceAddOnDisable("NexEnhance")
			end
		end)
	end
end

-- Initialization function triggered on PLAYER_LOGIN event
function Init:OnLogin()
	CheckForConflictingAddons()
	-- Set default CVars
	SetCVar("ActionButtonUseKeyDown", 1)
end
