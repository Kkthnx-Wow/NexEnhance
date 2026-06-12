--[[
	NexEnhance - Hide Help Tips
	-------------------------------------------------------------------------
	Suppresses Blizzard's tutorial / help-tip clutter (the yellow speech-bubble
	pop-ups raised through the HelpTip system - micro-button alerts, new-player
	pointers, panel "did you know" nudges, etc.) plus the in-game tutorial
	triggers behind the showTutorials CVars.

	  * Post-hooks HelpTip:Show and acknowledges every freshly shown tip, which
	    both hides it and marks it seen so it never returns.
	  * Sweeps any tips already active when the feature is switched on (e.g. the
	    ones that pop on login before our hook is installed).
	  * Whitelists NexEnhance's own HelpTips (currently the low-durability
	    nudge) by their text, so our intentional tips are left alone.

	Defaulted OFF and lives under General. Because hooksecurefunc can't be
	removed, the hook is gated by an `active` flag so the toggle works live; the
	tutorial CVars are restored to Blizzard's defaults when disabled.

	No Secret-value concerns: this is purely tutorial UI and touches no combat
	data.

	Inspired by NDui's M:HideBlizzHelpTip (by siweia), extended to cover the
	wider help surface and to spare our own tips.
--]]

local _, ns = ...
local L = ns.L

local hooksecurefunc = hooksecurefunc
local pcall = pcall
local C_Timer_After = C_Timer.After
local SetCVar = SetCVar

ns:RegisterDefaults({
	hideHelpTips = {
		enable = false,
	},
})

local HideHelpTips = ns:NewModule("HideHelpTips", "hideHelpTips", { group = "general", title = L["Hide Help Tips"], order = 40 })

-- HelpTips NexEnhance raises on purpose, keyed by their text. These are skipped
-- so the feature only quiets Blizzard's noise, not our own nudges. The static
-- list below is augmented at runtime by ns.OwnHelpTips, which F.ShowHelpTip
-- fills in as one-shot tips are raised.
local WHITELIST = {
	[L["DurabilityHelpTip"]] = true,
}

-- True when `text` is one of NexEnhance's intentional tips (static or dynamic).
local function IsOwnTip(text)
	if not text then
		return false
	end
	if WHITELIST[text] then
		return true
	end
	return ns.OwnHelpTips ~= nil and ns.OwnHelpTips[text] == true
end

-- Tutorial CVars we force off; restored to Blizzard's default ("1") on disable.
local TUTORIAL_CVARS = { "showTutorials", "showNPETutorials" }

local active = false
local hooked = false

-- Hide + permanently acknowledge every active, non-whitelisted HelpTip.
local function AcknowledgeAll()
	if not active then
		return
	end

	local HelpTip = _G.HelpTip
	local pool = HelpTip and HelpTip.framePool
	if not pool then
		return
	end

	for frame in pool:EnumerateActive() do
		local info = frame.info
		if not (info and IsOwnTip(info.text)) then
			frame:Acknowledge()
		end
	end
end

local function SetTutorialCVars(value)
	for i = 1, #TUTORIAL_CVARS do
		-- pcall so a CVar renamed/removed in a future patch can't error us out.
		pcall(SetCVar, TUTORIAL_CVARS[i], value)
	end
end

local function InstallHooks()
	if hooked then
		return
	end
	local HelpTip = _G.HelpTip
	if not HelpTip then
		return
	end
	hooked = true

	-- Post-hook: any tip Blizzard shows is acknowledged away immediately.
	hooksecurefunc(HelpTip, "Show", AcknowledgeAll)
end

local function Activate()
	active = true
	InstallHooks()
	SetTutorialCVars("0")

	-- Clear what's already up, then sweep once more after login settles (some
	-- tips queue a frame or two after PLAYER_LOGIN).
	AcknowledgeAll()
	C_Timer_After(1, AcknowledgeAll)
end

local function Deactivate()
	active = false
	SetTutorialCVars("1")
end

function HideHelpTips:OnEnable()
	Activate()
end

function HideHelpTips:OnSettingChanged(key, value)
	if key ~= "enable" then
		return
	end
	if value then
		Activate()
	else
		Deactivate()
	end
end

function HideHelpTips:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Hide Help Tips"], L["Suppress Blizzard's tutorial and help-tip pop-ups (micro-button alerts, new-player pointers, panel hints). NexEnhance's own tips are kept."])
end
