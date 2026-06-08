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
