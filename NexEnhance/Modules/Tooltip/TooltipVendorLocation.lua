--[[
	NexEnhance - Tooltip Vendor Location
	-------------------------------------------------------------------------
	A number of "barter"/token/curio items are turned in to a specific NPC in
	the world rather than used from the bag. For those items this module appends
	the vendor's name + zone to the item tooltip and lets you Ctrl-Click the item
	to drop a map waypoint on the vendor.

	Item->vendor lookup lives in our curated table. TooltipDataProcessor post-hook
	for display; hooksecurefunc on HandleModifiedItemClick for Ctrl+Click waypoint.
	Handlers early-out when disabled; zone names cached at file scope.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local L = ns.L

-- Localised globals (handlers run on every item tooltip / modified click).
local format = string.format
local hooksecurefunc = hooksecurefunc
local IsControlKeyDown = IsControlKeyDown
local InCombatLockdown = InCombatLockdown
local GetItemInfoFromHyperlink = GetItemInfoFromHyperlink
local TooltipDataProcessor = TooltipDataProcessor
local UiMapPoint = UiMapPoint

local C_Map_GetMapInfo = C_Map and C_Map.GetMapInfo
local C_Map_GetAreaInfo = C_Map and C_Map.GetAreaInfo
local C_Map_SetUserWaypoint = C_Map and C_Map.SetUserWaypoint
local C_Map_CanSetUserWaypointOnMap = C_Map and C_Map.CanSetUserWaypointOnMap
local C_Map_OpenWorldMap = C_Map and C_Map.OpenWorldMap
local C_SuperTrack_SetSuperTrackedUserWaypoint = C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint

-- Atlas waypoint pin, sized inline like Blizzard's content-tracking markup.
local WAYPOINT_ICON = "|A:waypoint-mappin-minimap-untracked:20:20:-2:-1|a "

ns:RegisterDefaults({
	vendorLocation = {
		enable = false,
		openMap = true,
	},
})

local VendorLocation = ns:NewModule("VendorLocation", "vendorLocation", { group = "tooltip", title = L["Vendor Location"], order = 60 })

local function db()
	return ns.db.vendorLocation
end

-- ---------------------------------------------------------------------------
-- Vendor data: [itemID] = entry, where an entry is one destination or a list.
--   name     fallback NPC display name
--   npc      NPC id (kept for maintenance / branch selection)
--   note     custom location note shown instead of the NPC name (e.g. cave)
--   sub      sub-area id, resolved to a zone name (overrides the map name)
--   map      uiMapID for the waypoint
--   x, y     normalised 0-1 coordinates for the waypoint
--   noteOnly the NPC name/location already prints on the item, so only show the
--            Ctrl-Click instruction (no extra location line)
--   label    prefix label for an entry (used by multi-destination items)
--   entries  list of destinations; all are listed, the first drives the pin
-- ---------------------------------------------------------------------------
local vendorData = {
	-- The War Within: Midnight-era barter tokens
	[264882] = { npc = 259722, name = "Andra", map = 2393, x = 0.418, y = 0.666, noteOnly = true }, -- Finery Funds
	[267051] = { npc = 255473, name = "Maren Silverwing", map = 2393, x = 0.48, y = 0.492, noteOnly = true }, -- Dark Particle
	[259361] = { name = "Abandoned Ritual Skull", note = L["Inside the Cave"], map = 2437, x = 0.444, y = 0.436 }, -- Vile Essence
	[245937] = { npc = 245976, name = "Deminos Darktrance", map = 2444, x = 0.388, y = 0.816, noteOnly = true }, -- Void-Tainted Remains
	[248944] = { npc = 249098, name = "Balaak the Twice-Exiled", map = 2444, x = 0.536, y = 0.52, noteOnly = true }, -- Ethereal Energy

	-- The War Within
	[225557] = { npc = 226205, name = "Cendvin", map = 2248, x = 0.744, y = 0.452 }, -- Sizzling Cinderpollen
	[212493] = { npc = 225166, name = "Middles", map = 2214, x = 0.4336, y = 0.352, noteOnly = true }, -- Odd Glob of Wax
	[224642] = { npc = 216164, name = "Gnawbles", map = 2214, x = 0.436, y = 0.352 }, -- Firelight Ruby
	[238920] = { sub = 15335, name = "Morgaen's Tears", map = 2215, x = 0.282, y = 0.56 }, -- Radiant Emblem of Service
	[227673] = { npc = 226994, name = "Blair Bass", map = 2346, x = 0.342, y = 0.716 }, -- "Gold" Fish
	[233246] = { npc = 234776, name = "Angelo Rustbin", map = 2346, x = 0.258, y = 0.381, noteOnly = true }, -- Gunk-Covered Thingy
	[234741] = {
		entries = { -- Miscellaneous Mechanica
			{ npc = 228286, name = "Skedgit Cinderbangs", map = 2346, x = 0.432, y = 0.828, label = L["Mount"] },
			{ npc = 236411, name = "Ditty Fuzeboy", map = 2346, x = 0.354, y = 0.412, label = L["Pet"] },
		},
	},
	[245510] = { npc = 245348, name = "Ba'choso", map = 2371, x = 0.42, y = 0.224 }, -- Loombeast Silk

	-- Dragonflight
	[205188] = { npc = 204693, name = "Ponzo", map = 2133, x = 0.58, y = 0.538 }, -- Barter Boulder
	[204715] = { npc = 203602, name = "Spinsoa", map = 2133, x = 0.558, y = 0.554 }, -- Unearthed Fragrant Coin
	[211376] = { npc = 212797, name = "Talisa Whisperbloom", map = 2200, x = 0.498, y = 0.62 }, -- Seedbloom

	-- Class Set Curios
	[249367] = { npc = 254436, name = "Kirana", map = 2424, x = 0.556, y = 0.878, noteOnly = true }, -- Chiming Void Curio
	[237602] = { npc = 248304, name = "Acquirer Ba'theom", map = 2371, x = 0.42, y = 0.224, noteOnly = true }, -- Hungering Void Curio
	[228819] = { npc = 231824, name = "Kari Bridgeblaster", note = L["Second Floor"], sub = 15388, map = 2346, x = 0.439, y = 0.498 }, -- Excessively Bejeweled Curio
	[225634] = { npc = 227003, name = "Kir'xal", map = 2216, x = 0.566, y = 0.458, noteOnly = true }, -- Web-Wrapped Curio
	[210947] = { npc = 213278, name = "Kirasztia", map = 2200, x = 0.366, y = 0.334, noteOnly = true }, -- Flame-Warped Curio
	[206046] = { npc = 205675, name = "Kaitalla", map = 2133, x = 0.52, y = 0.256, noteOnly = true }, -- Void-Touched Curio
}

vendorData[204985] = vendorData[205188] -- Barter Brick shares Barter Boulder's vendor

-- ---------------------------------------------------------------------------
-- Name resolution (session-cached: map/area names never change at runtime)
-- ---------------------------------------------------------------------------
local mapNameCache = {}
local function MapName(uiMapID)
	if not uiMapID then
		return nil
	end
	local cached = mapNameCache[uiMapID]
	if cached == nil then
		local info = C_Map_GetMapInfo and C_Map_GetMapInfo(uiMapID)
		cached = (info and info.name) or false
		mapNameCache[uiMapID] = cached
	end
	return cached or nil
end

local areaNameCache = {}
local function AreaName(areaID)
	if not areaID then
		return nil
	end
	local cached = areaNameCache[areaID]
	if cached == nil then
		cached = (C_Map_GetAreaInfo and C_Map_GetAreaInfo(areaID)) or false
		areaNameCache[areaID] = cached
	end
	return cached or nil
end

-- "Who - Where", with an optional "Label: " prefix.
local function FormatLine(who, where, label)
	local text
	if where and where ~= "" then
		text = format("%s |cffffffff-|r %s", who, where)
	else
		text = who
	end
	if label then
		text = label .. ": " .. text
	end
	return text
end

local function LocationText(e)
	local mapName = MapName(e.map)
	if e.note then
		-- A sub-area note prints against the sub-area name when one is given.
		return FormatLine(e.note, (e.sub and AreaName(e.sub)) or mapName, e.label)
	elseif e.npc then
		return FormatLine(e.name or format("NPC %d", e.npc), mapName, e.label)
	elseif e.sub then
		return FormatLine(AreaName(e.sub) or "", mapName, e.label)
	end
end

-- ---------------------------------------------------------------------------
-- Display: Item tooltip post-call
-- ---------------------------------------------------------------------------
local function AddLocationLine(tooltip, e)
	local text = LocationText(e)
	if text then
		tooltip:AddLine(text, 1, 0.82, 0, true)
	end
end

local function OnItemTooltip(tooltip, data)
	if not db().enable or tooltip ~= GameTooltip or tooltip:IsForbidden() then
		return
	end

	local itemID = data and data.id
	local entry = itemID and vendorData[itemID]
	if not entry then
		return
	end

	tooltip:AddLine(" ")
	if entry.entries then
		for i = 1, #entry.entries do
			AddLocationLine(tooltip, entry.entries[i])
		end
	elseif not entry.noteOnly then
		AddLocationLine(tooltip, entry)
	end
	tooltip:AddLine(WAYPOINT_ICON .. L["<Ctrl-Click to set a waypoint>"], 0.098, 1, 0.098, true)
end

-- ---------------------------------------------------------------------------
-- Waypoint: Ctrl-Click on the item
-- ---------------------------------------------------------------------------
local function SetWaypoint(uiMapID, x, y)
	if not (uiMapID and x and y and UiMapPoint and C_Map_SetUserWaypoint) then
		return
	end
	if C_Map_CanSetUserWaypointOnMap and not C_Map_CanSetUserWaypointOnMap(uiMapID) then
		return
	end

	C_Map_SetUserWaypoint(UiMapPoint.CreateFromCoordinates(uiMapID, x, y))
	if C_SuperTrack_SetSuperTrackedUserWaypoint then
		C_SuperTrack_SetSuperTrackedUserWaypoint(true)
	end
	if db().openMap and C_Map_OpenWorldMap then
		C_Map_OpenWorldMap(uiMapID)
	end
end

local function OnModifiedItemClick(itemLink)
	if not db().enable or not IsControlKeyDown() or not itemLink then
		return
	end
	-- Waypoints/world map can be restricted while in combat; defer to the player.
	if InCombatLockdown() then
		return
	end

	local itemID = GetItemInfoFromHyperlink(itemLink)
	local entry = itemID and vendorData[itemID]
	if not entry then
		return
	end

	local dest = entry.entries and entry.entries[1] or entry
	SetWaypoint(dest.map, dest.x, dest.y)
end

-- ---------------------------------------------------------------------------
-- Lifecycle (hooks install once; handlers gate on the live setting)
-- ---------------------------------------------------------------------------
local hooked = false

local function Setup()
	if hooked then
		return
	end
	hooked = true

	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
	end
	hooksecurefunc("HandleModifiedItemClick", OnModifiedItemClick)
end

function VendorLocation:OnEnable()
	if db().enable then
		Setup()
	end
end

function VendorLocation:OnSettingChanged()
	if db().enable then
		Setup()
	end
end

function VendorLocation:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Vendor Location"], L["For special barter/curio items, show where to turn them in and Ctrl-Click the item to set a map waypoint."])
	local _, mapInit = builder:Checkbox(category, self, "openMap", L["Open Map on Waypoint"], L["Open the world map when you Ctrl-Click to set a vendor waypoint."])

	builder:DependsOn(mapInit, enableInit)
end
