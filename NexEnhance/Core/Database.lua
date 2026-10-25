--[[
	NexEnhance - Database
	-------------------------------------------------------------------------
	Lightweight saved-variable manager with profile support - no external DB library.

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

-- Schema / named migrations live in Core/Migration.lua (`ns:RunAllMigrations`).

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

--- Whether a profile with this name already exists.
function ns:ProfileExists(name)
	return _G.NexEnhanceDB.profiles[name] ~= nil
end

-- Deep copy without touching metatables (profiles are plain data trees).
local function DeepCopy(src)
	local dst = {}
	for k, v in pairs(src) do
		if type(v) == "table" then
			dst[k] = DeepCopy(v)
		else
			dst[k] = v
		end
	end
	return dst
end

--- Create `newName` as a deep copy of the *active* profile's stored settings.
--- Does not switch to it, callers typically follow with ns:SetProfile(newName).
function ns:CopyProfileInto(newName)
	local root = _G.NexEnhanceDB
	if root.profiles[newName] then
		return false
	end
	root.profiles[newName] = DeepCopy(root.profiles[ns.profileName] or {})
	return true
end

--- Overwrite the active profile with a deep copy of another existing profile.
--- Source stays untouched, destination is the profile this character is using.
function ns:CopyProfileFrom(sourceName)
	local root = _G.NexEnhanceDB
	if sourceName == ns.profileName or type(root.profiles[sourceName]) ~= "table" then
		return false
	end

	root.profiles[ns.profileName] = DeepCopy(root.profiles[sourceName])
	ns.db = F.CopyDefaults(ns.defaults.profile, root.profiles[ns.profileName])

	if ns.OnProfileChanged then
		ns:OnProfileChanged(ns.profileName)
	end
	return true
end

--- Reset the active profile back to defaults.
function ns:ResetProfile()
	local root = _G.NexEnhanceDB
	root.profiles[ns.profileName] = {}
	ns.db = F.CopyDefaults(ns.defaults.profile, root.profiles[ns.profileName])

	if ns.OnProfileChanged then
		ns:OnProfileChanged(ns.profileName)
	end
	return true
end

--- Delete a profile. Refuses to delete the active profile (there must always be
--- one). Any other character pointing at it falls back to "Default" next login.
function ns:DeleteProfile(name)
	if name == ns.profileName then
		return false
	end

	local root = _G.NexEnhanceDB
	root.profiles[name] = nil
	for key, used in pairs(root.profileKeys) do
		if used == name then
			root.profileKeys[key] = nil
		end
	end
	return true
end

-- ---------------------------------------------------------------------------
-- Setup (called by the engine on ADDON_LOADED, before module OnInitialize)
-- ---------------------------------------------------------------------------
function ns:SetupDatabase()
	F.RefreshPlayerContext()

	-- Saved variables are nil on a brand-new install, create the skeleton.
	local root = _G.NexEnhanceDB or {}
	_G.NexEnhanceDB = root
	root.profiles = root.profiles or {}
	root.profileKeys = root.profileKeys or {}
	root.global = F.CopyDefaults(ns.defaults.global, root.global)

	-- Upgrade any older saved layout before modules read from it.
	ns:RunAllMigrations(root)

	_G.NexEnhanceCharDB = _G.NexEnhanceCharDB or {}

	-- Resolve which profile this character uses (default to its own key).
	local profileName = root.profileKeys[C.Player.key] or "Default"

	ns.global = root.global
	ns.charDB = _G.NexEnhanceCharDB
	ns:SetProfile(profileName)
end

--- Strip default-equal keys from the active profile before logout (sparse SV).
function ns:CompactActiveProfile()
	local root = _G.NexEnhanceDB
	if not root or not ns.profileName then
		return
	end
	local profile = root.profiles[ns.profileName]
	if profile then
		F.CompactDefaults(ns.defaults.profile, profile)
	end
end
