--[[
	NexEnhance - Audio Sync
	-------------------------------------------------------------------------
	Monitors voice chat and audio output device updates and automatically
	resets the game's sound driver.

	WoW still kills all in-game sound when you unplug headphones or switch the
	Windows output device. We listen for the client's device-update event and
	restart the sound subsystem. Blocked during movies/cinematics to avoid stutter.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local F, L = ns.F, ns.L

local CinematicFrame = CinematicFrame
local MovieFrame = MovieFrame
local SetCVar = SetCVar
local Sound_GameSystem_RestartSoundSystem = Sound_GameSystem_RestartSoundSystem

ns:RegisterDefaults({
	audioSync = {
		enable = false,
	},
})

local AudioSync = ns:NewModule("AudioSync", "audioSync", { group = "misc", title = L["Audio Sync"], order = 190 })

local eventHandles = {}

local function SyncAudio()
	if not ns.db.audioSync.enable then
		return
	end
	if not SetCVar then
		return
	end

	-- Force the sound output driver to the system default index (0).
	SetCVar("Sound_OutputDriverIndex", "0")

	-- Restarting the sound system while a movie or cinematic is playing is a great
	-- way to freeze the game client or cause horrible audio desync. Avoid it!
	local inCinematic = (CinematicFrame and CinematicFrame:IsShown()) or (MovieFrame and MovieFrame:IsShown())
	if Sound_GameSystem_RestartSoundSystem and not inCinematic then
		Sound_GameSystem_RestartSoundSystem()
	end
end

function AudioSync:VOICE_CHAT_OUTPUT_DEVICES_UPDATED()
	SyncAudio()
end

function AudioSync:RegisterModuleEvents()
	if self.eventsRegistered then
		return
	end
	self.eventsRegistered = true

	self:TrackEvent(eventHandles, "VOICE_CHAT_OUTPUT_DEVICES_UPDATED")

	-- Run once on load to ensure everything is initialized and synchronized correctly.
	SyncAudio()
end

function AudioSync:UnregisterModuleEvents()
	if not self.eventsRegistered then
		return
	end
	self.eventsRegistered = false

	ns:UnregisterModuleEventHandles(eventHandles)
end

function AudioSync:OnDisable()
	self:UnregisterModuleEvents()
end

function AudioSync:OnSettingChanged(key, value)
	if key ~= "enable" then
		return
	end
	if value then
		self:RegisterModuleEvents()
	else
		self:OnDisable()
	end
end

function AudioSync:OnEnable()
	if ns.db.audioSync.enable then
		self:RegisterModuleEvents()
	end
end

function AudioSync:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Audio Sync"], L["Automatically reset the sound system when audio output devices update (fixes the silent WoW sound bug)."])
end
