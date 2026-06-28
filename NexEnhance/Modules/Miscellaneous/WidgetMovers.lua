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
	     (ignoreFramePositionManager, the same opt-out Alert Frames uses for
	     GroupLootContainer) so it stops fighting us.
	  3. Pin the container to the anchor and re-pin it via a taint-safe
	     hooksecurefunc on SetPoint, as a belt-and-braces against anything else
	     repositioning it.

	Ported from NDui's UIWidgetFrameMover (by siweia); NDui's B.Mover anchors are
	replaced with F.CreateMover so the positions live in our profile and drag like
	any other NexEnhance element.

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

-- Pin `container` to `anchor`. Setting the point re-enters the SetPoint hook, but
-- the parent == anchor guard there stops the recursion. We skip re-pinning during
-- combat: ignoreFramePositionManager already keeps the legacy manager off these
-- containers, so the only in-combat caller is Blizzard's own widget layout, and
-- we'd rather not move frames mid-lockdown. The next out-of-combat SetPoint
-- (or widget refresh) re-glues it.
local function Glue(container, anchor, point)
	if InCombatLockdown() then
		return
	end
	container:ClearAllPoints()
	container:SetPoint(point, anchor)
end

local function TakeOver(container, anchor, point)
	-- Stop the legacy UIParent manager from moving it back.
	container.ignoreFramePositionManager = true

	hooksecurefunc(container, "SetPoint", function(self, _, parent)
		if parent ~= anchor then
			Glue(self, anchor, point)
		end
	end)

	Glue(container, anchor, point)
end

-- Build an invisible anchor sized to the container so the Edit Mode selection box
-- lines up. Empty widget containers report a ~1px size (not 0) when they have no
-- active widgets, so we clamp to a minimum grabbable size rather than trusting
-- the live size - otherwise the mover collapses to a single point in Edit Mode.
local function CreateAnchor(container, minW, minH)
	local anchor = CreateFrame("Frame", nil, UIParent)
	anchor:SetSize(max(container:GetWidth() or 0, minW), max(container:GetHeight() or 0, minH))
	return anchor
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
