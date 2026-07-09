--[[
	NexEnhance - Realm Catalog
	-------------------------------------------------------------------------
	Resolves a realm display name to Blizzard realm-list metadata (locale,
	region, timezone). There is no in-game API for arbitrary realm→region
	lookups; this table is generated from the same client realm list used on
	the login screen (see Tools/gen_realm_catalog.py).

	Runtime context uses GetCurrentRegionName(), GetRealmName(), and
	GetNormalizedRealmName().
--]]

local _, ns = ...
local RealmCatalog = {}
ns.RealmCatalog = RealmCatalog

local gsub = string.gsub
local GetCurrentRegionName = GetCurrentRegionName
local GetRealmName = GetRealmName
local GetNormalizedRealmName = GetNormalizedRealmName

local REALM_DATA = ns.RealmCatalogData or {}

local normalizedIndex = {}
local playerRegion
local playerTag

local function NormalizeRealmKey(name)
	return name and gsub(name, "[%s%-']", "") or ""
end

local function LocaleToTag(locale, timezone)
	if timezone == "AEST" then
		return "OCE"
	end
	if locale and #locale >= 4 then
		return locale:sub(3, 4)
	end
end

local function BuildNormalizedIndex()
	for name, info in pairs(REALM_DATA) do
		normalizedIndex[NormalizeRealmKey(name)] = info
	end
end

function RealmCatalog:LookupRealm(realmName)
	if not realmName then
		return
	end
	local info = REALM_DATA[realmName]
	if info then
		return info
	end
	return normalizedIndex[NormalizeRealmKey(realmName)]
end

function RealmCatalog:ParseLeaderRealm(leaderName)
	if not leaderName or leaderName == "" or issecretvalue(leaderName) then
		return
	end
	return leaderName:match("^[^%-]+%-(.+)$")
end

function RealmCatalog:RefreshPlayerContext()
	playerRegion = GetCurrentRegionName()
	local info = self:LookupRealm(GetRealmName())
	if not info then
		local normalized = GetNormalizedRealmName and GetNormalizedRealmName()
		if normalized then
			info = normalizedIndex[normalized]
		end
	end
	playerTag = info and LocaleToTag(info.locale, info.tz) or nil
end

function RealmCatalog:GetPlayerTag()
	return playerTag
end

function RealmCatalog:GetLocaleTag(leaderName)
	if leaderName and issecretvalue(leaderName) then
		return
	end

	local realm = self:ParseLeaderRealm(leaderName)
	if not realm then
		return
	end

	local info = self:LookupRealm(realm)
	if not info then
		return
	end

	if info.region ~= playerRegion then
		return info.region
	end

	local tag = LocaleToTag(info.locale, info.tz)
	if tag and tag ~= playerTag then
		return tag
	end
end

BuildNormalizedIndex()
