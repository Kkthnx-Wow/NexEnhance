local _, Module = ...

-- Function to hide the player's hit indicators
function Module:HidePlayerHitIndicator()
	if PlayerHitIndicator then
		PlayerHitIndicator:SetText(nil)
		PlayerHitIndicator.SetText = Module.Dummy
	else
		-- PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HitIndicator.HitText:SetText(nil)
		-- PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HitIndicator.HitText = Module.Dummy
		PlayerFrame:HookScript("OnEvent", function()
			PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HitIndicator.HitText:Hide()
		end)
	end
end

-- Function to hide the pet's hit indicator
function Module:HidePetHitIndicator()
	if PetHitIndicator then
		PetHitIndicator:SetText(nil)
		PetHitIndicator.SetText = Module.Dummy
	end
end

-- Function to hide all hit indicators
function Module:HideAllHitIndicators()
	self:HidePlayerHitIndicator()
	self:HidePetHitIndicator()
end

-- Event handler for PLAYER_LOGIN
function Module:PLAYER_LOGIN()
	self:HideAllHitIndicators()
end
