--[[
	NexEnhance - LevelAnnouncer
	-------------------------------------------------------------------------
	Tracks how long each level took and announces your ding in a channel of
	your choice. Works solo (local print) or in a group/guild.

	Timing
	  The start timestamp is written into NexEnhanceCharDB (per-character
	  SavedVariables) using time() (Unix seconds) so it survives /reload and
	  zone transitions. A zone change does NOT reset the clock; only leveling
	  up or first-ever login for that character does. Offline time is counted
	  honestly — if you log out mid-level the elapsed includes real-world time.

	Max level
	  When the player hits GetMaxPlayerLevel() a random line from the pool is
	  used in place of the plain "Ding!" template, with the level time appended.

	Channel routing
	  LOCAL  : F.Print to chat (no SendChatMessage, always works)
	  SAY    : /say — other players nearby can see it
	  PARTY  : instance chat if in LFG, raid chat if in a raid, party otherwise;
	            falls back to LOCAL when not grouped
	  GUILD  : guild chat; falls back to LOCAL when not in a guild
--]]

local _, ns = ...
local F, L = ns.F, ns.L

local format = string.format
local floor = math.floor
local random = math.random
local time = time
local UnitLevel = UnitLevel
local GetMaxPlayerLevel = GetMaxPlayerLevel
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local IsInGuild = IsInGuild
local IsPartyLFG = IsPartyLFG
local C_ChatInfo = C_ChatInfo

-- ---------------------------------------------------------------------------
-- Defaults & module
-- ---------------------------------------------------------------------------
ns:RegisterDefaults({
	levelAnnouncer = {
		enable = false, -- opt-in only; nobody wants surprise chat spam
		channel = "LOCAL",
		announceMax = true,
	},
})

local LevelAnnouncer = ns:NewModule("LevelAnnouncer", "levelAnnouncer", { group = "announcements", title = L["Level Announcer"], order = 30 })

-- Midnight cap; GetMaxPlayerLevel() is always queried at runtime, this is
-- only the fallback if the API isn't present.
local MIDNIGHT_MAX_LEVEL = 90

-- ---------------------------------------------------------------------------
-- Max-level message pool
--   Randomly chosen so repeated fresh alts don't see the same line. Written
--   as natural exclamations — these appear as chat messages in party/guild/say
--   (e.g. "[PlayerName]: Ding! Max level 90!") so they must read like something
--   a real player would actually type, not a game tooltip talking to the player
--   in second person. %d is filled with the max level number; the elapsed time
--   string is appended separately.
-- ---------------------------------------------------------------------------
local MAX_LEVEL_MESSAGES = {
	"Ding! Max level %d!",
	"DING %d! Finally at max level!",
	"Level %d! Max level reached!",
	"Ding! Hit %d — the grind is done!",
	"DING! Level %d! Max level complete!",
	"Level %d hit! Done leveling!",
}

-- ---------------------------------------------------------------------------
-- Duration formatting
--   Collapses whole seconds into "Xh Ym Zs" / "Xm Ys" / "Ys".
-- ---------------------------------------------------------------------------
local function FormatDuration(seconds)
	seconds = floor(seconds)
	if seconds < 60 then
		return format(L["%ds"], seconds)
	end
	local mins = floor(seconds / 60)
	local secs = seconds % 60
	if mins < 60 then
		return format(L["%dm %ds"], mins, secs)
	end
	local hours = floor(mins / 60)
	mins = mins % 60
	return format(L["%dh %dm %ds"], hours, mins, secs)
end

-- ---------------------------------------------------------------------------
-- Channel routing
--   Routes SendChatMessage to the right channel based on db.channel and the
--   player's current group/guild status. Falls back to a local F.Print when
--   the requested social context isn't available (e.g. PARTY while solo).
-- ---------------------------------------------------------------------------
local function SendMessage(msg)
	local channel = ns.db.levelAnnouncer.channel

	if channel == "SAY" then
		C_ChatInfo.SendChatMessage(msg, "SAY")
	elseif channel == "PARTY" then
		if IsPartyLFG() then
			C_ChatInfo.SendChatMessage(msg, "INSTANCE_CHAT")
		elseif IsInRaid() then
			C_ChatInfo.SendChatMessage(msg, "RAID")
		elseif IsInGroup() then
			C_ChatInfo.SendChatMessage(msg, "PARTY")
		else
			F.Print(msg) -- not grouped: print locally
		end
	elseif channel == "GUILD" then
		if IsInGuild() then
			C_ChatInfo.SendChatMessage(msg, "GUILD")
		else
			F.Print(msg) -- not in guild: print locally
		end
	else -- LOCAL (default)
		F.Print(msg)
	end
end

-- ---------------------------------------------------------------------------
-- Level tracking (ns.charDB — per-character SavedVariables)
--   { level = N, startTime = T }
--   startTime is a time() Unix timestamp so it survives /reload and zone
--   changes. PLAYER_ENTERING_WORLD only resets it when the stored level no
--   longer matches the current level (first login, or data is stale).
-- ---------------------------------------------------------------------------
local function GetTracker()
	ns.charDB.levelTracker = ns.charDB.levelTracker or {}
	return ns.charDB.levelTracker
end

local function StartClock(level)
	ns.charDB.levelTracker = { level = level, startTime = time() }
end

-- ---------------------------------------------------------------------------
-- Event handlers
-- ---------------------------------------------------------------------------

--- Runs on every login and zone change. Initialises the clock for the
--- current level when no valid tracking data exists; leaves it alone on
--- simple reloads or zone transitions so the elapsed time keeps accruing.
function LevelAnnouncer:PLAYER_ENTERING_WORLD()
	if not ns.db.levelAnnouncer.enable then
		return
	end
	local currentLevel = UnitLevel("player")
	-- UnitLevel has no SecretReturns in Resources 12.0.7.
	if not currentLevel then
		return
	end
	local tracker = GetTracker()
	if tracker.level ~= currentLevel or not tracker.startTime then
		-- First login on this character, stale data, or the level changed
		-- without us catching it (shouldn't happen, but be safe).
		StartClock(currentLevel)
	end
	-- If level matches and startTime exists: /reload or zone change.
	-- Preserve the clock so the elapsed accumulates correctly.
end

--- Fires when the player levels up. Calculates elapsed time, builds the
--- message, routes it to the chosen channel, then resets the clock for the
--- new level.
function LevelAnnouncer:PLAYER_LEVEL_UP(newLevel)
	if not ns.db.levelAnnouncer.enable or not newLevel then
		return
	end

	local tracker = GetTracker()
	-- time() is a plain Lua function — it never returns a secret value.
	local elapsed = tracker.startTime and (time() - tracker.startTime) or 0
	local durationStr = elapsed > 0 and FormatDuration(elapsed) or nil

	local maxLevel = GetMaxPlayerLevel() or MIDNIGHT_MAX_LEVEL

	local isMax = newLevel >= maxLevel

	local msg
	if isMax and ns.db.levelAnnouncer.announceMax then
		-- Random pool line + optional elapsed time.
		local template = MAX_LEVEL_MESSAGES[random(#MAX_LEVEL_MESSAGES)]
		local baseLine = format(template, newLevel)
		msg = durationStr and format(L["%s (%s for this level)"], baseLine, durationStr) or baseLine
	elseif durationStr then
		msg = format(L["Ding! Level %d in %s!"], newLevel, durationStr)
	else
		msg = format(L["Ding! Level %d!"], newLevel)
	end

	SendMessage(msg)

	-- Reset the clock so the NEXT level starts fresh from this moment.
	StartClock(newLevel)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
local eventHandles = {}
local eventsRegistered = false

function LevelAnnouncer:OnEnable()
	if eventsRegistered then
		return
	end
	eventsRegistered = true
	self:TrackEvent(eventHandles, "PLAYER_LEVEL_UP")
	self:TrackEvent(eventHandles, "PLAYER_ENTERING_WORLD")
end

function LevelAnnouncer:OnDisable()
	ns:UnregisterModuleEventHandles(eventHandles)
	eventsRegistered = false
end

function LevelAnnouncer:OnSettingChanged(key, value)
	-- ApplyModuleSetting owns OnEnable/OnDisable. On enable, still kick-start
	-- the clock so the first ding after toggle shows a meaningful duration.
	if key == "enable" and not value then
		return
	end

	if ns.db.levelAnnouncer.enable then
		local currentLevel = UnitLevel("player")
		if currentLevel then
			local tracker = GetTracker()
			if tracker.level ~= currentLevel or not tracker.startTime then
				StartClock(currentLevel)
			end
		end
	end
end

function LevelAnnouncer:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Level Announcer"], L["Announce how long each level took when you ding."])

	local _, channelInit = builder:Dropdown(category, self, "channel", L["Announce Channel"], L["Where to post the level-up message. Falls back to Local if the chosen context is unavailable."], {
		{ value = "LOCAL", label = L["Local Only"] },
		{ value = "SAY", label = L["/say"] },
		{ value = "PARTY", label = L["Party / Raid"] },
		{ value = "GUILD", label = L["Guild"] },
	})
	builder:DependsOn(channelInit, enableInit)

	local _, maxInit = builder:Checkbox(category, self, "announceMax", L["Special Max Level Message"], L["Replace the normal ding message with a special line when you reach the maximum level."])
	builder:DependsOn(maxInit, enableInit)
end
