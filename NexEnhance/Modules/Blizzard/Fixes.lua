local _, Module = ...

-- Unregister talent event
if PlayerTalentFrame then
	PlayerTalentFrame:UnregisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
else
	hooksecurefunc("TalentFrame_LoadUI", function()
		PlayerTalentFrame:UnregisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
	end)
end

-- Fix blizz bug in addon list
local _AddonTooltip_Update = AddonTooltip_Update
function AddonTooltip_Update(owner)
	if not owner then
		return
	end
	if owner:GetID() < 1 then
		return
	end
	_AddonTooltip_Update(owner)
end

-- Fix Drag Collections taint
do
	-- Create a frame for handling collections-related events and fixes
	local collectionsEventFrame = CreateFrame("Frame")
	local isDragFixApplied = false

	collectionsEventFrame:SetScript("OnEvent", function(self, event, addon)
		if event == "ADDON_LOADED" and addon == "Blizzard_Collections" then
			local checkBox = WardrobeTransmogFrame.ToggleSecondaryAppearanceCheckbox
			checkBox.Label:ClearAllPoints()
			checkBox.Label:SetPoint("LEFT", checkBox, "RIGHT", 2, 1)
			checkBox.Label:SetWidth(152)

			CollectionsJournal:HookScript("OnShow", function()
				if not isDragFixApplied then
					if InCombatLockdown() then
						self:RegisterEvent("PLAYER_REGEN_ENABLED")
					else
						Module.CreateMoverFrame(CollectionsJournal)
					end
					isDragFixApplied = true
				end
			end)
			self:UnregisterEvent("ADDON_LOADED")
		elseif event == "PLAYER_REGEN_ENABLED" then
			if not isDragFixApplied then
				Module.CreateMoverFrame(CollectionsJournal)
				isDragFixApplied = true
			end
			self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		end
	end)

	collectionsEventFrame:RegisterEvent("ADDON_LOADED")
end

-- Select target when click on raid units
do
	local raidUIEventFrame = CreateFrame("Frame")

	-- Function to handle fixing the Raid Group Button
	local function fixRaidGroupButton()
		for i = 1, 40 do
			local bu = _G["RaidGroupButton" .. i]
			if bu and bu.unit and not bu.clickFixed then
				bu:SetAttribute("type", "target")
				bu:SetAttribute("unit", bu.unit)

				bu.clickFixed = true
			end
		end
	end

	-- Event handler for fixing Blizzard_RaidUI issues
	raidUIEventFrame:SetScript("OnEvent", function(self, event, addon)
		if event == "ADDON_LOADED" and addon == "Blizzard_RaidUI" then
			if not InCombatLockdown() then
				fixRaidGroupButton()
			else
				self:RegisterEvent("PLAYER_REGEN_ENABLED")
			end
			self:UnregisterEvent("ADDON_LOADED")
		elseif event == "PLAYER_REGEN_ENABLED" then
			if RaidGroupButton1 and RaidGroupButton1:GetAttribute("type") ~= "target" then
				fixRaidGroupButton()
			end
			self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		end
	end)

	raidUIEventFrame:RegisterEvent("ADDON_LOADED")
end

-- Fix blizz guild news hyperlink error
do
	local function fixGuildNews(_, addon)
		if addon ~= "Blizzard_GuildUI" then
			return
		end

		local _GuildNewsButton_OnEnter = GuildNewsButton_OnEnter
		function GuildNewsButton_OnEnter(self)
			if not (self.newsInfo and self.newsInfo.whatText) then
				return
			end
			_GuildNewsButton_OnEnter(self)
		end

		Module:UnregisterEvent("ADDON_LOADED", fixGuildNews)
	end

	Module:RegisterEvent("ADDON_LOADED", fixGuildNews)
end

-- Fix guild news jam
do
	local lastTime, timeGap = 0, 1.5
	local function updateGuildNews(self, event)
		if event == "PLAYER_ENTERING_WORLD" then
			QueryGuildNews()
		else
			if self:IsVisible() then
				local nowTime = GetTime()
				if nowTime - lastTime > timeGap then
					CommunitiesGuildNews_Update(self)
					lastTime = nowTime
				end
			end
		end
	end

	CommunitiesFrameGuildDetailsFrameNews:SetScript("OnEvent", updateGuildNews)
end
