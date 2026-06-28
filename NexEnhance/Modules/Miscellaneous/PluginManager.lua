--[[
	NexEnhance - Plugin Manager
	-------------------------------------------------------------------------
	Built-in settings UI for third-party NexEnhance plugins: install guidance
	when none are present, and enable toggles for plugins that do not register
	their own options page.
--]]

local _, ns = ...
local L, F = ns.L, ns.F

local format = string.format
local CreateFrame = CreateFrame

local Mod = ns:NewModule("PluginManager", nil, {
	group = "plugins",
	title = L["Extensions"],
	order = 0,
})

function Mod:RegisterOptions(category, builder)
	local layout = builder.layout
	local list = ns:GetPlugins()

	if #list == 0 then
		if layout and F.CreateSettingsDescription then
			local hint = F.CreateSettingsDescription(L["PLUGIN_INSTALL_HINT"])
			if hint then
				layout:AddInitializer(hint)
			end
		end
		return
	end

	for i = 1, #list do
		local plugin = list[i]
		if not plugin.RegisterOptions then
			if layout and ns.AddSectionHeader then
				ns.AddSectionHeader(layout, plugin.title or plugin.name, false)
			end

			builder:Checkbox(category, plugin, "enable", L["Enable"], plugin.notes ~= "" and plugin.notes or nil)

			if layout and F.CreateSettingsDescription then
				local meta = format(L["PLUGIN_BY_AUTHOR"], plugin.author, plugin.pluginVersion or "?")
				if plugin.addon then
					meta = meta .. "\n" .. format(L["PLUGIN_ADDON_FOLDER"], plugin.addon)
				end
				local line = F.CreateSettingsDescription(meta)
				if line then
					layout:AddInitializer(line)
				end
			end
		end
	end
end

local CONTENT_WIDTH = 584
local CARD_PAD = 14
local CARD_GAP = 12
local SETTINGS_ICON = [[Interface\ICONS\INV_Misc_Gear_01]]

local function PluginSidebarLabel()
	return F.Colorize(L["Plugin Manager"], "gray")
end

local function MakeLabel(parent, template, text)
	local fs = parent:CreateFontString(nil, "OVERLAY", template)
	fs:SetJustifyH("LEFT")
	if text then
		fs:SetText(text)
	end
	return fs
end

local function CreatePluginCard(parent, plugin)
	local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	card:SetSize(CONTENT_WIDTH, 1)
	card:SetBackdrop(ns.C.Backdrops.window)

	local title = MakeLabel(card, "GameFontNormalLarge", plugin.title or plugin.name)
	title:SetPoint("TOPLEFT", CARD_PAD, -CARD_PAD)
	title:SetTextColor(0.92, 0.92, 0.96)

	local meta = MakeLabel(card, "GameFontHighlightSmall", format(L["PLUGIN_BY_AUTHOR"], plugin.author, plugin.pluginVersion or "?"))
	meta:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	meta:SetTextColor(0.65, 0.65, 0.65)

	local y = -CARD_PAD - title:GetStringHeight() - 4 - meta:GetStringHeight()

	if plugin.addon then
		local folder = MakeLabel(card, "GameFontHighlightSmall", format(L["PLUGIN_ADDON_FOLDER"], plugin.addon))
		folder:SetPoint("TOPLEFT", CARD_PAD, y)
		folder:SetTextColor(0.55, 0.55, 0.55)
		y = y - folder:GetStringHeight() - 4
	end

	if plugin.notes and plugin.notes ~= "" then
		local notes = MakeLabel(card, "GameFontHighlight", plugin.notes)
		notes:SetWidth(CONTENT_WIDTH - CARD_PAD * 2)
		notes:SetPoint("TOPLEFT", CARD_PAD, y)
		notes:SetTextColor(0.78, 0.78, 0.78)
		y = y - notes:GetStringHeight() - 8
	end

	local check = CreateFrame("CheckButton", nil, card, "ChatConfigCheckButtonTemplate")
	check:SetPoint("TOPLEFT", CARD_PAD, y - 4)
	check.Text:SetText(L["Enable"])
	check:SetChecked(plugin:IsEnabled())
	check:SetScript("OnClick", function(self)
		local enabled = self:GetChecked()
		if not ns.db or not ns.db[plugin.dbKey] then
			return
		end
		ns.db[plugin.dbKey].enable = enabled
		if plugin.OnSettingChanged then
			plugin:OnSettingChanged("enable", enabled)
		end
		ns:ApplyPluginEnable(plugin, enabled)
		ns:TriggerCallback("SettingChanged." .. plugin.dbKey .. ".enable", enabled, plugin)
	end)

	local height = CARD_PAD + math.abs(y) + 28 + CARD_PAD
	card:SetHeight(height)
	return card
end

local function BuildPluginCanvas(canvas)
	local scroll = CreateFrame("ScrollFrame", nil, canvas, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 16, -16)
	scroll:SetPoint("BOTTOMRIGHT", -36, 16)

	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(CONTENT_WIDTH, 1)
	scroll:SetScrollChild(content)

	local heading = MakeLabel(content, "GameFontNormalHuge", L["Plugin Manager"])
	heading:SetPoint("TOPLEFT", 0, 0)
	heading:SetTextColor(0.92, 0.92, 0.96)

	local intro = MakeLabel(content, "GameFontHighlight", L["DESC_PLUGINS"])
	intro:SetWidth(CONTENT_WIDTH)
	intro:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -8)
	intro:SetTextColor(0.72, 0.72, 0.72)

	local y = -(heading:GetStringHeight() + 8 + intro:GetStringHeight() + 16)
	local list = ns:GetPlugins()

	if #list == 0 then
		local empty = MakeLabel(content, "GameFontHighlight", L["PLUGIN_INSTALL_HINT"])
		empty:SetWidth(CONTENT_WIDTH)
		empty:SetPoint("TOPLEFT", 0, y)
		empty:SetTextColor(0.65, 0.65, 0.65)
		y = y - empty:GetStringHeight() - CARD_GAP
	else
		for i = 1, #list do
			local card = CreatePluginCard(content, list[i])
			card:SetPoint("TOPLEFT", 0, y)
			y = y - card:GetHeight() - CARD_GAP
		end
	end

	content:SetHeight(math.abs(y) + CARD_PAD)
end

ns:RegisterOptionsCanvas(L["Plugin Manager"], BuildPluginCanvas, PluginSidebarLabel(), { afterGroup = "plugins", icon = SETTINGS_ICON })
