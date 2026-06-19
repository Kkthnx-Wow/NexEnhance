--[[
	NexEnhance - Plugin API
	-------------------------------------------------------------------------
	Third-party addons extend NexEnhance by calling NexEnhance:RegisterPlugin(...)
	after NexEnhance has loaded. Plugins are separate WoW addons that declare
	## Dependencies: NexEnhance in their .toc.

	Plugins reuse the same lifecycle, profile DB, settings builder, and event
	dispatch as built-in modules — they appear under NexEnhance → Plugins in
	the settings panel (or a group the author chooses).

	See Examples/NexEnhancePluginTemplate/ for a starter project.
--]]

local _, ns = ...
local F = ns.F
local L = ns.L

local IsLoggedIn = IsLoggedIn
local tinsert = table.insert
local format = string.format
local type = type

-- Bump when the RegisterPlugin contract changes incompatibly.
ns.API_VERSION = 1

local plugins = {}
local pluginById = {}

ns.plugins = plugins

local coreInitialized = false
local coreEnabled = false

local function RunPluginCallback(plugin, method)
	local fn = plugin[method]
	if type(fn) ~= "function" then
		return
	end
	local ok, err = pcall(fn, plugin)
	if not ok and F.Print then
		F.Print("|cffff5555Error in plugin", plugin.name, "(" .. method .. "):|r", err)
	end
end

local function MergePluginDefaults(plugin, spec)
	local dbKey = plugin.dbKey
	local profileDefaults = spec.defaults or { enable = true }
	ns:RegisterDefaults({ [dbKey] = profileDefaults })

	if spec.globalDefaults then
		ns:RegisterDefaults({ [dbKey] = spec.globalDefaults }, "global")
	end

	if coreInitialized and ns.db and F.CopyDefaults then
		ns.db[dbKey] = F.CopyDefaults(profileDefaults, ns.db[dbKey] or {})
	end
end

local function ActivatePlugin(plugin)
	if plugin.active then
		return
	end
	plugin.active = true

	RunPluginCallback(plugin, "OnInitialize")

	if coreEnabled and plugin:IsEnabled() then
		RunPluginCallback(plugin, "OnEnable")
	end

	ns:TriggerCallback("Plugin.Registered", plugin)
end

local function EnablePlugin(plugin)
	if not plugin.active or not plugin:IsEnabled() then
		return
	end
	RunPluginCallback(plugin, "OnEnable")
end

local function DisablePlugin(plugin)
	RunPluginCallback(plugin, "OnDisable")
end

--- Internal: called by the engine after SetupDatabase + module OnInitialize.
function ns:OnCoreInitialized()
	coreInitialized = true
	for i = 1, #plugins do
		if not plugins[i].active then
			ActivatePlugin(plugins[i])
		end
	end
end

--- Internal: called by the engine after built-in module OnEnable pass.
function ns:OnCoreEnabled()
	coreEnabled = true
	for i = 1, #plugins do
		local plugin = plugins[i]
		if plugin.active and plugin:IsEnabled() then
			RunPluginCallback(plugin, "OnEnable")
		end
	end
end

--- Apply an enable/disable toggle for a plugin (settings panel or /nex toggle).
function ns:ApplyPluginEnable(plugin, enabled)
	if not plugin or not plugin.isPlugin then
		return
	end
	if enabled then
		EnablePlugin(plugin)
	else
		DisablePlugin(plugin)
	end
end

local function ValidateSpec(spec)
	assert(type(spec) == "table", "NexEnhance:RegisterPlugin expects a table")
	assert(type(spec.id) == "string" and spec.id ~= "", "RegisterPlugin: id is required (e.g. 'Author.MyAddon')")
	assert(type(spec.name) == "string" and spec.name ~= "", "RegisterPlugin: name is required")
	assert(type(spec.dbKey) == "string" and spec.dbKey ~= "", "RegisterPlugin: dbKey is required")
	assert(not spec.dbKey:find("%s"), "RegisterPlugin: dbKey must not contain spaces")
	assert(type(spec.title) == "string" and spec.title ~= "", "RegisterPlugin: title is required")
end

--- Register a third-party plugin. Returns the plugin handle (same table shape as
--- a built-in module: RegisterEvent, IsEnabled, etc.).
---
--- Required fields:
---   id      — unique string, e.g. "MyName.MyFeature"
---   name    — internal name (used by /nex toggle)
---   title   — display name in settings
---   dbKey   — profile settings key (must not collide with a built-in module)
---
--- Recommended: version, author, notes, defaults = { enable = true }, addon
--- Optional: group (default "plugins"), order, globalDefaults, website
--- Lifecycle: OnInitialize, OnEnable, OnDisable, OnSettingChanged, RegisterOptions
function ns:RegisterPlugin(spec)
	ValidateSpec(spec)

	if pluginById[spec.id] then
		return pluginById[spec.id]
	end

	if ns:GetModule(spec.name) then
		error(format("NexEnhance:RegisterPlugin: name '%s' is already in use", spec.name))
	end

	if ns.defaults.profile[spec.dbKey] then
		error(format("NexEnhance:RegisterPlugin: dbKey '%s' conflicts with an existing module", spec.dbKey))
	end

	local plugin = {
		name = spec.name,
		dbKey = spec.dbKey,
		id = spec.id,
		isPlugin = true,
		title = spec.title,
		group = spec.group or "plugins",
		order = spec.order or 100,
		pluginVersion = spec.version or "?",
		author = spec.author or L["Unknown"],
		notes = spec.notes or "",
		website = spec.website,
		addon = spec.addon,
		since = spec.since,
	}

	local lifecycle = { "OnInitialize", "OnEnable", "OnDisable", "OnSettingChanged", "RegisterOptions" }
	for i = 1, #lifecycle do
		local key = lifecycle[i]
		if spec[key] then
			plugin[key] = spec[key]
		end
	end

	ns:RegisterAddonModule(plugin)
	pluginById[spec.id] = plugin
	tinsert(plugins, plugin)

	MergePluginDefaults(plugin, spec)

	if coreInitialized then
		ActivatePlugin(plugin)
	elseif IsLoggedIn() then
		ActivatePlugin(plugin)
	end

	if coreEnabled and ns.optionsBuilt and spec.RegisterOptions and F.Print then
		F.Print(F.Colorize(L["PLUGIN_RELOAD_FOR_OPTIONS"], "brand"))
	end

	return plugin
end

function ns:GetPlugin(id)
	return pluginById[id]
end

function ns:GetPlugins()
	return plugins
end

function ns:IsPluginRegistered(id)
	return pluginById[id] ~= nil
end

-- Profile switches: refresh every active plugin.
local priorProfileChanged = ns.OnProfileChanged
function ns:OnProfileChanged(profileName)
	for i = 1, #plugins do
		local plugin = plugins[i]
		if plugin.active then
			RunPluginCallback(plugin, "OnDisable")
			if plugin:IsEnabled() then
				RunPluginCallback(plugin, "OnEnable")
			end
		end
	end
	if priorProfileChanged then
		priorProfileChanged(self, profileName)
	end
end
