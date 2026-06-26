--[[
	NexEnhance - Auto PvP Release
	-------------------------------------------------------------------------
	Automatically releases your spirit when you die in a Battleground or PvP
	zone. Because let's face it: getting farmed at the graveyard is annoying,
	but staring at the greyed-out screen of despair while waiting to manually
	click "Release Spirit" is just wasting precious seconds you could spend
	actually fighting (or getting farmed again).

	We check for self-resurrection (Soulstones, Reincarnate, etc.) to ensure
	we don't rob you of a strategic self-rez. And we only do it in PvP zones
	so you don't release in the middle of a raid boss fight and walk back.

	Inspired by the auto-release logic in EnhanceQoL.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local F, L = ns.F, ns.L

local C_DeathInfo = C_DeathInfo
local C_Map = C_Map
local IsInInstance = IsInInstance
local RepopMe = RepopMe
local StaticPopup_Hide = StaticPopup_Hide
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local C_Timer_After = C_Timer.After

-- World maps that are actually outdoor PvP battle zones.
-- Wintergrasp and Tol Barad are notoriously buggy zones where Blizzard's
-- instance check occasionally acts like you're in the open world.
local PVP_WORLD_MAPS = {
	[123] = true, -- Wintergrasp
	[244] = true, -- Tol Barad (PvP)
	[588] = true, -- Ashran
	[622] = true, -- Stormshield
	[624] = true, -- Warspear
}

ns:RegisterDefaults({
	autoPvPRelease = {
		enable = false,
		delay = 0,
	},
})

local AutoPvPRelease = ns:NewModule("AutoPvPRelease", "autoPvPRelease", { group = "automation", title = L["Auto PvP Release"], order = 110 })

local function HasSelfResurrect()
	local deathInfo = C_DeathInfo
	local options = deathInfo and deathInfo.GetSelfResurrectOptions and deathInfo.GetSelfResurrectOptions()
	if not options then
		return false
	end
	for i = 1, #options do
		local option = options[i]
		if option and option.canUse then
			-- Shaman Reincarnate, Warlock Soulstone, or similar active options.
			return true
		end
	end
	return false
end

local function IsInPvPZone()
	local inInstance, instanceType = IsInInstance()
	if inInstance and instanceType == "pvp" then
		return true
	end
	local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	if mapID and PVP_WORLD_MAPS[mapID] then
		return true
	end
	return false
end

function AutoPvPRelease:PLAYER_DEAD()
	if not ns.db.autoPvPRelease.enable then
		return
	end

	-- Don't steal a player's deliberate decision to use their Soulstone or Reincarnate.
	if HasSelfResurrect() then
		return
	end

	-- Verify we are actually in a PvP BG or battle zone.
	if not IsInPvPZone() then
		return
	end

	local delay = ns.db.autoPvPRelease.delay or 0
	if delay <= 0 then
		RepopMe()
		StaticPopup_Hide("DEATH")
	else
		C_Timer_After(delay, function()
			-- Double-check everything after the delay in case they got rezzed
			-- or toggled the setting off mid-death.
			if not ns.db.autoPvPRelease.enable then
				return
			end
			if not UnitIsDeadOrGhost("player") then
				return
			end
			if HasSelfResurrect() then
				return
			end
			if not IsInPvPZone() then
				return
			end

			RepopMe()
			StaticPopup_Hide("DEATH")
		end)
	end
end

function AutoPvPRelease:RegisterModuleEvents()
	if self.eventsRegistered then
		return
	end
	self.eventsRegistered = true

	self:RegisterEvent("PLAYER_DEAD")
end

function AutoPvPRelease:UnregisterModuleEvents()
	if not self.eventsRegistered then
		return
	end
	self.eventsRegistered = false

	ns:UnregisterEvent("PLAYER_DEAD", self.PLAYER_DEAD)
end

function AutoPvPRelease:OnSettingChanged(key, value)
	if key ~= "enable" then
		return
	end
	if value then
		self:RegisterModuleEvents()
	else
		self:UnregisterModuleEvents()
	end
end

function AutoPvPRelease:OnEnable()
	if ns.db.autoPvPRelease.enable then
		self:RegisterModuleEvents()
	end
end

function AutoPvPRelease:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Auto PvP Release"], L["Automatically release spirit in Battlegrounds and PvP instances."])
	local _, delayInit = builder:Slider(category, self, "delay", L["Release Delay (seconds)"], L["The amount of seconds to wait before auto-releasing your spirit."], 0, 30, 1, "%d")

	builder:DependsOn(delayInit, enableInit)
end
