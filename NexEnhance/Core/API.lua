--[[
	NexEnhance - Widget API
	-------------------------------------------------------------------------
	Framework-level extensions to the WoW widget API. These add `:Kill()` and
	`:StripTextures()` methods to every widget so skinning modules can clean up
	Blizzard frames with a single call.

	Adapted from CharInspectPlus / KkthnxUI (the standard ElvUI-style pattern):
	  https://github.com/Kkthnx-Wow/CharInspectPlus

	The functions are also exposed on `ns.F` (F.Kill / F.StripTextures) for
	callers that prefer a plain function over a method.
--]]

local _, ns = ...
local F, C = ns.F, ns.C

-- Localised globals.
local _G = _G
local CreateFrame = CreateFrame
local EnumerateFrames = EnumerateFrames
local RegisterAttributeDriver = RegisterAttributeDriver
local UIParent = UIParent
local getmetatable = getmetatable
local select = select
local tonumber = tonumber
local type = type
local tinsert = table.insert

-- ---------------------------------------------------------------------------
-- Hider frame: a hidden, secure-aware parent for objects we want gone. Driven
-- by a state driver so it stays hidden even through secure state changes.
-- ---------------------------------------------------------------------------
local hider = CreateFrame("Frame", "NexEnhanceUIHider", UIParent, "SecureHandlerAttributeTemplate")
hider:Hide()
hider:SetPoint("TOPLEFT", 0, 0)
hider:SetPoint("BOTTOMRIGHT", 0, 0)
RegisterAttributeDriver(hider, "state-visibility", "hide")
ns.HiderFrame = hider

-- ---------------------------------------------------------------------------
-- Kill: fully disable an object (unregister events + reparent to the hider).
-- ---------------------------------------------------------------------------
local function killObject(object)
	if object.UnregisterAllEvents then
		object:UnregisterAllEvents()
		object:SetParent(hider)
	else
		object.Show = object.Hide
	end

	object:Hide()
end

-- ---------------------------------------------------------------------------
-- SetFrameHiddenTaintSafe: hide protected/managed Blizzard frames without
-- reparenting them. Some managed frames (notably PetFrame) can taint when moved
-- to a hider frame, so modules that need a reversible hide should use alpha +
-- mouse state instead of SetParent.
-- ---------------------------------------------------------------------------
function F.SetFrameHiddenTaintSafe(frame, hidden)
	if not frame then return end

	frame:SetAlpha(hidden and 0 or 1)
	if frame.EnableMouse then
		frame:EnableMouse(not hidden)
	end
	if frame.SetMouseClickEnabled then
		frame:SetMouseClickEnabled(not hidden)
	end
	if frame.SetMouseMotionEnabled then
		frame:SetMouseMotionEnabled(not hidden)
	end
end

-- ---------------------------------------------------------------------------
-- MakeWindowMovable: shared boilerplate for our standalone panels (Changelog,
-- Credits, Profiles, Install). Enables left-button dragging and, when given the
-- frame's global name, registers it with UISpecialFrames so Escape closes it.
-- ---------------------------------------------------------------------------
function F.MakeWindowMovable(frame, escapeName)
	if not frame then return end
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	if escapeName then
		tinsert(_G["UISpecialFrames"], escapeName)
	end
end

-- Common Blizzard texture/region child names to clear when stripping a frame.
local BLIZZARD_TEXTURES = {
	"Inset", "inset", "InsetFrame", "LeftInset", "RightInset",
	"NineSlice", "BG", "Bg", "border", "Border", "Background",
	"BorderFrame", "bottomInset", "BottomInset", "bgLeft", "bgRight",
	"FilligreeOverlay", "PortraitOverlay", "ArtOverlayFrame", "Portrait",
	"portrait", "ScrollFrameBorder", "ScrollUpBorder", "ScrollDownBorder",
	"TitleWidgetContainer",
}

local function processRegions(shouldKill, ...)
	for i = 1, select("#", ...) do
		local region = select(i, ...)
		if region and region.IsObjectType and region:IsObjectType("Texture") then
			if shouldKill and type(shouldKill) == "boolean" then
				killObject(region)
			elseif tonumber(shouldKill) then
				if shouldKill == 0 then
					region:SetAlpha(0)
				elseif i ~= shouldKill then
					-- Clearing the texture is cheaper than hiding for many regions.
					region:SetTexture("")
				end
			else
				region:SetTexture("")
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- StripTextures: recursively clear Blizzard textures from a frame.
--   shouldKill == true        -> Kill() each texture region
--   shouldKill == 0           -> set alpha 0
--   shouldKill == <index>     -> keep that region, clear the rest
--   shouldKill == nil/other   -> clear all texture regions
-- ---------------------------------------------------------------------------
local function stripTextures(object, shouldKill)
	local frameName = object.GetName and object:GetName()
	for i = 1, #BLIZZARD_TEXTURES do
		local texture = BLIZZARD_TEXTURES[i]
		local blizzFrame = object[texture] or (frameName and _G[frameName .. texture])
		if blizzFrame then
			stripTextures(blizzFrame, shouldKill)
		end
	end

	if object.GetRegions then
		processRegions(shouldKill, object:GetRegions())
	end
end

F.Kill = killObject
F.StripTextures = stripTextures

-- ---------------------------------------------------------------------------
-- Backdrop / border skin system
--   A lightweight, ElvUI/NDui-style backdrop: a child frame one level below
--   its parent with a flat fill and a 1px border. `:SetInside()` pins it to the
--   parent's edges. Used by the tooltip and other skin modules.
-- ---------------------------------------------------------------------------
local BACKDROP = {
	bgFile = C.Media.Textures.blank,
	edgeFile = C.Media.Textures.blank,
	edgeSize = C.Mult,
}

-- Reset a backdrop's border to the neutral (black) colour.
local function setBorderColor(bg)
	if bg and bg.SetBackdropBorderColor then
		bg:SetBackdropBorderColor(0, 0, 0, 1)
	end
end

-- Pin a backdrop to its anchor's edges (optionally inset by x/y).
local function setInside(self, anchor, x, y)
	anchor = anchor or self.__anchor
	x, y = x or 0, y or 0
	self:ClearAllPoints()
	self:SetPoint("TOPLEFT", anchor, "TOPLEFT", -x, y)
	self:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", x, -y)
end

local function createBackdrop(frame, alpha)
	if frame.nexBackdrop then return frame.nexBackdrop end

	local bg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	local level = frame:GetFrameLevel()
	bg:SetFrameLevel(level > 0 and level - 1 or 0)
	-- Use the live pixel size (set by the UIScale module) so borders stay 1px.
	BACKDROP.edgeSize = C.Mult
	bg:SetBackdrop(BACKDROP)
	bg:SetBackdropColor(0, 0, 0, alpha or 0.7)
	setBorderColor(bg)

	bg.__anchor = frame
	bg.SetInside = setInside
	bg:SetInside(frame)

	frame.nexBackdrop = bg
	return bg
end

F.CreateBackdrop = createBackdrop
F.SetBorderColor = setBorderColor

-- ---------------------------------------------------------------------------
-- NineSlice border skin (Blizzard atlas art)
--   Thin wrapper over Blizzard's own NineSliceUtil.ApplyLayout, driven by a
--   data table built from the glue/callout tooltip atlases. Unlike SetBackdrop
--   this uses the engine's nine-piece art (rounded corners, tiled edges) and
--   matches how Blizzard themes its own frames. The pieces are created on the
--   "BORDER" layer, so ARTWORK/OVERLAY content drawn on the frame stays on top.
--
--   Two ways to pick the art:
--     opts.layout : the name of a Blizzard-registered layout (recommended).
--                   "TooltipDefaultLayout" is what every in-game tooltip uses,
--                   so it is guaranteed present and has all four edges + center.
--     opts.kit    : one of our atlas tables below ("glue"/"glow"). These come
--                   from the glue/callout art; the glue set is NOT fully
--                   registered for in-game frames (its vertical edges live in a
--                   separate texture file), so we probe EVERY piece and bail out
--                   wholesale rather than draw a half border.
--
--   Either way the function returns nil when the requested art is unavailable,
--   so callers can fall back to F.CreateBackdrop.
--
--   Usage:
--     if not F.CreateNineSlice(frame, { layout = "TooltipDefaultLayout",
--                                       bg = { 0.06, 0.06, 0.06, 0.95 } }) then
--         frame:SetBackdrop(...) -- classic fallback
--     end
--
--   opts.bg : optional {r, g, b, a}. Tints the layout's Center piece when one
--             exists (e.g. TooltipDefaultLayout), else paints a flat fill.
--             Defaults to NINESLICE_DEFAULT_BG (dark panel); pass false to skip.
--   opts.border : optional {r, g, b, a}. Tints all edge/corner pieces.
-- ---------------------------------------------------------------------------
local C_Texture = _G.C_Texture
local NineSliceUtil = _G.NineSliceUtil ---@diagnostic disable-line: undefined-field

-- Standard dark panel fill applied to the Center piece when no colour is given.
local NINESLICE_DEFAULT_BG = { 0.06, 0.06, 0.06, 0.95 }

-- Atlas element names (the data export's leading "_"/"!" tiling markers are not
-- part of the element name; the engine reads tiling from the atlas itself).
local NINESLICE_KITS = {
	glue = {
		TopLeftCorner = { atlas = "Tooltip-Glues-NineSlice-CornerTopLeft" },
		TopRightCorner = { atlas = "Tooltip-Glues-NineSlice-CornerTopRight" },
		BottomLeftCorner = { atlas = "Tooltip-Glues-NineSlice-CornerBottomLeft" },
		BottomRightCorner = { atlas = "Tooltip-Glues-NineSlice-CornerBottomRight" },
		TopEdge = { atlas = "Tooltip-Glues-NineSlice-EdgeTop" },
		BottomEdge = { atlas = "Tooltip-Glues-NineSlice-EdgeBottom" },
		LeftEdge = { atlas = "Tooltip-Glues-NineSlice-EdgeLeft" },
		RightEdge = { atlas = "Tooltip-Glues-NineSlice-EdgeRight" },
	},
	glow = {
		TopLeftCorner = { atlas = "CalloutGlow-NineSlice-CornerTopLeft" },
		TopRightCorner = { atlas = "CalloutGlow-NineSlice-CornerTopRight" },
		BottomLeftCorner = { atlas = "CalloutGlow-NineSlice-CornerBottomLeft" },
		BottomRightCorner = { atlas = "CalloutGlow-NineSlice-CornerBottomRight" },
		TopEdge = { atlas = "CalloutGlow-NineSlice-EdgeTop" },
		BottomEdge = { atlas = "CalloutGlow-NineSlice-EdgeBottom" },
		LeftEdge = { atlas = "CalloutGlow-NineSlice-EdgeLeft" },
		RightEdge = { atlas = "CalloutGlow-NineSlice-EdgeRight" },
	},
}

-- Probe each kit at most once (every piece must resolve), and named layouts
-- once each. The answer never changes within a session.
local nineSliceKitOK = {}

local function kitAvailable(kit)
	local cached = nineSliceKitOK[kit]
	if cached ~= nil then return cached end

	local ok = false
	local layout = NINESLICE_KITS[kit]
	if layout and NineSliceUtil and NineSliceUtil.ApplyLayout and C_Texture and C_Texture.GetAtlasInfo then
		ok = true
		for _, piece in next, layout do
			if not C_Texture.GetAtlasInfo(piece.atlas) then
				ok = false
				break
			end
		end
	end

	nineSliceKitOK[kit] = ok
	return ok
end

local function namedLayoutAvailable(name)
	return NineSliceUtil and NineSliceUtil.ApplyLayoutByName and NineSliceUtil.GetLayout
		and NineSliceUtil.GetLayout(name) ~= nil
end

function F.CreateNineSlice(frame, opts)
	if not frame then return end
	if frame.nexNineSlice then return frame end

	opts = opts or {}

	if opts.layout then
		if not namedLayoutAvailable(opts.layout) then return nil end
		NineSliceUtil.ApplyLayoutByName(frame, opts.layout)
	else
		local kit = opts.kit or "glue"
		if not kitAvailable(kit) then return nil end
		NineSliceUtil.ApplyLayout(frame, NINESLICE_KITS[kit])
	end

	-- Default to the standard dark panel fill so callers get a consistent look
	-- without passing a colour every time; pass opts.bg = false to opt out.
	local bgColor = opts.bg
	if bgColor == nil then bgColor = NINESLICE_DEFAULT_BG end
	if bgColor then
		local r, g, b = bgColor[1], bgColor[2], bgColor[3]
		local a = bgColor[4] or 1
		-- Layouts like TooltipDefaultLayout supply a Center fill; tint it instead
		-- of stacking a second texture behind it.
		if frame.Center then
			frame.Center:Show()
			frame.Center:SetVertexColor(r, g, b, a)
		else
			local bg = frame.nexNineSliceBG or frame:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints(frame)
			bg:SetColorTexture(r, g, b, a)
			frame.nexNineSliceBG = bg
		end
	elseif frame.Center then
		-- Edge-only border (bg = false): hide the layout's Center fill so the
		-- frame is just the border art (e.g. framing the square minimap).
		frame.Center:Hide()
	end

	if opts.border then
		local r, g, b = opts.border[1], opts.border[2], opts.border[3]
		local a = opts.border[4] or 1
		for _, pieceName in next, { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "TopEdge", "BottomEdge", "LeftEdge", "RightEdge" } do
			local piece = frame[pieceName]
			if piece then
				piece:SetVertexColor(r, g, b, a)
			end
		end
	end

	frame.nexNineSlice = true
	return frame
end

function F.SetNineSliceBorderColor(frame, r, g, b, a)
	if not frame then return end
	for _, pieceName in next, { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "TopEdge", "BottomEdge", "LeftEdge", "RightEdge" } do
		local piece = frame[pieceName]
		if piece then
			piece:SetVertexColor(r, g, b, a or 1)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Tutorial glow border (raw textures)
--   Blizzard's CalloutGlow atlases split horizontal and vertical art across two
--   files; the vertical atlases often fail GetAtlasInfo in-game, so the "glow"
--   kit above no-ops. This helper uses the raw texture paths directly (the same
--   approach KeyUI and Blizzard's old GlowBorderTemplate used) and always draws
--   all eight pieces.
--
--   Pieces are anchored to extend outward from the frame edges. Attach to a
--   child frame that matches the panel size, one frame level below the panel.
--
--   opts.outset : pixels the glow extends beyond the frame (default 8)
--   opts.blend  : texture blend mode (default "ADD" - emits light like a real
--                 glow; pass "BLEND" for a flat, background-independent halo)
-- ---------------------------------------------------------------------------
local GLOW_TEX_H = "Interface/TutorialFrame/UIFrameTutorialGlow"
local GLOW_TEX_V = "Interface/TutorialFrame/UIFrameTutorialGlowVertical"

function F.CreateGlowBorder(frame, opts)
	if not frame or frame.nexGlowBorder then return frame end

	opts = opts or {}
	local out = opts.outset or 8
	local blend = opts.blend or "ADD"

	local topLeft = frame:CreateTexture(nil, "BORDER")
	topLeft:SetTexture(GLOW_TEX_H)
	topLeft:SetSize(16, 16)
	topLeft:SetTexCoord(0.03125, 0.53125, 0.570312, 0.695312)
	topLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", -out, out)

	local topRight = frame:CreateTexture(nil, "BORDER")
	topRight:SetTexture(GLOW_TEX_H)
	topRight:SetSize(16, 16)
	topRight:SetTexCoord(0.03125, 0.53125, 0.710938, 0.835938)
	topRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", out - 1, out)

	local bottomLeft = frame:CreateTexture(nil, "BORDER")
	bottomLeft:SetTexture(GLOW_TEX_H)
	bottomLeft:SetSize(16, 16)
	bottomLeft:SetTexCoord(0.03125, 0.53125, 0.289062, 0.414062)
	bottomLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -out, -out)

	local bottomRight = frame:CreateTexture(nil, "BORDER")
	bottomRight:SetTexture(GLOW_TEX_H)
	bottomRight:SetSize(16, 16)
	bottomRight:SetTexCoord(0.03125, 0.53125, 0.429688, 0.554688)
	bottomRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", out, -out)

	local top = frame:CreateTexture(nil, "BORDER")
	top:SetTexture(GLOW_TEX_H)
	top:SetPoint("TOPLEFT", topLeft, "TOPRIGHT")
	top:SetPoint("BOTTOMRIGHT", topRight, "BOTTOMLEFT")
	top:SetTexCoord(0, 0.5, 0.148438, 0.273438)

	local bottom = frame:CreateTexture(nil, "BORDER")
	bottom:SetTexture(GLOW_TEX_H)
	bottom:SetPoint("TOPLEFT", bottomLeft, "TOPRIGHT")
	bottom:SetPoint("BOTTOMRIGHT", bottomRight, "BOTTOMLEFT")
	bottom:SetTexCoord(0, 0.5, 0.0078125, 0.132812)

	local left = frame:CreateTexture(nil, "BORDER")
	left:SetTexture(GLOW_TEX_V)
	left:SetPoint("TOPLEFT", topLeft, "BOTTOMLEFT")
	left:SetPoint("BOTTOMRIGHT", bottomLeft, "TOPRIGHT")
	left:SetTexCoord(0.015625, 0.265625, 0, 1)

	local right = frame:CreateTexture(nil, "BORDER")
	right:SetTexture(GLOW_TEX_V)
	right:SetPoint("TOPLEFT", topRight, "BOTTOMLEFT", 1, 0)
	right:SetPoint("BOTTOMRIGHT", bottomRight, "TOPRIGHT", 1, 0)
	right:SetTexCoord(0.296875, 0.546875, 0, 1)

	for _, piece in next, { topLeft, topRight, bottomLeft, bottomRight, top, bottom, left, right } do
		piece:SetBlendMode(blend)
	end

	frame.nexGlowBorder = true
	return frame
end

-- ---------------------------------------------------------------------------
-- Edit Mode mover
--   Register one of our own frames with Blizzard's Edit Mode (via the bundled
--   LibEditMode) so the user can drag it like a native UI element. The chosen
--   position is persisted to the active profile under `movers[key]` and
--   re-applied on login / layout change. Falls back to a static anchor when
--   the library isn't present.
-- ---------------------------------------------------------------------------
local function getEditMode()
	return _G.LibStub and _G.LibStub("LibEditMode", true)
end

-- `onPlace` (optional) is invoked to position the frame whenever it has NOT been
-- moved by the user. Use it for frames that want a live relative anchor (e.g.
-- glued under the minimap) instead of a baked absolute coordinate, so they keep
-- tracking their anchor and can't be stranded by a stale default. Once the user
-- drags it in Edit Mode the saved absolute position always wins.
function F.CreateMover(frame, key, label, point, x, y, onPlace)
	point, x, y = point or "CENTER", x or 0, y or 0

	local function applyDefault()
		if onPlace then
			onPlace(frame)
		else
			frame:ClearAllPoints()
			frame:SetPoint(point, x, y)
		end
	end

	local function place()
		local saved = ns.db and ns.db.movers and ns.db.movers[key]
		if saved then
			local savedPoint = type(saved.point) == "string" and saved.point
			local savedX, savedY = tonumber(saved.x), tonumber(saved.y)
			if savedPoint and savedX and savedY then
				frame:ClearAllPoints()
				frame:SetPoint(savedPoint, savedX, savedY)
			else
				-- Discard malformed mover data instead of crashing SetPoint.
				ns.db.movers[key] = nil
				applyDefault()
			end
		else
			applyDefault()
		end
	end

	local lib = getEditMode()
	if not lib then
		place()
		return
	end

	frame.editModeName = label or key
	lib:AddFrame(frame, function(_, _, newPoint, newX, newY)
		if not ns.db then return end
		ns.db.movers = ns.db.movers or {}
		-- "Reset to default" re-applies exactly the default we registered below.
		-- For onPlace movers that default is only a placeholder (the real anchor
		-- is relative/live), so a literal reset would strand the frame at it
		-- (e.g. BOTTOMLEFT 0,0 = bottom of the screen). Detect that case, drop
		-- the saved position and re-run the live anchor instead.
		if onPlace and newPoint == point and newX == x and newY == y then
			ns.db.movers[key] = nil
			applyDefault()
			return
		end
		ns.db.movers[key] = { point = newPoint, x = tonumber(newX) or 0, y = tonumber(newY) or 0 }
	end, { point = point, x = x, y = y }, label or key)

	place()
	lib:RegisterCallback("layout", place)
end

-- ---------------------------------------------------------------------------
-- Inject the methods onto every widget metatable (existing and future).
-- ---------------------------------------------------------------------------
local function addApi(object)
	local mt = getmetatable(object).__index
	if not object.Kill then
		mt.Kill = killObject
	end
	if not object.StripTextures then
		mt.StripTextures = stripTextures
	end
end

local handledTypes = { Frame = true }

local base = CreateFrame("Frame")
addApi(base)
addApi(base:CreateTexture())
addApi(base:CreateFontString())
addApi(base:CreateMaskTexture())

-- Walk live frames once to capture every object type the base frame misses.
local object = EnumerateFrames()
while object do
	if not object:IsForbidden() and not handledTypes[object:GetObjectType()] then
		addApi(object)
		handledTypes[object:GetObjectType()] = true
	end
	object = EnumerateFrames(object)
end
