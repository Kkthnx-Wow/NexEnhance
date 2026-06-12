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
local tconcat = table.concat
local tremove = table.remove
local wipe = wipe
local C_Timer = C_Timer
local DEFAULT_CHAT_FRAME = DEFAULT_CHAT_FRAME

local PREFIX = format("|c%s%s|r:", C.BrandHex, "NexEnhance")

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
function F.FormatMoney(copper)
	copper = floor(copper or 0)
	local gold = floor(copper / 10000)
	local silver = floor((copper % 10000) / 100)
	local copperRem = copper % 100

	if gold > 0 then
		return format("%d|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t %d|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t %d|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t", gold, silver, copperRem)
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
--- persist and blow up later. (All three Peterodox addons do exactly this on
--- load.) Keys absent from `defaults` are never iterated, so genuinely dynamic
--- saved data - movers, profiles, account caches - is always preserved.
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

--- Count entries in a hash table (no `#` for non-array tables).
function F.TableCount(tbl)
	local count = 0
	for _ in pairs(tbl) do
		count = count + 1
	end
	return count
end

-- ---------------------------------------------------------------------------
-- Timing helpers
-- ---------------------------------------------------------------------------

--- Debounce: returns a function that, however often it is called, only runs
--- `func` once after `delay` seconds of quiet. Ideal for event storms such as
--- BAG_UPDATE where many events fire in quick succession.
function F.Debounce(delay, func)
	local scheduled = false
	return function(...)
		if scheduled then
			return
		end
		scheduled = true
		local args = { ... }
		C_Timer.After(delay, function()
			scheduled = false
			func(unpack(args))
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Object pool
--   Generic recycler that avoids churning the GC for frequently created and
--   freed objects (frames, textures, data rows). Unlike a plain free-list it
--   also tracks the *active* set, so the whole batch can be reclaimed in one
--   call - the usual pattern for "rebuild this list from scratch on refresh".
--
--   Adapted from Plumber's API.CreateObjectPool (Peterodox), trimmed to what
--   NexEnhance needs and guarded so it works for non-frame objects too.
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
		if obj.Show then
			obj:Show()
		end
		if onAcquired then
			onAcquired(obj)
		end
		return obj
	end

	--- Release a single active object back into the pool.
	function pool:Release(obj)
		local active = self.active
		for i = 1, #active do
			if active[i] == obj then
				tremove(active, i)
				reclaim(obj)
				return
			end
		end
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
-- Secret API modelled on oUF's (by Simpy): a small, complete set of guards so
-- callers never boolean-test / compare / index a secret directly. Every helper
-- is safe to call even on clients where the underlying primitive is absent.
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

	--- True when a widget/frame currently holds any secret values (aspects).
	function F.HasSecretValues(object)
		return object and object.HasSecretValues and object:HasSecretValues()
	end

	--- True when a widget/frame holds no secret values.
	function F.NoSecretValues(object)
		return not F.HasSecretValues(object)
	end
end

-- ---------------------------------------------------------------------------
-- Unit / display helpers (used by tooltip and skin modules)
-- ---------------------------------------------------------------------------
do
	local UnitIsPlayer = UnitIsPlayer
	local UnitClass = UnitClass
	local UnitReaction = UnitReaction
	local FACTION_BAR_COLORS = FACTION_BAR_COLORS
	local CLASS_COLORS = _G["CUSTOM_CLASS_COLORS"] or RAID_CLASS_COLORS
	local strmatch = string.match
	local tonumber = tonumber

	--- Wrap colour (r,g,b or {r,g,b}) into a "|cffRRGGBB" escape prefix.
	function F.ColorStr(r, g, b)
		return "|c" .. F.RGBToHex(r, g, b)
	end

	--- Resolve a unit's display colour: class colour for players, reaction
	--- colour for NPCs, white otherwise. Every identity read is secret-gated so
	--- this never errors under tainted execution.
	function F.UnitColor(unit)
		local r, g, b = 1, 1, 1
		if not unit then
			return r, g, b
		end

		local isPlayer = UnitIsPlayer(unit)
		if F.NotSecret(isPlayer) and isPlayer then
			local _, class = UnitClass(unit)
			if F.NotSecret(class) and class then
				local color = CLASS_COLORS[class]
				if color then
					return color.r, color.g, color.b
				end
			end
			return r, g, b
		end

		local reaction = UnitReaction(unit, "player")
		if F.NotSecret(reaction) and reaction and FACTION_BAR_COLORS then
			local color = FACTION_BAR_COLORS[reaction]
			if color then
				return color.r, color.g, color.b
			end
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
end

-- Number abbreviation built on the 12.0 AbbreviateNumbers API. Two presets,
-- selectable via General > Number Format (stored in ns.db.numberFormat.style),
-- mirroring NDui's CreateAbbreviateConfig setup:
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

--- Resize a font string while preserving its font file and flags.
function F.SetFontSize(fontString, size)
	local font, _, flags = fontString:GetFont()
	fontString:SetFont(font, size, flags)
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

-- ---------------------------------------------------------------------------
-- Item level scanning
--   Reads effective item level (and, on a full scan, gems/sockets/enchant
--   text) from the modern structured tooltip API. The line args are already
--   surfaced by C_TooltipInfo, so fields like .gemIcon/.enchantID are direct.
--   Ported from NDui's B.GetItemLevel (by yleaf).
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
--   Idea borrowed from Lars Norberg's BlizzardBags_BoE (GoldpawsStuff):
--     https://github.com/GoldpawsStuff/BlizzardBags_BoE
--   Prefers the structured bag-tooltip binding line; falls back to the static
--   bindType from C_Item.GetItemInfo. Returns nil when bound or not applicable.
-- ---------------------------------------------------------------------------
do
	local C_TooltipInfo = C_TooltipInfo
	local C_Container = C_Container
	local C_Item = C_Item
	local select = select

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
