local _, Module = ...
Module.LibEasyMenu = LibStub("LibEasyMenu-1.0")

local function UpdateMinimapButton(button, icon)
	button:ClearAllPoints()
	button:SetPoint("TOPLEFT", MinimapBackdrop, "TOPLEFT", 10, -150)

	button:SetNormalTexture(icon)
	button:GetNormalTexture():SetAtlas(icon)

	button:SetPushedTexture(icon)
	button:GetPushedTexture():SetAtlas(icon)

	button:SetHighlightTexture(icon, "BLEND")
	button:GetHighlightTexture():SetAtlas("dragonflight-landingbutton-circlehighlight")

	button.LoopingGlow:SetAtlas(icon)
	button.LoopingGlow:SetSize(29, 29)

	button:SetHitRectInsets(0, 0, 0, 0)
	button:SetSize(29, 29)
end

local function ToggleLandingPage(_, ...)
	if not C_Garrison.HasGarrison(...) then
		UIErrorsFrame:AddMessage(Module.InfoColor .. CONTRIBUTION_TOOLTIP_UNLOCKED_WHEN_ACTIVE)
		return
	end

	local covenantID = C_Covenants.GetActiveCovenantID()
	if covenantID and covenantID > 0 then
		local covenantData = C_Covenants.GetCovenantData(covenantID)
		if covenantData then
			print("Covenant Name:", covenantData.name)
		else
			UIErrorsFrame:AddMessage(Module.InfoColor .. "No covenant data available.")
		end
	else
		UIErrorsFrame:AddMessage(Module.InfoColor .. "No active covenant selected.")
	end

	ShowGarrisonLandingPage(...)
end

local function SetupGarrisonMinimapButton()
	local garrMinimapButton = _G.ExpansionLandingPageMinimapButton
	if garrMinimapButton then
		local buttonTextureIcon = "groupfinder-icon-class-" .. Module.MyClass
		UpdateMinimapButton(garrMinimapButton, buttonTextureIcon)

		garrMinimapButton:HookScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetText(self.title, 1, 1, 1)
			GameTooltip:AddLine(self.description, nil, nil, nil, true)
			GameTooltip:AddLine(Module.L["Right click to switch garrisons"], nil, nil, nil, true)
			GameTooltip:Show()
		end)

		garrMinimapButton:HookScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)

		local menuList = {
			{
				text = _G.GARRISON_TYPE_9_0_LANDING_PAGE_TITLE,
				func = ToggleLandingPage,
				arg1 = Enum.GarrisonType.Type_9_0_Garrison,
				notCheckable = true,
				icon = 1046795,
			},
			{
				text = _G.WAR_CAMPAIGN,
				func = ToggleLandingPage,
				arg1 = Enum.GarrisonType.Type_8_0_Garrison,
				notCheckable = true,
				icon = 237387,
			},
			{
				text = _G.ORDER_HALL_LANDING_PAGE_TITLE,
				func = ToggleLandingPage,
				arg1 = Enum.GarrisonType.Type_7_0_Garrison,
				notCheckable = true,
				icon = 1397630,
			},
			{
				text = _G.GARRISON_LANDING_PAGE_TITLE,
				func = ToggleLandingPage,
				arg1 = Enum.GarrisonType.Type_6_0_Garrison,
				notCheckable = true,
				icon = 1005027,
			},
		}

		garrMinimapButton:HookScript("OnMouseDown", function(self, btn)
			if btn == "RightButton" then
				if _G.GarrisonLandingPage and _G.GarrisonLandingPage:IsShown() then
					HideUIPanel(_G.GarrisonLandingPage)
				end
				if _G.ExpansionLandingPage and _G.ExpansionLandingPage:IsShown() then
					HideUIPanel(_G.ExpansionLandingPage)
				end
				Module.LibEasyMenu.Create(menuList, Module.EasyMenu, self, -80, 0, "MENU", 1)
			else
				self:SetPoint("TOPLEFT", MinimapBackdrop, "TOPLEFT", 10, -152)
			end
		end)

		garrMinimapButton:HookScript("OnMouseUp", function(self)
			self:SetPoint("TOPLEFT", MinimapBackdrop, "TOPLEFT", 10, -150)
		end)

		-- Dynamic updating of the button
		garrMinimapButton:HookScript("OnShow", function(self)
			UpdateMinimapButton(self, buttonTextureIcon)
		end)

		hooksecurefunc(garrMinimapButton, "UpdateIcon", function(self)
			UpdateMinimapButton(self, buttonTextureIcon)
		end)
	end
end

local function ReplaceInstanceDifficultyFlag(texture)
	texture:SetTexture(Module.Media .. "InstanceDifficulty.blp")
end

local function ReskinInstanceDifficulty(instanceDifficulty)
	if not instanceDifficulty then
		return
	end
	instanceDifficulty.Border:Hide()
	ReplaceInstanceDifficultyFlag(instanceDifficulty.Background)
	hooksecurefunc(instanceDifficulty.Background, "SetAtlas", ReplaceInstanceDifficultyFlag)
end

local function SetupInstanceDifficulty()
	local instDifficulty = MinimapCluster.InstanceDifficulty
	if instDifficulty then
		ReskinInstanceDifficulty(instDifficulty.Instance)
		ReskinInstanceDifficulty(instDifficulty.Default)
		ReskinInstanceDifficulty(instDifficulty.Guild)
		ReskinInstanceDifficulty(instDifficulty.ChallengeMode)
	end
end

function Module:ReskinMinimapElements()
	SetupGarrisonMinimapButton()
	SetupInstanceDifficulty()
end

function Module:PLAYER_LOGIN()
	DropDownList1:SetClampedToScreen(true)
	MinimapCluster:EnableMouse(false)
	Minimap:SetArchBlobRingScalar(0)
	Minimap:SetQuestBlobRingScalar(0)

	Module.HideObject(Minimap.ZoomIn)
	Module.HideObject(Minimap.ZoomOut)

	self:ReskinMinimapElements()
end
