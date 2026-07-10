--[[
	NexEnhance - Tooltip Mount Source
	-------------------------------------------------------------------------
	When you hold Shift over another player's mount *buff* (an aura tooltip),
	appends the mount's collection status and where it comes from.

	Wired from Tooltip:OnEnable via Tooltip:SetupMountSource(). Skips when the
	standalone MountsSource addon is loaded. Secret-guarded aura reads.
--]]

local _, ns = ...
local F = ns.F
local Tooltip = ns:GetModule("Tooltip")
if not Tooltip then
	return
end

local select = select
local hooksecurefunc = hooksecurefunc

local AuraUtil = AuraUtil
local C_AddOns = C_AddOns
local C_MountJournal = C_MountJournal
local C_UnitAuras = C_UnitAuras
local IsShiftKeyDown = IsShiftKeyDown
local UnitIsPlayer = UnitIsPlayer
local UnitIsUnit = UnitIsUnit

local COLLECTED = COLLECTED
local NOT_COLLECTED = NOT_COLLECTED
local SOURCE = SOURCE

-- spell -> { source, index }, with `false` cached for non-mount spells so we
-- never re-query the journal for the same aura.
local mountCache = {}

local function GetMountInfoBySpell(spell)
	if mountCache[spell] == nil then
		-- Count the key once (negative result); a later positive overwrite reuses it.
		F.CacheSet(mountCache, spell, false)
		local index = C_MountJournal.GetMountFromSpell(spell)
		if index then
			local _, mSpell = C_MountJournal.GetMountInfoByID(index)
			if spell == mSpell then
				local _, _, source = C_MountJournal.GetMountInfoExtraByID(index)
				mountCache[spell] = { source = source, index = index }
			end
		end
	end
	return mountCache[spell] or nil
end

local function IsCollected(info)
	-- 11th return of GetMountInfoByID is `isCollected`.
	return select(11, C_MountJournal.GetMountInfoByID(info.index)) and true or false
end

-- Append the Source/collection lines once (skip if we've already added them).
local function AddSourceLine(tip, info)
	if F.TooltipHasLine(tip, SOURCE) then
		return
	end

	tip:AddLine(" ")
	tip:AddDoubleLine(SOURCE, IsCollected(info) and COLLECTED or NOT_COLLECTED)
	tip:AddLine(info.source, 1, 1, 1)
	tip:Show()
end

-- Only annotate while Shift is held over another player (not yourself).
local function HandleAura(tip, unit, spellID)
	if not Tooltip:IsEnabled() or not ns.db.tooltip.mountSource then
		return
	end
	if not spellID or F.IsSecret(spellID) then
		return
	end
	if not IsShiftKeyDown() then
		return
	end
	if not unit or F.IsSecretUnit(unit) then
		return
	end
	-- UnitIsPlayer: SecretArguments only.
	local isSelf = F.SafeUnitIsUnit(unit, "player")
	if not UnitIsPlayer(unit) or isSelf then
		return
	end

	local info = GetMountInfoBySpell(spellID)
	if info then
		AddSourceLine(tip, info)
	end
end

function Tooltip:SetupMountSource()
	if Tooltip._mountSourceHooked then
		return
	end
	-- Defer to the dedicated addon if the user runs it.
	if C_AddOns.IsAddOnLoaded("MountsSource") then
		return
	end
	if not (C_MountJournal and AuraUtil and C_UnitAuras) then
		return
	end
	Tooltip._mountSourceHooked = true

	hooksecurefunc(GameTooltip, "SetUnitAura", function(tip, unit, ...)
		if tip:IsForbidden() then
			return
		end
		local data = C_UnitAuras.GetAuraDataByIndex(unit, ...)
		-- A secret data table (e.g. another unit's auras under Patch 12.0) would
		-- crash AuraUtil.UnpackAuraData, so read the spellId field directly and
		-- let HandleAura's IsSecret guard sort out the rest.
		if not data or F.IsSecret(data) then
			return
		end
		HandleAura(tip, unit, data.spellId)
	end)

	hooksecurefunc(GameTooltip, "SetUnitBuffByAuraInstanceID", function(tip, unit, auraInstanceID)
		if tip:IsForbidden() then
			return
		end
		local data = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
		if not data or F.IsSecret(data) then
			return
		end
		HandleAura(tip, unit, data.spellId)
	end)
end
