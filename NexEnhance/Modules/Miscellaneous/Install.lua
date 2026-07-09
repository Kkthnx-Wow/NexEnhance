--[[
	NexEnhance - Install / First-Run
	-------------------------------------------------------------------------
	One-click welcome screen: applies recommended Blizzard CVars, raid frames,
	and the default chat layout, then reloads. Auto-opens once (ns.global.installed);
	reopen anytime with /nex install.
--]]

-- luacheck: globals ScrollUtil FCF_DockUpdate
---@diagnostic disable: undefined-field
local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local _G = _G
local pcall = pcall
local format = string.format
local SetCVar = SetCVar
local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local C_Timer = C_Timer
local C_PlayerInfo = C_PlayerInfo
local UnitRace = UnitRace
local PlaySound = PlaySound
local SOUNDKIT = SOUNDKIT

local INSTALL_SOUND = (SOUNDKIT and SOUNDKIT.UI_LEGENDARY_LOOT_TOAST) or 63971
local NUM_CHAT_WINDOWS = NUM_CHAT_WINDOWS
local GetChatWindowInfo = GetChatWindowInfo
local FCF_OpenNewWindow = FCF_OpenNewWindow
local FCF_SetWindowName = FCF_SetWindowName
local FCF_SetLocked = FCF_SetLocked
local FCF_DockFrame = FCF_DockFrame
local FCF_SelectDockFrame = FCF_SelectDockFrame
local ChatFrame_RemoveAllMessageGroups = ChatFrame_RemoveAllMessageGroups
local ChatFrame_RemoveChannel = ChatFrame_RemoveChannel
local ChatFrame_AddMessageGroup = ChatFrame_AddMessageGroup
local ChatFrame_AddChannel = ChatFrame_AddChannel
local ChangeChatColor = ChangeChatColor

local BACKDROP = C.Backdrops.window
local FRAME_W, FRAME_H = 640, 460

-- Dress-up player scene (Blizzard_DressUpFrame).
local DRESS_UP_SCENE_ID = 596

-- Player emote sequence: Wave (67) → Dance (69, loops). Same IDs as AFKCam.
local INSTALL_ANIMS = {
	{ id = 67, duration = 2.3 },
	{ id = 69 },
}

ns:RegisterDefaults({
	installed = false,
	setupComplete = false,
}, "global")

local Install = ns:NewModule("Install", "install", { group = "misc", order = 0 })

local APPLY_ORDER = { "blizzardQoL", "actionBars", "nameplates", "combatText", "raidFrames", "chatLayout" }

-- ---------------------------------------------------------------------------
-- Apply helpers
-- ---------------------------------------------------------------------------
local function SetCVarSafe(name, value)
	pcall(SetCVar, name, value)
end

local function ApplyBlizzardQoL()
	SetCVarSafe("autoLootDefault", 1)
	SetCVarSafe("alwaysCompareItems", 1)
	SetCVarSafe("autoSelfCast", 1)
	SetCVarSafe("lootUnderMouse", 1)
	SetCVarSafe("screenshotQuality", 10)
	SetCVarSafe("showTutorials", 0)
	SetCVarSafe("autoQuestWatch", 1)
end

local function ApplyActionBars()
	if InCombatLockdown() then
		return
	end
	SetCVarSafe("lockActionBars", 1)
	SetCVarSafe("alwaysShowActionBars", 1)
end

local function ApplyNameplates()
	if InCombatLockdown() then
		return
	end
	SetCVarSafe("nameplateMotion", 1)
	SetCVarSafe("nameplateShowAll", 1)
	SetCVarSafe("nameplateShowEnemies", 1)
end

local function ApplyCombatText()
	SetCVarSafe("floatingCombatTextFloatMode", 1)
	SetCVarSafe("floatingCombatTextCombatDamage", 1)
	SetCVarSafe("floatingCombatTextCombatHealing", 1)
	SetCVarSafe("floatingCombatTextCombatDamageDirectionalScale", 0)
	SetCVarSafe("floatingCombatTextCombatDamageDirectionalOffset", 10)
end

local function ApplyRaidFrames()
	if InCombatLockdown() then
		return
	end

	local profiles = _G.CompactUnitFrameProfiles
	if not profiles then
		return
	end

	SetCVarSafe("useCompactPartyFrames", 1)
	pcall(function()
		local selected = profiles.selectedProfile
		_G.SetRaidProfileOption(selected, "useClassColors", true)
		_G.SetRaidProfileOption(selected, "displayPowerBar", true)
		_G.SetRaidProfileOption(selected, "displayBorder", false)
		_G.CompactUnitFrameProfiles_ApplyCurrentSettings()
		_G.CompactUnitFrameProfiles_UpdateCurrentPanel()
	end)
end

local GENERAL_REMOVE_CHANNELS = {
	"LocalDefense",
	"GuildRecruitment",
	"LookingForGroup",
	"Services",
}

local GENERAL_MESSAGE_GROUPS = {
	"SAY",
	"EMOTE",
	"YELL",
	"GUILD",
	"OFFICER",
	"GUILD_ACHIEVEMENT",
	"MONSTER_SAY",
	"MONSTER_EMOTE",
	"MONSTER_YELL",
	"MONSTER_WHISPER",
	"MONSTER_BOSS_EMOTE",
	"MONSTER_BOSS_WHISPER",
	"PARTY",
	"PARTY_LEADER",
	"RAID",
	"RAID_LEADER",
	"RAID_WARNING",
	"INSTANCE_CHAT",
	"INSTANCE_CHAT_LEADER",
	"BG_HORDE",
	"BG_ALLIANCE",
	"BG_NEUTRAL",
	"SYSTEM",
	"ERRORS",
	"AFK",
	"DND",
	"IGNORED",
	"ACHIEVEMENT",
}

local WHISPER_MESSAGE_GROUPS = { "WHISPER", "BN_WHISPER", "BN_CONVERSATION" }

local LOOT_MESSAGE_GROUPS = {
	"COMBAT_XP_GAIN",
	"COMBAT_HONOR_GAIN",
	"COMBAT_FACTION_CHANGE",
	"LOOT",
	"MONEY",
	"SKILL",
}

-- Default channel tints for General, Trade, and Local Defense.
local CHAT_CHANNEL_COLORS = {
	{ "CHANNEL1", 0.76, 0.90, 0.91 },
	{ "CHANNEL2", 0.91, 0.62, 0.47 },
	{ "CHANNEL3", 0.91, 0.89, 0.47 },
}

local function ApplyChatColors()
	if not ChangeChatColor then
		return
	end
	for i = 1, #CHAT_CHANNEL_COLORS do
		local entry = CHAT_CHANNEL_COLORS[i]
		pcall(ChangeChatColor, entry[1], entry[2], entry[3], entry[4])
	end
end

local function AddMessageGroups(frame, groups)
	for i = 1, #groups do
		ChatFrame_AddMessageGroup(frame, groups[i])
	end
end

local function OpenChatWindow(name)
	for i = 1, NUM_CHAT_WINDOWS do
		if GetChatWindowInfo(i) == name then
			return _G["ChatFrame" .. i]
		end
	end
	return FCF_OpenNewWindow(name)
end

local function ApplyChatLayout()
	FCF_SetWindowName(ChatFrame1, L["General"])
	ChatFrame1:Show()

	ChatFrame_RemoveAllMessageGroups(ChatFrame1)
	ChatFrame_RemoveChannel(ChatFrame1, TRADE)
	ChatFrame_RemoveChannel(ChatFrame1, GENERAL)
	for i = 1, #GENERAL_REMOVE_CHANNELS do
		ChatFrame_RemoveChannel(ChatFrame1, GENERAL_REMOVE_CHANNELS[i])
	end
	AddMessageGroups(ChatFrame1, GENERAL_MESSAGE_GROUPS)

	FCF_DockFrame(ChatFrame2)
	FCF_SetLocked(ChatFrame2, true)
	FCF_SetWindowName(ChatFrame2, L["Combat"])
	ChatFrame2:Show()

	local whispers = OpenChatWindow(L["Whispers"])
	FCF_SetLocked(whispers, true)
	FCF_DockFrame(whispers)
	ChatFrame_RemoveAllMessageGroups(whispers)
	AddMessageGroups(whispers, WHISPER_MESSAGE_GROUPS)

	local trade = OpenChatWindow(L["Trade"])
	FCF_SetLocked(trade, true)
	FCF_DockFrame(trade)
	ChatFrame_RemoveAllMessageGroups(trade)
	ChatFrame_AddChannel(trade, TRADE)
	ChatFrame_AddChannel(trade, GENERAL)
	ChatFrame_AddChannel(trade, "Services")

	local loot = OpenChatWindow(L["Loot"])
	FCF_SetLocked(loot, true)
	FCF_DockFrame(loot)
	ChatFrame_RemoveAllMessageGroups(loot)
	AddMessageGroups(loot, LOOT_MESSAGE_GROUPS)

	DEFAULT_CHAT_FRAME:SetUserPlaced(true)

	SetCVarSafe("chatMouseScroll", 1)
	SetCVarSafe("chatStyle", "im")
	SetCVarSafe("WholeChatWindowClickable", 0)
	SetCVarSafe("WhisperMode", "inline")
	SetCVarSafe("removeChatDelay", 1)
	SetCVarSafe("colorChatNamesByClass", 0)
	SetCVarSafe("chatClassColorOverride", 0)
	SetCVarSafe("speechToText", 0)

	ApplyChatColors()

	local dock = _G.GENERAL_CHAT_DOCK
	if dock and FCFDock_GetSelectedWindow and FCFDock_GetSelectedWindow(dock) ~= ChatFrame1 then
		FCF_SelectDockFrame(ChatFrame1)
	elseif FCF_DockUpdate then
		FCF_DockUpdate()
	end
end

local function ForceChatLayout()
	if InCombatLockdown() then
		return
	end
	local ok = pcall(ApplyChatLayout)
	if ok and ns.charDB then
		ns.charDB.chatLayoutInstalled = true
	end
end

local APPLY_FNS = {
	blizzardQoL = ApplyBlizzardQoL,
	actionBars = ApplyActionBars,
	nameplates = ApplyNameplates,
	combatText = ApplyCombatText,
	raidFrames = ApplyRaidFrames,
	chatLayout = ForceChatLayout,
}

local SUMMARY_KEYS = {
	blizzardQoL = "Install option blizzard QoL",
	actionBars = "Install option action bars",
	nameplates = "Install option nameplates",
	combatText = "Install option combat text",
	raidFrames = "Install option raid frames",
	chatLayout = "Install option chat layout",
}

local function ApplyRecommended()
	for i = 1, #APPLY_ORDER do
		local fn = APPLY_FNS[APPLY_ORDER[i]]
		if fn then
			fn()
		end
	end
end

local function BuildSummaryText()
	local brand = C.BrandHex
	local lines = { L["Install welcome body intro"], "" }
	for i = 1, #APPLY_ORDER do
		local labelKey = SUMMARY_KEYS[APPLY_ORDER[i]]
		if labelKey then
			lines[#lines + 1] = format("|c%s•|r |cffe6e6e6%s|r", brand, L[labelKey])
		end
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = format("|cff909090%s|r", L["Choosing Install will reload your interface."])
	lines[#lines + 1] = format("|cff909090%s|r", L["Your other settings are left untouched. You can re-run this anytime with /nex install."])
	return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------------
-- Install welcome model (your character + wave / dance)
-- ---------------------------------------------------------------------------
local function StopInstallAnim(installFrame)
	installFrame.animToken = (installFrame.animToken or 0) + 1
	installFrame.animSequenceStarted = nil
end

local function PlayInstallAnimStep(installFrame, actor, stepIndex)
	local token = installFrame.animToken
	local step = INSTALL_ANIMS[stepIndex]
	if not step or not actor or token ~= installFrame.animToken then
		return
	end

	pcall(actor.SetAnimation, actor, step.id, 0, 1.0)

	if not step.duration then
		return
	end

	C_Timer.After(step.duration, function()
		if installFrame.animToken ~= token then
			return
		end
		PlayInstallAnimStep(installFrame, actor, stepIndex + 1)
	end)
end

local function StartInstallAnimSequence(installFrame, actor)
	StopInstallAnim(installFrame)
	PlayInstallAnimStep(installFrame, actor, 1)
end

local function ScheduleInstallAnims(installFrame, actor)
	if not actor then
		return
	end

	local function tryStart()
		if installFrame.playerActor ~= actor or installFrame.animSequenceStarted then
			return
		end
		installFrame.animSequenceStarted = true
		StartInstallAnimSequence(installFrame, actor)
	end

	if actor.SetOnModelLoadedCallback then
		actor:SetOnModelLoadedCallback(function()
			tryStart()
		end)
	end

	-- Fallback when the model is already resident (callback may not re-fire).
	C_Timer.After(0.2, tryStart)
end

local function GetPlayerModelSetup()
	local overrideActorName
	local useNativeForm = true

	if C_PlayerInfo and C_PlayerInfo.GetAlternateFormInfo then
		local hasAlternateForm, inAlternateForm = C_PlayerInfo.GetAlternateFormInfo()
		if hasAlternateForm and inAlternateForm then
			useNativeForm = false
		end
	end

	local _, raceFilename = UnitRace("player")
	if raceFilename and raceFilename:lower() == "dracthyr" then
		overrideActorName = "dracthyr-alt"
		useNativeForm = false
	end

	return overrideActorName, useNativeForm
end

local function RefreshInstallModel(installFrame)
	local scene = installFrame.modelScene
	if not scene or not _G.SetupPlayerForModelScene then
		return
	end

	StopInstallAnim(installFrame)

	scene:ClearScene()
	scene:SetViewInsets(0, 0, 0, 0)
	scene:ReleaseAllActors()

	local transitionType = _G.CAMERA_TRANSITION_TYPE_IMMEDIATE
		or (Enum.CameraTransitionType and Enum.CameraTransitionType.Immediately)
	local modificationType = _G.CAMERA_MODIFICATION_TYPE_DISCARD
		or (Enum.CameraModificationType and Enum.CameraModificationType.Discard)

	if scene.TransitionToModelSceneID then
		scene:TransitionToModelSceneID(DRESS_UP_SCENE_ID, transitionType, modificationType, true)
	else
		scene:SetFromModelSceneID(DRESS_UP_SCENE_ID, true)
	end

	local overrideActorName, useNativeForm = GetPlayerModelSetup()
	-- Match DressUpFrame_Show: always auto-dress the player unit (scene flags omit Autodress).
	local sheatheWeapons, autoDress, hideWeapons = false, true, false

	SetupPlayerForModelScene(
		scene,
		overrideActorName,
		nil,
		sheatheWeapons,
		autoDress,
		hideWeapons,
		useNativeForm
	)

	local actor = scene:GetPlayerActor(overrideActorName)
	installFrame.playerActor = actor
	scene.playerActor = actor

	if actor then
		pcall(actor.SetSheathed, actor, true)
		ScheduleInstallAnims(installFrame, actor)
	end
end

-- ---------------------------------------------------------------------------
-- UI
-- ---------------------------------------------------------------------------
local frame

local function Build()
	if frame then
		return frame
	end

	frame = CreateFrame("Frame", "NexEnhanceInstall", UIParent, "BackdropTemplate")
	frame:SetSize(FRAME_W, FRAME_H)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetToplevel(true)
	frame:Hide()
	frame:SetBackdrop(BACKDROP)
	frame:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
	frame:SetBackdropBorderColor(1, 1, 1)

	local glow = CreateFrame("Frame", nil, frame)
	glow:SetAllPoints(frame)
	glow:SetFrameLevel(frame:GetFrameLevel() - 1)
	glow:SetAlpha(0.90)
	F.CreateGlowBorder(glow, { outset = 4, blend = "BLEND", color = C.Colors.brand })

	F.MakeWindowMovable(frame, "NexEnhanceInstall")

	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	frame:SetScript("OnEvent", function(self, event)
		if event == "PLAYER_REGEN_DISABLED" then
			if self:IsShown() then
				self.showAfterCombat = true
				self:Hide()
			end
		elseif event == "PLAYER_REGEN_ENABLED" and self.showAfterCombat and not self:IsShown() then
			self.showAfterCombat = nil
			self:Show()
			if _G.UIFrameFadeIn then
				_G.UIFrameFadeIn(self, 0.25, 0, 1)
			end
		end
	end)

	local logo = frame:CreateTexture(nil, "ARTWORK")
	logo:SetSize(56, 56)
	logo:SetPoint("TOPLEFT", 16, -14)
	logo:SetTexture(C.Media.Textures.logo)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -6)
	title:SetText(L["Welcome to NexEnhance"])

	local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -6)
	sub:SetFormattedText("%s |c%s%s|r", L["Version"], C.BrandHex, ns.version)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	local divider = frame:CreateTexture(nil, "ARTWORK")
	divider:SetColorTexture(C.Colors.brand[1], C.Colors.brand[2], C.Colors.brand[3], 0.55)
	divider:SetHeight(2)
	divider:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -12)
	divider:SetPoint("RIGHT", frame, "RIGHT", -16, 0)

	local welcomeTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	welcomeTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -108)
	welcomeTitle:SetText(L["Install wizard welcome title"])

	frame.modelHolder = CreateFrame("Frame", nil, frame)
	frame.modelHolder:SetSize(200, 280)
	frame.modelHolder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 52)

	frame.modelScene = CreateFrame("ModelScene", nil, frame.modelHolder, "NonInteractableModelSceneMixinTemplate")
	frame.modelScene:SetAllPoints(frame.modelHolder)
	frame.modelScene:SetFrameLevel(frame.modelHolder:GetFrameLevel() + 1)
	frame.modelScene:EnableMouse(false)

	local body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	body:SetPoint("TOPLEFT", welcomeTitle, "BOTTOMLEFT", 0, -12)
	body:SetPoint("RIGHT", frame.modelHolder, "LEFT", -16, 0)
	body:SetJustifyH("LEFT")
	body:SetJustifyV("TOP")
	body:SetSpacing(4)
	body:SetText(BuildSummaryText())

	frame:SetScript("OnShow", function(self)
		RefreshInstallModel(self)
	end)
	frame:SetScript("OnHide", function(self)
		StopInstallAnim(self)
		if self.modelScene then
			self.modelScene.playerActor = nil
		end
		self.playerActor = nil
		if self.showAfterCombat then
			return
		end
		if ns.global then
			ns.global.installed = true
		end
	end)

	frame.skipBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.skipBtn:SetSize(120, 26)
	frame.skipBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 16)
	frame.skipBtn:SetText(L["Not Now"])
	frame.skipBtn:SetScript("OnClick", function()
		frame:Hide()
	end)

	frame.installBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.installBtn:SetSize(120, 26)
	frame.installBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 16)
	frame.installBtn:SetText(L["Install"])
	frame.installBtn:SetScript("OnClick", function(self)
		if InCombatLockdown() then
			return
		end

		PlaySound(INSTALL_SOUND, "Master")
		self:Disable()
		frame.skipBtn:Disable()

		ApplyRecommended()
		if ns.global then
			ns.global.installed = true
			ns.global.setupComplete = true
		end

		_G.ReloadUI()
	end)

	return frame
end

function ns:OpenInstall()
	local f = Build()
	if f:IsShown() then
		f:Hide()
		return
	end

	f.installBtn:Enable()
	f.skipBtn:Enable()

	if InCombatLockdown() then
		f.showAfterCombat = true
		F.Print(L["Setup will open when you leave combat."])
		return
	end

	f:Show()
	if _G.UIFrameFadeIn then
		_G.UIFrameFadeIn(f, 0.25, 0, 1)
	end
end

function Install:OnEnable()
	-- Prefix is already Nex (brand) + Enhance (gold). Body stays white so the
	-- name colours read; version is muted gold like TOC "Enhance".
	F.Print(format(
		"|cffffffff%s|r  |cffaaaaaa/nex|r  |c%sv%s|r",
		L["Loaded."],
		C.HeaderHex,
		ns.version or "?"
	))

	if ns.global and not ns.global.installed then
		C_Timer.After(1.5, function()
			if ns.global and not ns.global.installed then
				ns:OpenInstall()
			end
		end)
	end

	if ns.global and ns.global.setupComplete and ns.charDB and not ns.charDB.chatLayoutInstalled then
		C_Timer.After(1.5, function()
			if ns.global and ns.global.setupComplete and ns.charDB and not ns.charDB.chatLayoutInstalled then
				ForceChatLayout()
			end
		end)
	end
end
