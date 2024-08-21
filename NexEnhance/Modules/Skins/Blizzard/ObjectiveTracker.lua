local _, Module = ...

-- Extract color components for easier reference
local colorRed, colorGreen, colorBlue = Module.r, Module.g, Module.b

-- -- Function to apply skin to a header
-- function Module:ApplySkinToHeader(header)
-- 	header.Text:SetTextColor(colorRed, colorGreen, colorBlue)
-- 	header.Background:SetTexture(nil)

-- 	local headerBackgroundTexture = header:CreateTexture(nil, "ARTWORK")
-- 	headerBackgroundTexture:SetTexture("Interface\\LFGFrame\\UI-LFG-SEPARATOR")
-- 	headerBackgroundTexture:SetTexCoord(0, 0.66, 0, 0.31)
-- 	headerBackgroundTexture:SetVertexColor(colorRed, colorGreen, colorBlue, 0.8)
-- 	headerBackgroundTexture:SetPoint("BOTTOMLEFT", 0, -4)
-- 	headerBackgroundTexture:SetSize(250, 30)

-- 	header.bg = headerBackgroundTexture -- Make accessible for other addons
-- end

-- -- Handle collapse
-- local function UpdateCollapseIcon(texture, collapsed)
-- 	local atlas = collapsed and "Campaign_HeaderIcon_Closed" or "Campaign_HeaderIcon_Open"
-- 	texture:SetAtlas(atlas, true)
-- end

-- local function ResetCollapseIcon(self, texture)
-- 	if self.settingTexture then
-- 		return
-- 	end
-- 	self.settingTexture = true
-- 	self:SetNormalTexture(0)

-- 	if texture and texture ~= "" then
-- 		if strfind(texture, "Plus") or strfind(texture, "[Cc]losed") then
-- 			self.__texture:UpdateCollapseIcon(true)
-- 		elseif strfind(texture, "Minus") or strfind(texture, "[Oo]pen") then
-- 			self.__texture:UpdateCollapseIcon(false)
-- 		end
-- 	end
-- 	self.settingTexture = nil
-- end

-- -- Handle close button
-- function Module:ReskinCollapseButton()
-- 	self:SetNormalTexture(0)
-- 	self:SetHighlightTexture(0)
-- 	self:SetPushedTexture(0)

-- 	self.__texture = self:CreateTexture(nil, "OVERLAY")
-- 	self.__texture:SetPoint("CENTER")
-- 	self.__texture.UpdateCollapseIcon = UpdateCollapseIcon

-- 	hooksecurefunc(self, "SetNormalAtlas", ResetCollapseIcon)
-- end

-- local function UpdateMinimizeButtonState(button, collapsed)
-- 	button = button.MinimizeButton or button
-- 	button.__texture:UpdateCollapseIcon(collapsed)
-- end

-- local function ReskinMinimizeButton(button)
-- 	Module.ReskinCollapseButton(button)
-- 	button:GetNormalTexture():SetAlpha(0)
-- 	button:GetPushedTexture():SetAlpha(0)
-- 	button.__texture:UpdateCollapseIcon(false)
-- 	if button.SetCollapsed then
-- 		hooksecurefunc(button, "SetCollapsed", UpdateMinimizeButtonState)
-- 	end
-- end

-- -- Function triggered on PLAYER_LOGIN event
-- function Module:PLAYER_LOGIN()
-- 	if not Module.db.profile.skins.blizzskins.objectiveTracker then
-- 		return
-- 	end

-- 	local headers = {
-- 		_G.BONUS_OBJECTIVE_TRACKER_MODULE.Header,
-- 		-- _G.MONTHLY_ACTIVITIES_TRACKER_MODULE.Header,
-- 		_G.ObjectiveTrackerBlocksFrame.AchievementHeader,
-- 		_G.ObjectiveTrackerBlocksFrame.CampaignQuestHeader,
-- 		_G.ObjectiveTrackerBlocksFrame.ProfessionHeader,
-- 		_G.ObjectiveTrackerBlocksFrame.QuestHeader,
-- 		_G.ObjectiveTrackerBlocksFrame.ScenarioHeader,
-- 		_G.ObjectiveTrackerFrame.BlocksFrame.UIWidgetsHeader,
-- 		_G.WORLD_QUEST_TRACKER_MODULE.Header,
-- 	}

-- 	for _, header in pairs(headers) do
-- 		self:ApplySkinToHeader(header)
-- 	end

-- 	-- Minimize Button
-- 	local mainMinimizeButton = ObjectiveTrackerFrame.HeaderMenu.MinimizeButton
-- 	ReskinMinimizeButton(mainMinimizeButton)

-- 	for _, header in pairs(headers) do
-- 		local minimizeButton = header.MinimizeButton
-- 		if minimizeButton then
-- 			ReskinMinimizeButton(minimizeButton)
-- 		end
-- 	end
-- end

local function reskinHeader(header)
	header.Text:SetTextColor(colorRed, colorGreen, colorBlue)
	header.Background:SetTexture(nil)
	local bg = header:CreateTexture(nil, "ARTWORK")
	bg:SetTexture("Interface\\LFGFrame\\UI-LFG-SEPARATOR")
	bg:SetTexCoord(0, 0.66, 0, 0.31)
	bg:SetVertexColor(colorRed, colorGreen, colorBlue, 0.8)
	bg:SetPoint("BOTTOMLEFT", 0, -4)
	bg:SetSize(250, 30)
	header.bg = bg -- accessable for other addons
end

-- Handle collapse
local function UpdateCollapseIcon(texture, collapsed)
	local atlas = collapsed and "Campaign_HeaderIcon_Closed" or "Campaign_HeaderIcon_Open"
	texture:SetAtlas(atlas, true)
end

local function ResetCollapseIcon(self, texture)
	if self.settingTexture then
		return
	end
	self.settingTexture = true
	self:SetNormalTexture(0)

	if texture and texture ~= "" then
		if strfind(texture, "Plus") or strfind(texture, "[Cc]losed") then
			self.__texture:DoCollapse(true)
		elseif strfind(texture, "Minus") or strfind(texture, "[Oo]pen") then
			self.__texture:DoCollapse(false)
		end
	end
	self.settingTexture = nil
end

-- Handle close button
function Module:ReskinCollapseButton()
	self:SetNormalTexture(0)
	self:SetHighlightTexture(0)
	self:SetPushedTexture(0)

	self.__texture = self:CreateTexture(nil, "OVERLAY")
	self.__texture:SetPoint("CENTER")
	self.__texture.DoCollapse = UpdateCollapseIcon

	hooksecurefunc(self, "SetNormalAtlas", ResetCollapseIcon)
end

local function UpdateMinimizeButtonState(button, collapsed)
	button = button.MinimizeButton
	button.__texture:DoCollapse(collapsed)
end

local function ReskinMinimizeButton(button)
	Module.ReskinCollapseButton(button)
	button:GetNormalTexture():SetAlpha(0)
	button:GetPushedTexture():SetAlpha(0)
	button.__texture:DoCollapse(false)
	if button.SetCollapsed then
		hooksecurefunc(button, "SetCollapsed", UpdateMinimizeButtonState)
	end
end

function Module:PLAYER_LOGIN()
	-- Reskin Headers
	local mainHeader = ObjectiveTrackerFrame.Header
	Module.StripTextures(mainHeader) -- main header looks simple this way

	local trackers = {
		ScenarioObjectiveTracker,
		UIWidgetObjectiveTracker,
		CampaignQuestObjectiveTracker,
		QuestObjectiveTracker,
		AdventureObjectiveTracker,
		AchievementObjectiveTracker,
		MonthlyActivitiesObjectiveTracker,
		ProfessionsRecipeTracker,
		BonusObjectiveTracker,
		WorldQuestObjectiveTracker,
	}
	for _, tracker in pairs(trackers) do
		reskinHeader(tracker.Header)
	end

	-- Minimize Button
	local mainMinimizeButton = mainHeader.MinimizeButton
	ReskinMinimizeButton(mainMinimizeButton)
end
