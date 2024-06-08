local _, Module = ...

local UnitIsFriend = UnitIsFriend
local UnitIsEnemy = UnitIsEnemy
local UnitIsPlayer = UnitIsPlayer
local UnitClass = UnitClass
local UnitExists = UnitExists
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local hooksecurefunc = hooksecurefunc
local select = select

local healthbarsHooked = nil

local function getUnitReaction(unit)
	if UnitIsFriend("player", unit) then
		return "FRIENDLY"
	elseif UnitIsEnemy("player", unit) then
		return "HOSTILE"
	else
		return "NEUTRAL"
	end
end

local colorTable = { r = 0, g = 0, b = 0 }

local function getUnitColor(unit)
	if UnitIsPlayer(unit) then
		local color = RAID_CLASS_COLORS[select(2, UnitClass(unit))]
		if color then
			colorTable.r, colorTable.g, colorTable.b = color.r, color.g, color.b
			return colorTable
		end
	else
		local reaction = getUnitReaction(unit)

		if reaction == "HOSTILE" then
			colorTable.r, colorTable.g, colorTable.b = 1, 0, 0
		elseif reaction == "NEUTRAL" then
			colorTable.r, colorTable.g, colorTable.b = 1, 1, 0
		else -- if reaction is "FRIENDLY"
			colorTable.r, colorTable.g, colorTable.b = 0, 1, 0
		end
		return colorTable
	end
end

local function setStatusBarColor(frame, color)
	if color then
		frame:SetStatusBarDesaturated(true)
		frame:SetStatusBarColor(color.r, color.g, color.b)
	end
end

local function resetFrameColor(frame)
	frame:SetStatusBarDesaturated(false)
	frame:SetStatusBarColor(0, 1, 0)
end

function Module.UpdateToTColor()
	local color = getUnitColor("targettarget")
	setStatusBarColor(TargetFrameToT.HealthBar, color)
end

local function updateFrameColorByUnit(unit, frame)
	if UnitExists(unit) then
		local color = getUnitColor(unit)
		setStatusBarColor(frame, color)
	end
end

function Module.UpdateFrames()
	local frames = {
		["player"] = PlayerFrame.healthbar,
		["target"] = TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBar,
		["focus"] = FocusFrame.TargetFrameContent.TargetFrameContentMain.HealthBar,
		["targettarget"] = TargetFrameToT.HealthBar,
		["focustarget"] = FocusFrameToT.HealthBar,
		["party1"] = PartyFrame.MemberFrame1.HealthBar,
		["party2"] = PartyFrame.MemberFrame2.HealthBar,
		["party3"] = PartyFrame.MemberFrame3.HealthBar,
		["party4"] = PartyFrame.MemberFrame4.HealthBar,
	}

	if Module.db.profile.unitframes.classColorHealth then
		Module.HookHealthbarColors()
		for unit, frame in pairs(frames) do
			updateFrameColorByUnit(unit, frame)
		end
	else
		for unit, frame in pairs(frames) do
			if UnitExists(unit) then
				resetFrameColor(frame)
			end
		end
	end
end

function Module.HookHealthbarColors()
	if not healthbarsHooked and Module.db.profile.unitframes.classColorHealth then
		hooksecurefunc("UnitFrameHealthBar_Update", function(self, unit)
			if unit then
				local color = getUnitColor(unit)
				setStatusBarColor(self, color)
				Module.UpdateToTColor()
			end
		end)
		healthbarsHooked = true
	end
end

function Module.PlayerReputationColor()
	local frame = PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
	if frame.ReputationColor then
		frame.ReputationColor:Hide()
	end
end

function Module.TargetReputationColor()
	local frame = TargetFrame.TargetFrameContent.TargetFrameContentMain
	if frame.ReputationColor then
		frame.ReputationColor:Hide()
	end
end

function Module:PLAYER_LOGIN()
	if IsAddOnLoaded("BetterBlizzFrames") then
		return
	end

	C_Timer.After(1, function()
		if Module.db.profile.unitframes.classColorHealth then
			Module.UpdateFrames()
			Module.PlayerReputationColor()
			Module.TargetReputationColor()
		end
	end)
end
