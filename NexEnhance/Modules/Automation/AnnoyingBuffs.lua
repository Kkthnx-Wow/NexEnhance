local _, Module = ...

function Module:CheckAndRemoveBadBuffs()
	-- Loop through buffs on the player
	local index = 1
	while true do
		-- Get buff data for current index
		local aura = C_UnitAuras.GetBuffDataByIndex("player", index)

		-- Exit loop if no more buffs
		if not aura then
			break
		end

		-- Check for bad buffs and cancel them
		if Module.Data.AnnoyingBuffsInfo[spellId] then
			CancelSpellByName(aura.name)
			local spellLink = C_Spell.GetSpellLink(aura.spellId)
			Module:Print("Removed annoying buff" .. " " .. (spellLink or aura.name) .. "|r")
		end

		index = index + 1
	end

	index = index + 1
end

function Module:PLAYER_LOGIN()
	if Module.db.profile.automation.AnnoyingBuffs then
		Module:RegisterUnitEvent("UNIT_AURA", "player", self.CheckAndRemoveBadBuffs)
	else
		Module:UnregisterUnitEvent("UNIT_AURA", "player", self.CheckAndRemoveBadBuffs)
	end
end
