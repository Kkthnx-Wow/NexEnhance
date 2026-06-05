--[[
	NexEnhance - Changelog
	-------------------------------------------------------------------------
	A styled, in-game changelog window. Opens automatically once per account
	whenever the version changes, and any time via /nex changelog.

	The data table below is the single source of truth for the in-game notes;
	keep it in sync with CHANGELOG.md.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local C, L = ns.C, ns.L

local _G = _G
local ipairs = ipairs
local format = string.format
local tconcat = table.concat
local tinsert = table.insert
local CreateFrame = CreateFrame
local C_Timer = C_Timer

ns:RegisterDefaults({
	changelog = {
		enable = true,
		autoShow = true,
	},
})
ns:RegisterDefaults({ lastChangelog = false }, "global")

local Changelog = ns:NewModule("Changelog", "changelog", { group = "misc", title = L["Changelog"], order = 60 })

-- A Blizzard tooltip-style border (matches the rest of the UI).
local BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true,
	tileSize = 16,
	edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

-- ---------------------------------------------------------------------------
-- Notes (keep in sync with CHANGELOG.md)
-- ---------------------------------------------------------------------------
local CHANGELOG = {
	{
		version = "1.2.3",
		date = "2026-06-05",
		intro = "Inventory clarity and a proper thank-you page: bind labels on bag icons plus a class-coloured credits panel for the authors whose work helped build NexEnhance.",
		sections = {
			{ "Inventory", {
				"Bind Status: show BoE, BoA and WuE on unbound bag and bank items (top-right of the icon; item level stays bottom-left).",
				"Toggle under Item Level → Show Bind Status.",
				"Idea borrowed from Lars Norberg's BlizzardBags_BoE (GoldpawsStuff) — thank you, friend.",
			} },
			{ "Credits", {
				"A scrollable thank-you panel with class-coloured contributor cards, feature lists and library acknowledgements.",
				"Open with /nex credits or from Settings → NexEnhance → Credits.",
			} },
			{ "Interface", {
				"/nex help and the options landing page now list the credits command.",
			} },
		},
	},
	{
		version = "1.2.2",
		date = "2026-06-05",
		intro = "A small packaging update so CurseForge and Wago can track releases correctly.",
		sections = {
			{ "Packaging", {
				"Added X-Curse-Project-ID and X-Wago-ID to the addon manifest.",
			} },
		},
	},
	{
		version = "1.2.1",
		date = "2026-06-05",
		intro = "A polish-and-extras update: colour your default frames, a Details! skin and a mount-source tooltip, plus an easier-to-read Settings panel - still improve, never reskin.",
		sections = {
			{ "General", {
				"Frame Colour: tint the default unit frames and HUD (player, pet, target, focus, boss, class resources, cast bars, totems and the minimap) with a colour of your choice.",
				"UI Scale now lives in the new General group.",
			} },
			{ "Skins", {
				"Details: frames each Details! window with the Minimalistic skin plus a clean Blizzard-style border and background.",
			} },
			{ "Tooltip", {
				"Mount Source: hold Shift over another player's mount buff to see its collection status and source.",
			} },
			{ "Chat", {
				"Chat Copy button no longer disappears when switching chat tabs.",
			} },
			{ "Interface", {
				"Each Settings subcategory now has a sidebar icon and an intro description at the top of its page.",
			} },
		},
	},
	{
		version = "1.2.0",
		date = "2026-06-05",
		intro = "A chat-focused update: a cleaner, smarter edit box, a movable Battle.net pop-up, and a new Mythic+ keystone autoslotter - plus an easier-to-navigate Settings panel.",
		sections = {
			{ "Chat", {
				"Edit box now hides when inactive and recolours reliably for the active channel as you switch.",
				"Optionally hide the chat scroll bar and jump-to-bottom button.",
				"Battle.net pop-ups now sit at the chat's top-right corner and are movable in Edit Mode.",
			} },
			{ "Automation", {
				"Auto Keystone: automatically slots your Mythic+ keystone when the Challenge Mode UI opens (defers to AngryKeystones if installed).",
				"Auto Hide Tracker: hides the Objective Tracker during boss fights and arenas, keeping objectives visible in Mythic+ by default.",
			} },
			{ "Interface", {
				"The Settings sidebar is now listed alphabetically.",
				"Dependent options grey out when their parent toggle is off across many more modules, and their labels are a touch larger.",
			} },
		},
	},
	{
		version = "1.1.0",
		date = "2026-06-05",
		intro = "A feature update: a fuller Automation suite, inventory and tooltip quality-of-life, and sharper unit-frame colours - still improve, never reskin.",
		sections = {
			{ "Unit Frames", {
				"NPCs now tint by reaction (hostile red, neutral yellow, friendly green) instead of flat green; players keep class colours.",
				"Boss frames (Boss 1-5) are now coloured alongside the target/focus frames.",
				"Fixed hostile NPCs and bosses showing a green health bar in combat and instances.",
			} },
			{ "Inventory", {
				"Already Known: learned toys, mounts, recipes and pets dim to green at vendors, the Auction House and the guild bank.",
			} },
			{ "Tooltip", {
				"Trade Target Info: marks a trade partner as stranger / friend / guild and class-colours their name.",
				"Choose whether the unit health bar sits at the top or bottom of the tooltip.",
			} },
			{ "Automation", {
				"Decline Duels: auto-declines player and pet-battle PvP duels.",
				"Auto Invite: accepts invites from trusted friends and guild members.",
				"Auto Goodbye: a friendly farewell to the group after a dungeon or Mythic+.",
				"Auto Resurrect: accepts rezzes out of combat (skips encounter pylon/brazier), with an optional /thank.",
			} },
			{ "Maps", {
				"Map Reveal: removes fog of war from the world map, toggled from the config (the on-map checkbox was removed).",
				"Wowhead Links: copyable Wowhead links on the world map (tracked quest) and the achievement frame.",
			} },
			{ "Extras", {
				"Queue Timer on the LFG eye, a one-time first-run setup screen, and this in-game changelog window (/nex changelog) that highlights the newest version and dims older ones.",
				"Quick Item Delete: optionally skip the type-DELETE prompt for good/quest items (off by default).",
				"Hardened the shared event dispatcher so modules can unregister mid-dispatch safely (fixes a rare error opening the achievements panel).",
			} },
		},
	},
	{
		version = "1.0.0",
		date = "2026-06-05",
		intro = "The first public release. A complete, event-driven engine with a full suite of toggleable modules that sharpen the default UI without reskinning it.",
		sections = {
			{ "Core Engine", {
				"Single-frame event dispatcher and a clean OnInitialize -> OnEnable lifecycle.",
				"Per-module profile database with live-apply settings (most changes need no reload).",
				"Modern, grouped Settings panel and /nex slash commands.",
				"Edit Mode movers for our own frames, plus pixel-perfect backdrop helpers.",
			} },
			{ "Action Bars", {
				"Cooldown text on action buttons with a minimum-duration threshold.",
			} },
			{ "Unit Frames", {
				"Class-coloured health for players across party, target, focus and their targets (secret-value safe).",
			} },
			{ "Auras", {
				"Buff Reminder: icons for missing buffs you can provide, on a movable anchor.",
			} },
			{ "Inventory", {
				"Item Level on the Character and Inspect panes (Shift to show).",
				"Durability tab with per-slot repair-cost tooltip and a low-durability nudge.",
				"Mail: Collect-Gold and Take-All buttons, quick-delete, attachment tooltips, GM-mail fix.",
			} },
			{ "Chat", {
				"Flattened tabs and a top-docked, full-width edit box that holds steady on every tab (including Combat Log).",
				"Channel-tinted Blizzard border, quick scroll, sticky whispers, tab channel cycling and a font-size menu.",
				"Chat Copy window and shortened channel names.",
			} },
			{ "Filters", {
				"Chat Filter: keyword spam filtering, repeat detection, stranger/spammer blocking and item-level links (/nexfilter).",
			} },
			{ "Tooltip", {
				"Improved, never reskinned: quality-coloured default borders, spell/item/aura IDs, source icons, item levels and unit hover tips.",
			} },
			{ "Skins", {
				"Objective Tracker cleanup, Character frame tidy-up, and clean channel-coloured chat bubbles.",
			} },
			{ "DataText", {
				"Stats readout under the minimap: FPS / latency with a memory + addon tooltip. Toggle FPS/MS, flip order, class-colour the numbers.",
			} },
			{ "Maps", {
				"World Map coordinates, a smaller scalable map (no blackout), fade-on-movement and a movable anchor.",
			} },
			{ "Automation", {
				"Auto Vendor + repair, Quick Quest, Faster Loot and Movie Skip.",
			} },
			{ "Announcements", {
				"Quest Notification: concise, throttled quest progress and completion messages.",
			} },
			{ "Extras", {
				"Always-on Blizzard bug fixes, UI Scale, Social Colours, Drag 'Em All, Alert Frames, a login Animation and /rl reload shortcuts.",
			} },
		},
	},
}

local frame

-- Two colour palettes so the newest version reads as "what's new" in full
-- colour while older entries are dimmed to grey "history". The first entry in
-- CHANGELOG is always the most recent.
local PALETTE_NEW = {
	version = "ffffff",
	date = "888888",
	intro = "b0b0b0",
	heading = "|c" .. C.BrandHex,
	bullet = "909090",
	body = "e6e6e6",
}
local PALETTE_OLD = {
	version = "9d9d9d",
	date = "5f5f5f",
	intro = "707070",
	heading = "|cff8a8a8a",
	bullet = "555555",
	body = "808080",
}

local function BuildText()
	local buf = {}
	for index, entry in ipairs(CHANGELOG) do
		local isLatest = index == 1
		local p = isLatest and PALETTE_NEW or PALETTE_OLD

		local tag = isLatest and format("  |c%sNEW|r", C.BrandHex) or ""
		buf[#buf + 1] = format("|cff%sVersion %s|r  |cff%s%s|r%s", p.version, entry.version, p.date, entry.date, tag)
		if entry.intro then
			buf[#buf + 1] = format("|cff%s%s|r", p.intro, entry.intro)
		end
		buf[#buf + 1] = " "
		for _, section in ipairs(entry.sections) do
			buf[#buf + 1] = format("%s%s|r", p.heading, section[1])
			local lines = section[2]
			for i = 1, #lines do
				buf[#buf + 1] = format("|cff%s-|r |cff%s%s|r", p.bullet, p.body, lines[i])
			end
			buf[#buf + 1] = " "
		end
	end
	return tconcat(buf, "\n")
end

local function Build()
	if frame then return frame end

	frame = CreateFrame("Frame", "NexEnhanceChangelog", UIParent, "BackdropTemplate")
	frame:SetSize(560, 600)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
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
	tinsert(_G.UISpecialFrames, "NexEnhanceChangelog") -- close on Escape

	local logo = frame:CreateTexture(nil, "ARTWORK")
	logo:SetSize(56, 56)
	logo:SetPoint("TOPLEFT", 16, -14)
	logo:SetTexture(C.Media.Textures.logo)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -6)
	title:SetText(ns.title)

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

	local scroll = CreateFrame("ScrollFrame", "NexEnhanceChangelogScroll", frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -12)
	scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 16)

	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(500, 1)
	scroll:SetScrollChild(child)

	local body = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	body:SetPoint("TOPLEFT", 0, 0)
	body:SetWidth(496)
	body:SetJustifyH("LEFT")
	body:SetJustifyV("TOP")
	body:SetSpacing(4)
	body:SetText(BuildText())

	child:SetSize(500, body:GetStringHeight() + 12)

	return frame
end

-- Public: toggle the window (used by the /nex changelog handler).
function ns:OpenChangelog()
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

function Changelog:OnEnable()
	if not ns.db.changelog.enable then return end

	-- Auto-show once per account whenever the version changes, but only after
	-- the first-run install screen has been dealt with (so they don't overlap).
	if ns.db.changelog.autoShow and ns.global and ns.global.installed and ns.global.lastChangelog ~= ns.version then
		ns.global.lastChangelog = ns.version
		C_Timer.After(2.5, function()
			ns:OpenChangelog()
		end)
	end
end

function Changelog:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "autoShow", L["Auto-Show Changelog"], L["Open the changelog automatically the first time you log in after an update."])
end
