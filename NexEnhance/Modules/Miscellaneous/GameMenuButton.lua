-- GameMenuButton.lua

local _, Module = ...

function Module:CreateGUIGameMenuButton()
	local gui = CreateFrame("Button", "NexEnhance_GameMenuButton", GameMenuFrame, "GameMenuButtonTemplate, BackdropTemplate")
	gui:SetText(Module.Title)
	gui:SetPoint("TOP", GameMenuButtonAddons, "BOTTOM", 0, -21)
	GameMenuFrame:HookScript("OnShow", function(self)
		GameMenuButtonLogout:SetPoint("TOP", gui, "BOTTOM", 0, -21)
		self:SetHeight(self:GetHeight() + gui:GetHeight() + 22)
	end)

	gui:SetScript("OnClick", function()
		if InCombatLockdown() then
			UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT)
			return
		end
		OpenConfigWithDefaultGroup("general")
		HideUIPanel(GameMenuFrame)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
	end)
end

function Module:PLAYER_LOGIN()
	self:CreateGUIGameMenuButton()
end
