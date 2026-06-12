--[[
	NexEnhance - Install / First-Run
	-------------------------------------------------------------------------
	A one-time, account-wide welcome screen that applies a set of recommended
	CVars, class-coloured raid frames and the default chat layout. Once it has
	been completed or dismissed it never auto-opens again (tracked in
	ns.global.installed); it can always be re-opened with /nex install. Completed
	installs are tracked separately from dismissed prompts, and the chat layout is
	tracked per-character because Blizzard stores chat windows per character.

	Recommended-settings list adapted from NDui's tutorial by siweia:
	  https://github.com/siweia/NDui

	Every SetCVar is wrapped so a CVar that no longer exists on the live client
	can't abort the rest of the routine.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local _G = _G
local pcall = pcall
local format = string.format
local tconcat = table.concat
local SetCVar = SetCVar
local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local C_Timer = C_Timer
local PlaySound = PlaySound
local SOUNDKIT = SOUNDKIT

-- A short, celebratory toast for confirming the install (same flourish the
-- login logo flyby uses). Fall back to a raw kit id on older clients.
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

ns:RegisterDefaults({ installed = false, setupComplete = false }, "global")

local Install = ns:NewModule("Install", "install", { group = "misc", order = 0 })

-- ---------------------------------------------------------------------------
-- Recommended settings
-- ---------------------------------------------------------------------------
local function SetCVarSafe(name, value)
	pcall(SetCVar, name, value)
end

local function ForceDefaultSettings()
	SetCVarSafe("autoLootDefault", 1)
	SetCVarSafe("alwaysCompareItems", 1)
	SetCVarSafe("autoSelfCast", 1)
	SetCVarSafe("lootUnderMouse", 1)
	SetCVarSafe("screenshotQuality", 10)
	SetCVarSafe("showTutorials", 0)
	SetCVarSafe("lockActionBars", 1)
	SetCVarSafe("autoQuestWatch", 1)
	SetCVarSafe("floatingCombatTextFloatMode", 1)
	SetCVarSafe("floatingCombatTextCombatDamage", 1)
	SetCVarSafe("floatingCombatTextCombatHealing", 1)
	SetCVarSafe("floatingCombatTextCombatDamageDirectionalScale", 0)
	SetCVarSafe("floatingCombatTextCombatDamageDirectionalOffset", 10)

	-- These are protected during combat.
	if not InCombatLockdown() then
		SetCVarSafe("nameplateMotion", 1)
		SetCVarSafe("nameplateShowAll", 1)
		SetCVarSafe("nameplateShowEnemies", 1)
		SetCVarSafe("alwaysShowActionBars", 1)
	end
end

local function ForceRaidFrame()
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

-- ---------------------------------------------------------------------------
-- Chat layout
-- A sorted, four-window dock (General / Whispers / Trade / Loot) plus a locked
-- Combat Log, with a handful of chat CVars. Group lists are preallocated so the
-- routine is just a couple of tight loops. Adapted from NDui by siweia.
-- ---------------------------------------------------------------------------
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

local function AddMessageGroups(frame, groups)
	for i = 1, #groups do
		ChatFrame_AddMessageGroup(frame, groups[i])
	end
end

-- Reuse a window already named `name` instead of opening a fresh one, so
-- re-running /nex install never stacks up duplicate Whisper/Trade/Loot tabs.
local function OpenChatWindow(name)
	for i = 1, NUM_CHAT_WINDOWS do
		if GetChatWindowInfo(i) == name then
			return _G["ChatFrame" .. i]
		end
	end
	return FCF_OpenNewWindow(name)
end

local function ApplyChatLayout()
	-- General (ChatFrame1)
	FCF_SetWindowName(ChatFrame1, L["General"])
	ChatFrame1:Show()

	ChatFrame_RemoveAllMessageGroups(ChatFrame1)
	ChatFrame_RemoveChannel(ChatFrame1, TRADE)
	ChatFrame_RemoveChannel(ChatFrame1, GENERAL)
	for i = 1, #GENERAL_REMOVE_CHANNELS do
		ChatFrame_RemoveChannel(ChatFrame1, GENERAL_REMOVE_CHANNELS[i])
	end
	AddMessageGroups(ChatFrame1, GENERAL_MESSAGE_GROUPS)

	-- Combat Log (ChatFrame2)
	FCF_DockFrame(ChatFrame2)
	FCF_SetLocked(ChatFrame2, true)
	FCF_SetWindowName(ChatFrame2, L["Combat"])
	ChatFrame2:Show()

	-- Whispers
	local whispers = OpenChatWindow(L["Whispers"])
	FCF_SetLocked(whispers, true)
	FCF_DockFrame(whispers)
	ChatFrame_RemoveAllMessageGroups(whispers)
	AddMessageGroups(whispers, WHISPER_MESSAGE_GROUPS)

	-- Trade
	local trade = OpenChatWindow(L["Trade"])
	FCF_SetLocked(trade, true)
	FCF_DockFrame(trade)
	ChatFrame_RemoveAllMessageGroups(trade)
	ChatFrame_AddChannel(trade, TRADE)
	ChatFrame_AddChannel(trade, GENERAL)
	ChatFrame_AddChannel(trade, "Services")

	-- Loot
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

	FCF_SelectDockFrame(ChatFrame1)
end

local function ForceChatLayout()
	if InCombatLockdown() then
		return
	end
	-- Wrapped so a renamed/removed Blizzard chat API can't abort the install.
	local ok = pcall(ApplyChatLayout)
	if ok and ns.charDB then
		ns.charDB.chatLayoutInstalled = true
	end
end

local function ApplyAll()
	ForceDefaultSettings()
	ForceRaidFrame()
	ForceChatLayout()
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------
local BACKDROP = C.Backdrops.window

local function BuildBody()
	local brand = C.BrandHex
	local lines = {
		format("|cffffffff%s|r", L["Set up NexEnhance with a handful of recommended Blizzard settings:"]),
		" ",
		format("|c%s-|r |cffe6e6e6%s|r", brand, L["Auto-loot, compare items on hover and self-cast on right-click."]),
		format("|c%s-|r |cffe6e6e6%s|r", brand, L["Locked action bars that are always shown, with cleaner combat text."]),
		format("|c%s-|r |cffe6e6e6%s|r", brand, L["Moving nameplates that show all enemies."]),
		format("|c%s-|r |cffe6e6e6%s|r", brand, L["Class-coloured raid frames with power bars and no clutter."]),
		format("|c%s-|r |cffe6e6e6%s|r", brand, L["Sorted chat windows: General, Whispers, Trade and Loot."]),
		" ",
		format("|cff909090%s|r", L["Your other settings are left untouched. You can re-run this anytime with /nex install."]),
		format("|cff909090%s|r", L["Choosing Install will reload your interface."]),
	}
	return tconcat(lines, "\n")
end

local frame
local function Build()
	if frame then
		return frame
	end

	frame = CreateFrame("Frame", "NexEnhanceInstall", UIParent, "BackdropTemplate")
	frame:SetSize(520, 420)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetToplevel(true)
	frame:Hide()
	frame:SetBackdrop(BACKDROP)
	frame:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
	frame:SetBackdropBorderColor(1, 1, 1)
	F.MakeWindowMovable(frame, "NexEnhanceInstall") -- draggable + Escape-close

	-- Any close (button, Escape, reload) marks the prompt as seen - except a
	-- temporary combat auto-hide, which should reopen afterwards untouched.
	frame:SetScript("OnHide", function(self)
		if self.showAfterCombat then
			return
		end
		if ns.global then
			ns.global.installed = true
		end
	end)

	-- If we log straight into a fight, tuck the prompt away so it isn't in the
	-- way, then bring it back once combat ends. `showAfterCombat` also marks a
	-- show request that arrived during combat (see ns:OpenInstall).
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	frame:SetScript("OnEvent", function(self, event)
		if event == "PLAYER_REGEN_DISABLED" then
			if self:IsShown() then
				self.showAfterCombat = true
				self:Hide()
			end
		elseif event == "PLAYER_REGEN_ENABLED" then
			if self.showAfterCombat and not self:IsShown() then
				self.showAfterCombat = nil
				self:Show()
				if _G.UIFrameFadeIn then
					_G.UIFrameFadeIn(self, 0.25, 0, 1)
				end
			end
		end
	end)

	local logo = frame:CreateTexture(nil, "ARTWORK")
	logo:SetSize(60, 60)
	logo:SetPoint("TOPLEFT", 18, -16)
	logo:SetTexture(C.Media.Textures.logo)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 14, -4)
	title:SetText(L["Welcome to NexEnhance"])

	local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -6)
	sub:SetFormattedText("%s |c%s%s|r", L["Version"], C.BrandHex, ns.version)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	local divider = frame:CreateTexture(nil, "ARTWORK")
	divider:SetColorTexture(C.Colors.brand[1], C.Colors.brand[2], C.Colors.brand[3], 0.55)
	divider:SetHeight(2)
	divider:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -14)
	divider:SetPoint("RIGHT", frame, "RIGHT", -18, 0)

	local body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	body:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 2, -14)
	body:SetPoint("RIGHT", frame, "RIGHT", -18, 0)
	body:SetJustifyH("LEFT")
	body:SetJustifyV("TOP")
	body:SetSpacing(5)
	body:SetText(BuildBody())

	local skip = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	skip:SetSize(150, 26)
	skip:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 8, 16)
	skip:SetText(L["Not Now"])
	skip:SetScript("OnClick", function()
		frame:Hide()
	end)

	local install = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	install:SetSize(150, 26)
	install:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -8, 16)
	install:SetText(L["Install"])
	install:SetScript("OnClick", function(self)
		-- ApplyAll touches combat-protected settings, so never run mid-fight
		-- (the prompt auto-hides in combat, so this is just belt-and-braces).
		if InCombatLockdown() then
			return
		end

		PlaySound(INSTALL_SOUND, "Master")
		self:Disable()
		skip:Disable()

		ApplyAll()
		if ns.global then
			ns.global.installed = true
			ns.global.setupComplete = true
		end

		-- ReloadUI() is hardware-event restricted (protected 'Reload()'): it only
		-- succeeds when called synchronously inside the input that triggered it.
		-- A C_Timer callback has no hardware event behind it, so a delayed reload
		-- is blocked (ADDON_ACTION_BLOCKED). Reload now, on this button click.
		_G.ReloadUI()
	end)

	return frame
end

-- Public: open / toggle the window (used by the /nex install handler).
function ns:OpenInstall()
	local f = Build()
	if f:IsShown() then
		f:Hide()
		return
	end

	-- Don't pop the prompt up mid-fight; flag it to open once combat ends.
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
	-- One short, friendly greeting per session.
	F.Print(format("%s  |cff909090%s|r", F.Colorize(L["Loaded. Type /nex for options."], "brand"), ns.version))

	-- First run on this account: present the welcome screen.
	if ns.global and not ns.global.installed then
		C_Timer.After(1.5, function()
			if not ns.global.installed then
				ns:OpenInstall()
			end
		end)
	end

	-- Chat windows are character-specific, so apply the default chat layout once
	-- per character even when the account-wide welcome screen has already run.
	if ns.global and ns.global.setupComplete and ns.charDB and not ns.charDB.chatLayoutInstalled then
		C_Timer.After(1.5, function()
			if ns.global and ns.global.setupComplete and ns.charDB and not ns.charDB.chatLayoutInstalled then
				ForceChatLayout()
			end
		end)
	end
end
