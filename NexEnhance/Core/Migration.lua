--[[
	NexEnhance - Migration
	-------------------------------------------------------------------------
	Two complementary upgrade paths for SavedVariables:

	1) Schema version steps (`ns:RegisterSchemaMigration(v, fn)`)
	   Ordered bumps of `root.schemaVersion`. Use when the SV *layout* changes
	   (key renamed/moved). Bump DB_SCHEMA_VERSION and add a step.

	2) Named one-shot migrations (`ns:RegisterMigration({ id, scope, body })`)
	   Idempotent, pcall-wrapped, stamped per-scope in `_migrations[id]`.
	   Modules register at file load, the runner walks every profile/global once
	   during SetupDatabase (before defaults merge into the active profile).

	Scopes:
	  root    - whole NexEnhanceDB (ctx.root)
	  global  - root.global (ctx.global)
	  profile - each root.profiles[name] (ctx.profile, ctx.profileName)
	  char    - NexEnhanceCharDB (ctx.char)

	Authoring: ids are forever, bodies must be safe to re-run, never call live
	character APIs here (ADDON_LOADED / SetupDatabase timing).
--]]

local _, ns = ...
local F = ns.F

local pairs = pairs
local type = type
local pcall = pcall
local tostring = tostring

-- ---------------------------------------------------------------------------
-- Schema version steps (ordered)
-- ---------------------------------------------------------------------------
local DB_SCHEMA_VERSION = 4
local schemaSteps = {}

--- Register an upgrade from version (v-1) to v. Idempotent by version stamp.
function ns:RegisterSchemaMigration(version, body)
	if type(version) ~= "number" or type(body) ~= "function" then
		error("RegisterSchemaMigration: need (number, function)", 2)
	end
	if schemaSteps[version] then
		error("RegisterSchemaMigration: duplicate version " .. tostring(version), 2)
	end
	schemaSteps[version] = body
end

function ns:GetDBSchemaVersion()
	return DB_SCHEMA_VERSION
end

-- ---------------------------------------------------------------------------
-- Named one-shot migrations
-- ---------------------------------------------------------------------------
local namedMigrations = {}
local namedById = {}
local VALID_SCOPES = {
	root = true,
	global = true,
	profile = true,
	char = true,
}

--- Register a named migration. See file header for scopes and guarantees.
function ns:RegisterMigration(spec)
	if type(spec) ~= "table" then
		error("RegisterMigration: spec must be a table", 2)
	end
	if type(spec.id) ~= "string" or spec.id == "" then
		error("RegisterMigration: spec.id must be a non-empty string", 2)
	end
	if type(spec.body) ~= "function" then
		error("RegisterMigration: spec.body must be a function", 2)
	end
	if not VALID_SCOPES[spec.scope] then
		error("RegisterMigration: scope must be root|global|profile|char", 2)
	end
	if namedById[spec.id] then
		error("RegisterMigration: duplicate id '" .. spec.id .. "'", 2)
	end
	namedMigrations[#namedMigrations + 1] = spec
	namedById[spec.id] = spec
end

local function FlagTable(host)
	if type(host) ~= "table" then
		return nil
	end
	host._migrations = host._migrations or {}
	return host._migrations
end

local function RunNamedOne(spec, ctx, flagHost)
	local flags = FlagTable(flagHost)
	if not flags or flags[spec.id] then
		return
	end
	local ok, err = pcall(spec.body, ctx)
	if ok then
		flags[spec.id] = true
	elseif F and F.Print then
		-- Stamp only on success so a broken body retries next login.
		F.Print("Migration failed:", spec.id, tostring(err))
	end
end

local function RunNamedMigrations(root)
	local charDB = _G.NexEnhanceCharDB
	for i = 1, #namedMigrations do
		local spec = namedMigrations[i]
		if spec.scope == "root" then
			RunNamedOne(spec, { root = root }, root)
		elseif spec.scope == "global" then
			root.global = root.global or {}
			RunNamedOne(spec, { root = root, global = root.global }, root.global)
		elseif spec.scope == "profile" then
			if type(root.profiles) == "table" then
				for name, profile in pairs(root.profiles) do
					if type(profile) == "table" then
						RunNamedOne(spec, {
							root = root,
							profile = profile,
							profileName = name,
						}, profile)
					end
				end
			end
		elseif spec.scope == "char" then
			if type(charDB) == "table" then
				RunNamedOne(spec, { root = root, char = charDB }, charDB)
			end
		end
	end
end

local function RunSchemaMigrations(root)
	local version = root.schemaVersion or 1
	for v = version + 1, DB_SCHEMA_VERSION do
		local step = schemaSteps[v]
		if step then
			local ok, err = pcall(step, root)
			if not ok and F and F.Print then
				F.Print("Schema migration failed:", v, tostring(err))
				-- Stop advancing so we retry this step next session.
				return
			end
		end
	end
	root.schemaVersion = DB_SCHEMA_VERSION
end

--- Run schema steps then named migrations. Called from SetupDatabase.
function ns:RunAllMigrations(root)
	if type(root) ~= "table" then
		return
	end
	RunSchemaMigrations(root)
	RunNamedMigrations(root)
end

-- ---------------------------------------------------------------------------
-- Built-in schema steps (formerly inline in Database.lua)
-- ---------------------------------------------------------------------------

-- The Battle.net toast and Quick Join button movers were re-defaulted to
-- the chat's top-left corner. Drop any stale saved positions so the new
-- anchor takes effect once, the user can still drag them afterwards.
ns:RegisterSchemaMigration(2, function(root)
	for _, profile in pairs(root.profiles) do
		if type(profile.movers) == "table" then
			profile.movers.bnToast = nil
			profile.movers.quickJoinToast = nil
		end
	end
end)

-- The Loot Roll bar was re-defaulted to a larger width/height. Drop any
-- stale saved sizes so the new defaults take effect once, the sliders still
-- let the user resize afterwards.
ns:RegisterSchemaMigration(3, function(root)
	for _, profile in pairs(root.profiles) do
		if type(profile.lootRoll) == "table" then
			profile.lootRoll.width = nil
			profile.lootRoll.height = nil
		end
	end
end)

-- Quest Navigation skin merged into Map Pin Navigation (UMPD-style).
ns:RegisterSchemaMigration(4, function(root)
	for _, profile in pairs(root.profiles) do
		local old = profile.questNavigation
		if type(old) == "table" then
			profile.mapPinNavigation = profile.mapPinNavigation or {}
			local new = profile.mapPinNavigation
			if old.enable ~= nil and new.enable == nil then
				new.enable = old.enable
			end
			if new.showEta == nil then
				new.showEta = old.enable ~= false
			end
			profile.questNavigation = nil
		end
	end
end)

-- ClassColors.colorReputation -> TargetFrameLayout.enable (was per-char OnInitialize).
ns:RegisterMigration({
	id = "target_frame_layout_from_classcolors_reputation",
	scope = "profile",
	body = function(ctx)
		local profile = ctx.profile
		local legacy = profile.classColors and profile.classColors.colorReputation
		if not legacy then
			return
		end
		profile.targetFrameLayout = profile.targetFrameLayout or {}
		if profile.targetFrameLayout.enable == nil then
			profile.targetFrameLayout.enable = true
		end
	end,
})
