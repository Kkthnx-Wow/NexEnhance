--[[
	NexEnhance - Auto Summon
	-------------------------------------------------------------------------
	Automatically accepts summon requests when you are out of combat, because
	nobody has time to stare at a popup and manually click "Accept" while
	waiting for that one lazy raid member to finally get to the stone.

	Blizzard has this tendency to lazily prompt players with popups that block
	half the screen. We automate this nuisance. We only do it out of combat
	to avoid accidentally teleporting you into the abyss mid-boss pull.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local F, L = ns.F, ns.L

local C_SummonInfo = C_SummonInfo
local StaticPopup_Hide = StaticPopup_Hide
local UnitAffectingCombat = UnitAffectingCombat

ns:RegisterDefaults({
	autoSummon = {
		enable = false,
	},
})

local AutoSummon = ns:NewModule("AutoSummon", "autoSummon", { group = "automation", title = L["Auto Summon"], order = 100 })

local eventHandles = {}

function AutoSummon:CONFIRM_SUMMON()
	if not ns.db.autoSummon.enable then
		return
	end

	-- If the player is in combat, ignore it. Taking a summon mid-fight is usually a disaster.
	if UnitAffectingCombat("player") then
		return
	end

	local summonInfo = C_SummonInfo
	if not summonInfo or not summonInfo.ConfirmSummon then
		return
	end

	-- Delay slightly to let the client settle, standard next-frame or 0.1s defer
	C_Timer.After(0.1, function()
		if not ns.db.autoSummon.enable then
			return
		end
		if UnitAffectingCombat("player") then
			return
		end

		local info = C_SummonInfo
		if not info or not info.GetSummonConfirmTimeLeft or info.GetSummonConfirmTimeLeft() <= 0 then
			-- The summon has already expired or vanished. Sad.
			return
		end
		if not info.GetSummonConfirmSummoner or not info.GetSummonConfirmSummoner() then
			-- No summoner info? Blizzard API doing Blizzard things. Skip.
			return
		end

		info.ConfirmSummon()

		-- Hide all the redundant Blizzard popups that would otherwise linger
		StaticPopup_Hide("CONFIRM_SUMMON")
		StaticPopup_Hide("CONFIRM_SUMMON_SCENARIO")
		StaticPopup_Hide("CONFIRM_SUMMON_STARTING_AREA")
	end)
end

function AutoSummon:RegisterModuleEvents()
	if self.eventsRegistered then
		return
	end
	self.eventsRegistered = true

	self:TrackEvent(eventHandles, "CONFIRM_SUMMON")
end

function AutoSummon:UnregisterModuleEvents()
	if not self.eventsRegistered then
		return
	end
	self.eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
end

function AutoSummon:OnDisable()
	self:UnregisterModuleEvents()
end

function AutoSummon:OnSettingChanged(key, value)
	if key ~= "enable" then
		return
	end
	if value then
		self:RegisterModuleEvents()
	else
		self:OnDisable()
	end
end

function AutoSummon:OnEnable()
	if ns.db.autoSummon.enable then
		self:RegisterModuleEvents()
	end
end

function AutoSummon:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Auto Summon"], L["Automatically accept summon requests when you are out of combat."])
end
