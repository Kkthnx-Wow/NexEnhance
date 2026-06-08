--[[
	NexEnhance - Credits
	-------------------------------------------------------------------------
	A scrollable thank-you panel for the authors and projects whose ideas and
	code helped shape NexEnhance. Opens via /nex credits or from the Settings
	panel (Credits canvas page).
--]]

local _, ns = ...
local C, L = ns.C, ns.L

local _G = _G
local ipairs = ipairs
local format = string.format
local tinsert = table.insert
local CreateFrame = CreateFrame

local BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true,
	tileSize = 16,
	edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local CARD_PAD = 14
local CARD_GAP = 12
local CONTENT_WIDTH = 584
local SETTINGS_ICON = [[Interface\ICONS\INV_Misc_Book_09]]

local CLASS_COLORS = _G["CUSTOM_CLASS_COLORS"] or _G["RAID_CLASS_COLORS"]

-- Sidebar label only: rainbow letters like a Blizzard shop flair.
local SIDEBAR_RAINBOW = {
	{ 0.95, 0.25, 0.25 },
	{ 1.00, 0.55, 0.12 },
	{ 1.00, 0.88, 0.20 },
	{ 0.25, 0.85, 0.35 },
	{ 0.00, 0.68, 1.00 },
	{ 0.58, 0.35, 0.95 },
	{ 0.95, 0.35, 0.75 },
}

local CONTRIBUTORS = {
	{
		name = "Elv & the Tukui team",
		class = "PALADIN",
		project = "ElvUI",
		url = "github.com/tukui-org/ElvUI",
		thanks = "For ElvUI's AFK module — the foundation NexEnhance's AFK Camera builds on: bottom bar layout, faction crest, chat log and camera spin.",
		features = {
			"Misc — AFK Camera",
		},
	},
	{
		name = "Mortalknight",
		class = "DEATHKNIGHT",
		project = "GW2 UI",
		url = "github.com/Mortalknight/GW2_UI",
		thanks = "For GW2 UI's afk.lua — the wave/dance/sleep animation cycle and per-animation model holder offsets carried into NexEnhance's AFK Camera.",
		features = {
			"Misc — AFK Camera (model animations)",
		},
	},
	{
		name = "Shestak",
		class = "WARRIOR",
		project = "ShestakUI",
		url = "github.com/Shestak/ShestakUI",
		thanks = "For ShestakUI — the edit-box UpdateHeader hook for reliable channel colouring that NexEnhance's chat module borrowed.",
		features = {
			"Chat — Edit box channel colouring",
		},
	},
	{
		name = "Siweia",
		class = "MAGE",
		project = "NDui",
		url = "github.com/siweia/NDui",
		thanks = "For NDui — a towering default-UI companion whose modules, polish, and restraint set the bar for what \"enhance, don't reskin\" can look like.",
		features = {
			"Chat — Chat, Chat Filter, Chat Copy, Channel Rename",
			"Automation — Auto Vendor, Quick Quest, Faster Loot, Movie Skip",
			"Tooltip — Tooltip suite, Tooltip ID, Icons, Hover Tips",
			"Inventory — Mail, Already Known, Item Level (via yleaf)",
			"Misc — Animation, Alert Frames, BlizzFix, Quest Notification, Trade Target Info, Install CVars, Reminder, Stats",
			"Action Bars — Cooldown text styling",
		},
	},
	{
		name = "yleaf",
		class = "WARLOCK",
		project = "NDui — ItemLevel & yClassColors",
		url = "github.com/siweia/NDui",
		thanks = "For the item-level scanner, gem/enchant overlays, and yClassColors — small details that make inventory and social lists feel complete.",
		features = {
			"Inventory — Item Level overlays",
			"Misc — Social Colours (yClassColors)",
			"Core — F.GetItemLevel tooltip scanning",
		},
	},
	{
		name = "Lars Norberg",
		class = "SHAMAN",
		project = "GoldpawsStuff — BlizzardBags_BoE",
		url = "github.com/GoldpawsStuff/BlizzardBags_BoE",
		thanks = "For the bag bind-label idea — BoE and BoA text on icons — and for being a good friend. NexEnhance's bind overlays owe a direct debt to your work.",
		features = {
			"Inventory — BoE / BoA / WuE bind labels on bags & bank",
		},
	},
	{
		name = "p3lim",
		class = "DRUID",
		project = "QuickQuest & Dashi (public domain)",
		url = "github.com/p3lim-wow",
		thanks = "For QuickQuest's quest automation DNA and Dashi's settings helpers — shared freely and woven carefully into NexEnhance.",
		features = {
			"Automation — Quick Quest",
			"Core — Settings canvas helpers & scroll widgets (Dashi)",
		},
	},
	{
		name = "emelio",
		class = "ROGUE",
		project = "NDui — DragEmAll",
		url = "github.com/siweia/NDui",
		thanks = "For DragEmAll — the drag-anywhere quality-of-life that makes Blizzard frames feel less stuck in place.",
		features = {
			"Misc — Drag 'Em All",
		},
	},
	{
		name = "Cloudy",
		class = "PRIEST",
		project = "Cloudy Unit Info",
		url = "github.com/siweia/NDui",
		thanks = "For Cloudy Unit Info — the inspect item-level approach carried forward through NDui and into NexEnhance's tooltip item level.",
		features = {
			"Tooltip — average item level on unit tooltips",
		},
	},
	{
		name = "Peterodox",
		class = "EVOKER",
		project = "Plumber",
		url = "github.com/Peterodox/Plumber",
		thanks = "For Plumber — its delve borrowed-power automation, vendor-location tooltips (item/vendor data by gifLeo), and rare-announcement throttling each inspired a NexEnhance equivalent, rebuilt our way against the optimisation guide.",
		features = {
			"Automation — Delves Automation",
			"Tooltip — Vendor Location (data by gifLeo)",
			"Announcements — Rare Alert (anti-burst throttle & per-vignette re-announce cooldown)",
		},
	},
	{
		name = "Leatrix",
		class = "HUNTER",
		project = "Leatrix Plus",
		url = "curseforge.com/wow/addons/leatrix-plus",
		thanks = "For Leatrix Plus — its quest-automation refinements (accept by frequency, costly turn-in protection, and a configurable override key) sharpened NexEnhance's Quick Quest.",
		features = {
			"Automation — Quick Quest (frequency filters, turn-in safeguards, override key)",
		},
	},
	{
		name = "lightspark",
		class = "MONK",
		project = "ls_Monobrow",
		url = "github.com/ls-/ls_Monobrow",
		thanks = "For ls_Monobrow — its experience-bar fade behaviour (rest dim, reveal on mouseover / in combat / with a target) reimagined event-driven for NexEnhance's bar.",
		features = {
			"Misc — Experience Bar fade",
		},
	},
	{
		name = "Alteredcross",
		class = "PALADIN",
		project = "Chief Break-It Officer & Amateur Theorist",
		thanks = "Our good friend and forever PTR buddy — the paladin who logs in, clicks everything twice, /reloads on principle, and reports bugs before we finish typing the commit message. Half QA legend, half conspiracy theorist; fully convinced Blizzard nerfs our AFK bar when the moon is in retrograde. NexEnhance would ship with twice as many \"wait, what?\" moments without you.",
		features = {
			"Testing — if it can break, he will find it (lovingly)",
			"Bug hunting — \"bro watch this\" followed by a perfect repro",
			"Morale — unsolicited theories about who really moved the crest 6 pixels",
		},
	},
}

local LIBRARIES = {
	{
		name = "LibEditMode",
		author = "p3lim",
		class = "DRUID",
		note = "Edit Mode extension hooks for NexEnhance movers.",
	},
}

local function GetClassColor(classFile)
	local color = CLASS_COLORS and CLASS_COLORS[classFile]
	if not color then return 1, 1, 1 end
	return color.r, color.g, color.b
end

local function ColorHex(classFile)
	local r, g, b = GetClassColor(classFile)
	return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

local function RainbowEscape(text, offset)
	local parts = {}
	local count = #SIDEBAR_RAINBOW
	offset = offset or 0
	for i = 1, #text do
		local char = text:sub(i, i)
		if char == " " then
			parts[#parts + 1] = " "
		else
			local c = SIDEBAR_RAINBOW[((i - 1 + offset) % count) + 1]
			parts[#parts + 1] = format("|cff%02x%02x%02x%s|r", c[1] * 255, c[2] * 255, c[3] * 255, char)
		end
	end
	return table.concat(parts)
end

local function CreditsSettingsLabel()
	return format("|T%s:16:16|t %s", SETTINGS_ICON, RainbowEscape(L["Credits"], 0))
end

local function FormatBullets(lines)
	local out = {}
	for i = 1, #lines do
		out[i] = format("|cff666666•|r %s", lines[i])
	end
	return table.concat(out, "\n")
end

local function BuildHero(parent, width)
	local r, g, b = C.Colors.brand[1], C.Colors.brand[2], C.Colors.brand[3]

	local heart = parent:CreateTexture(nil, "ARTWORK")
	heart:SetSize(24, 24)
	heart:SetPoint("TOP", 0, -2)
	heart:SetTexture("Interface\\Icons\\INV_ValentinesCard01")
	heart:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local heading = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	heading:SetPoint("TOP", heart, "BOTTOM", 0, -6)
	heading:SetTextColor(r, g, b)
	heading:SetText(L["CREDITS_HEADING"])

	local sub = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	sub:SetPoint("TOP", heading, "BOTTOM", 0, -10)
	sub:SetWidth(width - 32)
	sub:SetJustifyH("CENTER")
	sub:SetWordWrap(true)
	sub:SetTextColor(0.88, 0.88, 0.88)
	sub:SetText(L["CREDITS_SUBTITLE"])

	local intro = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	intro:SetPoint("TOP", sub, "BOTTOM", 0, -14)
	intro:SetWidth(width - 48)
	intro:SetJustifyH("CENTER")
	intro:SetWordWrap(true)
	intro:SetSpacing(4)
	intro:SetTextColor(0.72, 0.72, 0.72)
	intro:SetText(L["CREDITS_INTRO"])

	local divider = parent:CreateTexture(nil, "ARTWORK")
	divider:SetColorTexture(r, g, b, 0.45)
	divider:SetHeight(2)
	divider:SetPoint("TOP", intro, "BOTTOM", 0, -16)
	divider:SetPoint("LEFT", parent, "LEFT", 12, 0)
	divider:SetPoint("RIGHT", parent, "RIGHT", -12, 0)

	return 28 + 6 + heading:GetStringHeight() + 10 + sub:GetStringHeight() + 14 + intro:GetStringHeight() + 16 + 2
end

local function CreateCreditCard(parent, entry, contentWidth)
	local r, g, b = GetClassColor(entry.class)
	local textWidth = contentWidth - CARD_PAD * 2 - 6

	local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	card:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
	card:SetBackdropColor(0.04, 0.04, 0.05, 0.92)

	local accent = card:CreateTexture(nil, "ARTWORK")
	accent:SetColorTexture(r, g, b, 1)
	accent:SetWidth(4)
	accent:SetPoint("TOPLEFT", 0, 0)
	accent:SetPoint("BOTTOMLEFT", 0, 0)

	local glow = card:CreateTexture(nil, "BACKGROUND")
	glow:SetColorTexture(r, g, b, 0.07)
	glow:SetPoint("TOPLEFT", accent, "TOPRIGHT", 0, 0)
	glow:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)

	local name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	name:SetPoint("TOPLEFT", accent, "TOPRIGHT", CARD_PAD, -CARD_PAD)
	name:SetTextColor(r, g, b)
	name:SetText(entry.name)

	local project = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	project:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
	project:SetTextColor(0.58, 0.58, 0.58)
	project:SetText(entry.project)

	local anchor = project
	if entry.url then
		local url = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		url:SetPoint("TOPLEFT", project, "BOTTOMLEFT", 0, -2)
		url:SetTextColor(0.42, 0.62, 0.82)
		url:SetText(entry.url)
		anchor = url
	end

	local thanks = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	thanks:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
	thanks:SetWidth(textWidth)
	thanks:SetJustifyH("LEFT")
	thanks:SetWordWrap(true)
	thanks:SetSpacing(3)
	thanks:SetTextColor(0.78, 0.78, 0.78)
	thanks:SetText(entry.thanks)

	local features = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	features:SetPoint("TOPLEFT", thanks, "BOTTOMLEFT", 0, -10)
	features:SetWidth(textWidth)
	features:SetJustifyH("LEFT")
	features:SetWordWrap(true)
	features:SetSpacing(2)
	features:SetText(FormatBullets(entry.features))

	local cardHeight = CARD_PAD + name:GetStringHeight() + 3 + project:GetStringHeight()
		+ (entry.url and 16 or 0) + 10 + thanks:GetStringHeight() + 10 + features:GetStringHeight() + CARD_PAD
	card:SetHeight(cardHeight)

	return card, cardHeight
end

local function PopulateCreditsList(scrollChild, contentWidth)
	local y = 0

	for i = 1, #CONTRIBUTORS do
		local card, cardHeight = CreateCreditCard(scrollChild, CONTRIBUTORS[i], contentWidth)
		card:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
		card:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
		y = y + cardHeight + CARD_GAP
	end

	local libHeading = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	libHeading:SetPoint("TOPLEFT", 0, -y - 4)
	libHeading:SetTextColor(C.Colors.brand[1], C.Colors.brand[2], C.Colors.brand[3])
	libHeading:SetText(L["CREDITS_LIBRARIES"])
	y = y + libHeading:GetStringHeight() + 10

	for i = 1, #LIBRARIES do
		local lib = LIBRARIES[i]
		local line = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		line:SetPoint("TOPLEFT", 8, -y)
		line:SetWidth(contentWidth - 16)
		line:SetJustifyH("LEFT")
		line:SetWordWrap(true)
		line:SetText(format("%s%s|r |cff888888by %s%s|r — %s",
			ColorHex(lib.class), lib.name, ColorHex(lib.class), lib.author, lib.note))
		y = y + line:GetStringHeight() + 6
	end

	local footer = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	footer:SetPoint("TOPLEFT", 0, -y - 12)
	footer:SetWidth(contentWidth)
	footer:SetJustifyH("CENTER")
	footer:SetWordWrap(true)
	footer:SetTextColor(0.5, 0.5, 0.5)
	footer:SetText(L["CREDITS_FOOTER"])
	y = y + footer:GetStringHeight() + 24

	scrollChild:SetHeight(y)
end

local function AttachCreditsScroll(parent, topInset, contentWidth)
	local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, topInset)
	scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -26, 6)

	local child = CreateFrame("Frame", nil, scroll)
	child:SetWidth(contentWidth)
	scroll:SetScrollChild(child)

	PopulateCreditsList(child, contentWidth)
	return scroll
end

-- ---------------------------------------------------------------------------
-- Standalone window
-- ---------------------------------------------------------------------------
local frame

local function BuildStandalone()
	if frame then return frame end

	frame = CreateFrame("Frame", "NexEnhanceCredits", UIParent, "BackdropTemplate")
	frame:SetSize(640, 720)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:Hide()
	frame:SetBackdrop(BACKDROP)
	frame:SetBackdropColor(0.05, 0.05, 0.07, 0.97)
	frame:SetBackdropBorderColor(C.Colors.brand[1], C.Colors.brand[2], C.Colors.brand[3], 0.85)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(_G.UISpecialFrames, "NexEnhanceCredits")

	local logo = frame:CreateTexture(nil, "ARTWORK")
	logo:SetSize(48, 48)
	logo:SetPoint("TOPLEFT", 18, -16)
	logo:SetTexture(C.Media.Textures.logo)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -4)
	title:SetTextColor(C.Colors.brand[1], C.Colors.brand[2], C.Colors.brand[3])
	title:SetText(L["Credits"])

	local meta = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	meta:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -4)
	meta:SetFormattedText("%s |c%s%s|r", L["Version"], C.BrandHex, ns.version)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)

	local hero = CreateFrame("Frame", nil, frame)
	hero:SetPoint("TOPLEFT", 16, -72)
	hero:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -72)
	local heroHeight = BuildHero(hero, CONTENT_WIDTH)
	hero:SetHeight(heroHeight)

	AttachCreditsScroll(frame, -72 - heroHeight - 8, CONTENT_WIDTH)

	return frame
end

function ns:OpenCredits()
	local f = BuildStandalone()
	if f:IsShown() then
		f:Hide()
	else
		f:Show()
		if _G.UIFrameFadeIn then
			_G.UIFrameFadeIn(f, 0.25, 0, 1)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Settings canvas (NexEnhance → Credits)
-- ---------------------------------------------------------------------------
local canvasBuilt = false

local function BuildCreditsCanvas(canvas)
	if canvasBuilt then return end
	canvasBuilt = true

	local hero = CreateFrame("Frame", nil, canvas)
	hero:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, 0)
	hero:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", 0, 0)
	local heroHeight = BuildHero(hero, 500)
	hero:SetHeight(heroHeight)

	AttachCreditsScroll(canvas, -heroHeight - 4, 500)
end

ns:RegisterOptionsCanvas(L["Credits"], BuildCreditsCanvas, CreditsSettingsLabel())
