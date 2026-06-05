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
	F.Print("  /nex changelog     -", L["Open the changelog"])
	F.Print("  /nex install       -", L["Open the setup screen"])
end

handlers.changelog = function(_)
	if ns.OpenChangelog then
		ns:OpenChangelog()
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
local GROUP_ORDER = {
	{ key = "actionbars", title = L["Action Bars"] },
	{ key = "unitframes", title = L["Unit Frames"] },
	{ key = "auras", title = L["Auras"] },
	{ key = "inventory", title = L["Inventory"] },
	{ key = "chat", title = L["Chat"] },
	{ key = "filters", title = L["Filters"] },
	{ key = "tooltip", title = L["Tooltip"] },
	{ key = "skins", title = L["Skins"] },
	{ key = "datatext", title = L["DataText"] },
	{ key = "maps", title = L["Maps"] },
	{ key = "automation", title = L["Automation"] },
	{ key = "announcements", title = L["Announcements"] },
	{ key = "misc", title = L["Miscellaneous"] },
}

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
	local frame = CreateFrame("Frame", "NexEnhanceOptionsLanding")

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

	local divider = header:CreateTexture(nil, "ARTWORK")
	divider:SetPoint("TOP", 0, -50)
	divider:SetAtlas("Options_HorizontalDivider", true)

	-- The container the builder draws into.
	local canvas = Mixin(CreateFrame("Frame", nil, frame), canvasMixin)
	canvas:SetPoint("BOTTOMLEFT", 0, 5)
	canvas:SetPoint("BOTTOMRIGHT", -12, 5)
	canvas:SetPoint("TOP", 0, -56)

	return frame, canvas
end

local optionsCanvases = {}

-- Public: register a custom canvas sub-page under the addon category. The
-- `builder(canvas)` callback is invoked lazily the first time the settings panel
-- is shown; the canvas frame exposes canvas:SetDefaultsHandler(fn).
function ns:RegisterOptionsCanvas(name, builder)
	optionsCanvases[#optionsCanvases + 1] = { name = name, builder = builder }
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
	if Settings.RegisterVerticalLayoutSubcategory then
		local sortedGroups = {}
		for i = 1, #GROUP_ORDER do
			sortedGroups[i] = GROUP_ORDER[i]
		end
		table.sort(sortedGroups, function(a, b) return a.title < b.title end)

		for i = 1, #sortedGroups do
			local g = sortedGroups[i]
			local sub, layout = Settings.RegisterVerticalLayoutSubcategory(category, g.title)
			groupCategory[g.key] = sub
			groupLayout[g.key] = layout
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
			module:RegisterOptions(moduleCategory, OptionBuilder)
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
			Settings.RegisterCanvasLayoutSubcategory(category, frame, entry.name)

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

	function ns:OpenOptions()
		if Settings.OpenToCategory then
			Settings.OpenToCategory(category.ID)
		elseif _G["C_SettingsUtil"] and _G["C_SettingsUtil"].OpenSettingsPanel then
			_G["C_SettingsUtil"].OpenSettingsPanel(category.ID)
		end
	end
end

ns:RegisterEvent("PLAYER_LOGIN", BuildOptions)
