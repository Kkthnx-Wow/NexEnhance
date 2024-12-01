local _, Module = ...

local select = select
local UnitIsPlayer = UnitIsPlayer
local UnitName = UnitName
local IsShiftKeyDown = IsShiftKeyDown
local hooksecurefunc = hooksecurefunc
local C_MountJournal_GetMountFromSpell = C_MountJournal.GetMountFromSpell
local C_MountJournal_GetMountInfoByID = C_MountJournal.GetMountInfoByID
local C_MountJournal_GetMountInfoExtraByID = C_MountJournal.GetMountInfoExtraByID

local MountTable = {}

-- Function to check if a mount is collected
local function IsCollected(spell)
	local mountInfo = MountTable[spell]
	if mountInfo then
		return select(11, C_MountJournal_GetMountInfoByID(mountInfo.index))
	end
	return false
end

local function GetMountInfoBySpell(spell)
	if not MountTable[spell] then
		local index = C_MountJournal_GetMountFromSpell(spell)
		if index then
			local _, mSpell = C_MountJournal_GetMountInfoByID(index)
			if spell == mSpell then
				local _, _, source = C_MountJournal_GetMountInfoExtraByID(index)
				MountTable[spell] = { source = source, index = index }
			end
		end
	end
	return MountTable[spell]
end

local function AddLine(self, source, isCollectedText, type, noadd)
	for i = 1, self:NumLines() do
		local line = _G[self:GetName() .. "TextLeft" .. i]
		if line then
			local text = line:GetText()
			if text == type then
				return
			end
		end
	end

	if not noadd then
		self:AddLine(" ")
	end

	self:AddDoubleLine(type, isCollectedText)
	self:AddLine(source, 1, 1, 1)
	self:Show()
end

local function HandleAura(self, id)
	if IsShiftKeyDown() and UnitIsPlayer("target") and UnitName("target") ~= Module.MyName then
		local mountInfo = id and GetMountInfoBySpell(id)
		if mountInfo then
			AddLine(self, mountInfo.source, IsCollected(id) and COLLECTED or NOT_COLLECTED, SOURCE)
		end
	end
end

function Module:PLAYER_LOGIN()
	if C_AddOns.IsAddOnLoaded("MountsSource") then
		return
	end

	-- Add config option

	hooksecurefunc(GameTooltip, "SetUnitAura", function(self, ...)
		local spellID = select(10, AuraUtil.UnpackAuraData(C_UnitAuras.GetAuraDataByIndex(...)))
		local table = spellID and GetMountInfoBySpell(spellID)
		if table then
			HandleAura(self, spellID)
		end
	end)

	hooksecurefunc(GameTooltip, "SetUnitBuffByAuraInstanceID", function(self, unit, auraInstanceID)
		local data = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
		if not data then
			return
		end

		local table = data.spellId and GetMountInfoBySpell(data.spellId)
		if table then
			HandleAura(self, data.spellId)
		end
	end)
end
