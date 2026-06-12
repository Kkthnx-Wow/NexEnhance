--[[
	NexEnhance - Widgets
	-------------------------------------------------------------------------
	Reusable, data-provider backed scroll widgets built on Blizzard's modern
	ScrollBox/ScrollUtil system. Adapted from p3lim's Dashi (public domain) so
	we get the convenient list/grid helpers without adopting its framework or
	taking over our namespace.

	Usage (configure first, add data last - data triggers initialisation):

		local list = F.CreateScrollList(parent)
		list:SetElementType("BackdropTemplate")  -- frame template (required)
		list:SetElementHeight(20)                 -- required
		list:SetElementOnUpdate(function(element, data) ... end)
		list:AddData("first", "second")

	Grids additionally need SetElementWidth/SetElementSize.
--]]

-- luacheck: globals ScrollUtil

local _, ns = ...
local F = ns.F

local next, floor = next, math.floor
local Mixin = Mixin
local CreateFrame = CreateFrame
local CreateDataProvider = CreateDataProvider
local ScrollUtil = ScrollUtil
local CreateScrollBoxListLinearView = CreateScrollBoxListLinearView
local CreateScrollBoxListGridView = CreateScrollBoxListGridView
local GameTooltip_Hide = GameTooltip_Hide

-- Default comparator: stringify so mixed key types still sort deterministically.
local function defaultSort(a, b)
	return tostring(a) > tostring(b)
end

-- Lazily build the view + data provider the first time data is added. Doing it
-- here (rather than at creation) lets callers finish configuring the widget,
-- and matches "configure, then AddData" usage.
local function initialize(scroll)
	if scroll._provider then
		return
	end

	local view
	if scroll.kind == "grid" then
		local width = scroll:GetWidth() - scroll.bar:GetWidth() - (scroll._insetLeft or 0) - (scroll._insetRight or 0)
		local spacing = scroll._spacingHorizontal or 0
		local stride = floor((width - spacing) / (scroll._elementWidth + spacing))
		if stride < 1 then
			stride = 1
		end

		view = CreateScrollBoxListGridView(stride, scroll._insetTop or 0, scroll._insetBottom or 0, scroll._insetLeft or 0, scroll._insetRight or 0, spacing, scroll._spacingVertical or 0)
		view:SetStrideExtent(scroll._elementWidth)
		view:SetElementSizeCalculator(function()
			return scroll._elementWidth, scroll._elementHeight
		end)
	else
		view = CreateScrollBoxListLinearView(scroll._insetTop or 0, scroll._insetBottom or 0, scroll._insetLeft or 0, scroll._insetRight or 0, scroll._spacingVertical or 0)
		view:SetElementExtentCalculator(function()
			return scroll._elementHeight
		end)
	end

	view:SetElementInitializer(scroll._elementType, function(element, data)
		if scroll.kind == "grid" and scroll._elementWidth then
			element:SetWidth(scroll._elementWidth)
		end
		if scroll._elementHeight then
			element:SetHeight(scroll._elementHeight)
		end

		-- One-time per-frame setup. Frames are recycled, so guard on a flag.
		if not element._initialized then
			element._initialized = true

			if scroll._scripts then
				for script, callback in next, scroll._scripts do
					element:SetScript(script, callback)
					-- Convenience: auto-hide tooltips if OnEnter was set alone.
					if script == "OnEnter" and not scroll._scripts.OnLeave then
						element:SetScript("OnLeave", GameTooltip_Hide)
					end
				end
			end

			if scroll._onLoad then
				scroll._onLoad(element)
			end
		end

		element.data = data

		if scroll._onUpdate then
			scroll._onUpdate(element, data)
		end
	end)

	if scroll._onReset then
		scroll:HookScript("OnHide", function()
			for _, element in next, view:GetFrames() do
				scroll._onReset(element)
			end
		end)
	end

	ScrollUtil.InitScrollBoxListWithScrollBar(scroll, scroll.bar, view)
	ScrollUtil.AddManagedScrollBarVisibilityBehavior(scroll, scroll.bar)

	local provider = CreateDataProvider()
	provider:SetSortComparator(scroll._sort or defaultSort, true)
	view:SetDataProvider(provider)
	scroll._provider = provider
end

local scrollMixin = {}

function scrollMixin:SetInsets(top, bottom, left, right)
	self._insetTop, self._insetBottom, self._insetLeft, self._insetRight = top, bottom, left, right
end

function scrollMixin:SetElementType(kind)
	self._elementType = kind
end

function scrollMixin:SetElementHeight(height)
	self._elementHeight = height
end

function scrollMixin:SetElementWidth(width)
	self._elementWidth = width
end

function scrollMixin:SetElementSize(width, height)
	self._elementWidth = width
	self._elementHeight = height or width
end

function scrollMixin:SetElementSpacing(horizontal, vertical)
	self._spacingHorizontal = horizontal
	self._spacingVertical = vertical or horizontal
end

function scrollMixin:SetElementSortingMethod(callback)
	self._sort = callback
end

function scrollMixin:SetElementOnLoad(callback)
	self._onLoad = callback
end

function scrollMixin:SetElementOnScript(script, callback)
	self._scripts = self._scripts or {}
	self._scripts[script] = callback
end

function scrollMixin:SetElementOnUpdate(callback)
	self._onUpdate = callback
end

function scrollMixin:SetElementOnReset(callback)
	self._onReset = callback
end

function scrollMixin:AddData(...)
	initialize(self)
	self._provider:Insert(...)
end

function scrollMixin:AddDataByKeys(data)
	for key, value in next, data do
		if value then -- only truthy values become entries
			self:AddData(key)
		end
	end
end

function scrollMixin:RemoveData(...)
	if self._provider then
		self._provider:Remove(...)
	end
end

function scrollMixin:ResetData()
	if self._provider then
		self._provider:Flush()
	end
end

local function createScrollWidget(parent, kind)
	local box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
	box:SetPoint("TOPLEFT")
	box:SetPoint("BOTTOMRIGHT", -8, 0) -- leave room for the scrollbar
	box.kind = kind

	local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", box, "TOPRIGHT")
	bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT")
	box.bar = bar

	return Mixin(box, scrollMixin)
end

--- Create a vertical scrolling list that fills its parent. See file header for
--- usage. Returns the scroll box (a frame) with the scrollMixin methods.
function F.CreateScrollList(parent)
	return createScrollWidget(parent, "list")
end

--- Create a scrolling grid that fills its parent. Requires SetElementWidth (or
--- SetElementSize) in addition to the list requirements.
function F.CreateScrollGrid(parent)
	return createScrollWidget(parent, "grid")
end

-- ---------------------------------------------------------------------------
-- Edit box
--   Blizzard's vertical Settings layout has no text-input control, so this is
--   a small styled EditBox for use on canvas sub-pages (custom panels) or other
--   frames. Matches our backdrop look via F.CreateBackdrop.
--
--   Usage:
--     local box = F.CreateEditBox(parent, 160, 22)
--     box:SetCallback(function(self, text) ... end) -- fired on Enter
-- ---------------------------------------------------------------------------
local function editBox_OnEscape(self)
	self:ClearFocus()
end

local function editBox_OnEnter(self)
	if self._callback then
		self._callback(self, self:GetText())
	end
	self:ClearFocus()
end

local function editBox_SetCallback(self, callback)
	self._callback = callback
end

-- Soft gold used to highlight the border while the box has keyboard focus.
local EDITBOX_FOCUS_R, EDITBOX_FOCUS_G, EDITBOX_FOCUS_B = 0.9, 0.75, 0.32

local function editBox_OnFocusGained(self)
	if self.nexBackdrop then
		self.nexBackdrop:SetBackdropBorderColor(EDITBOX_FOCUS_R, EDITBOX_FOCUS_G, EDITBOX_FOCUS_B, 1)
	end
	if self.nexEntryBox then
		for _, tex in next, self.nexEntryBox do
			tex:SetVertexColor(1, 0.92, 0.72)
		end
	end
end

local function editBox_OnFocusLost(self)
	F.SetBorderColor(self.nexBackdrop)
	if self.nexEntryBox then
		for _, tex in next, self.nexEntryBox do
			tex:SetVertexColor(1, 1, 1)
		end
	end
end

-- Blizzard's "common-gray-button-entrybox" three-slice. All members are 48px
-- tall: -left (13) is the left cap, -right (314) is the body with the rounded
-- right end baked in, and -center (16) is the stretchable bridge between them.
local ENTRYBOX_LEFT = "common-gray-button-entrybox-left"
local ENTRYBOX_CENTER = "common-gray-button-entrybox-center"
local ENTRYBOX_RIGHT = "common-gray-button-entrybox-right"
local ENTRYBOX_NATIVE_HEIGHT = 48
local ENTRYBOX_LEFT_WIDTH = 13
local ENTRYBOX_RIGHT_WIDTH = 314

--- Skin `frame` with the gray entry-box three-slice, scaled to the frame's
--- current height (keeping the caps' aspect ratio). Returns the cached pieces.
function F.CreateEntryBoxSkin(frame)
	if frame.nexEntryBox then
		return frame.nexEntryBox
	end

	local h = frame:GetHeight()
	if not h or h <= 0 then
		h = 24
	end
	local scale = h / ENTRYBOX_NATIVE_HEIGHT

	local left = frame:CreateTexture(nil, "BACKGROUND")
	left:SetAtlas(ENTRYBOX_LEFT)
	left:SetSize(ENTRYBOX_LEFT_WIDTH * scale, h)
	left:SetPoint("LEFT")

	local right = frame:CreateTexture(nil, "BACKGROUND")
	right:SetAtlas(ENTRYBOX_RIGHT)
	right:SetSize(ENTRYBOX_RIGHT_WIDTH * scale, h)
	right:SetPoint("RIGHT")

	local center = frame:CreateTexture(nil, "BACKGROUND")
	center:SetAtlas(ENTRYBOX_CENTER)
	center:SetHeight(h)
	center:SetPoint("LEFT", left, "RIGHT")
	center:SetPoint("RIGHT", right, "LEFT")

	local pieces = { Left = left, Center = center, Right = right }
	frame.nexEntryBox = pieces
	return pieces
end

--- Create a styled, single-line edit box. `width`/`height` default to 150x22.
--- Pass `entryBox` truthy to skin it with Blizzard's gray entry-box three-slice;
--- otherwise it uses our flat recessed backdrop. Either way the border/texture
--- brightens while focused. The returned frame gains :SetCallback(fn) where
--- fn(self, text) fires when the player presses Enter. Escape clears focus.
function F.CreateEditBox(parent, width, height, entryBox)
	local eb = CreateFrame("EditBox", nil, parent)
	eb:SetAutoFocus(false)
	eb:SetFontObject("ChatFontNormal")
	eb:SetSize(width or 150, height or 22)
	eb:SetTextInsets(8, 8, 0, 0)
	eb:SetScript("OnEscapePressed", editBox_OnEscape)
	eb:SetScript("OnEnterPressed", editBox_OnEnter)
	eb.SetCallback = editBox_SetCallback

	if entryBox then
		F.CreateEntryBoxSkin(eb)
	else
		F.CreateBackdrop(eb, 0.7)
	end
	eb:HookScript("OnEditFocusGained", editBox_OnFocusGained)
	eb:HookScript("OnEditFocusLost", editBox_OnFocusLost)

	return eb
end

-- ---------------------------------------------------------------------------
-- Settings list helpers
--   Blizzard's vertical Settings layout has section headers but no body-text or
--   text-input element, so these add small custom rows. They mirror Blizzard's
--   own pattern: XML templates carrying mixins (see Widgets.xml) built via
--   Settings.CreateElementInitializer.
-- ---------------------------------------------------------------------------
-- luacheck: globals NexEnhanceSettingsDescriptionMixin NexEnhanceSettingsEditBoxMixin

NexEnhanceSettingsDescriptionMixin = {}

function NexEnhanceSettingsDescriptionMixin:EvaluateState()
	local initializer = self.initializer
	local enabled = true
	if initializer and initializer.EvaluateModifyPredicates then
		enabled = initializer:EvaluateModifyPredicates()
	end

	local d = enabled and 0.85 or 0.45
	self.Text:SetTextColor(d, d, d)
end

function NexEnhanceSettingsDescriptionMixin:Init(initializer)
	local data = initializer:GetData()
	self.initializer = initializer

	-- Support builder:DependsOn for read-only text rows, so stats/notes dim with
	-- the setting they belong to just like Blizzard's native controls.
	if self.cbrHandles then
		self.cbrHandles:Unregister()
	elseif Settings and Settings.CreateCallbackHandleContainer then
		self.cbrHandles = Settings.CreateCallbackHandleContainer()
	end
	local parentInitializer = initializer.GetParentInitializer and initializer:GetParentInitializer()
	local parentSetting = parentInitializer and parentInitializer:GetSetting()
	if self.cbrHandles and parentSetting then
		self.cbrHandles:SetOnValueChangedCallback(parentSetting:GetVariable(), self.EvaluateState, self)
	end

	self.Text:SetText(data and data.text or "")
	self:EvaluateState()
end

function NexEnhanceSettingsDescriptionMixin:Release()
	if self.cbrHandles then
		self.cbrHandles:Unregister()
	end
end

-- Measure wrapped text height off-screen. We measure at a slightly narrower
-- width than the real element so the reserved height never clips the text.
local descMeasure
local DESC_MEASURE_WIDTH = 500
local DESC_PADDING = 14

local function MeasureDescriptionHeight(text)
	if not descMeasure then
		descMeasure = UIParent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		descMeasure:Hide()
		descMeasure:SetWidth(DESC_MEASURE_WIDTH)
		descMeasure:SetJustifyH("LEFT")
		descMeasure:SetWordWrap(true)
	end
	descMeasure:SetText(text or "")
	return (descMeasure:GetStringHeight() or 12) + DESC_PADDING
end

--- Create an initializer that renders `text` as a wrapped description paragraph,
--- ready for layout:AddInitializer(...). Returns nil if the Settings API is
--- unavailable. Height is computed from the text so it never clips.
function F.CreateSettingsDescription(text)
	if not (Settings and Settings.CreateElementInitializer) then
		return
	end
	local initializer = Settings.CreateElementInitializer("NexEnhanceSettingsDescriptionTemplate", { text = text })
	local height = MeasureDescriptionHeight(text)
	initializer.GetExtent = function()
		return height
	end
	return initializer
end

NexEnhanceSettingsEditBoxMixin = {}

local function editBoxRow_OnEnterPressed(self)
	local owner = self:GetParent()
	local data = owner and owner._nexData
	if data and data.setValue then
		data.setValue(self:GetText() or "")
		if data.getValue then
			self:SetText(data.getValue() or "")
		end
	end
	self:ClearFocus()
end

local function editBoxRow_OnEscapePressed(self)
	local owner = self:GetParent()
	local data = owner and owner._nexData
	if data and data.getValue then
		self:SetText(data.getValue() or "")
	end
	self:ClearFocus()
end

-- Blizzard anchors control labels at LEFT (indent + 37); mirror that so our row
-- lines up with the surrounding checkboxes/dropdowns. (See SettingsListElementMixin.)
local SETTINGS_LABEL_INDENT = 37

--- Re-read the parent dependency (set via builder:DependsOn) and grey out / lock
--- the row when the parent toggle is off, matching Blizzard's dependent rows.
function NexEnhanceSettingsEditBoxMixin:EvaluateState()
	local initializer = self.initializer
	local enabled = true
	if initializer and initializer.EvaluateModifyPredicates then
		enabled = initializer:EvaluateModifyPredicates()
	end

	local nameColor = enabled and NORMAL_FONT_COLOR or GRAY_FONT_COLOR
	self.Text:SetTextColor(nameColor:GetRGB())
	local d = enabled and 0.75 or 0.4
	self.Description:SetTextColor(d, d, d)

	local box = self.EditBox
	if box then
		box:SetEnabled(enabled)
		if not enabled then
			box:ClearFocus()
		end
		box:SetTextColor(enabled and 1 or 0.5, enabled and 1 or 0.5, enabled and 1 or 0.5)
		if box.nexEntryBox then
			local g = enabled and 1 or 0.5
			for _, tex in next, box.nexEntryBox do
				tex:SetDesaturated(not enabled)
				tex:SetVertexColor(g, g, g)
			end
		end
	end
end

function NexEnhanceSettingsEditBoxMixin:Init(initializer)
	local data = initializer:GetData()
	self._nexData = data
	self.initializer = initializer

	-- Clear any callback left over from a previous pooled use before we re-hook.
	if self.cbrHandles then
		self.cbrHandles:Unregister()
	else
		self.cbrHandles = Settings.CreateCallbackHandleContainer()
	end

	-- Live-update our enabled state when the parent toggle (builder:DependsOn)
	-- changes, exactly as Blizzard's SettingsListElementMixin does.
	local parentInitializer = initializer.GetParentInitializer and initializer:GetParentInitializer()
	if parentInitializer then
		local parentSetting = parentInitializer:GetSetting()
		if parentSetting then
			self.cbrHandles:SetOnValueChangedCallback(parentSetting:GetVariable(), self.EvaluateState, self)
		end
	end

	self.Text:SetText(data and data.name or "")
	self.Description:SetText(data and data.tooltip or "")

	-- Match Blizzard's label indent (extra 15px for dependent rows) so the row
	-- aligns with the checkboxes above/below it.
	local indent = (initializer.GetIndent and initializer:GetIndent()) or 0
	self.Text:ClearAllPoints()
	self.Text:SetPoint("TOPLEFT", indent + SETTINGS_LABEL_INDENT, -4)

	if not self.EditBox then
		local box = F.CreateEditBox(self, 200, 28, true)
		box:SetScript("OnEnterPressed", editBoxRow_OnEnterPressed)
		box:SetScript("OnEscapePressed", editBoxRow_OnEscapePressed)
		self.EditBox = box
	end

	-- Anchor the box's left to the label (self.Text) so they share the same
	-- indent, and drop it below the (possibly wrapped) description. Anchoring to
	-- the description's BOTTOMLEFT proved unreliable, so we derive the offset
	-- from its measured height instead.
	local descHeight = self.Description:GetStringHeight()
	if not descHeight or descHeight <= 0 then
		descHeight = 12
	end
	self.EditBox:ClearAllPoints()
	self.EditBox:SetPoint("TOPLEFT", self.Text, "BOTTOMLEFT", 0, -(descHeight + 11))

	self.EditBox:SetWidth((data and data.width) or 200)
	self.EditBox:SetText((data and data.getValue and data.getValue()) or "")

	self:EvaluateState()
end

function NexEnhanceSettingsEditBoxMixin:Release()
	if self.cbrHandles then
		self.cbrHandles:Unregister()
	end
end

--- Create an initializer for an inline Settings edit box row. The value is owned
--- by the caller through getValue/setValue so it can write to any saved table.
function F.CreateSettingsEditBox(name, tooltip, getValue, setValue, width)
	if not (Settings and Settings.CreateElementInitializer) then
		return
	end
	local initializer = Settings.CreateElementInitializer("NexEnhanceSettingsEditBoxTemplate", {
		name = name,
		tooltip = tooltip,
		getValue = getValue,
		setValue = setValue,
		width = width or 200,
	})
	initializer.GetExtent = function()
		return 74
	end
	return initializer
end
