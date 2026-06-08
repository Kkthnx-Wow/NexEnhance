--[[
	NexEnhance - Cancel Bad Buffs
	-------------------------------------------------------------------------
	Automatically removes cosmetic "costume" and holiday buffs (Hallow's End
	costumes, Mohawked!, Turkey Feathers, Noblegarden disguises and the like)
	while you are out of combat, so a random world transform never sticks to
	your character.

	Reworked from ShestakUI by Wetxius / Shestak (original "by Unknown"):
	  https://github.com/Wetxius/ShestakUI/blob/main/ShestakUI/Modules/Automation/CancelBadBuffs.lua
	  https://github.com/Wetxius/ShestakUI/blob/main/ShestakUI/Config/Filters/BadBuffs.lua

	Differences from the original:
	  - Matches by spellID (locale-independent) instead of localized spell name,
	    so it never has to call GetSpellInfo or risk a stale-name lookup.
	  - Registers UNIT_AURA filtered to the player only (RegisterUnitEvent), plus
	    a single post-combat sweep, instead of a broad UNIT_AURA listener.
	  - Cancels via CancelUnitBuff by index (high -> low) using reused scratch
	    tables, so a sweep allocates nothing.
	  - Guards spellID/name reads with F.NotSecret for 12.0 secret values, and
	    only ever cancels out of combat (cancelling auras is blocked in combat).
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local F, L = ns.F, ns.L

local format = string.format
local tostring = tostring
local InCombatLockdown = InCombatLockdown
local CancelUnitBuff = CancelUnitBuff
local GetBuffDataByIndex = C_UnitAuras and C_UnitAuras.GetBuffDataByIndex

-- Cosmetic / costume / holiday transforms, keyed by spellID. Keying by ID keeps
-- this locale-independent; add new entries by pasting the spellID from Wowhead.
local BAD_BUFFS = {
	[58493] = true, -- Mohawked!
	[44212] = true, -- Jack-o'-Lanterned!
	[61716] = true, -- Rabbit Costume (Noblegarden)
	[61734] = true, -- Noblegarden Bunny
	[61781] = true, -- Turkey Feathers (Pilgrim's Bounty)
	[16739] = true, -- Orb of Deception
	-- Hallow's End costumes (Hallowed Wand / Tricky Treat)
	[24709] = true, -- Pirate Costume
	[24710] = true, -- Ninja Costume
	[24712] = true, -- Leper Gnome Costume
	[24723] = true, -- Skeleton Costume
	[24732] = true, -- Bat Costume
	[24735] = true, -- Ghost Costume
	[24740] = true, -- Wisp Costume
	[172003] = true, -- Slime Costume
	[172008] = true, -- Ghoul Costume
	[172010] = true, -- Abomination Costume
	[172015] = true, -- Geist Costume
	[172020] = true, -- Spider Costume
}

ns:RegisterDefaults({
	cancelBadBuffs = {
		enable = false,
		announce = true,
	},
})

local CancelBadBuffs = ns:NewModule("CancelBadBuffs", "cancelBadBuffs", { group = "automation", title = L["Cancel Bad Buffs"], order = 55 })

-- Reused scratch tables so a sweep never allocates (guide: wipe/reuse, don't {}).
local badIndices, badNames = {}, {}

function CancelBadBuffs:Sweep()
	if not ns.db.cancelBadBuffs.enable then return end
	if not GetBuffDataByIndex or not CancelUnitBuff then return end
	-- Cancelling auras is a protected action that fails in combat; defer to the
	-- PLAYER_REGEN_ENABLED sweep instead.
	if InCombatLockdown() then return end

	local announce = ns.db.cancelBadBuffs.announce
	local count = 0

	local i = 1
	while true do
		local data = GetBuffDataByIndex("player", i, "HELPFUL")
		if not data then break end

		-- spellId is a plain number in the open world, but can be a secret value
		-- inside instances in 12.0; never use a secret as a table key.
		local spellId = data.spellId
		if spellId and F.NotSecret(spellId) and BAD_BUFFS[spellId] then
			count = count + 1
			badIndices[count] = i
			if announce then
				local name = data.name
				badNames[count] = (name and F.NotSecret(name)) and name or tostring(spellId)
			end
		end

		i = i + 1
	end

	if count == 0 then return end

	-- Cancel from the highest index down so the lower indices we still need stay
	-- valid as the aura list shifts.
	for n = count, 1, -1 do
		CancelUnitBuff("player", badIndices[n])
		if announce then
			F.Print(format(L["Cancelled %s."], F.Colorize(badNames[n], "green")))
			badNames[n] = nil
		end
		badIndices[n] = nil
	end
end

function CancelBadBuffs:UNIT_AURA()
	self:Sweep()
end

function CancelBadBuffs:PLAYER_REGEN_ENABLED()
	self:Sweep()
end

function CancelBadBuffs:RegisterModuleEvents()
	if self.eventsRegistered then return end
	if not GetBuffDataByIndex or not CancelUnitBuff then return end
	self.eventsRegistered = true

	self:RegisterUnitEvent("UNIT_AURA", nil, "player")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function CancelBadBuffs:OnSettingChanged(key, value)
	if key == "enable" and value then
		self:RegisterModuleEvents()
		self:Sweep()
	end
end

function CancelBadBuffs:OnEnable()
	if not ns.db.cancelBadBuffs.enable then return end
	self:RegisterModuleEvents()
end

function CancelBadBuffs:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Cancel Bad Buffs"], L["Automatically remove cosmetic costume and holiday buffs (Hallow's End costumes, Mohawked!, Turkey Feathers and similar) while you are out of combat."])
	local _, announceInit = builder:Checkbox(category, self, "announce", L["Announce Cancelled Buffs"], L["Print a message in chat whenever a cosmetic buff is removed."])

	builder:DependsOn(announceInit, enableInit)
end
