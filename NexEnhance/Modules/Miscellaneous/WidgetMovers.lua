--[[
	NexEnhance - Widget Movers
	-------------------------------------------------------------------------
	Makes Blizzard's below-minimap and top-center UI widget containers draggable
	in Edit Mode via our LibEditMode mover.

	These containers are positioned by the legacy UIParent frame-position manager,
	NOT by Edit Mode. So for each one we:
	  1. Register an invisible anchor frame with Edit Mode (F.CreateMover) - that
	     anchor is what the user drags and what persists in the profile.
	  2. Opt the container out of the position manager
	     (ignoreFramePositionManager — Blizzard you're sneaky; same opt-out Alert
	     Frames uses for GroupLootContainer) so it stops fighting us.
	  3. Pin the container to the anchor and re-pin it via a taint-safe
	     hooksecurefunc on SetPoint. Belt-and-braces against anything else
	     repositioning it.

	Incident (WidgetMovers, Jun 2026): SetPoint hook compared arg1 (point string)
	to our anchor frame instead of arg2 (relativeTo). Infinite Glue loop → C stack
	overflow when UI scale / layout ran. This is why we don't code at 3am.

	Anchor positions use F.CreateMover so they live in our profile like any other
	NexEnhance element.

	Important: UIWidgetPowerBarContainerFrame is intentionally NOT moved here.
	Blizzard routes that widget through EncounterBar:Layout(), and EncounterBar is
	a native Edit Mode system (Enum.EditModeSystem.EncounterBar). Registering our
	own mover for it would fight Blizzard's built-in mover.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local L, F = ns.L, ns.F

local _G = _G
local max = math.max
local format = string.format
local CreateFrame = CreateFrame
local UIParent = UIParent
local hooksecurefunc = hooksecurefunc
local InCombatLockdown = InCombatLockdown

ns:RegisterDefaults({
	widgetMovers = {
		enable = false,
	},
})

local WidgetMovers = ns:NewModule("WidgetMovers", "widgetMovers", { group = "movers", title = L["Widget Movers"], order = 20 })

-- Pin `container` to `anchor`. Re-entrancy guard (`gluing`) stops our own
-- SetPoint from re-entering the hook. Skip re-pin during combat lockdown.
local function TakeOver(container, anchor, point)
	container.ignoreFramePositionManager = true

	local gluing = false
	local function Glue(self)
		if gluing or InCombatLockdown() then
			return
		end
		gluing = true
		self:ClearAllPoints()
		self:SetPoint(point, anchor)
		gluing = false
	end

	-- Blizzard fix this already: SetPoint(point, relativeTo, ...). Arg2 is the
	-- frame, not arg1. Wrong index = infinite hook loop = stack overflow.
	hooksecurefunc(container, "SetPoint", function(self, _, relativeTo)
		if gluing or relativeTo == anchor then
			return
		end
		Glue(self)
	end)

	Glue(container)
end

-- Empty widget containers lie about their size (~1px, not 0). Trust that and the
-- mover handle becomes a single pixel in Edit Mode. Ask us how we know.
local function CreateAnchor(container, minW, minH)
	local anchor = CreateFrame("Frame", nil, UIParent)
	anchor:SetSize(max(container:GetWidth() or 0, minW), max(container:GetHeight() or 0, minH))
	return anchor
end

function WidgetMovers:OnInitialize()
	ns.Debug.BindModule(self, "widgetMovers", {
		title = L["Widget Movers"],
		expectations = {
			{
				name = "widget containers opt out of FPM when enabled",
				test = function()
					if not ns.db.widgetMovers.enable then
						return true
					end
					local below = _G.UIWidgetBelowMinimapContainerFrame
					local top = _G.UIWidgetTopCenterContainerFrame
					if below and not below.ignoreFramePositionManager then
						return false
					end
					if top and not top.ignoreFramePositionManager then
						return false
					end
					return true
				end,
				detail = function()
					local below = _G.UIWidgetBelowMinimapContainerFrame
					local top = _G.UIWidgetTopCenterContainerFrame
					return format("belowFPM=%s topFPM=%s", below and tostring(below.ignoreFramePositionManager) or "nil", top and tostring(top.ignoreFramePositionManager) or "nil")
				end,
			},
		},
		dump = function()
			local below = _G.UIWidgetBelowMinimapContainerFrame
			local top = _G.UIWidgetTopCenterContainerFrame
			if below then
				local p, rel = below:GetPoint()
				F.Print(format("  BelowMinimap: ignoreFPM=%s point=%s rel=%s size=%.0fx%.0f", tostring(below.ignoreFramePositionManager), tostring(p), rel and rel:GetName() or "nil", below:GetWidth(), below:GetHeight()))
			end
			if top then
				local p, rel = top:GetPoint()
				F.Print(format("  TopCenter: ignoreFPM=%s point=%s rel=%s size=%.0fx%.0f", tostring(top.ignoreFramePositionManager), tostring(p), rel and rel:GetName() or "nil", top:GetWidth(), top:GetHeight()))
			end
		end,
	})
end

function WidgetMovers:OnEnable()
	if not ns.db.widgetMovers.enable then
		return
	end

	local belowMinimap = _G.UIWidgetBelowMinimapContainerFrame
	if belowMinimap then
		local anchor = CreateAnchor(belowMinimap, 200, 50)
		-- Default home: glued under the minimap (its native position), tracking
		-- the minimap live until the user drags it in Edit Mode.
		F.CreateMover(anchor, "widgetBelowMinimap", L["Below-Minimap Widgets"], "TOPRIGHT", 0, -220, function(self)
			self:ClearAllPoints()
			self:SetPoint("TOPRIGHT", _G.Minimap, "BOTTOMRIGHT", 0, -30)
		end)
		TakeOver(belowMinimap, anchor, "TOPRIGHT")
	end

	local topCenter = _G.UIWidgetTopCenterContainerFrame
	if topCenter then
		local anchor = CreateAnchor(topCenter, 230, 40)
		-- Native home is top-centre, just under the buff/minimap row.
		F.CreateMover(anchor, "widgetTopCenter", L["Top-Center Widgets"], "TOP", 0, -28)
		TakeOver(topCenter, anchor, "TOP")
	end
end

function WidgetMovers:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Widget Movers"], L["Make Blizzard's below-minimap and top-center widget displays draggable in Edit Mode (reload to disable)."])
end
