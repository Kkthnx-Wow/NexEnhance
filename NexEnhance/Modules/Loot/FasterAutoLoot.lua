local _, Module = ...

local GetCVarBool = GetCVarBool
local GetNumLootItems = GetNumLootItems
local GetTime = GetTime
local IsModifiedClick = IsModifiedClick
local LootSlot = LootSlot

local lootDelay = 0

local function HandleFasterLoot()
	local thisTime = GetTime()
	if thisTime - lootDelay < 0.3 then
		return
	end
	lootDelay = thisTime

	if GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE") then
		local numLootItems = GetNumLootItems()
		if not numLootItems or numLootItems == 0 then
			return
		end

		for i = numLootItems, 1, -1 do
			LootSlot(i)
		end

		lootDelay = GetTime()
	end
end

function Module:PLAYER_LOGIN()
	if not (Module.NexConfig and Module.NexConfig.loot and Module.NexConfig.loot.FasterLoot) then
		return
	end

	if Module.NexConfig.loot.FasterLoot then
		Module:RegisterEvent("LOOT_READY", HandleFasterLoot)
	else
		Module:UnregisterEvent("LOOT_READY", HandleFasterLoot)
	end
end
