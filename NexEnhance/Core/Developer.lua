--[[ 
    Developer Playground (Dev File)
    This file serves as a playground for testing features and ideas that might or might not make it 
    into NexEnhance UI. Nothing here is final or permanent—just a space for fun experimentation! 
]]

local _, Core = ...

-- Developer List
local Developers = {
	["Kkthnx-Area 52"] = true,
	["Kkthnxx-Area 52"] = true,
	["Kkthnxbye-Area 52"] = true,
}

-- Utility: Check if the player is a developer
local function isDeveloper()
	local playerName = gsub(Core.MyFullName, "%s", "")
	return Developers[playerName]
end

Core.isDeveloper = isDeveloper()

-- Slash Commands
SlashCmdList["RELOADUI"] = ReloadUI
SLASH_RELOADUI1 = "/rl"

-- Section: Power Bar Frame Modification
local function modifyPowerBarFrame()
	if UIWidgetPowerBarContainerFrame then
		if UIWidgetPowerBarContainerFrame:GetScale() ~= Core.db.profile.miscellaneous.widgetScale then
			UIWidgetPowerBarContainerFrame:SetScale(Core.db.profile.miscellaneous.widgetScale)
		end

		if Core.db.profile.miscellaneous.hideWidgetTexture then
			for _, child in ipairs({ UIWidgetPowerBarContainerFrame:GetChildren() }) do
				for _, region in ipairs({ child:GetRegions() }) do
					if region:GetObjectType() == "Texture" and region:IsShown() then
						region:Hide()
					end
				end
			end
		end
	end
end

local frameUpdater = CreateFrame("Frame")
frameUpdater:RegisterEvent("UPDATE_UI_WIDGET")
frameUpdater:HookScript("OnEvent", modifyPowerBarFrame)

-- Section: Chat Frame Toggle Functions
function Core:ToggleSocialButton()
	if QuickJoinToastButton then
		if Core.db.profile.chat.SocialButton then
			QuickJoinToastButton:Hide()
		else
			QuickJoinToastButton:Show()
		end
	end
end

function Core:ToggleMenuButton()
	if ChatFrameMenuButton then
		if Core.db.profile.chat.MenuButton then
			ChatFrameMenuButton:SetScript("OnShow", nil)
			ChatFrameMenuButton:Hide()
		else
			ChatFrameMenuButton:Show()
		end
	end
end

function Core:ToggleChannelButton()
	if ChatFrameChannelButton then
		if Core.db.profile.chat.ChannelButton then
			ChatFrameChannelButton:SetScript("OnShow", nil)
			ChatFrameChannelButton:Hide()
		else
			ChatFrameChannelButton:Show()
		end
	end
end

-- Initialize Toggles on Login
function Core:PLAYER_LOGIN()
	self:ToggleSocialButton()
	self:ToggleMenuButton()
	self:ToggleChannelButton()
end

-- Section: Chat Filter and Highlighting
local db = {
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
	local color = db.highlightColor or "00ff00"
	if db.useBrackets then
		return "|cff" .. color .. "[" .. match .. "]|r"
	else
		return "|cff" .. color .. match .. "|r"
	end
end

local function HighlightGuildTag(tag)
	local color = db.highlightColor or "00ff00"
	return "|cff" .. color .. "<" .. tag .. ">|r"
end

local function PlayHighlightSound()
	if db.playSound then
		local currentTime = GetTime()
		if currentTime - lastSoundTime >= db.soundCooldown then
			local success = PlaySound(db.soundFile, "Master")
			if success then
				lastSoundTime = currentTime
			end
		end
	end
end

local function ChatFilter(_, _, message, ...)
	local playerName = UnitName("player")
	local nameHighlighted = false

	if db.highlightPlayer then
		local playerNamePattern = playerName:gsub("%a", function(c)
			return "[" .. c:upper() .. c:lower() .. "]"
		end)
		message = message:gsub(playerNamePattern, function(match)
			nameHighlighted = true
			return wrapName(match)
		end)
	end

	if db.highlightGuild then
		message = message:gsub("<(.-)>", HighlightGuildTag)
	end

	if nameHighlighted then
		PlayHighlightSound()
	end

	return false, message, ...
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
	ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", ChatFilter)
	ChatFrame_AddMessageEventFilter("CHAT_MSG_YELL", ChatFilter)
	ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY", ChatFilter)
	ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID", ChatFilter)
	ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD", ChatFilter)
	ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", ChatFilter)
	ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", ChatFilter)
end)

-- Section: Error Toggle for Combat
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
