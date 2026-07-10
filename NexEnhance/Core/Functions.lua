--[[
	NexEnhance - Functions
	-------------------------------------------------------------------------
	Shared utility library. Everything here is stateless and reusable. Helpers
	follow the report guidance: reuse tables, avoid per-call garbage, cache
	globals, and prefer string.format over chained concatenation.
--]]

local _, ns = ...
local C, F = ns.C, ns.F

-- Localised globals (hot-path friendly).
local select, type, tostring = select, type, tostring
local pairs, ipairs = pairs, ipairs
local floor = math.floor
local format = string.format
local gsub = string.gsub
local strfind = string.find
local tconcat = table.concat
local tremove = table.remove
local wipe = wipe
local C_Timer = C_Timer
local BreakUpLargeNumbers = BreakUpLargeNumbers
local DEFAULT_CHAT_FRAME = DEFAULT_CHAT_FRAME

-- Match TOC / ns.title: blue Nex + gold Enhance (not a flat brand wash).
local PREFIX = format("|c%sNex|r|c%sEnhance|r:", C.BrandHex, C.HeaderHex)

local UnitName = UnitName
local GetRealmName = GetRealmName
local UnitLevel = UnitLevel

-- ---------------------------------------------------------------------------
-- Player context (name/realm may be nil at file-load time)
-- ---------------------------------------------------------------------------

--- Refresh session identity fields on `C.Player` once the character exists.
function F.RefreshPlayerContext()
	local name = UnitName("player")
	local realm = GetRealmName()
	if name and F.NotSecret(name) then
		C.Player.name = name
	end
	if realm and F.NotSecret(realm) then
		C.Player.realm = realm
	end
	if C.Player.name and C.Player.realm then
		C.Player.key = C.Player.name .. " - " .. C.Player.realm
	end
	-- UnitLevel: SecretArguments only (Resources 12.0.7) — plain assign.
	C.Player.level = UnitLevel("player")
end

-- ---------------------------------------------------------------------------
-- Output
-- ---------------------------------------------------------------------------

-- Reusable buffer so Print() does not allocate a new table per call.
local printBuffer = {}

--- Print a branded message to the default chat frame. Accepts any number of
--- arguments (numbers/strings), joined by spaces.
function F.Print(...)
	wipe(printBuffer)
	printBuffer[1] = PREFIX
	for i = 1, select("#", ...) do
		printBuffer[i + 1] = tostring((select(i, ...)))
	end
	DEFAULT_CHAT_FRAME:AddMessage(tconcat(printBuffer, " "))
end

-- ---------------------------------------------------------------------------
-- Bounded cache
--   Item links carry random suffixes/bonus IDs, so link-keyed memo tables can
--   grow without bound across a long session. Writing through F.CacheSet caps
--   the table: once it crosses `limit` distinct keys we wipe wholesale (cheap
--   and rare) instead of tracking LRU. The bookkeeping count lives under a
--   string sentinel key that never collides with item links or numeric IDs,
--   and callers only ever read with direct key lookups (no iteration).
-- ---------------------------------------------------------------------------
local CACHE_COUNT = "__nexCount"
function F.CacheSet(cache, key, value, limit)
	local count = cache[CACHE_COUNT] or 0
	if count >= (limit or 600) then
		wipe(cache)
		count = 0
	end
	if cache[key] == nil then
		count = count + 1
	end
	cache[CACHE_COUNT] = count
	cache[key] = value
	return value
end

-- ---------------------------------------------------------------------------
-- Colour helpers
-- ---------------------------------------------------------------------------

--- Convert 0-1 RGB to a WoW hex string ("ffRRGGBB"), suitable for |c....
function F.RGBToHex(r, g, b)
	-- Accept a {r, g, b} table as the first argument too.
	if type(r) == "table" then
		r, g, b = r[1], r[2], r[3]
	end
	return format("ff%02x%02x%02x", r * 255, g * 255, b * 255)
end

-- Branded display title: blue Nex + gold Enhance (matches tooltip section headers).
ns.title = format("|c%sNex|r|c%sEnhance|r", C.BrandHex, C.HeaderHex)

--- Convert a hex string ("RRGGBB" or "ffRRGGBB") to 0-1 RGB triplet.
function F.HexToRGB(hex)
	if #hex == 8 then
		hex = hex:sub(3)
	end -- strip alpha
	return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

--- Convert 0-1 RGBA to the "AARRGGBB" hex string used by Blizzard's Settings
--- colour swatches (CreateColorFromHexString / Color:GenerateHexColor). Alpha
--- defaults to fully opaque when omitted.
function F.RGBAToHex(r, g, b, a)
	if type(r) == "table" then
		r, g, b, a = r[1], r[2], r[3], r[4]
	end
	return format("%02x%02x%02x%02x", (a or 1) * 255, r * 255, g * 255, b * 255)
end

--- Convert an "AARRGGBB" (or "RRGGBB") hex string to a 0-1 RGBA quad. Alpha is
--- 1 when the string has no alpha component.
function F.HexToRGBA(hex)
	if #hex == 8 then
		return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255, tonumber(hex:sub(1, 2), 16) / 255
	end
	return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 1
end

--- Wrap text in a colour escape sequence. `color` may be a {r,g,b} table or a
--- key into C.Colors ("red", "brand", ...).
function F.Colorize(text, color)
	if type(color) == "string" then
		color = C.Colors[color] or C.Colors.white
	end
	return format("|c%s%s|r", F.RGBToHex(color), text)
end

--- Inline |T| markup for sidebar icons. Uses C.TexCoord (normalized) converted to
--- pixel texels on the 64x64 source — |T| escapes do not accept 0–1 floats.
function F.SidebarIconMarkup(iconPath, size)
	if not iconPath then
		return ""
	end
	size = size or 16
	local fileSize = 64
	local l, r, t, b = C.TexCoord[1], C.TexCoord[2], C.TexCoord[3], C.TexCoord[4]
	local leftTexel = floor(l * fileSize + 0.5)
	local rightTexel = floor(r * fileSize + 0.5)
	local topTexel = floor(t * fileSize + 0.5)
	local bottomTexel = floor(b * fileSize + 0.5)
	return format("|T%s:%d:%d:0:0:%d:%d:%d:%d:%d:%d|t", iconPath, size, size, fileSize, fileSize, leftTexel, rightTexel, topTexel, bottomTexel)
end

--- Compact |T| tag for inline chat icons (emoji, badges). Width and height default to 16.
--- Optional xOffset/yOffset nudge the icon (autocomplete row alignment).
function F.ChatTexture(path, width, height, xOffset, yOffset)
	if not path then
		return ""
	end
	width = width or 16
	height = height or 16
	if xOffset or yOffset then
		return format("|T%s:%d:%d:%d:%d|t", path, width, height, xOffset or 0, yOffset or 0)
	end
	return format("|T%s:%d:%d|t", path, width, height)
end

-- ---------------------------------------------------------------------------
-- Numbers / formatting
-- ---------------------------------------------------------------------------

--- Round to the given number of decimal places (default 0).
function F.Round(value, places)
	if places and places > 0 then
		local mult = 10 ^ places
		return floor(value * mult + 0.5) / mult
	end
	return floor(value + 0.5)
end

--- Format a copper amount into a "Xg Ys Zc" string using Blizzard's icons.
--- The gold component is grouped with thousands separators (e.g. 25,000).
function F.FormatMoney(copper)
	copper = floor(copper or 0)
	local gold = floor(copper / 10000)
	local silver = floor((copper % 10000) / 100)
	local copperRem = copper % 100

	if gold > 0 then
		local goldText = BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or gold
		return format("%s|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t %d|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t %d|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t", goldText, silver, copperRem)
	elseif silver > 0 then
		return format("%d|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t %d|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t", silver, copperRem)
	end
	return format("%d|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t", copperRem)
end

-- ---------------------------------------------------------------------------
-- Table helpers
-- ---------------------------------------------------------------------------

--- Recursively fill `target` with any keys missing from `defaults`, without
--- overwriting values the user already set. This is the saved-variable
--- "apply defaults" / "merge defaults" pass (cheaper and clearer than a
--- metatable proxy). NOTE: this is a *merge*, not a clone - to duplicate a
--- table outright (so the original is untouched) use the global CopyTable from
--- SharedXML/TableUtil.lua instead.
---
--- Type-repair: a key whose saved value no longer matches the default's *type*
--- is reset to the default. This heals schema drift - e.g. a setting that used
--- to be a number and is now a table - so stale, wrong-typed saved data can't
--- persist and blow up later. Wrong-typed saved keys get reset to the default
--- so a number that became a table can't linger and crash on load. Keys absent
--- from `defaults` are never iterated, so genuinely dynamic saved data - movers, profiles, account caches - is always preserved.
function F.CopyDefaults(defaults, target)
	if type(target) ~= "table" then
		target = {}
	end
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			-- Recurse: a non-table saved value here is rebuilt into a fresh
			-- table from the defaults by the type guard at the top.
			target[key] = F.CopyDefaults(value, target[key])
		elseif target[key] == nil or type(target[key]) ~= type(value) then
			target[key] = value
		end
	end
	return target
end

--- Drop saved keys that match defaults so SavedVariables stay sparse.
--- Only walks keys present in `defaults`; extra profile keys (movers, etc.) are kept.
function F.CompactDefaults(defaults, target)
	if type(defaults) ~= "table" or type(target) ~= "table" then
		return
	end
	for key, defaultValue in pairs(defaults) do
		local value = target[key]
		if value == nil then
			-- already sparse
		elseif type(defaultValue) == "table" then
			if type(value) == "table" then
				F.CompactDefaults(defaultValue, value)
				if not next(value) then
					target[key] = nil
				end
			end
		elseif value == defaultValue then
			target[key] = nil
		end
	end
end

--- Copy values from prior sibling keys when a new setting is absent (schema
--- upgrades). `inheritMap` is `{ newKey = "oldKey" }`; only runs when
--- `target[newKey]` is nil and the old key still holds a value.
function F.InheritExistingValues(target, inheritMap)
	if type(target) ~= "table" or type(inheritMap) ~= "table" then
		return target
	end
	for newKey, oldKey in pairs(inheritMap) do
		if target[newKey] == nil and target[oldKey] ~= nil then
			target[newKey] = target[oldKey]
		end
	end
	return target
end

--- Count entries in a hash table (no `#` for non-array tables).
function F.TableCount(tbl)
	local count = 0
	for _ in pairs(tbl) do
		count = count + 1
	end
	return count
end

-- ---------------------------------------------------------------------------
-- Frame event helpers
-- ---------------------------------------------------------------------------

--- Register `events` on `frame` and set a single OnEvent handler. Caller must
--- call `frame:UnregisterAllEvents()` (and clear the script) when tearing down.
function F.RegisterFrameForEvents(frame, events, handler)
	if not frame or not events then
		return
	end
	for i = 1, #events do
		frame:RegisterEvent(events[i])
	end
	if handler then
		frame:SetScript("OnEvent", handler)
	end
end

-- ---------------------------------------------------------------------------
-- Timing helpers
-- ---------------------------------------------------------------------------

--- Debounce: returns a function that, however often it is called, only runs
--- `func` once after `delay` seconds of quiet. Ideal for event storms such as
--- BAG_UPDATE where many events fire in quick succession.
---
--- We capture up to 4 positional args in fixed upvalue slots instead of building
--- a `{ ... }` table on every call — avoids GC on suppressed invocations.
--- 4 slots covers virtually every WoW event payload (most have 0-2 args);
--- callers that truly need 5+ args should use a different approach.
function F.Debounce(delay, func)
	local scheduled = false
	return function(...)
		if scheduled then
			return
		end
		scheduled = true
		local a1, a2, a3, a4 = ...
		C_Timer.After(delay, function()
			scheduled = false
			func(a1, a2, a3, a4)
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Reset / clock helpers
--   Defensive guards on GetQuestResetTime (SavedInstances-style): the API can
--   return nil, negative values after DST, or nonsense >24h inside instances.
-- ---------------------------------------------------------------------------

local GetQuestResetTime = GetQuestResetTime
local GetTime = GetTime
local time = time
local floor = math.floor
local tonumber = tonumber
local date = date
local DAILY_RESET_MAX = 24 * 60 * 60 + 30

--- Seconds until the next daily quest reset, or nil when the API is unreliable.
function F.GetSecondsUntilDailyReset()
	local resetTime = GetQuestResetTime and GetQuestResetTime()
	if not resetTime or resetTime <= 0 or resetTime > DAILY_RESET_MAX then
		return nil
	end
	return resetTime
end

--- Seconds until the next weekly reset, or nil when unavailable.
function F.GetSecondsUntilWeeklyReset()
	if not (C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset) then
		return nil
	end
	local weekly = C_DateAndTime.GetSecondsUntilWeeklyReset()
	if not weekly or weekly <= 0 then
		return nil
	end
	return weekly
end

--- Absolute `time()` of the next daily reset, or nil.
function F.GetNextDailyResetTime()
	local seconds = F.GetSecondsUntilDailyReset()
	return seconds and (time() + seconds) or nil
end

--- Absolute `time()` of the next weekly reset, or nil.
function F.GetNextWeeklyResetTime()
	local seconds = F.GetSecondsUntilWeeklyReset()
	return seconds and (time() + seconds) or nil
end

--- Convert a `GetTime()`-relative value to absolute `time()`.
do
	local getTimeToTimeOffset = time() - GetTime()
	function F.GetTimeToTime(val)
		if not val then
			return nil
		end
		return val + getTimeToTimeOffset
	end
end

--- Hours the server calendar is ahead of the local machine (0.5h steps).
function F.GetServerOffsetHours()
	if not (C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime) then
		return 0
	end
	local serverDate = C_DateAndTime.GetCurrentCalendarTime()
	if not serverDate then
		return 0
	end
	local serverWeekday = serverDate.weekday - 1
	local serverHour, serverMinute = serverDate.hour, serverDate.minute
	local localWeekday = tonumber(date("%w"))
	local localHour, localMinute = tonumber(date("%H")), tonumber(date("%M"))
	if serverWeekday == (localWeekday + 1) % 7 then
		serverHour = serverHour + 24
	elseif localWeekday == (serverWeekday + 1) % 7 then
		localHour = localHour + 24
	end
	return floor((serverHour + serverMinute / 60 - localHour - localMinute / 60) * 2 + 0.5) / 2
end

-- ---------------------------------------------------------------------------
-- Object pool
--   Generic recycler that avoids churning the GC for frequently created and
--   freed objects (frames, textures, data rows). Unlike a plain free-list it
--   also tracks the *active* set, so the whole batch can be reclaimed in one
--   call - the usual pattern for "rebuild this list from scratch on refresh".
--
--     local pool = F.CreatePool(
--         function() return CreateFrame("Frame", nil, parent) end, -- creator
--         function(f) f.data = nil end)                            -- onRemoved (optional)
--
--     local f = pool:Acquire()   -- reuse a free object, or create one
--     ...
--     pool:ReleaseAll()          -- reclaim every active object at once
--
--   `onRemoved(obj)` runs when an object is released (after the pool hides and
--   unanchors frame-like objects). `onAcquired(obj)` runs after one is handed
--   out. Each created object also gains an :Release() method.
-- ---------------------------------------------------------------------------

--- Create a pool. See block comment above for the calling convention.
function F.CreatePool(creator, onRemoved, onAcquired)
	local pool = {
		objects = {}, -- every object the pool has ever created
		active = {}, -- objects currently handed out
		free = {}, -- objects available for reuse (used as a stack)
		numFree = 0,
	}

	-- Hide/unanchor frame-like objects, then run user cleanup, then park the
	-- object on the free stack. Capability checks keep this safe for plain
	-- tables (which have no Hide/ClearAllPoints).
	local function reclaim(obj)
		obj._poolIdx = nil -- clear index so double-Release is a safe no-op
		if obj.ClearAllPoints then
			obj:ClearAllPoints()
		end
		if obj.Hide then
			obj:Hide()
		end
		if onRemoved then
			onRemoved(obj)
		end
		pool.numFree = pool.numFree + 1
		pool.free[pool.numFree] = obj
	end

	-- One shared closure per pool (not per object) so injecting :Release()
	-- costs no extra garbage as the pool grows.
	local function objRelease(obj)
		pool:Release(obj)
	end

	function pool:Acquire()
		local obj
		if self.numFree > 0 then
			obj = self.free[self.numFree]
			self.free[self.numFree] = nil
			self.numFree = self.numFree - 1
		else
			obj = creator()
			self.objects[#self.objects + 1] = obj
			obj.Release = objRelease
		end

		self.active[#self.active + 1] = obj
		obj._poolIdx = #self.active -- reverse-index for O(1) Release
		if obj.Show then
			obj:Show()
		end
		if onAcquired then
			onAcquired(obj)
		end
		return obj
	end

	--- Release a single active object back into the pool.
	--- O(1): uses a reverse-index (`obj._poolIdx`) to find the slot, then
	--- swaps with the last element and pops — no linear scan needed.
	function pool:Release(obj)
		local idx = obj._poolIdx
		if not idx then
			return -- already released or not from this pool
		end
		local active = self.active
		local last = #active
		if idx ~= last then
			-- Move the last element into the vacated slot and update its index.
			local tail = active[last]
			active[idx] = tail
			tail._poolIdx = idx
		end
		active[last] = nil
		reclaim(obj) -- also clears obj._poolIdx inside reclaim
	end

	--- Reclaim every active object in one pass. Cheap way to clear a list
	--- before repopulating it.
	function pool:ReleaseAll()
		local active = self.active
		for i = #active, 1, -1 do
			local obj = active[i]
			active[i] = nil
			reclaim(obj)
		end
	end

	--- Iterate the active objects: `for _, obj in pool:EnumerateActive() do`.
	function pool:EnumerateActive()
		return ipairs(self.active)
	end

	--- The live active array (do not modify; use Release/ReleaseAll).
	function pool:GetActiveObjects()
		return self.active
	end

	return pool
end

-- ---------------------------------------------------------------------------
-- Safety
-- ---------------------------------------------------------------------------

--- Shared do-nothing function. Use it to neutralise a method on a frame we want
--- to stop misbehaving (e.g. an addon button that keeps re-anchoring itself)
--- without allocating a fresh empty closure at each call site.
function F.Noop() end

--- Protected call that reports (rather than swallows) failures. Use only at
--- trust boundaries (third-party callbacks, user input); not in hot loops.
function F.SafeCall(func, ...)
	local ok, errOrResult = pcall(func, ...)
	if not ok then
		F.Print(F.Colorize("Error:", "red"), errOrResult)
		return nil
	end
	return errOrResult
end

-- ---------------------------------------------------------------------------
-- Secret values (Patch 12.0)
--   Identity/health APIs can return "secret" values that tainted code may not
--   boolean-test or compare. Gate any such read with these helpers first.
-- ---------------------------------------------------------------------------
-- Shared secret guards — callers never boolean-test / compare / index a secret
-- directly. Safe even when the underlying primitive is absent on older clients.
do
	local issecretvalue = _G["issecretvalue"]
	local issecrettable = _G["issecrettable"]
	local canaccessvalue = _G["canaccessvalue"]
	local C_Secrets = _G["C_Secrets"]
	local ShouldUnitIdentityBeSecret = C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret

	--- True when `value` is a secret value (always safe to call).
	function F.IsSecret(value)
		return issecretvalue and issecretvalue(value)
	end

	--- True when `value` is a normal (non-secret) value.
	function F.NotSecret(value)
		return not F.IsSecret(value)
	end

	--- True when a unit's identity is currently hidden (instances / restricted).
	--- pcall'd because the API can be absent or throw on some unit tokens.
	function F.IsSecretUnit(unit)
		if not (unit and ShouldUnitIdentityBeSecret) then
			return false
		end
		local ok, value = pcall(ShouldUnitIdentityBeSecret, unit)
		return ok and value
	end

	--- True when a unit's identity is readable.
	function F.NotSecretUnit(unit)
		return not F.IsSecretUnit(unit)
	end

	--- True when `object` is a secret table (its fields may not be indexed).
	function F.IsSecretTable(object)
		return issecrettable and issecrettable(object)
	end

	--- True when `object` is a normal (non-secret) table.
	function F.NotSecretTable(object)
		return not F.IsSecretTable(object)
	end

	--- True when tainted code may actually read `value` (some secrets are still
	--- accessible). Defaults to true where the primitive is unavailable.
	function F.CanAccessValue(value)
		return not canaccessvalue or canaccessvalue(value)
	end

	--- True when tainted code may NOT read `value`.
	function F.CanNotAccessValue(value)
		return not F.CanAccessValue(value)
	end

	--- Compare two unit tokens without secret arithmetic errors. Returns false when
	--- comparison is blocked (`C_Secrets.CanCompareUnitTokens`) or the result is secret.
	function F.SafeUnitIsUnit(a, b)
		if not (a and b and UnitIsUnit) then
			return false
		end
		if C_Secrets and C_Secrets.CanCompareUnitTokens then
			local ok, can = pcall(C_Secrets.CanCompareUnitTokens, a, b)
			if ok and not can then
				return false
			end
		end
		local ok, result = pcall(UnitIsUnit, a, b)
		if not ok or F.IsSecret(result) then
			return false
		end
		return result and true or false
	end

	--- True when a widget/frame currently holds any secret values (aspects).
	function F.HasSecretValues(object)
		return object and object.HasSecretValues and object:HasSecretValues()
	end

	--- True when a widget/frame holds no secret values.
	function F.NoSecretValues(object)
		return not F.HasSecretValues(object)
	end

	local C_CurveUtil = _G["C_CurveUtil"]
	local EvaluateColorFromBoolean = C_CurveUtil and C_CurveUtil.EvaluateColorFromBoolean

	--- Read a boolean when safe; returns `true`/`false`, or `nil` when secret/unknown.
	function F.BooleanIsTrue(value)
		if F.NotSecret(value) then
			return value and true or false
		end
		return nil
	end

	--- Pick RGB for false vs true without comparing a secret boolean in Lua.
	function F.EvaluateColorFromBoolean(bool, r0, g0, b0, r1, g1, b1)
		if F.NotSecret(bool) then
			if bool then
				return r1, g1, b1
			end
			return r0, g0, b0
		end
		if EvaluateColorFromBoolean then
			return EvaluateColorFromBoolean(bool, r0, g0, b0, r1, g1, b1)
		end
		return r0, g0, b0
	end

	--- Secret-safe frame show: uses SetShown when readable, SetAlphaFromBoolean when secret.
	function F.SetShownFromBoolean(frame, bool, shownAlpha)
		if not frame then
			return
		end
		shownAlpha = shownAlpha or 1
		if F.NotSecret(bool) then
			if bool then
				frame:SetAlpha(shownAlpha)
				frame:Show()
			else
				frame:Hide()
			end
			return
		end
		if frame.SetAlphaFromBoolean then
			frame:SetAlphaFromBoolean(bool, shownAlpha, 0)
		end
		if frame.SetShownFromBoolean then
			frame:SetShownFromBoolean(bool)
		end
	end

	--- Hide a cooldown swipe when a DurationObject is zero (permanent aura).
	--- `durObj:IsZero()` may be Secret; `SetAlphaFromBoolean` routes it safely.
	function F.MaskCooldownSwipeFromDurationObject(cooldown, durObj)
		if not (cooldown and durObj and durObj.IsZero and cooldown.SetAlphaFromBoolean) then
			return
		end
		cooldown:SetAlphaFromBoolean(durObj:IsZero(), 0, 1)
	end
end

-- ---------------------------------------------------------------------------
-- Unit / display helpers (used by tooltip and skin modules)
-- ---------------------------------------------------------------------------
do
	local UnitIsPlayer = UnitIsPlayer
	local UnitClass = UnitClass
	local UnitReaction = UnitReaction
	local UnitSelectionColor = UnitSelectionColor
	local UnitSelectionType = UnitSelectionType
	local UnitIsFriend = UnitIsFriend
	local UnitIsUnit = UnitIsUnit
	local UnitPlayerControlled = UnitPlayerControlled
	local UnitIsOwnerOrControllerOfUnit = UnitIsOwnerOrControllerOfUnit
	local UnitIsOtherPlayersPet = UnitIsOtherPlayersPet
	local CompactUnitFrame_IsOnThreatListWithPlayer = CompactUnitFrame_IsOnThreatListWithPlayer
	local FACTION_BAR_COLORS = FACTION_BAR_COLORS
	local CLASS_COLORS = _G["CUSTOM_CLASS_COLORS"] or RAID_CLASS_COLORS
	local strmatch = string.match
	local tonumber = tonumber

	--- Wrap colour (r,g,b or {r,g,b}) into a "|cffRRGGBB" escape prefix.
	function F.ColorStr(r, g, b)
		return "|c" .. F.RGBToHex(r, g, b)
	end

	local function ColorDistance(r, g, b, cr, cg, cb)
		local dr, dg, db = r - cr, g - cg, b - cb
		return dr * dr + dg * dg + db * db
	end

	-- UnitSelectionType (0=hostile, 1=unfriendly, 2=neutral, 3=friendly) is what
	-- nameplates use for reaction category. Map to FACTION_BAR_COLORS indices.
	local SELECTION_TYPE_TO_FACTION = {
		[0] = 2, -- hostile red
		[1] = 3, -- unfriendly orange
		[2] = 4, -- neutral yellow
		[3] = 5, -- friendly green
	}

	-- Saturated UnitSelectionColor references (wiki); fallback when type is secret.
	local SELECTION_RGB_REFS = {
		{ 2, 1.0, 0.0, 0.0 }, -- hostile
		{ 3, 1.0, 0.5, 0.0 }, -- unfriendly orange
		{ 4, 1.0, 1.0, 0.0 }, -- neutral yellow
		{ 5, 0.0, 1.0, 0.0 }, -- friendly green
	}

	local function FactionIndexFromSelectionRGB(sr, sg, sb)
		local bestIdx, bestDist
		for i = 1, #SELECTION_RGB_REFS do
			local ref = SELECTION_RGB_REFS[i]
			local d = ColorDistance(sr, sg, sb, ref[2], ref[3], ref[4])
			if not bestDist or d < bestDist then
				bestDist = d
				bestIdx = ref[1]
			end
		end
		return bestIdx
	end

	-- FACTION_ORANGE_COLOR is very brown; on desaturated HUD health atlases it reads
	-- almost like hostile red. Nudge unfriendly toward nameplate orange (1, 0.5, 0).
	local UNFRIENDLY_ORANGE_BOOST = { r = 1.0, g = 0.52, b = 0.0 }
	local UNFRIENDLY_ORANGE_BLEND = 0.7

	local function ResolveFactionTint(factionIdx)
		local color = FACTION_BAR_COLORS[factionIdx]
		if not color then
			return nil
		end

		if factionIdx == 3 then
			local boost = UNFRIENDLY_ORANGE_BOOST
			local mix = UNFRIENDLY_ORANGE_BLEND
			return color.r + (boost.r - color.r) * mix, color.g + (boost.g - color.g) * mix, color.b + (boost.b - color.b) * mix
		end

		return color.r, color.g, color.b
	end

	--- Player pets, party pets, and other player-controlled friendly units are
	--- not NPC reaction targets (Blizzard keeps pet HUD bars green). Matches
	--- TargetFrame CheckFaction skipping tap-deny on UnitPlayerControlled units.
	function F.IsFriendlyControlledUnit(unit)
		if not unit then
			return false
		end

		if UnitIsUnit then
			if F.SafeUnitIsUnit(unit, "pet") then
				return true
			end
		end

		-- UnitIsOtherPlayersPet / UnitPlayerControlled / UnitIsFriend /
		-- UnitIsOwnerOrControllerOfUnit: SecretArguments only (Resources 12.0.7).
		if UnitIsOtherPlayersPet and UnitIsOtherPlayersPet(unit) then
			return true
		end

		if not UnitPlayerControlled or not UnitPlayerControlled(unit) then
			return false
		end

		if UnitIsOwnerOrControllerOfUnit and UnitIsOwnerOrControllerOfUnit("player", unit) then
			return true
		end

		if UnitIsFriend and UnitIsFriend("player", unit) then
			return true
		end

		return false
	end

	--- NPC reaction tint: read UnitSelectionType/Color (same source as nameplates),
	--- then output the darker FACTION_BAR_COLORS entry so unit frames and tooltips
	--- match nameplate category without bright selection RGB. Falls back to
	--- UnitReaction when selection APIs are unavailable.
	function F.GetNpcReactionColor(unit)
		if not unit or not FACTION_BAR_COLORS then
			return nil
		end

		if F.IsFriendlyControlledUnit(unit) then
			return ResolveFactionTint(5)
		end

		local factionIdx

		-- UnitSelectionType / UnitSelectionColor / UnitReaction: SecretArguments only.
		if UnitSelectionType then
			local selType = UnitSelectionType(unit, false)
			if selType ~= nil then
				factionIdx = SELECTION_TYPE_TO_FACTION[selType]
			end
		end

		if not factionIdx and UnitSelectionColor then
			local sr, sg, sb = UnitSelectionColor(unit, false)
			if sr then
				factionIdx = FactionIndexFromSelectionRGB(sr, sg, sb)
			end
		end

		if not factionIdx then
			local reaction = UnitReaction(unit, "player")
			if not reaction then
				return nil
			end
			factionIdx = reaction
		end

		-- Neutral/yellow mobs turn bright red (1,0,0) on nameplates when pulled;
		-- CompactUnitFrame considerSelectionInCombatAsHostile. Use darker hostile
		-- red so nameplate + target frame stay on our palette.
		-- Threat list can still be secret (UnitThreatSituation); friend flag is plain.
		if CompactUnitFrame_IsOnThreatListWithPlayer and UnitIsFriend then
			local onThreat = CompactUnitFrame_IsOnThreatListWithPlayer(unit)
			if F.NotSecret(onThreat) and onThreat and not UnitIsFriend("player", unit) then
				factionIdx = 2
			end
		end

		if not FACTION_BAR_COLORS[factionIdx] then
			return nil
		end

		return ResolveFactionTint(factionIdx)
	end

	--- Map bright UnitSelectionColor RGB (what Blizzard just put on a nameplate bar)
	--- to the darker FACTION_BAR_COLORS palette. Used when unit-token reaction
	--- APIs are unreadable from tainted code but the bar colour is not secret.
	function F.GetNpcReactionColorFromRGB(r, g, b)
		if not (F.NotSecret(r) and F.NotSecret(g) and F.NotSecret(b)) then
			return nil
		end
		local factionIdx = FactionIndexFromSelectionRGB(r, g, b)
		return ResolveFactionTint(factionIdx)
	end

	--- Resolve a unit's display colour: class colour for players, reaction colour
	--- for NPCs, white otherwise. UnitIsPlayer / classFilename are SecretArguments-only;
	--- className (1st UnitClass return) is ConditionalSecret — we use the 2nd.
	function F.UnitColor(unit)
		local r, g, b = 1, 1, 1
		if not unit then
			return r, g, b
		end

		if UnitIsPlayer(unit) then
			local _, class = UnitClass(unit)
			if class then
				local color = CLASS_COLORS[class]
				if color then
					return color.r, color.g, color.b
				end
			end
			return r, g, b
		end

		local nr, ng, nb = F.GetNpcReactionColor(unit)
		if nr then
			return nr, ng, nb
		end
		return r, g, b
	end

	--- Extract the numeric NPC ID from a unit GUID (nil for players/secret).
	function F.GetNPCID(guid)
		if not guid or F.IsSecret(guid) then
			return
		end
		local id = strmatch(guid, "^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)")
		return tonumber(id)
	end

	--- Seconds since an NPC spawned, decoded from the GUID spawn UID (nil if unavailable/secret).
	--- https://warcraft.wiki.gg/wiki/GUID#Spawn_UIDs
	function F.GetNPCSpawnAge(guid)
		if not guid or F.IsSecret(guid) then
			return
		end
		if C_PlayerInfo and C_PlayerInfo.GUIDIsPlayer and C_PlayerInfo.GUIDIsPlayer(guid) then
			return
		end
		local spawnUID = select(6, strsplit("-", guid))
		if not spawnUID then
			return
		end
		local serverTime = GetServerTime()
		local epoch = 8388608 -- 2^23
		local spawnEpoch = serverTime - (serverTime % epoch)
		local spawnEpochOffset = bit.band(tonumber(spawnUID, 16) or 0, 0x7fffff)
		local spawnTime = spawnEpoch + spawnEpochOffset
		if spawnTime > serverTime then
			spawnTime = spawnTime - (epoch - 1)
		end
		return serverTime - spawnTime
	end

	--- Compact duration for tooltip/debug readouts (e.g. 3m 12s).
	function F.FormatShortDuration(seconds)
		if not seconds or seconds <= 0 then
			return "0s"
		end
		seconds = floor(seconds)
		if seconds >= 86400 then
			return format("%dd %dh", floor(seconds / 86400), floor((seconds % 86400) / 3600))
		elseif seconds >= 3600 then
			return format("%dh %dm", floor(seconds / 3600), floor((seconds % 3600) / 60))
		elseif seconds >= 60 then
			return format("%dm %ds", floor(seconds / 60), seconds % 60)
		end
		return format("%ds", seconds)
	end
end

-- Number abbreviation built on the 12.0 AbbreviateNumbers API. Two presets,
-- selectable via General > Number Format (stored in ns.db.numberFormat.style):
--   1 = Western:          1.2k / 3.4m / 5.6b / 7.8t
--   2 = East Asian myriad: 1.2w (万) / 3.4y (亿) / 5.6z (兆)
-- The configs are built lazily/cached on first use so we don't pay for them at
-- load and so localized abbreviation strings are ready.
---@diagnostic disable-next-line: undefined-global
local CreateAbbreviateConfig = CreateAbbreviateConfig
local AbbreviateNumbers = AbbreviateNumbers
local numberAbbrevOptions

local function GetNumberAbbrevOptions()
	if numberAbbrevOptions then
		return numberAbbrevOptions
	end

	local L = ns.L
	numberAbbrevOptions = {
		[1] = { config = CreateAbbreviateConfig({
			{ breakpoint = 1e12, abbreviation = "t", significandDivisor = 1e10, fractionDivisor = 1e2, abbreviationIsGlobal = false },
			{ breakpoint = 1e9, abbreviation = "b", significandDivisor = 1e7, fractionDivisor = 1e2, abbreviationIsGlobal = false },
			{ breakpoint = 1e6, abbreviation = "m", significandDivisor = 1e4, fractionDivisor = 1e2, abbreviationIsGlobal = false },
			{ breakpoint = 1e3, abbreviation = "k", significandDivisor = 1e2, fractionDivisor = 1e1, abbreviationIsGlobal = false },
		}) },
		[2] = { config = CreateAbbreviateConfig({
			{ breakpoint = 1e12, abbreviation = L["Abbrev Number Three"], significandDivisor = 1e10, fractionDivisor = 1e2, abbreviationIsGlobal = false },
			{ breakpoint = 1e8, abbreviation = L["Abbrev Number Two"], significandDivisor = 1e6, fractionDivisor = 1e2, abbreviationIsGlobal = false },
			{ breakpoint = 1e4, abbreviation = L["Abbrev Number One"], significandDivisor = 1e3, fractionDivisor = 1e1, abbreviationIsGlobal = false },
		}) },
	}
	return numberAbbrevOptions
end

--- Abbreviate large numbers ("1.2m", "356.1k"); leaves small numbers as-is.
--- Honours the General > Number Format preference; negatives keep their sign.
function F.ShortValue(value)
	local style = (ns.db and ns.db.numberFormat and ns.db.numberFormat.style) or 1
	local opt = GetNumberAbbrevOptions()[style]
	if opt then
		---@diagnostic disable-next-line: redundant-parameter
		return AbbreviateNumbers(value, opt)
	else
		return value
	end
end

-- ---------------------------------------------------------------------------
-- Font-string helpers
-- ---------------------------------------------------------------------------

--- Create an OUTLINE font string on `parent`.
function F.CreateFS(parent, size, text, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs:SetFont(C.Media.Fonts.normal, size or 12, "OUTLINE")
	fs:SetShadowColor(0, 0, 0, 0)
	if text then
		fs:SetText(text)
	end
	return fs
end

--- Strip inline colour codes so a duplicate shadow string can stay solid black.
function F.StripColorCodes(text)
	if not text then
		return ""
	end
	text = gsub(text, "|%a%x%x%x%x%x%x%x%x", "")
	text = gsub(text, "|r", "")
	text = gsub(text, "|R", "")
	return text
end

--- Plain font string with a manual drop shadow. On 12.0.7+ the engine can report
--- GetShadowOffset() as 1,-1 while Slug-rendered text draws the shadow flush on
--- the glyphs, so we offset a solid-black duplicate instead of SetShadowOffset.
function F.CreatePlainFS(parent, size, text, layer)
	local lyr = layer or "OVERLAY"
	local sz = size or 12
	local font = C.Media.Fonts.normal

	-- Shadow beneath main string — explicit sublevels; sibling order alone is not
	-- reliable on StatusBar and other layered parents (e.g. cast bar latency text).
	local shadow = parent:CreateFontString(nil, lyr)
	shadow:SetDrawLayer(lyr, -1)
	shadow:SetFont(font, sz, "")
	shadow:SetTextColor(0, 0, 0, 0.85)

	local fs = parent:CreateFontString(nil, lyr)
	fs:SetDrawLayer(lyr, 1)
	fs:SetFont(font, sz, "")
	fs.nexShadow = shadow
	fs.nexPlainLayer = lyr
	shadow:SetPoint("CENTER", fs, "CENTER", 1, -1)

	if text then
		F.SetPlainText(fs, text)
	end
	return fs
end

--- Keep a CreatePlainFS shadow duplicate in sync with the main string.
function F.SetPlainText(fs, text)
	fs:SetText(text or "")
	local shadow = fs.nexShadow
	if shadow then
		shadow:SetText(F.StripColorCodes(text))
	end
end

function F.SetPlainFormattedText(fs, fmt, ...)
	F.SetPlainText(fs, format(fmt, ...))
end

--- Hide a CreatePlainFS string and its manual shadow duplicate.
function F.HidePlainFS(fs)
	if not fs then
		return
	end
	fs:Hide()
	local shadow = fs.nexShadow
	if shadow then
		shadow:Hide()
	end
end

--- Show a CreatePlainFS string and its manual shadow duplicate.
function F.ShowPlainFS(fs)
	if not fs then
		return
	end
	local shadow = fs.nexShadow
	local lyr = fs.nexPlainLayer or "OVERLAY"
	if shadow then
		shadow:SetDrawLayer(lyr, -1)
		shadow:Show()
	end
	fs:SetDrawLayer(lyr, 1)
	fs:Show()
end

--- Tear down a CreatePlainFS string (main + shadow).
function F.ReleasePlainFS(fs)
	if not fs then
		return
	end
	F.HidePlainFS(fs)
	local shadow = fs.nexShadow
	if shadow then
		shadow:SetParent(nil)
		fs.nexShadow = nil
	end
	fs:SetParent(nil)
end

--- Resize a font string while preserving its font file and flags.
function F.SetFontSize(fontString, size)
	local font, _, flags = fontString:GetFont()
	fontString:SetFont(font, size, flags)
	local shadow = fontString.nexShadow
	if shadow then
		local sFont, _, sFlags = shadow:GetFont()
		shadow:SetFont(sFont or font, size, sFlags or flags)
	end
end

-- ---------------------------------------------------------------------------
-- HelpTip helpers
--   One-shot, account-wide tutorial nudges built on Blizzard's HelpTip frame.
--   F.ShowHelpTip(owner, key, text[, opts]) shows `text` anchored to `owner`
--   exactly once per account: clicking the acknowledge button records `key` in
--   ns.global.helpTips so it never returns. `key` is a short, stable id
--   ("QuickJoinApply") kept separate from the (localised) text.
--
--   Every tip we raise on purpose is remembered in `ns.OwnHelpTips` (keyed by
--   text) so the Hide Help Tips feature spares it - it only quiets Blizzard's
--   noise, not ours. See Modules/Miscellaneous/HideHelpTips.lua.
-- ---------------------------------------------------------------------------

-- Texts NexEnhance raises on purpose; populated as tips are shown.
ns.OwnHelpTips = ns.OwnHelpTips or {}

--- Mark a one-shot HelpTip acknowledged. Wired as the HelpTip `callbackArg`, so
--- WoW calls it with the `key` when the user clicks the acknowledge button.
function F.AcknowledgeHelpTip(key)
	if not (key and ns.global) then
		return
	end
	ns.global.helpTips = ns.global.helpTips or {}
	ns.global.helpTips[key] = true
end

--- Show a one-shot HelpTip once per account. No-ops if it's already been
--- acknowledged, if the owner/HelpTip frame isn't available, or before the DB
--- is built. `opts` may carry buttonStyle, targetPoint, alignment, offsetX/Y.
function F.ShowHelpTip(owner, key, text, opts)
	---@diagnostic disable-next-line: undefined-field
	local HelpTip = _G.HelpTip
	if not (owner and key and text and HelpTip and ns.global) then
		return
	end

	local seen = ns.global.helpTips
	if seen and seen[key] then
		return
	end

	-- Register the text BEFORE Show, so the Hide Help Tips post-hook (which
	-- fires from inside HelpTip:Show) recognises it as ours and leaves it be.
	ns.OwnHelpTips[text] = true

	opts = opts or {}
	HelpTip:Show(owner, {
		text = text,
		buttonStyle = opts.buttonStyle or HelpTip.ButtonStyle.GotIt,
		targetPoint = opts.targetPoint or HelpTip.Point.RightEdgeCenter,
		alignment = opts.alignment,
		offsetX = opts.offsetX,
		offsetY = opts.offsetY,
		onAcknowledgeCallback = F.AcknowledgeHelpTip,
		callbackArg = key,
	})
end

-- ---------------------------------------------------------------------------
-- Tooltip helpers
-- ---------------------------------------------------------------------------

--- True when `tip` already shows a left-hand line whose text contains `label`
--- (plain substring match). Used to avoid duplicate M+/target lines on refresh.
function F.TooltipHasLineContaining(tip, label)
	local name = tip and tip.GetName and tip:GetName()
	if not name or not label then
		return false
	end
	for i = 1, tip:NumLines() do
		local line = _G[name .. "TextLeft" .. i]
		local text = line and line:GetText()
		if text and F.NotSecret(text) and text:find(label, 1, true) then
			return true
		end
	end
	return false
end

--- True when `tip` already shows a left-hand line whose text equals `matchText`.
--- Used to avoid appending duplicate annotation lines (IDs, source lines) when a
--- tooltip is rebuilt. Every text read is secret-gated so it never errors under
--- tainted execution.
function F.TooltipHasLine(tip, matchText)
	local name = tip and tip.GetName and tip:GetName()
	if not name then
		return false
	end
	for i = 1, tip:NumLines() do
		local line = _G[name .. "TextLeft" .. i]
		local text = line and line:GetText()
		if text and F.NotSecret(text) and text == matchText then
			return true
		end
	end
	return false
end

--- Addon-initiated `RefreshData` rebuilds the tooltip in tainted execution.
--- Unit lines run `GameTooltip_UnitColor` -> `UnitPlayerControlled(unit)`, which
--- rejects secret unit tokens unless the call stack is untainted (Midnight 12.0+).
--- @param tooltip GameTooltip|table
--- @param opts? table itemOnly: when true, skip unit tooltips entirely (Pawn/item paths).
--- @return boolean refreshed
function F.SafeRefreshTooltipData(tooltip, opts)
	if not tooltip or tooltip:IsForbidden() or not tooltip:IsShown() then
		return false
	end
	if not tooltip.RefreshData then
		return false
	end

	opts = opts or {}
	local unitType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit
	if tooltip.IsTooltipType and unitType and tooltip:IsTooltipType(unitType) then
		if opts.itemOnly then
			return false
		end
		-- GetUnit() returns a unit token string — not a secret-tagged API return.
		local unit = tooltip.GetUnit and tooltip:GetUnit()
		if unit and F.IsSecretUnit(unit) then
			return false
		end
	end

	local ok, err = pcall(tooltip.RefreshData, tooltip)
	if not ok then
		if type(err) == "string" and (strfind(err, "secret", 1, true) or strfind(err, "UnitPlayerControlled", 1, true)) then
			return false
		end
		error(err, 2)
	end
	return true
end

-- ---------------------------------------------------------------------------
-- Item level scanning
--   Reads effective item level (and, on a full scan, gems/sockets/enchant
--   text) from the modern structured tooltip API. The line args are already
--   surfaced by C_TooltipInfo, so fields like .gemIcon/.enchantID are direct.
-- ---------------------------------------------------------------------------
do
	local strfind, strmatch, gsub = string.find, string.match, string.gsub
	local tonumber = tonumber
	local C_TooltipInfo = C_TooltipInfo

	-- Simple link-keyed cache for the cheap (level-only) path.
	local iLvlCache = {}

	-- Patterns built once from Blizzard's localized templates.
	local itemLevelString = "^" .. gsub(_G["ITEM_LEVEL"] or "Item Level %d", "%%d", "")
	local enchantString = gsub(_G["ENCHANTED_TOOLTIP_LINE"] or "Enchanted: %s", "%%s", "(.+)")

	local HEART_OF_AZEROTH = 158075

	-- Reused on every full scan so we never allocate per call.
	local slotData = { gems = {}, gemsColor = {} }

	--- Returns the effective item level for an item.
	---   * F.GetItemLevel(link)                  - by hyperlink
	---   * F.GetItemLevel(_, unit, slotIndex)    - by equipped slot
	---   * F.GetItemLevel(_, bagID, slotID)      - by bag slot (numeric bagID)
	--- With `fullScan` true (equipped slot form) it returns a table:
	---   { iLvl, enchantText, gems = {tex,...}, gemsColor = {color,...} }
	--- otherwise it returns a number (or nil).
	function F.GetItemLevel(link, arg1, arg2, fullScan)
		if not C_TooltipInfo then
			return
		end

		if fullScan then
			if not (arg1 and arg2) then
				return
			end

			---@type any
			local data = C_TooltipInfo.GetInventoryItem(arg1, arg2)
			if not data then
				return
			end

			wipe(slotData.gems)
			wipe(slotData.gemsColor)
			slotData.iLvl = nil
			slotData.enchantText = nil

			local num = 0
			for i = 2, #data.lines do
				local lineData = data.lines[i]
				if not slotData.iLvl then
					local text = lineData.leftText
					local found = text and strfind(text, itemLevelString)
					if found then
						slotData.iLvl = tonumber(strmatch(text, "(%d+)%)?$")) or 0
					end
				elseif data.id == HEART_OF_AZEROTH then
					if lineData.essenceIcon then
						num = num + 1
						slotData.gems[num] = lineData.essenceIcon
						slotData.gemsColor[num] = lineData.leftColor
					end
				else
					if lineData.enchantID then
						slotData.enchantText = strmatch(lineData.leftText, enchantString)
					elseif lineData.gemIcon then
						num = num + 1
						slotData.gems[num] = lineData.gemIcon
					elseif lineData.socketType then
						num = num + 1
						slotData.gems[num] = format("Interface\\ItemSocketingFrame\\UI-EmptySocket-%s", lineData.socketType)
					end
				end
			end

			return slotData
		end

		-- Hyperlink mode needs an actual hyperlink. LootFrame can briefly expose a
		-- slot before GetLootSlotLink is ready; don't feed nil to C_TooltipInfo and
		-- make Blizzard yell at us in hieroglyphics.
		if not link and type(arg1) ~= "string" and type(arg1) ~= "number" then
			return
		end

		if iLvlCache[link] then
			return iLvlCache[link]
		end

		---@type any
		local data
		if type(arg1) == "string" then
			data = C_TooltipInfo.GetInventoryItem(arg1, arg2)
		elseif type(arg1) == "number" then
			data = C_TooltipInfo.GetBagItem(arg1, arg2)
		else
			data = C_TooltipInfo.GetHyperlink(link, nil, nil, true)
		end
		if not data then
			return
		end

		for i = 2, 5 do
			local lineData = data.lines[i]
			if not lineData then
				break
			end
			local text = lineData.leftText
			if text and strfind(text, itemLevelString) then
				F.CacheSet(iLvlCache, link, tonumber(strmatch(text, "(%d+)%)?$")))
				break
			end
		end
		return iLvlCache[link]
	end
end

-- ---------------------------------------------------------------------------
-- Item bind label (BoE / BoA / WuE)
--   Prefers the structured bag-tooltip binding line; falls back to the static
--   bindType from C_Item.GetItemInfo. Returns nil when bound or not applicable.
-- ---------------------------------------------------------------------------
do
	local C_TooltipInfo = C_TooltipInfo
	local C_Container = C_Container
	local C_Item = C_Item

	local LINE_ITEM_BINDING = Enum.TooltipDataLineType.ItemBinding
	local BIND = Enum.TooltipDataItemBinding
	local ITEM_BIND = Enum.ItemBind

	---@return string|nil "BoE", "BoA", "WuE", or "BoU"
	function F.GetItemBindLabel(link, bagID, slotID)
		if not link then
			return
		end

		if bagID and slotID then
			local containerInfo = C_Container.GetContainerItemInfo(bagID, slotID)
			if containerInfo and containerInfo.isBound then
				return
			end
		end

		if bagID and slotID and C_TooltipInfo then
			local data = C_TooltipInfo.GetBagItem(bagID, slotID)
			if data and data.lines then
				for i = 2, #data.lines do
					local line = data.lines[i]
					if line.type == LINE_ITEM_BINDING then
						local bonding = line.bonding
						if bonding == BIND.BindOnEquip then
							return "BoE"
						elseif bonding == BIND.BindOnUse then
							return "BoU"
						elseif bonding == BIND.Account or bonding == BIND.BindToAccount or bonding == BIND.BindToBnetAccount or bonding == BIND.BnetAccount then
							return "BoA"
						elseif bonding == BIND.AccountUntilEquipped or bonding == BIND.BindToAccountUntilEquipped then
							return "WuE"
						end
						return
					end
				end
			end
		end

		local bindType = select(14, C_Item.GetItemInfo(link))
		if bindType == ITEM_BIND.OnEquip then
			return "BoE"
		elseif bindType == ITEM_BIND.OnUse then
			return "BoU"
		elseif bindType == ITEM_BIND.ToWoWAccount or bindType == ITEM_BIND.ToBnetAccount then
			return "BoA"
		elseif bindType == ITEM_BIND.ToBnetAccountUntilEquipped then
			return "WuE"
		end
	end
end
