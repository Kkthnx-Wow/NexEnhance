--[[
	NexEnhance - Profile Import / Export
	-------------------------------------------------------------------------
	Share a full settings profile as a single copy-paste string. New exports use
	LibSerialize + LibDeflate to produce compact printable strings. Imports still
	accept the older Base64/Lua-literal format for backwards compatibility.

	Exposed as both a Settings canvas sub-page (NexEnhance -> Profiles) and a
	standalone window via /nex profile.

	The legacy parser is retained only for old !NEX1! exports.
--]]

-- luacheck: globals ChatFontNormal StaticPopupDialogs StaticPopup_Show ReloadUI YES NO ACCEPT CANCEL ScrollUtil LibStub

local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local _G = _G
local pairs, type, next = pairs, type, next
local format, schar, ssub, gsub = string.format, string.char, string.sub, string.gsub
local floor = math.floor
local tconcat = table.concat
local loadstring, setfenv, pcall = loadstring, setfenv, pcall
local CreateFrame = CreateFrame
local ScrollUtil = ScrollUtil
local LibSerialize = LibStub and (LibStub:GetLibrary("LibSerialize-KkthnxUI", true) or LibStub:GetLibrary("LibSerialize", true))
local LibDeflate = LibStub and (LibStub:GetLibrary("LibDeflate-KkthnxUI", true) or LibStub:GetLibrary("LibDeflate", true))

-- A tag so we can sanity-check a pasted blob before trying to decode it, and so
-- a future format change can bump the number without silently mis-parsing.
local LEGACY_PREFIX = "!NEX1!"
local PREFIX = "!NEX2!"

-- ---------------------------------------------------------------------------
-- Serialiser (table -> Lua-literal string)
-- ---------------------------------------------------------------------------
local SerializeValue, SerializeTable

function SerializeValue(value)
	local t = type(value)
	if t == "string" then
		return format("%q", value)
	elseif t == "boolean" then
		return value and "true" or "false"
	elseif t == "number" then
		if value ~= value then
			return "0" -- guard against NaN sneaking in
		elseif floor(value) == value and value >= -9007199254740992 and value <= 9007199254740992 then
			return format("%d", value)
		end
		return format("%.14g", value)
	elseif t == "table" then
		return SerializeTable(value)
	end
	return "nil"
end

function SerializeTable(tbl)
	local parts = { "{" }
	for k, v in pairs(tbl) do
		local key
		local tk = type(k)
		if tk == "number" then
			key = "[" .. (floor(k) == k and format("%d", k) or format("%.14g", k)) .. "]"
		elseif tk == "string" then
			key = "[" .. format("%q", k) .. "]"
		end
		if key then
			parts[#parts + 1] = key .. "=" .. SerializeValue(v) .. ","
		end
	end
	parts[#parts + 1] = "}"
	return tconcat(parts)
end

-- ---------------------------------------------------------------------------
-- Base64 codec (no bit library dependency; plain arithmetic)
-- ---------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_LOOKUP = {}
for i = 1, #B64 do
	B64_LOOKUP[ssub(B64, i, i)] = i - 1
end

local function Base64Encode(data)
	local out, n, i = {}, #data, 1
	while i <= n do
		local c1 = data:byte(i)
		local c2 = data:byte(i + 1)
		local c3 = data:byte(i + 2)
		i = i + 3

		local e1 = floor(c1 / 4)
		local e2 = (c1 % 4) * 16 + (c2 and floor(c2 / 16) or 0)
		out[#out + 1] = ssub(B64, e1 + 1, e1 + 1)
		out[#out + 1] = ssub(B64, e2 + 1, e2 + 1)
		if c2 then
			local e3 = (c2 % 16) * 4 + (c3 and floor(c3 / 64) or 0)
			out[#out + 1] = ssub(B64, e3 + 1, e3 + 1)
			if c3 then
				local e4 = c3 % 64
				out[#out + 1] = ssub(B64, e4 + 1, e4 + 1)
			else
				out[#out + 1] = "="
			end
		else
			out[#out + 1] = "=="
		end
	end
	return tconcat(out)
end

local function Base64Decode(data)
	data = gsub(data, "[^A-Za-z0-9+/=]", "")
	local out, n, i = {}, #data, 1
	while i <= n do
		local s1 = B64_LOOKUP[ssub(data, i, i)]
		local s2 = B64_LOOKUP[ssub(data, i + 1, i + 1)]
		local ch3 = ssub(data, i + 2, i + 2)
		local ch4 = ssub(data, i + 3, i + 3)
		local s3 = B64_LOOKUP[ch3]
		local s4 = B64_LOOKUP[ch4]
		i = i + 4

		if not s1 or not s2 then
			break
		end
		out[#out + 1] = schar(s1 * 4 + floor(s2 / 16))
		if ch3 ~= "=" and s3 then
			out[#out + 1] = schar((s2 % 16) * 16 + floor(s3 / 4))
			if ch4 ~= "=" and s4 then
				out[#out + 1] = schar((s3 % 4) * 64 + s4)
			end
		end
	end
	return tconcat(out)
end

-- ---------------------------------------------------------------------------
-- Export / parse
-- ---------------------------------------------------------------------------
local function ExportProfile()
	local root = _G.NexEnhanceDB
	local profile = root and root.profiles and root.profiles[ns.profileName]
	if type(profile) ~= "table" then
		return nil
	end

	local payload = {
		v = ns.version,
		p = ns.profileName,
		d = profile,
	}

	if LibSerialize and LibDeflate then
		local ok, serialized = pcall(LibSerialize.SerializeEx, LibSerialize, { stable = true }, payload)
		if ok and type(serialized) == "string" then
			local compressed = LibDeflate:CompressDeflate(serialized)
			if type(compressed) == "string" then
				return PREFIX .. LibDeflate:EncodeForPrint(compressed)
			end
		end
	end

	-- Legacy fallback, kept mostly as a failsafe if the bundled libraries fail
	-- to load. ParseImport still accepts this format from older addon builds.
	return LEGACY_PREFIX .. Base64Encode("return " .. SerializeTable(payload))
end

-- Returns (dataTable, profileName, version) on success, or (nil, errorCode) on
-- failure. Performs no side effects so the caller can validate before applying.
local function ParseLegacyImport(text)
	if type(text) ~= "string" then
		return nil, "empty"
	end
	text = gsub(text, "%s+", "")
	if text == "" then
		return nil, "empty"
	end

	if ssub(text, 1, #LEGACY_PREFIX) == LEGACY_PREFIX then
		text = ssub(text, #LEGACY_PREFIX + 1)
	end

	local decoded = Base64Decode(text)
	if not decoded or decoded == "" then
		return nil, "invalid"
	end

	if not loadstring then
		return nil, "invalid"
	end
	local chunk = loadstring(decoded)
	if not chunk then
		return nil, "invalid"
	end

	-- Sandbox: run with an empty environment so the chunk can only build and
	-- return a table; any attempt to call a global errors out under pcall.
	if setfenv then
		setfenv(chunk, {})
	end
	local ok, result = pcall(chunk)
	if not ok or type(result) ~= "table" then
		return nil, "invalid"
	end

	local data = (type(result.d) == "table") and result.d or result
	if type(data) ~= "table" or next(data) == nil then
		return nil, "invalid"
	end

	return data, result.p, result.v
end

local function ParseImport(text)
	if type(text) ~= "string" then
		return nil, "empty"
	end
	text = gsub(text, "%s+", "")
	if text == "" then
		return nil, "empty"
	end

	if ssub(text, 1, #PREFIX) == PREFIX then
		if not (LibSerialize and LibDeflate) then
			return nil, "invalid"
		end

		local encoded = ssub(text, #PREFIX + 1)
		local compressed = LibDeflate:DecodeForPrint(encoded)
		if not compressed then
			return nil, "invalid"
		end

		local serialized = LibDeflate:DecompressDeflate(compressed)
		if not serialized then
			return nil, "invalid"
		end

		local ok, result = LibSerialize:Deserialize(serialized)
		if not ok or type(result) ~= "table" then
			return nil, "invalid"
		end

		local data = (type(result.d) == "table") and result.d or result
		if type(data) ~= "table" or next(data) == nil then
			return nil, "invalid"
		end
		return data, result.p, result.v
	end

	return ParseLegacyImport(text)
end

-- ---------------------------------------------------------------------------
-- Apply (confirmation -> overwrite active profile -> reload)
-- ---------------------------------------------------------------------------
StaticPopupDialogs["NEXENHANCE_PROFILE_IMPORT"] = {
	text = L["PROFILE_IMPORT_CONFIRM"],
	button1 = _G.YES,
	button2 = _G.NO,
	OnAccept = function(_, data)
		if type(data) ~= "table" then
			return
		end
		_G.NexEnhanceDB.profiles[ns.profileName] = data
		ReloadUI()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	showAlert = true,
	preferredIndex = 3,
}

-- ---------------------------------------------------------------------------
-- Profile management (create / copy / switch / delete)
-- ---------------------------------------------------------------------------
-- Generic confirm -> run data.func(). Used by switch/delete which only need a
-- yes/no.
StaticPopupDialogs["NEXENHANCE_PROFILE_ACTION"] = {
	text = "%s",
	button1 = _G.YES,
	button2 = _G.NO,
	OnAccept = function(_, data)
		if data and data.func then
			data.func()
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- Name prompt -> run data.func(name) with the trimmed, non-empty input.
StaticPopupDialogs["NEXENHANCE_PROFILE_NEWNAME"] = {
	text = "%s",
	button1 = _G.ACCEPT,
	button2 = _G.CANCEL,
	hasEditBox = true,
	maxLetters = 64,
	OnShow = function(self)
		self.editBox:SetText("")
		self.editBox:SetFocus()
	end,
	OnAccept = function(self, data)
		local name = gsub(gsub(self.editBox:GetText(), "^%s+", ""), "%s+$", "")
		if name ~= "" and data and data.func then
			data.func(name)
		end
	end,
	EditBoxOnEnterPressed = function(self)
		self:GetParent().button1:Click()
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local function DoSwitch(name)
	StaticPopup_Show("NEXENHANCE_PROFILE_ACTION", format(L["PROFILE_SWITCH_CONFIRM"], name), nil, {
		func = function()
			ns:SetProfile(name)
			ReloadUI()
		end,
	})
end

local function PrintProfileError(message)
	F.Print(F.Colorize(L["Profiles"] .. ": ", "brand") .. message)
end

local function DoNew()
	StaticPopup_Show("NEXENHANCE_PROFILE_NEWNAME", L["PROFILE_NEW_PROMPT"], nil, {
		func = function(name)
			if ns:ProfileExists(name) then
				PrintProfileError(format(L["PROFILE_EXISTS"], name))
				return
			end
			ns:SetProfile(name)
			ReloadUI()
		end,
	})
end

local function DoCopy()
	StaticPopup_Show("NEXENHANCE_PROFILE_NEWNAME", L["PROFILE_COPY_PROMPT"], nil, {
		func = function(name)
			if ns:ProfileExists(name) then
				PrintProfileError(format(L["PROFILE_EXISTS"], name))
				return
			end
			ns:CopyProfileInto(name)
			ns:SetProfile(name)
			ReloadUI()
		end,
	})
end

local function DoCopyFrom(name)
	StaticPopup_Show("NEXENHANCE_PROFILE_ACTION", format(L["PROFILE_COPY_FROM_CONFIRM"], name, ns.profileName), nil, {
		func = function()
			if ns:CopyProfileFrom(name) then
				ReloadUI()
			end
		end,
	})
end

local function DoReset()
	StaticPopup_Show("NEXENHANCE_PROFILE_ACTION", format(L["PROFILE_RESET_CONFIRM"], ns.profileName), nil, {
		func = function()
			ns:ResetProfile()
			ReloadUI()
		end,
	})
end

local function DoDelete(name)
	StaticPopup_Show("NEXENHANCE_PROFILE_ACTION", format(L["PROFILE_DELETE_CONFIRM"], name), nil, {
		func = function()
			ns:DeleteProfile(name)
		end,
	})
end

-- ---------------------------------------------------------------------------
-- Shared content (used by both the canvas page and the standalone window)
-- ---------------------------------------------------------------------------
local INPUT_BACKDROP = C.Backdrops.window

local function CreateInputArea(parent)
	local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	box:SetBackdrop(INPUT_BACKDROP)
	box:SetBackdropColor(0.06, 0.06, 0.06, 0.9)
	box:SetBackdropBorderColor(C.Colors.brand[1], C.Colors.brand[2], C.Colors.brand[3], 0.7)

	local scroll = CreateFrame("ScrollFrame", nil, box)
	scroll:SetPoint("TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", -28, 8)

	local scrollBar = CreateFrame("EventFrame", nil, box, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
	ScrollUtil.InitScrollFrameWithScrollBar(scroll, scrollBar)

	local editBox = CreateFrame("EditBox", nil, scroll)
	editBox:SetMultiLine(true)
	editBox:SetMaxLetters(0)
	editBox:SetAutoFocus(false)
	editBox:SetFontObject(ChatFontNormal)
	editBox:SetWidth(360)
	editBox:SetScript("OnEscapePressed", editBox.ClearFocus)
	scroll:SetScrollChild(editBox)
	scroll:SetScript("OnSizeChanged", function(_, width)
		if width and width > 0 then
			editBox:SetWidth(width)
		end
	end)

	-- A multiline EditBox auto-sizes to its text, so when it's short or empty
	-- only that sliver is actually clickable. Forward clicks anywhere in the
	-- viewport (and the surrounding padding) to the box, matching Blizzard's
	-- UIPanelInputScrollFrame behaviour, so the whole panel feels like one field.
	local function FocusEditBox()
		editBox:SetFocus()
	end
	scroll:EnableMouse(true)
	scroll:SetScript("OnMouseDown", FocusEditBox)
	box:EnableMouse(true)
	box:SetScript("OnMouseDown", FocusEditBox)

	return box, editBox
end

-- A heading line in the brand colour, used to separate the page's two sections.
local function CreateSectionHeading(parent, text)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	fs:SetTextColor(C.Colors.brand[1], C.Colors.brand[2], C.Colors.brand[3])
	fs:SetText(text)
	return fs
end

-- A styled dropdown whose items are rebuilt every time it opens (so the profile
-- list is always current). `populate(rootDescription)` adds the entries. Returns
-- the dropdown frame, or nil if the modern menu API is unavailable.
local function CreateMenuDropdown(parent, width, defaultText, populate)
	local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	if not (dd and dd.SetupMenu) then
		if dd then
			dd:Hide()
		end
		return nil
	end
	dd:SetWidth(width)
	dd:SetupMenu(function(_, root)
		populate(root)
	end)
	if defaultText then
		if dd.OverrideText then
			dd:OverrideText(defaultText)
		elseif dd.SetDefaultText then
			dd:SetDefaultText(defaultText)
		end
	end
	return dd
end

-- Lays the management + import/export UI out inside `container`, which must
-- already be sized and anchored by the caller (the canvas page or the
-- standalone body). Optional `ui` stores widget refs for RefreshProfileUI.
local function BuildProfileContent(container, ui)
	ui = ui or {}
	-- --- Profile management ------------------------------------------------
	local mgmtHeader = CreateSectionHeading(container, L["Profile Management"])
	mgmtHeader:SetPoint("TOPLEFT", 8, -6)

	local charKey = C.Player.key or (UnitName("player") .. " - " .. (GetRealmName() or ""))
	local current = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	current:SetPoint("TOPLEFT", mgmtHeader, "BOTTOMLEFT", 0, -8)
	current:SetText(format(L["Current Profile for %s: %s"], charKey, "|c" .. C.BrandHex .. ns.profileName .. "|r"))
	ui.current = current

	local hint = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT", current, "BOTTOMLEFT", 0, -6)
	hint:SetPoint("RIGHT", container, "RIGHT", -8, 0)
	hint:SetJustifyH("LEFT")
	hint:SetWordWrap(true)
	hint:SetTextColor(0.65, 0.65, 0.65)
	hint:SetText(L["PROFILE_CHAR_HINT"])

	local newBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
	newBtn:SetSize(140, 24)
	newBtn:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -12)
	newBtn:SetText(L["New"])
	newBtn:SetScript("OnClick", DoNew)

	local copyBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
	copyBtn:SetSize(140, 24)
	copyBtn:SetPoint("LEFT", newBtn, "RIGHT", 10, 0)
	copyBtn:SetText(L["Copy Current As"])
	copyBtn:SetScript("OnClick", DoCopy)

	local resetBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
	resetBtn:SetSize(140, 24)
	resetBtn:SetPoint("LEFT", copyBtn, "RIGHT", 10, 0)
	resetBtn:SetText(L["Reset Current"])
	resetBtn:SetScript("OnClick", DoReset)

	local switchDD = CreateMenuDropdown(container, 220, ns.profileName, function(root)
		local profiles = ns:GetProfiles()
		for i = 1, #profiles do
			local name = profiles[i]
			root:CreateRadio(name, function()
				return ns.profileName == name
			end, function()
				if name ~= ns.profileName then
					DoSwitch(name)
				end
			end)
		end
	end)
	if switchDD then
		switchDD:SetPoint("TOPLEFT", newBtn, "BOTTOMLEFT", 82, -20)
		ui.switchDD = switchDD
	end

	local switchLabel = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	switchLabel:SetWidth(72)
	switchLabel:SetJustifyH("RIGHT")
	switchLabel:SetText(L["Switch To"])
	if switchDD then
		switchLabel:SetPoint("RIGHT", switchDD, "LEFT", -8, 0)
	end

	local copyFromDD = CreateMenuDropdown(container, 220, L["Copy From"], function(root)
		local profiles = ns:GetProfiles()
		local any = false
		for i = 1, #profiles do
			local name = profiles[i]
			if name ~= ns.profileName then
				any = true
				root:CreateButton(name, function()
					DoCopyFrom(name)
				end)
			end
		end
		if not any then
			root:CreateTitle(L["PROFILE_NONE_TO_COPY"])
		end
	end)
	if copyFromDD and switchDD then
		copyFromDD:SetPoint("TOPLEFT", switchDD, "BOTTOMLEFT", 0, -12)
	end

	local copyFromLabel = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	copyFromLabel:SetWidth(72)
	copyFromLabel:SetJustifyH("RIGHT")
	copyFromLabel:SetText(L["Copy From"])
	if copyFromDD then
		copyFromLabel:SetPoint("RIGHT", copyFromDD, "LEFT", -8, 0)
	end

	local deleteDD = CreateMenuDropdown(container, 220, L["Delete"], function(root)
		local profiles = ns:GetProfiles()
		local any = false
		for i = 1, #profiles do
			local name = profiles[i]
			if name ~= ns.profileName then
				any = true
				root:CreateButton(name, function()
					DoDelete(name)
				end)
			end
		end
		if not any then
			root:CreateTitle(L["PROFILE_NONE_TO_DELETE"])
		end
	end)
	if deleteDD then
		deleteDD:SetPoint("TOPLEFT", (copyFromDD or switchDD or newBtn), "BOTTOMLEFT", copyFromDD and 0 or 82, -12)
	end

	local deleteLabel = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	deleteLabel:SetWidth(72)
	deleteLabel:SetJustifyH("RIGHT")
	deleteLabel:SetText(L["Delete"])
	if deleteDD then
		deleteLabel:SetPoint("RIGHT", deleteDD, "LEFT", -8, 0)
	end

	local divider = container:CreateTexture(nil, "ARTWORK")
	divider:SetColorTexture(C.Colors.brand[1], C.Colors.brand[2], C.Colors.brand[3], 0.4)
	divider:SetHeight(2)
	divider:SetPoint("TOPLEFT", (deleteDD or copyFromDD or switchDD or newBtn), "BOTTOMLEFT", (deleteDD or copyFromDD or switchDD) and -82 or 0, -16)
	divider:SetPoint("RIGHT", container, "RIGHT", -8, 0)

	-- --- Import / export ---------------------------------------------------
	local ioHeader = CreateSectionHeading(container, L["Import / Export"])
	ioHeader:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -12)

	local desc = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	desc:SetPoint("TOPLEFT", ioHeader, "BOTTOMLEFT", 0, -8)
	desc:SetPoint("RIGHT", container, "RIGHT", -8, 0)
	desc:SetJustifyH("LEFT")
	desc:SetWordWrap(true)
	desc:SetSpacing(3)
	desc:SetTextColor(0.82, 0.82, 0.82)
	desc:SetText(L["PROFILE_IO_DESC"])

	local exportBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
	exportBtn:SetSize(170, 24)
	exportBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -12)
	exportBtn:SetText(L["Export Current Profile"])

	local importBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
	importBtn:SetSize(170, 24)
	importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 10, 0)
	importBtn:SetText(L["Import Profile"])

	local status = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("BOTTOMLEFT", 8, 8)
	status:SetPoint("BOTTOMRIGHT", -8, 8)
	status:SetJustifyH("LEFT")
	status:SetWordWrap(true)

	local box, editBox = CreateInputArea(container)
	box:SetPoint("TOPLEFT", exportBtn, "BOTTOMLEFT", 0, -12)
	box:SetPoint("BOTTOMRIGHT", status, "TOPRIGHT", 0, 8)

	exportBtn:SetScript("OnClick", function()
		local str = ExportProfile()
		if not str then
			status:SetText("|cffff5555" .. L["PROFILE_IMPORT_INVALID"] .. "|r")
			return
		end
		editBox:SetText(str)
		editBox:SetFocus()
		editBox:HighlightText()
		editBox:SetCursorPosition(0)
		status:SetText("|cff66cc66" .. format(L["PROFILE_EXPORTED"], ns.profileName) .. "|r")
	end)

	importBtn:SetScript("OnClick", function()
		local data, err = ParseImport(editBox:GetText())
		if not data then
			local msg = (err == "empty") and L["PROFILE_IMPORT_EMPTY"] or L["PROFILE_IMPORT_INVALID"]
			status:SetText("|cffff5555" .. msg .. "|r")
			return
		end
		status:SetText("")
		StaticPopup_Show("NEXENHANCE_PROFILE_IMPORT", nil, nil, data)
	end)
end

local profileUI = {}

local function RefreshProfileUI()
	if profileUI.current then
		local charKey = C.Player.key or (UnitName("player") .. " - " .. (GetRealmName() or ""))
		profileUI.current:SetText(format(L["Current Profile for %s: %s"], charKey, "|c" .. C.BrandHex .. ns.profileName .. "|r"))
	end
	if profileUI.switchDD then
		if profileUI.switchDD.OverrideText then
			profileUI.switchDD:OverrideText(ns.profileName)
		elseif profileUI.switchDD.SetDefaultText then
			profileUI.switchDD:SetDefaultText(ns.profileName)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Settings canvas (NexEnhance -> Profiles)
-- ---------------------------------------------------------------------------
local SIDEBAR_ICON = [[Interface\ICONS\INV_Inscription_Scroll]]
local canvasBuilt = false

local function BuildProfileCanvas(canvas)
	if not canvasBuilt then
		canvasBuilt = true
		BuildProfileContent(canvas, profileUI)
	end
	RefreshProfileUI()
end

local function ProfilesSidebarLabel()
	return format("|c%s%s|r", C.BrandHex, L["Profiles"])
end

ns:RegisterOptionsCanvas(L["Profiles"], BuildProfileCanvas, ProfilesSidebarLabel(), { icon = SIDEBAR_ICON })

-- ---------------------------------------------------------------------------
-- Standalone window (/nex profile)
-- ---------------------------------------------------------------------------
local WINDOW_BACKDROP = C.Backdrops.window

local window

local function BuildWindow()
	if window then
		return window
	end

	window = CreateFrame("Frame", "NexEnhanceProfiles", UIParent, "BackdropTemplate")
	window:SetSize(560, 600)
	window:SetPoint("CENTER")
	window:SetFrameStrata("DIALOG")
	window:SetToplevel(true)
	window:Hide()
	window:SetBackdrop(WINDOW_BACKDROP)
	window:SetBackdropColor(0.05, 0.05, 0.07, 0.97)
	window:SetBackdropBorderColor(C.Colors.brand[1], C.Colors.brand[2], C.Colors.brand[3], 0.85)
	F.MakeWindowMovable(window, "NexEnhanceProfiles") -- draggable + Escape-close

	local logo = window:CreateTexture(nil, "ARTWORK")
	logo:SetSize(40, 40)
	logo:SetPoint("TOPLEFT", 16, -14)
	logo:SetTexture(C.Media.Textures.logo)

	local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -3)
	title:SetTextColor(C.Colors.brand[1], C.Colors.brand[2], C.Colors.brand[3])
	title:SetText(L["Profiles"])

	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)

	local body = CreateFrame("Frame", nil, window)
	body:SetPoint("TOPLEFT", 14, -64)
	body:SetPoint("BOTTOMRIGHT", -14, 12)
	BuildProfileContent(body, profileUI)
	RefreshProfileUI()

	return window
end

function ns:OpenProfiles()
	local f = BuildWindow()
	if f:IsShown() then
		f:Hide()
	else
		f:Show()
	end
end
