local NexEnhance, NE_Unitframes = ...

local UnitIsFriend = UnitIsFriend
local UnitIsEnemy = UnitIsEnemy
local UnitIsPlayer = UnitIsPlayer
local UnitClass = UnitClass

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

local function getUnitColor(unit)
	if UnitIsPlayer(unit) then
		local color = RAID_CLASS_COLORS[select(2, UnitClass(unit))]
		if color then
			return { r = color.r, g = color.g, b = color.b }
		end
	elseif colorPetAfterOwner and UnitIsUnit(unit, "pet") then
		-- Check if the unit is the player's pet and the setting is enabled
		local _, playerClass = UnitClass("player")
		local color = RAID_CLASS_COLORS[playerClass]
		if color then
			return { r = color.r, g = color.g, b = color.b }
		end
	else
		local reaction = getUnitReaction(unit)

		if reaction == "HOSTILE" then
			return { r = 1, g = 0, b = 0 }
		elseif reaction == "NEUTRAL" then
			return { r = 1, g = 1, b = 0 }
		else -- if reaction is "FRIENDLY"
			return { r = 0, g = 1, b = 0 }
		end
	end
end

local function updateFrameColorToggleVer(frame, unit)
	if NE_Unitframes.db.profile.unitframes.classColorHealth then
		local color = getUnitColor(unit)
		if color then
			frame:SetStatusBarDesaturated(true)
			frame:SetStatusBarColor(color.r, color.g, color.b)
		end
	end
end

local function resetFrameColor(frame, unit)
	frame:SetStatusBarDesaturated(false)
	frame:SetStatusBarColor(0, 1, 0)
end

local function UpdateHealthColor(frame, unit)
	local color = getUnitColor(unit)
	if color then
		frame:SetStatusBarDesaturated(true)
		frame:SetStatusBarColor(color.r, color.g, color.b)
	end
end

function NE_Unitframes:UpdateToTColor()
	updateFrameColorToggleVer(TargetFrameToT.HealthBar, "targettarget")
end

function NE_Unitframes:UpdateFrames()
	if NE_Unitframes.db.profile.unitframes.classColorHealth then
		NE_Unitframes:HookHealthbarColors()
		if UnitExists("player") then
			updateFrameColorToggleVer(PlayerFrame.healthbar, "player")
		end
		if UnitExists("target") then
			updateFrameColorToggleVer(TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBar, "target")
		end
		if UnitExists("focus") then
			updateFrameColorToggleVer(FocusFrame.TargetFrameContent.TargetFrameContentMain.HealthBar, "focus")
		end
		if UnitExists("targettarget") then
			updateFrameColorToggleVer(TargetFrameToT.HealthBar, "targettarget")
		end
		if UnitExists("focustarget") then
			updateFrameColorToggleVer(FocusFrameToT.HealthBar, "focustarget")
		end
		if UnitExists("party1") then
			updateFrameColorToggleVer(PartyFrame.MemberFrame1.HealthBar, "party1")
		end
		if UnitExists("party2") then
			updateFrameColorToggleVer(PartyFrame.MemberFrame2.HealthBar, "party2")
		end
		if UnitExists("party3") then
			updateFrameColorToggleVer(PartyFrame.MemberFrame3.HealthBar, "party3")
		end
		if UnitExists("party4") then
			updateFrameColorToggleVer(PartyFrame.MemberFrame4.HealthBar, "party4")
		end
	else
		if UnitExists("player") then
			resetFrameColor(PlayerFrame.healthbar, "player")
		end
		if UnitExists("target") then
			resetFrameColor(TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBar, "target")
		end
		if UnitExists("focus") then
			resetFrameColor(FocusFrame.TargetFrameContent.TargetFrameContentMain.HealthBar, "focus")
		end
		if UnitExists("targettarget") then
			resetFrameColor(TargetFrameToT.HealthBar, "targettarget")
		end
		if UnitExists("focustarget") then
			resetFrameColor(FocusFrameToT.HealthBar, "focustarget")
		end
		if UnitExists("party1") then
			resetFrameColor(PartyFrame.MemberFrame1.HealthBar, "party1")
		end
		if UnitExists("party2") then
			resetFrameColor(PartyFrame.MemberFrame2.HealthBar, "party2")
		end
		if UnitExists("party3") then
			resetFrameColor(PartyFrame.MemberFrame3.HealthBar, "party3")
		end
		if UnitExists("party4") then
			resetFrameColor(PartyFrame.MemberFrame4.HealthBar, "party4")
		end
	end

	if colorPetAfterOwner then
		if UnitExists("pet") then
			updateFrameColorToggleVer(PetFrame.healthbar, "pet")
		end
	end
end

function NE_Unitframes:UpdateFrameColor(frame, unit)
	local color = getUnitColor(unit)
	if color then
		frame:SetStatusBarDesaturated(true)
		frame:SetStatusBarColor(color.r, color.g, color.b)
	end
end

function NE_Unitframes:ClassColorReputation(frame, unit)
	local color = getUnitColor(unit)
	if color then
		frame:SetDesaturated(true)
		frame:SetVertexColor(color.r, color.g, color.b)
	end
end

function NE_Unitframes:ResetClassColorReputation(frame, unit)
	local color = getUnitColor(unit)
	if color then
		frame:SetDesaturated(false)
		frame:SetVertexColor(UnitSelectionColor(unit))
	end
end

function NE_Unitframes:HookHealthbarColors()
	if not healthbarsHooked and NE_Unitframes.db.profile.unitframes.classColorHealth then
		hooksecurefunc("UnitFrameHealthBar_Update", function(self, unit)
			if unit then
				UpdateHealthColor(self, unit)
				UpdateHealthColor(TargetFrameToT.HealthBar, "targettarget")
				UpdateHealthColor(FocusFrameToT.HealthBar, "focustarget")
			end
		end)
		healthbarsHooked = true
	end
end

function NE_Unitframes:PLAYER_LOGIN()
	if NE_Unitframes.db.profile.unitframes.classColorHealth then
		local function UpdateCVar()
			if not InCombatLockdown() then
				if classColorFrames then
					SetCVar("raidFramesDisplayClassColor", 1)
				end
			else
				C_Timer.After(2, function()
					UpdateCVar()
				end)
			end
		end
		UpdateCVar()
		NE_Unitframes:UpdateFrames()
	end
end
