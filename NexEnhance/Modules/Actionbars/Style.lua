local _, Module = ...

-- Importing required functions and constants
local gsub = string.gsub
local KEY_BUTTON4, KEY_NUMPAD1, RANGE_INDICATOR = KEY_BUTTON4, KEY_NUMPAD1, RANGE_INDICATOR

-- Processing key strings
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
	if not button or button.__styled then
		return
	end

	local count = button.Count
	local hotkey = button.HotKey
	local name = button.Name
	local slotbg = button.SlotBackground

	if name then
		name:ClearAllPoints()
		name:SetPoint("BOTTOMLEFT", 0, 0)
		name:SetPoint("BOTTOMRIGHT", 0, 0)
		name:SetFont("Fonts\\FRIZQT__.TTF", Module.Font[2] - 2, Module.Font[3]) -- 10 size
	end

	if slotbg then
		slotbg:SetAtlas("UI-HUD-ActionBar-IconFrame-Slot")
	end

	if count then
		count:ClearAllPoints()
		count:SetPoint("BOTTOMRIGHT", 2, 0)
		count:SetFont("Fonts\\ARIALN.TTF", Module.Font[2] + 2, Module.Font[3]) -- 14 size
	end

	if hotkey then
		hotkey:ClearAllPoints()
		hotkey:SetPoint("TOPRIGHT", 0, -3)
		hotkey:SetPoint("TOPLEFT", 0, -3)
		hotkey:SetFont("Fonts\\FRIZQT__.TTF", Module.Font[2], Module.Font[3]) -- 12 size and one has a 14 size?

		Module.UpdateHotKey(hotkey)
		hooksecurefunc(hotkey, "SetText", Module.UpdateHotKey)
	end

	button.__styled = true
end

function Module:PLAYER_LOGIN()
	if IsAddOnLoaded("Masque") and IsAddOnLoaded("MasqueBlizzBars") then
		return
	end

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
