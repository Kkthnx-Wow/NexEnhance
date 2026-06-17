--[[
	NexEnhance - Hide UI Elements
	-------------------------------------------------------------------------
	Optional toggles for default UI bits people often want gone. Everything
	here is OFF by default and only changes visibility - nothing is destroyed,
	so the elements return on reload (or immediately, where we can restore them).

	  * Aura collapse arrow: the little collapse/expand chevron Blizzard parks
	    next to the buffs (BuffFrame.CollapseAndExpandButton). Blizzard re-shows
	    it from RefreshConsolidationFrameVisibility whenever buffs change, so we
	    keep it hidden with an OnShow re-hide gated on the live toggle. Only the
	    BuffFrame carries this button today; the DebuffFrame entry is guarded so
	    it simply no-ops if Blizzard never adds one.

	  * Micro Menu & Bags: the bottom-right cluster. In current retail this is
	    two separate Edit Mode systems (MicroMenuContainer + BagsBar), not the
	    legacy MicroButtonAndBagsBar anchor frame, so we hide both. The bag
	    buttons can be protected, so hides are deferred out of combat, and an
	    OnShow re-hide keeps Edit Mode from bringing them back.

	  * Portrait combat text: the damage/healing numbers that flash over the
	    PlayerFrame portrait (PlayerFrame...HitIndicator.HitText, driven by
	    CombatFeedback_OnCombatEvent on UNIT_COMBAT). The text is a FontString,
	    not a frame, so we post-hook the global CombatFeedback_OnCombatEvent and
	    re-hide it for the player after Blizzard shows it. HEAL is the "healing"
	    toggle; everything else (WOUND/BLOCK/IMMUNE/ENERGIZE/misses) is "damage".
	    Only the PlayerFrame and PetFrame carry this in modern retail - the target
	    frame has no combat feedback - so there is nothing to toggle there.

	No Secret-value concerns: this is visibility only. The combat-feedback hook
	only reads the event name Blizzard passes us, never any unit/combat amount.
--]]

local _, ns = ...
local L = ns.L

local _G = _G
local type = type
local ipairs = ipairs
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc

ns:RegisterDefaults({
	hideUIElements = {
		auraCollapse = false,
		microBags = false,
		portraitDamage = false,
		portraitHealing = false,
	},
})

local Module = ns:NewModule("HideUIElements", "hideUIElements", { group = "general", title = L["Hide UI Elements"], order = 41 })

-- ---------------------------------------------------------------------------
-- Aura collapse arrow
-- ---------------------------------------------------------------------------
local AURA_FRAMES = { "BuffFrame", "DebuffFrame" }

-- Re-hide whenever Blizzard shows the chevron, but only while the toggle is on
-- so disabling hands visibility straight back to Blizzard. Not combat-gated:
-- the aura chevron is a plain CheckButton, not a protected frame.
local function KeepArrowHidden(button)
	if Module.hideAuraCollapse then
		button:Hide()
	end
end

local function ApplyAuraCollapse()
	for _, name in ipairs(AURA_FRAMES) do
		local frame = _G[name]
		local button = frame and frame.CollapseAndExpandButton
		if button then
			if not button.nexArrowHooked then
				button.nexArrowHooked = true
				button:HookScript("OnShow", KeepArrowHidden)
			end
			if Module.hideAuraCollapse then
				button:Hide()
			elseif frame.RefreshConsolidationFrameVisibility then
				-- Let Blizzard recompute the correct shown state right away.
				frame:RefreshConsolidationFrameVisibility()
			else
				button:Show()
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Micro Menu & Bags
-- ---------------------------------------------------------------------------
local MICRO_FRAMES = { "MicroMenuContainer", "BagsBar" }

-- Edit Mode (or a layout pass) re-shows these; keep them hidden while the toggle
-- is on. Defer in combat: the bag buttons can be protected, so we never Hide()
-- mid-lockdown and instead flush on PLAYER_REGEN_ENABLED.
local function KeepMicroHidden(frame)
	if not Module.hideMicroBags then
		return
	end
	if InCombatLockdown() then
		Module.pendingMicroBags = true
	else
		frame:Hide()
	end
end

local function ApplyMicroBags()
	if InCombatLockdown() then
		Module.pendingMicroBags = true
		return
	end

	local hide = Module.hideMicroBags
	for _, name in ipairs(MICRO_FRAMES) do
		local frame = _G[name]
		if frame then
			if not frame.nexMicroHooked then
				frame.nexMicroHooked = true
				frame:HookScript("OnShow", KeepMicroHidden)
			end
			if hide then
				frame:Hide()
			else
				frame:Show()
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Player portrait combat text (incoming damage / healing numbers)
-- ---------------------------------------------------------------------------
-- Post-hook of the global feedback driver. Blizzard's function ends by Show()ing
-- self.feedbackText; we hide it again for the player when the matching toggle is
-- on. HEAL is healing; every other event (damage, misses, blocks, energize) is
-- treated as damage/combat text. Filtered to PlayerFrame so the pet keeps its own.
local function OnCombatFeedback(self, event)
	if self ~= _G.PlayerFrame then
		return
	end
	local hide = (event == "HEAL") and Module.hidePortraitHealing or (event ~= "HEAL") and Module.hidePortraitDamage
	if hide and self.feedbackText then
		self.feedbackText:Hide()
	end
end

local function InstallPortraitHook()
	if Module.portraitHooked then
		return
	end
	if type(_G.CombatFeedback_OnCombatEvent) == "function" then
		Module.portraitHooked = true
		hooksecurefunc("CombatFeedback_OnCombatEvent", OnCombatFeedback)
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function Module:PLAYER_REGEN_ENABLED()
	if self.pendingMicroBags then
		self.pendingMicroBags = nil
		ApplyMicroBags()
	end
end

function Module:OnEnable()
	self.hideAuraCollapse = ns.db.hideUIElements.auraCollapse
	self.hideMicroBags = ns.db.hideUIElements.microBags
	self.hidePortraitDamage = ns.db.hideUIElements.portraitDamage
	self.hidePortraitHealing = ns.db.hideUIElements.portraitHealing

	ApplyAuraCollapse()
	ApplyMicroBags()
	InstallPortraitHook()

	-- Only needed to flush a combat-deferred micro/bags hide.
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function Module:OnSettingChanged(key)
	self.hideAuraCollapse = ns.db.hideUIElements.auraCollapse
	self.hideMicroBags = ns.db.hideUIElements.microBags
	self.hidePortraitDamage = ns.db.hideUIElements.portraitDamage
	self.hidePortraitHealing = ns.db.hideUIElements.portraitHealing

	if key == "auraCollapse" then
		ApplyAuraCollapse()
	elseif key == "microBags" then
		ApplyMicroBags()
	elseif key == "portraitDamage" or key == "portraitHealing" then
		-- The hook reads the live flags; nothing to re-apply (numbers reappear
		-- on the next combat event once a toggle is turned off).
		InstallPortraitHook()
	end
end

function Module:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "auraCollapse", L["Hide Aura Collapse Arrow"], L["Hide the collapse/expand arrow that sits next to your buffs."])
	builder:Checkbox(category, self, "microBags", L["Hide Micro Menu & Bags"], L["Hide the micro-menu buttons and the bag bar in the bottom-right (open them with keybinds). Reload to fully restore."])
	builder:Checkbox(category, self, "portraitDamage", L["Hide Portrait Damage Text"], L["Hide the incoming damage numbers that flash over your player portrait."])
	builder:Checkbox(category, self, "portraitHealing", L["Hide Portrait Healing Text"], L["Hide the incoming healing numbers that flash over your player portrait."])
end
