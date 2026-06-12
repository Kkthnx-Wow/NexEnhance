--[[
	NexEnhance - Auto Resurrect
	-------------------------------------------------------------------------
	Automatically accepts resurrection requests while you are out of combat,
	and (optionally) emotes a /thank to whoever brought you back.

	Adapted from KkthnxUI by Josh "Kkthnx" Russell:
	  https://github.com/Kkthnx-Wow/KkthnxUI_Firestorm/blob/main/KkthnxUI/Modules/Automation/Elements/Resurrect.lua

	Item-cast resurrects (the encounter "Failure Detection Pylon" and the
	"Brazier of Awakening") are deliberately ignored so you can still make the
	strategic call on those. The combat check avoids accepting a battle-rez at
	a bad moment. The event stays registered while the module is on; the enable
	flag is read live so the toggle applies without a reload.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local F, L = ns.F, ns.L

local AcceptResurrect = AcceptResurrect
local DoEmote = DoEmote
local StaticPopup_Hide = StaticPopup_Hide
local UnitAffectingCombat = UnitAffectingCombat
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local C_Timer_After = C_Timer.After
local GetLocale = GetLocale

-- Localised names of item-cast resurrects we never auto-accept (the caster
-- "name" handed to RESURRECT_REQUEST is the item name for these).
local PYLON_NAMES = {
	enUS = "Failure Detection Pylon",
	zhCN = "故障检测晶塔",
	zhTW = "滅團偵測水晶塔",
	ruRU = "Пилон для обнаружения проблем",
	koKR = "고장 감지 변환기",
	esMX = "Pilón detector de errores",
	ptBR = "Pilar Detector de Falhas",
	deDE = "Fehlschlagdetektorpylon",
	esES = "Pilón detector de errores",
	frFR = "Pylône de détection des échecs",
	itIT = "Pilone d'Individuazione Fallimenti",
}

local BRAZIER_NAMES = {
	enUS = "Brazier of Awakening",
	zhCN = "觉醒火盆",
	zhTW = "覺醒火盆",
	ruRU = "Жаровня пробуждения",
	koKR = "각성의 화로",
	esMX = "Blandón del Despertar",
	ptBR = "Braseiro do Despertar",
	deDE = "Kohlenbecken des Erwachens",
	esES = "Blandón de Despertar",
	frFR = "Brasero de l'Éveil",
	itIT = "Braciere del Risveglio",
}

-- Build a name->true blacklist for the active client locale (enUS fallback).
local blacklist = {}
do
	local locale = GetLocale()
	blacklist[PYLON_NAMES[locale] or PYLON_NAMES.enUS] = true
	blacklist[BRAZIER_NAMES[locale] or BRAZIER_NAMES.enUS] = true
end

ns:RegisterDefaults({
	autoResurrect = {
		enable = true,
		thankYou = false,
	},
})

local AutoResurrect = ns:NewModule("AutoResurrect", "autoResurrect", { group = "automation", title = L["Auto Resurrect"], order = 80 })

function AutoResurrect:RESURRECT_REQUEST(name)
	if not ns.db.autoResurrect.enable then
		return
	end

	-- Skip item-cast resurrects (pylon/brazier) - those are strategic. The
	-- caster name can be a secret value in 12.0, so gate the lookup.
	if F.NotSecret(name) and name and blacklist[name] then
		return
	end

	-- Only accept while safe; taking a rez mid-fight can pull aggro or waste it.
	if UnitAffectingCombat("player") then
		return
	end

	AcceptResurrect()
	StaticPopup_Hide("RESURRECT_NO_TIMER")

	-- Optional friendly thank-you once we're actually back on our feet.
	if ns.db.autoResurrect.thankYou and F.NotSecret(name) and name then
		C_Timer_After(3, function()
			if not UnitIsDeadOrGhost("player") then
				DoEmote("thank", name)
			end
		end)
	end
end

function AutoResurrect:RegisterModuleEvents()
	if self.eventsRegistered then
		return
	end
	self.eventsRegistered = true

	self:RegisterEvent("RESURRECT_REQUEST")
end

function AutoResurrect:OnSettingChanged(key, value)
	if key == "enable" and value then
		self:RegisterModuleEvents()
	end
end

function AutoResurrect:OnEnable()
	self:RegisterModuleEvents()
end

function AutoResurrect:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Auto Resurrect"], L["Automatically accept resurrection requests while you are out of combat (ignores item-cast soul stones like the encounter pylon and brazier)."])
	local _, thankInit = builder:Checkbox(category, self, "thankYou", L["Thank the Resurrecter"], L["Send a /thank emote to whoever resurrected you, a few seconds after you are back up."])

	builder:DependsOn(thankInit, enableInit)
end
