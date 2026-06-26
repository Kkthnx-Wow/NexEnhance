--[[
	NexEnhance - Hide DPS Role Icon
	-------------------------------------------------------------------------
	Hides the DPS (sword/DAMAGER) role icon from party and raid compact unit
	frames. Tank and healer icons remain visible — they carry actionable
	information (where to stand, who to keep alive). The DPS icon is noise:
	everyone who isn't a tank or healer is already understood to be DPS.

	Implementation:
	  `CompactUnitFrame_UpdateRoleIcon(frame)` is the shared function Blizzard
	  calls for both party and raid compact frames whenever role information
	  changes. Confirmed in:
	    Blizzard_UnitFrame/Shared/CompactUnitFrame.lua:1387 (12.0.7)
	  It sets frame.roleIcon:SetAtlas(...) then :Show(). We hook it and hide
	  the icon immediately after when the role is DAMAGER and the unit is not
	  in a vehicle (vehicle icons are shown by the same function and should
	  stay visible).

	  `UnitGroupRolesAssigned(unit)` returns "TANK", "HEALER", "DAMAGER",
	  or "NONE". Confirmed in GlobalAPI.lua (12.0.7).

	Default: OFF (opt-in).
--]]

local _, ns = ...
local L = ns.L

ns:RegisterDefaults({
	hideDpsRole = {
		enable = false,
	},
})

local HideDpsRole = ns:NewModule("HideDpsRole", "hideDpsRole", {
	group = "unitframes",
	title = L["Hide DPS Role Icon"],
	order = 50,
})

local hooked = false

local function OnCompactUnitFrame_UpdateRoleIcon(frame)
	if not ns.db or not ns.db.hideDpsRole.enable then
		return
	end
	if not frame or not frame.roleIcon then
		return
	end
	if not frame.roleIcon:IsShown() then
		return
	end
	if not frame.unit then
		return
	end

	-- Leave vehicle icons alone — they're shown by the same code path.
	if UnitInVehicle and UnitHasVehicleUI and UnitInVehicle(frame.unit) and UnitHasVehicleUI(frame.unit) then
		return
	end

	local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(frame.unit)
	if role == "DAMAGER" then
		frame.roleIcon:Hide()
		-- Restore Blizzard's expected hidden dimensions: width = 1, height stays.
		-- Blizzard does this itself when hiding the icon so anchored elements
		-- (like the name text) don't get pushed aside by a full-width invisible icon.
		local h = frame.roleIcon:GetHeight()
		if h and h > 0 then
			frame.roleIcon:SetSize(1, h)
		end
	end
end

local function Install()
	if hooked then
		return
	end
	if not _G.CompactUnitFrame_UpdateRoleIcon then
		return
	end
	hooksecurefunc("CompactUnitFrame_UpdateRoleIcon", OnCompactUnitFrame_UpdateRoleIcon)
	hooked = true
end

-- Force a refresh of all visible compact unit frames so the change takes
-- effect immediately without waiting for the next role-update event.
local function RefreshAllFrames()
	if not _G.CompactUnitFrame_UpdateRoleIcon then
		return
	end
	-- Compact party frames: party1..party4 + partypet1..4
	for i = 1, 4 do
		local f = _G["CompactPartyFrameMember" .. i]
		if f and f.unit then
			_G.CompactUnitFrame_UpdateRoleIcon(f)
		end
		local p = _G["CompactPartyFramePet" .. i]
		if p and p.unit then
			_G.CompactUnitFrame_UpdateRoleIcon(p)
		end
	end
	-- Compact raid frames: raid1..raid40
	for i = 1, 40 do
		local f = _G["CompactRaidFrame" .. i]
		if f and f.unit then
			_G.CompactUnitFrame_UpdateRoleIcon(f)
		end
	end
end

function HideDpsRole:OnEnable()
	Install()
	if ns.db.hideDpsRole.enable then
		RefreshAllFrames()
	end
end

function HideDpsRole:OnSettingChanged(key, value)
	if key ~= "enable" then
		return
	end
	if value then
		Install()
	end
	-- Refresh so icons appear/disappear immediately on toggle.
	C_Timer.After(0, RefreshAllFrames)
end

function HideDpsRole:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Hide DPS Role Icon"], L["Hide the DPS (sword) role icon from party and raid frames. Tank and healer icons remain visible."])
end
