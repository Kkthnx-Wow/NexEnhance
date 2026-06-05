--[[
	NexEnhance - Blizzard Fixes
	-------------------------------------------------------------------------
	A grab-bag of small, always-on workarounds for default UI bugs. These have
	no options - they just patch broken behaviour.

	Ported from NDui's Modules/Misc/BlizzFix.lua (by siweia), minus the NDui
	title/logo handling. The mover-dependent taint fixes (Collections /
	Professions CreateMF) are intentionally omitted - NexEnhance uses its own
	DragEmAll system instead of NDui's mover.
--]]

-- luacheck: globals AddonTooltip_Update GuildNewsButton_OnEnter SetTooltipMoney BackdropTemplateMixin PlayerTalentFrame TalentFrame_LoadUI
-- luacheck: read_globals GetCoinTextureString
-- Legacy/secret-context globals the Lua Language Server doesn't model.
---@diagnostic disable: undefined-global, undefined-field, deprecated
local _, ns = ...
local F = ns.F

local _G = _G
local hooksecurefunc = hooksecurefunc
local InCombatLockdown = InCombatLockdown
local GetCoinTextureString = GetCoinTextureString
local C_AddOns = C_AddOns

local BlizzFix = ns:NewModule("BlizzFix", "blizzFix")

-- ---------------------------------------------------------------------------
-- Fix: stop ACTIVE_TALENT_GROUP_CHANGED spam from the (legacy) talent frame.
-- No-op on modern clients where neither global exists.
-- ---------------------------------------------------------------------------
local function FixTalentEvent()
	if PlayerTalentFrame then
		PlayerTalentFrame:UnregisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
	elseif TalentFrame_LoadUI then
		hooksecurefunc("TalentFrame_LoadUI", function()
			if PlayerTalentFrame then
				PlayerTalentFrame:UnregisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
			end
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Fix: AddonList tooltip errors on header/blank rows (GetID() < 1).
-- ---------------------------------------------------------------------------
local function FixAddonTooltip()
	if type(AddonTooltip_Update) ~= "function" then return end
	local orig = AddonTooltip_Update
	AddonTooltip_Update = function(owner)
		if not owner then return end
		if owner.GetID and owner:GetID() < 1 then return end
		orig(owner)
	end
end

-- ---------------------------------------------------------------------------
-- Fix: guild news hyperlink error on entries with no whatText.
-- ---------------------------------------------------------------------------
local function FixGuildNews()
	if type(GuildNewsButton_OnEnter) ~= "function" then return end
	local orig = GuildNewsButton_OnEnter
	GuildNewsButton_OnEnter = function(self)
		if not (self.newsInfo and self.newsInfo.whatText) then return end
		orig(self)
	end
end

-- ---------------------------------------------------------------------------
-- Fix: click a legacy raid-group button to target that unit.
-- SetAttribute is blocked in combat, so this is deferred when locked down.
-- ---------------------------------------------------------------------------
local function FixRaidGroupButtons()
	for i = 1, 40 do
		local bu = _G["RaidGroupButton" .. i]
		if bu and bu.unit and not bu.clickFixed then
			bu:SetAttribute("type", "target")
			bu:SetAttribute("unit", bu.unit)
			bu.clickFixed = true
		end
	end
end

-- ---------------------------------------------------------------------------
-- Fix: guard backdrop texture setup against secret width values (12.0).
-- ---------------------------------------------------------------------------
local function FixBackdropSecret()
	local mixin = BackdropTemplateMixin
	if not mixin or type(mixin.SetupTextureCoordinates) ~= "function" then return end
	local orig = mixin.SetupTextureCoordinates
	function mixin:SetupTextureCoordinates()
		if F.IsSecret(self:GetWidth()) then return end
		orig(self)
	end
end

-- ---------------------------------------------------------------------------
-- Fix: money tooltip prefix/suffix spacing.
-- ---------------------------------------------------------------------------
local function FixTooltipMoney()
	SetTooltipMoney = function(frame, money, _, prefixText, suffixText)
		frame:AddLine((prefixText or "") .. " " .. GetCoinTextureString(money) .. " " .. (suffixText or ""), 1, 1, 1)
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function BlizzFix:SetupRaidFix()
	if InCombatLockdown() then
		self.pendingRaid = true
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
	else
		FixRaidGroupButtons()
	end
end

function BlizzFix:PLAYER_REGEN_ENABLED()
	if self.pendingRaid then
		self.pendingRaid = nil
		FixRaidGroupButtons()
	end
end

function BlizzFix:ADDON_LOADED(addon)
	if addon == "Blizzard_GuildUI" then
		FixGuildNews()
	elseif addon == "Blizzard_RaidUI" then
		self:SetupRaidFix()
	end
end

function BlizzFix:OnEnable()
	FixTalentEvent()
	FixAddonTooltip()
	FixBackdropSecret()
	FixTooltipMoney()

	-- LoadOnDemand UIs may already be present; otherwise wait for them.
	local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
	if isLoaded then
		if isLoaded("Blizzard_GuildUI") then FixGuildNews() end
		if isLoaded("Blizzard_RaidUI") then self:SetupRaidFix() end
	end

	self:RegisterEvent("ADDON_LOADED")
end
