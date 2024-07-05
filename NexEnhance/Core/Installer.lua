local AddonName, Core = ...

TOOLTIP_AZERITE_BACKGROUND_COLOR = CreateColor(1, 1, 1)
GAME_TOOLTIP_BACKDROP_STYLE_AZERITE_ITEM = {
	bgFile = "Interface/Tooltips/UI-Tooltip-Background-Azerite",
	edgeFile = "Interface/Tooltips/UI-Tooltip-Border-Azerite",
	tile = true,
	tileEdge = false,
	tileSize = 16,
	edgeSize = 19,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function CreateSplashScreen()
	local splash = CreateFrame("Frame", "NE_SplashScreen", UIParent, "BackdropTemplate")
	splash:SetSize(400, 200)
	splash:SetPoint("CENTER")
	splash:SetBackdrop(GAME_TOOLTIP_BACKDROP_STYLE_AZERITE_ITEM)
	splash:SetBackdropBorderColor((TOOLTIP_DEFAULT_COLOR):GetRGB())
	splash:SetBackdropColor((TOOLTIP_AZERITE_BACKGROUND_COLOR):GetRGB())

	splash.top = splash:CreateTexture(nil, "ARTWORK")
	splash.top:SetPoint("TOP", 0, 16)
	splash.top:SetAtlas("AzeriteTooltip-Topper", true)
	splash.top:SetScale(0.75)

	splash.bottom = splash:CreateTexture(nil, "ARTWORK")
	splash.bottom:SetPoint("BOTTOM", 0, -6)
	splash.bottom:SetAtlas("AzeriteTooltip-Bottom", true)
	splash.bottom:SetScale(1)

	splash.text = splash:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	splash.text:SetPoint("TOP", 0, -16)
	splash.text:SetText("Welcome to " .. Core.InfoColor .. AddonName .. ",|r " .. Core.MyClassColor .. Core.MyName .. "|r")

	splash.desc = splash:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	splash.desc:SetPoint("TOP", splash.text, "BOTTOM", 0, -16)
	splash.desc:SetWidth(370)
	splash.desc:SetJustifyH("CENTER")
	splash.desc:SetText("Click the button below to configure your interface with the recommended settings for an optimized and enhanced gaming experience.|n|nThis step is essential to ensure all features and enhancements are applied correctly.")

	splash.logo = splash:CreateTexture(nil, "BACKGROUND")
	splash.logo:SetBlendMode("ADD")
	splash.logo:SetAlpha(0.08)
	splash.logo:SetScale(0.7)
	splash.logo:SetTexture(Core.Logo256)
	splash.logo:SetPoint("CENTER")

	local button = CreateFrame("Button", nil, splash, "UIPanelButtonTemplate")
	button:SetSize(160, 36)
	button:SetPoint("BOTTOM", 0, 16)
	button:SetText("Apply Settings")

	button:SetScript("OnClick", function()
		Core:ForceDefaultCVars()
		Core:ForceChatSettings()
		PlaySound(21968)
		Core.db.profile.settingsApplied = true
		splash:Hide()
		ReloadUI()
	end)

	return splash
end

function Core:ForceDefaultCVars()
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
		Core:Print("Skipped setting combat CVars due to combat lockdown.")
	end

	-- Apply developer-specific CVars if isDeveloper is true
	if Core.isDeveloper then
		for _, cvar in pairs(developerCVars) do
			SetCVar(cvar[1], cvar[2])
		end
	else
		Core:Print("Skipped setting developer CVars as isDeveloper is not true.")
	end
end

function Core:ForceChatSettings()
	local function resetAndConfigureChatFrames()
		FCF_ResetChatWindows()

		for _, name in ipairs(_G.CHAT_FRAMES) do
			local frame = _G[name]

			if frame.Tab then -- only Voice has .Tab
				FCF_UnDockFrame(frame)
				FCF_SetLocked(frame, false)
				FCF_Close(frame)
			end

			-- Common configuration for all frames
			FCF_SetChatWindowFontSize(nil, frame, 12)
		end

		FCF_SelectDockFrame(ChatFrame1)
	end

	local function configureChatFrame(chatFrame, windowName, removeChannels, messageGroups, isDocked)
		-- Configuration for individual chat frames
		if isDocked then
			FCF_DockFrame(chatFrame)
		else
			FCF_OpenNewWindow(windowName)
		end

		FCF_SetLocked(chatFrame, true)
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

		FCF_SelectDockFrame(ChatFrame1)
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
	configureChatFrame(ChatFrame1, Core.L["General"], { "Trade", "Services", "General", "GuildRecruitment", "LookingForGroup" }, { "ACHIEVEMENT", "AFK", "BG_ALLIANCE", "BG_HORDE", "BG_NEUTRAL", "BN_INLINE_TOAST_ALERT", "CHANNEL", "DND", "EMOTE", "ERRORS", "GUILD", "GUILD_ACHIEVEMENT", "IGNORED", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "MONSTER_BOSS_EMOTE", "MONSTER_BOSS_WHISPER", "MONSTER_EMOTE", "MONSTER_SAY", "MONSTER_WHISPER", "MONSTER_YELL", "OFFICER", "PARTY", "PARTY_LEADER", "PING", "RAID", "RAID_LEADER", "RAID_WARNING", "SAY", "SYSTEM", "YELL" })
	configureChatFrame(ChatFrame2, Core.L["Log"], nil, {}, true)
	configureChatFrame(ChatFrame4, Core.L["Whisper"], nil, { "WHISPER", "BN_WHISPER", "BN_CONVERSATION" }, true)
	configureChatFrame(ChatFrame5, Core.L["Trade"], nil, {}, true)
	configureChatFrame(ChatFrame6, Core.L["Loot"], nil, { "COMBAT_XP_GAIN", "COMBAT_HONOR_GAIN", "COMBAT_FACTION_CHANGE", "SKILL", "LOOT", "CURRENCY", "MONEY" }, true)

	configureChatColors()
	local classColorGroups = { "SAY", "EMOTE", "YELL", "WHISPER", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "GUILD", "OFFICER", "ACHIEVEMENT", "GUILD_ACHIEVEMENT", "COMMUNITIES_CHANNEL" }
	local maxChatChannels = _G.MAX_WOW_CHAT_CHANNELS or 10 -- Fallback in case the global isn't set
	for i = 1, maxChatChannels do
		table.insert(classColorGroups, "CHANNEL" .. i)
	end
	enableClassColors(classColorGroups)
end

function Core:OnLogin()
	if not Core.db.profile.settingsApplied then
		local splash = CreateSplashScreen()
		splash:Show()
	else
		Core:Print(Core.InfoColor .. "v" .. Core.SystemColor .. C_AddOns.GetAddOnMetadata(AddonName, "Version"))
	end
end

Core:RegisterSlash("/nexinstall", function()
	local splash = CreateSplashScreen()
	if not splash:IsShown() then
		splash:Show()
	end
end)
