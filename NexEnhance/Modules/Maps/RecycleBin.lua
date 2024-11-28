local _, Module = ...

-- Sourced: NDui (Siweia)
-- Edited: KkthnxUI (Kkthnx)

-- Cache global references
local string_match = string.match
local string_upper = string.upper
local table_insert = table.insert
local C_Timer_After = C_Timer.After
local CreateFrame = CreateFrame
local Minimap = Minimap
local PlaySound = PlaySound
local UIParent = UIParent

-- Blacklisted buttons
local blackList = {
	["BattlefieldMinimap"] = true,
	["FeedbackUIButton"] = true,
	["GameTimeFrame"] = true,
	["GarrisonLandingPageMinimapButton"] = true,
	["MiniMapBattlefieldFrame"] = true,
	["MiniMapLFGFrame"] = true,
	["MinimapBackdrop"] = true,
	["MinimapZoneTextButton"] = true,
	["QueueStatusMinimapButton"] = true,
	["RecycleBinFrame"] = true,
	["RecycleBinToggleButton"] = true,
	["TimeManagerClockButton"] = true,
}

-- Ignored buttons pattern
local ignoredButtons = {
	["GatherMatePin"] = true,
	["HandyNotes.-Pin"] = true,
	["TTMinimapButton"] = true,
}

local buttons, shownButtons = {}, {}
local iconsPerRow = 6
local rowMult = iconsPerRow / 2 - 1
local currentIndex, pendingTime, timeThreshold = 0, 5, 12
local numMinimapChildren = 0

local function isButtonIgnored(name)
	for addonName in pairs(ignoredButtons) do
		if string_match(name, addonName) then
			return true
		end
	end
end

local function ReskinMinimapButton(child)
	table_insert(buttons, child)
end

local function KillMinimapButtons()
	for _, child in pairs(buttons) do
		if not child.styled then
			child:SetParent(RecycleBinFrame)
			if child:HasScript("OnDragStop") then
				child:SetScript("OnDragStop", nil)
			end
			if child:HasScript("OnDragStart") then
				child:SetScript("OnDragStart", nil)
			end
			if child:HasScript("OnClick") then
				child:HookScript("OnClick", function()
					PlaySound(825)
				end)
			end
			-- Handle special cases
			local name = child:GetName()
			if name == "DBMMinimapButton" then
				child:SetScript("OnMouseDown", nil)
				child:SetScript("OnMouseUp", nil)
			elseif name == "BagSync_MinimapButton" then
				child:HookScript("OnMouseUp", function()
					PlaySound(825)
				end)
			elseif name == "WIM3MinimapButton" then
				child.SetParent = Module.noop
				child:SetFrameStrata("DIALOG")
				child.SetFrameStrata = Module.noop
			end
			child.styled = true
		end
	end
end

local function CollectRubbish()
	local numChildren = Minimap:GetNumChildren()
	if numChildren ~= numMinimapChildren then
		-- examine new children
		for i = 1, numChildren do
			local child = select(i, Minimap:GetChildren())
			local name = child and child.GetName and child:GetName()
			if name and not child.isExamed and not blackList[name] then
				if (child:IsObjectType("Button") or string_match(string_upper(name), "BUTTON")) and not isButtonIgnored(name) then
					ReskinMinimapButton(child)
				end
				child.isExamed = true
			end
		end
		numMinimapChildren = numChildren
	end
	KillMinimapButtons()
	currentIndex = currentIndex + 1
	if currentIndex < timeThreshold then
		C_Timer_After(pendingTime, CollectRubbish)
	end
end

local function SortRubbish()
	if #buttons == 0 then
		return
	end
	wipe(shownButtons)
	for _, button in pairs(buttons) do
		if button:IsShown() then
			table_insert(shownButtons, button)
		end
	end
	local numShown = #shownButtons
	local row = numShown == 0 and 1 or Module:Round((numShown + rowMult) / iconsPerRow)
	local newHeight = row * 36 + 3
	RecycleBinFrame:SetHeight(newHeight)
	for index, button in pairs(shownButtons) do
		button:ClearAllPoints()
		if index == 1 then
			button:SetPoint("BOTTOMRIGHT", RecycleBinFrame, 0, 3)
		elseif mod(index, row) == 1 or row == 1 then
			button:SetPoint("RIGHT", shownButtons[index - row], "LEFT", 0, 0)
		else
			button:SetPoint("BOTTOM", shownButtons[index - 1], "TOP", 0, 3)
		end
	end
end

local function hideBinButton()
	RecycleBinFrame:Hide()
end

local function clickFunc(force)
	if force == 1 then
		PlaySound(825)
		UIFrameFadeOut(RecycleBinFrame, 0.5, 1, 0)
		C_Timer_After(0.5, hideBinButton)
	end
end

function Module:PLAYER_LOGIN()
	if C_AddOns.IsAddOnLoaded("MBB") then
		return
	end

	if not Module.db.profile.minimap.recycleBin then
		return
	end

	-- Recycle bin toggle button
	local bu = CreateFrame("Button", "RecycleBinToggleButton", Minimap)
	bu:SetFrameLevel(Minimap:GetFrameLevel() + 2)
	bu:SetSize(30, 30)
	bu:SetPoint("BOTTOMLEFT", 26, 7)

	-- Tooltip
	bu:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("RecycleBin", 1, 1, 1)
		GameTooltip:AddLine("Collects minimap buttons and provides access to them through a pop-up menu.", nil, nil, nil, true)
		GameTooltip:Show()

		-- Enlarge button slightly on hover
		-- self:SetScale(1.1)
		self.Icon:SetVertexColor(0.8, 0.8, 0.8) -- Slightly brighten the icon
	end)

	bu:SetScript("OnLeave", function(self)
		GameTooltip:Hide()

		-- Reset button scale on leave
		-- self:SetScale(1.0)
		self.Icon:SetVertexColor(1, 1, 1) -- Reset icon color
	end)

	-- Icon setup
	local recycleBinIcon = (Module.MyFaction == "Alliance") and "ShipMissionIcon-SiegeA-MapBadge" or (Module.MyFaction == "Horde") and "ShipMissionIcon-SiegeH-MapBadge" or "ShipMissionIcon-Combat-MapBadge"

	bu.Icon = bu:CreateTexture(nil, "ARTWORK")
	bu.Icon:SetAllPoints()
	bu.Icon:SetAtlas(recycleBinIcon)

	-- Set textures for button states
	bu:SetNormalTexture(recycleBinIcon)
	bu:SetPushedTexture(recycleBinIcon)
	bu:SetHighlightTexture(recycleBinIcon, "BLEND")
	bu:GetHighlightTexture():SetAtlas("dragonflight-landingbutton-circlehighlight")

	-- Recycle bin frame
	local width, height = 220, 30
	local bin = CreateFrame("Frame", "RecycleBinFrame", UIParent)
	bin:SetPoint("RIGHT", bu, "LEFT", 0, 0)
	bin:SetSize(width, height)
	bin:Hide()

	-- Click functionality
	bu:SetScript("OnMouseDown", function(self)
		-- Slightly move button to mimic a pressed effect
		self:SetPoint("BOTTOMLEFT", 27, 6)
	end)

	bu:SetScript("OnMouseUp", function(self)
		-- Reset button position on release
		self:SetPoint("BOTTOMLEFT", 26, 7)

		if bin:IsShown() then
			clickFunc(1)
		else
			PlaySound(825)
			SortRubbish()
			UIFrameFadeIn(bin, 0.5, 0, 1)
		end
	end)

	-- Collect minimap buttons
	CollectRubbish()
end
