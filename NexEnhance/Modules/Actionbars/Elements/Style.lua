local _, Modules = ...
local Module = Modules.Actionbars

local gsub = string.gsub
local KEY_BUTTON4, KEY_NUMPAD1, RANGE_INDICATOR = KEY_BUTTON4, KEY_NUMPAD1, RANGE_INDICATOR

local keyButton = gsub(KEY_BUTTON4, "%d", "")
local keyNumpad = gsub(KEY_NUMPAD1, "%d", "")

local replaces = {
	{ "(" .. keyButton .. ")", "M" },
	{ "(" .. keyNumpad .. ")", "N" },
	{ "(a%-)", "a" },
	{ "(c%-)", "c" },
	{ "(s%-)", "s" },
	{ KEY_BUTTON3, "M3" },
	{ KEY_MOUSEWHEELUP, "MU" },
	{ KEY_MOUSEWHEELDOWN, "MD" },
	{ KEY_SPACE, "Sp" },
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

function Module:UpdateHotKey()
	local text = self:GetText()
	if not text then
		return
	end

	if text == RANGE_INDICATOR then
		text = ""
	else
		for _, value in ipairs(replaces) do
			text = gsub(text, value[1], value[2])
		end
	end
	self:SetFormattedText("%s", text)
end

local function StyleActionButton(button)
	if not button then
		return
	end

	local count, hotkey, name, slotbg = button.Count, button.HotKey, button.Name, button.SlotBackground

	if name then
		name:SetShown(Modules.NexConfig.actionbars.showName)
		if Modules.NexConfig.actionbars.showName then
			name:SetFont("Fonts\\FRIZQT__.TTF", Modules.NexConfig.actionbars.nameSize, "OUTLINE")
		end
		name:ClearAllPoints()
		name:SetPoint("BOTTOMLEFT", 0, 0)
		name:SetPoint("BOTTOMRIGHT", 0, 0)
	end

	if slotbg then
		slotbg:SetAtlas("UI-HUD-ActionBar-IconFrame-Slot")
	end

	if count then
		count:SetShown(Modules.NexConfig.actionbars.showCount)
		if Modules.NexConfig.actionbars.showCount then
			count:SetFont("Fonts\\ARIALN.TTF", Modules.NexConfig.actionbars.countSize, "OUTLINE")
		end
		count:ClearAllPoints()
		count:SetPoint("BOTTOMRIGHT", 2, 0)
	end

	if hotkey then
		hotkey:SetShown(Modules.NexConfig.actionbars.showHotkey)
		if Modules.NexConfig.actionbars.showHotkey then
			hotkey:SetFont("Fonts\\FRIZQT__.TTF", Modules.NexConfig.actionbars.hotkeySize, "OUTLINE")
		end
		hotkey:ClearAllPoints()
		hotkey:SetPoint("TOPRIGHT", 0, -3)
		hotkey:SetPoint("TOPLEFT", 0, -3)

		Module.UpdateHotKey(hotkey)
		hooksecurefunc(hotkey, "SetText", Module.UpdateHotKey)
	end

	button.__styled = true
end

function Module:RefreshActionBarStyling()
	local actionButtons = {
		"ActionButton",
		"MultiBarBottomLeftButton",
		"MultiBarLeftButton",
		"MultiBarRightButton",
		"MultiBarBottomRightButton",
		"MultiBar5Button",
		"MultiBar6Button",
		"MultiBar7Button",
		"StanceButton",
		"PetActionButton",
	}

	for _, button in ipairs(actionButtons) do
		for i = 1, 12 do
			StyleActionButton(_G[button .. i])
		end
	end

	StyleActionButton(ExtraActionButton1)
end

function Module:UpdateStylingConfig()
	self:RefreshActionBarStyling()
end

function Module:RegisterActionbarStyle()
	self:RefreshActionBarStyling()
end
