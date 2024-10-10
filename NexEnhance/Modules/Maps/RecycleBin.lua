local _, Module = ...

-- Sourced: NDui (Siweia)
-- Edited: KkthnxUI (Kkthnx)

local string_find = string.find
local string_match = string.match
local string_upper = string.upper
local table_insert = table.insert

local C_Timer_After = C_Timer.After
local CreateFrame = CreateFrame
local Minimap = Minimap
local PlaySound = PlaySound
local UIParent = UIParent

function Module:PLAYER_LOGIN()
	if not Module.db.profile.minimap.recycleBin then
		return
	end

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

	local bu = CreateFrame("Button", "RecycleBinToggleButton", Minimap)
	bu:SetFrameLevel(Minimap:GetFrameLevel() + 2)
	bu:SetSize(30, 30)
	bu:ClearAllPoints()
	bu:SetPoint("BOTTOMLEFT", 26, 7)

	bu:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("RecycleBin", 1, 1, 1)
		GameTooltip:AddLine("Collects minimap buttons and provides access to them through a pop-up menu.", nil, nil, nil, true)
		GameTooltip:Show()
	end)

	local recycleBinIcon
	if Module.MyFaction == "Alliance" then
		recycleBinIcon = "ShipMissionIcon-SiegeA-MapBadge"
	elseif Module.MyFaction == "Horde" then
		recycleBinIcon = "ShipMissionIcon-SiegeH-MapBadge"
	else
		recycleBinIcon = "ShipMissionIcon-Combat-MapBadge"
	end

	bu.Icon = bu:CreateTexture(nil, "ARTWORK")
	bu.Icon:SetAllPoints()
	bu.Icon:SetAtlas(recycleBinIcon)

	local width, height = 220, 30
	local bin = CreateFrame("Frame", "RecycleBinFrame", UIParent)
	bin:ClearAllPoints()
	bin:SetPoint("RIGHT", bu, "LEFT", 0, 0)
	bin:SetSize(width, height)
	bin:Hide()

	local function hideBinButton()
		bin:Hide()
	end

	local function clickFunc(force)
		if force == 1 then
			PlaySound(825)
			UIFrameFadeOut(bin, 0.5, 1, 0)
			C_Timer_After(0.5, hideBinButton)
		end
	end

	local ignoredButtons = {
		["GatherMatePin"] = true,
		["HandyNotes.-Pin"] = true,
		["TTMinimapButton"] = true,
	}

	local function isButtonIgnored(name)
		for addonName in pairs(ignoredButtons) do
			if string_match(name, addonName) then
				return true
			end
		end
	end

	local iconsPerRow = 6
	local rowMult = iconsPerRow / 2 - 1
	local currentIndex, pendingTime, timeThreshold = 0, 5, 12
	local buttons, numMinimapChildren = {}, 0

	local function ReskinMinimapButton(child)
		table_insert(buttons, child)
	end

	local function KillMinimapButtons()
		for _, child in pairs(buttons) do
			if not child.styled then
				child:SetParent(bin)
				if child:HasScript("OnDragStop") then
					child:SetScript("OnDragStop", nil)
				end

				if child:HasScript("OnDragStart") then
					child:SetScript("OnDragStart", nil)
				end

				if child:HasScript("OnClick") then
					child:HookScript("OnClick", clickFunc)
				end

				-- Naughty Addons
				local name = child:GetName()
				if name == "DBMMinimapButton" then
					child:SetScript("OnMouseDown", nil)
					child:SetScript("OnMouseUp", nil)
				elseif name == "BagSync_MinimapButton" then
					child:HookScript("OnMouseUp", clickFunc)
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
			-- schedule another call if within time threshold
			C_Timer_After(pendingTime, CollectRubbish)
		end
	end

	local shownButtons = {}
	local function SortRubbish()
		if #buttons == 0 then
			return
		end

		table.wipe(shownButtons)
		for _, button in pairs(buttons) do
			if next(button) and button:IsShown() then -- fix for fuxking AHDB
				table_insert(shownButtons, button)
			end
		end

		local numShown = #shownButtons
		local row = numShown == 0 and 1 or Module:Round((numShown + rowMult) / iconsPerRow)
		local newHeight = row * 36 + 3
		bin:SetHeight(newHeight)

		for index, button in pairs(shownButtons) do
			button:ClearAllPoints()
			if index == 1 then
				button:SetPoint("BOTTOMRIGHT", bin, 0, 3)
			elseif row > 1 and mod(index, row) == 1 or row == 1 then
				button:SetPoint("RIGHT", shownButtons[index - row], "LEFT", 0, 0)
			else
				button:SetPoint("BOTTOM", shownButtons[index - 1], "TOP", 0, 3)
			end
		end
	end

	bu:SetScript("OnClick", function()
		if bin:IsShown() then
			clickFunc(1)
		else
			PlaySound(825)
			SortRubbish()
			UIFrameFadeIn(bin, 0.5, 0, 1)
		end
	end)

	CollectRubbish()
end
