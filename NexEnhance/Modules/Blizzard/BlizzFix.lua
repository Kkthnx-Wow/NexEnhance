--[[
	NexEnhance - Blizzard Fixes
	-------------------------------------------------------------------------
	A grab-bag of small, always-on workarounds for default UI bugs. These have
	no options - they just patch broken behaviour.

	Mover-dependent taint fixes (Collections / Professions CreateMF) are omitted —
	we use DragEmAll instead.
--]]

-- Legacy/secret-context globals the Lua Language Server doesn't model.
---@diagnostic disable: undefined-global, undefined-field, deprecated
local _, ns = ...

local _G = _G
local InCombatLockdown = InCombatLockdown
local C_AddOns = C_AddOns

local BlizzFix = ns:NewModule("BlizzFix", "blizzFix")

-- ---------------------------------------------------------------------------
-- Fix: AddonList tooltip errors on header/blank rows (GetID() < 1).
-- Wrapping the global AddonTooltip_Update tainted the mixin OnEnter path;
-- guard at the mixin call site instead.
-- ---------------------------------------------------------------------------
local function GuardAddonListTooltipMixin(mixin)
	if not mixin or mixin.nexAddonTooltipGuard or type(mixin.OnEnter) ~= "function" then
		return
	end

	local origOnEnter = mixin.OnEnter
	function mixin:OnEnter(...)
		if not self then
			return
		end
		if self.GetID and self:GetID() < 1 then
			return
		end
		return origOnEnter(self, ...)
	end

	mixin.nexAddonTooltipGuard = true
end

local function FixAddonTooltip()
	GuardAddonListTooltipMixin(_G["AddonListEntryMixin"])
	GuardAddonListTooltipMixin(_G["AddonListCategoryMixin"])
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
-- Fix: PetFrame's clickable area is slightly too tall/offset on Midnight.
-- BetterBlizzFrames tightens the hit rect instead of moving the protected
-- frame, which avoids managed-frame taint.
-- ---------------------------------------------------------------------------
local function FixPetFrameClickArea()
	local petFrame = _G["PetFrame"]
	if petFrame and petFrame.SetHitRectInsets then
		petFrame:SetHitRectInsets(0, 0, 1, 5)
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
	if addon == "Blizzard_AddOnList" then
		FixAddonTooltip()
	elseif addon == "Blizzard_RaidUI" then
		self:SetupRaidFix()
	end
end

function BlizzFix:OnEnable()
	FixPetFrameClickArea()

	-- LoadOnDemand UIs may already be present; otherwise wait for them.
	local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
	if isLoaded then
		if isLoaded("Blizzard_AddOnList") then
			FixAddonTooltip()
		end
		if isLoaded("Blizzard_RaidUI") then
			self:SetupRaidFix()
		end
	end

	self:RegisterEvent("ADDON_LOADED")
end
