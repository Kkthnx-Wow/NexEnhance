local _, Personal = ...

StaticPopupDialogs["NEXENHANCE_RELOAD"] = {
	text = "Changes have been made that require a reload.",
	button1 = ACCEPT,
	button2 = CANCEL,
	OnAccept = function()
		ReloadUI()
	end,
	hideOnEscape = false,
	whileDead = 1,
	preferredIndex = 3,
}

local function CreateSplashScreen()
	local splash = CreateFrame("Frame", "PersonalSplashScreen", UIParent, "BackdropTemplate")
	splash:SetSize(400, 200)
	splash:SetPoint("CENTER")
	splash:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})

	splash.text = splash:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	splash.text:SetPoint("TOP", 0, -16)
	splash.text:SetText("Welcome to NexEnhance")

	splash.desc = splash:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	splash.desc:SetPoint("TOP", splash.text, "BOTTOM", 0, -8)
	splash.desc:SetText("Click the button below to apply the default settings.")

	local button = CreateFrame("Button", nil, splash, "UIPanelButtonTemplate")
	button:SetSize(200, 40)
	button:SetPoint("BOTTOM", 0, 16)
	button:SetText("Apply Settings")

	button:SetScript("OnClick", function()
		Personal:ForceDefaultCVars()
		Personal:ForceChatSettings()
		PlaySound(21968)
		Personal.db.profile.settingsApplied = true
		splash:Hide()
		StaticPopup_Show("NEXENHANCE_RELOAD")
	end)

	return splash
end

function Personal:ForceDefaultCVars()
	local defaultCVars = {
		{ "RotateMinimap", 0 },
		{ "ShowClassColorInNameplate", 1 },
		{ "UberTooltips", 1 },
		{ "WholeChatWindowClickable", 0 },
		{ "alwaysCompareItems", 1 },
		{ "autoLootDefault", 1 },
		{ "autoOpenLootHistory", 0 },
		{ "autoQuestProgress", 1 },
		{ "autoQuestWatch", 1 },
		{ "autoSelfCast", 1 },
		{ "buffDurations", 1 },
		{ "cameraDistanceMaxZoomFactor", 2.6 },
		{ "cameraSmoothStyle", 0 },
		{ "colorblindMode", 0 },
		{ "floatingCombatTextCombatDamage", 1 },
		{ "floatingCombatTextCombatDamageDirectionalOffset", 10 },
		{ "floatingCombatTextCombatDamageDirectionalScale", 0 },
		{ "floatingCombatTextCombatHealing", 1 },
		{ "floatingCombatTextFloatMode", 1 },
		{ "gameTip", 0 },
		{ "instantQuestText", 1 },
		{ "lockActionBars", 1 },
		{ "lootUnderMouse", 1 },
		{ "lossOfControl", 0 },
		{ "overrideArchive", 0 },
		{ "profanityFilter", 0 },
		{ "removeChatDelay", 1 },
		{ "screenshotQuality", 10 },
		{ "scriptErrors", 1 },
		{ "showArenaEnemyFrames", 0 },
		{ "showLootSpam", 1 },
		{ "showTutorials", 0 },
		{ "showVKeyCastbar", 1 },
		{ "spamFilter", 0 },
		{ "taintLog", 0 },
		{ "violenceLevel", 5 },
		{ "whisperMode", "inline" },
		{ "ActionButtonUseKeyDown", 1 },
		{ "fstack_preferParentKeys", 0 },
		{ "showNPETutorials", 0 },
		{ "statusTextDisplay", "BOTH" },
		{ "threatWarning", 3 },
	}

	local combatCVars = {
		{ "nameplateShowEnemyMinions", 1 },
		{ "nameplateShowEnemyMinus", 1 },
		{ "nameplateShowFriendlyMinions", 0 },
		{ "nameplateShowFriends", 0 },
		{ "nameplateMotion", 1 },
		{ "nameplateShowAll", 1 },
		{ "nameplateShowEnemies", 1 },
		{ "alwaysShowActionBars", 1 },
	}

	local developerCVars = {
		{ "ffxGlow", 0 },
		{ "WorldTextScale", 1 },
		{ "SpellQueueWindow", 25 },
	}

	-- Apply default CVars
	for _, cvar in pairs(defaultCVars) do
		SetCVar(cvar[1], cvar[2])
	end

	-- Apply combat-related CVars if not in combat
	if not InCombatLockdown() then
		for _, cvar in pairs(combatCVars) do
			SetCVar(cvar[1], cvar[2])
		end
	else
		Personal:Print("Skipped setting combat CVars due to combat lockdown.")
	end

	-- Apply developer-specific CVars if Personal.isDeveloper is true
	if Personal.isDeveloper then
		for _, cvar in pairs(developerCVars) do
			SetCVar(cvar[1], cvar[2])
		end
	else
		Personal:Print("Skipped setting developer CVars as Personal.isDeveloper is not true.")
	end
end

function Personal:ForceChatSettings()
	local function resetAndConfigureChatFrames()
		FCF_ResetChatWindows()

		for _, name in ipairs(_G.CHAT_FRAMES) do
			local frame = _G[name]
			local id = frame:GetID()

			-- Configure specific frames based on their IDs
			if id == 1 then
				frame:ClearAllPoints()
				frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 7, 11)
			elseif id == 2 then
				FCF_SetWindowName(frame, Personal.L["CombatLog"])
			elseif id == 3 then
				-- Voice transcription specific settings
				VoiceTranscriptionFrame_UpdateVisibility(frame)
				VoiceTranscriptionFrame_UpdateVoiceTab(frame)
				VoiceTranscriptionFrame_UpdateEditBox(frame)
			end

			-- Common configuration for all frames
			FCF_SetChatWindowFontSize(nil, frame, 12)
			FCF_SavePositionAndDimensions(frame)
			FCF_StopDragging(frame)
		end
	end

	local function configureChatFrame(chatFrame, windowName, removeChannels, messageGroups, isDocked)
		-- Configuration for individual chat frames
		if isDocked then
			FCF_DockFrame(chatFrame)
		else
			FCF_OpenNewWindow(windowName)
		end

		FCF_SetLocked(chatFrame, 1)
		FCF_SetWindowName(chatFrame, windowName)
		chatFrame:Show()

		-- Remove specified channels and add message groups
		for _, channel in ipairs(removeChannels or {}) do
			ChatFrame_RemoveChannel(chatFrame, channel)
		end

		ChatFrame_RemoveAllMessageGroups(chatFrame)
		for _, group in ipairs(messageGroups) do
			ChatFrame_AddMessageGroup(chatFrame, group)
		end
	end

	local function configureChatColors()
		-- Set specific colors for chat channels
		ChangeChatColor("CHANNEL1", 195 / 255, 230 / 255, 232 / 255) -- General
		ChangeChatColor("CHANNEL2", 232 / 255, 158 / 255, 121 / 255) -- Trade
		ChangeChatColor("CHANNEL3", 232 / 255, 228 / 255, 121 / 255) -- Local Defense
	end

	local function enableClassColors(chatGroups)
		-- Enable class colors for specified chat groups
		for _, group in ipairs(chatGroups) do
			ToggleChatColorNamesByClassGroup(true, group)
		end
	end

	-- Apply configurations
	resetAndConfigureChatFrames()

	-- Configure specific chat frames
	configureChatFrame(ChatFrame1, "General", { "Trade", "Services", "General", "GuildRecruitment", "LookingForGroup" }, { "ACHIEVEMENT", "AFK", "BG_ALLIANCE", "BG_HORDE", "BG_NEUTRAL", "BN_INLINE_TOAST_ALERT", "CHANNEL", "DND", "EMOTE", "ERRORS", "GUILD", "GUILD_ACHIEVEMENT", "IGNORED", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "MONSTER_BOSS_EMOTE", "MONSTER_BOSS_WHISPER", "MONSTER_EMOTE", "MONSTER_SAY", "MONSTER_WHISPER", "MONSTER_YELL", "OFFICER", "PARTY", "PARTY_LEADER", "PING", "RAID", "RAID_LEADER", "RAID_WARNING", "SAY", "SYSTEM", "YELL" })
	configureChatFrame(ChatFrame2, "CombatLog", nil, {}, true)
	configureChatFrame(ChatFrame4, "Whisper", nil, { "WHISPER", "BN_WHISPER", "BN_CONVERSATION" }, true)
	configureChatFrame(ChatFrame5, "Trade", nil, {}, true)
	configureChatFrame(ChatFrame6, "Loot", nil, { "COMBAT_XP_GAIN", "COMBAT_HONOR_GAIN", "COMBAT_FACTION_CHANGE", "SKILL", "LOOT", "CURRENCY", "MONEY" }, true)

	configureChatColors()
	local classColorGroups = { "SAY", "EMOTE", "YELL", "WHISPER", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "GUILD", "OFFICER", "ACHIEVEMENT", "GUILD_ACHIEVEMENT", "COMMUNITIES_CHANNEL" }
	local maxChatChannels = _G.MAX_WOW_CHAT_CHANNELS or 10 -- Fallback in case the global isn't set
	for i = 1, maxChatChannels do
		table.insert(classColorGroups, "CHANNEL" .. i)
	end
	enableClassColors(classColorGroups)
end

function Personal:PLAYER_LOGIN()
	if not Personal.db.profile.settingsApplied then
		local splash = CreateSplashScreen()
		splash:Show()
	end
	-- else
	-- 	C_Timer.After(1, function()
	-- 		Personal:ForceDefaultCVars()
	-- 		Personal:ForceChatSettings()
	-- 		PlaySound(21968)
	-- 		Personal:Print("Personal setup completed. Default CVars and Chat Settings applied.")
	-- 		StaticPopup_Show("NEXENHANCE_RELOAD")
	-- 	end)
	-- end
end
