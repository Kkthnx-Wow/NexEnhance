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
local UIErrorsFrame = UIErrorsFrame

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
		printToChat = true,
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
local ignoredIDs = {} -- vignetteID -> true (defaults + user list), rebuilt on change
local seen = {} -- vignetteGUID -> true, bounded via F.CacheSet
local announcedAt = {} -- vignetteID -> GetTime() of last announce, bounded via F.CacheSet
local lastSoundAt = 0 -- GetTime() of the last alert sound (anti-burst throttle)
local instType = "none" -- current instance type for "sound in world only"
local subscribed, gateRegistered = false, false

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

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function AtlasIcon(atlas)
	if not atlas then return "" end
	if C_Texture_GetAtlasInfo and not C_Texture_GetAtlasInfo(atlas) then return "" end
	if CreateAtlasMarkup then
		return CreateAtlasMarkup(atlas, 16, 16) .. " "
	end
	return ""
end

local function IsRareVignette(atlas)
	return atlas and (strfind(atlas, "[Vv]ignette") or atlas == "nazjatar-nagaevent")
end

-- ---------------------------------------------------------------------------
-- Detection (VIGNETTE_MINIMAP_UPDATED handler)
-- ---------------------------------------------------------------------------
local function OnVignette(_, vignetteGUID)
	-- Cheapest possible filter first: we've already handled this GUID.
	if not vignetteGUID or seen[vignetteGUID] then return end

	local info = C_VignetteInfo.GetVignetteInfo(vignetteGUID)
	if not info then return end -- transient; leave uncached so it can resolve later

	-- Mark processed exactly once (bounded). Ordinary vignettes stop here and
	-- never re-query GetVignetteInfo on subsequent minimap ticks.
	F.CacheSet(seen, vignetteGUID, true, 1000)

	if not IsRareVignette(info.atlasName) then return end

	local vignetteID = info.vignetteID
	if ignoredIDs[vignetteID] then return end

	-- Per-rare quiet window: a fresh GUID for a rare type we just announced
	-- (re-entering its range, GUID churn) is swallowed until the cooldown lapses.
	local now = GetTime()
	local lastAnnounced = vignetteID and announcedAt[vignetteID]
	if lastAnnounced and (now - lastAnnounced) < REANNOUNCE_COOLDOWN then return end
	if vignetteID then F.CacheSet(announcedAt, vignetteID, now, 500) end

	local cfg = db()
	local icon = AtlasIcon(info.atlasName)
	local name = info.name or ""

	-- Centre-screen banner.
	UIErrorsFrame:AddMessage(format("%s%s %s%s", C.InfoColor, L["Rare Found"], icon, name))

	-- Clickable map link in chat.
	if cfg.printToChat then
		local mapID = C_Map_GetBestMapForUnit and C_Map_GetBestMapForUnit("player")
		local pos = mapID and C_VignetteInfo.GetVignettePosition(vignetteGUID, mapID)
		if pos then
			local x, y = pos:GetXY()
			F.Print(format("%s|cffeda55f|Hworldmap:%d:%d:%d|h[%s (%.1f, %.1f)]|h|r", icon, mapID, x * 10000, y * 10000, name, x * 100, y * 100))
		else
			F.Print(icon .. name)
		end
	end

	-- Alert sound (optionally suppressed inside instances). The global throttle
	-- keeps a burst of simultaneous new rares from machine-gunning the cue.
	if cfg.playSound and (not cfg.soundInWorldOnly or instType == "none") and (now - lastSoundAt) >= SOUND_THROTTLE then
		PlaySound(RARE_SOUND, "Master")
		lastSoundAt = now
	end
end

-- ---------------------------------------------------------------------------
-- Subscription gating
-- ---------------------------------------------------------------------------
local function Subscribe()
	if subscribed then return end
	subscribed = true
	ns:RegisterEvent("VIGNETTE_MINIMAP_UPDATED", OnVignette)
end

local function Unsubscribe()
	if not subscribed then return end
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
	if not gateRegistered then
		gateRegistered = true
		ns:RegisterEvent("UPDATE_INSTANCE_INFO", RefreshSubscription)
		ns:RegisterEvent("PLAYER_ENTERING_WORLD", RefreshSubscription)
	end
	RefreshSubscription()
end

local function Teardown()
	if gateRegistered then
		gateRegistered = false
		ns:UnregisterEvent("UPDATE_INSTANCE_INFO", RefreshSubscription)
		ns:UnregisterEvent("PLAYER_ENTERING_WORLD", RefreshSubscription)
	end
	Unsubscribe()
	wipe(seen)
	wipe(announcedAt)
	lastSoundAt = 0
end

function RareAlert:OnEnable()
	if db().enable then
		Setup()
	end
end

function RareAlert:OnSettingChanged(key)
	if not db().enable then
		Teardown()
	elseif key == "ignoreList" then
		RebuildIgnored()
	else
		Setup()
	end
end

function RareAlert:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Rare Alert"], L["Announce nearby rare creatures and world events the moment they appear on the minimap."])
	local _, soundInit = builder:Checkbox(category, self, "playSound", L["Rare Alert Sound"], L["Play an alert sound when a rare is detected."])
	local _, wildInit = builder:Checkbox(category, self, "soundInWorldOnly", L["Sound In World Only"], L["Only play the alert sound in the open world, not inside instances."])
	local _, printInit = builder:Checkbox(category, self, "printToChat", L["Rare Alert To Chat"], L["Post a clickable map link to chat when a rare is detected."])
	local _, ignoreInit = builder:EditBox(category, self, "ignoreList", L["Ignored Rare IDs"], L["Space or comma separated vignette IDs to never announce."], nil)

	builder:DependsOn(soundInit, enableInit)
	builder:DependsOn(wildInit, soundInit)
	builder:DependsOn(printInit, enableInit)
	if ignoreInit then
		builder:DependsOn(ignoreInit, enableInit)
	end
end
