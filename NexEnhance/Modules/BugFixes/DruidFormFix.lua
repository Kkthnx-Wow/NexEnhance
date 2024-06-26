local _, Module = ...

local _, _, classID = UnitClass("player")
if classID ~= 11 then
	return
end

-- Constants
local SPELL_MOONKIN_FORM = 24858
-- local GLYPH_SPELL_ID = 114301
local CHARACTER_SHEET_MODEL_SCENE_ID = 595
local CAMERA_TRANSITION_TYPE_IMMEDIATE = 1
local CAMERA_MODIFICATION_TYPE_MAINTAIN = 2

-- Variables
local IS_USING_GLYPH = false
local LAST_FORM_ID = nil
local MODULE_ENABLED = false
local HAS_HOOK = false

-- Cached functions
local GetShapeshiftFormID = GetShapeshiftFormID
local ModelScene = CharacterModelScene

local function ShowRegularModel()
	ModelScene:ReleaseAllActors()
	ModelScene:TransitionToModelSceneID(CHARACTER_SHEET_MODEL_SCENE_ID, CAMERA_TRANSITION_TYPE_IMMEDIATE, CAMERA_MODIFICATION_TYPE_MAINTAIN, true)
	local actor = ModelScene:GetPlayerActor()
	if actor then
		local _, inAlternateForm = C_PlayerInfo.GetAlternateFormInfo()
		local sheatheWeapon = GetSheathState() == 1
		local autodress = true
		local hideWeapon = false
		local useNativeForm = not inAlternateForm
		actor:SetModelByUnit("player", sheatheWeapon, autodress, hideWeapon, useNativeForm)
		actor:SetAnimationBlendOperation(0)
		return actor
	end
end

local function ShowAstralModel()
	local actor = ShowRegularModel()
	if actor then
		actor:SetSpellVisualKit(23368, false)
		actor:SetSpellVisualKit(27440, false)
	end
end

local function UpdatePlayerModel()
	if not MODULE_ENABLED then
		return
	end

	local form = GetShapeshiftFormID()
	if not (form == 31 and IS_USING_GLYPH) then
		return
	end

	ShowAstralModel()
end

local EventListener = CreateFrame("Frame")

EventListener:RegisterEvent("PLAYER_ENTERING_WORLD")
EventListener:RegisterEvent("USE_GLYPH")

EventListener:SetScript("OnEvent", function(self, event, ...)
	if event == "PLAYER_ENTERING_WORLD" or event == "USE_GLYPH" then
		if event == "PLAYER_ENTERING_WORLD" then
			self:UnregisterEvent(event)
		end
		IS_USING_GLYPH = HasAttachedGlyph(SPELL_MOONKIN_FORM)
	elseif event == "UPDATE_SHAPESHIFT_FORM" then
		local newForm = GetShapeshiftFormID()
		if (not IS_USING_GLYPH) or (newForm == LAST_FORM_ID) then
			return
		end

		if newForm == nil and LAST_FORM_ID == 31 then
			ShowRegularModel()
		elseif newForm == 31 and LAST_FORM_ID == nil then
			ShowAstralModel()
		end

		LAST_FORM_ID = newForm
	end
end)

local function HookFunctions()
	if PaperDollFrame_SetPlayer and ModelScene then
		hooksecurefunc("PaperDollFrame_SetPlayer", UpdatePlayerModel)
	end

	if PaperDollFrame then
		if PaperDollFrame:GetScript("OnShow") then
			PaperDollFrame:HookScript("OnShow", function()
				EventListener:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
				LAST_FORM_ID = GetShapeshiftFormID()
			end)
		end

		if PaperDollFrame:GetScript("OnHide") then
			PaperDollFrame:HookScript("OnHide", function()
				EventListener:UnregisterEvent("UPDATE_SHAPESHIFT_FORM")
			end)
		end
	end
end

function Module:EnableModule(state)
	if state then
		if not HAS_HOOK then
			HAS_HOOK = true
			HookFunctions()
		end
		MODULE_ENABLED = true
	else
		MODULE_ENABLED = false
	end
end
