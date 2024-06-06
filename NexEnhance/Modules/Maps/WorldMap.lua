local NexEnhance, NE_WorldMap = ...

local _G = _G

local C_Map_GetBestMapForUnit = C_Map.GetBestMapForUnit
local CreateFrame = CreateFrame
local CreateFrame = CreateFrame
local IsPlayerMoving = IsPlayerMoving
local IsPlayerMoving = IsPlayerMoving
local PLAYER = PLAYER
local PlayerMovementFrameFader = PlayerMovementFrameFader
local UIParent = UIParent
local hooksecurefunc = hooksecurefunc
local hooksecurefunc = hooksecurefunc

local currentMapID, playerCoords, cursorCoords
local smallerMapScale = 0.8

function NE_WorldMap:SetLargeWorldMap()
	local WorldMapFrame = _G.WorldMapFrame
	WorldMapFrame:SetParent(UIParent)
	WorldMapFrame:SetScale(1)
	WorldMapFrame.ScrollContainer.Child:SetScale(smallerMapScale)

	WorldMapFrame:OnFrameSizeChanged()
	if WorldMapFrame:GetMapID() then
		WorldMapFrame.NavBar:Refresh()
	end
end

function NE_WorldMap:UpdateMaximizedSize()
	local WorldMapFrame = _G.WorldMapFrame
	local width, height = WorldMapFrame:GetSize()
	local magicNumber = (1 - smallerMapScale) * 100
	WorldMapFrame:SetSize((width * smallerMapScale) - (magicNumber + 2), (height * smallerMapScale) - 2)
end

function NE_WorldMap:SynchronizeDisplayState()
	local WorldMapFrame = _G.WorldMapFrame
	if WorldMapFrame:IsMaximized() then
		WorldMapFrame:ClearAllPoints()
		WorldMapFrame:SetPoint("CENTER", UIParent)
	end

	NE_WorldMap.RestoreMoverFrame(self)
end

function NE_WorldMap:SetSmallWorldMap()
	local WorldMapFrame = _G.WorldMapFrame
	WorldMapFrame:ClearAllPoints()
	WorldMapFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -94)
end

function NE_WorldMap:GetCursorCoords()
	if not WorldMapFrame.ScrollContainer:IsMouseOver() then
		return
	end

	local cursorX, cursorY = WorldMapFrame.ScrollContainer:GetNormalizedCursorPosition()
	if cursorX < 0 or cursorX > 1 or cursorY < 0 or cursorY > 1 then
		return
	end

	return cursorX, cursorY
end

local function CoordsFormat(owner, none)
	local text = none and ": --, --" or ": %.1f, %.1f"
	return owner .. NE_WorldMap.MyColor .. text
end

function NE_WorldMap:UpdateCoords(elapsed)
	local WorldMapFrame = _G.WorldMapFrame
	if not WorldMapFrame:IsShown() then
		return
	end

	self.elapsed = (self.elapsed or 0) + elapsed

	if self.elapsed > 0.2 then
		local cursorX, cursorY = NE_WorldMap:GetCursorCoords()
		if cursorX and cursorY then
			cursorCoords:SetFormattedText(CoordsFormat("Mouse"), 100 * cursorX, 100 * cursorY)
		else
			cursorCoords:SetText(CoordsFormat("Mouse", true))
		end

		if not currentMapID then
			playerCoords:SetText(CoordsFormat(PLAYER, true))
		else
			local x, y = NE_WorldMap:GetPlayerPosition(currentMapID)
			if not x or (x == 0 and y == 0) then
				playerCoords:SetText(CoordsFormat(PLAYER, true))
			else
				playerCoords:SetFormattedText(CoordsFormat(PLAYER), 100 * x, 100 * y)
			end
		end

		self.elapsed = 0
	end
end

function NE_WorldMap:UpdateMapID()
	if self:GetMapID() == C_Map_GetBestMapForUnit("player") then
		currentMapID = self:GetMapID()
	else
		currentMapID = nil
	end
end

function NE_WorldMap:MapShouldFade()
	-- normally we would check GetCVarBool('mapFade') here instead of the setting
	return NE_WorldMap.db.profile.worldmap.FadeWhenMoving and not _G.WorldMapFrame:IsMouseOver()
end

function NE_WorldMap:MapFadeOnUpdate(elapsed)
	self.elapsed = (self.elapsed or 0) + elapsed
	if self.elapsed > 0.1 then
		self.elapsed = 0

		local object = self.FadeObject
		local settings = object and object.FadeSettings
		if not settings then
			return
		end

		local fadeOut = IsPlayerMoving() and (not settings.fadePredicate or settings.fadePredicate())
		local endAlpha = (fadeOut and (settings.minAlpha or 0.5)) or settings.maxAlpha or 1
		local startAlpha = _G.WorldMapFrame:GetAlpha()

		object.timeToFade = settings.durationSec or 0.5
		object.startAlpha = startAlpha
		object.endAlpha = endAlpha
		object.diffAlpha = endAlpha - startAlpha

		if object.fadeTimer then
			object.fadeTimer = nil
		end

		UIFrameFade(_G.WorldMapFrame, object)
	end
end

local fadeFrame
function NE_WorldMap:StopMapFromFading()
	if fadeFrame then
		fadeFrame:Hide()
	end
end

function NE_WorldMap:EnableMapFading(frame)
	if not fadeFrame then
		fadeFrame = CreateFrame("FRAME")
		fadeFrame:SetScript("OnUpdate", self.MapFadeOnUpdate)
		frame:HookScript("OnHide", self.StopMapFromFading)

		fadeFrame.FadeObject = {}
		fadeFrame.FadeObject.FadeSettings = {}
	end

	local settings = fadeFrame.FadeObject.FadeSettings
	settings.fadePredicate = NE_WorldMap.MapShouldFade
	settings.durationSec = 0.2
	settings.minAlpha = NE_WorldMap.db.profile.worldmap.AlphaWhenMoving
	settings.maxAlpha = 1

	fadeFrame:Show()
end

function NE_WorldMap:UpdateMapFade(minAlpha, maxAlpha, durationSec, fadePredicate) -- self is frame
	if self:IsShown() and (self == _G.WorldMapFrame and fadePredicate ~= NE_WorldMap.MapShouldFade) then
		-- blizzard spams code in OnUpdate and doesnt finish their functions, so we shut their fader down :L
		PlayerMovementFrameFader.RemoveFrame(self)

		-- replacement function which is complete :3
		if NE_WorldMap.db.profile.worldmap.FadeWhenMoving then
			NE_WorldMap:EnableMapFading(self)
		end
	end
end

function NE_WorldMap:WorldMap_OnShow()
	-- Update coordinates if necessary
	if self.CoordsUpdater then
		self.CoordsUpdater:SetScript("OnUpdate", self.UpdateCoords)
	end

	-- Check if the map has been size adjusted already
	if self.mapSizeAdjusted then
		return
	end

	-- Resize the map if necessary
	local frame = _G.WorldMapFrame
	local maxed = frame:IsMaximized()
	if maxed then -- Call this outside of smallerWorldMap
		frame:UpdateMaximizedSize()
	end

	-- Set the appropriate map size
	if NE_WorldMap.db.profile.worldmap.SmallWorldMap then
		if maxed then
			NE_WorldMap:SetLargeWorldMap()
		else
			NE_WorldMap:SetSmallWorldMap()
		end
	end

	-- Mark the map as size adjusted
	self.mapSizeAdjusted = true
end

function NE_WorldMap:WorldMap_OnHide()
	if self.CoordsUpdater then
		self.CoordsUpdater:SetScript("OnUpdate", nil)
	end
end

function NE_WorldMap:PLAYER_LOGIN()
	local WorldMapFrame = _G.WorldMapFrame
	if NE_WorldMap.db.profile.worldmap.Coordinates then
		-- Define the desired color (#F0C500 or RGB values 240/255, 197/255, 0)
		local textColor = { r = 240 / 255, g = 197 / 255, b = 0 }

		-- Create the coordinates frame
		local coordsFrame = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer)
		coordsFrame:SetSize(WorldMapFrame:GetWidth(), 17)
		coordsFrame:SetPoint("BOTTOMLEFT", 17)
		coordsFrame:SetPoint("BOTTOMRIGHT", 0)

		-- Background texture for the coordinates frame
		coordsFrame.Texture = coordsFrame:CreateTexture(nil, "BACKGROUND")
		coordsFrame.Texture:SetAllPoints()
		coordsFrame.Texture:SetTexture("Interface\\BUTTONS\\GreyscaleRamp64")
		coordsFrame.Texture:SetVertexColor(0.04, 0.04, 0.04, 0.5)

		-- Create the cursor coordinates text
		cursorCoords = WorldMapFrame.ScrollContainer:CreateFontString(nil, "OVERLAY")
		cursorCoords:SetFontObject(GameFontNormal)
		cursorCoords:SetFont(select(1, cursorCoords:GetFont()), 13, select(3, cursorCoords:GetFont()))
		cursorCoords:SetSize(200, 16)
		cursorCoords:SetParent(coordsFrame)
		cursorCoords:ClearAllPoints()
		cursorCoords:SetPoint("BOTTOMLEFT", 152, 1)
		cursorCoords:SetTextColor(textColor.r, textColor.g, textColor.b)
		cursorCoords:SetAlpha(0.9)

		-- Create the player coordinates text
		playerCoords = WorldMapFrame.ScrollContainer:CreateFontString(nil, "OVERLAY")
		playerCoords:SetFontObject(GameFontNormal)
		playerCoords:SetFont(select(1, playerCoords:GetFont()), 13, select(3, playerCoords:GetFont()))
		playerCoords:SetSize(200, 16)
		playerCoords:SetParent(coordsFrame)
		playerCoords:ClearAllPoints()
		playerCoords:SetPoint("BOTTOMRIGHT", -132, 1)
		playerCoords:SetTextColor(textColor.r, textColor.g, textColor.b)
		playerCoords:SetAlpha(0.9)

		hooksecurefunc(WorldMapFrame, "OnFrameSizeChanged", self.UpdateMapID)
		hooksecurefunc(WorldMapFrame, "OnMapChanged", self.UpdateMapID)

		self.CoordsUpdater = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer)
		self.CoordsUpdater:SetScript("OnUpdate", self.UpdateCoords)
	end

	if NE_WorldMap.db.profile.worldmap.SmallWorldMap then
		smallerMapScale = NE_WorldMap.db.profile.worldmap.SmallWorldMapScale or 0.9

		self.CreateMoverFrame(WorldMapFrame, nil, true)

		WorldMapFrame.BlackoutFrame.Blackout:SetTexture()
		WorldMapFrame.BlackoutFrame:EnableMouse(false)

		hooksecurefunc(WorldMapFrame, "Maximize", self.SetLargeWorldMap)
		hooksecurefunc(WorldMapFrame, "Minimize", self.SetSmallWorldMap)
		hooksecurefunc(WorldMapFrame, "SynchronizeDisplayState", self.SynchronizeDisplayState)
		hooksecurefunc(WorldMapFrame, "UpdateMaximizedSize", self.UpdateMaximizedSize)
	end

	WorldMapFrame:HookScript("OnShow", self.WorldMap_OnShow)
	WorldMapFrame:HookScript("OnHide", self.WorldMap_OnHide)

	hooksecurefunc(PlayerMovementFrameFader, "AddDeferredFrame", self.UpdateMapFade)

	-- if C["General"].NoTutorialButtons then
	-- 	WorldMapFrame.BorderFrame.Tutorial:Kill()
	-- end

	local loadWorldMapModules = {
		"CreateWorldMapReveal",
		"CreateWowHeadLinks",
		"CreateWorldMapPins",
	}

	for _, funcName in ipairs(loadWorldMapModules) do
		local func = self[funcName]
		if type(func) == "function" then
			local success, err = pcall(func, self)
			if not success then
				error("Error in function " .. funcName .. ": " .. tostring(err), 2)
			end
		end
	end
end