--[[
	NexEnhance - Install / First-Run
	-------------------------------------------------------------------------
	A one-time, account-wide welcome screen that applies a set of recommended
	CVars and class-coloured raid frames. Once it has been completed or
	dismissed it never auto-opens again (tracked in ns.global.installed); it can
	always be re-opened with /nex install.

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
local tinsert = table.insert
local SetCVar = SetCVar
local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local C_Timer = C_Timer

ns:RegisterDefaults({ installed = false }, "global")

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
	if InCombatLockdown() then return end

	local profiles = _G.CompactUnitFrameProfiles
	if not profiles then return end

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

local function ApplyAll()
	ForceDefaultSettings()
	ForceRaidFrame()
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------
local BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true,
	tileSize = 16,
	edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function BuildBody()
	local brand = C.BrandHex
	local lines = {
		format("|cffffffff%s|r", L["Set up NexEnhance with a handful of recommended Blizzard settings:"]),
		" ",
		format("|c%s-|r |cffe6e6e6%s|r", brand, L["Auto-loot, compare items on hover and self-cast on right-click."]),
		format("|c%s-|r |cffe6e6e6%s|r", brand, L["Locked action bars that are always shown, with cleaner combat text."]),
		format("|c%s-|r |cffe6e6e6%s|r", brand, L["Moving nameplates that show all enemies."]),
		format("|c%s-|r |cffe6e6e6%s|r", brand, L["Class-coloured raid frames with power bars and no clutter."]),
		" ",
		format("|cff909090%s|r", L["Your other settings are left untouched. You can re-run this anytime with /nex install."]),
		format("|cff909090%s|r", L["Choosing Install will reload your interface."]),
	}
	return tconcat(lines, "\n")
end

local frame
local function Build()
	if frame then return frame end

	frame = CreateFrame("Frame", "NexEnhanceInstall", UIParent, "BackdropTemplate")
	frame:SetSize(520, 420)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetToplevel(true)
	frame:Hide()
	frame:SetBackdrop(BACKDROP)
	frame:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
	frame:SetBackdropBorderColor(1, 1, 1)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(_G.UISpecialFrames, "NexEnhanceInstall") -- close on Escape

	-- Any close (button, Escape, reload) marks the prompt as seen.
	frame:SetScript("OnHide", function()
		if ns.global then ns.global.installed = true end
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

	local install = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	install:SetSize(150, 26)
	install:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -8, 16)
	install:SetText(L["Install"])
	install:SetScript("OnClick", function()
		ApplyAll()
		if ns.global then ns.global.installed = true end
		_G.ReloadUI()
	end)

	local skip = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	skip:SetSize(150, 26)
	skip:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 8, 16)
	skip:SetText(L["Not Now"])
	skip:SetScript("OnClick", function()
		frame:Hide()
	end)

	return frame
end

-- Public: open / toggle the window (used by the /nex install handler).
function ns:OpenInstall()
	local f = Build()
	if f:IsShown() then
		f:Hide()
	else
		f:Show()
		if _G.UIFrameFadeIn then
			_G.UIFrameFadeIn(f, 0.25, 0, 1)
		end
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
end
