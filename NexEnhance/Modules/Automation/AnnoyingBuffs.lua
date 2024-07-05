local _, Module = ...

local UnitBuff = UnitBuff

function Module:CheckAndRemoveBadBuffs()
	local index = 1
	while true do
		local name, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", index)
		if not name then
			return
		end

		if Module.Data.AnnoyingBuffsInfo[spellId] then -- Adjusted to use spellId instead of name
			CancelSpellByName(name)
			Module:Print("Removed annoying buff" .. " " .. GetSpellLink(spellId) .. "|r")
		end

		index = index + 1
	end
end

function Module:PLAYER_LOGIN()
	if Module.db.profile.automation.AnnoyingBuffs then
		Module:RegisterUnitEvent("UNIT_AURA", "player", self.CheckAndRemoveBadBuffs)
	else
		Module:UnregisterUnitEvent("UNIT_AURA", "player", self.CheckAndRemoveBadBuffs)
	end
end
