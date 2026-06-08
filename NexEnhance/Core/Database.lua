--[[
	NexEnhance - Database
	-------------------------------------------------------------------------
	Lightweight saved-variable manager with profile support, modelled on the
	AceDB layout but with no external dependency.

	Layout of the `NexEnhanceDB` saved variable:
	    {
	        profiles    = { ["Default"] = { ... settings ... } },
	        profileKeys = { ["Char - Realm"] = "Default" },
	        global      = { ... account-wide data ... },
	    }

	`NexEnhanceCharDB` holds genuinely per-character runtime data that should
	never be shared through a profile.

	Modules register their defaults at load time via `ns:RegisterDefaults`,
	then read/write through `ns.db` (active profile) once it is built on
	ADDON_LOADED.
--]]

local _, ns = ...
local C, F = ns.C, ns.F

-- The master default tree. Modules merge their own sub-tables into `profile`.
ns.defaults = {
	profile = {},
	global = {},
}

--- Merge a table of defaults into the profile defaults. Called by modules at
--- file-run time (before the DB is built), e.g.:
---     ns:RegisterDefaults({ autoVendor = { enable = true } })
function ns:RegisterDefaults(defaults, scope)
	scope = scope or "profile"
	F.CopyDefaults(defaults, ns.defaults[scope])
end

-- ---------------------------------------------------------------------------
-- Schema migration
--   Bump DB_SCHEMA_VERSION whenever the saved-variable *layout* changes (a key
--   is renamed/moved/restructured), and add a numbered step to `migrations`.
--   `migrations[v]` upgrades data from version (v-1) to v and runs once, in
--   order, only when older data is loaded. Unstamped data is treated as v1
--   (the baseline before versioning existed), matching the AceDB convention.
-- ---------------------------------------------------------------------------
local DB_SCHEMA_VERSION = 2

local migrations = {
	-- The Battle.net toast and Quick Join button movers were re-defaulted to
	-- the chat's top-left corner. Drop any stale saved positions so the new
	-- anchor takes effect once; the user can still drag them afterwards.
	[2] = function(root)
		for _, profile in pairs(root.profiles) do
			if type(profile.movers) == "table" then
				profile.movers.bnToast = nil
				profile.movers.quickJoinToast = nil
			end
		end
	end,
}

local function MigrateDatabase(root)
	local version = root.schemaVersion or 1
	for v = version + 1, DB_SCHEMA_VERSION do
		local step = migrations[v]
		if step then step(root) end
	end
	root.schemaVersion = DB_SCHEMA_VERSION
end

-- ---------------------------------------------------------------------------
-- Profile management
-- ---------------------------------------------------------------------------

--- Switch the active profile, rebuilding `ns.db` and notifying listeners.
function ns:SetProfile(profileName)
	local root = _G.NexEnhanceDB
	root.profileKeys[C.Player.key] = profileName
	root.profiles[profileName] = root.profiles[profileName] or {}

	-- Apply defaults to the (possibly new) profile and expose it.
	ns.db = F.CopyDefaults(ns.defaults.profile, root.profiles[profileName])
	ns.profileName = profileName

	-- Let modules react to a live profile switch.
	if ns.OnProfileChanged then
		ns:OnProfileChanged(profileName)
	end
end

--- Return a sorted-by-insertion list of existing profile names.
function ns:GetProfiles()
	local list = {}
	for name in pairs(_G.NexEnhanceDB.profiles) do
		list[#list + 1] = name
	end
	table.sort(list)
	return list
end

-- ---------------------------------------------------------------------------
-- Setup (called by the engine on ADDON_LOADED, before module OnInitialize)
-- ---------------------------------------------------------------------------
function ns:SetupDatabase()
	-- Saved variables are nil on a brand-new install; create the skeleton.
	local root = _G.NexEnhanceDB or {}
	_G.NexEnhanceDB = root
	root.profiles = root.profiles or {}
	root.profileKeys = root.profileKeys or {}
	root.global = F.CopyDefaults(ns.defaults.global, root.global)

	-- Upgrade any older saved layout before modules read from it.
	MigrateDatabase(root)

	_G.NexEnhanceCharDB = _G.NexEnhanceCharDB or {}

	-- Resolve which profile this character uses (default to its own key).
	local profileName = root.profileKeys[C.Player.key] or "Default"

	ns.global = root.global
	ns.charDB = _G.NexEnhanceCharDB
	ns:SetProfile(profileName)
end
