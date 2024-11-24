local _, Module = ...

local _G = _G
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc

local POSITION, ANCHOR_POINT, Y_OFFSET, BASE_YOFFSET = "TOP", "BOTTOM", -5, 0
local AlertFrameHolder

function Module:PostAlertMove()
	local AlertFrame = _G.AlertFrame

	-- Support for the Trading Post
	local perks = _G.PerksProgramFrame
	local perksFooter = perks and perks.FooterFrame
	local perksAnchor = (perksFooter and AlertFrame.baseAnchorFrame == perksFooter.RotateButtonContainer) and perksFooter

	local growUp = perksAnchor
	if not growUp then
		if not AlertFrameHolder:IsShown() then
			AlertFrameHolder:Show()
			AlertFrameHolder:SetPoint("TOP", UIParent, "TOP", 0, -20)
		end

		local _, y = AlertFrameHolder:GetCenter()
		if not y then
			y = UIParent:GetTop() / 2
		end
		growUp = y < (UIParent:GetTop() * 0.5)
	end

	if growUp then
		POSITION, ANCHOR_POINT, Y_OFFSET, BASE_YOFFSET = "BOTTOM", "TOP", 5, perksAnchor and 40 or 0
	else
		POSITION, ANCHOR_POINT, Y_OFFSET, BASE_YOFFSET = "TOP", "BOTTOM", -5, 0
	end

	local anchor = perksAnchor or AlertFrameHolder
	AlertFrame:ClearAllPoints()
	AlertFrame:SetAllPoints(anchor)
end

function Module:AdjustQueuedAnchors(relativeAlert)
	local base = BASE_YOFFSET
	for alert in self.alertFramePool:EnumerateActive() do
		alert:ClearAllPoints()
		alert:SetPoint(POSITION, relativeAlert, ANCHOR_POINT, 0, base + Y_OFFSET)

		relativeAlert = alert
		if base ~= 0 then
			base = 0
		end
	end
	return relativeAlert
end

function Module:AdjustAnchors(relativeAlert)
	local alert = self.alertFrame
	if alert:IsShown() then
		alert:ClearAllPoints()
		alert:SetPoint(POSITION, relativeAlert, ANCHOR_POINT, 0, Y_OFFSET)
		return alert
	end
	return relativeAlert
end

function Module:AdjustAnchorsNonAlert(relativeAnchor)
	local anchor = self.anchorFrame
	if anchor:IsShown() then
		anchor:ClearAllPoints()
		anchor:SetPoint(POSITION, relativeAnchor, ANCHOR_POINT, 0, Y_OFFSET)
		return anchor
	end
	return relativeAnchor
end

local function AlertSubSystem_AdjustPosition(alertFrameSubSystem)
	if alertFrameSubSystem.alertFramePool then
		alertFrameSubSystem.AdjustAnchors = Module.AdjustQueuedAnchors
	elseif not alertFrameSubSystem.anchorFrame then
		alertFrameSubSystem.AdjustAnchors = Module.AdjustAnchors
	elseif alertFrameSubSystem.anchorFrame then
		alertFrameSubSystem.AdjustAnchors = Module.AdjustAnchorsNonAlert
	end
end

function Module:PLAYER_LOGIN()
	AlertFrameHolder = CreateFrame("Frame", "AlertFrameHolder", UIParent)
	AlertFrameHolder:SetSize(200, 30)
	AlertFrameHolder:SetPoint("TOP", UIParent, "TOP", 0, -20)

	-- Adjust subsystems
	for _, alertFrameSubSystem in ipairs(_G.AlertFrame.alertFrameSubSystems) do
		AlertSubSystem_AdjustPosition(alertFrameSubSystem)
	end

	hooksecurefunc(_G.AlertFrame, "AddAlertFrameSubSystem", function(_, alertFrameSubSystem)
		AlertSubSystem_AdjustPosition(alertFrameSubSystem)
	end)

	hooksecurefunc(_G.AlertFrame, "SetBaseAnchorFrame", Module.PostAlertMove)
	hooksecurefunc(_G.AlertFrame, "ResetBaseAnchorFrame", Module.PostAlertMove)
	hooksecurefunc(_G.AlertFrame, "UpdateAnchors", Module.PostAlertMove)
end
