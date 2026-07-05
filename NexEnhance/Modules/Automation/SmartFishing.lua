--[[
	NexEnhance - Smart Fishing
	-------------------------------------------------------------------------
	While the fishing channel is active: widen soft-target interact CVars, mute
	music/ambience, and override-bind the fishing action-bar key to INTERACTTARGET
	for one-key bobber looting. Restores everything on channel stop, combat, or
	logout. Hold Shift when casting to skip. Blizzard fishing spell IDs from FrameXML.

	Verified against Resources 12.0.7: UNIT_SPELLCAST_SENT, ActionButtonUtil,
	SetOverrideBinding, SoftTarget* CVars.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local L = ns.L

local CreateFrame = CreateFrame
local GetActionInfo = GetActionInfo
local GetBindingKey = GetBindingKey
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local IsShiftKeyDown = IsShiftKeyDown
local RegisterStateDriver = RegisterStateDriver
local SetOverrideBinding = SetOverrideBinding
local ClearOverrideBindings = ClearOverrideBindings
local UnregisterStateDriver = UnregisterStateDriver
local C_Timer_After = C_Timer.After
local C_CVar_GetCVar = C_CVar.GetCVar
local C_CVar_SetCVar = C_CVar.SetCVar

local NUM_ACTIONBAR_BUTTONS = NUM_ACTIONBAR_BUTTONS or 12
local ActionBarButtonNames = ActionButtonUtil and ActionButtonUtil.ActionBarButtonNames

ns:RegisterDefaults({
	smartFishing = {
		enable = true,
	},
})

local SmartFishing = ns:NewModule("SmartFishing", "smartFishing", { group = "automation", title = L["Smart Fishing"], order = 35 })

-- Cast / channel spell IDs (retail fishing and fishing-adjacent activities).
local FISHING_SPELLS = {
	[131474] = true,
	[131476] = true,
	[131490] = true,
	[295727] = true, -- Compressed Ocean Fishing (audio profile)
	[377895] = true, -- Ice Fishing
	[405274] = true, -- Zskera cauldron
	[463743] = true, -- Anniversary secret fishing
	[1224771] = true, -- Void Hole Fishing
	[1239040] = true, -- Den of Nalorakk objective
}

local FISHING_CVARS = {
	Sound_EnableSFX = "1",
	Sound_MasterVolume = "1",
	Sound_MusicVolume = "0",
	Sound_AmbienceVolume = "0",
	Sound_SFXVolume = "1",
	SoftTargetInteract = "3",
	SoftTargetInteractArc = "2",
	SoftTargetInteractRange = "30",
	SoftTargetIconInteract = "1",
	SoftTargetIconGameObject = "1",
}

local handler = CreateFrame("Frame", nil, nil, "SecureHandlerStateTemplate")
handler:SetAttribute("_onstate-combat", [[
	if newstate == "clear" then
		self:ClearBindings()
	end
]])

local storedCVars = {}
local activeFishingSpell
local sentWrapper, channelStartWrapper, channelStopWrapper, logoutWrapper

local function RestoreCVars()
	for name, value in pairs(storedCVars) do
		C_CVar_SetCVar(name, value)
		storedCVars[name] = nil
	end
end

local function ClearFishingBindings()
	C_Timer_After(0, function()
		if handler then
			ClearOverrideBindings(handler)
			UnregisterStateDriver(handler, "combat")
		end
	end)
end

local function OnLogoutRestore()
	RestoreCVars()
end

local function StopSmartFishing()
	RestoreCVars()
	ClearFishingBindings()
	activeFishingSpell = nil
	if channelStopWrapper then
		ns:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", channelStopWrapper)
		channelStopWrapper = nil
	end
	if logoutWrapper then
		ns:UnregisterEvent("PLAYER_LOGOUT", logoutWrapper)
		logoutWrapper = nil
	end
end

local function ApplyOverrideBindings()
	if not activeFishingSpell or not ActionBarButtonNames or InCombatLockdown() then
		return
	end

	for i = 1, #ActionBarButtonNames do
		local barName = ActionBarButtonNames[i]
		for index = 1, NUM_ACTIONBAR_BUTTONS do
			local button = _G[barName .. index]
			if button and button.action then
				local _, actionID = GetActionInfo(button.action)
				if actionID == activeFishingSpell and button.bindingAction then
					local key1, key2 = GetBindingKey(button.bindingAction)
					if key1 then
						SetOverrideBinding(handler, true, key1, "INTERACTTARGET")
					end
					if key2 then
						SetOverrideBinding(handler, true, key2, "INTERACTTARGET")
					end
				end
			end
		end
	end

	RegisterStateDriver(handler, "combat", "[combat] clear; nothing")
end

local function ApplyFishingCVars()
	for name, value in pairs(FISHING_CVARS) do
		if storedCVars[name] == nil then
			storedCVars[name] = C_CVar_GetCVar(name)
		end
		C_CVar_SetCVar(name, value)
	end
end

local function OnChannelStop(_, _, _, spellID)
	if FISHING_SPELLS[spellID] then
		StopSmartFishing()
		return true
	end
end

local function OnChannelStart(_, _, _, spellID)
	if not ns.db.smartFishing.enable or IsShiftKeyDown() or InCombatLockdown() then
		return
	end
	if not FISHING_SPELLS[spellID] then
		return
	end

	ApplyFishingCVars()
	ApplyOverrideBindings()

	if not channelStopWrapper then
		channelStopWrapper = SmartFishing:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", OnChannelStop, "player")
	end
	if not logoutWrapper then
		logoutWrapper = ns:RegisterEvent("PLAYER_LOGOUT", OnLogoutRestore)
	end
end

local function OnSpellSent(_, _, _, spellID)
	if spellID and FISHING_SPELLS[spellID] then
		activeFishingSpell = spellID
	end
end

function SmartFishing:OnEnable()
	if not ns.db.smartFishing.enable then
		return
	end
	if not sentWrapper then
		sentWrapper = self:RegisterUnitEvent("UNIT_SPELLCAST_SENT", OnSpellSent, "player")
	end
	if not channelStartWrapper then
		channelStartWrapper = self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", OnChannelStart, "player")
	end
end

function SmartFishing:OnDisable()
	if sentWrapper then
		ns:UnregisterEvent("UNIT_SPELLCAST_SENT", sentWrapper)
		sentWrapper = nil
	end
	if channelStartWrapper then
		ns:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_START", channelStartWrapper)
		channelStartWrapper = nil
	end
	StopSmartFishing()
end

function SmartFishing:OnSettingChanged(key, value)
	if key == "enable" then
		if value then
			self:OnEnable()
		else
			self:OnDisable()
		end
	end
end

function SmartFishing:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Smart Fishing"], L["While fishing: widen soft-target interact, mute ambience, and rebind your fishing button key to interact with the bobber. Hold Shift when casting to skip."])
end
