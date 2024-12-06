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

SlashCmdList["RELOADUI"] = ReloadUI
SLASH_RELOADUI1 = "/rl"
SLASH_RELOADUI2 = "/reload"
SLASH_RELOADUI3 = "/reloadui"
SLASH_RELOADUI4 = "/rui"
SLASH_RELOADUI5 = "/re"
SLASH_RELOADUI6 = "///"

--[[ ============================================================
    SECTION: Power Bar Frame Modification
    Modifies the UI widget power bar frame, including scaling 
    and hiding textures as specified in the configuration.
=============================================================== ]]

local function UpdatePowerBarAppearance()
	if UIWidgetPowerBarContainerFrame then
		local configuredScale = Core.NexConfig.miscellaneous.widgetScale
		if UIWidgetPowerBarContainerFrame:GetScale() ~= configuredScale then
			UIWidgetPowerBarContainerFrame:SetScale(configuredScale)
		end

		if Core.NexConfig.miscellaneous.hideWidgetTexture then
			for _, childFrame in ipairs({ UIWidgetPowerBarContainerFrame:GetChildren() }) do
				for _, textureRegion in ipairs({ childFrame:GetRegions() }) do
					if textureRegion:GetObjectType() == "Texture" and textureRegion:IsShown() then
						textureRegion:Hide()
					end
				end
			end
		end
	end
end

local PowerBarUpdaterFrame = CreateFrame("Frame")
PowerBarUpdaterFrame:RegisterEvent("UPDATE_UI_WIDGET")
PowerBarUpdaterFrame:HookScript("OnEvent", UpdatePowerBarAppearance)

--[[ ============================================================
    SECTION: Chat Highlight and Sound Alerts
    Handles highlighting the player's name and guild tags in chat, 
    and optionally plays a sound when the player's name is mentioned.
=============================================================== ]]

local chatHighlightConfig = {
	highlightPlayer = true,
	useBrackets = true,
	highlightColor = "00ff00",
	highlightGuild = true,
	playSound = true,
	soundFile = 182876,
	soundCooldown = 5,
}

local lastSoundTime = 0

local function wrapName(match)
	local color = chatHighlightConfig.highlightColor or "00ff00"
	if chatHighlightConfig.useBrackets then
		return "|cff" .. color .. "[" .. match .. "]|r"
	else
		return "|cff" .. color .. match .. "|r"
	end
end

local function highlightGuildTag(tag)
	local color = chatHighlightConfig.highlightColor or "00ff00"
	return "|cff" .. color .. "<" .. tag .. ">|r"
end

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

local function ChatFilter(_, _, message, ...)
	local playerName = UnitName("player")
	local nameHighlighted = false

	if chatHighlightConfig.highlightPlayer then
		local playerNamePattern = playerName:gsub("%a", function(c)
			return "[" .. c:upper() .. c:lower() .. "]"
		end)
		message = message:gsub(playerNamePattern, function(match)
			nameHighlighted = true
			return wrapName(match)
		end)
	end

	if chatHighlightConfig.highlightGuild then
		message = message:gsub("<(.-)>", highlightGuildTag)
	end

	if nameHighlighted then
		playHighlightSound()
	end

	return false, message, ...
end

local chatFrame = CreateFrame("Frame")
chatFrame:RegisterEvent("PLAYER_LOGIN")
chatFrame:SetScript("OnEvent", function()
	local filters = {
		"CHAT_MSG_SAY",
		"CHAT_MSG_YELL",
		"CHAT_MSG_PARTY",
		"CHAT_MSG_RAID",
		"CHAT_MSG_GUILD",
		"CHAT_MSG_WHISPER",
		"CHAT_MSG_CHANNEL",
	}
	for _, event in ipairs(filters) do
		ChatFrame_AddMessageEventFilter(event, ChatFilter)
	end
end)

--[[ ============================================================
    SECTION: Error Toggle for Combat
    Temporarily disables UI error messages during combat and 
    re-enables them afterward to reduce distraction.
=============================================================== ]]

local ErrorToggleEventFrame = CreateFrame("Frame")
ErrorToggleEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
ErrorToggleEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
ErrorToggleEventFrame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		_G.UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
	elseif event == "PLAYER_REGEN_ENABLED" then
		_G.UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
	end
end)

--[[ ============================================================
    SECTION: Chat Message Blocker
    Filters out specific phrases or patterns in chat messages 
    (e.g., monster emotes) based on a configurable list of patterns.
=============================================================== ]]

local ChatFilter = {}
ChatFilter.blockedPatterns = {
	"^%s goes into a frenzy!$",
	"^%s attempts to run away in fear!$",
}

function ChatFilter:IsBlockedMessage(message)
	for _, pattern in ipairs(self.blockedPatterns) do
		if string.match(message, pattern:gsub("%%s", ".+")) then
			return true
		end
	end
	return false
end

function ChatFilter:OnChatMessage(_, _, msg, sender, ...)
	if self:IsBlockedMessage(msg) then
		DEFAULT_CHAT_FRAME:AddMessage("|cffFF0000[ChatFilter] Blocked message from: " .. sender .. "|r", 1.0, 0.0, 0.0)
		return true
	end
	return false
end

function ChatFilter:Initialize()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("CHAT_MSG_MONSTER_EMOTE")
	frame:SetScript("OnEvent", function(_, event, ...)
		if event == "CHAT_MSG_MONSTER_EMOTE" then
			self:OnChatMessage(nil, event, ...)
		end
	end)
end

ChatFilter:Initialize()
