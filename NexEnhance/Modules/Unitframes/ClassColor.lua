local _, Module = ...

local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitIsEnemy = UnitIsEnemy
local UnitIsFriend = UnitIsFriend
local UnitIsPlayer = UnitIsPlayer
local hooksecurefunc = hooksecurefunc
local select = select

local healthbarsHooked = nil
local classColorsOn

local OnSetVertexColorHookScript = function(r, g, b, a)
	return function(frame, _, _, _, _, flag)
		if flag ~= "NexHookSetVertexColor" then
			frame:SetVertexColor(r, g, b, a, "NexHookSetVertexColor")
		end
	end
end

function Module.SetVertexColor(frame, r, g, b, a)
	frame:SetVertexColor(r, g, b, a, "NexHookSetVertexColor")

	if not frame.NexHookSetVertexColor then
		hooksecurefunc(frame, "SetVertexColor", OnSetVertexColorHookScript(r, g, b, a))
		frame.NexHookSetVertexColor = true
	end
end

local function getUnitReaction(unit)
	if UnitIsFriend("player", unit) then
		return "FRIENDLY"
	elseif UnitIsEnemy("player", unit) then
		return "HOSTILE"
	else
		return "NEUTRAL"
	end
end

local function getUnitColor(unit)
	if UnitIsPlayer(unit) then
		local color = RAID_CLASS_COLORS[select(2, UnitClass(unit))]
		if color then
			return { r = color.r, g = color.g, b = color.b }, false
		end
	else
		local reaction = getUnitReaction(unit)

		if reaction == "HOSTILE" then
			return { r = 1, g = 0, b = 0 }, false
		elseif reaction == "NEUTRAL" then
			return { r = 1, g = 1, b = 0 }, false
		elseif reaction == "FRIENDLY" then
			return { r = 0, g = 1, b = 0 }, true
		end
	end
end

local function updateFrameColorToggleVer(frame, unit)
	if not frame then
		return
	end
	if not frame.SetStatusBarDesaturated then
		return
	end
	if classColorsOn then
		local color, isFriendly = getUnitColor(unit)
		if color then
			if isFriendly then
				frame:SetStatusBarDesaturated(false)
				frame:SetStatusBarColor(1, 1, 1)
			else
				frame:SetStatusBarDesaturated(true)
				frame:SetStatusBarColor(color.r, color.g, color.b)
			end
		end
	end
end

local function resetFrameColor(frame, unit)
	frame:SetStatusBarDesaturated(false)
	frame:SetStatusBarColor(1, 1, 1)
end

local validUnits = {
	player = true,
	target = true,
	targettarget = true,
	focus = true,
	focustarget = true,
	pet = true,
	party1 = true,
	party2 = true,
	party3 = true,
	party4 = true,
}

local function UpdateHealthColor(frame, unit)
	if not validUnits[unit] then
		return
	end
	local color, isFriendly = getUnitColor(unit)
	if color then
		if isFriendly then
			frame:SetStatusBarDesaturated(false)
			frame:SetStatusBarColor(1, 1, 1)
		else
			frame:SetStatusBarDesaturated(true)
			frame:SetStatusBarColor(color.r, color.g, color.b)
		end
	end
end

local function UpdateHealthColorCF(frame, unit)
	local color = getUnitColor(unit)
	if color then
		frame:SetStatusBarColor(color.r, color.g, color.b)
	end
end

function Module.UpdateToTColor()
	updateFrameColorToggleVer(TargetFrameToT.HealthBar, "targettarget")
end

function Module.UpdateFrames()
	classColorsOn = Module.db.profile.unitframes.classColorHealth
	if classColorsOn then
		Module.HookHealthbarColors()
		if UnitExists("player") then
			updateFrameColorToggleVer(PlayerFrame.healthbar, "player")
		end
		if UnitExists("target") then
			updateFrameColorToggleVer(TargetFrame.healthbar, "target")
		end
		if UnitExists("focus") then
			updateFrameColorToggleVer(FocusFrame.healthbar, "focus")
		end
		if UnitExists("targettarget") then
			updateFrameColorToggleVer(TargetFrameToT.HealthBar, "targettarget")
		end
		if UnitExists("focustarget") then
			updateFrameColorToggleVer(FocusFrameToT.HealthBar, "focustarget")
		end
		if UnitExists("party1") then
			updateFrameColorToggleVer(PartyFrame.MemberFrame1.HealthBarContainer.HealthBar, "party1")
		end
		if UnitExists("party2") then
			updateFrameColorToggleVer(PartyFrame.MemberFrame2.HealthBarContainer.HealthBar, "party2")
		end
		if UnitExists("party3") then
			updateFrameColorToggleVer(PartyFrame.MemberFrame3.HealthBarContainer.HealthBar, "party3")
		end
		if UnitExists("party4") then
			updateFrameColorToggleVer(PartyFrame.MemberFrame4.HealthBarContainer.HealthBar, "party4")
		end
	else
		if UnitExists("player") then
			resetFrameColor(PlayerFrame.healthbar, "player")
		end
		if UnitExists("target") then
			resetFrameColor(TargetFrame.healthbar, "target")
		end
		if UnitExists("focus") then
			resetFrameColor(FocusFrame.healthbar, "focus")
		end
		if UnitExists("targettarget") then
			resetFrameColor(TargetFrameToT.HealthBar, "targettarget")
		end
		if UnitExists("focustarget") then
			resetFrameColor(FocusFrameToT.HealthBar, "focustarget")
		end
		if UnitExists("party1") then
			resetFrameColor(PartyFrame.MemberFrame1.HealthBarContainer.HealthBar, "party1")
		end
		if UnitExists("party2") then
			resetFrameColor(PartyFrame.MemberFrame2.HealthBarContainer.HealthBar, "party2")
		end
		if UnitExists("party3") then
			resetFrameColor(PartyFrame.MemberFrame3.HealthBarContainer.HealthBar, "party3")
		end
		if UnitExists("party4") then
			resetFrameColor(PartyFrame.MemberFrame4.HealthBarContainer.HealthBar, "party4")
		end
	end
end

function Module.UpdateFrameColor(frame, unit)
	local color = getUnitColor(unit)
	if color then
		if color == "FRIENDLY" then
			frame:SetStatusBarDesaturated(false)
			frame:SetStatusBarColor(1, 1, 1)
		else
			frame:SetStatusBarDesaturated(true)
			frame:SetStatusBarColor(color.r, color.g, color.b)
		end
	end
end

function Module.ClassColorReputation(frame, unit)
	local color = getUnitColor(unit)
	if color then
		frame:SetDesaturated(true)
		frame:SetVertexColor(color.r, color.g, color.b)
	end
end

function Module.ResetClassColorReputation(frame, unit)
	local color = getUnitColor(unit)
	if color then
		frame:SetDesaturated(false)
		frame:SetVertexColor(UnitSelectionColor(unit))
	end
end

function Module.HookHealthbarColors()
	if not healthbarsHooked and classColorsOn then
		local function HookCfSetStatusBarColor(frame, unit)
			if not frame.SetStatusBarColorHooked then
				hooksecurefunc(frame, "SetStatusBarColor", function()
					if not frame.recoloring then
						frame.recoloring = true
						local color = getUnitColor(unit)
						if color then
							frame:SetStatusBarColor(color.r, color.g, color.b)
						end
						frame.recoloring = false
					end
				end)
				local color = getUnitColor(unit)
				if color then
					frame:SetStatusBarColor(color.r, color.g, color.b)
				end
				frame.SetStatusBarColorHooked = true
			end
		end

		if C_AddOns.IsAddOnLoaded("ClassicFrames") then
			hooksecurefunc("UnitFrameHealthBar_Update", function(self, unit)
				if unit then
					UpdateHealthColorCF(TargetFrameToT.HealthBar, "targettarget")
					UpdateHealthColorCF(FocusFrameToT.HealthBar, "focustarget")
				end
			end)
			if CfPlayerFrameHealthBar then
				HookCfSetStatusBarColor(CfPlayerFrameHealthBar, "player")
				HookCfSetStatusBarColor(CfTargetFrameHealthBar, "target")
				HookCfSetStatusBarColor(CfFocusFrameHealthBar, "focus")
			else
				print("ClassicFrames healthbars not detected. Please report to dev @bodify")
			end
		else
			hooksecurefunc("UnitFrameHealthBar_Update", function(self, unit)
				if unit then
					UpdateHealthColor(self, unit)
					UpdateHealthColor(TargetFrameToT.HealthBar, "targettarget")
					UpdateHealthColor(FocusFrameToT.HealthBar, "focustarget")
				end
			end)
		end

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
	Module.UpdateFrames()
	Module.PlayerReputationColor()
	Module.TargetReputationColor()
end
