--[[
	NexEnhance - Enhanced Color Picker
	-------------------------------------------------------------------------
	Augments Blizzard's ColorPickerFrame with precise numeric entry and quick
	class-colour swatches:
	  * A box-styled colour swatch caps the column (replacing Blizzard's two
	    stacked Current/Original swatches, the lower of which overlapped the
	    rows), sharing the boxes' width and left edge.
	  * R / G / B input boxes (0-255) that drive the colour wheel and update
	    live as the wheel/value/alpha is dragged (two-way sync).
	  * A row of class-colour swatches (canonical CLASS_SORT_ORDER) - click one
	    to snap the picker to that class colour; hover for its name.
	  * The native Hex box is reskinned to match and slotted in as the aligned
	    4th row of the column (R / G / B / #); Blizzard already keeps its text
	    synced with the wheel, so we only restyle and reposition it.

	Reworked from NDui's Modules/Skins/ColorPicker.lua (by siweia) against the
	current retail ColorPickerFrame (the 10.2.5 rebuild, layout unchanged through
	12.0). Differences from the original:
	  * No custom "movable by header" code - the modern frame already ships a
	    DragBar over its Header and is movable, so we don't duplicate it.
	  * Built on the NexEnhance widget helpers (F.CreateEditBox / F.CreateFS /
	    F.CreateBackdrop) so the additions match the rest of the UI, with focus
	    highlighting and a 1px border on every swatch.
	  * Defensive structure checks (Content / ColorPicker / swatch must exist)
	    and load-on-demand handling, so a future Blizzard layout change degrades
	    to "no enhancement" instead of a Lua error.
	  * Stable class ordering and per-swatch tooltips.

	No Secret-value concerns here: ColorPickerFrame is a pure UI dialog and none
	of these reads touch combat data.
--]]

local _, ns = ...
local F, L, C = ns.F, ns.L, ns.C

-- Localised globals.
local _G = _G
local ipairs, pairs = ipairs, pairs
local tonumber, tostring = tonumber, tostring
local CreateFrame = CreateFrame
local GameTooltip = GameTooltip

local CLASS_COLORS = _G["CUSTOM_CLASS_COLORS"] or _G["RAID_CLASS_COLORS"]
local LOCALIZED_CLASS_NAMES_MALE = _G["LOCALIZED_CLASS_NAMES_MALE"]
local CLASS_SORT_ORDER = _G["CLASS_SORT_ORDER"]

-- Layout constants. We grow the frame so the R/G/B/# column under the colour
-- swatch and the class-colour strip both sit clear of the footer.
local FRAME_HEIGHT = 278
local SWATCH_SIZE = 20
local SWATCH_STRIDE = SWATCH_SIZE + 2
local CLASSBAR_BOTTOM = 42 -- class strip offset from the frame's bottom edge
local BOX_WIDTH = 60
local BOX_HEIGHT = 22
local BOX_STRIDE = 26 -- vertical gap between rows (R / G / B / #)
local BOX_TOP_GAP = 6 -- gap between the swatch and the first (R) row
local LABEL_GAP = 6 -- gap between a row label and its box
local FOCUS_BORDER = { 0.9, 0.75, 0.32, 1 } -- gold focus tint, matches widgets
local INSET = C.Mult or 1

ns:RegisterDefaults({
	colorPicker = {
		enable = true,
	},
})

local ColorPicker = ns:NewModule("ColorPicker", "colorPicker", { group = "skins", title = L["Color Picker"], order = 45 })

-- ---------------------------------------------------------------------------
-- Class-colour swatches
-- ---------------------------------------------------------------------------
local function Swatch_OnClick(self)
	local picker = _G["ColorPickerFrame"]
	local colorPicker = picker and picker.Content and picker.Content.ColorPicker
	if colorPicker then
		-- Drives our OnColorSelect hook, which refreshes the R/G/B boxes too.
		colorPicker:SetColorRGB(self.r, self.g, self.b)
	end
end

local function Swatch_OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:AddLine(self.label, self.r, self.g, self.b)
	GameTooltip:Show()
end

local function Swatch_OnLeave()
	GameTooltip:Hide()
end

-- Build the ordered class list once (canonical order when available, else the
-- localised-names table in whatever order it iterates).
local function GetClassList()
	local list = {}
	if CLASS_SORT_ORDER and #CLASS_SORT_ORDER > 0 then
		for i = 1, #CLASS_SORT_ORDER do
			list[#list + 1] = CLASS_SORT_ORDER[i]
		end
	elseif LOCALIZED_CLASS_NAMES_MALE then
		for class in pairs(LOCALIZED_CLASS_NAMES_MALE) do
			list[#list + 1] = class
		end
	end
	return list
end

local function BuildClassBar(picker)
	local bar = CreateFrame("Frame", nil, picker)
	bar:SetSize(1, SWATCH_SIZE)
	bar:SetPoint("BOTTOM", 0, CLASSBAR_BOTTOM)

	local count = 0
	for _, class in ipairs(GetClassList()) do
		local color = CLASS_COLORS and CLASS_COLORS[class]
		local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
		if color and name then
			local bu = CreateFrame("Button", nil, bar)
			bu:SetSize(SWATCH_SIZE, SWATCH_SIZE)
			bu:SetPoint("LEFT", count * SWATCH_STRIDE, 0)
			F.CreateBackdrop(bu, 1)

			local tex = bu:CreateTexture(nil, "ARTWORK")
			tex:SetPoint("TOPLEFT", INSET, -INSET)
			tex:SetPoint("BOTTOMRIGHT", -INSET, INSET)
			tex:SetColorTexture(color.r, color.g, color.b)

			local hl = bu:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints(tex)
			hl:SetColorTexture(1, 1, 1, 0.3)

			bu.r, bu.g, bu.b = color.r, color.g, color.b
			bu.label = name
			bu:SetScript("OnClick", Swatch_OnClick)
			bu:SetScript("OnEnter", Swatch_OnEnter)
			bu:SetScript("OnLeave", Swatch_OnLeave)

			count = count + 1
		end
	end

	bar:SetWidth(count > 0 and count * SWATCH_STRIDE or 1)
end

-- ---------------------------------------------------------------------------
-- R / G / B numeric entry
-- ---------------------------------------------------------------------------
local function BoxValue(box)
	local v = tonumber(box:GetText())
	if not v or v < 0 then
		v = 0
	elseif v > 255 then
		v = 255
	end
	return v
end

-- Push the three boxes into the wheel. SetColorRGB fires OnColorSelect, which
-- normalises the box text back to the rounded value - no feedback loop, because
-- SetText does not trigger the Enter callback.
local function UpdateFromBoxes(picker)
	local colorPicker = picker.Content and picker.Content.ColorPicker
	if not colorPicker then
		return
	end
	local r = BoxValue(picker.nexBoxR) / 255
	local g = BoxValue(picker.nexBoxG) / 255
	local b = BoxValue(picker.nexBoxB) / 255
	colorPicker:SetColorRGB(r, g, b)
end

-- Anchor a box as row `index` (1 = R) in the column under the header swatch, so
-- swatch / R / G / B / # share a left edge and a constant vertical stride.
local function AnchorRow(box, picker, index)
	box:ClearAllPoints()
	box:SetPoint("TOPLEFT", picker.nexSwatch, "BOTTOMLEFT", 0, -((index - 1) * BOX_STRIDE) - BOX_TOP_GAP)
end

-- A right-justified label sitting just left of `box`; labels line up because the
-- boxes share a left edge.
local function AddRowLabel(box, text, r, g, b)
	local label = F.CreateFS(box, 13, text, "OVERLAY")
	label:SetPoint("RIGHT", box, "LEFT", -LABEL_GAP, 0)
	label:SetTextColor(r, g, b)
	return label
end

local function CreateCodeBox(picker, index, labelText, r, g, b)
	local box = F.CreateEditBox(picker.Content, BOX_WIDTH, BOX_HEIGHT)
	box:SetNumeric(true)
	box:SetMaxLetters(3)
	box:SetJustifyH("CENTER")
	box:SetTextInsets(2, 2, 0, 0)
	AnchorRow(box, picker, index)
	AddRowLabel(box, labelText, r, g, b)

	box:SetCallback(function()
		UpdateFromBoxes(picker)
	end)
	return box
end

-- Reskin Blizzard's native hex EditBox to match our dark R/G/B boxes: drop its
-- stock input-box art and the inline "#"/placeholder, give it our backdrop, and
-- mirror the gold focus border the widget helper applies to F.CreateEditBox.
local function ReskinHexBox(box)
	if box.nexSkinned then
		return
	end
	box.nexSkinned = true

	for _, key in ipairs({ "Left", "Right", "Middle" }) do
		local region = box[key]
		if region then
			region:SetAlpha(0)
		end
	end
	if box.Hash then
		box.Hash:SetAlpha(0)
	end -- we add an external "#" label instead
	if box.Instructions then
		box.Instructions:SetAlpha(0)
	end

	F.CreateBackdrop(box, 0.7)
	box:SetSize(BOX_WIDTH, BOX_HEIGHT)
	box:SetJustifyH("CENTER")
	box:SetTextInsets(3, 3, 0, 0)

	box:HookScript("OnEditFocusGained", function(self)
		if self.nexBackdrop then
			self.nexBackdrop:SetBackdropBorderColor(FOCUS_BORDER[1], FOCUS_BORDER[2], FOCUS_BORDER[3], FOCUS_BORDER[4])
		end
	end)
	box:HookScript("OnEditFocusLost", function(self)
		F.SetBorderColor(self.nexBackdrop)
	end)
end

-- Replace Blizzard's two stacked colour swatches (Current over Original, the
-- latter being what overlapped the R row) with a single box-styled swatch that
-- caps the R/G/B/# column. We keep the native textures around (hidden) only as
-- the positional anchor, and drive our swatch's colour from OnColorSelect.
local function BuildHeaderSwatch(picker)
	local content = picker.Content
	if content.ColorSwatchCurrent then
		content.ColorSwatchCurrent:SetAlpha(0)
	end
	if content.ColorSwatchOriginal then
		content.ColorSwatchOriginal:SetAlpha(0)
	end

	local swatch = CreateFrame("Frame", nil, content)
	swatch:SetSize(BOX_WIDTH, BOX_HEIGHT)
	swatch:SetPoint("TOPLEFT", content.ColorSwatchCurrent, "TOPLEFT", 0, 0)
	F.CreateBackdrop(swatch, 1)

	local tex = swatch:CreateTexture(nil, "ARTWORK")
	tex:SetPoint("TOPLEFT", INSET, -INSET)
	tex:SetPoint("BOTTOMRIGHT", -INSET, INSET)
	tex:SetColorTexture(1, 1, 1)

	picker.nexSwatch = swatch
	picker.nexSwatchTex = tex
end

-- Wheel/value/alpha moved: refresh the header swatch and numeric boxes from the
-- live colour.
local function OnColorSelect()
	local picker = _G["ColorPickerFrame"]
	if not (picker and picker.nexBoxR) then
		return
	end
	local cr, cg, cb = picker:GetColorRGB()
	if picker.nexSwatchTex then
		picker.nexSwatchTex:SetColorTexture(cr, cg, cb)
	end
	picker.nexBoxR:SetText(tostring(F.Round(cr * 255)))
	picker.nexBoxG:SetText(tostring(F.Round(cg * 255)))
	picker.nexBoxB:SetText(tostring(F.Round(cb * 255)))
end

-- ---------------------------------------------------------------------------
-- Enhancement
-- ---------------------------------------------------------------------------
local function Enhance()
	local picker = _G["ColorPickerFrame"]
	if not picker or picker.nexEnhanced then
		return
	end

	local content = picker.Content
	if not (content and content.ColorPicker and content.ColorSwatchCurrent) then
		return -- unexpected layout; leave Blizzard's frame untouched
	end
	picker.nexEnhanced = true

	picker:SetHeight(FRAME_HEIGHT)

	BuildClassBar(picker)
	BuildHeaderSwatch(picker)

	picker.nexBoxR = CreateCodeBox(picker, 1, "R", 1, 0.3, 0.3)
	picker.nexBoxG = CreateCodeBox(picker, 2, "G", 0.3, 1, 0.3)
	picker.nexBoxB = CreateCodeBox(picker, 3, "B", 0.45, 0.65, 1)

	-- Reskin the native hex box and slot it in as the aligned 4th row (R/G/B/#).
	-- Blizzard already keeps its text two-way synced with the wheel, so we only
	-- restyle and reposition it.
	local hexBox = content.HexBox
	if hexBox then
		ReskinHexBox(hexBox)
		AnchorRow(hexBox, picker, 4)
		AddRowLabel(hexBox, "#", 0.7, 0.7, 0.7)
		picker.nexHexBox = hexBox
	end

	content.ColorPicker:HookScript("OnColorSelect", OnColorSelect)

	-- Seed the boxes with the colour currently shown.
	OnColorSelect()
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
local function TryEnhance()
	local picker = _G["ColorPickerFrame"]
	if picker and picker.Content then
		Enhance()
		return picker.nexEnhanced
	end
	return false
end

function ColorPicker:ADDON_LOADED(addon)
	-- Blizzard_ColorPicker can be a separate (load-on-demand) addon; enhance as
	-- soon as the frame exists. Enhance() self-guards, so extra fires are cheap.
	if addon == "Blizzard_ColorPicker" or (_G["ColorPickerFrame"] and _G["ColorPickerFrame"].Content) then
		TryEnhance()
	end
end

function ColorPicker:OnEnable()
	if not self:IsEnabled() then
		return
	end
	if not TryEnhance() then
		self:RegisterEvent("ADDON_LOADED", "ADDON_LOADED")
	end
end

function ColorPicker:OnSettingChanged(key, value)
	-- The enhancement only adds widgets; it can't be cleanly torn down live, so
	-- enabling applies immediately and disabling takes effect on the next reload.
	if key == "enable" and value then
		if not TryEnhance() then
			self:RegisterEvent("ADDON_LOADED", "ADDON_LOADED")
		end
	end
end

function ColorPicker:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enhance Color Picker"], L["Add R/G/B input boxes and class-color swatches to Blizzard's color picker (reload to fully remove)."])
end
