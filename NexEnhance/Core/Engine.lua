--[[
	NexEnhance - Engine
	-------------------------------------------------------------------------
	The engine owns the addon namespace, the module system, a single shared
	event dispatcher and the load lifecycle. Every other file consumes the
	namespace handed to it by WoW via `local addonName, ns = ...`.

	Design goals (see deep-research-report-part-1 / part-2):
	  * One global only (`_G.NexEnhance`) - everything else lives on `ns`.
	  * One event frame for the whole addon; modules subscribe through it
	    instead of each creating their own frame and registering duplicates.
	  * Clear lifecycle: OnInitialize (DB ready) -> OnEnable (world ready).
--]]

local addonName, ns = ...

-- Expose a single global handle for debugging and inter-addon access.
_G.NexEnhance = ns

-- Cache hot globals as locals (cheaper than repeated hash lookups).
local CreateFrame = CreateFrame
local IsLoggedIn = IsLoggedIn
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local tinsert = table.insert
local wipe = wipe
local C_AddOns = C_AddOns

-- ---------------------------------------------------------------------------
-- Metadata
-- ---------------------------------------------------------------------------
ns.name = addonName
ns.title = C_AddOns.GetAddOnMetadata(addonName, "Title") or addonName
ns.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "0.0.0"

-- Sub-namespaces populated by the other core files. Declared here so load
-- order never produces a nil index.
ns.C = ns.C or {} -- Constants
ns.F = ns.F or {} -- Functions
ns.L = ns.L or setmetatable({}, {
	__index = function(_, key)
		return key
	end,
}) -- Locale (fallback to key)

-- ---------------------------------------------------------------------------
-- Module registry
-- ---------------------------------------------------------------------------
local modules = {} -- ordered list (preserves registration order for OnEnable)
local moduleByName = {} -- name -> module lookup

ns.modules = modules

local moduleMeta = {}
moduleMeta.__index = moduleMeta

--- Register an event against this module. The handler may be a function or
--- the name of a method on the module. When omitted, a method named exactly
--- after the event is used (the common WoW convention).
function moduleMeta:RegisterEvent(event, handler)
	handler = handler or self[event]
	if type(handler) == "string" then
		handler = self[handler]
	end
	assert(type(handler) == "function", ("NexEnhance: no handler for event '%s' on module '%s'"):format(event, self.name))

	-- Bind `self` once at registration time so the dispatch path stays cheap.
	-- Module handlers receive (self, ...payload) only — NOT the event name.
	-- See .cursor/rules/nexenhance-conventions.mdc § "Module RegisterEvent".
	-- Return the wrapper so callers can store it and pass it to ns:UnregisterEvent.
	local wrapper = function(_, ...)
		handler(self, ...)
	end
	return ns:RegisterEvent(event, wrapper)
end

--- Register a unit-filtered event (UNIT_AURA, UNIT_HEALTH, ...). Far cheaper
--- than a broad RegisterEvent because the client filters by unit token.
function moduleMeta:RegisterUnitEvent(event, handler, ...)
	handler = handler or self[event]
	if type(handler) == "string" then
		handler = self[handler]
	end
	assert(type(handler) == "function", ("NexEnhance: no handler for unit event '%s' on module '%s'"):format(event, self.name))

	return ns:RegisterUnitEvent(event, function(_, ...)
		handler(self, ...)
	end, ...)
end

--- Register `event` and append `{ event, wrapper }` to `handles` for teardown.
function moduleMeta:TrackEvent(handles, event, handler)
	handles[#handles + 1] = { event, self:RegisterEvent(event, handler) }
end

--- Register a unit event and append its handle to `handles`.
function moduleMeta:TrackUnitEvent(handles, event, handler, ...)
	handles[#handles + 1] = { event, self:RegisterUnitEvent(event, handler, ...) }
end

--- Returns whether this module is enabled in the active profile. Modules that
--- opt into the toggle convention store `enable` under `db[moduleKey]`.
function moduleMeta:IsEnabled()
	if not ns.db then
		return false
	end
	local settings = self.dbKey and ns.db[self.dbKey]
	if settings and settings.enable ~= nil then
		return settings.enable
	end
	return true
end

--- Create (or fetch) a module. `dbKey` ties the module to a settings table in
--- the active profile so `module:IsEnabled()` works out of the box.
--- `opts` is optional presentation metadata used by the options panel:
---   { group = "actionbars", title = "Action Bars", order = 10 }
--- `group` buckets the module into a themed settings subcategory, `title` is
--- the section header shown above its options, and `order` sorts within a group.
function ns:NewModule(name, dbKey, opts)
	assert(not moduleByName[name], ("NexEnhance: module '%s' already exists"):format(name))

	local module = setmetatable({ name = name, dbKey = dbKey }, moduleMeta)
	if opts then
		module.group = opts.group
		module.title = opts.title
		module.order = opts.order
		-- Version this module first shipped in. When it matches the running
		-- addon version, the landing page flags it with a glowing "New!" badge;
		-- the tag goes inert automatically on later versions (auto-detection via
		-- the account-wide knownModules record takes over from there).
		module.since = opts.since
	end
	moduleByName[name] = module
	tinsert(modules, module)
	return module
end

function ns:GetModule(name)
	return moduleByName[name]
end

--- Register a module table that was not created via NewModule (third-party plugins).
--- Attaches RegisterEvent / IsEnabled and adds the entry to the module registry.
function ns:RegisterAddonModule(module)
	assert(type(module) == "table" and type(module.name) == "string", "RegisterAddonModule: invalid module")
	assert(not moduleByName[module.name], ("NexEnhance: module '%s' already exists"):format(module.name))
	setmetatable(module, moduleMeta)
	moduleByName[module.name] = module
	tinsert(modules, module)
	return module
end

-- ---------------------------------------------------------------------------
-- Central event dispatcher
--   One frame for the whole addon. Each event maps to an array of callbacks
--   which are invoked in registration order. Arrays (not hash sets) keep the
--   dispatch loop allocation-free and ordered.
-- ---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame", "NexEnhanceEventFrame")
local eventCallbacks = {} -- event -> { callback, callback, ... }

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local callbacks = eventCallbacks[event]
	if not callbacks then
		return
	end
	-- Slots may be tombstoned (set to false) by UnregisterEvent, including by a
	-- callback unregistering itself mid-dispatch, so skip any falsy entry. We
	-- never table.remove during a fire, which keeps indices stable and avoids
	-- skipping the callback that follows a removed one.
	for i = 1, #callbacks do
		local callback = callbacks[i]
		if callback then
			callback(event, ...)
		end
	end
end)

function ns:RegisterEvent(event, callback)
	local callbacks = eventCallbacks[event]
	if not callbacks then
		callbacks = {}
		eventCallbacks[event] = callbacks
		eventFrame:RegisterEvent(event)
	end
	-- Fill a tombstoned slot if one exists (so add/remove cycles don't grow the
	-- array); this never shifts indices, so it's safe even mid-dispatch.
	for i = 1, #callbacks do
		if not callbacks[i] then
			callbacks[i] = callback
			return callback
		end
	end
	callbacks[#callbacks + 1] = callback
	return callback
end

function ns:RegisterUnitEvent(event, callback, ...)
	local callbacks = eventCallbacks[event]
	if not callbacks then
		callbacks = {}
		eventCallbacks[event] = callbacks
		eventFrame:RegisterUnitEvent(event, ...)
	end
	-- Fill a tombstoned slot if one exists (mirrors RegisterEvent; prevents
	-- add/remove cycles from growing the array unboundedly for unit events).
	for i = 1, #callbacks do
		if not callbacks[i] then
			callbacks[i] = callback
			return callback
		end
	end
	callbacks[#callbacks + 1] = callback
	return callback
end

function ns:UnregisterEvent(event, callback)
	local callbacks = eventCallbacks[event]
	if not callbacks then
		return
	end

	-- Tombstone (don't table.remove) so this is safe to call mid-dispatch: the
	-- OnEvent loop keeps stable indices and just skips falsy slots.
	local anyLive = false
	for i = 1, #callbacks do
		if callbacks[i] == callback then
			callbacks[i] = false
		elseif callbacks[i] then
			anyLive = true
		end
	end

	if not anyLive then
		eventCallbacks[event] = nil
		eventFrame:UnregisterEvent(event)
		return
	end

	-- Compact when tombstones outnumber live slots (> half are dead). Rebuilding
	-- the array is O(n) — same cost as we already paid above — and keeps the
	-- dispatch loop short for high-churn events like UNIT_AURA.
	local live, total = 0, #callbacks
	for i = 1, total do
		if callbacks[i] then
			live = live + 1
		end
	end
	if live < total / 2 then
		local compact = {}
		for i = 1, total do
			if callbacks[i] then
				compact[#compact + 1] = callbacks[i]
			end
		end
		eventCallbacks[event] = compact
	end
end

--- Unregister every `{ event, wrapper }` entry stored in `handles`, then wipe it.
function ns:UnregisterModuleEventHandles(handles)
	if not handles then
		return
	end
	for i = 1, #handles do
		local h = handles[i]
		if h then
			ns:UnregisterEvent(h[1], h[2])
		end
	end
	wipe(handles)
end

-- ---------------------------------------------------------------------------
-- Deferred work (combat, addon load, loading screen)
-- ---------------------------------------------------------------------------
local combatDeferred = {}
local combatDeferredN = 0
local combatEnterListeners = {}
local combatEnterN = 0
local combatLeaveListeners = {}
local combatLeaveN = 0
local combatBusHooked = false

local function FlushCombatDeferred()
	local n = combatDeferredN
	if n == 0 then
		return
	end
	combatDeferredN = 0
	for i = 1, n do
		local fn = combatDeferred[i]
		combatDeferred[i] = nil
		if fn then
			fn()
		end
	end
end

local function EnsureCombatDeferHook()
	EnsureCombatBus()
end

local function OnPlayerRegenDisabled()
	for i = 1, combatEnterN do
		local fn = combatEnterListeners[i]
		if fn then
			fn()
		end
	end
end

local function FinishRegenLeave()
	FlushCombatDeferred()
	for i = 1, combatLeaveN do
		local fn = combatLeaveListeners[i]
		if fn then
			fn()
		end
	end
end

local regenRetryPending = false

local function OnPlayerRegenEnabled()
	-- Blizzard sometimes fires regen before lockdown fully lifts. One immediate
	-- attempt, then a next-frame (and one delayed) retry — otherwise
	-- AfterCombatCallback queues can stall until the next fight ends.
	local function attempt()
		if InCombatLockdown() then
			return false
		end
		FinishRegenLeave()
		return true
	end

	if attempt() then
		return
	end

	if regenRetryPending then
		return
	end
	regenRetryPending = true

	C_Timer.After(0, function()
		if attempt() then
			regenRetryPending = false
			return
		end
		C_Timer.After(0.1, function()
			regenRetryPending = false
			attempt()
		end)
	end)
end

local function EnsureCombatBus()
	if combatBusHooked then
		return
	end
	combatBusHooked = true
	ns:RegisterEvent("PLAYER_REGEN_DISABLED", OnPlayerRegenDisabled)
	ns:RegisterEvent("PLAYER_REGEN_ENABLED", OnPlayerRegenEnabled)
end

--- Subscribe to combat start (`PLAYER_REGEN_DISABLED`). Returns an id for optional removal.
function ns:RegisterCombatEnterCallback(fn)
	if type(fn) ~= "function" then
		return
	end
	EnsureCombatBus()
	combatEnterN = combatEnterN + 1
	combatEnterListeners[combatEnterN] = fn
	return combatEnterN
end

--- Subscribe to combat end (`PLAYER_REGEN_ENABLED`, after lockdown lifts). Returns an id.
function ns:RegisterCombatLeaveCallback(fn)
	if type(fn) ~= "function" then
		return
	end
	EnsureCombatBus()
	combatLeaveN = combatLeaveN + 1
	combatLeaveListeners[combatLeaveN] = fn
	return combatLeaveN
end

--- Remove a combat-enter subscription returned by `RegisterCombatEnterCallback`.
function ns:UnregisterCombatEnterCallback(id)
	if id and combatEnterListeners[id] then
		combatEnterListeners[id] = nil
	end
end

--- Remove a combat-leave subscription returned by `RegisterCombatLeaveCallback`.
function ns:UnregisterCombatLeaveCallback(id)
	if id and combatLeaveListeners[id] then
		combatLeaveListeners[id] = nil
	end
end

--- Wrap a hook callback so it no-ops when `module` is disabled (hooksecurefunc
--- cannot be removed; gate live toggles instead of requiring /reload).
--- Skin modules usually inline `module:IsEnabled()` at the hook top; this helper
--- is optional sugar for the same pattern.
function ns:GuardModuleHook(module, fn)
	return function(...)
		if module and module.IsEnabled and not module:IsEnabled() then
			return
		end
		return fn(...)
	end
end

--- Run `fn` now when out of combat, otherwise after `PLAYER_REGEN_ENABLED`.
function ns:AfterCombatCallback(fn)
	if type(fn) ~= "function" then
		return
	end
	if not InCombatLockdown() then
		fn()
		return
	end
	combatDeferredN = combatDeferredN + 1
	combatDeferred[combatDeferredN] = fn
	EnsureCombatDeferHook()
end

local addonLoadedCallbacks = {}
local addonLoadedDispatcher = false

local function DispatchAddonLoaded(loadedAddon)
	local list = addonLoadedCallbacks[loadedAddon]
	if not list then
		return
	end
	for i = 1, #list do
		local fn = list[i]
		if fn then
			fn(loadedAddon)
		end
	end
end

local function EnsureAddonLoadedDispatcher()
	if addonLoadedDispatcher then
		return
	end
	addonLoadedDispatcher = true
	ns:RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
		DispatchAddonLoaded(loadedAddon)
	end)
end

--- Run `callback` when `addonName` loads (or immediately if already loaded).
function ns:RegisterAddOnLoadedCallback(addonName, callback)
	if not (addonName and callback) then
		return
	end
	EnsureAddonLoadedDispatcher()
	local list = addonLoadedCallbacks[addonName]
	if not list then
		list = {}
		addonLoadedCallbacks[addonName] = list
	end
	list[#list + 1] = callback
	if C_AddOns.IsAddOnLoaded(addonName) then
		callback(addonName)
	end
end

local loadingCompleteCallbacks = {}
local loadingCompleteFired = false
local loadingCompleteScheduled = false

local function FireLoadingComplete()
	if loadingCompleteFired then
		return
	end
	loadingCompleteFired = true
	for i = 1, #loadingCompleteCallbacks do
		local fn = loadingCompleteCallbacks[i]
		if fn then
			fn()
		end
	end
end

local function ScheduleLoadingComplete()
	if loadingCompleteFired or loadingCompleteScheduled then
		return
	end
	loadingCompleteScheduled = true
	C_Timer.After(0, function()
		loadingCompleteScheduled = false
		FireLoadingComplete()
	end)
end

--- Run `callback` once after the loading screen finishes (and on /reload via
--- PLAYER_LOGIN fallback). Safe to call after completion — runs immediately.
function ns:RegisterLoadingCompleteCallback(callback)
	if type(callback) ~= "function" then
		return
	end
	if loadingCompleteFired then
		callback()
		return
	end
	loadingCompleteCallbacks[#loadingCompleteCallbacks + 1] = callback
end

ns:RegisterEvent("LOADING_SCREEN_DISABLED", ScheduleLoadingComplete)

-- ---------------------------------------------------------------------------
-- Internal signal bus (pub/sub)
--   The dispatcher above is for *WoW game events*. This bus is for *internal*
--   addon signals, so modules can react to one another without holding hard
--   references - e.g. the options panel broadcasts "SettingChanged.tooltip.enable"
--   and any number of unrelated modules subscribe to it.
--
--   A subscriber is either a plain function or the *name* of a method on
--   `owner`. Binding `owner` up front avoids a per-subscription closure.
--
--     ns:RegisterCallback("SettingChanged.tooltip.enable", "RefreshAnchors", self)
--     ns:RegisterCallback("SettingChanged.tooltip.enable", function(value) ... end)
--     ns:TriggerCallback("SettingChanged.tooltip.enable", true)
-- ---------------------------------------------------------------------------
local signalCallbacks = {} -- signal -> { { callback, owner, isMethod }, ... }

--- Subscribe `callback` to `signal`. `callback` is a function or a method name
--- on `owner`. When `owner` is given it is passed as the first argument
--- (function form) or the receiver (method form). Returns `callback` so the
--- caller can keep a handle for UnregisterCallback.
function ns:RegisterCallback(signal, callback, owner)
	local list = signalCallbacks[signal]
	if not list then
		list = {}
		signalCallbacks[signal] = list
	end
	list[#list + 1] = { callback, owner, type(callback) == "string" }
	return callback
end

--- Fire `signal`, invoking every subscriber in registration order with `...`.
--- Allocation-free on the hot path (no varargs repacking).
function ns:TriggerCallback(signal, ...)
	local list = signalCallbacks[signal]
	if not list then
		return
	end
	-- Tombstoned slots are skipped, so subscribers can unregister mid-fire
	-- without shifting the callback that follows them.
	for i = 1, #list do
		local cb = list[i]
		if cb then
			if cb[3] then
				cb[2][cb[1]](cb[2], ...) -- owner:method(...)
			elseif cb[2] then
				cb[1](cb[2], ...) -- func(owner, ...)
			else
				cb[1](...) -- func(...)
			end
		end
	end
end

--- Remove a previously registered callback, matched by `callback` (function or
--- method name) and `owner`. Safe to call from within a fired callback.
function ns:UnregisterCallback(signal, callback, owner)
	local list = signalCallbacks[signal]
	if not list then
		return
	end

	local anyLive = false
	for i = 1, #list do
		local cb = list[i]
		if cb and cb[1] == callback and cb[2] == owner then
			list[i] = false
		elseif cb then
			anyLive = true
		end
	end

	if not anyLive then
		signalCallbacks[signal] = nil
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
--   ADDON_LOADED -> Initialize() : saved variables are ready, build the DB
--                                  and run each module's OnInitialize.
--   PLAYER_LOGIN  -> Enable()    : the world is ready, run each enabled
--                                  module's OnEnable.
--   The flags make both paths idempotent and handle late (LoadOnDemand)
--   loads where PLAYER_LOGIN has already fired.
-- ---------------------------------------------------------------------------
local initialized, enabled = false, false

local function RunCallback(module, method)
	local fn = module[method]
	if type(fn) ~= "function" then
		return
	end

	-- Isolate module faults so one broken module cannot abort the rest.
	local ok, err = pcall(fn, module)
	if not ok then
		ns.F.Print("|cffff5555Error in", module.name, "(" .. method .. "):|r", err)
	end
end

local function Enable()
	if enabled or not initialized then
		return
	end
	enabled = true

	for i = 1, #modules do
		local module = modules[i]
		if not module.isPlugin and module:IsEnabled() then
			RunCallback(module, "OnEnable")
		end
	end

	if ns.OnCoreEnabled then
		ns:OnCoreEnabled()
	end

	ScheduleLoadingComplete()
end

local function Initialize()
	if initialized then
		return
	end
	initialized = true

	-- Saved variables are guaranteed to exist by ADDON_LOADED, so the DB is
	-- built here, before any module touches `ns.db`.
	if ns.SetupDatabase then
		ns:SetupDatabase()
	end

	for i = 1, #modules do
		RunCallback(modules[i], "OnInitialize")
	end

	if ns.OnCoreInitialized then
		ns:OnCoreInitialized()
	end

	-- Late load (after login): PLAYER_LOGIN will not fire again, enable now.
	if IsLoggedIn() then
		Enable()
	end
end

local onAddonLoaded
onAddonLoaded = function(_, loadedAddon)
	if loadedAddon ~= addonName then
		return
	end
	ns:UnregisterEvent("ADDON_LOADED", onAddonLoaded) -- one-shot
	Initialize()
end

ns:RegisterEvent("ADDON_LOADED", onAddonLoaded)
ns:RegisterEvent("PLAYER_LOGIN", Enable)
ns:RegisterEvent("PLAYER_LOGOUT", function()
	if ns.CompactActiveProfile then
		ns:CompactActiveProfile()
	end
end)
