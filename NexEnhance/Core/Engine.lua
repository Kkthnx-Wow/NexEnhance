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
local tinsert = table.insert
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
ns.L = ns.L or setmetatable({}, { __index = function(_, key) return key end }) -- Locale (fallback to key)

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
	ns:RegisterEvent(event, function(_, ...) handler(self, ...) end)
end

--- Register a unit-filtered event (UNIT_AURA, UNIT_HEALTH, ...). Far cheaper
--- than a broad RegisterEvent because the client filters by unit token.
function moduleMeta:RegisterUnitEvent(event, handler, ...)
	handler = handler or self[event]
	if type(handler) == "string" then
		handler = self[handler]
	end
	assert(type(handler) == "function", ("NexEnhance: no handler for unit event '%s' on module '%s'"):format(event, self.name))

	ns:RegisterUnitEvent(event, function(_, ...) handler(self, ...) end, ...)
end

--- Returns whether this module is enabled in the active profile. Modules that
--- opt into the toggle convention store `enable` under `db[moduleKey]`.
function moduleMeta:IsEnabled()
	if not ns.db then return false end
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
	end
	moduleByName[name] = module
	tinsert(modules, module)
	return module
end

function ns:GetModule(name)
	return moduleByName[name]
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
	if not callbacks then return end
	for i = 1, #callbacks do
		callbacks[i](event, ...)
	end
end)

function ns:RegisterEvent(event, callback)
	local callbacks = eventCallbacks[event]
	if not callbacks then
		callbacks = {}
		eventCallbacks[event] = callbacks
		eventFrame:RegisterEvent(event)
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
	callbacks[#callbacks + 1] = callback
	return callback
end

function ns:UnregisterEvent(event, callback)
	local callbacks = eventCallbacks[event]
	if not callbacks then return end
	for i = #callbacks, 1, -1 do
		if callbacks[i] == callback then
			table.remove(callbacks, i)
		end
	end
	if #callbacks == 0 then
		eventCallbacks[event] = nil
		eventFrame:UnregisterEvent(event)
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
	if type(fn) ~= "function" then return end

	-- Isolate module faults so one broken module cannot abort the rest.
	local ok, err = pcall(fn, module)
	if not ok then
		ns.F.Print("|cffff5555Error in", module.name, "(" .. method .. "):|r", err)
	end
end

local function Enable()
	if enabled or not initialized then return end
	enabled = true

	for i = 1, #modules do
		local module = modules[i]
		if module:IsEnabled() then
			RunCallback(module, "OnEnable")
		end
	end
end

local function Initialize()
	if initialized then return end
	initialized = true

	-- Saved variables are guaranteed to exist by ADDON_LOADED, so the DB is
	-- built here, before any module touches `ns.db`.
	if ns.SetupDatabase then
		ns:SetupDatabase()
	end

	for i = 1, #modules do
		RunCallback(modules[i], "OnInitialize")
	end

	-- Late load (after login): PLAYER_LOGIN will not fire again, enable now.
	if IsLoggedIn() then
		Enable()
	end
end

local onAddonLoaded
onAddonLoaded = function(_, loadedAddon)
	if loadedAddon ~= addonName then return end
	ns:UnregisterEvent("ADDON_LOADED", onAddonLoaded) -- one-shot
	Initialize()
end

ns:RegisterEvent("ADDON_LOADED", onAddonLoaded)
ns:RegisterEvent("PLAYER_LOGIN", Enable)
