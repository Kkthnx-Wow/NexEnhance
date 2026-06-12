--[[
	NexEnhance - Rare Alert
	-------------------------------------------------------------------------
	Announces nearby rares and world events the moment their vignette appears
	on the minimap: a centre-screen banner, an optional alert sound, and an
	optional clickable map link posted to chat.

	Reworked from NDui's Misc/Notifications.lua RareAlert (by siweia) to fit the
	NexEnhance engine and the project optimisation guide:
	  * Event-driven and gated - we only listen for VIGNETTE_MINIMAP_UPDATED
	    while it is useful (skipped in warfront/scenario zones), and the whole
	    feature toggles live without a reload.
	  * The handler runs cheapest-filter-first and localises every API.
	  * The de-dupe set is bounded via F.CacheSet (NDui's `#cache > 666` guard
	    never triggered: the cache is string-keyed, so `#` was always 0).
	  * Each vignette GUID is processed once, so ordinary (non-rare) vignettes
	    don't re-query GetVignetteInfo on every minimap tick.
	  * Builds a correct, clickable worldmap hyperlink via string.format.

	Cherry-picked from RareScanner (by NIzReZ) to harden detection:
	  * Atlas bucketing - loot/lore container vignettes (VignetteLoot*,
	    loreobject) are excluded so a treasure chest isn't announced as a rare.
	  * Ignore by NPC ID - the entity ID is parsed from the vignette objectGUID
	    so the ignore list accepts the IDs Wowhead shows, not just vignetteIDs.
	  * Secret-value guards - vignette name and position can be secret inside
	    instances on 12.0; every read is gated with F.NotSecret before any
	    string/arith op, mirroring RareScanner's issecretvalue checks.
--]]

local _, ns = ...
local F, L, C = ns.F, ns.L, ns.C

-- Localised globals (handler runs on a frequently-fired event).
local format = string.format
local strfind, gmatch = string.find, string.gmatch
local tonumber, pairs, wipe = tonumber, pairs, wipe
local GetTime = GetTime
local PlaySound = PlaySound
local GetInstanceInfo = GetInstanceInfo
local CreateAtlasMarkup = _G["CreateAtlasMarkup"]
local C_Texture_GetAtlasInfo = C_Texture and C_Texture.GetAtlasInfo
local C_Map_GetBestMapForUnit = C_Map and C_Map.GetBestMapForUnit
local C_VignetteInfo = C_VignetteInfo
local C_Map = C_Map
local C_SuperTrack = C_SuperTrack
local C_Timer = C_Timer
local C_NamePlate = C_NamePlate
local UnitGUID = UnitGUID
local SetPortraitTexture = SetPortraitTexture
local InCombatLockdown = InCombatLockdown
local GetCVar, SetCVar = GetCVar, SetCVar
local UiMapPoint = _G["UiMapPoint"]
local CreateFrame, UIParent = CreateFrame, UIParent
local UIErrorsFrame = UIErrorsFrame
local UNKNOWN = _G["UNKNOWN"] or "Unknown"

-- The same classic Blizzard tooltip-style gold edge we frame the minimap with,
-- so the popup reads as part of the same UI (see Modules/Maps/Minimap.lua).
local BANNER_BACKDROP = {
	bgFile = C.Media.Textures.blank,
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 14,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- Portrait block sizing: icon sits slightly inset inside Portrait-Frame's inner circle.
local PORTRAIT_ICON = 42
local PORTRAIT_FRAME = 56

-- How long the click-to-track popup lingers before fading itself out.
local POPUP_DURATION = 12

-- Iconic NDui rare-spawn cue (UI_WorldQuest sting); played on the Master bus so
-- it is audible even with sound effects lowered.
local RARE_SOUND = 23404

-- Anti-spam tuning (idea cherry-picked from Plumber's RareAnnouncement cooldown):
--   SOUND_THROTTLE     - minimum gap between alert sounds, so a cluster of rares
--                        resolving on one minimap tick can't machine-gun the cue.
--   REANNOUNCE_COOLDOWN - per-vignetteID quiet window, so the same rare type can't
--                        re-announce while you fly in and out of its range.
local SOUND_THROTTLE = 5
local REANNOUNCE_COOLDOWN = 60

ns:RegisterDefaults({
	rareAlert = {
		enable = false,
		playSound = true,
		soundInWorldOnly = false,
		soundInBackground = false,
		printToChat = true,
		showPopup = true,
		clickToTarget = true,
		raidMarker = 0, -- 0 = off, 1-8 = raid target icon
		ignoreList = "",
	},
})

local RareAlert = ns:NewModule("RareAlert", "rareAlert", { group = "announcements", title = L["Rare Alert"], order = 20 })

local function db()
	return ns.db.rareAlert
end

-- ---------------------------------------------------------------------------
-- Static filters
-- ---------------------------------------------------------------------------
-- Event objects that fire constantly and aren't real rares.
local defaultIgnored = {
	[6149] = true, -- Onyxian Egg
	[6699] = true, -- misplaced curio (Underrot)
}

-- Zones where rare/vignette spam is unwanted (warfronts & their scenarios).
local ignoredZones = {
	[1153] = true,
	[1159] = true,
	[1803] = true,
	[1876] = true,
	[1943] = true,
	[2111] = true,
}

-- ---------------------------------------------------------------------------
-- Runtime state
-- ---------------------------------------------------------------------------
local ignoredIDs = {} -- vignetteID/npcID -> true (defaults + user list), rebuilt on change
local seen = {} -- vignetteGUID -> true, bounded via F.CacheSet
local announcedAt = {} -- vignetteID -> GetTime() of last announce, bounded via F.CacheSet
local lastSoundAt = 0 -- GetTime() of the last alert sound (anti-burst throttle)
local instType = "none" -- current instance type for "sound in world only"
local subscribed, gateRegistered = false, false

-- "Play sound while alt-tabbed" support. WoW mutes its whole audio engine while
-- the game is in the background unless this CVar is on, so to make the rare ping
-- audible while tabbed out we briefly force it on and restore the user's own
-- value a few seconds later. (Mechanism cherry-picked from RareAlert.)
local BG_SOUND_CVAR = "Sound_EnableSoundWhenGameIsInBG"
local bgSoundSaved -- user's CVar value before we forced it on (nil = not overridden)
local bgRestoreTimer

-- Rebuild the ignore set from the user's editbox (numbers only) plus defaults.
-- Cold path: only runs on enable and when the list setting changes.
local function RebuildIgnored()
	wipe(ignoredIDs)
	for id in pairs(defaultIgnored) do
		ignoredIDs[id] = true
	end
	local text = db().ignoreList
	if text and text ~= "" then
		for token in gmatch(text, "%d+") do
			ignoredIDs[tonumber(token)] = true
		end
	end
end

-- Restore the user's background-sound CVar after the brief override window.
local function RestoreBGSound()
	if bgSoundSaved ~= nil then
		SetCVar(BG_SOUND_CVAR, bgSoundSaved)
		bgSoundSaved = nil
	end
	bgRestoreTimer = nil
end

-- Play the rare alert cue, optionally making it audible while WoW is in the
-- background. Each alert (re)extends the restore window so a cluster of rares
-- doesn't cut the sound off early.
local function PlayRareSound()
	if db().soundInBackground then
		if bgSoundSaved == nil then
			local cur = GetCVar(BG_SOUND_CVAR)
			if cur ~= "1" then
				bgSoundSaved = cur
				SetCVar(BG_SOUND_CVAR, "1")
			end
		end
		if bgSoundSaved ~= nil then
			if bgRestoreTimer then
				bgRestoreTimer:Cancel()
			end
			bgRestoreTimer = C_Timer.NewTimer(5, RestoreBGSound)
		end
	end
	PlaySound(RARE_SOUND, "Master")
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
-- Raid target icon markup + name, for the marker dropdown labels.
local function MarkerLabel(index, name)
	return format("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:16:16|t %s", index, name)
end

local function AtlasIcon(atlas)
	if not atlas then
		return ""
	end
	if C_Texture_GetAtlasInfo and not C_Texture_GetAtlasInfo(atlas) then
		return ""
	end
	if CreateAtlasMarkup then
		return CreateAtlasMarkup(atlas, 16, 16) .. " "
	end
	return ""
end

-- Treasure/container and lore-object vignettes also carry "Vignette" in their
-- atlas (VignetteLoot, VignetteLootElite, loreobject-32x32, ...). RareScanner
-- buckets these separately from NPC rares; we exclude them so a treasure chest
-- isn't announced as "Rare Found". Atlas categories cherry-picked from
-- RareScanner's RSConstants (CONTAINER_*).
local function IsRareVignette(atlas)
	if not atlas then
		return false
	end
	-- Loot containers / lore objects are not rares.
	if strfind(atlas, "[Vv]ignette[Ll]oot") or strfind(atlas, "loreobject") then
		return false
	end
	return strfind(atlas, "[Vv]ignette") ~= nil or atlas == "nazjatar-nagaevent"
end

-- Pull the creature/entity ID out of a vignette's objectGUID so the ignore list
-- can match the NPC ID shown on Wowhead (like RareScanner). F.GetNPCID does the
-- GUID parse and is already guarded for 12.0 secret GUIDs.
local function GetVignetteNpcID(info)
	return F.GetNPCID(info.objectGUID)
end

-- ---------------------------------------------------------------------------
-- Click-to-track popup
--   A small, movable banner that appears when a rare is found. Clicking it
--   drops a tracked waypoint at the rare's position - TomTom if the user runs
--   it, otherwise Blizzard's own user waypoint + super-track arrow. The
--   position comes straight from the vignette, so this works for every rare
--   with no creature->displayID database (the only reason RareScanner needs its
--   huge data tables is the 3D model, which we intentionally skip).
-- ---------------------------------------------------------------------------
local popup -- lazily-built frame

-- Drop a tracked waypoint. mapID + x/y (0-1 fractions) come from the vignette.
local function SetTrackedWaypoint(mapID, x, y, name)
	if not (mapID and x and y) then
		return false
	end

	local TomTom = _G["TomTom"]
	if TomTom and TomTom.AddWaypoint then
		TomTom:AddWaypoint(mapID, x, y, { title = name, from = ns.name, persistent = false, crazy = true })
		return true
	end

	if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
		C_Map.ClearUserWaypoint()
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		end
		return true
	end

	return false
end

local function Popup_Hide()
	if not popup then
		return
	end
	if popup.hideTimer then
		popup.hideTimer:Cancel()
		popup.hideTimer = nil
	end
	popup.testing = nil
	popup.shownForEdit = nil
	-- The popup holds a secure child, so hiding it is a protected action in
	-- combat; defer the actual Hide to PLAYER_REGEN_ENABLED.
	if InCombatLockdown() then
		popup.pendingHide = true
		return
	end
	popup.pendingHide = nil
	popup:Hide()
end

-- Run on PLAYER_REGEN_ENABLED to flush a hide that was blocked during combat.
local function Popup_FlushPending()
	if popup and popup.pendingHide then
		popup.pendingHide = nil
		popup:Hide()
	end
end

-- Our secure overlay registers for "AnyUp" and runs a /targetexact macro, but if
-- the user has key-down action casting enabled (ActionButtonUseKeyDown = 1) the
-- protected macro can fire on the press instead of the release and silently miss
-- - the click-to-target would just not work for those users. Force key-up
-- handling for the duration of this one click and restore it in PostClick.
-- (Cherry-picked from RareAlert by the same mechanism it uses for its target
-- button.) SetCVar on this CVar is unprotected, so it is safe even in combat.
local function Popup_PreClick(self)
	self.prevUseKeyDown = GetCVar("ActionButtonUseKeyDown")
	if self.prevUseKeyDown ~= "0" then
		SetCVar("ActionButtonUseKeyDown", "0")
	end
end

-- Insecure post-hook for the secure overlay's click: the protected /targetexact
-- macro (if any) has already run; here we just drop the waypoint and dismiss.
-- PostClick is safe on a secure button (unlike SetScript("OnClick"), which would
-- taint the secure path - see the optimisation guide, Section 9).
local function Popup_PostClick(self, button)
	-- Restore the user's key-down casting preference flipped in Popup_PreClick.
	if self.prevUseKeyDown and self.prevUseKeyDown ~= "0" then
		SetCVar("ActionButtonUseKeyDown", self.prevUseKeyDown)
	end
	self.prevUseKeyDown = nil

	local f = self:GetParent()
	if button == "LeftButton" then
		if SetTrackedWaypoint(f.mapID, f.x, f.y, f.rareName) then
			F.Print(format(L["Tracking %s."], F.Colorize(f.rareName or UNKNOWN, "green")))
		end
	end
	if not f.testing then
		Popup_Hide()
	end
end

-- Rebuild the secure click macro for the rare currently shown. macrotext is a
-- protected attribute, so this only works out of combat; in combat we leave the
-- previous macro in place (targeting just won't update until you drop combat).
local function Popup_UpdateMacro(f, targetName)
	if not f.secure or InCombatLockdown() then
		return
	end

	local cfg = db()
	local macro = ""
	if cfg.clickToTarget and targetName and targetName ~= UNKNOWN then
		macro = "/cleartarget\n/targetexact " .. targetName
		local marker = cfg.raidMarker
		if marker and marker > 0 then
			macro = macro .. "\n/tm " .. marker
		end
	end
	f.secure:SetAttribute("macrotext", macro)
end

-- Find a usable unit token for a GUID by checking the units we can actually
-- reach (target/mouseover/nameplates). Used to grab a 2D portrait when the rare
-- happens to be on screen; otherwise we fall back to the vignette icon. GUID
-- reads can be secret in instances, so every compare is guarded.
local function GetUnitForGUID(guid)
	if not guid then
		return
	end

	local t = UnitGUID("target")
	if t and F.NotSecret(t) and t == guid then
		return "target"
	end

	local m = UnitGUID("mouseover")
	if m and F.NotSecret(m) and m == guid then
		return "mouseover"
	end

	if C_NamePlate and C_NamePlate.GetNamePlates then
		local plates = C_NamePlate.GetNamePlates()
		for i = 1, #plates do
			local token = plates[i].namePlateUnitToken
			if token then
				local g = UnitGUID(token)
				if g and F.NotSecret(g) and g == guid then
					return token
				end
			end
		end
	end
end

-- Show a 2D portrait for `unit` when possible, else the vignette `atlas` icon.
local function Popup_SetIcon(f, atlas, unit)
	if unit and SetPortraitTexture then
		if not f.iconMasked then
			f.icon:AddMaskTexture(f.iconMask)
			f.iconMasked = true
		end
		f.iconRing:Show()
		f.icon:SetTexCoord(0, 1, 0, 1)
		SetPortraitTexture(f.icon, unit)
	elseif atlas then
		if f.iconMasked and f.icon.RemoveMaskTexture then
			f.icon:RemoveMaskTexture(f.iconMask)
			f.iconMasked = nil
		end
		f.iconRing:Hide()
		f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		f.icon:SetTexture(nil)
		f.icon:SetAtlas(atlas)
	end
end

local function BuildPopup()
	if popup then
		return popup
	end

	local f = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
	f:SetSize(268, PORTRAIT_FRAME + 10)
	f:SetFrameStrata("HIGH")
	f:Hide()
	f:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	-- Tooltip-style border over a dark fill.
	f:SetBackdrop(BANNER_BACKDROP)
	f:SetBackdropColor(0.05, 0.05, 0.05, 0.9)

	-- Portrait holder keeps the face + ring aligned as one block.
	f.portraitHolder = CreateFrame("Frame", nil, f)
	f.portraitHolder:SetSize(PORTRAIT_FRAME, PORTRAIT_FRAME)
	f.portraitHolder:SetPoint("LEFT", 10, -4)

	f.iconRing = f.portraitHolder:CreateTexture(nil, "OVERLAY")
	f.iconRing:SetAllPoints(f.portraitHolder)
	f.iconRing:SetAtlas("Portrait-Frame")
	f.iconRing:Hide()

	f.icon = f.portraitHolder:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(PORTRAIT_ICON, PORTRAIT_ICON)
	f.icon:SetPoint("CENTER", f.portraitHolder, "CENTER", 0, 0)
	f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	-- Round the portrait into a minimap-style face with a circular alpha mask.
	f.iconMask = f.portraitHolder:CreateMaskTexture()
	f.iconMask:SetSize(PORTRAIT_ICON, PORTRAIT_ICON)
	f.iconMask:SetPoint("CENTER", f.icon, "CENTER")
	f.iconMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

	f.title = F.CreateFS(f, 14, nil, "OVERLAY")
	f.title:SetPoint("TOPLEFT", f.portraitHolder, "TOPRIGHT", 10, -2)
	f.title:SetPoint("RIGHT", f, "RIGHT", -24, 0)
	f.title:SetJustifyH("LEFT")
	f.title:SetWordWrap(false)

	f.coords = F.CreateFS(f, 11, nil, "OVERLAY")
	f.coords:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
	f.coords:SetJustifyH("LEFT")
	f.coords:SetTextColor(0.7, 0.7, 0.7)

	f.hint = F.CreateFS(f, 10, L["Click to set a waypoint"], "OVERLAY")
	f.hint:SetPoint("BOTTOMLEFT", f.portraitHolder, "BOTTOMRIGHT", 10, 8)
	f.hint:SetTextColor(0.5, 0.78, 1)

	-- Secure overlay: a SecureActionButtonTemplate covering the banner. Left-click
	-- runs the protected /targetexact macro (set out of combat via Popup_UpdateMacro);
	-- the waypoint + dismiss happen in the safe PostClick post-hook. The button is
	-- created once and never individually shown/hidden, so its visibility simply
	-- follows the parent and we never touch a protected frame during combat.
	local secure = CreateFrame("Button", nil, f, "SecureActionButtonTemplate")
	secure:SetAllPoints(f)
	secure:SetFrameLevel(f:GetFrameLevel() + 1)
	secure:RegisterForClicks("AnyUp")
	secure:SetAttribute("type1", "macro")
	secure:SetScript("PreClick", Popup_PreClick)
	secure:SetScript("PostClick", Popup_PostClick)
	secure:SetScript("OnEnter", function()
		local b = C.Colors.brand
		f:SetBackdropBorderColor(b[1], b[2], b[3], 1)
	end)
	secure:SetScript("OnLeave", function()
		f:SetBackdropBorderColor(1, 0.82, 0, 1)
	end)
	f.secure = secure

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetSize(22, 22)
	close:SetPoint("TOPRIGHT", 0, 0)
	close:SetFrameLevel(secure:GetFrameLevel() + 1)
	close:SetScript("OnClick", Popup_Hide)
	f.close = close

	f:SetBackdropBorderColor(1, 0.82, 0, 1)

	F.CreateMover(f, "rareAlert", L["Rare Alert"], "TOP", 0, -240)

	popup = f
	return f
end

-- Populate and show the popup for a freshly-found rare. `guid` (optional, the
-- vignette objectGUID) lets us show a 2D portrait when the rare is on screen.
local function Popup_Show(atlas, name, mapID, x, y, guid)
	-- The popup contains a secure child, so showing it is blocked in combat. If
	-- we're fighting, skip the popup for this rare - the banner, sound and chat
	-- link have already fired, and a click-to-target/track popup is of little use
	-- mid-combat anyway. (Building it in combat would also taint the secure child.)
	if InCombatLockdown() then
		return
	end

	local f = BuildPopup()

	local unit = (guid and F.NotSecret(guid)) and GetUnitForGUID(guid) or nil
	Popup_SetIcon(f, atlas, unit)

	f.rareName = name
	f.title:SetText(name)
	f.mapID, f.x, f.y = mapID, x, y

	-- Configure the secure click macro for this rare (out of combat only).
	Popup_UpdateMacro(f, name)

	local cfg = db()
	local canTrack = mapID and x and y
	if canTrack then
		f.coords:SetFormattedText("(%.1f, %.1f)", x * 100, y * 100)
	else
		-- No trackable position (e.g. secret coords inside an instance).
		f.coords:SetText("")
	end

	-- Hint reflects what a click will actually do.
	local hint
	if cfg.clickToTarget and canTrack then
		hint = L["Click to target & track"]
	elseif cfg.clickToTarget then
		hint = L["Click to target"]
	elseif canTrack then
		hint = L["Click to set a waypoint"]
	end
	if hint then
		f.hint:SetText(hint)
		f.hint:Show()
	else
		f.hint:Hide()
	end

	f.pendingHide = nil
	f:Show()
	if f.hideTimer then
		f.hideTimer:Cancel()
	end
	f.hideTimer = C_Timer.NewTimer(POPUP_DURATION, Popup_Hide)
end

-- ---------------------------------------------------------------------------
-- Preview + Edit Mode integration
-- ---------------------------------------------------------------------------
-- Show a non-expiring sample popup (player portrait, current position) used by
-- both the /nex rare preview and the Edit Mode mover, so the banner is grabbable
-- without needing a live rare.
local function Popup_ShowPreview()
	local mapID = C_Map_GetBestMapForUnit and C_Map_GetBestMapForUnit("player")
	local x, y
	if mapID and C_Map and C_Map.GetPlayerMapPosition then
		local pos = C_Map.GetPlayerMapPosition(mapID, "player")
		if pos then
			local px, py = pos:GetXY()
			if px and py and F.NotSecret(px) and F.NotSecret(py) then
				x, y = px, py
			end
		end
	end

	Popup_Show("VignetteKill", L["Rare Alert"] .. " " .. (_G["EXAMPLE"] or "Preview"), mapID, x, y)
	-- Preview the 2D portrait look with the player's own portrait.
	if SetPortraitTexture then
		Popup_SetIcon(popup, nil, "player")
	end
	if popup.hideTimer then
		popup.hideTimer:Cancel()
		popup.hideTimer = nil
	end
end

-- Keep LibEditMode's mover/selection on top of our secure overlay so it wins the
-- drag. The selection is parented to the banner (SetAllPoints), so by default the
-- secure button (a higher frame level, HIGH strata) ate the click. We lift the
-- selection a full strata above the banner. EditModeSystemSelectionTemplate
-- re-asserts its own level when shown, so we re-apply this on every enter.
local function RaiseEditSelection()
	local sel = popup and popup.editSelection
	if not sel then
		return
	end
	sel:SetFrameStrata("HIGH")
	local base = (popup.close and popup.close:GetFrameLevel()) or popup:GetFrameLevel()
	sel:SetFrameLevel(base + 5)
end

-- Show the banner on Edit Mode enter so its mover is grabbable without /nex rare,
-- and hide it again on exit. If a /nex rare preview is already up we leave it
-- alone (shownForEdit only tracks the banner WE revealed for editing).
local function OnEditEnter()
	if popup and not popup:IsShown() then
		Popup_ShowPreview()
		popup.shownForEdit = true
	end
	RaiseEditSelection()
end

local function OnEditExit()
	if popup and popup.shownForEdit then
		popup.shownForEdit = nil
		Popup_Hide()
	end
end

-- Mirror the click-behaviour options onto the LibEditMode dialog (like the exp
-- bar) and reveal the banner with Edit Mode so it can be moved. Runs once, after
-- the popup (and its mover) exist.
local editModeHooked = false
local function HookEditMode()
	if editModeHooked or not popup then
		return
	end
	local lib = _G.LibStub and _G.LibStub("LibEditMode", true)
	if not lib then
		return
	end
	editModeHooked = true

	if lib.AddFrameSettings and lib.SettingType then
		local markerValues = {
			{ text = L["Off"], value = 0 },
			{ text = MarkerLabel(1, L["Star"]), value = 1 },
			{ text = MarkerLabel(2, L["Circle"]), value = 2 },
			{ text = MarkerLabel(3, L["Diamond"]), value = 3 },
			{ text = MarkerLabel(4, L["Triangle"]), value = 4 },
			{ text = MarkerLabel(5, L["Moon"]), value = 5 },
			{ text = MarkerLabel(6, L["Square"]), value = 6 },
			{ text = MarkerLabel(7, L["Cross"]), value = 7 },
			{ text = MarkerLabel(8, L["Skull"]), value = 8 },
		}

		lib:AddFrameSettings(popup, {
			{
				kind = lib.SettingType.Checkbox,
				name = L["Click To Target"],
				desc = L["Left-click the popup to clear your target and target the rare by name. Targeting needs a secure click, so it only updates out of combat."],
				default = true,
				get = function()
					return db().clickToTarget
				end,
				set = function(_, value)
					db().clickToTarget = value
				end,
			},
			{
				kind = lib.SettingType.Dropdown,
				name = L["Raid Marker"],
				desc = L["Also place a raid target marker on the rare when you click to target it."],
				default = 0,
				values = markerValues,
				get = function()
					return db().raidMarker
				end,
				set = function(_, value)
					db().raidMarker = value
				end,
			},
		})
	end

	-- Stash LibEditMode's mover/selection so RaiseEditSelection can lift it above
	-- our secure overlay on every Edit Mode enter (see that function). It is
	-- hidden outside Edit Mode, so this never affects normal clicks.
	popup.editSelection = lib.frameSelections and lib.frameSelections[popup]
	RaiseEditSelection()

	if lib.RegisterCallback then
		lib:RegisterCallback("enter", OnEditEnter)
		lib:RegisterCallback("exit", OnEditExit)
	end
end

-- ---------------------------------------------------------------------------
-- Detection (VIGNETTE_MINIMAP_UPDATED handler)
-- ---------------------------------------------------------------------------
local function OnVignette(_, vignetteGUID)
	-- Cheapest possible filter first: we've already handled this GUID.
	if not vignetteGUID or seen[vignetteGUID] then
		return
	end

	local info = C_VignetteInfo.GetVignetteInfo(vignetteGUID)
	if not info then
		return
	end -- transient; leave uncached so it can resolve later

	-- Mark processed exactly once (bounded). Ordinary vignettes stop here and
	-- never re-query GetVignetteInfo on subsequent minimap ticks.
	F.CacheSet(seen, vignetteGUID, true, 1000)

	if not IsRareVignette(info.atlasName) then
		return
	end

	local vignetteID = info.vignetteID
	if vignetteID and ignoredIDs[vignetteID] then
		return
	end

	-- Also honour the ignore list against the underlying NPC ID (the ID Wowhead
	-- shows), not just the vignetteID, so users can blacklist a specific rare.
	local npcID = GetVignetteNpcID(info)
	if npcID and ignoredIDs[npcID] then
		return
	end

	-- Per-rare quiet window: a fresh GUID for a rare type we just announced
	-- (re-entering its range, GUID churn) is swallowed until the cooldown lapses.
	local now = GetTime()
	local lastAnnounced = vignetteID and announcedAt[vignetteID]
	if lastAnnounced and (now - lastAnnounced) < REANNOUNCE_COOLDOWN then
		return
	end
	if vignetteID then
		F.CacheSet(announcedAt, vignetteID, now, 500)
	end

	local cfg = db()
	local icon = AtlasIcon(info.atlasName)

	-- info.name can be a secret value inside instances on 12.0; never run a
	-- string op (format/concat) on it. Fall back to UNKNOWN when guarded.
	local rawName = info.name
	local name = (rawName and F.NotSecret(rawName)) and rawName or UNKNOWN

	-- Centre-screen banner.
	UIErrorsFrame:AddMessage(format("%s%s %s%s", C.InfoColor, L["Rare Found"], icon, name))

	-- Resolve the rare's position once (shared by the chat link and the popup).
	-- Coordinates can be secret inside instances on 12.0; arithmetic on a secret
	-- value errors, so leave x/y nil when guarded - both consumers handle that.
	local mapID, x, y
	if cfg.printToChat or cfg.showPopup then
		mapID = C_Map_GetBestMapForUnit and C_Map_GetBestMapForUnit("player")
		local pos = mapID and C_VignetteInfo.GetVignettePosition(vignetteGUID, mapID)
		if pos then
			local px, py = pos:GetXY()
			if px and py and F.NotSecret(px) and F.NotSecret(py) then
				x, y = px, py
			end
		end
	end

	-- Clickable map link in chat.
	if cfg.printToChat then
		if mapID and x and y then
			F.Print(format("%s|cffeda55f|Hworldmap:%d:%d:%d|h[%s (%.1f, %.1f)]|h|r", icon, mapID, x * 10000, y * 10000, name, x * 100, y * 100))
		else
			F.Print(icon .. name)
		end
	end

	-- Movable click-to-track popup (with a 2D portrait when the rare is on screen).
	if cfg.showPopup then
		Popup_Show(info.atlasName, name, mapID, x, y, info.objectGUID)
	end

	-- Alert sound (optionally suppressed inside instances). The global throttle
	-- keeps a burst of simultaneous new rares from machine-gunning the cue.
	if cfg.playSound and (not cfg.soundInWorldOnly or instType == "none") and (now - lastSoundAt) >= SOUND_THROTTLE then
		PlayRareSound()
		lastSoundAt = now
	end
end

-- ---------------------------------------------------------------------------
-- Subscription gating
-- ---------------------------------------------------------------------------
local function Subscribe()
	if subscribed then
		return
	end
	subscribed = true
	ns:RegisterEvent("VIGNETTE_MINIMAP_UPDATED", OnVignette)
end

local function Unsubscribe()
	if not subscribed then
		return
	end
	subscribed = false
	ns:UnregisterEvent("VIGNETTE_MINIMAP_UPDATED", OnVignette)
end

-- Decide whether to listen for vignettes based on the current zone/instance.
local function RefreshSubscription()
	if not db().enable then
		Unsubscribe()
		return
	end

	local _, it, _, _, maxPlayers, _, _, instID = GetInstanceInfo()
	instType = it or "none"

	local smallScenario = (it == "scenario" and (maxPlayers == 3 or maxPlayers == 6))
	if (instID and ignoredZones[instID]) or smallScenario then
		Unsubscribe()
	else
		Subscribe()
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
local function Setup()
	RebuildIgnored()
	-- Build the popup now so its Edit Mode mover is registered up front (it can
	-- then be positioned via /nex rare without waiting for a real rare). Skip if
	-- we're in combat - the secure child can't be configured then; it'll build
	-- lazily on the next out-of-combat rare or /nex rare.
	if db().showPopup and not InCombatLockdown() then
		BuildPopup()
		HookEditMode()
	end
	if not gateRegistered then
		gateRegistered = true
		ns:RegisterEvent("UPDATE_INSTANCE_INFO", RefreshSubscription)
		ns:RegisterEvent("PLAYER_ENTERING_WORLD", RefreshSubscription)
		-- Flush any popup hide that combat blocked.
		ns:RegisterEvent("PLAYER_REGEN_ENABLED", Popup_FlushPending)
	end
	RefreshSubscription()
end

local function Teardown()
	if gateRegistered then
		gateRegistered = false
		ns:UnregisterEvent("UPDATE_INSTANCE_INFO", RefreshSubscription)
		ns:UnregisterEvent("PLAYER_ENTERING_WORLD", RefreshSubscription)
		ns:UnregisterEvent("PLAYER_REGEN_ENABLED", Popup_FlushPending)
	end
	Unsubscribe()
	Popup_Hide()
	-- Restore the background-sound CVar immediately if an override is pending.
	if bgRestoreTimer then
		bgRestoreTimer:Cancel()
	end
	RestoreBGSound()
	wipe(seen)
	wipe(announcedAt)
	lastSoundAt = 0
end

-- Preview the popup so it can be skinned/positioned (used by /nex rare). Toggles
-- a sticky sample with the player's current position as the click target.
function RareAlert:ToggleTest()
	-- The popup carries a secure child, so building/showing/hiding it is a
	-- protected action during combat.
	if InCombatLockdown() then
		F.Print(F.Colorize(L["Rare Alert"] .. ": ", "brand") .. L["Cannot preview the popup during combat."])
		return
	end

	BuildPopup()
	if popup:IsShown() and popup.testing then
		Popup_Hide()
		return
	end

	Popup_ShowPreview()
	popup.testing = true
end

function RareAlert:OnEnable()
	if db().enable then
		Setup()
	end
end

function RareAlert:OnSettingChanged(key, value)
	if not db().enable then
		Teardown()
	elseif key == "ignoreList" then
		RebuildIgnored()
	elseif key == "showPopup" and not value then
		Popup_Hide()
	else
		Setup()
	end
end

function RareAlert:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Rare Alert"], L["Announce nearby rare creatures and world events the moment they appear on the minimap."])
	local _, soundInit = builder:Checkbox(category, self, "playSound", L["Rare Alert Sound"], L["Play an alert sound when a rare is detected."])
	local _, wildInit = builder:Checkbox(category, self, "soundInWorldOnly", L["Sound In World Only"], L["Only play the alert sound in the open world, not inside instances."])
	local _, bgInit = builder:Checkbox(category, self, "soundInBackground", L["Sound While Alt-Tabbed"], L["Make the alert sound audible while WoW is minimised or in the background. Briefly overrides your background-sound setting and restores it afterwards."])
	local _, printInit = builder:Checkbox(category, self, "printToChat", L["Rare Alert To Chat"], L["Post a clickable map link to chat when a rare is detected."])
	local _, popupInit = builder:Checkbox(category, self, "showPopup", L["Rare Alert Popup"], L["Show a movable popup when a rare is detected - click it to set a tracked waypoint (uses TomTom if installed). Preview/move it with /nex rare."])
	local _, targetInit = builder:Checkbox(category, self, "clickToTarget", L["Click To Target"], L["Left-click the popup to clear your target and target the rare by name. Targeting needs a secure click, so it only updates out of combat."])

	local markerChoices = {
		{ value = 0, label = L["Off"] },
		{ value = 1, label = MarkerLabel(1, L["Star"]) },
		{ value = 2, label = MarkerLabel(2, L["Circle"]) },
		{ value = 3, label = MarkerLabel(3, L["Diamond"]) },
		{ value = 4, label = MarkerLabel(4, L["Triangle"]) },
		{ value = 5, label = MarkerLabel(5, L["Moon"]) },
		{ value = 6, label = MarkerLabel(6, L["Square"]) },
		{ value = 7, label = MarkerLabel(7, L["Cross"]) },
		{ value = 8, label = MarkerLabel(8, L["Skull"]) },
	}
	local _, markerInit = builder:Dropdown(category, self, "raidMarker", L["Raid Marker"], L["Also place a raid target marker on the rare when you click to target it."], markerChoices)

	local _, ignoreInit = builder:EditBox(category, self, "ignoreList", L["Ignored Rare IDs"], L["Space or comma separated vignette IDs to never announce."], nil)

	builder:DependsOn(soundInit, enableInit)
	builder:DependsOn(wildInit, soundInit)
	builder:DependsOn(bgInit, soundInit)
	builder:DependsOn(printInit, enableInit)
	builder:DependsOn(popupInit, enableInit)
	builder:DependsOn(targetInit, popupInit)
	if markerInit then
		builder:DependsOn(markerInit, targetInit)
	end
	if ignoreInit then
		builder:DependsOn(ignoreInit, enableInit)
	end
end
