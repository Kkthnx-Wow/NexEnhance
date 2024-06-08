local _, Module = ...

local UnitBuff = UnitBuff
local InCombatLockdown = InCombatLockdown

Module.CheckBadBuffs = {
	[172003] = true,
	[172008] = true,
	[172010] = true,
	[172015] = true,
	[172020] = true,
	[24709] = true,
	[24710] = true,
	[24712] = true,
	[24723] = true,
	[24732] = true,
	[24735] = true,
	[24740] = true,
	[279509] = true,
	[44212] = true,
	[58493] = true,
	[61716] = true,
	[61734] = true,
	[61781] = true,
	[261477] = true,
	[354550] = true,
	[354481] = true,
}

-- Function to check for bad buffs and remove them
local function CheckAndRemoveBadBuffs(event)
	-- Check if the player is in combat, if so, register for the event when the player leaves combat
	if InCombatLockdown() then
		return Module:RegisterEvent("PLAYER_REGEN_ENABLED", CheckAndRemoveBadBuffs)
	-- Unregister the event if the player has left combat
	elseif event == "PLAYER_REGEN_ENABLED" then
		Module:UnregisterEvent("PLAYER_REGEN_ENABLED", CheckAndRemoveBadBuffs)
	end

	-- Loop through all the player's buffs
	local index = 1
	while true do
		local name, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", index)
		if not name then
			return
		end

		-- Check if the current buff is a bad buff, and if so, cancel it and print a message
		if Module.CheckAnnoyingBuffs[name] then
			CancelSpellByName(name)
			Module:Print("Removed Bad Buff" .. " " .. GetSpellLink(spellId) .. "|r")
		end

		index = index + 1
	end
end

function Module:PLAYER_LOGIN()
	if Module.db.profile.automation.AnnoyingBuffs then
		Module:RegisterUnitEvent("UNIT_AURA", CheckAndRemoveBadBuffs, "player")
	else
		Module:UnregisterUnitEvent("UNIT_AURA", CheckAndRemoveBadBuffs)
	end
end
