--[[
	NexEnhance - Faster Loot
	-------------------------------------------------------------------------
	Speeds up auto-loot by clearing every loot slot the instant LOOT_READY
	fires (with a short throttle to avoid hammering the server), so corpses
	empty almost immediately when auto-loot is active.

	Ported from NDui's Misc FasterLoot (by siweia), adapted to the NexEnhance
	framework. Toggles its event subscription live, no reload needed.
--]]

local _, ns = ...
local L = ns.L

local GetTime = GetTime
local GetCVarBool = GetCVarBool
local IsModifiedClick = IsModifiedClick
local GetNumLootItems = GetNumLootItems
local LootSlot = LootSlot

ns:RegisterDefaults({
	fasterLoot = {
		enable = true,
	},
})

local FasterLoot = ns:NewModule("FasterLoot", "fasterLoot", { group = "automation", title = L["Faster Loot"], order = 30 })

local lootDelay = 0

local function DoFasterLoot()
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

function FasterLoot:Update()
	if ns.db.fasterLoot.enable then
		if not self.registered then
			ns:RegisterEvent("LOOT_READY", DoFasterLoot)
			self.registered = true
		end
	elseif self.registered then
		ns:UnregisterEvent("LOOT_READY", DoFasterLoot)
		self.registered = nil
	end
end

function FasterLoot:OnEnable()
	self:Update()
end

function FasterLoot:OnSettingChanged()
	self:Update()
end

function FasterLoot:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Faster Loot"], L["Instantly clear loot when auto-loot is active."])
end
