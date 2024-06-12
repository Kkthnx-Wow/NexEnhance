local _, Module = ...

local UnitBuff = UnitBuff
local InCombatLockdown = InCombatLockdown

Module.CheckAnnoyingBuffs = {
	[172003] = true, -- Red Ogre Costume
	[172008] = true, -- Blue Ogre Costume
	[172010] = true, -- Ogre Pinata
	[172015] = true, -- Ogre Pinata
	[172020] = true, -- Ogre Pinata
	[24709] = true, -- Pirate Costume
	[24710] = true, -- Leper Gnome Costume
	[24712] = true, -- Skeleton Costume
	[24723] = true, -- Polymorph: Pig
	[24732] = true, -- Polymorph: Turtle
	[24735] = true, -- Polymorph: Cow
	[24740] = true, -- Polymorph: Rabbit
	[261477] = true, -- Fetch Ball
	[279509] = true, -- Blood Elf Illusion
	[354481] = true, -- Sparkle Transformation
	[354550] = true, -- Spinning Sword
	[44212] = true, -- Jack-o'-Lanterned!
	[58493] = true, -- Anxious: Crate Costume
	[61716] = true, -- Rabbit Costume
	[61734] = true, -- Iron Boot Flask
	[61781] = true, -- Headless Horseman Costume

	-- [279997] = true, -- Testing with Heartsbane Curse
}

-- function Module:PLAYER_REGEN_ENABLED()
-- 	Module:CheckAndRemoveBadBuffs()
-- end

function Module:CheckAndRemoveBadBuffs()
	-- if InCombatLockdown() then
	-- 	return end
	-- else
	local index = 1
	while true do
		local name, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", index)
		if not name then
			return
		end

		if Module.CheckAnnoyingBuffs[spellId] then -- Adjusted to use spellId instead of name
			CancelSpellByName(name)
			Module:Print("Removed annoying buff" .. " " .. GetSpellLink(spellId) .. "|r")
		end

		index = index + 1
	end
	-- end
end

function Module:PLAYER_LOGIN()
	if Module.db.profile.automation.AnnoyingBuffs then
		Module:RegisterUnitEvent("UNIT_AURA", "player", self.CheckAndRemoveBadBuffs)
	else
		Module:UnregisterUnitEvent("UNIT_AURA", "player", self.CheckAndRemoveBadBuffs)
	end
end
