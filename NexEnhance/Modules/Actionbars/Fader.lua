local _, Module = ...

-----------------
-- Credit: ElvUI
-----------------

Module.handledbuttons = {}

local function ClearTimers(object)
	if object.delayTimer then
		-- P:CancelTimer(object.delayTimer)
		object.delayTimer = nil
	end
end

local function DelayFadeOut(frame, timeToFade, startAlpha, endAlpha)
	ClearTimers(frame)

	if AB.db["Delay"] > 0 then
		frame.delayTimer = P:ScheduleTimer(UIFrameFadeOut, AB.db["Delay"], P, frame, timeToFade, startAlpha, endAlpha)
	else
		UIFrameFadeOut(frame, timeToFade, startAlpha, endAlpha)
	end
end

function Module:FadeBlingTexture(cooldown, alpha)
	if not cooldown then
		return
	end
	cooldown:SetBlingTexture(alpha > 0.5 and [[Interface\Cooldown\star4]] or P.Blank)
end

function Module:FadeBlings(alpha)
	for _, button in pairs(Bar.buttons) do
		Module:FadeBlingTexture(button.cooldown, alpha)
	end
end

function Module:Button_OnEnter()
	if not Module.fadeParent.mouseLock then
		ClearTimers(Module.fadeParent)
		UIFrameFadeIn(Module.fadeParent, 0.2, Module.fadeParent:GetAlpha(), 1)
		Module:FadeBlings(1)
	end
end

function Module:Button_OnLeave()
	if not Module.fadeParent.mouseLock then
		DelayFadeOut(Module.fadeParent, 0.38, Module.fadeParent:GetAlpha(), Module.db["Alpha"])
		Module:FadeBlings(Module.db["Alpha"])
	end
end

local function flyoutButtonAnchor(frame)
	local parent = frame:GetParent()
	local _, parentAnchorButton = parent:GetPoint()
	if not Module.handledbuttons[parentAnchorButton] then
		return
	end

	return parentAnchorButton
end

function Module:FlyoutButton_OnEnter()
	local anchor = flyoutButtonAnchor(self)
	if anchor then
		Module.Button_OnEnter(anchor)
	end
end

function Module:FlyoutButton_OnLeave()
	local anchor = flyoutButtonAnchor(self)
	if anchor then
		Module.Button_OnLeave(anchor)
	end
end

function Module:FadeParent_OnEvent(event)
	if (event == "ACTIONBAR_SHOWGRID") or (Module.db["Combat"] and UnitAffectingCombat("player")) or (Module.db["Target"] and UnitExists("target")) or (Module.db["Casting"] and (UnitCastingInfo("player") or UnitChannelInfo("player"))) or (Module.db["Health"] and (UnitHealth("player") ~= UnitHealthMax("player"))) or (Module.db["Vehicle"] and UnitHasVehicleUI("player")) then
		self.mouseLock = true
		ClearTimers(Module.fadeParent)
		UIFrameFadeIn(self, 0.2, self:GetAlpha(), 1)
		Module:FadeBlings(1)
	else
		self.mouseLock = false
		DelayFadeOut(self, 0.38, self:GetAlpha(), Module.db["Alpha"])
		Module:FadeBlings(Module.db["Alpha"])
	end
end

local options = {
	Combat = {
		enable = function(self)
			self:RegisterEvent("PLAYER_REGEN_ENABLED")
			self:RegisterEvent("PLAYER_REGEN_DISABLED")
			self:RegisterUnitEvent("UNIT_FLAGS", "player")
		end,
		events = { "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UNIT_FLAGS" },
	},
	Target = {
		enable = function(self)
			self:RegisterEvent("PLAYER_TARGET_CHANGED")
		end,
		events = { "PLAYER_TARGET_CHANGED" },
	},
	Casting = {
		enable = function(self)
			self:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
			self:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
			self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
			self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
		end,
		events = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" },
	},
	Health = {
		enable = function(self)
			self:RegisterUnitEvent("UNIT_HEALTH", "player")
		end,
		events = { "UNIT_HEALTH" },
	},
	Vehicle = {
		enable = function(self)
			self:RegisterEvent("UNIT_ENTERED_VEHICLE")
			self:RegisterEvent("UNIT_EXITED_VEHICLE")
			self:RegisterEvent("VEHICLE_UPDATE")
		end,
		events = { "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "VEHICLE_UPDATE" },
	},
}

function Module:UpdateFaderSettings()
	for key, option in pairs(options) do
		if AB.db[key] then
			if option.enable then
				option.enable(AB.fadeParent)
			end
		else
			if option.events and next(option.events) then
				for _, event in ipairs(option.events) do
					AB.fadeParent:UnregisterEvent(event)
				end
			end
		end
	end
end

local NE_ActionBar = {
	["Bar1"] = "MainMenuBar",
	["Bar2"] = "MultiBarBottomLeft",
	["Bar3"] = "MultiBarBottomRight",
	["Bar4"] = "MultiBarLeft",
	["Bar5"] = "MultiBarRight",
	["Bar6"] = "MultiBar5",
	["Bar7"] = "MultiBar6",
	["Bar8"] = "MultiBar7",
	["PetBar"] = "PossessActionBar",
	["StanceBar"] = "MainMenuBarVehicleLeaveButton",
}

local function updateAfterCombat(event)
	Module:UpdateFaderState()
	Module:UnregisterEvent(event, updateAfterCombat)
end

function Module:UpdateFaderState()
	if InCombatLockdown() then
		Module:RegisterEvent("PLAYER_REGEN_ENABLED", updateAfterCombat)
		return
	end

	for key, name in pairs(NE_ActionBar) do
		local bar = _G[name]
		if bar then
			bar:SetParent(Module.db[key] and Module.fadeParent or UIParent)
		end
	end

	if not Module.isHooked then
		for _, button in ipairs(Bar.buttons) do
			button:HookScript("OnEnter", Module.Button_OnEnter)
			button:HookScript("OnLeave", Module.Button_OnLeave)

			Module.handledbuttons[button] = true
		end

		Module.isHooked = true
	end
end

-- function Module:SetupFlyoutButton(button)
-- 	button:HookScript("OnEnter", Module.FlyoutButton_OnEnter)
-- 	button:HookScript("OnLeave", Module.FlyoutButton_OnLeave)
-- end

-- function Module:LAB_FlyoutCreated(button)
-- 	Module:SetupFlyoutButton(button)
-- end

-- function Module:SetupLABFlyout()
-- 	for _, button in next, LAB.FlyoutButtons do
-- 		Module:SetupFlyoutButton(button)
-- 	end

-- 	Module:RegisterCallback("OnFlyoutButtonCreated", Module.LAB_FlyoutCreated)
-- end

function Module:PLAYER_LOGIN()
	if not Module.db["GlobalFade"] then
		return
	end

	Module.fadeParent = CreateFrame("Frame", "NE_Fader", _G.UIParent, "SecureHandlerStateTemplate")
	RegisterStateDriver(Module.fadeParent, "visibility", "[petbattle] hide; show")
	Module.fadeParent:SetAlpha(Module.db["Alpha"])
	Module.fadeParent:RegisterEvent("ACTIONBAR_SHOWGRID")
	Module.fadeParent:RegisterEvent("ACTIONBAR_HIDEGRID")
	Module.fadeParent:SetScript("OnEvent", Module.FadeParent_OnEvent)

	Module:UpdateFaderSettings()
	Module:UpdateFaderState()
	-- Module:SetupLABFlyout()
end
