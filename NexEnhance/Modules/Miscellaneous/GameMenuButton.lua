-- GameMenuButton.lua

local _, Module = ...

local gameMenuLastButtons = {
	[_G.GAMEMENU_OPTIONS] = 1,
	[_G.BLIZZARD_STORE] = 2,
}

function Module:PositionGameMenuButton()
	local anchorIndex = (C_StorePublic.IsEnabled and C_StorePublic.IsEnabled() and 2) or 1
	for button in GameMenuFrame.buttonPool:EnumerateActive() do
		local text = button:GetText()
		GameMenuFrame.MenuButtons[text] = button
		local lastIndex = gameMenuLastButtons[text]
		if lastIndex == anchorIndex and GameMenuFrame.NexEnhance then
			GameMenuFrame.NexEnhance:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -10)
		elseif not lastIndex then
			local point, anchor, point2, x, y = button:GetPoint()
			button:SetPoint(point, anchor, point2, x, y - 36)
		end
	end
	GameMenuFrame:SetHeight(GameMenuFrame:GetHeight() + 36)
	if GameMenuFrame.NexEnhance then
		GameMenuFrame.NexEnhance:SetFormattedText(Module.Title)
	end
end

function Module:ClickGameMenu()
	if InCombatLockdown() then
		UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT)
		return
	end
	OpenConfigWithDefaultGroup("general")
	HideUIPanel(GameMenuFrame)
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
end

function Module:CreateGUIGameMenuButton()
	if GameMenuFrame.NexEnhance then
		return
	end
	local button = CreateFrame("Button", "NexEnhance_GameMenuButton", GameMenuFrame, "MainMenuFrameButtonTemplate")
	button:SetScript("OnClick", function()
		Module:ClickGameMenu()
	end)

	GameMenuFrame.NexEnhance = button
	GameMenuFrame.MenuButtons = {}
	hooksecurefunc(GameMenuFrame, "Layout", function()
		Module:PositionGameMenuButton()
	end)
end

function Module:PLAYER_LOGIN()
	self:CreateGUIGameMenuButton()
end
