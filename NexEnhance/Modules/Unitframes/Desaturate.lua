local _, Module = ...

-- Configuration
local debuffsDesaturate = true

-- Function to update debuff desaturation
local function UpdateDebuffDesaturate()
	if debuffsDesaturate then
		-- Show all debuffs on target
		SetCVar("noBuffDebuffFilterOnTarget", 1)

		-- Hook to update debuff visuals
		hooksecurefunc("TargetFrame_UpdateDebuffAnchor", function(self, buff, index)
			local _, _, _, _, _, _, caster = UnitDebuff("target", index)
			if caster ~= "player" then
				buff.Icon:SetDesaturated(true) -- Desaturate icon for non-player debuffs
			else
				buff.Icon:SetDesaturated(false) -- Keep icon normal for player's own debuffs
			end
		end)
	else
		-- Restore default debuff filtering
		SetCVar("noBuffDebuffFilterOnTarget", 0)
	end
end

-- Event handler for player login
function Module:PLAYER_LOGIN()
	if IsAddOnLoaded("BetterBlizzFrames") then
		return -- Skip if BetterBlizzFrames addon is loaded
	end

	UpdateDebuffDesaturate()
end
