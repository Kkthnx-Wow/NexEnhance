local _, Module = ...

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

-- Ignored button patterns
local ignoredButtons = {
	["GatherMatePin"] = true,
	["HandyNotes.-Pin"] = true,
	["TTMinimapButton"] = true,
}

-- Variables
local recycleBin
local buttons, shownButtons = {}, {}
local iconsPerRow = 6
local rowMult = iconsPerRow / 2 - 1
local currentIndex, pendingTime, timeThreshold = 0, 5, 12
local numMinimapChildren = 0

-- Helper functions
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
			child:SetParent(recycleBin)
			child:SetScript("OnDragStop", nil)
			child:SetScript("OnDragStart", nil)
			if child:HasScript("OnClick") then
				child:HookScript("OnClick", function()
					PlaySound(825)
				end)
			end
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
	recycleBin:SetHeight(row * 36 + 3)

	for index, button in pairs(shownButtons) do
		button:ClearAllPoints()
		if index == 1 then
			button:SetPoint("BOTTOMRIGHT", recycleBin, 0, 3)
		elseif mod(index, row) == 1 or row == 1 then
			button:SetPoint("RIGHT", shownButtons[index - row], "LEFT", 0, 0)
		else
			button:SetPoint("BOTTOM", shownButtons[index - 1], "TOP", 0, 3)
		end
	end
end

local function hideBinButton()
	recycleBin:Hide()
end

local function clickFunc(force)
	if force == 1 then
		UIFrameFadeOut(recycleBin, 0.5, 1, 0)
		C_Timer_After(0.5, hideBinButton)
	end
end

-- Main function
function Module:PLAYER_LOGIN()
	if C_AddOns.IsAddOnLoaded("MBB") then
		return
	end

	if not Module.db.profile.minimap.recycleBin then
		return
	end

	local toggleButton = CreateFrame("Button", "RecycleBinToggleButton", Minimap)
	toggleButton:SetSize(30, 30)
	toggleButton:SetPoint("BOTTOMLEFT", 27, 7)
	toggleButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	toggleButton:SetFrameLevel(999)
	Module.AddTooltip(toggleButton, "ANCHOR_LEFT", "|nStores minimap buttons to reduce clutter.", "info", "Recycle Bin", true)

	local recycleBinIcon = (Module.MyFaction == "Alliance" and "ShipMissionIcon-SiegeA-MapBadge") or (Module.MyFaction == "Horde" and "ShipMissionIcon-SiegeH-MapBadge") or "ShipMissionIcon-Combat-MapBadge"

	toggleButton:SetHighlightTexture(recycleBinIcon, "BLEND")
	local highlightTexture = toggleButton:GetHighlightTexture()
	if highlightTexture then
		highlightTexture:SetAtlas("dragonflight-landingbutton-circlehighlight")
	end

	toggleButton.Icon = toggleButton:CreateTexture(nil, "ARTWORK")
	toggleButton.Icon:SetAllPoints()
	toggleButton.Icon:SetAtlas(recycleBinIcon)

	recycleBin = CreateFrame("Frame", "RecycleBinFrame", UIParent)
	recycleBin:SetPoint("RIGHT", toggleButton, "LEFT", 0, 0)
	recycleBin:SetSize(220, 30)
	recycleBin:Hide()

	toggleButton:SetScript("OnClick", function(_, btn)
		if btn == "RightButton" then
			Module.db.profile.minimap.recycleBinAuto = not Module.db.profile.minimap.recycleBinAuto
			toggleButton:GetScript("OnEnter")(toggleButton)
		else
			if recycleBin:IsShown() then
				clickFunc(1)
			else
				SortRubbish()
				UIFrameFadeIn(recycleBin, 0.5, 0, 1)
			end
		end
	end)

	CollectRubbish()
end
