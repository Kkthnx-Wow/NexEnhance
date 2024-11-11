local _, Module = ...

local math_ceil = math.ceil
local mod = mod
local table_wipe = table.wipe
local table_insert = table.insert

local C_Map_GetMapArtID = C_Map.GetMapArtID
local C_Map_GetMapArtLayers = C_Map.GetMapArtLayers
local C_MapExplorationInfo_GetExploredMapTextures = C_MapExplorationInfo.GetExploredMapTextures
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc

local shownMapCache, exploredCache, fileDataIDs, storedTex = {}, {}, {}, {}

local function GetStringFromInfo(info)
	return format("W%dH%dX%dY%d", info.textureWidth, info.textureHeight, info.offsetX, info.offsetY)
end

local function GetShapesFromString(str)
	local w, h, x, y = strmatch(str, "W(%d*)H(%d*)X(%d*)Y(%d*)")
	return tonumber(w), tonumber(h), tonumber(x), tonumber(y)
end

local function RefreshFileIDsByString(str)
	table_wipe(fileDataIDs)

	for fileID in gmatch(str, "%d+") do
		table_insert(fileDataIDs, fileID)
	end
end

function Module:MapData_RefreshOverlays(fullUpdate)
	table_wipe(shownMapCache)
	table_wipe(exploredCache)
	for _, tex in pairs(storedTex) do
		tex:SetVertexColor(1, 1, 1)
	end
	wipe(storedTex)

	local mapID = WorldMapFrame.mapID
	if not mapID then
		return
	end

	local mapArtID = C_Map_GetMapArtID(mapID)
	local mapData = mapArtID and Module.Data.WorldMapRevelInfo[mapArtID]
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

	local TILE_SIZE_WIDTH = layerInfo.tileWidth
	local TILE_SIZE_HEIGHT = layerInfo.tileHeight

	-- Blizzard_SharedMapDataProviders\MapExplorationDataProvider: MapExplorationPinMixin:RefreshOverlays
	for i, exploredInfoString in pairs(mapData) do
		if not exploredCache[i] then
			local width, height, offsetX, offsetY = GetShapesFromString(i)
			RefreshFileIDsByString(exploredInfoString)
			local numTexturesWide = math_ceil(width / TILE_SIZE_WIDTH)
			local numTexturesTall = math_ceil(height / TILE_SIZE_HEIGHT)
			local texturePixelWidth, textureFileWidth, texturePixelHeight, textureFileHeight

			for j = 1, numTexturesTall do
				if j < numTexturesTall then
					texturePixelHeight = TILE_SIZE_HEIGHT
					textureFileHeight = TILE_SIZE_HEIGHT
				else
					texturePixelHeight = mod(height, TILE_SIZE_HEIGHT)
					if texturePixelHeight == 0 then
						texturePixelHeight = TILE_SIZE_HEIGHT
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
						texturePixelWidth = TILE_SIZE_WIDTH
						textureFileWidth = TILE_SIZE_WIDTH
					else
						texturePixelWidth = width % TILE_SIZE_WIDTH
						if texturePixelWidth == 0 then
							texturePixelWidth = TILE_SIZE_WIDTH
						end
						textureFileWidth = 16
						while textureFileWidth < texturePixelWidth do
							textureFileWidth = textureFileWidth * 2
						end
					end
					texture:SetWidth(texturePixelWidth)
					texture:SetHeight(texturePixelHeight)
					texture:SetTexCoord(0, texturePixelWidth / textureFileWidth, 0, texturePixelHeight / textureFileHeight)
					texture:SetPoint("TOPLEFT", offsetX + (TILE_SIZE_WIDTH * (k - 1)), -(offsetY + (TILE_SIZE_HEIGHT * (j - 1))))
					texture:SetTexture(fileDataIDs[((j - 1) * numTexturesWide) + k], nil, nil, "TRILINEAR")

					if Module.db.profile.worldmap.RevealWorldMap then
						if Module.db.profile.worldmap.MapRevealGlow then
							texture:SetVertexColor(0.7, 0.7, 0.7)
						else
							texture:SetVertexColor(1, 1, 1)
						end
						texture:SetDrawLayer("ARTWORK", -2)
						texture:Show()
						if fullUpdate then
							self.textureLoadGroup:AddTexture(texture)
						end
					else
						texture:Hide()
					end
					table_insert(shownMapCache, texture)
				end
			end
		end
	end
end

function Module:MapData_ResetTexturePool(texture)
	texture:SetVertexColor(1, 1, 1)
	texture:SetAlpha(1)
	return TexturePool_HideAndClearAnchors(self, texture)
end

function Module:PLAYER_LOGIN()
	if C_AddOns.IsAddOnLoaded("Leatrix_Maps") then
		return
	end

	local bu = CreateFrame("CheckButton", nil, WorldMapFrame.BorderFrame.TitleContainer, "OptionsBaseCheckButtonTemplate")
	bu:SetHitRectInsets(-5, -5, -5, -5)
	bu:SetPoint("TOPRIGHT", -160, 0)
	bu:SetSize(24, 24)
	bu:SetChecked(Module.db.profile.worldmap.RevealWorldMap)
	bu.text = Module.CreateFontString(bu, 12, "Map Reveal", "system", "", "LEFT", 24, 0)

	for pin in WorldMapFrame:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
		hooksecurefunc(pin, "RefreshOverlays", Module.MapData_RefreshOverlays)
		pin.overlayTexturePool.resetterFunc = Module.MapData_ResetTexturePool
	end

	function bu.UpdateTooltip(self)
		if GameTooltip:IsForbidden() then
			return
		end

		GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 10)

		local r, g, b = 0.2, 1.0, 0.2

		if Module.db.profile.worldmap.RevealWorldMap == true then
			GameTooltip:AddLine(Module.L["Reveal Enabled"])
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(Module.L["Reveal Enabled Desc"], r, g, b)
		else
			GameTooltip:AddLine(Module.L["Reveal Disabled"])
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(Module.L["Reveal Disabled Desc"], r, g, b)
		end

		GameTooltip:Show()
	end

	bu:HookScript("OnEnter", function(self)
		if GameTooltip:IsForbidden() then
			return
		end

		self:UpdateTooltip()
	end)

	bu:HookScript("OnLeave", function()
		if GameTooltip:IsForbidden() then
			return
		end

		GameTooltip:Hide()
	end)

	bu:SetScript("OnClick", function(self)
		Module.db.profile.worldmap.RevealWorldMap = self:GetChecked()

		for i = 1, #shownMapCache do
			shownMapCache[i]:SetShown(Module.db.profile.worldmap.RevealWorldMap)
		end
	end)
end
