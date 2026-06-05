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
		if stride < 1 then stride = 1 end

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

--- Create a styled, single-line edit box. `width`/`height` default to 150x22.
--- The returned frame gains :SetCallback(fn) where fn(self, text) fires when the
--- player presses Enter. Escape clears focus.
function F.CreateEditBox(parent, width, height)
	local eb = CreateFrame("EditBox", nil, parent)
	eb:SetAutoFocus(false)
	eb:SetFontObject("ChatFontNormal")
	eb:SetSize(width or 150, height or 22)
	eb:SetTextInsets(6, 6, 0, 0)
	eb:SetScript("OnEscapePressed", editBox_OnEscape)
	eb:SetScript("OnEnterPressed", editBox_OnEnter)
	eb.SetCallback = editBox_SetCallback

	F.CreateBackdrop(eb, 0.7)

	return eb
end
