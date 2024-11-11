local _, Module = ...

function Module:CheckAndRemoveBadBuffs()
	if InCombatLockdown() then
		if not Module:IsEventRegistered("PLAYER_REGEN_ENABLED", self.CheckAndRemoveBadBuffs) then
			Module:RegisterEvent("PLAYER_REGEN_ENABLED", self.CheckAndRemoveBadBuffs)
		end
		return
	else
		if Module:IsEventRegistered("PLAYER_REGEN_ENABLED", self.CheckAndRemoveBadBuffs) then
			Module:UnregisterEvent("PLAYER_REGEN_ENABLED", self.CheckAndRemoveBadBuffs)
		end
	end

	local index = 1
	while true do
		local aura = C_UnitAuras.GetBuffDataByIndex("player", index)

		if not aura then
			break
		end

		if Module.Data.AnnoyingBuffsInfo[aura.spellId] then
			CancelSpellByName(aura.name)
			local spellLink = C_Spell.GetSpellLink(aura.spellId)
			Module:Print("Removed annoying buff" .. " " .. (spellLink or aura.name) .. "|r")
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
