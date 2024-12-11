--[[ 
    Developer Playground (Dev File)
    This file serves as a playground for testing features and ideas that might or might not make it 
    into NexEnhance UI. Nothing here is final or permanent—just a space for fun experimentation! 
]]

local _, Core = ...

--[[ ============================================================
    SECTION: Developer Utilities
    This section includes developer-related logic, such as checking
    if the current player is a developer and managing developer tools.
=============================================================== ]]

Core.Developers = {
	["Kkthnx-Area 52"] = true,
	["Kkthnxx-Area 52"] = true,
	["Kkthnxbye-Area 52"] = true,
}

local function isDeveloper()
	local playerName = gsub(Core.MyFullName, "%s", "")
	return Core.Developers[playerName]
end

Core.isDeveloper = isDeveloper()

--[[ ============================================================
    SECTION: Slash Command Utilities
    Provides convenient slash commands for developers, such as 
    quickly reloading the UI (/rl).
=============================================================== ]]

do
	SlashCmdList["RELOADUI"] = ReloadUI
	SLASH_RELOADUI1 = "/rl"
	SLASH_RELOADUI2 = "/reload"
	SLASH_RELOADUI3 = "/reloadui"
	SLASH_RELOADUI4 = "/rui"
	SLASH_RELOADUI5 = "/re"
	SLASH_RELOADUI6 = "///"
end

--[[ ============================================================
    SECTION: Power Bar Frame Modification
    Modifies the UI widget power bar frame, including scaling 
    and hiding textures as specified in the configuration.
=============================================================== ]]

do
	-- Cache global functions for better performance
	local ipairs = ipairs
	local CreateFrame = CreateFrame

	-- Function to update the power bar's appearance
	local function UpdatePowerBarAppearance()
		local widgetFrame = _G.UIWidgetPowerBarContainerFrame
		if not widgetFrame then
			return
		end -- Exit early if the frame doesn't exist

		-- Cache the configuration values
		local configuredScale = Core.NexConfig.miscellaneous.widgetScale
		local hideWidgetTexture = Core.NexConfig.miscellaneous.hideWidgetTexture

		-- Update the scale only if necessary
		if widgetFrame:GetScale() ~= configuredScale then
			widgetFrame:SetScale(configuredScale)
		end

		-- Hide textures if the option is enabled
		if hideWidgetTexture then
			for _, childFrame in ipairs({ widgetFrame:GetChildren() }) do
				for _, region in ipairs({ childFrame:GetRegions() }) do
					if region:IsShown() and region:GetObjectType() == "Texture" then
						region:Hide()
					end
				end
			end
		end
	end

	-- Create a frame to handle the UPDATE_UI_WIDGET event
	local PowerBarUpdaterFrame = CreateFrame("Frame")
	PowerBarUpdaterFrame:RegisterEvent("UPDATE_UI_WIDGET")

	-- Use a lightweight OnEvent script
	PowerBarUpdaterFrame:SetScript("OnEvent", function(_, event)
		if event == "UPDATE_UI_WIDGET" then
			UpdatePowerBarAppearance()
		end
	end)
end

--[[ ============================================================
    SECTION: Chat Highlight and Sound Alerts
    Handles highlighting the player's name and guild tags in chat, 
    and optionally plays a sound when the player's name is mentioned.
=============================================================== ]]

do
	-- Cache global variables for better performance
	local UnitName = UnitName
	local GetTime = GetTime
	local PlaySound = PlaySound
	local ChatFrame_AddMessageEventFilter = ChatFrame_AddMessageEventFilter
	local CreateFrame = CreateFrame

	-- Chat highlight configuration
	local chatHighlightConfig = {
		highlightPlayer = true,
		useBrackets = true,
		highlightColor = "00ff00",
		highlightGuild = true,
		playSound = true,
		soundFile = 182876,
		soundCooldown = 5,
	}

	-- Keep track of the last sound time
	local lastSoundTime = 0

	-- Wrap player name in highlight color and brackets
	local function wrapName(match)
		local color = chatHighlightConfig.highlightColor or "00ff00"
		if chatHighlightConfig.useBrackets then
			return "|cff" .. color .. "[" .. match .. "]|r"
		else
			return "|cff" .. color .. match .. "|r"
		end
	end

	-- Highlight guild tags
	local function highlightGuildTag(tag)
		local color = chatHighlightConfig.highlightColor or "00ff00"
		return "|cff" .. color .. "<" .. tag .. ">|r"
	end

	-- Play the highlight sound with cooldown
	local function playHighlightSound()
		if chatHighlightConfig.playSound then
			local currentTime = GetTime()
			if currentTime - lastSoundTime >= chatHighlightConfig.soundCooldown then
				local success = PlaySound(chatHighlightConfig.soundFile, "Master")
				if success then
					lastSoundTime = currentTime
				end
			end
		end
	end

	-- Filter chat messages
	local function ChatFilter(_, event, message, author, ...)
		local playerName = UnitName("player")

		-- Ignore messages authored by the player themselves
		if author == playerName then
			return false
		end

		local nameHighlighted = false

		if chatHighlightConfig.highlightPlayer then
			-- Create a pattern to match the player's name in any case
			local playerNamePattern = playerName:gsub("%a", function(c)
				return "[" .. c:upper() .. c:lower() .. "]"
			end)
			message = message:gsub(playerNamePattern, function(match)
				nameHighlighted = true
				return wrapName(match)
			end)
		end

		if chatHighlightConfig.highlightGuild then
			-- Highlight guild tags in messages
			message = message:gsub("<(.-)>", highlightGuildTag)
		end

		if nameHighlighted then
			playHighlightSound()
		end

		-- Return false to allow Blizzard's handling of the event
		return false, message, author, ...
	end

	-- Initialize the chat filter on PLAYER_LOGIN
	local chatFrame = CreateFrame("Frame")
	chatFrame:RegisterEvent("PLAYER_LOGIN")
	chatFrame:SetScript("OnEvent", function()
		-- List of chat events to filter
		local filters = {
			"CHAT_MSG_SAY",
			"CHAT_MSG_YELL",
			"CHAT_MSG_PARTY",
			"CHAT_MSG_RAID",
			"CHAT_MSG_GUILD",
			"CHAT_MSG_WHISPER",
			"CHAT_MSG_CHANNEL",
		}
		-- Register the ChatFilter function for all relevant events
		for _, event in ipairs(filters) do
			ChatFrame_AddMessageEventFilter(event, ChatFilter)
		end
		chatFrame:UnregisterEvent("PLAYER_LOGIN") -- Clean up event registration
	end)
end

--[[ ============================================================
    SECTION: Error Toggle for Combat
    Temporarily disables UI error messages during combat and 
    re-enables them afterward to reduce distraction.
=============================================================== ]]

do
	-- Cache global variables for better performance
	local UIErrorsFrame = _G.UIErrorsFrame
	local CreateFrame = CreateFrame

	-- Create and configure the event frame
	local ErrorToggleEventFrame = CreateFrame("Frame")
	ErrorToggleEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
	ErrorToggleEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

	-- Event handler
	ErrorToggleEventFrame:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then
			UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
		elseif event == "PLAYER_REGEN_ENABLED" then
			UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
		end
	end)
end

--[[ ============================================================
    SECTION: Chat Message Blocker
    Filters out specific phrases or patterns in chat messages 
    (e.g., monster emotes) based on a configurable list of patterns.
=============================================================== ]]

do
	-- Cache global references for performance
	local string_match = string.match
	local string_gsub = string.gsub
	local ipairs = ipairs
	local ChatFrame_AddMessageEventFilter = ChatFrame_AddMessageEventFilter

	-- Create the ChatFilter object
	local ChatFilter = {}
	ChatFilter.blockedPatterns = {
		"^%s goes into a frenzy!$",
		"^%s attempts to run away in fear!$",
	}

	-- Check if a message matches any of the blocked patterns
	function ChatFilter:IsBlockedMessage(message)
		for _, pattern in ipairs(self.blockedPatterns) do
			if string_match(message, string_gsub(pattern, "%%s", ".+")) then
				return true
			end
		end
		return false
	end

	-- Custom chat message filter function
	local function MyChatFilter(self, event, msg, sender, ...)
		if ChatFilter:IsBlockedMessage(msg) then
			return true
		end
		return false
	end

	-- Add the filter for specific chat message events
	ChatFrame_AddMessageEventFilter("CHAT_MSG_MONSTER_EMOTE", MyChatFilter)
end
