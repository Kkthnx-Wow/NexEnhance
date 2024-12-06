local _, Modules = ...
local Module = Modules.Actionbars

local gsub = string.gsub
local KEY_BUTTON4, KEY_NUMPAD1, RANGE_INDICATOR = KEY_BUTTON4, KEY_NUMPAD1, RANGE_INDICATOR

-- Dynamically handle key replacements
local keyButton = gsub(KEY_BUTTON4 or "", "%d", "")
local keyNumpad = gsub(KEY_NUMPAD1 or "", "%d", "")

local replaces = {
	{ "(" .. keyButton .. ")", "M" },
	{ "(" .. keyNumpad .. ")", "N" },
	{ "(a%-)", "a" },
	{ "(c%-)", "c" },
	{ "(s%-)", "s" },
	{ KEY_BUTTON3 or "", "M3" },
	{ KEY_MOUSEWHEELUP or "", "MU" },
	{ KEY_MOUSEWHEELDOWN or "", "MD" },
	{ KEY_SPACE or "", "Sp" },
	{ "CAPSLOCK", "CL" },
	{ "Capslock", "CL" },
	{ "BUTTON", "M" },
	{ "NUMPAD", "N" },
	{ "(ALT%-)", "a" },
	{ "(CTRL%-)", "c" },
	{ "(SHIFT%-)", "s" },
	{ "MOUSEWHEELUP", "MU" },
	{ "MOUSEWHEELDOWN", "MD" },
	{ "SPACE", "Sp" },
}

local function safeGetText(object)
	return object and object:GetText() or nil
end

local function IsButtonValid(button)
	return button ~= nil
end

function Module:UpdateHotKey(hotkey)
	if not hotkey then
		return
	end

	local text = safeGetText(hotkey)
	if not text or text == "" then
		return
	end

	if text == RANGE_INDICATOR then
		text = ""
	else
		for _, value in ipairs(replaces) do
			text = gsub(text, value[1], value[2])
		end
	end

	hotkey:SetFormattedText("%s", text)
end

local function StyleActionButton(button, config)
	if not button then
		return
	end

	local count = button.Count
	local hotkey = button.HotKey
	local name = button.Name
	local slotbg = button.SlotBackground

	if name then
		name:SetShown(config.showName)
		if config.showName then
			name:SetFont("Fonts\\FRIZQT__.TTF", config.nameSize, "OUTLINE")
		end
		name:ClearAllPoints()
		name:SetPoint("BOTTOMLEFT", 0, 0)
		name:SetPoint("BOTTOMRIGHT", 0, 0)
	end

	if slotbg then
		slotbg:SetAtlas("UI-HUD-ActionBar-IconFrame-Slot")
	end

	if count then
		count:SetShown(config.showCount)
		if config.showCount then
			count:SetFont("Fonts\\ARIALN.TTF", config.countSize, "OUTLINE")
		end
		count:ClearAllPoints()
		count:SetPoint("BOTTOMRIGHT", 2, 0)
	end

	if hotkey then
		hotkey:SetShown(config.showHotkey)
		if config.showHotkey then
			hotkey:SetFont("Fonts\\FRIZQT__.TTF", config.hotkeySize, "OUTLINE")
		end
		hotkey:ClearAllPoints()
		hotkey:SetPoint("TOPRIGHT", 0, -3)
		hotkey:SetPoint("TOPLEFT", 0, -3)

		Module:UpdateHotKey(hotkey)

		hooksecurefunc(hotkey, "SetText", function()
			Module:UpdateHotKey(hotkey)
		end)
	end
end

function Module:RefreshActionBarStyling()
	local actionbarConfig = Modules.NexConfig.actionbars

	local actionButtons = {
		{ prefix = "ActionButton", count = 12 },
		{ prefix = "MultiBarBottomLeftButton", count = 12 },
		{ prefix = "MultiBarLeftButton", count = 12 },
		{ prefix = "MultiBarRightButton", count = 12 },
		{ prefix = "MultiBarBottomRightButton", count = 12 },
		{ prefix = "MultiBar5Button", count = 12 },
		{ prefix = "MultiBar6Button", count = 12 },
		{ prefix = "MultiBar7Button", count = 12 },
		{ prefix = "StanceButton", count = 10 },
		{ prefix = "PetActionButton", count = 10 },
	}

	for _, buttonSet in ipairs(actionButtons) do
		for i = 1, buttonSet.count do
			local buttonName = buttonSet.prefix .. i
			local button = _G[buttonName]
			if IsButtonValid(button) then
				StyleActionButton(button, actionbarConfig)
			end
		end
	end

	if IsButtonValid(ExtraActionButton1) then
		StyleActionButton(ExtraActionButton1, actionbarConfig)
	end
end

function Module:UpdateStylingConfig()
	self:RefreshActionBarStyling()
end

function Module:RegisterActionbarStyle()
	self:RefreshActionBarStyling()
end
