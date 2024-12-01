local _, Module = ...

local UnitBattlePetType, UnitBattlePetSpeciesID = UnitBattlePetType, UnitBattlePetSpeciesID
local PET, ID, UNKNOWN = PET, ID, UNKNOWN
local PET_TYPE_SUFFIX = PET_TYPE_SUFFIX

function Module:UpdatePetInfo(petType)
	if not self.petIcon then
		local f = self:CreateTexture(nil, "OVERLAY")
		f:SetPoint("TOPRIGHT", -5, -5)
		f:SetSize(35, 35)
		f:SetBlendMode("ADD")
		f:SetTexCoord(0.188, 0.883, 0, 0.348)
		self.petIcon = f
	end

	if PET_TYPE_SUFFIX[petType] then
		self.petIcon:SetTexture("Interface\\PetBattles\\PetIcon-" .. PET_TYPE_SUFFIX[petType])
		self.petIcon:SetAlpha(1)
	end
end

function Module:ResetPetInfo()
	if self.petIcon and self.petIcon:GetAlpha() ~= 0 then
		self.petIcon:SetAlpha(0)
	end
end
GameTooltip:HookScript("OnTooltipCleared", Module.ResetPetInfo)

function Module:PetInfo(unit)
	-- Add config option
	if not unit then
		return
	end

	if not UnitIsBattlePet(unit) then
		return
	end

	-- Pet Species icon
	Module.UpdatePetInfo(self, UnitBattlePetType(unit))

	-- Pet ID
	local speciesID = UnitBattlePetSpeciesID(unit)
	self:AddDoubleLine(PET .. ID .. ":", speciesID and (Module.InfoColor .. speciesID .. "|r") or ("|CFFC0C0C0" .. UNKNOWN .. "|r"))
end
