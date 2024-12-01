local _, Module = ...
Module.LibEasyMenu = LibStub("LibEasyMenu-1.0")

local function UpdateMinimapButton(button, icon)
	if not icon then
		return
	end

	button:ClearAllPoints()
	button:SetPoint("TOPLEFT", MinimapBackdrop, "TOPLEFT", 10, -150)

	button:SetNormalTexture(icon)
	local normalTexture = button:GetNormalTexture()
	if normalTexture then
		normalTexture:SetAtlas(icon)
	end

	button:SetPushedTexture(icon)
	local pushedTexture = button:GetPushedTexture()
	if pushedTexture then
		pushedTexture:SetAtlas(icon)
	end

	button:SetHighlightTexture(icon, "BLEND")
	local highlightTexture = button:GetHighlightTexture()
	if highlightTexture then
		highlightTexture:SetAtlas("dragonflight-landingbutton-circlehighlight")
	end

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

	ShowGarrisonLandingPage(...)
end

local function SetupGarrisonMinimapButton()
	local garrMinimapButton = _G.ExpansionLandingPageMinimapButton
	if garrMinimapButton then
		local buttonTextureIcon = "groupfinder-icon-class-" .. Module.MyClass
		UpdateMinimapButton(garrMinimapButton, buttonTextureIcon)

		garrMinimapButton:HookScript("OnShow", function(self)
			UpdateMinimapButton(self, buttonTextureIcon)
		end)

		hooksecurefunc(garrMinimapButton, "UpdateIcon", function(self)
			UpdateMinimapButton(self, buttonTextureIcon)
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
			end
		end)

		garrMinimapButton:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetText(self.title, 1, 1, 1)
			GameTooltip:AddLine(self.description, nil, nil, nil, true)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(Module.L["|cff5bc0beRight-click to toggle between garrisons.|r"], nil, nil, nil, true)
			GameTooltip:Show()
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

function Module:TrackMinimapPing()
	if not Module.db.profile.minimap.PingNotifier then
		return
	end

	local pingNotifierFrame = CreateFrame("Frame", nil, Minimap)
	pingNotifierFrame:SetAllPoints()

	pingNotifierFrame.text = Module.CreateFontString(pingNotifierFrame, 13, "", false, "OUTLINE", "TOP", 0, -20)

	local fadeAnimationGroup = pingNotifierFrame:CreateAnimationGroup()
	fadeAnimationGroup:SetScript("OnPlay", function()
		pingNotifierFrame:SetAlpha(1)
	end)

	fadeAnimationGroup:SetScript("OnFinished", function()
		pingNotifierFrame:SetAlpha(0)
	end)

	local fadeOutAnimation = fadeAnimationGroup:CreateAnimation("Alpha")
	fadeOutAnimation:SetFromAlpha(1)
	fadeOutAnimation:SetToAlpha(0)
	fadeOutAnimation:SetDuration(3)
	fadeOutAnimation:SetSmoothing("OUT")
	fadeOutAnimation:SetStartDelay(3)

	Module:RegisterEvent("MINIMAP_PING", function(_, unit)
		if UnitIsUnit(unit, "player") then
			return
		end

		local classToken = select(2, UnitClass(unit))
		local r, g, b = Module.ClassColor(classToken)

		local unitName = GetUnitName(unit)

		fadeAnimationGroup:Stop()
		pingNotifierFrame.text:SetText(unitName)
		pingNotifierFrame.text:SetTextColor(r, g, b)
		fadeAnimationGroup:Play()
	end)
end

function Module:PLAYER_LOGIN()
	DropDownList1:SetClampedToScreen(true)
	MinimapCluster:EnableMouse(false)
	Minimap:SetArchBlobRingScalar(0)
	Minimap:SetQuestBlobRingScalar(0)

	Module.HideObject(Minimap.ZoomIn)
	Module.HideObject(Minimap.ZoomOut)

	self:ReskinMinimapElements()
	self:TrackMinimapPing()
end
