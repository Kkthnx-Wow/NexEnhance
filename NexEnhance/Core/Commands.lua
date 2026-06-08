--[[
	NexEnhance - Commands & Options
	-------------------------------------------------------------------------
	User-facing entry points: the `/nex` slash command and a modern Settings
	panel. The panel uses Blizzard's vertical layout API with direct-backed
	settings, so values write to the active profile immediately and modules can
	apply changes live.
--]]

local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local type = type
local format = string.format

-- Y-offset for the sub-title header divider. Blizzard's default is -50; we push
-- it down a few pixels so it reads as a clearer separator below the title.
local NATIVE_DIVIDER_Y = -56

local function Brand(text)
	return "|c" .. C.BrandHex .. text .. "|r"
end

-- ---------------------------------------------------------------------------
-- Slash command handlers
-- ---------------------------------------------------------------------------
local handlers = {}

handlers.help = function(_)
	F.Print(F.Colorize(L["Usage"] .. ":", "brand"))
	F.Print("  /nex help          -", L["Show this help"])
	F.Print("  /nex modules       -", L["List modules and their state"])
	F.Print("  /nex toggle <name> -", L["Toggle a module: /nex toggle <module>"])
	F.Print("  /nex config        -", L["Open the options panel"])
	F.Print("  /nex reminder      -", L["Toggle buff reminder test icons"])
	F.Print("  /nex afk           -", L["Toggle AFK camera preview"])
	F.Print("  /nex changelog     -", L["Open the changelog"])
	F.Print("  /nex credits       -", L["Open the credits panel"])
	F.Print("  /nex profile       -", L["Open the profile import/export panel"])
	F.Print("  /nex install       -", L["Open the setup screen"])
end

handlers.profile = function(_)
	if ns.OpenProfiles then
		ns:OpenProfiles()
	end
end

handlers.changelog = function(_)
	if ns.OpenChangelog then
		ns:OpenChangelog()
	end
end

handlers.credits = function(_)
	if ns.OpenCredits then
		ns:OpenCredits()
	end
end

handlers.install = function(_)
	if ns.OpenInstall then
		ns:OpenInstall()
	end
end

handlers.modules = function(_)
	F.Print(F.Colorize(L["Modules"] .. ":", "brand"))
	for i = 1, #ns.modules do
		local module = ns.modules[i]
		local state = module:IsEnabled() and F.Colorize(L["Enabled"], "green") or F.Colorize(L["Disabled"], "red")
		F.Print(" -", module.name, state)
	end
end

handlers.toggle = function(name)
	if not name or name == "" then
		F.Print(L["Usage"] .. ": /nex toggle <module>")
		return
	end

	local module = ns:GetModule(name)
	if not module or not module.dbKey then
		F.Print(F.Colorize(format("Unknown module '%s'.", name), "red"))
		return
	end

	local settings = ns.db[module.dbKey]
	settings.enable = not settings.enable
	local state = settings.enable and F.Colorize(L["Enabled"], "green") or F.Colorize(L["Disabled"], "red")
	F.Print(module.name, "->", state)
	if module.OnSettingChanged then
		module:OnSettingChanged("enable", settings.enable)
	end
end

handlers.reminder = function(_)
	local module = ns:GetModule("Reminder")
	if module and module.ToggleTest then
		module:ToggleTest()
	else
		F.Print(F.Colorize(L["Buff Reminder"] .. ": ", "brand") .. L["Module unavailable."])
	end
end

handlers.afk = function(_)
	local module = ns:GetModule("AFKCam")
	if module and module.ToggleTest then
		module:ToggleTest()
	else
		F.Print(F.Colorize(L["AFK Camera"] .. ": ", "brand") .. L["Module unavailable."])
	end
end

handlers.config = function(_)
	if ns.OpenOptions then
		ns:OpenOptions()
	else
		F.Print(L["Show this help"])
		handlers.help()
	end
end

local function HandleSlash(input)
	input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local command, rest = input:match("^(%S*)%s*(.-)$")
	command = command:lower()

	local handler = handlers[command] or handlers.help
	handler(rest)
end

_G.SLASH_NEXENHANCE1 = "/nex"
_G.SLASH_NEXENHANCE2 = "/nexenhance"
_G["SlashCmdList"]["NEXENHANCE"] = HandleSlash

-- ---------------------------------------------------------------------------
-- Options panel (modern Settings API, guarded)
-- ---------------------------------------------------------------------------
local function ApplyModuleSetting(module, key, value)
	if module.OnSettingChanged then
		module:OnSettingChanged(key, value)
	elseif module.UpdateStylingConfig then
		module:UpdateStylingConfig()
	end
end

local OptionBuilder = {}

local function GetDefault(module, key)
	local defaults = ns.defaults.profile[module.dbKey]
	return defaults and defaults[key]
end

-- Register a setting that reads/writes ns.db[module.dbKey][key] directly and
-- fires the module's live-apply callback on change.
local function RegisterSetting(category, module, key, name)
	local variableTbl = ns.db[module.dbKey]
	local defaultValue = GetDefault(module, key)
	local variable = ns.name .. "_" .. module.dbKey .. "_" .. key
	local setting = Settings.RegisterAddOnSetting(category, variable, key, variableTbl, type(defaultValue), name, defaultValue)
	setting:SetValueChangedCallback(function(_, value)
		ApplyModuleSetting(module, key, value)
	end)
	return setting
end

function OptionBuilder:Checkbox(category, module, key, name, tooltip)
	local setting = RegisterSetting(category, module, key, name)
	local initializer = Settings.CreateCheckbox(category, setting, tooltip)
	return setting, initializer
end

function OptionBuilder:Slider(category, module, key, name, tooltip, minValue, maxValue, step)
	local setting = RegisterSetting(category, module, key, name)

	local options = Settings.CreateSliderOptions(minValue, maxValue, step)
	if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
	end
	local initializer = Settings.CreateSlider(category, setting, options, tooltip)
	return setting, initializer
end

-- `choices` is an array of { value = number, label = string, tooltip = string }.
function OptionBuilder:Dropdown(category, module, key, name, tooltip, choices)
	if not Settings.CreateDropdown then return end

	local setting = RegisterSetting(category, module, key, name)

	local function GetOptions()
		local container = Settings.CreateControlTextContainer()
		for i = 1, #choices do
			local choice = choices[i]
			container:Add(choice.value, choice.label, choice.tooltip)
		end
		return container:GetData()
	end

	local initializer = Settings.CreateDropdown(category, setting, GetOptions, tooltip)
	return setting, initializer
end

-- Colour swatch. The stored value is an "AARRGGBB" hex string (Blizzard reads
-- it via CreateColorFromHexString and writes it back with Color:GenerateHexColor),
-- so the module's default for `key` must be a hex string. Use F.HexToRGBA /
-- F.RGBAToHex to convert in the module's apply callback.
function OptionBuilder:Color(category, module, key, name, tooltip)
	if not Settings.CreateColorSwatch then return end

	local setting = RegisterSetting(category, module, key, name)
	local initializer = Settings.CreateColorSwatch(category, setting, tooltip)
	return setting, initializer
end

function OptionBuilder:EditBox(category, module, key, name, tooltip, width, onCommit)
	local layout = self.layout
	if not (layout and F.CreateSettingsEditBox) then return end

	local setting = RegisterSetting(category, module, key, name)
	local initializer = F.CreateSettingsEditBox(name, tooltip, function()
		return setting:GetValue()
	end, function(text)
		if onCommit then
			text = onCommit(text) or text
		end
		setting:SetValue(text)
	end, width)
	if initializer then
		layout:AddInitializer(initializer)
	end
	return setting, initializer
end

-- Add a section header (same style as the per-module headers) partway through a
-- module's options, to visually group a related cluster of settings.
function OptionBuilder:Header(text)
	local layout = self.layout
	if layout and _G["CreateSettingsListSectionHeaderInitializer"] then
		layout:AddInitializer(_G["CreateSettingsListSectionHeaderInitializer"](text))
	end
end

-- Make `child` depend on a parent toggle. `child` and `parent` are the
-- *initializers* (the 2nd return value from the builder methods above). The
-- child is automatically greyed out and disabled whenever the parent toggle is
-- off; Blizzard re-evaluates this when the parent's value changes. The parent
-- should be a checkbox/toggle so its value reads as a boolean.
-- ---------------------------------------------------------------------------
-- Child rows (DependsOn / Indent) render with Blizzard's GameFontNormalSmall,
-- which is tiny next to their parent. Bump our dependent rows up one point: we
-- tag the child initializer and restyle its label after Blizzard's
-- SettingsListElementMixin:Init runs (every control type funnels through it).
-- ---------------------------------------------------------------------------
-- luacheck: globals CreateFont
local childFont
local function GetChildFont()
	if childFont then return childFont end
	childFont = CreateFont("NexEnhanceSettingChildFont")
	childFont:CopyFontObject("GameFontNormalSmall")
	local file, size, flags = childFont:GetFont()
	if file and size then
		childFont:SetFont(file, size + 1, flags)
	end
	return childFont
end

local elementMixin = _G["SettingsListElementMixin"]
if elementMixin and not ns.__settingsChildFontHooked then
	ns.__settingsChildFontHooked = true
	hooksecurefunc(elementMixin, "Init", function(self, initializer)
		if initializer and initializer.nexBumpFont and self.Text then
			self.Text:SetFontObject(GetChildFont())
		end
	end)
end

function OptionBuilder:DependsOn(child, parent)
	if not (child and parent and child.SetParentInitializer) then return end
	child.nexBumpFont = true
	child:SetParentInitializer(parent, function()
		local setting = parent:GetSetting()
		return setting and setting:GetValue()
	end)
end

-- Nest `child` under `parent` for purely visual grouping (indented) without
-- ever disabling it.
function OptionBuilder:Indent(child, parent)
	if not (child and parent and child.SetParentInitializer) then return end
	child.nexBumpFont = true
	child:SetParentInitializer(parent, function() return true end)
end

-- Themed option groups, in display order. Modules declare a `group` key (see
-- ns:NewModule) and land in the matching subcategory; anything without a known
-- group falls through to "misc".
-- `icon` is an in-game texture path (with backslashes) or an atlas name. To use
-- a custom/Wowhead icon, save the file under the addon (e.g. Media\Sections\) and
-- point `icon` at that path - WoW can't download images at runtime. These are
-- placeholder in-game icons; swap them freely.
local GROUP_ORDER = {
	{ key = "general", title = L["General"], icon = [[Interface\ICONS\Trade_Engineering]], desc = L["DESC_GENERAL"] },
	{ key = "actionbars", title = L["Action Bars"], icon = [[Interface\ICONS\Ability_Warrior_Charge]], desc = L["DESC_ACTIONBARS"] },
	{ key = "unitframes", title = L["Unit Frames"], icon = [[Interface\ICONS\Ability_Warrior_BattleShout]], desc = L["DESC_UNITFRAMES"] },
	{ key = "auras", title = L["Auras"], icon = [[Interface\ICONS\Spell_Holy_WordFortitude]], desc = L["DESC_AURAS"] },
	{ key = "inventory", title = L["Inventory"], icon = [[Interface\ICONS\INV_Misc_Bag_08]], desc = L["DESC_INVENTORY"] },
	{ key = "chat", title = L["Chat"], icon = [[Interface\ICONS\INV_Letter_15]], desc = L["DESC_CHAT"] },
	{ key = "filters", title = L["Filters"], icon = [[Interface\ICONS\INV_Misc_Spyglass_02]], desc = L["DESC_FILTERS"] },
	{ key = "tooltip", title = L["Tooltip"], icon = [[Interface\ICONS\INV_Misc_Note_01]], desc = L["DESC_TOOLTIP"] },
	{ key = "skins", title = L["Skins"], icon = [[Interface\ICONS\INV_Shirt_GuildTabard_01]], desc = L["DESC_SKINS"] },
	{ key = "datatext", title = L["DataText"], icon = [[Interface\ICONS\INV_Misc_PocketWatch_01]], desc = L["DESC_DATATEXT"] },
	{ key = "maps", title = L["Maps"], icon = [[Interface\ICONS\INV_Misc_Map_01]], desc = L["DESC_MAPS"] },
	{ key = "automation", title = L["Automation"], icon = [[Interface\ICONS\INV_Gizmo_01]], desc = L["DESC_AUTOMATION"] },
	{ key = "announcements", title = L["Announcements"], icon = [[Interface\ICONS\INV_Misc_Horn_01]], desc = L["DESC_ANNOUNCEMENTS"] },
	{ key = "misc", title = L["Miscellaneous"], icon = [[Interface\ICONS\INV_Misc_QuestionMark]], desc = L["DESC_MISC"] },
}

-- Build a sidebar label with an inline icon. Texture paths (containing a
-- backslash) use a |T|t escape; otherwise the value is treated as an atlas name.
-- The icon is prefixed for display only - sorting still uses the clean title.
local CreateAtlasMarkup = _G["CreateAtlasMarkup"]
local function GroupLabel(g)
	if not g.icon then return g.title end
	if g.icon:find("\\", 1, true) then
		return format("|T%s:16:16:0:0|t %s", g.icon, g.title)
	end
	if CreateAtlasMarkup then
		return CreateAtlasMarkup(g.icon, 16, 16) .. " " .. g.title
	end
	return g.title
end

local GROUP_INDEX = {}
for i = 1, #GROUP_ORDER do
	GROUP_INDEX[GROUP_ORDER[i].key] = i
end

-- Stable ordering: by group, then the module's own order, then name.
local function SortModules(a, b)
	local ga = GROUP_INDEX[a.group or "misc"] or math.huge
	local gb = GROUP_INDEX[b.group or "misc"] or math.huge
	if ga ~= gb then return ga < gb end

	local oa, ob = a.order or 100, b.order or 100
	if oa ~= ob then return oa < ob end

	return a.name < b.name
end

local function AddSectionHeader(layout, text)
	if layout and _G["CreateSettingsListSectionHeaderInitializer"] then
		layout:AddInitializer(_G["CreateSettingsListSectionHeaderInitializer"](text))
	end
end

-- ---------------------------------------------------------------------------
-- Landing page (canvas)
--   A small styled frame for the top-level category: logo, title, version,
--   tagline, a live module count and the slash-command quick reference. Falls
--   back gracefully to a plain vertical category if canvas layout is missing.
-- ---------------------------------------------------------------------------
local function MakeFontString(parent, template, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY", template or "GameFontNormal")
	fs:SetJustifyH("LEFT")
	return fs
end

local function CreateLandingFrame()
	local frame = CreateFrame("Frame", nil)

	local logo = frame:CreateTexture(nil, "ARTWORK")
	logo:SetSize(72, 72)
	logo:SetPoint("TOPLEFT", 14, -14)
	logo:SetTexture(C.Media.Textures.logo)

	local title = MakeFontString(frame, "GameFontNormalHuge")
	title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 14, -2)
	title:SetText(ns.title)

	local meta = MakeFontString(frame, "GameFontDisable")
	meta:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -7)
	local author = C_AddOns.GetAddOnMetadata(ns.name, "Author") or "?"
	meta:SetText(format("%s %s   %s %s", L["Version"], Brand(ns.version), L["Author"], Brand(author)))

	local stats = MakeFontString(frame, "GameFontHighlight")
	stats:SetPoint("TOPLEFT", meta, "BOTTOMLEFT", 0, -4)
	frame.stats = stats

	local tagline = MakeFontString(frame, "GameFontHighlight")
	tagline:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -16)
	tagline:SetPoint("RIGHT", frame, "RIGHT", -24, 0)
	tagline:SetJustifyH("LEFT")
	tagline:SetWordWrap(true)
	tagline:SetText(C_AddOns.GetAddOnMetadata(ns.name, "Notes") or "")

	local divider = frame:CreateTexture(nil, "ARTWORK")
	divider:SetColorTexture(C.Colors.brand[1], C.Colors.brand[2], C.Colors.brand[3], 0.55)
	divider:SetHeight(2)
	divider:SetPoint("TOPLEFT", tagline, "BOTTOMLEFT", 0, -14)
	divider:SetPoint("RIGHT", frame, "RIGHT", -24, 0)

	local heading = MakeFontString(frame, "GameFontNormalLarge")
	heading:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -12)
	heading:SetText(Brand(L["Getting Started"]))

	-- Slash-command quick reference, reusing the help strings.
	local lines = {
		{ "/nex", L["Open the options panel"] },
		{ "/nex modules", L["List modules and their state"] },
		{ "/nex toggle <module>", L["Toggle a module: /nex toggle <module>"] },
		{ "/nex credits", L["Open the credits panel"] },
		{ "/nex help", L["Show this help"] },
	}

	local anchor = heading
	for i = 1, #lines do
		local row = MakeFontString(frame, "GameFontHighlight")
		row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", i == 1 and 6 or 0, i == 1 and -8 or -5)
		row:SetText(format("%s  |cffaaaaaa%s|r", Brand(lines[i][1]), lines[i][2]))
		anchor = row
	end

	function frame:OnRefresh()
		local total, enabled = #ns.modules, 0
		for i = 1, total do
			if ns.modules[i]:IsEnabled() then
				enabled = enabled + 1
			end
		end
		self.stats:SetFormattedText(L["%d modules, %d enabled"], total, enabled)
	end

	return frame
end

-- ---------------------------------------------------------------------------
-- Canvas sub-pages
--   For richer custom panels (lists, custom widgets, etc.) that the vertical
--   layout can't express. Replicates the native SettingsList header so the page
--   visually matches Blizzard's, including an optional "Defaults" button.
--   Adapted from p3lim's Dashi (public domain).
-- ---------------------------------------------------------------------------
local canvasMixin = {}
function canvasMixin:SetDefaultsHandler(callback)
	local button = self:GetParent().Header.DefaultsButton
	button:Show()
	button:SetScript("OnClick", callback)
end

local function CreateCanvasSubFrame(name)
	local frame = CreateFrame("Frame")

	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(50)
	frame.Header = header

	local title = header:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
	title:SetPoint("TOPLEFT", 7, -22)
	title:SetJustifyH("LEFT")
	title:SetText(name)
	header.Title = title

	local defaults = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
	defaults:SetPoint("TOPRIGHT", -36, -16)
	defaults:SetSize(96, 22)
	defaults:SetText(_G["SETTINGS_DEFAULTS"] or DEFAULTS or "Defaults")
	defaults:Hide()
	header.DefaultsButton = defaults

	-- Sits a touch lower than Blizzard's default (-50) so the line has more
	-- breathing room beneath the (icon'd) sub-title. Kept in sync with the
	-- native vertical-layout pages by InstallHeaderDividerNudge below.
	local divider = header:CreateTexture(nil, "ARTWORK")
	divider:SetPoint("TOP", 0, NATIVE_DIVIDER_Y)
	divider:SetAtlas("Options_HorizontalDivider", true)

	-- The container the builder draws into.
	local canvas = Mixin(CreateFrame("Frame", nil, frame), canvasMixin)
	canvas:SetPoint("BOTTOMLEFT", 0, 5)
	canvas:SetPoint("BOTTOMRIGHT", -12, 5)
	canvas:SetPoint("TOP", 0, -56)

	return frame, canvas
end

-- The native SettingsList (used by every vertical-layout subcategory) is a single
-- shared instance, so its header divider is shared across our pages AND Blizzard's.
-- We can't move it just for our subcategories at creation time; instead we hook the
-- per-page display and reposition the divider only while a NexEnhance category is
-- shown, restoring Blizzard's default (-50) for everyone else.
local function InstallHeaderDividerNudge(ourCategories)
	local panel = _G["SettingsPanel"]
	if not (panel and panel.DisplayCategory and panel.GetSettingsList) or panel.nexHeaderDividerHooked then
		return
	end
	panel.nexHeaderDividerHooked = true

	-- The divider texture has no parentKey, so locate it once (cached) by atlas.
	local divider
	local function GetDivider()
		if divider then return divider end
		local list = panel:GetSettingsList()
		local header = list and list.Header
		if not header then return nil end
		local regions = { header:GetRegions() }
		for i = 1, #regions do
			local region = regions[i]
			if region.GetAtlas and region:GetAtlas() == "Options_HorizontalDivider" then
				divider = region
				return divider
			end
		end
		return nil
	end

	hooksecurefunc(panel, "DisplayCategory", function(_, category)
		local tex = GetDivider()
		if not tex then return end
		tex:ClearAllPoints()
		tex:SetPoint("TOP", 0, ourCategories[category] and NATIVE_DIVIDER_Y or -50)
	end)
end

local optionsCanvases = {}

-- Public: register a custom canvas sub-page under the addon category. The
-- `builder(canvas)` callback is invoked lazily the first time the settings panel
-- is shown; the canvas frame exposes canvas:SetDefaultsHandler(fn).
-- Optional `sidebarLabel` colours/icons the Settings sidebar entry (e.g. rainbow
-- |cff escapes); `name` stays plain for sorting and the in-page header.
function ns:RegisterOptionsCanvas(name, builder, sidebarLabel)
	optionsCanvases[#optionsCanvases + 1] = {
		name = name,
		builder = builder,
		sidebar = sidebarLabel or name,
	}
end

local function BuildOptions()
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end

	local category
	if Settings.RegisterCanvasLayoutCategory then
		category = Settings.RegisterCanvasLayoutCategory(CreateLandingFrame(), ns.title)
	else
		category = Settings.RegisterVerticalLayoutCategory(ns.title)
	end
	ns.settingsCategory = category

	-- One subcategory (with its own layout) per themed group, listed
	-- alphabetically by (localised) title so the sidebar reads A, B, C...
	local groupCategory, groupLayout = {}, {}
	local ourCategories = {}
	if Settings.RegisterVerticalLayoutSubcategory then
		local sortedGroups = {}
		for i = 1, #GROUP_ORDER do
			sortedGroups[i] = GROUP_ORDER[i]
		end
		table.sort(sortedGroups, function(a, b) return a.title < b.title end)

		for i = 1, #sortedGroups do
			local g = sortedGroups[i]
			local sub, layout = Settings.RegisterVerticalLayoutSubcategory(category, GroupLabel(g))
			groupCategory[g.key] = sub
			groupLayout[g.key] = layout
			ourCategories[sub] = true

			-- Intro blurb at the top of the subcategory page.
			if g.desc and F.CreateSettingsDescription then
				local desc = F.CreateSettingsDescription(g.desc)
				if desc then layout:AddInitializer(desc) end
			end
		end
	end

	-- Copy + sort the module list so registration order does not dictate layout.
	local ordered = {}
	for i = 1, #ns.modules do
		ordered[i] = ns.modules[i]
	end
	table.sort(ordered, SortModules)

	for i = 1, #ordered do
		local module = ordered[i]
		if module.RegisterOptions then
			local key = groupCategory[module.group] and module.group or "misc"
			local moduleCategory = groupCategory[key] or category
			AddSectionHeader(groupLayout[key], module.title or module.name)
			OptionBuilder.layout = groupLayout[key]
			module:RegisterOptions(moduleCategory, OptionBuilder)
			OptionBuilder.layout = nil
		end
	end

	-- Custom canvas sub-pages (registered via ns:RegisterOptionsCanvas). These
	-- can only be registered after the modules run (that's when they're queued),
	-- so they trail the themed groups; sort them alphabetically among themselves.
	if Settings.RegisterCanvasLayoutSubcategory then
		table.sort(optionsCanvases, function(a, b) return a.name < b.name end)
		local panel = _G["SettingsPanel"]
		for i = 1, #optionsCanvases do
			local entry = optionsCanvases[i]
			local frame, canvas = CreateCanvasSubFrame(entry.name)
			Settings.RegisterCanvasLayoutSubcategory(category, frame, entry.sidebar)

			-- Build lazily on first show so we don't pay for the UI up front.
			if panel and entry.builder then
				local built = false
				panel:HookScript("OnShow", function()
					if not built then
						built = true
						entry.builder(canvas)
					end
				end)
			elseif entry.builder then
				entry.builder(canvas)
			end
		end
	end

	Settings.RegisterAddOnCategory(category)

	InstallHeaderDividerNudge(ourCategories)

	function ns:OpenOptions()
		if Settings.OpenToCategory then
			Settings.OpenToCategory(category.ID)
		elseif _G["C_SettingsUtil"] and _G["C_SettingsUtil"].OpenSettingsPanel then
			_G["C_SettingsUtil"].OpenSettingsPanel(category.ID)
		end
	end
end

ns:RegisterEvent("PLAYER_LOGIN", BuildOptions)
