--[[
	NexEnhance - Map Reveal
	-------------------------------------------------------------------------
	Removes fog of war from the world map, drawing the unexplored map tiles
	from C.WorldMapPlusData (see Modules/Maps/MapRevealData.lua, which you
	populate yourself). Turned on/off entirely from the config, like every
	other module - no on-map checkbox.

	Adapted from KkthnxUI by Josh "Kkthnx" Russell:
	  https://github.com/Kkthnx-Wow/KkthnxUI/blob/main/KkthnxUI/Modules/Maps/Elements/MapReveal.lua

	K.* helpers are replaced with framework equivalents (ns.db.mapReveal for
	options). Defers to Leatrix_Maps if that addon is loaded.
--]]

-- luacheck: globals TexturePool_HideAndClearAnchors
---@diagnostic disable: undefined-field, undefined-global
local _, ns = ...
local C, L = ns.C, ns.L

local pairs, tonumber = pairs, tonumber
local gmatch, format, strmatch = string.gmatch, string.format, string.match
local tinsert, twipe = table.insert, table.wipe
local ceil, mod = math.ceil, mod

local hooksecurefunc = hooksecurefunc
local TexturePool_HideAndClearAnchors = TexturePool_HideAndClearAnchors
local C_AddOns_IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
local C_Map_GetMapArtID = C_Map.GetMapArtID
local C_Map_GetMapArtLayers = C_Map.GetMapArtLayers
local C_MapExplorationInfo_GetExploredMapTextures = C_MapExplorationInfo.GetExploredMapTextures

ns:RegisterDefaults({
	mapReveal = {
		enable = true,
		glow = false,
	},
})

local MapReveal = ns:NewModule("MapReveal", "mapReveal", { group = "maps", title = L["Map Reveal"], order = 20 })

-- Per-frame scratch caches, reused each refresh to avoid churn.
local shownMapCache, exploredCache, fileDataIDs, storedTex = {}, {}, {}, {}

-- Apply the current enable state to the tiles already drawn for the open map,
-- so toggling the option in config reveals/hides without needing a reload or
-- a map redraw.
local function ApplyRevealState()
	local reveal = ns.db.mapReveal.enable
	for i = 1, #shownMapCache do
		shownMapCache[i]:SetShown(reveal)
	end
end

local function GetStringFromInfo(info)
	return format("W%dH%dX%dY%d", info.textureWidth, info.textureHeight, info.offsetX, info.offsetY)
end

local function GetShapesFromString(str)
	local w, h, x, y = strmatch(str, "W(%d*)H(%d*)X(%d*)Y(%d*)")
	return tonumber(w), tonumber(h), tonumber(x), tonumber(y)
end

local function RefreshFileIDsByString(str)
	twipe(fileDataIDs)
	for fileID in gmatch(str, "%d+") do
		tinsert(fileDataIDs, fileID)
	end
end

-- Hooked onto each MapExplorationPin's RefreshOverlays, so `self` is the pin.
function MapReveal:MapData_RefreshOverlays(fullUpdate)
	twipe(shownMapCache)
	twipe(exploredCache)
	for _, tex in pairs(storedTex) do
		tex:SetVertexColor(1, 1, 1)
	end
	twipe(storedTex)

	local WorldMapFrame = _G.WorldMapFrame
	local mapID = WorldMapFrame and WorldMapFrame.mapID
	if not mapID then
		return
	end

	local mapArtID = C_Map_GetMapArtID(mapID)
	local mapData = mapArtID and C.WorldMapPlusData[mapArtID]
	if not mapData then
		return
	end

	local exploredMapTextures = C_MapExplorationInfo_GetExploredMapTextures(mapID)
	if exploredMapTextures then
		for _, exploredTextureInfo in pairs(exploredMapTextures) do
			exploredCache[GetStringFromInfo(exploredTextureInfo)] = true
		end
	end

	if not self.layerIndex then
		self.layerIndex = WorldMapFrame.ScrollContainer:GetCurrentLayerIndex()
	end
	local layers = C_Map_GetMapArtLayers(mapID)
	local layerInfo = layers and layers[self.layerIndex]
	if not layerInfo then
		return
	end

	local tileSizeWidth = layerInfo.tileWidth
	local tileSizeHeight = layerInfo.tileHeight
	local reveal = ns.db.mapReveal.enable
	local glow = ns.db.mapReveal.glow

	for i, exploredInfoString in pairs(mapData) do
		if not exploredCache[i] then
			local width, height, offsetX, offsetY = GetShapesFromString(i)
			RefreshFileIDsByString(exploredInfoString)
			local numTexturesWide = ceil(width / tileSizeWidth)
			local numTexturesTall = ceil(height / tileSizeHeight)
			local texturePixelWidth, textureFileWidth, texturePixelHeight, textureFileHeight

			for j = 1, numTexturesTall do
				if j < numTexturesTall then
					texturePixelHeight = tileSizeHeight
					textureFileHeight = tileSizeHeight
				else
					texturePixelHeight = mod(height, tileSizeHeight)
					if texturePixelHeight == 0 then
						texturePixelHeight = tileSizeHeight
					end
					textureFileHeight = 16
					while textureFileHeight < texturePixelHeight do
						textureFileHeight = textureFileHeight * 2
					end
				end
				for k = 1, numTexturesWide do
					local texture = self.overlayTexturePool:Acquire()
					tinsert(storedTex, texture)
					if k < numTexturesWide then
						texturePixelWidth = tileSizeWidth
						textureFileWidth = tileSizeWidth
					else
						texturePixelWidth = width % tileSizeWidth
						if texturePixelWidth == 0 then
							texturePixelWidth = tileSizeWidth
						end
						textureFileWidth = 16
						while textureFileWidth < texturePixelWidth do
							textureFileWidth = textureFileWidth * 2
						end
					end
					texture:SetWidth(texturePixelWidth)
					texture:SetHeight(texturePixelHeight)
					texture:SetTexCoord(0, texturePixelWidth / textureFileWidth, 0, texturePixelHeight / textureFileHeight)
					texture:SetPoint("TOPLEFT", offsetX + (tileSizeWidth * (k - 1)), -(offsetY + (tileSizeHeight * (j - 1))))
					texture:SetTexture(fileDataIDs[((j - 1) * numTexturesWide) + k], nil, nil, "TRILINEAR")

					if reveal then
						texture:SetVertexColor(glow and 0.7 or 1, glow and 0.7 or 1, glow and 0.7 or 1)
						texture:SetDrawLayer("ARTWORK", -2)
						texture:Show()
						if fullUpdate then
							self.textureLoadGroup:AddTexture(texture)
						end
					else
						texture:Hide()
					end
					tinsert(shownMapCache, texture)
				end
			end
		end
	end
end

function MapReveal:MapData_ResetTexturePool(texture)
	texture:SetVertexColor(1, 1, 1)
	texture:SetAlpha(1)
	return TexturePool_HideAndClearAnchors(self, texture)
end

function MapReveal:Setup()
	if self.started then
		return
	end
	local WorldMapFrame = _G.WorldMapFrame
	if not WorldMapFrame then
		return
	end -- Blizzard_WorldMap not available yet
	if C_AddOns_IsAddOnLoaded and C_AddOns_IsAddOnLoaded("Leatrix_Maps") then
		return
	end
	self.started = true

	for pin in WorldMapFrame:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
		hooksecurefunc(pin, "RefreshOverlays", MapReveal.MapData_RefreshOverlays)
		pin.overlayTexturePool.resetterFunc = MapReveal.MapData_ResetTexturePool
	end
end

function MapReveal:OnEnable()
	if ns.db.mapReveal.enable then
		self:Setup()
	end
end

function MapReveal:OnSettingChanged(key, value)
	if key == "enable" then
		if value then
			self:Setup()
		end
		-- Reveal/hide the tiles already drawn for the open map right away.
		ApplyRevealState()
	end
end

function MapReveal:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Map Reveal"], L["Reveal unexplored areas on the world map by removing fog of war."])
	local _, glowInit = builder:Checkbox(category, self, "glow", L["Dim Revealed Areas"], L["Slightly darken the revealed tiles so explored areas still stand out."])

	builder:DependsOn(glowInit, enableInit)
end
