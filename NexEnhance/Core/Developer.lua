local _, Core = ...

-- Devs list
local Developers = {
	["Kkthnx-Area 52"] = true,
	["Kkthnxx-Area 52"] = true,
	["Kkthnxbye-Area 52"] = true,
}

-- Utility function to check if the player is a developer
local function isDeveloper()
	local playerName = gsub(Core.MyFullName, "%s", "")
	return Developers[playerName]
end

Core.isDeveloper = isDeveloper()

SlashCmdList["RELOADUI"] = ReloadUI
SLASH_RELOADUI1 = "/rl"

local function modifyPowerBarFrame()
	if UIWidgetPowerBarContainerFrame then
		if UIWidgetPowerBarContainerFrame:GetScale() ~= Core.db.profile.miscellaneous.widgetScale then
			UIWidgetPowerBarContainerFrame:SetScale(Core.db.profile.miscellaneous.widgetScale)
		end

		if Core.db.profile.miscellaneous.hideWidgetTexture then -- Only hide textures if the option is enabled
			for _, child in ipairs({ UIWidgetPowerBarContainerFrame:GetChildren() }) do
				for _, region in ipairs({ child:GetRegions() }) do
					if region:GetObjectType() == "Texture" then
						if region:IsShown() and Core.db.profile.miscellaneous.hideWidgetTexture then
							region:Hide()
						end
					end
				end
			end
		end
	end
end

local frameUpdater = CreateFrame("Frame")
frameUpdater:RegisterEvent("UPDATE_UI_WIDGET")
frameUpdater:HookScript("OnEvent", modifyPowerBarFrame)

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

function Core:PLAYER_LOGIN()
	self:ToggleSocialButton()
	self:ToggleMenuButton()
	self:ToggleChannelButton()
end

local _, namespace = ...

-- Helper function to create a text-based queue timer with frame skin
local function CreateQueueTimerFrame(parentDialog, duration, event)
	local frame = namespace:CreateFrame("Frame", nil, parentDialog, "BackdropTemplate")
	frame.backdropInfo = BACKDROP_DIALOG_32_32
	frame:ApplyBackdrop()
	frame:SetPoint("TOP", parentDialog, "BOTTOM", 0, 6)
	frame:SetSize(304, 64)

	-- Create the timer text
	frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.text:SetPoint("CENTER")
	frame.text:SetText("QueueTimer: " .. duration .. "s")
	frame.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "")

	local function GetColor(timeLeft, maxTime)
		local percentage = timeLeft / maxTime
		if percentage > 0.66 then
			return 0, 1, 0
		elseif percentage > 0.33 then
			return 1, 1, 0
		elseif percentage > 0.1 then
			return 1, 0.5, 0
		else
			return 1, 0, 0
		end
	end

	local function UpdateText()
		local startTime = GetTime()
		frame:SetScript("OnUpdate", function(_, elapsed)
			local elapsedTime = GetTime() - startTime
			local timeLeft = math.max(0, duration - elapsedTime)

			if timeLeft > 0 then
				local r, g, b = GetColor(timeLeft, duration)
				frame.text:SetText("QueueTimer: " .. string.format("%.1f", timeLeft) .. "s")
				frame.text:SetTextColor(r, g, b)
			else
				frame:SetScript("OnUpdate", nil)
				frame.text:SetText("QueueTimer: 0s")
				frame.text:SetTextColor(1, 0, 0)
			end
		end)
	end

	namespace:RegisterEvent(event, function()
		if parentDialog:IsShown() then
			frame.text:SetText("QueueTimer: " .. duration .. "s")
			frame.text:SetTextColor(0, 1, 0)
			UpdateText()
		end
	end)
end

-- Function to initialize the LFG Dungeon Ready Dialog Timer
local function InitLFGDungeonReadyDialogTimer()
	CreateQueueTimerFrame(LFGDungeonReadyDialog, 40, "LFG_PROPOSAL_SHOW")
end

-- Function to initialize the PVP Ready Dialog Timer
local function InitPVPReadyDialogTimer()
	CreateQueueTimerFrame(PVPReadyDialog, 90, "UPDATE_BATTLEFIELD_STATUS")
end

-- Use HookAddOn to ensure the code only loads when the addon is enabled
function namespace:OnLogin()
	if namespace:IsAddOnEnabled("DBM-Core") or namespace:IsAddOnEnabled("BigWigs") then
		return
	end

	-- Initialize both timers
	InitLFGDungeonReadyDialogTimer()
	InitPVPReadyDialogTimer()
end

-- Configuration table
local db = {
	highlightPlayer = true, -- Enable player name highlighting
	useBrackets = true, -- Enable or disable wrapping with brackets
	highlightColor = "00ff00", -- Default highlight color (green)
	highlightGuild = true, -- Enable guild name highlighting
	playSound = true, -- Enable sound notification
	soundFile = 182876, -- Path to the sound file
	soundCooldown = 5, -- Cooldown in seconds between sound notifications
}

-- Timestamp for the last sound played
local lastSoundTime = 0

-- Function to wrap the name with optional brackets
local function wrapName(match)
	local color = db.highlightColor or "00ff00" -- Default to green if no color is set
	if db.useBrackets then
		return "|cff" .. color .. "[" .. match .. "]|r"
	else
		return "|cff" .. color .. match .. "|r"
	end
end

-- Function to handle guild tag highlighting
local function HighlightGuildTag(tag)
	local color = db.highlightColor or "00ff00" -- Use the same color for guilds
	return "|cff" .. color .. "<" .. tag .. ">|r"
end

-- Function to play sound with cooldown
local function PlayHighlightSound()
	if db.playSound then
		local currentTime = GetTime()
		if currentTime - lastSoundTime >= db.soundCooldown then
			local success = PlaySound(db.soundFile, "Master")
			if not success then
				print("Error: Failed to play sound. Check the file path.")
			else
				lastSoundTime = currentTime -- Update the timestamp
			end
		end
	end
end

-- Chat filter function
local function ChatFilter(_, _, message, ...)
	local playerName = UnitName("player")
	local nameHighlighted = false
	if db.highlightPlayer then
		-- Case-insensitive pattern matching for the player's name
		local playerNamePattern = playerName:gsub("%a", function(c)
			return "[" .. c:upper() .. c:lower() .. "]"
		end)
		-- Apply the wrapping logic and check if the name is found
		local newMessage = message:gsub(playerNamePattern, function(match)
			nameHighlighted = true
			return wrapName(match)
		end)
		message = newMessage
	end
	if db.highlightGuild then
		message = message:gsub("<(.-)>", HighlightGuildTag)
	end
	-- Play sound if the player's name was highlighted
	if nameHighlighted then
		PlayHighlightSound()
	end
	return false, message, ...
end

-- Event listener for player login
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
