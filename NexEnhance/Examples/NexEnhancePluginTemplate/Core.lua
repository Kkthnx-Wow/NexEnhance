--[[
	NexEnhance Plugin Template
	-------------------------------------------------------------------------
	1. Copy this entire folder to Interface/AddOns/ under a new name.
	2. Edit the .toc (Title, Author, Version) and keep ## Dependencies: NexEnhance.
	3. Customize the RegisterPlugin block below.
	4. /reload and open Esc → Options → NexEnhance → Plugin Manager.
--]]

local addonName = ...

local function RegisterWithNexEnhance()
	local nex = _G.NexEnhance
	if not nex or not nex.RegisterPlugin then
		return
	end

	nex:RegisterPlugin({
		id = "YourName." .. addonName,
		addon = addonName,
		name = "ExamplePlugin",
		title = "Example Plugin",
		dbKey = "examplePlugin",
		version = "1.0.0",
		author = "Your Name",
		notes = "A minimal NexEnhance plugin that prints a message when enabled.",
		defaults = {
			enable = true,
			greetInChat = true,
		},

		OnEnable = function(_plugin)
			-- Install hooks, create frames, register events here.
		end,

		OnDisable = function(_plugin)
			-- Tear down hooks, frames, and event registrations here.
		end,

		OnSettingChanged = function(plugin, key, value)
			if key == "greetInChat" and value and plugin:IsEnabled() then
				DEFAULT_CHAT_FRAME:AddMessage("|cff5C8BCFNexEnhance|r Example Plugin: setting enabled.")
			end
		end,

		RegisterOptions = function(plugin, category, builder)
			builder:Checkbox(category, plugin, "enable", "Enable", "Turn this example plugin on or off.")
			builder:Checkbox(category, plugin, "greetInChat", "Greet in chat", "Print a one-line message when this toggle is turned on.")
		end,
	})
end

if _G.NexEnhance and _G.NexEnhance.RegisterPlugin then
	RegisterWithNexEnhance()
else
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("ADDON_LOADED")
	frame:SetScript("OnEvent", function(_, _, loaded)
		if loaded == "NexEnhance" then
			RegisterWithNexEnhance()
			frame:UnregisterAllEvents()
		end
	end)
end
