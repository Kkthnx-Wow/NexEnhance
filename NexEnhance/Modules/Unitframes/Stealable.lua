local _, Module = ...

-- Configuration
local buffsStealable = true

-- Function to update buff stealable status
local function UpdateBuffStealable()
	if buffsStealable then
		hooksecurefunc("TargetFrame_UpdateBuffAnchor", function(self, buff, index)
			local _, _, _, _, debuffType = UnitBuff(self.unit, index)
			if debuffType == "Magic" and self.unit ~= Module.MyName then
				buff.Stealable:Show()
			else
				buff.Stealable:Hide()
			end
		end)
	end
end

-- Event handler for player login
function Module:PLAYER_LOGIN()
	if IsAddOnLoaded("BetterBlizzFrames") then
		return -- Skip if BetterBlizzFrames addon is loaded
	end

	UpdateBuffStealable()
end
