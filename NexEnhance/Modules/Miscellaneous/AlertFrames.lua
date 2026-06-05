--[[
	NexEnhance - Alert Frames
	-------------------------------------------------------------------------
	Re-anchors Blizzard's alert popups (achievements, loot rolls, world quest
	rewards, etc.) to a single fixed point near the top of the screen and makes
	the group-loot roll bars stack cleanly with them. Optionally suppresses the
	Talking Head frame.

	Ported from NDui's Modules/Misc/AlertFrames.lua (by siweia), adapted to the
	NexEnhance framework. The anchor is registered with Edit Mode (LibEditMode)
	so it can be dragged. All re-anchoring is done with hooksecurefunc, so it is
	taint-safe.
--]]

-- luacheck: globals GroupLootContainer
---@diagnostic disable: undefined-field
local _, ns = ...
local F, L = ns.F, ns.L

local _G = _G
local select = select
local tremove = table.remove
local hooksecurefunc = hooksecurefunc
local CreateFrame = CreateFrame
local UIParent = UIParent
local AlertFrame = AlertFrame
local GroupLootContainer = GroupLootContainer

ns:RegisterDefaults({
	alertFrames = {
		enable = true,
		hideTalkingHead = false,
	},
})

local AlertFrames = ns:NewModule("AlertFrames", "alertFrames", { group = "misc", title = L["Alert Frames"], order = 30 })

-- Current stacking direction; flipped by AlertFrame_UpdateAnchor depending on
-- whether the anchor sits in the top or bottom half of the screen.
local POSITION, ANCHOR_POINT, YOFFSET = "TOP", "BOTTOM", -10
local parentFrame

-- ---------------------------------------------------------------------------
-- Anchor maths (ported 1:1 from NDui; `self` is the alert subsystem/frame)
-- ---------------------------------------------------------------------------
local function AlertFrame_SetPoint(self, relativeAlert)
	self:ClearAllPoints()
	self:SetPoint(POSITION, relativeAlert, ANCHOR_POINT, 0, YOFFSET)
end

local function AlertFrame_AdjustQueuedAnchors(self, relativeAlert)
	for alertFrame in self.alertFramePool:EnumerateActive() do
		AlertFrame_SetPoint(alertFrame, relativeAlert)
		relativeAlert = alertFrame
	end
	return relativeAlert
end

local function AlertFrame_AdjustAnchors(self, relativeAlert)
	if self.alertFrame:IsShown() then
		AlertFrame_SetPoint(self.alertFrame, relativeAlert)
		return self.alertFrame
	end
	return relativeAlert
end

local function AlertFrame_AdjustAnchorsNonAlert(self, relativeAlert)
	if self.anchorFrame:IsShown() then
		AlertFrame_SetPoint(self.anchorFrame, relativeAlert)
		return self.anchorFrame
	end
	return relativeAlert
end

local function AlertFrame_AdjustPosition(self)
	if self.alertFramePool then
		self.AdjustAnchors = AlertFrame_AdjustQueuedAnchors
	elseif not self.anchorFrame then
		self.AdjustAnchors = AlertFrame_AdjustAnchors
	elseif self.anchorFrame then
		self.AdjustAnchors = AlertFrame_AdjustAnchorsNonAlert
	end
end

local function AlertFrame_UpdateAnchor(self)
	local y = select(2, parentFrame:GetCenter())
	local screenHeight = UIParent:GetTop()
	if y and screenHeight and y > screenHeight / 2 then
		POSITION, ANCHOR_POINT, YOFFSET = "TOP", "BOTTOM", -10
	else
		POSITION, ANCHOR_POINT, YOFFSET = "BOTTOM", "TOP", 10
	end

	self:ClearAllPoints()
	self:SetPoint(POSITION, parentFrame)
	GroupLootContainer:ClearAllPoints()
	GroupLootContainer:SetPoint(POSITION, parentFrame)
end

local function UpdateGroupLootContainer(self)
	local lastIdx
	for i = 1, self.maxIndex do
		local frame = self.rollFrames[i]
		if frame then
			frame:ClearAllPoints()
			frame:SetPoint("CENTER", self, POSITION, 0, self.reservedSize * (i - 1 + 0.5) * YOFFSET / 10)
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

-- ---------------------------------------------------------------------------
-- Talking Head
-- ---------------------------------------------------------------------------
local talkingHeadHidden
local function NoTalkingHeads()
	if not ns.db.alertFrames.hideTalkingHead then return end
	local frame = _G.TalkingHeadFrame
	if not frame or talkingHeadHidden then return end

	talkingHeadHidden = true
	frame:UnregisterAllEvents()
	hooksecurefunc(frame, "Show", function(self)
		self:Hide()
	end)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function AlertFrames:ADDON_LOADED(addon)
	if addon == "Blizzard_TalkingHeadUI" then
		NoTalkingHeads()
	end
end

function AlertFrames:OnEnable()
	if not ns.db.alertFrames.enable then return end

	parentFrame = CreateFrame("Frame", nil, UIParent)
	parentFrame:SetSize(200, 30)
	-- Top-centre by default; draggable in Edit Mode.
	F.CreateMover(parentFrame, "alertFrames", L["Alert Frames"], "TOP", 0, -40)

	GroupLootContainer:EnableMouse(false)
	GroupLootContainer.ignoreFramePositionManager = true

	-- Iterate backwards: we tremove the Talking Head subsystem mid-loop, and a
	-- forward ipairs would shift indices down and skip the next subsystem.
	for index = #AlertFrame.alertFrameSubSystems, 1, -1 do
		local subSystem = AlertFrame.alertFrameSubSystems[index]
		if subSystem.anchorFrame and subSystem.anchorFrame == _G.TalkingHeadFrame then
			tremove(AlertFrame.alertFrameSubSystems, index)
		else
			AlertFrame_AdjustPosition(subSystem)
		end
	end

	hooksecurefunc(AlertFrame, "AddAlertFrameSubSystem", function(_, subSystem)
		AlertFrame_AdjustPosition(subSystem)
	end)

	hooksecurefunc(AlertFrame, "UpdateAnchors", AlertFrame_UpdateAnchor)
	hooksecurefunc("GroupLootContainer_Update", UpdateGroupLootContainer)

	NoTalkingHeads()
	self:RegisterEvent("ADDON_LOADED")
end

function AlertFrames:OnSettingChanged()
	-- Enabling the hide can apply live; turning it back off needs a reload.
	NoTalkingHeads()
end

function AlertFrames:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Alert Frames"], L["Move achievement/loot/reward alert popups to the top of the screen (reload to disable)."])
	local _, headInit = builder:Checkbox(category, self, "hideTalkingHead", L["Hide Talking Head"], L["Suppress the Talking Head dialog frame (reload to re-enable it)."])

	builder:DependsOn(headInit, enableInit)
end
