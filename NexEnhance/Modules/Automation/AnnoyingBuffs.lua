local _, Module = ...

function Module:CheckAndRemoveBadBuffs()
	-- Only remove buffs if the player is out of combat and regen is enabled
	if not InCombatLockdown() and UnitAffectingCombat("player") == false then
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
			if Module.Data.AnnoyingBuffsInfo[aura.spellId] then
				CancelSpellByName(aura.name)
				local spellLink = GetSpellLink(aura.spellId)
				Module:Print("Removed annoying buff" .. " " .. (spellLink or aura.name) .. "|r")
			end

			index = index + 1
		end
	end
end

function Module:PLAYER_LOGIN()
	if Module.db.profile.automation.AnnoyingBuffs then
		Module:RegisterUnitEvent("UNIT_AURA", "player", self.CheckAndRemoveBadBuffs)
		Module:RegisterEvent("PLAYER_REGEN_ENABLED", self.CheckAndRemoveBadBuffs) -- Add this line
	else
		Module:UnregisterUnitEvent("UNIT_AURA", "player", self.CheckAndRemoveBadBuffs)
		Module:UnregisterEvent("PLAYER_REGEN_ENABLED", self.CheckAndRemoveBadBuffs) -- Add this line
	end
end
