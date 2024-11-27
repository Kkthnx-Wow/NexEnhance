local _, Module = ...

local isProcessing = false -- Flag to prevent multiple triggers

function Module:CheckAndRemoveBadBuffs()
	if isProcessing then
		return -- Prevent re-entrant calls
	end

	isProcessing = true
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

	isProcessing = false
end

function Module:PLAYER_LOGIN()
	if Module.db.profile.automation.AnnoyingBuffs then
		Module:RegisterUnitEvent("UNIT_AURA", "player", function()
			if not InCombatLockdown() then
				Module:CheckAndRemoveBadBuffs()
			else
				Module:DeferMethod(self, "CheckAndRemoveBadBuffs")
			end
		end)
	else
		Module:UnregisterUnitEvent("UNIT_AURA", "player", self.CheckAndRemoveBadBuffs)
	end
end
