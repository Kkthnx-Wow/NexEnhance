--[[
	NexEnhance - ClassColors
	-------------------------------------------------------------------------
	Re-colours the health bars of the default Blizzard unit frames:
	  * players -> their class colour;
	  * NPCs    -> their reaction colour (hostile red, unfriendly orange, neutral
	               yellow, friendly green). Player pets and other friendly
	               player-controlled units stay green (or class-coloured when
	               available), never hostile NPC reaction.
	Covered frames: player, pet, target, target-of-target, focus, focus-target,
	the raid boss frames (Boss1..Boss5), and the Dragonflight party HUD portraits.
	Offline players: grey desaturated health (via GetUnitHealthColor), plus on
	target/focus/toT/boss HUD frames a desaturated portrait and the standard
	Disconnect-Icon overlay (party portraits already get this from Blizzard).
	Compact raid/party frames (Edit Mode) are left to Blizzard — they already
	expose a "Class Colors" raid-profile option via CompactUnitFrame_UpdateHealthColor.

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

	hooksecurefunc is used for both, so we never taint the secure unit buttons.
	SetStatusBarColor / SetStatusBarDesaturated accept tainted callers (12.0+).

	Patch 12.0: UnitIsPlayer / UnitIsConnected / UnitTreatAsPlayerForDisplay /
	UnitClass classFilename are SecretArguments only (Resources 12.0.7) — plain
	booleans / tokens. Only UnitClass's first return (className) is ConditionalSecret;
	we use the second return (classFilename) without a secret gate.
--]]

local _, ns = ...
local F, L = ns.F, ns.L

-- Localised globals.
local _G = _G
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitIsPlayer = UnitIsPlayer
local UnitIsConnected = UnitIsConnected
local UnitTreatAsPlayerForDisplay = UnitTreatAsPlayerForDisplay
local SetDesaturation = SetDesaturation
local hooksecurefunc = hooksecurefunc
local ipairs = ipairs

local CLASS_COLORS = _G["CUSTOM_CLASS_COLORS"] or RAID_CLASS_COLORS

-- Blizzard uses 0.5 grey for offline bars (UnitFrameHealthBar_Update,
-- CompactUnitFrame_UpdateHealthColor). HUD atlas bars need desaturation too.
local DISCONNECTED_COLOR = { r = 0.5, g = 0.5, b = 0.5 }
local DISCONNECT_ICON = "Interface\\CharacterFrame\\Disconnect-Icon"

ns:RegisterDefaults({
	classColors = {
		enable = true,
	},
})

local ClassColors = ns:NewModule("ClassColors", "classColors", { group = "unitframes", title = L["Class Colours"], order = 10 })

local eventHandles = {}
local eventsRegistered = false

local HUD_REFRESH_UNITS = {
	target = true,
	focus = true,
	pet = true,
}
for i = 1, 4 do
	HUD_REFRESH_UNITS["party" .. i] = true
end
for i = 1, 5 do
	HUD_REFRESH_UNITS["boss" .. i] = true
end

local function IsHUDRefreshUnit(unit)
	return not unit or HUD_REFRESH_UNITS[unit] == true
end

local scheduleRefreshStandard = F.Debounce(0, function()
	if ns.db.classColors.enable then
		ClassColors:RefreshStandard()
	end
end)

-- Returns the class colour for a unit, or DISCONNECTED_COLOR when offline,
-- or nil if it should keep Blizzard's default (NPC / classless).
local function GetPlayerClassColor(unit)
	if not unit then
		return nil
	end

	local isPlayer = UnitIsPlayer(unit)
	if not isPlayer then
		local treatAsPlayer = UnitTreatAsPlayerForDisplay and UnitTreatAsPlayerForDisplay(unit)
		if not treatAsPlayer then
			return nil
		end
	end

	local connected = UnitIsConnected(unit)
	if not connected then
		return DISCONNECTED_COLOR
	end

	local _, class = UnitClass(unit)
	if not class then
		return nil
	end

	return CLASS_COLORS[class] or nil
end

-- Resolve the health-bar tint for a unit: class colour for players, reaction
-- colour for NPCs via F.GetNpcReactionColor (UnitSelectionType/Color category +
-- dark FACTION_BAR palette). Returns r, g, b, or nil when it cannot decide.
local function GetUnitHealthColor(unit)
	if not unit then
		return nil
	end

	local connected = UnitIsConnected(unit)
	if not connected then
		return DISCONNECTED_COLOR.r, DISCONNECTED_COLOR.g, DISCONNECTED_COLOR.b
	end

	if UnitIsPlayer(unit) then
		local _, class = UnitClass(unit)
		if not class then
			return nil
		end
		local color = CLASS_COLORS[class]
		if color then
			return color.r, color.g, color.b
		end
		return nil
	end

	-- Pets/guardians: never run NPC reaction (hostile red) on player-controlled units.
	if F.IsFriendlyControlledUnit(unit) then
		local color = GetPlayerClassColor(unit)
		if color then
			return color.r, color.g, color.b
		end
		local friendly = _G.FACTION_BAR_COLORS and _G.FACTION_BAR_COLORS[5]
		if friendly then
			return friendly.r, friendly.g, friendly.b
		end
		return 0, 1, 0
	end

	local treatAsPlayer = UnitTreatAsPlayerForDisplay and UnitTreatAsPlayerForDisplay(unit)
	if treatAsPlayer then
		local _, class = UnitClass(unit)
		if class then
			local color = CLASS_COLORS[class]
			if color then
				return color.r, color.g, color.b
			end
		end
	end

	return F.GetNpcReactionColor(unit)
end

-- Offline players: party frames use PartyMemberFrameMixin:UpdateOnlineStatus
-- (desaturated portrait + Disconnect-Icon overlay + grey full health bar).
-- Target/focus HUD frames ship without that overlay, so we mirror the party look
-- when Class Colours is enabled. Health tint is handled above; this covers portrait.
local function GetHudPortrait(frame)
	if not frame then
		return nil, nil
	end
	local container = frame.TargetFrameContainer
	if container and container.Portrait then
		return container.Portrait, container
	end
	if frame.Portrait then
		return frame.Portrait, frame
	end
	return nil, nil
end

local function EnsureDisconnectIcon(anchorFrame, portrait)
	if not anchorFrame.nexDisconnectIcon then
		local icon = anchorFrame:CreateTexture(nil, "OVERLAY", nil, 7)
		icon:SetTexture(DISCONNECT_ICON)
		icon:SetSize(64, 64)
		icon:SetPoint("CENTER", portrait, "CENTER", 0, 0)
		icon:Hide()
		anchorFrame.nexDisconnectIcon = icon
	end
	return anchorFrame.nexDisconnectIcon
end

local function ShouldShowDisconnect(unit)
	if not unit or not UnitExists(unit) then
		return false
	end
	if not UnitIsPlayer(unit) then
		return false
	end
	return not UnitIsConnected(unit)
end

local function IsPartyHudMemberFrame(frame)
	return frame and frame.PartyMemberOverlay ~= nil
end

local function UpdateDisconnectVisuals(frame)
	if not frame or IsPartyHudMemberFrame(frame) then
		return
	end
	local portrait, anchor = GetHudPortrait(frame)
	if not portrait or not anchor then
		return
	end
	local icon = EnsureDisconnectIcon(anchor, portrait)
	local show = ns.db.classColors.enable and ShouldShowDisconnect(frame.unit)
	if show then
		if SetDesaturation then
			SetDesaturation(portrait, true)
		end
		icon:Show()
	else
		if SetDesaturation then
			SetDesaturation(portrait, false)
		end
		icon:Hide()
	end
end

local function UpdateDisconnectFromHealthBar(statusbar)
	local frame = statusbar and statusbar.unitFrame
	if frame and not IsPartyHudMemberFrame(frame) and GetHudPortrait(frame) then
		UpdateDisconnectVisuals(frame)
	end
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
		-- (Disconnected units always resolve to grey above via GetUnitHealthColor.)
		ApplyHudHealthColor(statusbar, HUD_DEFAULT_COLOR.r, HUD_DEFAULT_COLOR.g, HUD_DEFAULT_COLOR.b, false)
	end
	UpdateDisconnectFromHealthBar(statusbar)
end

-- ---------------------------------------------------------------------------
-- Immediate refresh for the standard frames that exist at login (compact
-- raid/party frames refresh via Blizzard's own profile options).
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
			UpdateDisconnectVisuals(frame)
			-- Target/Focus carry a target-of-target subframe.
			if frame.totFrame then
				RefreshBar(frame.totFrame.healthbar)
				UpdateDisconnectVisuals(frame.totFrame)
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
		UpdateDisconnectVisuals(frame)
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

-- CheckFaction resets portrait vertex colour; re-apply offline desaturation + icon.
local function HookCheckFaction(frame)
	if not frame or frame.nexDisconnectHooked then
		return
	end
	if type(frame.CheckFaction) ~= "function" then
		return
	end
	frame.nexDisconnectHooked = true
	hooksecurefunc(frame, "CheckFaction", function(f)
		UpdateDisconnectVisuals(f)
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
	HookCheckFaction(_G["TargetFrame"])
	HookCheckFaction(_G["FocusFrame"])

	-- Boss frames share the TargetFrame atlas + CheckClassification re-skin.
	ForEachBossFrame(function(frame)
		HookClassification(frame)
		HookCheckFaction(frame)
	end)

	HookPartyUpdateArt()
end

-- Recolour on the events that change which unit a frame shows, rebuild its
-- skin, or lift combat (identity stops being secret, so target/focus can
-- finally be coloured). Our handler runs after Blizzard's because the default
-- frames registered these events at load, before our PLAYER_LOGIN.
function ClassColors:RefreshEvent()
	scheduleRefreshStandard()
end

function ClassColors:RefreshEventUnit(unit)
	if unit and not IsHUDRefreshUnit(unit) then
		return
	end
	scheduleRefreshStandard()
end

function ClassColors:RegisterModuleEvents()
	if eventsRegistered then
		return
	end
	eventsRegistered = true

	self:TrackEvent(eventHandles, "PLAYER_ENTERING_WORLD", "RefreshEvent")
	self:TrackEvent(eventHandles, "PLAYER_TARGET_CHANGED", "RefreshEvent")
	self:TrackEvent(eventHandles, "PLAYER_FOCUS_CHANGED", "RefreshEvent")
	self:TrackEvent(eventHandles, "UNIT_CLASSIFICATION_CHANGED", "RefreshEventUnit")
	self:TrackEvent(eventHandles, "PLAYER_REGEN_ENABLED", "RefreshEvent")
	self:TrackEvent(eventHandles, "GROUP_ROSTER_UPDATE", "RefreshEvent")
	self:TrackEvent(eventHandles, "UNIT_FACTION", "RefreshEventUnit")
	self:TrackEvent(eventHandles, "UNIT_THREAT_LIST_UPDATE", "RefreshEventUnit")
	self:TrackEvent(eventHandles, "UNIT_THREAT_SITUATION_UPDATE", "RefreshEventUnit")
	self:TrackEvent(eventHandles, "UNIT_CONNECTION", "RefreshEventUnit")
	self:TrackUnitEvent(eventHandles, "UNIT_PET", "RefreshEvent", "player")
	self:TrackEvent(eventHandles, "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "RefreshEvent")
end

function ClassColors:UnregisterModuleEvents()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
end

function ClassColors:OnEnable()
	self:InstallHooks()
	self:RegisterModuleEvents()
	self:RefreshStandard()
end

function ClassColors:OnDisable()
	self:UnregisterModuleEvents()
	self:RefreshStandard()
end

function ClassColors:OnSettingChanged(key)
	if key == "enable" then
		-- ApplyModuleSetting owns enable lifecycle.
		return
	end
end

function ClassColors:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Class-Coloured Health"], L["Colour HUD unit-frame health bars by class for players and by reaction for NPCs (player, pet, target, focus, boss, party portraits). Offline players use a grey desaturated health bar, desaturated portrait, and disconnect icon on target/focus (matching party frames). Compact raid/party frames use Blizzard's own Class Colors option."])
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
	local hr, hg, hb = GetUnitHealthColor(unit)
	local isPlayer = unit and UnitIsPlayer(unit)
	local desat = bar.IsStatusBarDesaturated and bar:IsStatusBarDesaturated() or nil
	ns.F.Print(string.format("%s unit=%s lockColor=%s isPlayer=%s computed=[%s] barColor=[%s] desat=%s", label, tostring(unit), tostring(bar.lockColor), tostring(isPlayer), hr and fmt(hr, hg, hb) or "nil", fmt(r, g, b), tostring(desat)))
end

function ClassColors:Debug()
	ns.F.Print("ClassColors debug --------------------------------")
	ns.F.Print("enable =", tostring(ns.db and ns.db.classColors and ns.db.classColors.enable))
	ns.F.Print("hooksInstalled =", tostring(self.hooksInstalled))
	ns.F.Print("CLASS_COLORS source =", _G["CUSTOM_CLASS_COLORS"] and "CUSTOM" or "RAID")
	DumpFrame("PlayerFrame", _G["PlayerFrame"])
	DumpFrame("PetFrame", _G["PetFrame"])
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
