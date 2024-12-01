local _, Module = ...

local CancelDuel = CancelDuel
local StaticPopup_Hide = StaticPopup_Hide
local CancelPetBattlePVPDuel = C_PetBattles.CancelPVPDuel
local confirmationColor = "|cff00ff00"

-- Declines a pending duel request
function Module:DeclineDuelRequest(opponentName)
	CancelDuel() -- Cancel the duel request
	StaticPopup_Hide("DUEL_REQUESTED") -- Hide the pending duel popup
	Module:Print("Declined a duel request from: " .. confirmationColor .. opponentName .. "|r") -- Print confirmation message
end

-- Declines a pending pet battle PVP duel request
function Module:DeclinePetBattlePVPDuelRequest(opponentName)
	CancelPetBattlePVPDuel() -- Cancel the pet battle PVP duel request
	StaticPopup_Hide("PET_BATTLE_PVP_DUEL_REQUESTED") -- Hide the pending pet battle PVP duel popup
	Module:Print("Declined a pet battle PVP duel request from: " .. confirmationColor .. opponentName .. "|r") -- Print confirmation message
end

-- Registers or unregisters the event handlers for auto-declining duels
function Module:CreateAutoDeclineDuels()
	if Module.NexConfig.automation.DeclineDuels then
		self:RegisterEvent("DUEL_REQUESTED", self.DeclineDuelRequest)
	elseif self:IsEventRegistered("DUEL_REQUESTED", self.DeclineDuelRequest) then
		self:UnregisterEvent("DUEL_REQUESTED", self.DeclineDuelRequest)
	end

	-- Check and register/unregister pet battle PVP duel request events based on profile settings
	if Module.NexConfig.automation.DeclinePetDuels then
		self:RegisterEvent("PET_BATTLE_PVP_DUEL_REQUESTED", self.DeclinePetBattlePVPDuelRequest)
	elseif self:IsEventRegistered("PET_BATTLE_PVP_DUEL_REQUESTED", self.DeclinePetBattlePVPDuelRequest) then
		self:UnregisterEvent("PET_BATTLE_PVP_DUEL_REQUESTED", self.DeclinePetBattlePVPDuelRequest)
	end
end

function Module:PLAYER_LOGIN()
	self:CreateAutoDeclineDuels()
end
