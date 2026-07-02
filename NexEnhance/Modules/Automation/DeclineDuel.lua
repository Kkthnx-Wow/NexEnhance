--[[
	NexEnhance - Decline Duel
	-------------------------------------------------------------------------
	Automatically declines duel and pet-battle PvP duel requests, hiding the
	Blizzard popup and printing who was declined.

	Adapted from KkthnxUI by Josh "Kkthnx" Russell:
	  https://github.com/Kkthnx-Wow/KkthnxUI/blob/master/KkthnxUI/Modules/Automation/Elements/DeclineDuel.lua

	Both event handlers are registered when the module first enables and are
	gated at fire time by the master toggle and their own sub-option, so every
	toggle applies live without a reload.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local F, L = ns.F, ns.L

local _G = _G
local format = string.format
local CancelDuel = CancelDuel
local StaticPopup_Hide = StaticPopup_Hide
local C_PetBattles_CancelPVPDuel = C_PetBattles and C_PetBattles.CancelPVPDuel

local UNKNOWN = _G.UNKNOWN or "Unknown"

ns:RegisterDefaults({
	declineDuel = {
		enable = true,
		declineDuels = true,
		declinePetDuels = true,
	},
})

local DeclineDuel = ns:NewModule("DeclineDuel", "declineDuel", { group = "automation", title = L["Decline Duels"], order = 50 })

local eventHandles = {}

function DeclineDuel:DUEL_REQUESTED(name)
	if not ns.db.declineDuel.enable then
		return
	end
	if not ns.db.declineDuel.declineDuels then
		return
	end

	CancelDuel()
	StaticPopup_Hide("DUEL_REQUESTED")
	F.Print(format(L["Declined a duel request from %s."], F.Colorize(name or UNKNOWN, "green")))
end

function DeclineDuel:PET_BATTLE_PVP_DUEL_REQUESTED(name)
	if not ns.db.declineDuel.enable then
		return
	end
	if not ns.db.declineDuel.declinePetDuels then
		return
	end

	if C_PetBattles_CancelPVPDuel then
		C_PetBattles_CancelPVPDuel()
	end
	StaticPopup_Hide("PET_BATTLE_PVP_DUEL_REQUESTED")
	F.Print(format(L["Declined a pet battle duel request from %s."], F.Colorize(name or UNKNOWN, "green")))
end

function DeclineDuel:RegisterModuleEvents()
	if self.eventsRegistered then
		return
	end
	self.eventsRegistered = true

	self:TrackEvent(eventHandles, "DUEL_REQUESTED")
	self:TrackEvent(eventHandles, "PET_BATTLE_PVP_DUEL_REQUESTED")
end

function DeclineDuel:UnregisterModuleEvents()
	if not self.eventsRegistered then
		return
	end
	self.eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
end

function DeclineDuel:OnDisable()
	self:UnregisterModuleEvents()
end

function DeclineDuel:OnSettingChanged(key, value)
	if key == "enable" then
		if value then
			self:RegisterModuleEvents()
		else
			self:OnDisable()
		end
	end
end

function DeclineDuel:OnEnable()
	self:RegisterModuleEvents()
end

function DeclineDuel:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Decline Duels"], L["Automatically decline duel and pet-battle PvP duel requests."])
	local _, duelInit = builder:Checkbox(category, self, "declineDuels", L["Decline Player Duels"], L["Decline standard player duel requests."])
	local _, petInit = builder:Checkbox(category, self, "declinePetDuels", L["Decline Pet Duels"], L["Decline pet-battle PvP duel requests."])

	builder:DependsOn(duelInit, enableInit)
	builder:DependsOn(petInit, enableInit)
end
