local _, Module = ...
Module.originalPetHitIndicatorParent = nil

function Module:TogglePlayerHitIndicator()
	if Module.NexConfig.unitframes.playerFrameEnhancements.playerHitIndicatorHide then
		PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HitIndicator:SetAlpha(0)
		PetHitIndicator:SetParent(Module.HiddenFrame)
	else
		PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HitIndicator:SetAlpha(1)
		PetHitIndicator:SetParent(PetFrame) -- Idk what the real parent is? I tried to debug it but...
	end
end

function Module:OnLogin()
	self:TogglePlayerHitIndicator()
end
