--[[
	NexEnhance - Auto Greed
	-------------------------------------------------------------------------
	Automatically rolls Greed (or Disenchant) on low-rarity group-loot drops so
	you are not clicking the same roll buttons all night. By default it only
	acts at max level, on Uncommon (green) Bind-on-Equip items, and prefers
	Disenchant when you can.

	Notes on the modern API (verified against Blizzard source under Resources/):
	  * START_LOOT_ROLL(rollID, rollTime, lootHandle)
	  * GetLootRollItemInfo(rollID) ->
	      texture, name, count, quality, bindOnPickUp,
	      canNeed, canGreed, canDisenchant, ...
	  * RollOnLoot(rollID, rollType) with LOOT_ROLL_TYPE_* (PASS/NEED/GREED/DE)
	  * BoP / soulbound rolls raise CONFIRM_LOOT_ROLL / CONFIRM_DISENCHANT_ROLL,
	    answered with ConfirmLootRoll(rollID, rollType).

	Midnight: item quality can be a secret value inside instances, so the rarity
	gate is taken behind F.NotSecret - if we cannot read it, we leave the roll
	for the player rather than guessing.
--]]

---@diagnostic disable: undefined-field, undefined-global
local _, ns = ...
local F, L = ns.F, ns.L

local _G = _G

local GetLootRollItemInfo = GetLootRollItemInfo
local RollOnLoot = RollOnLoot
local ConfirmLootRoll = ConfirmLootRoll
local StaticPopup_Hide = StaticPopup_Hide
local UnitLevel = UnitLevel
local GetMaxLevelForPlayerExpansion = GetMaxLevelForPlayerExpansion
local wipe = wipe

local LOOT_ROLL_TYPE_GREED = _G.LOOT_ROLL_TYPE_GREED -- 2
local LOOT_ROLL_TYPE_DISENCHANT = _G.LOOT_ROLL_TYPE_DISENCHANT -- 3

local UNCOMMON = Enum.ItemQuality.Uncommon -- 2
local RARE = Enum.ItemQuality.Rare -- 3

ns:RegisterDefaults({
	autoGreed = {
		enable = false,
		maxLevelOnly = true,
		preferDisenchant = true,
		includeRares = false,
		skipBoP = true,
		autoConfirm = true,
	},
})

local AutoGreed = ns:NewModule("AutoGreed", "autoGreed", { group = "automation", title = L["Auto Greed"], order = 15 })

local eventHandles = {}

-- Roll IDs we initiated, so we only auto-confirm our own BoP/soulbound prompts
-- and never silently confirm a roll the player started by hand.
local ourRolls = {}

local function AtMaxLevel()
	return UnitLevel("player") >= GetMaxLevelForPlayerExpansion()
end

-- Decide the roll type for an eligible item, or nil to leave it alone.
local function ChooseRoll(cfg, canGreed, canDisenchant)
	if cfg.preferDisenchant and canDisenchant then
		return LOOT_ROLL_TYPE_DISENCHANT
	end
	if canGreed then
		return LOOT_ROLL_TYPE_GREED
	end
	if canDisenchant then
		return LOOT_ROLL_TYPE_DISENCHANT
	end
	return nil
end

function AutoGreed:START_LOOT_ROLL(rollID)
	local cfg = ns.db.autoGreed
	if not cfg.enable or not rollID then
		return
	end
	if cfg.maxLevelOnly and not AtMaxLevel() then
		return
	end

	local _, name, _, quality, bindOnPickUp, _, canGreed, canDisenchant = GetLootRollItemInfo(rollID)
	if not name then
		return
	end

	-- Never act on a rarity we cannot actually read (secret in instances).
	if F.IsSecret(quality) or quality == nil then
		return
	end

	local maxQuality = cfg.includeRares and RARE or UNCOMMON
	if quality < UNCOMMON or quality > maxQuality then
		return
	end

	if bindOnPickUp and cfg.skipBoP then
		return
	end

	local rollType = ChooseRoll(cfg, canGreed, canDisenchant)
	if not rollType then
		return
	end

	ourRolls[rollID] = rollType
	RollOnLoot(rollID, rollType)
end

-- Both confirm events share the same shape (rollID, rollType). We only answer
-- prompts for rolls we started; anything else is the player's decision.
function AutoGreed:ConfirmRoll(rollID, rollType)
	local cfg = ns.db.autoGreed
	if not cfg.enable or not cfg.autoConfirm then
		return
	end
	if not ourRolls[rollID] then
		return
	end

	ourRolls[rollID] = nil
	ConfirmLootRoll(rollID, rollType)
	StaticPopup_Hide("CONFIRM_LOOT_ROLL")
end

function AutoGreed:CONFIRM_LOOT_ROLL(rollID, rollType)
	self:ConfirmRoll(rollID, rollType)
end

function AutoGreed:CONFIRM_DISENCHANT_ROLL(rollID, rollType)
	self:ConfirmRoll(rollID, rollType)
end

-- Drop our bookkeeping once a roll resolves so the table cannot grow unbounded.
function AutoGreed:CANCEL_LOOT_ROLL(rollID)
	ourRolls[rollID] = nil
end

function AutoGreed:RegisterModuleEvents()
	if self.eventsRegistered then
		return
	end
	self.eventsRegistered = true

	self:TrackEvent(eventHandles, "START_LOOT_ROLL")
	self:TrackEvent(eventHandles, "CONFIRM_LOOT_ROLL")
	self:TrackEvent(eventHandles, "CONFIRM_DISENCHANT_ROLL")
	self:TrackEvent(eventHandles, "CANCEL_LOOT_ROLL")
end

function AutoGreed:UnregisterModuleEvents()
	if not self.eventsRegistered then
		return
	end
	self.eventsRegistered = false
	wipe(ourRolls)
	ns:UnregisterModuleEventHandles(eventHandles)
end

function AutoGreed:OnDisable()
	self:UnregisterModuleEvents()
end

function AutoGreed:OnEnable()
	self:RegisterModuleEvents()
end

function AutoGreed:OnSettingChanged(key)
	if key == "enable" then
		-- ApplyModuleSetting owns enable lifecycle.
		return
	end
end

function AutoGreed:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Auto Greed"], L["Automatically roll Greed (or Disenchant) on low-rarity group loot."])
	local _, maxLevelInit = builder:Checkbox(category, self, "maxLevelOnly", L["Max Level Only"], L["Only auto-roll while at the expansion's max level."])
	local _, deInit = builder:Checkbox(category, self, "preferDisenchant", L["Prefer Disenchant"], L["Disenchant instead of Greed whenever you are able to."])
	local _, raresInit = builder:Checkbox(category, self, "includeRares", L["Include Rares"], L["Also auto-roll on Rare (blue) items, not just Uncommon (green)."])
	local _, bopInit = builder:Checkbox(category, self, "skipBoP", L["Skip Bind on Pickup"], L["Never auto-roll on Bind-on-Pickup items; leave those for you to decide."])
	local _, confirmInit = builder:Checkbox(category, self, "autoConfirm", L["Auto-Confirm"], L["Automatically confirm the bind/soulbound popup for rolls this module made."])

	builder:DependsOn(maxLevelInit, enableInit)
	builder:DependsOn(deInit, enableInit)
	builder:DependsOn(raresInit, enableInit)
	builder:DependsOn(bopInit, enableInit)
	builder:DependsOn(confirmInit, enableInit)
end
