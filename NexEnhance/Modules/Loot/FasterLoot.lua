local NexEnhance, NE_FasterLoot = ...

-- Local references to global functions
local GetCVarBool = GetCVarBool
local GetNumLootItems = GetNumLootItems
local GetTime = GetTime
local IsModifiedClick = IsModifiedClick
local LootSlot = LootSlot

local lootDelay = 0

-- Function to handle faster loot
local function HandleFasterLoot()
	local thisTime = GetTime()
	if thisTime - lootDelay >= 0.3 then
		lootDelay = thisTime

		if GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE") then
			for i = GetNumLootItems(), 1, -1 do
				LootSlot(i)
			end
			lootDelay = thisTime
		end
	end
end

-- Function to enable or disable faster loot based on the configuration
function NE_FasterLoot:OnLogin()
	if NE_FasterLoot.db.profile.loot.FasterLoot then
		NE_FasterLoot:RegisterEvent("LOOT_READY", HandleFasterLoot)
	else
		NE_FasterLoot:UnregisterEvent("LOOT_READY", HandleFasterLoot)
	end
end
