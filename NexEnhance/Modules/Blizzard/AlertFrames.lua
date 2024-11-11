local _, Module = ...

local ipairs, tremove = ipairs, table.remove
local UIParent = UIParent
local AlertFrame = AlertFrame
local GroupLootContainer = GroupLootContainer

local POSITION, ANCHOR_POINT, YOFFSET = "TOP", "BOTTOM", -6
local parentFrame

function Module:AlertFrame_UpdateAnchor()
	-- support for the Trading Post
	local perks = _G.PerksProgramFrame
	local perksFooter = perks and perks.FooterFrame
	local perksAnchor = (perksFooter and AlertFrame.baseAnchorFrame == perksFooter.RotateButtonContainer) and perksFooter

	if perksAnchor then
		parentFrame = perksAnchor -- Use the Trading Post footer as the anchor
	else
		local y = select(2, parentFrame:GetCenter())
		local screenHeight = UIParent:GetTop()
		if y > screenHeight / 2 then
			POSITION = "TOP"
			ANCHOR_POINT = "BOTTOM"
			YOFFSET = -6
		else
			POSITION = "BOTTOM"
			ANCHOR_POINT = "TOP"
			YOFFSET = 6
		end
	end

	self:ClearAllPoints()
	self:SetPoint(POSITION, parentFrame, ANCHOR_POINT, 0, YOFFSET) -- Anchor to the chosen parent frame
	GroupLootContainer:ClearAllPoints()
	GroupLootContainer:SetPoint(POSITION, parentFrame, ANCHOR_POINT, 0, YOFFSET) -- Anchor to the chosen parent frame
end

function Module:UpdatGroupLootContainer()
	local lastIdx = nil

	for i = 1, self.maxIndex do
		local frame = self.rollFrames[i]
		if frame then
			frame:ClearAllPoints()
			frame:SetPoint("CENTER", self, POSITION, 0, self.reservedSize * (i - 1 + 0.5) * YOFFSET / 6)
			lastIdx = i
		end
	end

	if lastIdx then
		self:SetHeight(self.reservedSize * lastIdx)
		self:Show()
	else
		self:Hide()
	end
end

function Module:AlertFrame_SetPoint(relativeAlert)
	self:ClearAllPoints()
	self:SetPoint(POSITION, relativeAlert, ANCHOR_POINT, 0, YOFFSET)
end

function Module:AlertFrame_AdjustQueuedAnchors(relativeAlert)
	for alertFrame in self.alertFramePool:EnumerateActive() do
		Module.AlertFrame_SetPoint(alertFrame, relativeAlert)
		relativeAlert = alertFrame
	end

	return relativeAlert
end

function Module:AlertFrame_AdjustAnchors(relativeAlert)
	if self.alertFrame:IsShown() then
		Module.AlertFrame_SetPoint(self.alertFrame, relativeAlert)
		return self.alertFrame
	end

	return relativeAlert
end

function Module:AlertFrame_AdjustAnchorsNonAlert(relativeAlert)
	if self.anchorFrame:IsShown() then
		Module.AlertFrame_SetPoint(self.anchorFrame, relativeAlert)
		return self.anchorFrame
	end

	return relativeAlert
end

function Module:AlertFrame_AdjustPosition()
	if self.alertFramePool then
		self.AdjustAnchors = Module.AlertFrame_AdjustQueuedAnchors
	elseif not self.anchorFrame then
		self.AdjustAnchors = Module.AlertFrame_AdjustAnchors
	elseif self.anchorFrame then
		self.AdjustAnchors = Module.AlertFrame_AdjustAnchorsNonAlert
	end
end

function Module:PLAYER_LOGIN()
	parentFrame = CreateFrame("Frame", nil, UIParent)
	parentFrame:SetSize(200, 30)
	parentFrame:SetPoint("TOP", UIParent, 0, -40)

	GroupLootContainer:EnableMouse(false)
	GroupLootContainer.ignoreFramePositionManager = true

	for index, alertFrameSubSystem in ipairs(AlertFrame.alertFrameSubSystems) do
		if alertFrameSubSystem.anchorFrame and alertFrameSubSystem.anchorFrame == _G.TalkingHeadFrame then
			tremove(_G.AlertFrame.alertFrameSubSystems, index)
		else
			Module.AlertFrame_AdjustPosition(alertFrameSubSystem)
		end
	end

	hooksecurefunc(AlertFrame, "AddAlertFrameSubSystem", function(_, alertFrameSubSystem)
		Module.AlertFrame_AdjustPosition(alertFrameSubSystem)
	end)

	hooksecurefunc(_G.AlertFrame, "SetBaseAnchorFrame", Module.AlertFrame_UpdateAnchor)
	hooksecurefunc(_G.AlertFrame, "ResetBaseAnchorFrame", Module.AlertFrame_UpdateAnchor)

	hooksecurefunc(AlertFrame, "UpdateAnchors", Module.AlertFrame_UpdateAnchor)
	hooksecurefunc("GroupLootContainer_Update", Module.UpdatGroupLootContainer)
end
