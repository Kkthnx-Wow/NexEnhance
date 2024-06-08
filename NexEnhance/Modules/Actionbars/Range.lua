local NexEnhance, NE_Range = ...

function NE_Range:UpdateRangeIndicator(checksRange, inRange)
	if not self.setHooksecurefunc and self.UpdateUsable then
		hooksecurefunc(self, "UpdateUsable", function(self, _, isUsable)
			if IsUsableAction(self.action) and ActionHasRange(self.action) and IsActionInRange(self.action) == false then
				self.icon:SetVertexColor(1, 0, 0)
			end
		end)
		self.setHooksecurefunc = true
	end

	if self.HotKey:GetText() == RANGE_INDICATOR then
		if checksRange then
			if inRange then
				if self.UpdateUsable then
					self:UpdateUsable()
				end
			else
				self.icon:SetVertexColor(1, 0, 0)
			end
		end
	else
		if checksRange and not inRange then
			self.icon:SetVertexColor(1, 0, 0)
		elseif self.UpdateUsable then
			self:UpdateUsable()
		end
	end
end

function NE_Range:PLAYER_LOGIN()
	if not NE_Range.db.profile.actionbars.range then
		return
	end

	hooksecurefunc("ActionButton_UpdateRangeIndicator", NE_Range.UpdateRangeIndicator)
end
