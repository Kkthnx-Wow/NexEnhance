local _, Module = ...

local AcceptResurrect = AcceptResurrect
local DoEmote = DoEmote
local StaticPopup_Hide = StaticPopup_Hide
local UnitAffectingCombat = UnitAffectingCombat
local UnitIsDeadOrGhost = UnitIsDeadOrGhost

-- Localized names for specific items
local localizedPylonNames = {
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
local localizedBrazierNames = {
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

-- Valid emotes
local validEmotes = {
	["cheer"] = true,
	["thank"] = true,
	["bow"] = true,
	["salute"] = true,
	["wave"] = true,
	["clap"] = true,
	["raise"] = true,
	["apologize"] = true,
	["flex"] = true,
}

local function HandleAutoResurrect(_, arg1)
	local clientLocale = GetLocale()
	local pylonName = localizedPylonNames[clientLocale] or localizedPylonNames["enUS"]
	local brazierName = localizedBrazierNames[clientLocale] or localizedBrazierNames["enUS"]
	if pylonName == arg1 or brazierName == arg1 then
		return
	end

	if not UnitAffectingCombat("player") then
		AcceptResurrect()
		StaticPopup_Hide("RESURRECT_NO_TIMER")
		if Module.db.profile.automation.AutoResurrectEmote and Module.db.profile.automation.AutoResurrectEmote ~= "none" then
			C_Timer.After(3, function()
				if not UnitIsDeadOrGhost("player") then
					local emote = Module.db.profile.automation.AutoResurrectEmote
					if validEmotes[emote] then
						DoEmote(emote, arg1)
					else
						-- Fallback to a safe emote
						DoEmote("thank", arg1)
					end
				end
			end)
		end
	end
end

function Module:PLAYER_LOGIN()
	if Module.db.profile.automation.AutoResurrect then
		Module:RegisterEvent("RESURRECT_REQUEST", HandleAutoResurrect)
	else
		Module:UnregisterEvent("RESURRECT_REQUEST", HandleAutoResurrect)
	end
end
