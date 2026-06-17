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
local F, C, L = ns.F, ns.C, ns.L

-- Localised globals.
local _G = _G
local CreateFrame = CreateFrame
local CreateColor = CreateColor
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
	if not frame then
		return
	end

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
	if not frame then
		return
	end
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
	"Inset",
	"inset",
	"InsetFrame",
	"LeftInset",
	"RightInset",
	"NineSlice",
	"BG",
	"Bg",
	"border",
	"Border",
	"Background",
	"BorderFrame",
	"bottomInset",
	"BottomInset",
	"bgLeft",
	"bgRight",
	"FilligreeOverlay",
	"PortraitOverlay",
	"ArtOverlayFrame",
	"Portrait",
	"portrait",
	"ScrollFrameBorder",
	"ScrollUpBorder",
	"ScrollDownBorder",
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
	if frame.nexBackdrop then
		return frame.nexBackdrop
	end

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
-- Tooltip backdrop (Blizzard UI-Tooltip art)
--   Applies the game's classic tooltip fill (UI-Tooltip-Background) and border
--   (UI-Tooltip-Border) to a frame the proper way: a BackdropTemplate child one
--   level below the parent, pinned to its edges (optionally expanded by
--   `outset`). The border is a tintable nine-patch; the fill is a tiled texture.
--   These are stock game assets referenced by path, so nothing is bundled.
--
--   opts.outset      : px the backdrop expands beyond the frame edges (default 0)
--   opts.edgeSize    : tooltip border edge size in px (default 16)
--   opts.bgColor     : {r, g, b[, a]} fill colour (default {0.06, 0.06, 0.06, 0.9})
--   opts.borderColor : {r, g, b[, a]} border tint (default {1, 1, 1, 1})
--   opts.frameLevel  : explicit frame level (default parent level - 1)
--   opts.noBackground: true -> border only, no fill
--
--   Returns the backdrop frame (also stored as frame.nexBackdrop) carrying
--   :SetInside, :SetBorderColor and the standard SetBackdrop* methods.
-- ---------------------------------------------------------------------------
local TOOLTIP_BG = "Interface\\Tooltips\\UI-Tooltip-Background"
local TOOLTIP_EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"

function F.CreateTooltipBackdrop(frame, opts)
	if not frame then
		return
	end
	opts = opts or {}

	local bg = frame.nexBackdrop
	if not bg then
		bg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		bg.__anchor = frame
		bg.SetInside = setInside
		frame.nexBackdrop = bg
	end

	local level = opts.frameLevel or (frame:GetFrameLevel() - 1)
	bg:SetFrameLevel(level > 0 and level or 0)

	-- Tooltip border art is a 16px nine-patch; the fill inset is a quarter of the
	-- edge so the background sits just inside the border lip.
	local edgeSize = opts.edgeSize or 16
	local inset = edgeSize / 4
	bg:SetBackdrop({
		bgFile = (not opts.noBackground) and TOOLTIP_BG or nil,
		edgeFile = TOOLTIP_EDGE,
		tile = true,
		tileSize = edgeSize,
		edgeSize = edgeSize,
		insets = { left = inset, right = inset, top = inset, bottom = inset },
	})

	local bc = opts.borderColor or { 1, 1, 1, 1 }
	bg:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
	if not opts.noBackground then
		local bgc = opts.bgColor or { 0.06, 0.06, 0.06, 0.9 }
		bg:SetBackdropColor(bgc[1], bgc[2], bgc[3], bgc[4] or 1)
	end

	local outset = opts.outset or 0
	bg:SetInside(frame, outset, outset)
	return bg
end

-- ---------------------------------------------------------------------------
-- Gradient texture
--   Creates a flat texture on `frame` that fades between two alpha stops of the
--   same colour along the given axis ("H" horizontal, "V" vertical) via the
--   modern Texture:SetGradient(orientation, minColour, maxColour) API (the old
--   SetGradientAlpha was removed in 9.0). Optional width/height size the texture;
--   otherwise anchor the returned texture yourself. Reusable gradient art helper
--   (chat backgrounds, info bars, divider lines), modelled on NDui's B.SetGradient.
-- ---------------------------------------------------------------------------
local GRADIENT_ORIENTATION = { H = "HORIZONTAL", V = "VERTICAL" }

function F.SetGradient(frame, orientation, r, g, b, a1, a2, width, height)
	orientation = GRADIENT_ORIENTATION[orientation]
	if not frame or not orientation then
		return
	end

	local tex = frame:CreateTexture(nil, "BACKGROUND")
	tex:SetTexture(C.Media.Textures.blank)
	tex:SetGradient(orientation, CreateColor(r, g, b, a1), CreateColor(r, g, b, a2))
	if width then
		tex:SetWidth(width)
	end
	if height then
		tex:SetHeight(height)
	end

	return tex
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
	if not frame or frame.nexGlowBorder then
		return frame
	end

	opts = opts or {}
	local out = opts.outset or 8
	local blend = opts.blend or "ADD"
	local color = opts.color -- optional {r, g, b}; tints the glow halo

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
		if color then
			-- The glow art is gold; SetVertexColor only *multiplies*, so tinting a
			-- yellow texture blue yields mud (its blue channel is ~0). Desaturate to
			-- greyscale first so the vertex colour actually takes.
			piece:SetDesaturated(true)
			piece:SetVertexColor(color[1], color[2], color[3])
		end
	end

	frame.nexGlowBorder = true
	return frame
end

-- ---------------------------------------------------------------------------
-- "New!" feature badge
--   Blizzard's animated, glowing "New!" label (NewFeatureLabelTemplate) - the
--   same flair the default UI slaps on the Adventure Guide / Wardrobe tabs.
--   Anchor the returned frame next to whatever you want to call out; the caller
--   owns show/hide and persistence. Falls back to a plain brand-blue "New!"
--   text if the template ever goes missing on a given client.
-- ---------------------------------------------------------------------------
function F.CreateNewFeatureBadge(parent, text)
	local label = text or _G.NEW or "New!" ---@diagnostic disable-line: undefined-field

	local ok, badge = pcall(CreateFrame, "Frame", nil, parent, "NewFeatureLabelTemplate")
	if ok and badge then
		-- The template doesn't always set its own text for us, so do it
		-- defensively, then let it re-size to fit (method name guarded - it's
		-- not present on every flavour).
		local fs = badge.Label or badge.Text
		if fs and fs.SetText then
			fs:SetText(label)
		end
		if badge.Layout then
			pcall(badge.Layout, badge)
		end
		badge:Show()
		return badge
	end

	-- Fallback: a static brand-blue "New!" with no animation.
	local fallback = CreateFrame("Frame", nil, parent)
	local fs = fallback:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetPoint("CENTER")
	fs:SetText(label)
	fs:SetTextColor(C.Colors.brand[1], C.Colors.brand[2], C.Colors.brand[3])
	fallback:SetSize((fs:GetStringWidth() or 24) + 6, (fs:GetStringHeight() or 12) + 4)
	return fallback
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

-- One-time Edit Mode nudge. Plenty of NexEnhance widgets (exp bar, datatexts,
-- buff reminder, rare alert, ...) are movable in Edit Mode, but that's not at
-- all obvious - so the first time the user opens Edit Mode we point it out once,
-- account-wide. Registered a single time on the shared LibEditMode instance the
-- first time any mover is created, so it costs nothing if no movers exist.
---@diagnostic disable-next-line: undefined-field
local HelpTip = _G.HelpTip
local moverTipHooked = false

local function ShowEditModeMoverTip()
	---@diagnostic disable-next-line: undefined-field
	local owner = _G.EditModeManagerFrame or UIParent
	local point = HelpTip and HelpTip.Point and HelpTip.Point.LeftEdgeCenter
	F.ShowHelpTip(owner, "EditModeMovers", L["EditModeMoversHelpTip"], { targetPoint = point })
end

local function HookEditModeMoverTip(lib)
	if moverTipHooked or not (lib and lib.RegisterCallback) then
		return
	end
	moverTipHooked = true
	lib:RegisterCallback("enter", ShowEditModeMoverTip)
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

	HookEditModeMoverTip(lib)

	frame.editModeName = label or key
	lib:AddFrame(frame, function(_, _, newPoint, newX, newY)
		if not ns.db then
			return
		end
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
