local NexEnhance, NE_Range = ...

function NE_Range:RangeUpdate(hasrange, inrange)
	local Icon = self.icon
	local ID = self.action

	if not ID then
		return
	end

	local IsUsable, NotEnoughPower = IsUsableAction(ID)
	local HasRange = hasrange
	local InRange = inrange

	if IsUsable then
		if HasRange and InRange == false then
			Icon:SetVertexColor(0.8, 0.1, 0.1)
		else
			Icon:SetVertexColor(1.0, 1.0, 1.0)
		end
	elseif NotEnoughPower then
		Icon:SetVertexColor(0.1, 0.3, 1.0)
	else
		Icon:SetVertexColor(0.3, 0.3, 0.3)
	end
end

function NE_Range:PLAYER_LOGIN()
	if not NE_Range.db.profile.actionbars.range then
		return
	end

	hooksecurefunc("ActionButton_UpdateRangeIndicator", NE_Range.RangeUpdate)
end
