--[[
	NexEnhance - Faster Loot
	-------------------------------------------------------------------------
	Speeds up auto-loot by walking loot slots immediately when loot opens. The
	slot walker is paced very lightly so it stays responsive without hammering
	the server or repeatedly processing duplicate loot events.
--]]

local _, ns = ...
local L = ns.L

local GetCVarBool = GetCVarBool
local IsModifiedClick = IsModifiedClick
local GetNumLootItems = GetNumLootItems
local GetLootSlotInfo = GetLootSlotInfo
local LootSlot = LootSlot
local CreateFrame = CreateFrame
local select, type = select, type

ns:RegisterDefaults({
	fasterLoot = {
		enable = true,
	},
})

local FasterLoot = ns:NewModule("FasterLoot", "fasterLoot", { group = "automation", title = L["Faster Loot"], order = 30 })

local LOOT_TICK = 0.03
local lootFrame = CreateFrame("Frame")
local currentSlot, tickElapsed = 0, 0
local lastNumLoot = nil
local initialAutoLootState = false

local function IsAutoLooting(autoLoot)
	if not initialAutoLootState then
		-- LOOT_READY can fire repeatedly and its autoLoot arg can be noisy, so
		-- preserve the first positive state and otherwise fall back to the CVar.
		initialAutoLootState = autoLoot or GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE")
	end
	return initialAutoLootState
end

local function StopLootTicker()
	lootFrame:SetScript("OnUpdate", nil)
	currentSlot = 0
	tickElapsed = 0
end

local function LootCurrentSlot()
	if currentSlot < 1 then
		StopLootTicker()
		return
	end

	local maybeLocked, modernLocked = select(5, GetLootSlotInfo(currentSlot))
	local locked = type(maybeLocked) == "boolean" and maybeLocked or modernLocked
	if not locked then
		LootSlot(currentSlot)
	end
	currentSlot = currentSlot - 1
end

local function OnLootTicker(_, elapsed)
	tickElapsed = tickElapsed + elapsed
	if tickElapsed < LOOT_TICK then
		return
	end
	tickElapsed = 0
	LootCurrentSlot()
end

local function StartLooting(numItems)
	StopLootTicker()
	currentSlot = numItems
	LootCurrentSlot()
	if currentSlot > 0 then
		lootFrame:SetScript("OnUpdate", OnLootTicker)
	end
end

local function DoFasterLoot(_, autoLoot)
	local numItems = GetNumLootItems()
	if numItems == 0 or lastNumLoot == numItems then
		return
	end

	if IsAutoLooting(autoLoot) then
		lastNumLoot = numItems
		StartLooting(numItems)
	end
end

local function OnLootClosed()
	StopLootTicker()
	lastNumLoot = nil
	initialAutoLootState = false
end

function FasterLoot:Update()
	if ns.db.fasterLoot.enable then
		if not self.registered then
			ns:RegisterEvent("LOOT_READY", DoFasterLoot)
			ns:RegisterEvent("LOOT_OPENED", DoFasterLoot)
			ns:RegisterEvent("LOOT_CLOSED", OnLootClosed)
			self.registered = true
		end
	elseif self.registered then
		ns:UnregisterEvent("LOOT_READY", DoFasterLoot)
		ns:UnregisterEvent("LOOT_OPENED", DoFasterLoot)
		ns:UnregisterEvent("LOOT_CLOSED", OnLootClosed)
		OnLootClosed()
		self.registered = nil
	end
end

function FasterLoot:OnEnable()
	self:Update()
end

function FasterLoot:OnDisable()
	if self.registered then
		ns:UnregisterEvent("LOOT_READY", DoFasterLoot)
		ns:UnregisterEvent("LOOT_OPENED", DoFasterLoot)
		ns:UnregisterEvent("LOOT_CLOSED", OnLootClosed)
		self.registered = nil
	end
	OnLootClosed()
end

function FasterLoot:OnSettingChanged()
	self:Update()
end

function FasterLoot:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Faster Loot"], L["Instantly clear loot when auto-loot is active."])
end
