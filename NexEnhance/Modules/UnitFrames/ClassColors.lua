--[[
	NexEnhance - ClassColors
	-------------------------------------------------------------------------
	Re-colours the health bars of the default Blizzard unit frames:
	  * players -> their class colour;
	  * NPCs    -> their reaction colour (hostile red, neutral yellow, friendly
	               green), matching F.UnitColor and Blizzard's reaction strip.
	Covered frames: player, pet, target, target-of-target, focus, focus-target,
	the raid boss frames (Boss1..Boss5), party and the raid-style/compact frames.

	Why NPCs needed fixing: the default atlas health bar is GREEN for everyone
	(target/focus/boss bars all share "UI-HUD-UnitFrame-Target-...-Bar-Health",
	a green texture). Blizzard only shows reaction on the small ReputationColor
	strip + portrait, so a hostile boss still has a GREEN main bar. We tint the
	main bar by reaction so hostile units read red, neutral yellow, etc.

	How it works (researched from BlizzardInterfaceCode):
	  * Dragonflight+ HUD health bars (player, target, focus, boss, party, pet)
	    set `lockColor = true` on load and keep `SetStatusBarColor(1,1,1)`; the
	    green look is baked into the BarTexture atlas. We must NOT bail on
	    lockColor. Instead use StatusBar:SetStatusBarDesaturated(true) then
	    SetStatusBarColor(rgb) so the atlas greyscales and tints correctly.
	  * We post-hook `UnitFrameHealthBar_Update` and Target/Focus/Boss
	    `CheckClassification` (which re-applies the health atlas and would
	    otherwise undo our tint).
	  * Target/Focus also carry a `ReputationColor` strip (the small bar under
	    the name). Blizzard tints it with `UnitSelectionColor` (reaction green,
	    hostile red, NPC rep, etc.) inside `CheckFaction`. See TargetFrameLayout
	    for optional player-style strip/name tweaks.
	  * Compact frames (raid-style party / raid / arena) colour through
	    `CompactUnitFrame_UpdateHealthColor(frame)`. Their bars use a plain
	    texture, so no desaturation is needed - just SetStatusBarColor. We skip
	    nameplates (forbidden / secret healthBar) and defer to Blizzard when
	    threat-colouring is enabled on the frame.

	hooksecurefunc is used for both, so we never taint the secure unit buttons.
	SetStatusBarColor / SetStatusBarDesaturated accept tainted callers (12.0+).

	Patch 12.0 "Secret Values" (the bit that was breaking us):
	  When a unit's identity is restricted (in combat, instances, etc.) the
	  identity APIs -- UnitIsPlayer / UnitIsConnected / UnitClass -- hand back
	  *secret* values. Tainted addon code is NOT allowed to run a boolean test
	  or comparison on a secret boolean, so `if not UnitIsPlayer(unit)` throws
	  "attempt to ... a secret value", which silently aborted our hook and left
	  the bar Blizzard-green. We now probe each result with F.IsSecret and
	  bail (leaving Blizzard's colour) whenever the answer is secret. Player and
	  group members are never identity-restricted, so they always colour; an
	  arbitrary target/focus colours out of combat and falls back in combat.
--]]

local _, ns = ...
local F, L = ns.F, ns.L

-- Localised globals.
local _G = _G
local UnitClass = UnitClass
local UnitIsPlayer = UnitIsPlayer
local UnitIsConnected = UnitIsConnected
local UnitReaction = UnitReaction
local UnitThreatSituation = UnitThreatSituation
local UnitTreatAsPlayerForDisplay = UnitTreatAsPlayerForDisplay
local hooksecurefunc = hooksecurefunc
local ipairs = ipairs
local strfind = string.find

local FACTION_BAR_COLORS = _G["FACTION_BAR_COLORS"]

-- Shared secret-value gate (Core/Functions.lua). It accepts any value and never
-- errors, so it is safe to call before we branch on a possibly-secret result.
local IsSecret = F.IsSecret

local CLASS_COLORS = _G["CUSTOM_CLASS_COLORS"] or RAID_CLASS_COLORS

ns:RegisterDefaults({
	classColors = {
		enable = true,
	},
})

local ClassColors = ns:NewModule("ClassColors", "classColors", { group = "unitframes", title = L["Class Colours"], order = 10 })

-- Returns the class colour for a unit, or nil if it should keep Blizzard's
-- default colour (NPC, disconnected, classless, or identity-restricted/secret).
-- Each identity read is gated by F.IsSecret *before* we boolean-test it,
-- so this never errors on a secret value under tainted execution.
local function GetPlayerClassColor(unit)
	if not unit then
		return nil
	end

	local isPlayer = UnitIsPlayer(unit)
	if IsSecret(isPlayer) then
		return nil
	end
	if not isPlayer then
		local treatAsPlayer = UnitTreatAsPlayerForDisplay and UnitTreatAsPlayerForDisplay(unit)
		if IsSecret(treatAsPlayer) or not treatAsPlayer then
			return nil
		end
	end

	local connected = UnitIsConnected(unit)
	if IsSecret(connected) or not connected then
		return nil
	end

	local _, class = UnitClass(unit)
	if IsSecret(class) or not class then
		return nil
	end

	return CLASS_COLORS[class] or nil
end

-- Resolve the health-bar tint for a unit: class colour for players, reaction
-- colour (hostile red / neutral yellow / friendly green) for NPCs - matching
-- F.UnitColor and Blizzard's own reaction strip. Returns r, g, b, or nil when
-- it cannot decide (classless, disconnected, or identity-restricted/secret) so
-- the caller can fall back to Blizzard's default atlas instead of guessing.
-- Every identity read is gated by F.IsSecret before it is boolean-tested.
local function GetUnitHealthColor(unit)
	if not unit then
		return nil
	end

	local isPlayer = UnitIsPlayer(unit)
	if IsSecret(isPlayer) then
		return nil
	end

	if isPlayer then
		local connected = UnitIsConnected(unit)
		if IsSecret(connected) or not connected then
			return nil
		end
		local _, class = UnitClass(unit)
		if IsSecret(class) or not class then
			return nil
		end
		local color = CLASS_COLORS[class]
		if color then
			return color.r, color.g, color.b
		end
		return nil
	end

	-- Non-player: reaction colour. Leave the default atlas if we have no
	-- reaction table or the reaction is secret/unknown.
	if not FACTION_BAR_COLORS then
		return nil
	end
	local reaction = UnitReaction(unit, "player")
	if IsSecret(reaction) or not reaction then
		return nil
	end
	local color = FACTION_BAR_COLORS[reaction]
	if color then
		return color.r, color.g, color.b
	end
	return nil
end

-- Atlas HUD bars use lockColor so Blizzard skips SetStatusBarColor in
-- UnitFrameHealthBar_Update; the visible green is the atlas at multiply 1,1,1.
local HUD_DEFAULT_COLOR = { r = 1, g = 1, b = 1 }

local function ApplyHudHealthColor(statusbar, r, g, b, desaturated)
	if statusbar.SetStatusBarDesaturated then
		statusbar:SetStatusBarDesaturated(desaturated)
	end
	statusbar:SetStatusBarColor(r, g, b)
end

-- ---------------------------------------------------------------------------
-- Standard HUD frames (atlas + lockColor -> StatusBar desaturation API)
-- ---------------------------------------------------------------------------
local function ColorStandardHealth(statusbar, unit)
	if not statusbar then
		return
	end
	if not ns.db.classColors.enable then
		return
	end

	unit = unit or statusbar.unit
	local r, g, b = GetUnitHealthColor(unit)
	if r then
		-- Players -> class colour, NPCs -> reaction colour. Desaturate so the
		-- green atlas greyscales first, then the tint multiplies in correctly.
		ApplyHudHealthColor(statusbar, r, g, b, true)
	else
		-- Identity-restricted / secret / undecidable: restore the saturated
		-- atlas so Blizzard's default green stands instead of a wrong guess.
		ApplyHudHealthColor(statusbar, HUD_DEFAULT_COLOR.r, HUD_DEFAULT_COLOR.g, HUD_DEFAULT_COLOR.b, false)
	end
end

-- ---------------------------------------------------------------------------
-- Compact frames (plain texture -> straight colour, no desaturation)
-- ---------------------------------------------------------------------------
local function ColorCompactHealth(frame)
	if not frame or not ns.db.classColors.enable then
		return
	end

	-- Nameplates also route through CompactUnitFrame_UpdateHealthColor. Their
	-- frames can be forbidden and, on 12.0, their healthBar is handed back as a
	-- secret value, so calling SetStatusBarColor on it throws "bad self". We
	-- only colour the party/raid compact frames, never nameplates.
	if frame.IsForbidden and frame:IsForbidden() then
		return
	end

	local healthBar = frame.healthBar
	if not healthBar or IsSecret(healthBar) then
		return
	end

	local unit = frame.displayedUnit or frame.unit
	if not unit or IsSecret(unit) or strfind(unit, "nameplate") then
		return
	end

	-- Leave Blizzard's aggro/threat tint when the frame has that option enabled
	-- (Edit Mode raid/party frames). Matches CompactUnitFrame_UpdateHealthColor.
	if frame.displayThreatHealthBarColor then
		local threat = UnitThreatSituation(unit)
		if not IsSecret(threat) and threat and threat > 0 then
			return
		end
	end

	local color = GetPlayerClassColor(unit)
	if color then
		healthBar:SetStatusBarColor(color.r, color.g, color.b)
	end
end

-- ---------------------------------------------------------------------------
-- Immediate refresh for the standard frames that exist at login (compact
-- frames refresh themselves continuously, so they need no manual pass).
-- ---------------------------------------------------------------------------
local standardFrames = {
	"PlayerFrame",
	"PetFrame",
	"TargetFrame",
	"FocusFrame",
}

-- Boss frames (Boss1TargetFrame .. Boss5TargetFrame) are BossTargetFrameMixin,
-- built on TargetFrameMixin with unit "boss1".."boss5". They use the SAME
-- atlas health bar + CheckClassification re-skin, so they need the same hooks
-- and the same reaction tint as the target/focus frames. They live in
-- BossTargetFrameContainer.BossTargetFrames and exist (hidden) from login.
local function ForEachBossFrame(callback)
	local container = _G["BossTargetFrameContainer"]
	local frames = container and container.BossTargetFrames
	if not frames then
		return
	end
	for _, frame in ipairs(frames) do
		if frame then
			callback(frame)
		end
	end
end

-- Apply when enabling, restore when disabling. Important: do NOT call back
-- into UnitFrameHealthBar_Update from addon code. That function reads secret
-- health values, and running it under addon-tainted execution can poison
-- statusbar.currValue and break Blizzard's TextStatusBar/OnUpdate paths.
local function RefreshBar(bar)
	if not bar then
		return
	end

	if ns.db.classColors.enable then
		ColorStandardHealth(bar, bar.unit)
	else
		ApplyHudHealthColor(bar, HUD_DEFAULT_COLOR.r, HUD_DEFAULT_COLOR.g, HUD_DEFAULT_COLOR.b, false)
	end
end

function ClassColors:RefreshStandard()
	for i = 1, #standardFrames do
		local frame = _G[standardFrames[i]]
		if frame then
			RefreshBar(frame.healthbar)
			-- Target/Focus carry a target-of-target subframe.
			if frame.totFrame then
				RefreshBar(frame.totFrame.healthbar)
			end
		end
	end

	-- Modern party UI (Dragonflight+).
	local partyFrame = _G["PartyFrame"]
	if partyFrame and partyFrame.PartyMemberFramePool then
		for member in partyFrame.PartyMemberFramePool:EnumerateActive() do
			local bar = member.HealthBarContainer and member.HealthBarContainer.HealthBar
			RefreshBar(bar)
		end
	end

	-- Raid boss frames.
	ForEachBossFrame(function(frame)
		RefreshBar(frame.healthbar)
	end)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

-- Target/Focus rebuild their health-bar atlas inside CheckClassification (and
-- again on UNIT_CLASSIFICATION_CHANGED). SetAtlas resets the texture's
-- desaturation and vertex colour, so it runs *after* our UnitFrameHealthBar_Update
-- hook and wipes the class colour straight back to green. We post-hook the
-- per-frame method so we re-tint immediately after the atlas is reapplied.
local function HookClassification(frame)
	if not frame or frame.nexClassColorHooked then
		return
	end
	if type(frame.CheckClassification) ~= "function" then
		return
	end
	frame.nexClassColorHooked = true
	hooksecurefunc(frame, "CheckClassification", function(f)
		ColorStandardHealth(f.healthbar, f.unit)
	end)
end

-- PartyMemberFrameMixin:UpdateArt() re-applies the HUD health atlas when a
-- member enters/leaves a vehicle (ToPlayerArt / ToVehicleArt). Same pattern as
-- TargetFrameMixin:CheckClassification — hook after the atlas swap so our tint
-- is not left on the wrong texture state.
local function HookPartyUpdateArt()
	local mixin = _G["PartyMemberFrameMixin"]
	if not mixin or mixin.nexClassColorHooked or type(mixin.UpdateArt) ~= "function" then
		return
	end
	mixin.nexClassColorHooked = true
	hooksecurefunc(mixin, "UpdateArt", function(self)
		local container = self.HealthBarContainer
		local bar = container and container.HealthBar
		local unit = self.GetUnit and self:GetUnit() or self.unit
		ColorStandardHealth(bar, unit)
	end)
end

function ClassColors:InstallHooks()
	if self.hooksInstalled then
		return
	end
	self.hooksInstalled = true

	-- Value / max-health / initial updates for every standard bar.
	hooksecurefunc("UnitFrameHealthBar_Update", ColorStandardHealth)

	-- Re-tint after the atlas re-skin on the frames that do it.
	HookClassification(_G["TargetFrame"])
	HookClassification(_G["FocusFrame"])

	-- Boss frames share the TargetFrame atlas + CheckClassification re-skin.
	ForEachBossFrame(function(frame)
		HookClassification(frame)
	end)

	-- Compact (raid-style) frames.
	if _G["CompactUnitFrame_UpdateHealthColor"] then
		hooksecurefunc("CompactUnitFrame_UpdateHealthColor", ColorCompactHealth)
	end

	HookPartyUpdateArt()
end

-- Recolour on the events that change which unit a frame shows, rebuild its
-- skin, or lift combat (identity stops being secret, so target/focus can
-- finally be coloured). Our handler runs after Blizzard's because the default
-- frames registered these events at load, before our PLAYER_LOGIN.
function ClassColors:RefreshEvent()
	self:RefreshStandard()
end

function ClassColors:OnEnable()
	self:InstallHooks()

	self:RegisterEvent("PLAYER_ENTERING_WORLD", "RefreshEvent")
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "RefreshEvent")
	self:RegisterEvent("PLAYER_FOCUS_CHANGED", "RefreshEvent")
	self:RegisterEvent("UNIT_CLASSIFICATION_CHANGED", "RefreshEvent")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "RefreshEvent")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "RefreshEvent")
	-- Reaction tint can change without a retarget (mind control, faction flip).
	self:RegisterEvent("UNIT_FACTION", "RefreshEvent")
	-- Party disconnect/reconnect toggles desaturation alongside health updates.
	self:RegisterEvent("UNIT_CONNECTION", "RefreshEvent")
	-- Boss frames appear mid-fight; refresh when an encounter engages units.
	self:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT", "RefreshEvent")

	self:RefreshStandard()
end

function ClassColors:OnSettingChanged(_, value)
	if value then
		self:InstallHooks()
	end
	-- Re-run the standard pass: enabling applies colours now; disabling
	-- re-saturates the bars (Blizzard restores its own colour on the next tick).
	self:RefreshStandard()
end

function ClassColors:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Class-Coloured Health"], L["Colour unit-frame health bars by class for players and by reaction for NPCs (player, target, focus, boss, party and more)."])
end

-- ---------------------------------------------------------------------------
-- Diagnostics: run  /run NexEnhance:DebugClassColors()  in-game to see exactly
-- what the module sees for each frame (enabled?, hooks installed?, the unit,
-- the colour we computed, the bar's current colour, desaturation, secrets).
-- ---------------------------------------------------------------------------
local function fmt(r, g, b)
	if not r then
		return "nil"
	end
	return string.format("%.2f,%.2f,%.2f", r, g, b)
end

local function DumpFrame(label, frame)
	if not frame then
		ns.F.Print(label, "= <frame missing>")
		return
	end
	local bar = frame.healthbar
	if not bar then
		ns.F.Print(label, "= <healthbar missing>")
		return
	end

	local unit = bar.unit or frame.unit
	local r, g, b = bar:GetStatusBarColor()
	local color = GetPlayerClassColor(unit)
	local isPlayer = unit and UnitIsPlayer(unit)
	local desat = bar.IsStatusBarDesaturated and bar:IsStatusBarDesaturated() or nil
	ns.F.Print(string.format("%s unit=%s lockColor=%s isPlayer=%s secret=%s computed=[%s] barColor=[%s] desat=%s", label, tostring(unit), tostring(bar.lockColor), tostring(IsSecret(isPlayer) and "SECRET" or isPlayer), tostring(IsSecret(isPlayer)), color and fmt(color.r, color.g, color.b) or "nil", fmt(r, g, b), tostring(desat)))
end

function ClassColors:Debug()
	ns.F.Print("ClassColors debug --------------------------------")
	ns.F.Print("enable =", tostring(ns.db and ns.db.classColors and ns.db.classColors.enable))
	ns.F.Print("hooksInstalled =", tostring(self.hooksInstalled))
	ns.F.Print("CLASS_COLORS source =", _G["CUSTOM_CLASS_COLORS"] and "CUSTOM" or "RAID")
	DumpFrame("PlayerFrame", _G["PlayerFrame"])
	DumpFrame("TargetFrame", _G["TargetFrame"])
	DumpFrame("FocusFrame", _G["FocusFrame"])
	ns.F.Print("Forcing a refresh now...")
	self:RefreshStandard()
end

-- Expose a stable entry point for the slash/`/run` diagnostic.
function ns:DebugClassColors()
	local m = ns:GetModule("ClassColors")
	if m then
		m:Debug()
	end
end
