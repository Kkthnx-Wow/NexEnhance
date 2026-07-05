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

local ShowUIPanel = ShowUIPanel
local LoadAddOn = LoadAddOn

-- Mirror Blizzard_ChatFrameBase/Mainline/SlashCommandsOverrides.lua (EDITMODE).
local function OpenEditMode()
	local frame = _G.EditModeManagerFrame
	if not frame and LoadAddOn then
		pcall(LoadAddOn, "Blizzard_EditMode")
		frame = _G.EditModeManagerFrame
	end
	if not frame then
		F.Print(L["Edit Mode is not available right now."])
		return
	end
	if frame.CanEnterEditMode and not frame:CanEnterEditMode() then
		local msg = _G.ERROR_SLASH_EDITMODE_CANNOT_ENTER
		if msg and _G.ChatFrameUtil and ChatFrameUtil.DisplaySystemMessageInPrimary then
			ChatFrameUtil.DisplaySystemMessageInPrimary(msg)
		else
			F.Print(L["Cannot enter Edit Mode right now."])
		end
		return
	end
	ShowUIPanel(frame)
end

-- Key bindings live in Settings (Settings.KEYBINDINGS_CATEGORY_ID from
-- Blizzard_SettingsDefinitions_Frame/Keybindings.lua); no global /keybinds slash.
local function OpenKeyBindings()
	local catID = Settings and Settings.KEYBINDINGS_CATEGORY_ID
	if not catID then
		F.Print(L["Key Bindings settings are not available right now."])
		return
	end
	if Settings.OpenToCategory then
		Settings.OpenToCategory(catID)
	elseif _G.C_SettingsUtil and C_SettingsUtil.OpenSettingsPanel then
		C_SettingsUtil.OpenSettingsPanel(catID)
	else
		F.Print(L["Key Bindings settings are not available right now."])
	end
end

-- ---------------------------------------------------------------------------
-- Slash command handlers
-- ---------------------------------------------------------------------------
local handlers = {}

handlers.help = function(_)
	F.Print(F.Colorize(L["Usage"] .. ":", "brand"))
	F.Print("  /nex help          -", L["Show this help"])
	F.Print("  /nex modules       -", L["List modules and their state"])
	F.Print("  /nex plugins       -", L["List installed NexEnhance plugins"])
	F.Print("  /nex toggle <name> -", L["Toggle a module: /nex toggle <module>"])
	F.Print("  /nex config        -", L["Open the options panel"])
	F.Print("  /nex editmode, em  -", L["Open Edit Mode (same as /editmode)"])
	F.Print("  /nex keybinds, kb  -", L["Open Key Bindings in Settings"])
	F.Print("  /nex reminder      -", L["Toggle buff reminder test icons"])
	F.Print("  /nex rare          -", L["Toggle rare alert popup preview"])
	F.Print("  /nex afk           -", L["Toggle AFK camera preview"])
	F.Print("  /nex lootroll      -", L["Toggle loot roll test bars"])
	F.Print("  /nex alerttest     -", L["Toggle alert frame test previews"])
	F.Print("  /nex questnotify   -", L["Toggle quest notification self-test"])
	F.Print("  /nex quickquest    -", L["Toggle Quick Quest debug logging"])
	F.Print("  /nex way <coords>  -", L["Set a user map waypoint (TomTom-style)"])
	F.Print("  /nex abandonquests -", L["Abandon every quest in your log"])
	F.Print("  /nex bordertest    -", L["Preview the tooltip border"])
	F.Print("  /nex changelog     -", L["Open the changelog"])
	F.Print("  /nex credits       -", L["Open the credits panel"])
	F.Print("  /nex profile       -", L["Open the profile import/export panel"])
	F.Print("  /nex install       -", L["Open the setup screen"])
	F.Print("  /nex uiscale         -", L["Dump UI scale and chat dock debug info"])
	F.Print("  /nex uiscale apply   -", L["Force UI scale apply now"])
	F.Print("  /nex debug           -", L["Debug system help (dumps, logging, export)"])
	F.Print("  /nex poiscan       -", L["Dump area POIs on your current map (event setup)"])
	F.Print("  /nex newreset      -", L["Reset new-update badges for testing"])
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

handlers.uiscale = function(rest)
	rest = (rest or ""):lower()
	if rest == "apply" then
		if ns.ApplyUIScaleNow then
			ns:ApplyUIScaleNow()
			F.Print(L["UIScale apply requested"])
		end
		return
	end
	if ns.Debug then
		ns.Debug.PrintEnvironment()
		ns.Debug.DumpScope("uiscale")
	end
end

handlers.debug = function(rest)
	if ns.Debug then
		ns.Debug.HandleSlash(rest)
	end
end

handlers.newreset = function(_)
	if ns.global then
		ns.global.newSeen = nil
	end
	F.Print(L["New update badges reset. Reload your UI, then open Settings."])
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
		F.Print(F.Colorize(format(L["Unknown module '%s'."], name), "red"))
		return
	end

	local settings = ns.db[module.dbKey]
	settings.enable = not settings.enable
	local state = settings.enable and F.Colorize(L["Enabled"], "green") or F.Colorize(L["Disabled"], "red")
	local label = module.title or module.name
	F.Print(label, "->", state)
	if module.isPlugin then
		ns:ApplyPluginEnable(module, settings.enable)
	end
	if module.OnSettingChanged then
		module:OnSettingChanged("enable", settings.enable)
	end
	ns:TriggerCallback("SettingChanged." .. module.dbKey .. ".enable", settings.enable, module)
end

handlers.plugins = function(_)
	local list = ns:GetPlugins()
	if #list == 0 then
		F.Print(F.Colorize(L["Plugins"], "brand") .. ": " .. L["PLUGIN_NONE_INSTALLED"])
		return
	end
	F.Print(F.Colorize(L["Plugins"], "brand") .. " (" .. #list .. "):")
	for i = 1, #list do
		local plugin = list[i]
		local state = plugin:IsEnabled() and F.Colorize(L["Enabled"], "green") or F.Colorize(L["Disabled"], "red")
		F.Print(format("  %s v%s — %s (%s)", plugin.title or plugin.name, plugin.pluginVersion or "?", plugin.author or L["Unknown"], state))
	end
	F.Print(L["PLUGIN_OPEN_SETTINGS_HINT"])
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

handlers.alerttest = function(_)
	local module = ns:GetModule("AlertFrames")
	if module and module.ToggleTest then
		module:ToggleTest()
	else
		F.Print(F.Colorize(L["Alert Frames"] .. ": ", "brand") .. L["Module unavailable."])
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

handlers.quickquest = function(_)
	local module = ns:GetModule("QuickQuest")
	if module and module.ToggleDebug then
		module:ToggleDebug()
	else
		F.Print(F.Colorize(L["Quick Quest"] .. ": ", "brand") .. L["Module unavailable."])
	end
end

handlers.way = function(rest)
	local module = ns:GetModule("MapPinNavigation")
	if module and module.HandleWaypointSlash then
		module:HandleWaypointSlash(rest)
	else
		F.Print(F.Colorize(L["Map Pin Navigation"] .. ": ", "brand") .. L["Module unavailable."])
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
		handlers.help()
	end
end

handlers.editmode = function(_)
	OpenEditMode()
end

handlers.em = handlers.editmode

handlers.keybinds = function(_)
	OpenKeyBindings()
end

handlers.kb = handlers.keybinds
handlers.binds = handlers.keybinds

local function HandleSlash(input)
	input = (input or ""):match("^%s*(.-)%s*$") or ""
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
	if key == "enable" and module.isPlugin then
		ns:ApplyPluginEnable(module, value)
	end

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
		if onSettingVisualRefresh then
			onSettingVisualRefresh(module.dbKey, setting)
		end
	end)

	-- Keep every registered setting keyed by module so the per-option and
	-- per-section revert controls can call setting:SetValueToDefault() later.
	ns.nexSettings = ns.nexSettings or {}
	local bucket = ns.nexSettings[module.dbKey]
	if not bucket then
		bucket = {}
		ns.nexSettings[module.dbKey] = bucket
	end
	bucket[key] = setting

	return setting
end

-- Tag a control initializer so the shared SettingsListElementMixin hook knows it
-- owns a NexEnhance setting and can attach the hover-revert icon (see below).
local function MarkResettable(initializer)
	if initializer then
		initializer.nexRevert = true
	end
	return initializer
end

function OptionBuilder:Checkbox(category, module, key, name, tooltip)
	local setting = RegisterSetting(category, module, key, name)
	local initializer = Settings.CreateCheckbox(category, setting, tooltip)
	return setting, MarkResettable(initializer)
end

function OptionBuilder:Slider(category, module, key, name, tooltip, minValue, maxValue, step, formatValue)
	local setting = RegisterSetting(category, module, key, name)

	local options = Settings.CreateSliderOptions(minValue, maxValue, step)
	if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
		if type(formatValue) == "function" then
			options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatValue)
		else
			options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
		end
	end
	local initializer = Settings.CreateSlider(category, setting, options, tooltip)
	return setting, MarkResettable(initializer)
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
	return setting, MarkResettable(initializer)
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
	return setting, MarkResettable(initializer)
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
		initializer.GetSetting = function()
			return setting
		end
		layout:AddInitializer(MarkResettable(initializer))
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

-- ---------------------------------------------------------------------------
-- Per-option revert
--   Every NexEnhance setting registers with a default value (RegisterSetting),
--   so any control row can be reset in place via setting:SetValueToDefault(),
--   which fires the same value-changed callback as a normal edit (live-apply,
--   OnSettingChanged and the callback bus all run — no /reload).
--
--   We tag our control initializers (nexRevert) in the builder, then a single
--   hook on the shared SettingsListElementMixin:Init attaches a small
--   `transmog-icon-revert` button just left of the row label. It only appears
--   while the row's label (its Tooltip hover region) is hovered AND the current
--   value differs from default, so default rows stay clean and un-cluttered.
-- ---------------------------------------------------------------------------
local REVERT_ATLAS = "transmog-icon-revert"
local REVERT_SIZE = 15

-- Pooled settings rows are recycled; track live rows weakly so section reset can
-- hide per-option revert icons without waiting for a fresh hover.
local revertRows = setmetatable({}, { __mode = "k" })

local function TrackRevertRow(row)
	if row then
		revertRows[row] = true
	end
end

local function UntrackRevertRow(row)
	if row then
		revertRows[row] = nil
	end
end

local function RowIsDirty(row)
	local setting = row.nexRevertSetting
	if not setting then
		return false
	end
	-- Colour swatches store hex strings; equality still holds for a plain compare.
	return setting:GetValue() ~= setting:GetDefaultValue()
end

local function RefreshRevertButton(row)
	local btn = row.nexRevertButton
	if not btn then
		return
	end
	btn:SetShown((row.nexHoverRow or row.nexHoverBtn) and RowIsDirty(row))
end

local function RefreshAllRevertRows()
	for row in pairs(revertRows) do
		RefreshRevertButton(row)
	end
end

local function RefreshRevertRowsForSetting(setting)
	if not setting then
		return
	end
	for row in pairs(revertRows) do
		if row.nexRevertSetting == setting then
			RefreshRevertButton(row)
		end
	end
end

-- Fired after every live setting change so revert icons + section headers stay in sync.
local onSettingVisualRefresh

local function EnsureRevertButton(row)
	local btn = row.nexRevertButton
	if btn then
		return btn
	end

	local region = row.Tooltip or row
	btn = CreateFrame("Button", nil, region)
	btn:SetSize(REVERT_SIZE, REVERT_SIZE)
	btn:SetFrameLevel(region:GetFrameLevel() + 5)
	-- Sit just left of the label text (Blizzard anchors labels at indent + 37).
	if row.Text then
		btn:SetPoint("RIGHT", row.Text, "LEFT", -4, 0)
	end
	btn:Hide()

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetAtlas(REVERT_ATLAS)

	btn:SetScript("OnEnter", function(self)
		row.nexHoverBtn = true
		RefreshRevertButton(row)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L["Reset to default"])
		GameTooltip:AddLine(L["Reset this option to its default value."], 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function()
		row.nexHoverBtn = false
		GameTooltip:Hide()
		-- Defer: leaving the icon back onto the row shouldn't hide-then-flicker.
		if C_Timer and C_Timer.After then
			C_Timer.After(0, function()
				RefreshRevertButton(row)
			end)
		else
			RefreshRevertButton(row)
		end
	end)
	btn:SetScript("OnClick", function()
		if row.nexRevertSetting then
			row.nexRevertSetting:SetValueToDefault()
			RefreshRevertButton(row)
		end
	end)

	row.nexRevertButton = btn
	return btn
end

-- Reveal/hide the icon as the label's hover region (the Tooltip child that also
-- drives Blizzard's own row hover/tooltip) is entered and left. Deferring the
-- leave lets the button's own OnEnter win when the pointer moves onto the icon.
local function HookRowHover(row)
	local region = row.Tooltip or row
	if row.nexRevertHoverHooked then
		return
	end
	row.nexRevertHoverHooked = true
	region:HookScript("OnEnter", function()
		row.nexHoverRow = true
		RefreshRevertButton(row)
	end)
	region:HookScript("OnLeave", function()
		row.nexHoverRow = false
		if C_Timer and C_Timer.After then
			C_Timer.After(0, function()
				RefreshRevertButton(row)
			end)
		else
			RefreshRevertButton(row)
		end
	end)
end

-- Rows are pooled and recycled across every Settings page (ours and Blizzard's),
-- so we re-evaluate on each Init: only our tagged initializers get a live button.
local function UpdateRowRevert(row, initializer)
	row.nexRevertSetting = nil
	local resettable = initializer and initializer.nexRevert and initializer.GetSetting
	local setting = resettable and initializer:GetSetting()
	if not setting then
		UntrackRevertRow(row)
		if row.nexRevertButton then
			row.nexRevertButton:Hide()
		end
		return
	end
	row.nexRevertSetting = setting
	TrackRevertRow(row)
	EnsureRevertButton(row)
	HookRowHover(row)
	RefreshRevertButton(row)
end

local function InstallRowRevertHooks()
	if ns.__settingsRowRevertHooked then
		return
	end
	ns.__settingsRowRevertHooked = true

	local elementMixin = _G["SettingsListElementMixin"]
	if elementMixin then
		hooksecurefunc(elementMixin, "Init", function(self, initializer)
			if initializer and initializer.nexBumpFont and self.Text then
				self.Text:SetFontObject(GetChildFont())
			end
			UpdateRowRevert(self, initializer)
		end)
		hooksecurefunc(elementMixin, "Release", function(self)
			UntrackRevertRow(self)
			self.nexRevertSetting = nil
			self.nexHoverRow = nil
			self.nexHoverBtn = nil
		end)
	end

	local editMixin = _G["NexEnhanceSettingsEditBoxMixin"]
	if editMixin then
		hooksecurefunc(editMixin, "Init", function(self, initializer)
			UpdateRowRevert(self, initializer)
		end)
		hooksecurefunc(editMixin, "Release", function(self)
			UntrackRevertRow(self)
			self.nexRevertSetting = nil
			self.nexHoverRow = nil
			self.nexHoverBtn = nil
		end)
	end
end

InstallRowRevertHooks()

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
	{ key = "nameplates", title = L["Nameplates"], icon = [[Interface\ICONS\Ability_Hunter_SniperShot]], desc = L["DESC_NAMEPLATES"] },
	{ key = "auras", title = L["Auras"], icon = [[Interface\ICONS\Spell_Holy_WordFortitude]], desc = L["DESC_AURAS"] },
	{ key = "inventory", title = L["Inventory"], icon = [[Interface\ICONS\INV_Misc_Bag_08]], desc = L["DESC_INVENTORY"] },
	{ key = "chat", title = L["Chat"], icon = [[Interface\ICONS\INV_Letter_15]], desc = L["DESC_CHAT"] },
	{ key = "filters", title = L["Filters"], icon = [[Interface\ICONS\INV_Misc_Spyglass_02]], desc = L["DESC_FILTERS"] },
	{ key = "tooltip", title = L["Tooltip"], icon = [[Interface\ICONS\INV_Misc_Note_01]], desc = L["DESC_TOOLTIP"] },
	{ key = "skins", title = L["Skins"], icon = [[Interface\ICONS\INV_Shirt_GuildTabard_01]], desc = L["DESC_SKINS"] },
	{ key = "datatext", title = L["DataText"], icon = [[Interface\ICONS\INV_Misc_PocketWatch_01]], desc = L["DESC_DATATEXT"] },
	{ key = "maps", title = L["Maps"], icon = [[Interface\ICONS\INV_Misc_Map_01]], desc = L["DESC_MAPS"] },
	{ key = "plugins", title = L["Plugins"], icon = [[Interface\ICONS\INV_Misc_Gear_01]], desc = L["DESC_PLUGINS"] },
	{ key = "automation", title = L["Automation"], icon = [[Interface\ICONS\INV_Gizmo_01]], desc = L["DESC_AUTOMATION"] },
	{ key = "announcements", title = L["Announcements"], icon = [[Interface\ICONS\INV_Misc_Horn_01]], desc = L["DESC_ANNOUNCEMENTS"] },
	{ key = "camera", title = L["Camera"], icon = [[Interface\ICONS\INV_Misc_Spyglass_03]], desc = L["DESC_CAMERA"] },
	{ key = "alerts", title = L["Alerts"], icon = [[Interface\ICONS\INV_Misc_Bell_01]], desc = L["DESC_ALERTS"] },
	{ key = "movers", title = L["Movers"], icon = [[Interface\ICONS\INV_Misc_Wrench_01]], desc = L["DESC_MOVERS"] },
	{ key = "misc", title = L["Miscellaneous"], icon = [[Interface\ICONS\INV_Misc_QuestionMark]], desc = L["DESC_MISC"] },
}

-- Sidebar labels are plain text; icons are drawn as Texture widgets (SetTexCoord)
-- so every entry crops to the same square. Borders + notification dots anchor
-- to that texture in InstallCategorySidebarBadges.
local SIDEBAR_NEW_ATLAS = "UI-HUD-MicroMenu-Communities-Icon-Notification"
local SIDEBAR_NEW_DOT_SIZE = 19
local SIDEBAR_NEW_DOT_GAP = 2
local SIDEBAR_ICON_BORDER_ATLAS = "Soulbinds_Collection_SpecBorder_Primary"
local SIDEBAR_ICON_SIZE = 16
local SIDEBAR_ICON_BORDER_SIZE = 26
local SIDEBAR_ICON_GAP = 4

local function GroupLabel(g)
	if g.key == "plugins" then
		return F.Colorize(g.title, "gray")
	end
	if g.key == "general" then
		return F.Colorize(g.title, "header")
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

-- Build a name -> true lookup of modules flagged by GetNewModules (tagged *or*
-- auto-detected). Sidebar markers and section-header badges must use the same
-- rules as the landing-page callout, not IsTaggedNew alone.
local function BuildNewModuleLookup()
	local lookup = {}
	local list = GetNewModules()
	for i = 1, #list do
		lookup[list[i].name] = true
	end
	return lookup
end

-- Acknowledge the current version's new features: stamp the version (so the
-- landing callout and section-header badges stop showing next session) and fold
-- every module that was flagged as new into the baseline.
local RefreshSidebarNewBadges

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
	local list = GetNewModules()
	for i = 1, #list do
		known[list[i].name] = true
	end
	RefreshSidebarNewBadges()
end

-- Sidebar categories flagged during BuildOptions.
local sidebarNewCategories = {}
local sidebarCategoryIcons = {}
local SettingsCategoryListButtonMixin = _G["SettingsCategoryListButtonMixin"]
local SettingsCategoryListMixin = _G["SettingsCategoryListMixin"]
local sidebarBadgeHooked = false

local function ShouldShowSidebarNewDot(category)
	return category and sidebarNewCategories[category] and ns.global and ns.global.newSeen ~= ns.version
end

local function ApplySidebarIconTexture(tex, iconPath)
	if iconPath:find("\\", 1, true) or iconPath:find("/", 1, true) then
		pcall(tex.SetAtlas, tex, nil)
		tex:SetTexture(iconPath)
		tex:SetTexCoord(C.TexCoord[1], C.TexCoord[2], C.TexCoord[3], C.TexCoord[4])
	else
		tex:SetTexture(nil)
		tex:SetAtlas(iconPath)
		tex:SetTexCoord(0, 1, 0, 1)
	end
end

local function UpdateCategorySidebarChrome(button, category)
	if not button then
		return
	end

	local iconPath = category and sidebarCategoryIcons[category]
	local label = button.Label

	if iconPath and label then
		local icon = button.nexSidebarIcon
		if not icon then
			icon = button:CreateTexture(nil, "ARTWORK", nil, 2)
			icon:SetSize(SIDEBAR_ICON_SIZE, SIDEBAR_ICON_SIZE)
			icon:SetPoint("RIGHT", label, "LEFT", -SIDEBAR_ICON_GAP, 0)
			button.nexSidebarIcon = icon
		end
		ApplySidebarIconTexture(icon, iconPath)
		icon:SetDrawLayer("ARTWORK", 2)
		icon:Show()

		local border = button.nexIconBorder
		if not border then
			border = button:CreateTexture(nil, "ARTWORK", nil, 4)
			border:SetAtlas(SIDEBAR_ICON_BORDER_ATLAS)
			border:SetSize(SIDEBAR_ICON_BORDER_SIZE, SIDEBAR_ICON_BORDER_SIZE)
			border:SetPoint("CENTER", icon, "CENTER")
			button.nexIconBorder = border
		end
		border:SetDrawLayer("ARTWORK", 4)
		border:Show()

		if ShouldShowSidebarNewDot(category) then
			local dotFrame = button.nexNewDotFrame
			if not dotFrame then
				dotFrame = CreateFrame("Frame", nil, button)
				dotFrame:SetFrameStrata("HIGH")
				dotFrame:SetFrameLevel(button:GetFrameLevel() + 20)
				local tex = dotFrame:CreateTexture(nil, "OVERLAY")
				tex:SetAllPoints()
				tex:SetAtlas(SIDEBAR_NEW_ATLAS)
				button.nexNewDotFrame = dotFrame
			end
			dotFrame:SetSize(SIDEBAR_NEW_DOT_SIZE, SIDEBAR_NEW_DOT_SIZE)
			dotFrame:ClearAllPoints()
			dotFrame:SetPoint("RIGHT", icon, "LEFT", -SIDEBAR_NEW_DOT_GAP, -2)
			dotFrame:Show()
		elseif button.nexNewDotFrame then
			button.nexNewDotFrame:Hide()
		end
	elseif button.nexSidebarIcon then
		button.nexSidebarIcon:Hide()
		if button.nexIconBorder then
			button.nexIconBorder:Hide()
		end
		if button.nexNewDotFrame then
			button.nexNewDotFrame:Hide()
		end
	end
end

local function RefreshAllSidebarDots(listMixin)
	local scroll = listMixin and listMixin.ScrollBox
	if not scroll then
		local panel = _G["SettingsPanel"]
		scroll = panel and panel.CategoryList and panel.CategoryList.ScrollBox
	end
	if not (scroll and scroll.ForEachFrame) then
		return
	end
	scroll:ForEachFrame(function(button)
		local elementData = button.GetElementData and button:GetElementData()
		local cat = elementData and elementData.data and elementData.data.category
		if cat then
			UpdateCategorySidebarChrome(button, cat)
		end
	end)
end

RefreshSidebarNewBadges = function()
	local panel = _G["SettingsPanel"]
	RefreshAllSidebarDots(panel and panel.CategoryList)
end

local function InstallCategorySidebarBadges()
	if sidebarBadgeHooked or not SettingsCategoryListButtonMixin then
		return
	end
	sidebarBadgeHooked = true

	hooksecurefunc(SettingsCategoryListButtonMixin, "Init", function(button, initializer)
		local category = initializer and initializer.data and initializer.data.category
		UpdateCategorySidebarChrome(button, category)
	end)

	if SettingsCategoryListMixin then
		hooksecurefunc(SettingsCategoryListMixin, "CreateCategories", function(listMixin)
			-- Buttons are rebuilt asynchronously after the data provider updates.
			if C_Timer and C_Timer.After then
				C_Timer.After(0, function()
					RefreshAllSidebarDots(listMixin)
				end)
			else
				RefreshAllSidebarDots(listMixin)
			end
		end)
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

-- Section reset: revert every registered setting under a module's dbKey to its
-- default. Because SetValueToDefault fires each setting's value-changed callback,
-- modules live-apply exactly as they would for individual edits.
local function SectionHasDirty(dbKey)
	local bucket = ns.nexSettings and ns.nexSettings[dbKey]
	if not bucket then
		return false
	end
	for _, setting in pairs(bucket) do
		if setting:GetValue() ~= setting:GetDefaultValue() then
			return true
		end
	end
	return false
end

local function ResetSection(dbKey)
	local bucket = ns.nexSettings and ns.nexSettings[dbKey]
	if not bucket then
		return
	end
	for _, setting in pairs(bucket) do
		if setting:GetValue() ~= setting:GetDefaultValue() then
			setting:SetValueToDefault()
		end
	end
end

_G.StaticPopupDialogs["NEXENHANCE_RESET_SECTION"] = {
	text = "%s",
	button1 = _G.YES,
	button2 = _G.NO,
	OnAccept = function(_, data)
		if data and data.dbKey then
			ResetSection(data.dbKey)
			if data.onDone then
				data.onDone()
			end
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local SECTION_REVERT_ATLAS = "transmog-icon-revert-small"

-- Section-header title anchor from the template (TOPLEFT x=7 y=-16). We shift the
-- title right by ICON_SLOT while a reset icon is showing so the icon sits in the
-- gap to the *left* of the name, then restore it for pristine/other headers.
local SECTION_TITLE_X = 7
local SECTION_TITLE_Y = -16
local SECTION_ICON_SLOT = 22

-- Forward declaration: the button scripts below reference UpdateSectionReset,
-- which is defined further down (keeps the local out of the global namespace).
local UpdateSectionReset

-- Pooled section headers keyed by module dbKey (weak keys — frames are recycled).
local sectionHeadersByKey = {}

local function UntrackSectionHeader(headerFrame)
	local oldKey = headerFrame.nexTrackedResetKey
	if oldKey and sectionHeadersByKey[oldKey] then
		sectionHeadersByKey[oldKey][headerFrame] = nil
	end
	headerFrame.nexTrackedResetKey = nil
end

local function TrackSectionHeader(headerFrame, dbKey, title)
	UntrackSectionHeader(headerFrame)
	if not dbKey then
		return
	end
	headerFrame.nexTrackedResetKey = dbKey
	headerFrame.nexResetTitle = title
	local bucket = sectionHeadersByKey[dbKey]
	if not bucket then
		bucket = setmetatable({}, { __mode = "k" })
		sectionHeadersByKey[dbKey] = bucket
	end
	bucket[headerFrame] = true
end

local function RefreshSectionHeaders(dbKey)
	local bucket = dbKey and sectionHeadersByKey[dbKey]
	if not bucket then
		return
	end
	for headerFrame in pairs(bucket) do
		UpdateSectionReset(headerFrame, dbKey, headerFrame.nexResetTitle)
	end
end

-- Scripts are bound once (below) and read the live dbKey/title from button fields,
-- so re-initialising a pooled header row costs no closure allocation.
local function SectionResetButton_OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(L["Reset Section"])
	GameTooltip:AddLine(L["Reset every option in this section to its default value."], 0.8, 0.8, 0.8, true)
	GameTooltip:Show()
end

local function SectionResetButton_OnClick(self)
	local dbKey = self.nexDbKey
	if not dbKey then
		return
	end
	local header = self:GetParent()
	_G.StaticPopup_Show("NEXENHANCE_RESET_SECTION", format(L["SECTION_RESET_CONFIRM"], self.nexTitle or ""), nil, {
		dbKey = dbKey,
		onDone = function()
			UpdateSectionReset(header, dbKey, self.nexTitle)
			RefreshAllRevertRows()
		end,
	})
end

-- Attach (once, then reuse) a revert icon to the LEFT of a section header title.
-- Shown only for headers tagged with a module dbKey that currently has at least
-- one non-default value, so pristine sections carry no button.
function UpdateSectionReset(headerFrame, dbKey, title)
	TrackSectionHeader(headerFrame, dbKey, title)

	local btn = headerFrame.nexResetButton
	local titleFS = headerFrame.Title

	if not (dbKey and SectionHasDirty(dbKey)) then
		if btn then
			btn:Hide()
		end
		-- Restore the default title position (frames are pooled across sections).
		if titleFS then
			titleFS:ClearAllPoints()
			titleFS:SetPoint("TOPLEFT", SECTION_TITLE_X, SECTION_TITLE_Y)
		end
		return
	end

	if not btn then
		btn = CreateFrame("Button", nil, headerFrame)
		btn:SetSize(18, 17)
		local icon = btn:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints()
		icon:SetAtlas(SECTION_REVERT_ATLAS)
		btn:SetScript("OnEnter", SectionResetButton_OnEnter)
		btn:SetScript("OnLeave", GameTooltip_Hide)
		btn:SetScript("OnClick", SectionResetButton_OnClick)
		headerFrame.nexResetButton = btn
	end

	btn.nexDbKey, btn.nexTitle = dbKey, title

	-- Make room to the left of the name, then drop the icon into that gap,
	-- vertically centred on the title text (small nudge down to align optically).
	if titleFS then
		titleFS:ClearAllPoints()
		titleFS:SetPoint("TOPLEFT", SECTION_TITLE_X + SECTION_ICON_SLOT, SECTION_TITLE_Y)
		btn:ClearAllPoints()
		btn:SetPoint("RIGHT", titleFS, "LEFT", -4, -1)
	end

	btn:Show()
end

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

		UpdateSectionReset(headerFrame, data and data.nexResetKey, data and data.name)
	end)
	-- Section headers have no Release mixin; TrackSectionHeader untracks the
	-- previous dbKey every time Init runs on a recycled frame.
end

onSettingVisualRefresh = function(dbKey, setting)
	RefreshRevertRowsForSetting(setting)
	RefreshSectionHeaders(dbKey)
end

-- `resetKey` (optional) is a module dbKey: when set, the header gets a revert
-- icon that resets every registered option under that dbKey. Intra-module
-- sub-headers (ns.AddSectionHeader) omit it, so only the top module header for a
-- section carries the reset control.
local function AddSectionHeader(layout, text, isNew, resetKey)
	if not (layout and CreateSettingsListSectionHeaderInitializer) then
		return
	end
	local init = CreateSettingsListSectionHeaderInitializer(text)
	if init and init.GetData then
		local data = init:GetData()
		if data then
			if isNew then
				data.nexNew = true
			end
			data.nexResetKey = resetKey
		end
	end
	layout:AddInitializer(init)
end

ns.AddSectionHeader = AddSectionHeader

-- ---------------------------------------------------------------------------
-- Escape menu (GameMenuFrame) — NexEnhance config shortcut
--   Blizzard rebuilds the menu on every show (InitButtons → Reset → AddButton).
--   Post-hook InitButtons and insert our entry after Options/Shop via layoutIndex.
-- ---------------------------------------------------------------------------
local HideUIPanel = HideUIPanel
local PlaySound = PlaySound
local hooksecurefunc = hooksecurefunc
local GAMEMENU_OPTIONS = _G["GAMEMENU_OPTIONS"]
local BLIZZARD_STORE = _G["BLIZZARD_STORE"]
local ADDONS = _G["ADDONS"]
local RETURN_TO_GAME = _G["RETURN_TO_GAME"]
local SOUNDKIT = _G["SOUNDKIT"]

local gameMenuButtonHooked = false

local function ResolveGameMenuInsertIndex(menu)
	local anchorLayout = 0
	for button in menu.buttonPool:EnumerateActive() do
		local text = button:GetText() or ""
		if text == GAMEMENU_OPTIONS or text == BLIZZARD_STORE then
			anchorLayout = math.max(anchorLayout, button.layoutIndex or 0)
		end
	end
	if anchorLayout > 0 then
		return anchorLayout + 1
	end
	for button in menu.buttonPool:EnumerateActive() do
		if button:GetText() == ADDONS then
			return button.layoutIndex
		end
	end
	for button in menu.buttonPool:EnumerateActive() do
		if button:GetText() == RETURN_TO_GAME then
			return button.layoutIndex
		end
	end
	return menu.nextLayoutIndex
end

local function InsertGameMenuButton(menu)
	if not menu or not menu.AddButton or not menu.buttonPool then
		return
	end

	local insertIndex = ResolveGameMenuInsertIndex(menu)
	if not insertIndex then
		return
	end

	local function OpenFromGameMenu()
		if SOUNDKIT then
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
		end
		HideUIPanel(menu)
		if ns.OpenOptions then
			ns:OpenOptions()
		end
	end

	local btn = menu:AddButton(ns.title, OpenFromGameMenu)
	for button in menu.buttonPool:EnumerateActive() do
		if button ~= btn and button.layoutIndex >= insertIndex then
			button.layoutIndex = button.layoutIndex + 1
		end
	end
	btn.layoutIndex = insertIndex
	menu:MarkDirty()
end

local function TryInstallGameMenuButton()
	if gameMenuButtonHooked then
		return true
	end
	local menu = _G["GameMenuFrame"]
	if not (menu and menu.InitButtons and menu.AddButton) then
		return false
	end
	gameMenuButtonHooked = true
	hooksecurefunc(menu, "InitButtons", InsertGameMenuButton)
	return true
end

local function ScheduleGameMenuButtonInstall()
	if TryInstallGameMenuButton() then
		return
	end
	if C_Timer and C_Timer.NewTicker then
		local tries = 0
		C_Timer.NewTicker(0.5, function(ticker)
			tries = tries + 1
			if TryInstallGameMenuButton() or tries >= 20 then
				ticker:Cancel()
			end
		end)
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
		{ "/nex plugins", L["List installed NexEnhance plugins"] },
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

		local listContent = CreateFrame("Frame", nil, block)
		listContent:SetPoint("TOPLEFT", nheading, "BOTTOMLEFT", 6, -8)
		listContent:SetPoint("RIGHT", block, "RIGHT", 0, 0)

		local rowAnchor, totalH = listContent, 0
		for i = 1, #newModules do
			local row = MakeFontString(listContent, "GameFontHighlight")
			row:SetPoint("TOPLEFT", rowAnchor, i == 1 and "TOPLEFT" or "BOTTOMLEFT", 0, i == 1 and 0 or -5)
			row:SetPoint("RIGHT", listContent, "RIGHT", 0, 0)
			row:SetJustifyH("LEFT")
			row:SetWordWrap(true)
			row:SetText("|cff888888• |r" .. (newModules[i].title or newModules[i].name))
			rowAnchor = row
			totalH = totalH + (row:GetStringHeight() or 12) + (i == 1 and 0 or 5)
		end
		listContent:SetHeight(math.max(totalH, 1))

		local NEW_LIST_MAX_HEIGHT = 132
		local headingH = nheading:GetStringHeight() or 16
		if totalH > NEW_LIST_MAX_HEIGHT and ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar then
			local scroll = CreateFrame("ScrollFrame", nil, block)
			scroll:SetPoint("TOPLEFT", nheading, "BOTTOMLEFT", 0, -6)
			scroll:SetPoint("RIGHT", block, "RIGHT", -20, 0)
			scroll:SetHeight(NEW_LIST_MAX_HEIGHT)

			local scrollBar = CreateFrame("EventFrame", nil, block, "MinimalScrollBar")
			scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
			scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
			ScrollUtil.InitScrollFrameWithScrollBar(scroll, scrollBar)

			listContent:SetParent(scroll)
			listContent:ClearAllPoints()
			listContent:SetWidth(scroll:GetWidth() > 0 and scroll:GetWidth() or 360)
			scroll:SetScrollChild(listContent)
			listContent:SetPoint("TOPLEFT")

			block:SetHeight(headingH + NEW_LIST_MAX_HEIGHT + 12)
		else
			block:SetHeight(headingH + totalH + 14)
		end
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
function ns:RegisterOptionsCanvas(name, builder, sidebarLabel, opts)
	optionsCanvases[#optionsCanvases + 1] = {
		name = name,
		builder = builder,
		sidebar = sidebarLabel or name,
		afterGroup = opts and opts.afterGroup,
		icon = opts and opts.icon,
	}
end

local function BuildOptions()
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then
		return
	end

	InstallSectionHeaderBadges()
	InstallCategorySidebarBadges()

	local category
	if Settings.RegisterCanvasLayoutCategory then
		category = Settings.RegisterCanvasLayoutCategory(CreateLandingFrame(), ns.title)
	else
		category = Settings.RegisterVerticalLayoutCategory(ns.title)
	end
	ns.settingsCategory = category

	local newModuleLookup = BuildNewModuleLookup()

	for id in pairs(sidebarNewCategories) do
		sidebarNewCategories[id] = nil
	end
	for id in pairs(sidebarCategoryIcons) do
		sidebarCategoryIcons[id] = nil
	end

	-- Which groups contain a module flagged new this version, so the sidebar entry
	-- can carry a "New" marker pointing the user at the right section.
	local groupHasNew = {}
	for i = 1, #ns.modules do
		local m = ns.modules[i]
		if m.title and newModuleLookup[m.name] then
			groupHasNew[m.group or "misc"] = true
		end
	end

	local canvasesAfterGroup = {}
	local deferredCanvases = {}
	for i = 1, #optionsCanvases do
		local entry = optionsCanvases[i]
		if entry.afterGroup then
			canvasesAfterGroup[entry.afterGroup] = canvasesAfterGroup[entry.afterGroup] or {}
			local bucket = canvasesAfterGroup[entry.afterGroup]
			bucket[#bucket + 1] = entry
		else
			deferredCanvases[#deferredCanvases + 1] = entry
		end
	end

	local panel = _G["SettingsPanel"]
	local ourCategories = {}
	local function RegisterCanvasEntry(entry)
		if not Settings.RegisterCanvasLayoutSubcategory then
			return
		end
		local frame, canvas = CreateCanvasSubFrame(entry.name)
		local sub = Settings.RegisterCanvasLayoutSubcategory(category, frame, entry.sidebar)
		if sub then
			ourCategories[sub] = true
			if entry.icon then
				sidebarCategoryIcons[sub] = entry.icon
			end
		end

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

	-- One subcategory (with its own layout) per themed group, listed
	-- alphabetically by (localised) title so the sidebar reads A, B, C...
	local groupCategory, groupLayout = {}, {}
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
			local sub, layout = Settings.RegisterVerticalLayoutSubcategory(category, GroupLabel(g))
			groupCategory[g.key] = sub
			groupLayout[g.key] = layout
			ourCategories[sub] = true
			if g.icon then
				sidebarCategoryIcons[sub] = g.icon
			end
			if groupHasNew[g.key] and sub then
				sidebarNewCategories[sub] = true
			end

			-- Intro blurb at the top of the subcategory page.
			if g.desc and F.CreateSettingsDescription then
				local desc = F.CreateSettingsDescription(g.desc)
				if desc then
					layout:AddInitializer(desc)
				end
			end

			local pinned = canvasesAfterGroup[g.key]
			if pinned then
				for j = 1, #pinned do
					RegisterCanvasEntry(pinned[j])
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
			AddSectionHeader(groupLayout[key], module.title or module.name, newModuleLookup[module.name] == true, module.dbKey)
			OptionBuilder.layout = groupLayout[key]
			module:RegisterOptions(moduleCategory, OptionBuilder)
			OptionBuilder.layout = nil
		end
	end

	-- Remaining canvas sub-pages (Credits, Profiles, …) trail the themed groups.
	if Settings.RegisterCanvasLayoutSubcategory then
		table.sort(deferredCanvases, function(a, b)
			return a.name < b.name
		end)
		for i = 1, #deferredCanvases do
			RegisterCanvasEntry(deferredCanvases[i])
		end
	end

	Settings.RegisterAddOnCategory(category)

	InstallHeaderDividerNudge(ourCategories)

	-- Refresh sidebar dots after the category list builds (Init may run before
	-- sidebarNewCategories is populated if the settings panel was already open).
	if C_Timer and C_Timer.After then
		C_Timer.After(0, RefreshSidebarNewBadges)
	end

	-- Acknowledge the landing callout + section badges when the player opens a
	-- NexEnhance *sub*-page — not the root landing canvas, so sidebar dots stay
	-- visible while browsing the category list.
	do
		local panel = _G["SettingsPanel"]
		if panel and panel.DisplayCategory and not panel.nexNewSeenHooked then
			panel.nexNewSeenHooked = true
			hooksecurefunc(panel, "DisplayCategory", function(_, cat)
				if cat ~= category and ourCategories[cat] then
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

	ns.optionsBuilt = true
end

ns:RegisterEvent("PLAYER_LOGIN", BuildOptions)
ns:RegisterEvent("PLAYER_LOGIN", ScheduleGameMenuButtonInstall)
