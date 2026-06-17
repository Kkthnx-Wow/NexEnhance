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
local tonumber = tonumber
local ipairs = ipairs

local C_Map = C_Map
local C_AreaPoiInfo = C_AreaPoiInfo
local C_VignetteInfo = C_VignetteInfo
local C_UIWidgetManager = C_UIWidgetManager
local C_QuestLog = C_QuestLog

-- POI fields (names/descriptions) can be Secret in instanced content; guard every
-- value before tostring so the scan never errors on a secret. See the Midnight
-- Secret Values guide: tostring() on a secret value throws.
local function SafeStr(v)
	if v == nil then
		return "-"
	end
	if F.IsSecret(v) then
		return "<secret>"
	end
	return tostring(v)
end

-- Dump every widget in a POI's tooltipWidgetSet: type plus any timer/bar/text
-- value we can read. Used to discover where event countdowns (e.g. Stormarion's
-- "Next Assault") actually live so the datatext can parse the right field.
local function DumpWidgetSet(widgetSet)
	if not (widgetSet and C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID) then
		return
	end
	local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(widgetSet)
	if not widgets then
		return
	end
	local widgetManager = rawget(_G, "UIWidgetManager")
	for _, w in ipairs(widgets) do
		local info
		if widgetManager then
			local typeInfo = widgetManager:GetWidgetTypeInfo(w.widgetType)
			if typeInfo and typeInfo.visInfoDataFunction then
				info = typeInfo.visInfoDataFunction(w.widgetID)
			end
		end
		local detail = "-"
		if info then
			detail = format("text=%s timer=%s/%s bar=%s/%s/%s", SafeStr(info.text or info.headerText or info.overrideBarText), SafeStr(info.timerValue), SafeStr(info.timerMin), SafeStr(info.barValue), SafeStr(info.barMin), SafeStr(info.barMax))
		end
		F.Print(format("      w:%s type:%s | %s", SafeStr(w.widgetID), SafeStr(w.widgetType), detail))
	end
end

-- Dump one POI-id list (area POIs, events, quest hubs...) for a map. World events
-- like Stormarion Assault / Void Incursions are surfaced by GetEventsForMap, not
-- the plain GetAreaPOIForMap, which is why the first scan came up empty. Returns
-- how many lines were printed so the caller can detect a fully empty scan.
local function ScanPoiList(mapID, poiIDs, label)
	if not poiIDs or #poiIDs == 0 then
		return 0
	end

	local printed = 0
	for _, poiID in ipairs(poiIDs) do
		local poi = C_AreaPoiInfo.GetAreaPOIInfo(mapID, poiID)
		if poi then
			if printed == 0 then
				F.Print(F.Colorize(label .. ":", "brand"))
			end
			local secs = C_AreaPoiInfo.GetAreaPOISecondsLeft and C_AreaPoiInfo.GetAreaPOISecondsLeft(poiID)
			local widgetSet = poi.tooltipWidgetSet
			local widgetCount
			if widgetSet and C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID then
				local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(widgetSet)
				widgetCount = widgets and #widgets or 0
			end
			F.Print(format("  %d | %s | %s | poi:%s | widget:%s (%s) | locked:%s event:%s suppress:%s", poiID, SafeStr(poi.name), SafeStr(poi.atlasName), secs and SafeStr(secs) or "-", SafeStr(widgetSet), widgetCount and tostring(widgetCount) or "-", SafeStr(rawget(poi, "isLocked")), SafeStr(rawget(poi, "isCurrentEvent")), SafeStr(rawget(poi, "isSuppressible"))))
			DumpWidgetSet(widgetSet)
			printed = printed + 1
		end
	end
	return printed
end

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
	F.Print("  /nex rare          -", L["Toggle rare alert popup preview"])
	F.Print("  /nex afk           -", L["Toggle AFK camera preview"])
	F.Print("  /nex lootroll      -", L["Toggle loot roll test bars"])
	F.Print("  /nex questnotify   -", L["Toggle quest notification self-test"])
	F.Print("  /nex abandonquests -", L["Abandon every quest in your log"])
	F.Print("  /nex bordertest    -", L["Preview the tooltip border"])
	F.Print("  /nex changelog     -", L["Open the changelog"])
	F.Print("  /nex credits       -", L["Open the credits panel"])
	F.Print("  /nex profile       -", L["Open the profile import/export panel"])
	F.Print("  /nex install       -", L["Open the setup screen"])
	F.Print("  /nex poiscan       -", L["Dump area POIs on your current map (event setup)"])
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
	ns:TriggerCallback("SettingChanged." .. module.dbKey .. ".enable", settings.enable, module)
end

handlers.reminder = function(_)
	local module = ns:GetModule("Reminder")
	if module and module.ToggleTest then
		module:ToggleTest()
	else
		F.Print(F.Colorize(L["Buff Reminder"] .. ": ", "brand") .. L["Module unavailable."])
	end
end

handlers.rare = function(_)
	local module = ns:GetModule("RareAlert")
	if module and module.ToggleTest then
		module:ToggleTest()
	else
		F.Print(F.Colorize(L["Rare Alert"] .. ": ", "brand") .. L["Module unavailable."])
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

handlers.lootroll = function(_)
	local module = ns:GetModule("LootRoll")
	if module and module.ToggleTest then
		module:ToggleTest()
	else
		F.Print(F.Colorize(L["Loot Roll"] .. ": ", "brand") .. L["Module unavailable."])
	end
end

handlers.questnotify = function(_)
	local module = ns:GetModule("QuestNotification")
	if module and module.ToggleDebug then
		module:ToggleDebug()
	else
		F.Print(F.Colorize(L["Quest Notification"] .. ": ", "brand") .. L["Module unavailable."])
	end
end

-- Collect every quest the player is allowed to abandon. We gather questIDs up
-- front rather than abandoning while walking the log: AbandonQuest() removes the
-- entry, which reshuffles every index after it, so iterating-and-abandoning by
-- index would skip quests. World quests and session-locked quests are filtered
-- by CanAbandonQuest, but we guard the API surface in case a flavor lacks it.
local function CollectAbandonableQuests()
	local quests = {}
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then
		return quests
	end

	local numEntries = C_QuestLog.GetNumQuestLogEntries()
	for index = 1, numEntries do
		local info = C_QuestLog.GetInfo(index)
		if info and not info.isHeader and info.questID and info.questID > 0 then
			local canAbandon = true
			if C_QuestLog.CanAbandonQuest then
				canAbandon = C_QuestLog.CanAbandonQuest(info.questID)
			end
			if canAbandon then
				quests[#quests + 1] = info.questID
			end
		end
	end

	return quests
end

-- Abandon a list of questIDs. The modern flow selects the quest, caches it as the
-- abandon target (SetAbandonQuest reads GetSelectedQuest), then commits with
-- AbandonQuest(). Returns how many were actually removed.
local function AbandonQuestList(quests)
	if not (C_QuestLog and C_QuestLog.SetSelectedQuest and C_QuestLog.SetAbandonQuest and C_QuestLog.AbandonQuest) then
		return 0
	end

	local removed = 0
	for i = 1, #quests do
		local questID = quests[i]
		-- Re-check: a previous abandon (shared/chained quests) may have removed
		-- this one already, and CanAbandonQuest state can change mid-loop.
		local stillHave = not C_QuestLog.GetLogIndexForQuestID or C_QuestLog.GetLogIndexForQuestID(questID)
		if stillHave then
			C_QuestLog.SetSelectedQuest(questID)
			C_QuestLog.SetAbandonQuest()
			C_QuestLog.AbandonQuest()
			removed = removed + 1
		end
	end

	return removed
end

-- Confirm before wiping the quest log: AbandonQuest also destroys any quest items
-- tied to those quests, so this is destructive and gated behind a yes/no popup.
_G.StaticPopupDialogs["NEXENHANCE_ABANDON_ALL_QUESTS"] = {
	text = "%s",
	button1 = _G.YES,
	button2 = _G.NO,
	OnAccept = function(_, data)
		local quests = (data and data.quests) or CollectAbandonableQuests()
		local removed = AbandonQuestList(quests)
		F.Print(F.Colorize(L["Abandon All Quests"] .. ": ", "brand") .. format(L["Abandoned %d quest(s)."], removed))
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	showAlert = true,
	preferredIndex = 3,
}

handlers.abandonquests = function(_)
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then
		F.Print(F.Colorize(L["Abandon All Quests"] .. ": ", "brand") .. L["Quest log unavailable on this client."])
		return
	end

	local quests = CollectAbandonableQuests()
	local count = #quests
	if count == 0 then
		F.Print(F.Colorize(L["Abandon All Quests"] .. ": ", "brand") .. L["No abandonable quests in your log."])
		return
	end

	_G.StaticPopup_Show("NEXENHANCE_ABANDON_ALL_QUESTS", format(L["Abandon all %d quest(s) in your log? This cannot be undone."], count), nil, { quests = quests })
end

-- Border preview: a movable grid showing the tooltip border at several outsets
-- and edge sizes, in a default (white) and brand-tinted column. Toggle to close.
local borderTestFrame
handlers.bordertest = function(_)
	if borderTestFrame then
		borderTestFrame:SetShown(not borderTestFrame:IsShown())
		return
	end

	local f = CreateFrame("Frame", "NexEnhanceBorderTest", UIParent)
	f:SetSize(380, 392)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(f)
	-- Pink main backdrop + white inner panels so border edge alignment is obvious.
	bg:SetColorTexture(1, 0.2, 0.6, 0.95)
	F.MakeWindowMovable(f, "NexEnhanceBorderTest")

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -8)
	title:SetText(F.Colorize(L["Border Preview"], "brand"))

	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOM", 0, 8)
	hint:SetText(L["Drag to move - /nex bordertest to toggle"])

	-- Two columns: a neutral (white) border tint and a brand-tinted border.
	local cols = {
		{ label = L["Default"], color = { 1, 1, 1, 1 } },
		{ label = L["Tinted"], color = C.Colors.brand },
	}
	for c, col in ipairs(cols) do
		local hdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		hdr:SetPoint("TOPLEFT", f, "TOPLEFT", 24 + (c - 1) * 178 + 56, -36)
		hdr:SetText(F.Colorize(col.label, "brand"))
	end

	-- Rows: outset 0 pins the border on the panel edge; positive outset frames
	-- the panel from just outside it. edgeSize controls the tooltip border scale.
	local rows = {
		{ label = "outset 0", outset = 0, edgeSize = 16 },
		{ label = "outset 4", outset = 4, edgeSize = 16 },
		{ label = "edge 12", outset = 0, edgeSize = 12 },
		{ label = "edge 24", outset = 0, edgeSize = 24 },
	}
	for r, v in ipairs(rows) do
		for c, col in ipairs(cols) do
			local panel = CreateFrame("Frame", nil, f)
			panel:SetSize(150, 64)
			panel:SetPoint("TOPLEFT", f, "TOPLEFT", 24 + (c - 1) * 178, -56 - (r - 1) * 78)
			local pbg = panel:CreateTexture(nil, "BACKGROUND")
			pbg:SetAllPoints(panel)
			pbg:SetColorTexture(1, 1, 1, 1)
			F.CreateTooltipBackdrop(panel, {
				outset = v.outset,
				edgeSize = v.edgeSize,
				borderColor = col.color,
				noBackground = true,
			})
			local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			lbl:SetPoint("CENTER")
			lbl:SetText(v.label)
			lbl:SetTextColor(0, 0, 0)
		end
	end

	borderTestFrame = f
end

-- Dev/setup helper: dump every Area POI on the current map (or a passed map id)
-- with its id, name, atlas, remaining time and widget set. Used to capture the
-- live runtime IDs for new world events (Stormarion Assault, Void Incursions,
-- Abundance Harvest) that aren't published in wow-ui-source.
handlers.poiscan = function(rest)
	if not (C_Map and C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap) then
		F.Print(F.Colorize(L["POI scan unavailable on this client."], "red"))
		return
	end

	local mapID = tonumber(rest) or (C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
	if not mapID then
		F.Print(F.Colorize(L["No map found. Try: /nex poiscan <mapID>"], "red"))
		return
	end

	local mapInfo = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
	F.Print(F.Colorize(format(L["Area POIs on map %d (%s):"], mapID, mapInfo and mapInfo.name or "?"), "brand"))

	local total = 0
	total = total + ScanPoiList(mapID, C_AreaPoiInfo.GetAreaPOIForMap(mapID), L["POIs"])
	if C_AreaPoiInfo.GetEventsForMap then
		total = total + ScanPoiList(mapID, C_AreaPoiInfo.GetEventsForMap(mapID), L["Events"])
	end
	if C_AreaPoiInfo.GetQuestHubsForMap then
		total = total + ScanPoiList(mapID, C_AreaPoiInfo.GetQuestHubsForMap(mapID), L["Quest Hubs"])
	end
	if C_AreaPoiInfo.GetDelvesForMap then
		total = total + ScanPoiList(mapID, C_AreaPoiInfo.GetDelvesForMap(mapID), L["Delves"])
	end

	-- Vignettes are the live map/minimap markers (rares, treasures and some
	-- escalating events such as the Void Incursion progress marker). They're keyed
	-- by transient GUID, not map id, so we dump all currently-active ones.
	if C_VignetteInfo and C_VignetteInfo.GetVignettes then
		local guids = C_VignetteInfo.GetVignettes()
		if guids then
			local printed = 0
			for _, guid in ipairs(guids) do
				local v = C_VignetteInfo.GetVignetteInfo(guid)
				if v then
					if printed == 0 then
						F.Print(F.Colorize(L["Vignettes"] .. ":", "brand"))
					end
					F.Print(format("  %s | %s | %s", SafeStr(v.vignetteID), SafeStr(v.name), SafeStr(v.atlasName)))
					printed = printed + 1
				end
			end
			total = total + printed
		end
	end

	if total == 0 then
		F.Print("  " .. L["None reported - stand in the zone, or pass a map id: /nex poiscan <mapID>"])
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

	-- Broadcast on the internal bus so *other* modules can react to this change
	-- without a hard reference to the owning module. Subscribe with:
	--   ns:RegisterCallback("SettingChanged."..dbKey.."."..key, fn[, owner])
	if module.dbKey then
		ns:TriggerCallback("SettingChanged." .. module.dbKey .. "." .. key, value, module)
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
	if not Settings.CreateDropdown then
		return
	end

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
	if not Settings.CreateColorSwatch then
		return
	end

	local setting = RegisterSetting(category, module, key, name)
	local initializer = Settings.CreateColorSwatch(category, setting, tooltip)
	return setting, initializer
end

function OptionBuilder:EditBox(category, module, key, name, tooltip, width, onCommit)
	local layout = self.layout
	if not (layout and F.CreateSettingsEditBox) then
		return
	end

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

-- Multiline free-text row backed by caller-supplied get/set (e.g. account-wide
-- keyword tables). `opts`: width, boxHeight, onRestoreDefaults, restoreLabel.
function OptionBuilder:MultilineEditBox(category, name, tooltip, getValue, setValue, opts)
	local layout = self.layout
	if not (layout and F.CreateSettingsMultilineEditBox) then
		return
	end
	local initializer = F.CreateSettingsMultilineEditBox(name, tooltip, getValue, setValue, opts)
	if initializer then
		layout:AddInitializer(initializer)
	end
	return initializer
end

-- Add a section header (same style as the per-module headers) partway through a
-- module's options, to visually group a related cluster of settings.
function OptionBuilder:Header(text)
	local layout = self.layout
	if layout and _G["CreateSettingsListSectionHeaderInitializer"] then
		layout:AddInitializer(_G["CreateSettingsListSectionHeaderInitializer"](text))
	end
end

-- Add a read-only, wrapped description paragraph (e.g. live statistics). Returns
-- the initializer so callers can later update initializer:GetData().text; the
-- description template re-reads that text every time the page is displayed, so a
-- refreshed value shows the next time the user opens/returns to the page. Keep
-- the line count stable, as the reserved row height is measured once up front.
function OptionBuilder:Description(text)
	local layout = self.layout
	if not (layout and F.CreateSettingsDescription) then
		return
	end
	local initializer = F.CreateSettingsDescription(text)
	if initializer then
		layout:AddInitializer(initializer)
	end
	return initializer
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
	if childFont then
		return childFont
	end
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
	if not (child and parent and child.SetParentInitializer) then
		return
	end
	child.nexBumpFont = true
	child:SetParentInitializer(parent, function()
		local setting = parent:GetSetting()
		return setting and setting:GetValue()
	end)
end

-- Nest `child` under `parent` for purely visual grouping (indented) without
-- ever disabling it.
function OptionBuilder:Indent(child, parent)
	if not (child and parent and child.SetParentInitializer) then
		return
	end
	child.nexBumpFont = true
	child:SetParentInitializer(parent, function()
		return true
	end)
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
-- Sidebar category buttons are Blizzard's pooled/recycled frames, so we can't
-- reliably anchor a glow template onto them. The label is plain text we own,
-- though, so groups containing a freshly-added module get a brand-blue "New"
-- suffix - enough to draw the eye to which section to open.
local NEW_MARKER = "  " .. Brand(_G.NEW or "New") ---@diagnostic disable-line: undefined-field
local function GroupLabel(g, isNew)
	local suffix = isNew and NEW_MARKER or ""
	if not g.icon then
		return g.title .. suffix
	end
	if g.icon:find("\\", 1, true) then
		return format("|T%s:16:16:0:0|t %s%s", g.icon, g.title, suffix)
	end
	if CreateAtlasMarkup then
		return CreateAtlasMarkup(g.icon, 16, 16) .. " " .. g.title .. suffix
	end
	return g.title .. suffix
end

local GROUP_INDEX = {}
for i = 1, #GROUP_ORDER do
	GROUP_INDEX[GROUP_ORDER[i].key] = i
end

-- Stable ordering: by group, then the module's own order, then name.
local function SortModules(a, b)
	local ga = GROUP_INDEX[a.group or "misc"] or math.huge
	local gb = GROUP_INDEX[b.group or "misc"] or math.huge
	if ga ~= gb then
		return ga < gb
	end

	local oa, ob = a.order or 100, b.order or 100
	if oa ~= ob then
		return oa < ob
	end

	return a.name < b.name
end

-- Account-wide record of module names already shown to the player, so the
-- landing page can flag genuinely new modules after an update with a glowing
-- "New!" badge. Seeded wholesale the first time we ever run (and during the
-- install flow) so brand-new and first-upgrade users don't get the whole list
-- lit up - only modules added in *later* updates light up.
local function GetNewModules()
	if not ns.global then
		return {}
	end
	local known = ns.global.knownModules
	-- "Bootstrap" = the first time auto-detection runs (empty record), a fresh
	-- install, or mid-install. In that state we seed the existing line-up silently
	-- so untagged modules don't all light up at once.
	local bootstrap = (known == nil) or (next(known) == nil) or not ns.global.installed
	if not known then
		known = {}
		ns.global.knownModules = known
	end

	-- Modules explicitly tagged as added in the *current* version glow until the
	-- player dismisses this version's callout. This is tracked separately from the
	-- baseline `knownModules`, so a baseline that already lists them (e.g. seeded
	-- by an earlier build of this feature) can't wrongly suppress the badge.
	local dismissed = (ns.global.newSeen == ns.version)

	local result = {}
	for i = 1, #ns.modules do
		local m = ns.modules[i]
		if m.title then -- only user-facing modules (those shown in the options)
			if (m.since ~= nil) and (m.since == ns.version) then
				if not dismissed then
					result[#result + 1] = m
				end
			elseif not known[m.name] and bootstrap then
				known[m.name] = true -- seed silently
			elseif not known[m.name] then
				result[#result + 1] = m -- auto-detected addition from a later update
			end
		end
	end
	table.sort(result, SortModules)
	return result
end

-- True when a module is explicitly tagged as added in the running version and the
-- player hasn't yet acknowledged this version's "new" callout.
local function IsTaggedNew(module)
	return ns.global ~= nil and module.since ~= nil and module.since == ns.version and ns.global.newSeen ~= ns.version
end

-- Acknowledge the current version's new features: stamp the version (so the
-- landing callout and section-header badges stop showing next session) and fold
-- this version's tagged-new modules into the baseline, so a later version - where
-- the `since` tag is inert - doesn't re-flag them via auto-detection.
local function AcknowledgeNewVersion()
	if not ns.global or ns.global.newSeen == ns.version then
		return
	end
	ns.global.newSeen = ns.version
	local known = ns.global.knownModules
	if not known then
		known = {}
		ns.global.knownModules = known
	end
	for i = 1, #ns.modules do
		local m = ns.modules[i]
		if m.title and m.since == ns.version then
			known[m.name] = true
		end
	end
end

-- Section-header "New!" badge
--   Tag a section header initializer's data with `nexNew`, then a one-time hook on
--   the shared SettingsListSectionHeaderMixin:Init shows/hides a glowing badge on
--   the (pooled, recycled) header frame whenever it's bound to a tagged
--   initializer. Doing it in Init keeps it pooling-safe: the same frame is reused
--   for many headers, so we explicitly show OR hide every time it's initialised.
local CreateSettingsListSectionHeaderInitializer = _G["CreateSettingsListSectionHeaderInitializer"]
local SettingsListSectionHeaderMixin = _G["SettingsListSectionHeaderMixin"]
local sectionBadgeHooked = false

local function InstallSectionHeaderBadges()
	if sectionBadgeHooked or not SettingsListSectionHeaderMixin then
		return
	end
	sectionBadgeHooked = true
	hooksecurefunc(SettingsListSectionHeaderMixin, "Init", function(headerFrame, initializer)
		local data = initializer and initializer.GetData and initializer:GetData()
		local badge = headerFrame.nexNewBadge
		if data and data.nexNew then
			if not badge then
				badge = F.CreateNewFeatureBadge(headerFrame)
				if headerFrame.Title then
					badge:SetPoint("LEFT", headerFrame.Title, "RIGHT", 8, 0)
				else
					badge:SetPoint("LEFT", headerFrame, "LEFT", 4, 0)
				end
				headerFrame.nexNewBadge = badge
			end
			badge:Show()
		elseif badge then
			badge:Hide()
		end
	end)
end

local function AddSectionHeader(layout, text, isNew)
	if not (layout and CreateSettingsListSectionHeaderInitializer) then
		return
	end
	local init = CreateSettingsListSectionHeaderInitializer(text)
	if isNew and init and init.GetData then
		local data = init:GetData()
		if data then
			data.nexNew = true
		end
	end
	layout:AddInitializer(init)
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

	-- New-feature callout: flag modules added since the player last looked, with
	-- Blizzard's glowing "New!" badge so fresh modules are easy to spot. Dismissal
	-- is centralised (AcknowledgeNewVersion, fired when any NexEnhance page is
	-- opened), so this just renders.
	local newModules = GetNewModules()
	if #newModules > 0 then
		local block = CreateFrame("Frame", nil, frame)
		block:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -18)
		block:SetPoint("RIGHT", frame, "RIGHT", -24, 0)

		local nheading = MakeFontString(block, "GameFontNormalLarge")
		nheading:SetPoint("TOPLEFT")
		nheading:SetText(Brand(L["New This Update"]))

		local badge = F.CreateNewFeatureBadge(block)
		badge:SetPoint("LEFT", nheading, "RIGHT", 10, 1)

		local rowAnchor, totalH = nheading, nheading:GetStringHeight() or 16
		for i = 1, #newModules do
			local row = MakeFontString(block, "GameFontHighlight")
			row:SetPoint("TOPLEFT", rowAnchor, "BOTTOMLEFT", i == 1 and 6 or 0, i == 1 and -8 or -5)
			row:SetText("|cff888888• |r" .. (newModules[i].title or newModules[i].name))
			rowAnchor = row
			totalH = totalH + (row:GetStringHeight() or 12) + (i == 1 and 8 or 5)
		end
		block:SetHeight(totalH)
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

	-- First real use of the internal signal bus: keep the landing-page module
	-- count live when a module is toggled from Settings or `/nex toggle`.
	for i = 1, #ns.modules do
		local module = ns.modules[i]
		if module.dbKey then
			ns:RegisterCallback("SettingChanged." .. module.dbKey .. ".enable", "OnRefresh", frame)
		end
	end
	frame:OnRefresh()

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
		if divider then
			return divider
		end
		local list = panel:GetSettingsList()
		local header = list and list.Header
		if not header then
			return nil
		end
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
		if not tex then
			return
		end
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
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then
		return
	end

	InstallSectionHeaderBadges()

	local category
	if Settings.RegisterCanvasLayoutCategory then
		category = Settings.RegisterCanvasLayoutCategory(CreateLandingFrame(), ns.title)
	else
		category = Settings.RegisterVerticalLayoutCategory(ns.title)
	end
	ns.settingsCategory = category

	-- Which groups contain a module flagged new this version, so the sidebar entry
	-- can carry a "New" marker pointing the user at the right section.
	local groupHasNew = {}
	for i = 1, #ns.modules do
		local m = ns.modules[i]
		if m.title and IsTaggedNew(m) then
			groupHasNew[m.group or "misc"] = true
		end
	end

	-- One subcategory (with its own layout) per themed group, listed
	-- alphabetically by (localised) title so the sidebar reads A, B, C...
	local groupCategory, groupLayout = {}, {}
	local ourCategories = {}
	if Settings.RegisterVerticalLayoutSubcategory then
		local sortedGroups = {}
		for i = 1, #GROUP_ORDER do
			sortedGroups[i] = GROUP_ORDER[i]
		end
		table.sort(sortedGroups, function(a, b)
			return a.title < b.title
		end)

		for i = 1, #sortedGroups do
			local g = sortedGroups[i]
			local sub, layout = Settings.RegisterVerticalLayoutSubcategory(category, GroupLabel(g, groupHasNew[g.key]))
			groupCategory[g.key] = sub
			groupLayout[g.key] = layout
			ourCategories[sub] = true

			-- Intro blurb at the top of the subcategory page.
			if g.desc and F.CreateSettingsDescription then
				local desc = F.CreateSettingsDescription(g.desc)
				if desc then
					layout:AddInitializer(desc)
				end
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
			AddSectionHeader(groupLayout[key], module.title or module.name, IsTaggedNew(module))
			OptionBuilder.layout = groupLayout[key]
			module:RegisterOptions(moduleCategory, OptionBuilder)
			OptionBuilder.layout = nil
		end
	end

	-- Custom canvas sub-pages (registered via ns:RegisterOptionsCanvas). These
	-- can only be registered after the modules run (that's when they're queued),
	-- so they trail the themed groups; sort them alphabetically among themselves.
	if Settings.RegisterCanvasLayoutSubcategory then
		table.sort(optionsCanvases, function(a, b)
			return a.name < b.name
		end)
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

	-- Acknowledge "New This Update" badges (landing callout + section headers)
	-- once the player actually opens any NexEnhance page; they then clear from the
	-- next session on.
	do
		local panel = _G["SettingsPanel"]
		if panel and panel.DisplayCategory and not panel.nexNewSeenHooked then
			panel.nexNewSeenHooked = true
			hooksecurefunc(panel, "DisplayCategory", function(_, cat)
				if cat == category or ourCategories[cat] then
					AcknowledgeNewVersion()
				end
			end)
		end
	end

	function ns:OpenOptions()
		if Settings.OpenToCategory then
			Settings.OpenToCategory(category.ID)
		elseif _G["C_SettingsUtil"] and _G["C_SettingsUtil"].OpenSettingsPanel then
			_G["C_SettingsUtil"].OpenSettingsPanel(category.ID)
		end
	end
end

ns:RegisterEvent("PLAYER_LOGIN", BuildOptions)
