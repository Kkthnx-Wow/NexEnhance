--[[
	NexEnhance - ExtraQuestButton
	-------------------------------------------------------------------------
	A keybindable button that surfaces the closest usable quest item from your
	log (the one Blizzard would otherwise bury in the objective tracker), so one
	bind uses whatever the current objective needs. Uses the same HUD action-bar
	art as the ActionBars module.

	Design notes:
	  * The button is a SecureActionButtonTemplate driven by a state driver, so
	    it is created and configured out of combat only; in-combat changes are
	    deferred to PLAYER_REGEN_ENABLED (SetAttribute/SetSize are protected).
	  * It is anchored to a plain, always-shown anchor frame that carries the
	    Edit Mode mover. The secure button is never re-pointed after creation,
	    which keeps repositioning taint-free even though the button can be hidden
	    while no quest item is relevant.
	  * Quest data can be Secret inside instances; the link/count/distance reads
	    are guarded with F.NotSecret before any string/arithmetic use.
--]]

local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

-- Localised globals (hot-path friendly).
local _G = _G
local next, type = next, type
local tonumber = tonumber
local sqrt = math.sqrt
local format = string.format
local match = string.match
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local RegisterStateDriver = RegisterStateDriver
local UnitCreatureID = UnitCreatureID
local UnitGUID = UnitGUID
local HasExtraActionBar = HasExtraActionBar
local GetBindingKey, GetBindingText = GetBindingKey, GetBindingText
local GetItemInfoFromHyperlink = GetItemInfoFromHyperlink
local GetQuestLogSpecialItemInfo = GetQuestLogSpecialItemInfo
local QuestHasPOIInfo = QuestHasPOIInfo
local RANGE_INDICATOR = RANGE_INDICATOR
local TOOLTIP_UPDATE_TIME = TOOLTIP_UPDATE_TIME or 0.2

local C_Item = C_Item
local C_DurationUtil_CreateDuration = C_DurationUtil and C_DurationUtil.CreateDuration
-- Pulled out of C_Item because it's the only member called from OnUpdate; the
-- rest live in event-driven paths where a namespace lookup is noise.
local IsItemInRange = C_Item.IsItemInRange
local C_UnitAuras = C_UnitAuras
local C_Map_GetBestMapForUnit = C_Map.GetBestMapForUnit
local C_Map_GetPlayerMapPosition = C_Map.GetPlayerMapPosition
local C_QuestLog_GetInfo = C_QuestLog.GetInfo
local C_QuestLog_IsOnMap = C_QuestLog.IsOnMap
local C_QuestLog_IsComplete = C_QuestLog.IsComplete
local C_QuestLog_IsWorldQuest = C_QuestLog.IsWorldQuest
local C_QuestLog_GetDistanceSqToQuest = C_QuestLog.GetDistanceSqToQuest
local C_QuestLog_GetNumQuestWatches = C_QuestLog.GetNumQuestWatches
local C_QuestLog_GetNumQuestLogEntries = C_QuestLog.GetNumQuestLogEntries
local C_QuestLog_GetLogIndexForQuestID = C_QuestLog.GetLogIndexForQuestID
local C_QuestLog_GetNumWorldQuestWatches = C_QuestLog.GetNumWorldQuestWatches
local C_QuestLog_GetQuestIDForQuestWatchIndex = C_QuestLog.GetQuestIDForQuestWatchIndex
local C_QuestLog_GetQuestIDForWorldQuestWatchIndex = C_QuestLog.GetQuestIDForWorldQuestWatchIndex

local NotSecret = F.NotSecret

local MAX_DISTANCE_YARDS = 1e3 -- ignore quest items farther than this

-- ---------------------------------------------------------------------------
-- Defaults & module
-- ---------------------------------------------------------------------------
ns:RegisterDefaults({
	extraQuestButton = {
		enable = false,
		size = 44,
		trackingOnly = false,
		zoneOnly = false,
		distanceYd = 1000,
	},
})

local EQB = ns:NewModule("ExtraQuestButton", "extraQuestButton", { group = "actionbars", title = L["Extra Quest Button"], order = 60 })
local eventHandles = {}
local bagCooldownDispatchId

-- ---------------------------------------------------------------------------
-- Quest/item priority tables (questID and itemID keyed)
--   These tweak the auto-detection for quests the API reports inaccurately;
--   they are pure data, built once at file scope.
-- ---------------------------------------------------------------------------

-- Warlords of Draenor intro quest items which inspired the original addon.
local blacklist = {
	[113191] = true,
	[110799] = true,
	[109164] = true,
	[191729] = true,
}

-- Items that should be used on specific mobs (npcID = itemID); these win over
-- distance-based quest matching when the player has the target selected.
local targetItems = {
	[9999] = 11804, -- Un'Goro Crater
	[25321] = 34711, -- Borean Tundra
	[25322] = 34711, -- Borean Tundra
	[25752] = 35352, -- Borean Tundra
	[25753] = 35352, -- Borean Tundra
	[25758] = 35352, -- Borean Tundra
	[25814] = 35401, -- Borean Tundra
	[26811] = 36859, -- Grizzly Hills
	[26812] = 36859, -- Grizzly Hills
	[26841] = 37887, -- Dragonblight
	[27122] = 37887, -- Dragonblight
	[27808] = 37887, -- Dragonblight
	[28750] = 39157, -- Zul'Drak
	[28802] = 39206, -- Zul'Drak
	[28843] = 39238, -- Zul'Drak
	[28931] = 39664, -- Zul'Drak
	[29747] = 41265, -- Icecrown
	[34925] = 46954, -- Icecrown
	[35092] = 46954, -- Icecrown
	[36231] = 49202, -- Gilneas
	[36845] = 49647, -- Mulgore
	[36922] = 49679, -- Azshara
	[42681] = 58167, -- Deepholm
	[42682] = 58167, -- Deepholm
	[43814] = 60206, -- Duskwood
	[43923] = 60225, -- Duskwood
	[44218] = 60490, -- Deepholm
	[44262] = 60503, -- Loch Modan
	[48136] = 63426, -- Hillsbrad Foothills
	[48269] = 63508, -- Hillsbrad Foothills
	[48741] = 64445, -- Hillsbrad Foothills
	[48742] = 64445, -- Hillsbrad Foothills
	[81183] = 115475, -- Spires of Arak
	[141501] = 162450, -- Zuldazar
	[158532] = 172950, -- Ardenweald
	[166958] = 183689, -- Icecrown
	[166959] = 183689, -- Icecrown
	[167395] = 172020, -- Maldraxxus
	[169206] = 179921, -- Ardenweald
	[171211] = 180613, -- Bastion
	[175857] = 186199, -- Night Fae Assault in Maw
	[176131] = 186199, -- Night Fae Assault in Maw
	[178693] = 186097, -- Night Fae Assault in Maw
	[178704] = 186097, -- Night Fae Assault in Maw
	[178786] = 186199, -- Night Fae Assault in Maw
	[178855] = 186199, -- Night Fae Assault in Maw
	[178859] = 186199, -- Night Fae Assault in Maw
	[178878] = 186199, -- Night Fae Assault in Maw
	[179217] = 186199, -- Night Fae Assault in Maw
	[226580] = 219322, -- Azj-Kahet
}

-- Quests without a defined map area (questID = bool/mapID/{mapID,...}); these
-- get low priority during collision.
local inaccurateQuestAreas = {
	[11731] = { 84, 87, 103 }, -- alliance capitals (missing Darnassus)
	[11921] = { 84, 87, 103 }, -- alliance capitals (missing Darnassus)
	[11922] = { 18, 85, 88, 110 }, -- horde capitals
	[11926] = { 18, 85, 88, 110 }, -- horde capitals
	[12779] = 124, -- Scarlet Enclave (Death Knight starting zone)
	[13798] = 63, -- Ashenvale
	[13875] = 63, -- Ashenvale
	[13998] = 11, -- Northern Barrens
	[14246] = 66, -- Desolace
	[24440] = 7, -- Mulgore
	[24456] = 7, -- Mulgore
	[24524] = 7, -- Mulgore
	[24629] = { 84, 85, 87, 88, 103, 110 }, -- major capitals (missing Darnassus & Undercity)
	[25577] = 198, -- Mount Hyjal
	[29506] = 407, -- Darkmoon Island
	[29510] = 407, -- Darkmoon Island
	[29515] = 407, -- Darkmoon Island
	[29516] = 407, -- Darkmoon Island
	[29517] = 407, -- Darkmoon Island
	[49813] = true, -- anywhere
	[49846] = true, -- anywhere
	[49860] = true, -- anywhere
	[49864] = true, -- anywhere
	[25798] = 64, -- Thousand Needles
	[25799] = 64, -- Thousand Needles
	[34461] = 590, -- Horde Garrison
	[34587] = 582, -- Alliance Garrison
	[53476] = true,
	[59809] = true,
	[63892] = { 1961, 2006, 2007 }, -- Korthia and sub-zones
	[75923] = 2023, -- Ohn'ahran Plains
	[66439] = 2022, -- The Waking Shores
	[77891] = 2200, -- Emerald Dream
	[78068] = true, -- anywhere
	[78070] = true, -- anywhere
	[78075] = true, -- anywhere
	[78081] = true, -- anywhere
	[60004] = 118, -- Legion pre-event quest
	[63971] = 1543, -- Night Fae assault
	[79960] = 2255,
	[13103] = 125, -- Dalaran (Northrend)
	[13115] = 125, -- Dalaran (Northrend)
	[13107] = 125, -- Dalaran (Northrend)
	[13116] = 125, -- Dalaran (Northrend)
	[13114] = { 125, 127 }, -- Crystalsong Forest
	[13102] = { 125, 127 }, -- Crystalsong Forest
	[86603] = 2371, -- K'aresh
	[89056] = 2371, -- K'aresh
	[35187] = 539, -- Shadowmoon Valley
	[54103] = 49, -- Redridge Mountains
	[54106] = 49, -- Redridge Mountains
	[54999] = true,
	[55034] = true,
	[79331] = { 1, 37 }, -- Noblegarden
	[79578] = { 1, 37 }, -- Noblegarden
	[79330] = { 1, 37 }, -- Noblegarden
	[79577] = { 1, 37 }, -- Noblegarden
}

-- Items that should be used for a quest but the API does not report (questID = itemID).
local questItems = {
	[10129] = 28038, -- Hellfire Peninsula
	[10146] = 28038, -- Hellfire Peninsula
	[10162] = 28132, -- Hellfire Peninsula
	[10163] = 28132, -- Hellfire Peninsula
	[10346] = 28132, -- Hellfire Peninsula
	[10347] = 28132, -- Hellfire Peninsula
	[11617] = 34772, -- Borean Tundra
	[11633] = 34782, -- Borean Tundra
	[11894] = 35288, -- Borean Tundra
	[11982] = 35734, -- Grizzly Hills
	[11986] = 35739, -- Grizzly Hills
	[11989] = 38083, -- Grizzly Hills
	[12066] = 36751, -- Dragonblight
	[12026] = 35739, -- Grizzly Hills
	[12415] = 37716, -- Grizzly Hills
	[12007] = 35797, -- Grizzly Hills
	[12456] = 37881, -- Dragonblight
	[12470] = 37923, -- Dragonblight
	[12484] = 38149, -- Grizzly Hills
	[12661] = 41390, -- Zul'Drak
	[12713] = 38699, -- Zul'Drak
	[12861] = 41161, -- Zul'Drak
	[12925] = 41612, -- Storm Peaks
	[13343] = 44450, -- Dragonblight
	[13425] = 41612, -- Storm Peaks
	[13542] = 44868, -- Darkshore
	[13890] = 46365, -- Ashenvale
	[26868] = 60681, -- Loch Modan
	[27384] = 12888, -- Eastern Plaguelands
	[28317] = 63357, -- Burning Steppes
	[28318] = 63357, -- Burning Steppes
	[28319] = 63357, -- Burning Steppes
	[28450] = 63357, -- Burning Steppes
	[28451] = 63357, -- Burning Steppes
	[28452] = 63357, -- Burning Steppes
	[29821] = 84157, -- Jade Forest
	[31112] = 84157, -- Jade Forest
	[31769] = 89769, -- Jade Forest
	[35237] = 11891, -- Ashenvale
	[36848] = 36851, -- Grizzly Hills
	[37565] = 118330, -- Azsuna
	[39385] = 128287, -- Stormheim
	[39847] = 129047, -- Dalaran (Broken Isles)
	[40003] = 129161, -- Stormheim
	[40965] = 133882, -- Suramar
	[43827] = 129161, -- Stormheim
	[49402] = 154878, -- Tiragarde Sound
	[50164] = 154878, -- Tiragarde Sound
	[51646] = 154878, -- Tiragarde Sound
	[53476] = 163852, -- Zandalar/Kul Tiras
	[58586] = 174465, -- Venthyr Covenant
	[59063] = 175137, -- Night Fae Covenant
	[59809] = 177904, -- Night Fae Covenant
	[60188] = 178464, -- Night Fae Covenant
	[60649] = 180170, -- Ardenweald
	[60609] = { 180008, 180009 }, -- Ardenweald
	[61708] = 174043, -- Maldraxxus
	[63892] = 185963, -- Korthia
	[12022] = 169219, -- Brewfest
	[12191] = 169219, -- Brewfest
	[66439] = 192545, -- The Waking Shores
	[77891] = 209017, -- Emerald Dream
	[77483] = 202247, -- Technoscrying
	[77484] = 202247, -- Technoscrying
	[77434] = 202247, -- Technoscrying
	[78931] = 202247, -- Technoscrying
	[78820] = 202247, -- Technoscrying
	[78616] = 202247, -- Technoscrying
	[78755] = 211483, -- Khaz Algar
	[79960] = 216664, -- Azj-Kahet
	[84672] = { 229824, 229825, 229805 }, -- Undermine
	[35187] = { 112904, 112791 }, -- Garrison Campaign
}

-- Items that should be shown but the API hides (itemID = bool/mapID).
local completeShownItems = {
	[35797] = 116, -- Grizzly Hills
	[60273] = 50, -- Northern Stranglethorn
	[52853] = true, -- Mount Hyjal
	[41058] = 120, -- Storm Peaks
	[57412] = 205, -- Shimmering Expanse
	[62508] = 241, -- Twilight Highlands
	[63357] = 36, -- Burning Steppes
	[64660] = 241, -- Twilight Highlands
	[177904] = true,
}

-- Items that are shown after the quest is complete but should not be; a numeric
-- Non-zero value = use this replacement item instead of the quest item.
local noCompleteItems = {
	[23680] = 60273, -- Northern Stranglethorn Vale
}

-- Same as inaccurateQuestAreas, but with a precise point. We approximate the
-- point distance without HereBeDragons; it is only used for priority ranking.
local accurateQuestAreas = {
	[12484] = { 116, 0.1683, 0.4834 }, -- Grizzly Hills
	[27389] = { 23, 0.3596, 0.4573 }, -- Eastern Plaguelands
	[27451] = { 23, 0.5526, 0.6225 }, -- Eastern Plaguelands
	[35001] = { 542, 0.6681, 0.4553 }, -- Spires of Arak
	[57455] = { 1565, 0.3075, 0.3568 }, -- Ardenweald
	[63971] = { 1543, 0.2308, 0.3729 }, -- The Maw
	[82266] = { 2213, 0.3081, 0.3343 }, -- City of Threads, Azj-Kahet
}

-- Items that should win collisions in areas with multiple quest items.
local priorityItems = {
	[46316] = -10, -- Orc-Hair Braid, Ashenvale
	[63508] = 1, -- Helcular's Rod, Hillsbrad Foothills
	[64471] = 1, -- Goblin Pocket-Nuke, Hillsbrad Foothills
	[64583] = 2, -- Water Barrel, Hillsbrad Foothills
	[232466] = -10, -- Leave the Storm, Siren Isle
	[228988] = 1, -- Rock Reviver, Siren Isle
}

-- ---------------------------------------------------------------------------
-- Skinning: same HUD art the ActionBars module applies to the bars.
-- ---------------------------------------------------------------------------
local HUD_ICON_FRAME = "UI-HUD-ActionBar-IconFrame"
local HUD_ICON_FRAME_DOWN = "UI-HUD-ActionBar-IconFrame-Down"
local HUD_ICON_FRAME_SLOT = "UI-HUD-ActionBar-IconFrame-Slot"
local HUD_ICON_FRAME_MOUSEOVER = "UI-HUD-ActionBar-IconFrame-Mouseover"
-- Blizzard's HUD icon mask (ActionButtonTemplate/ExtraActionBar IconMask) rounds
-- the icon to the gold frame opening so the corners can't poke past it.
local HUD_ICON_MASK = "UI-HUD-ActionBar-IconFrame-Mask"
local FRAME_WIDTH_RATIO = 46 / 45 -- the IconFrame atlas overhangs its 45px button
-- Blizzard centers the 64px mask atlas over a 45px icon (~1.42x), so its feathered
-- border sits outside the icon and the art fills the frame.
local MASK_SIZE_RATIO = 64 / 45
local GOLD = C.Colors.yellow

local function SizeFrameArt(texture, button)
	if not texture then
		return
	end
	local w, h = button:GetSize()
	if not w or w == 0 then
		w = 44
	end
	if not h or h == 0 then
		h = 44
	end
	texture:SetDrawLayer("OVERLAY")
	texture:ClearAllPoints()
	texture:SetPoint("CENTER")
	texture:SetSize(w * FRAME_WIDTH_RATIO, h)
	texture:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
end

-- The gold IconFrame chrome is the button's OVERLAY NormalTexture, but the
-- Cooldown is a child frame - child frames render above ALL of the parent's
-- textures, so a full-size swipe sweeps over the gold border. Inset the cooldown
-- to the frame's inner opening (matching how Blizzard insets its action-button
-- icons) so the swipe and its leading edge stay inside the border.
local COOLDOWN_INSET_RATIO = 0.07
local function SizeCooldown(button)
	local cooldown = button.Cooldown
	if not cooldown then
		return
	end
	local w = button:GetWidth()
	if not w or w == 0 then
		w = 44
	end
	local inset = w * COOLDOWN_INSET_RATIO
	cooldown:ClearAllPoints()
	cooldown:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
	cooldown:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
end

-- Re-apply the gold frame art at the button's current size (called after a size
-- change). Runs out of combat only via the caller.
local function ResizeButtonArt(button)
	SizeFrameArt(button:GetNormalTexture(), button)
	SizeFrameArt(button:GetPushedTexture(), button)
	if button.nexSlotArt then
		button.nexSlotArt:SetAllPoints(button)
	end
	local w, h = button:GetSize()
	if not w or w == 0 then
		w = 44
	end
	if not h or h == 0 then
		h = 44
	end
	if button.nexIconMask then
		button.nexIconMask:ClearAllPoints()
		button.nexIconMask:SetPoint("CENTER")
		button.nexIconMask:SetSize(w * MASK_SIZE_RATIO, h * MASK_SIZE_RATIO)
	end
	-- Highlight matches the regular action-button footprint, not the icon, so the
	-- mouseover art lines up with the frame edges.
	if button.nexHighlight then
		button.nexHighlight:ClearAllPoints()
		button.nexHighlight:SetPoint("CENTER")
		button.nexHighlight:SetSize(w * FRAME_WIDTH_RATIO, h)
	end
	SizeCooldown(button)
end

-- ---------------------------------------------------------------------------
-- Closest usable quest item in log (Secret-guarded distance/count reads)
-- ---------------------------------------------------------------------------
local function GetItemLinkFromID(itemID)
	return format("|Hitem:%d|h", itemID)
end

local function GetBestFallbackItemLink(questID)
	local fallbackItemID = questItems[questID]
	if fallbackItemID == 202247 and C_UnitAuras then
		-- Technoscrying quests should not show while the disguise/aura is active.
		if C_UnitAuras.GetPlayerAuraBySpellID(409668) or C_UnitAuras.GetPlayerAuraBySpellID(414539) then
			fallbackItemID = nil
		end
	end

	if type(fallbackItemID) == "table" then
		for _, itemID in next, fallbackItemID do
			local link = GetItemLinkFromID(itemID)
			local count = C_Item.GetItemCount(link)
			if NotSecret(count) and count > 0 then
				return link
			end
		end
	elseif fallbackItemID then
		return GetItemLinkFromID(fallbackItemID)
	end
end

local function IsQuestOnMapCurrentMap(questID)
	if C_QuestLog_IsOnMap(questID) then
		return true
	end

	local currentMapID = C_Map_GetBestMapForUnit("player")
	local accurateQuestArea = accurateQuestAreas[questID]
	if accurateQuestArea and accurateQuestArea[1] == currentMapID then
		return true
	end

	local questMapID = inaccurateQuestAreas[questID]
	if type(questMapID) == "boolean" then
		return true
	elseif type(questMapID) == "number" then
		return questMapID == currentMapID
	elseif type(questMapID) == "table" then
		for _, mapID in next, questMapID do
			if mapID == currentMapID then
				return true
			end
		end
	end
end

local function GetDistanceSqToPoint(mapID, x, y)
	local currentMapID = C_Map_GetBestMapForUnit("player")
	if currentMapID ~= mapID then
		return
	end

	local position = C_Map_GetPlayerMapPosition(mapID, "player")
	if not position then
		return
	end

	local playerX, playerY = position:GetXY()
	if not NotSecret(playerX) or not NotSecret(playerY) then
		return
	end

	local dx, dy = playerX - x, playerY - y
	return (dx * dx) + (dy * dy)
end

local function GetQuestDistanceWithItem(questID, maxDistanceYd)
	local questLogIndex = C_QuestLog_GetLogIndexForQuestID(questID)
	if not questLogIndex then
		return
	end

	local itemLink, _, _, showWhenComplete = GetQuestLogSpecialItemInfo(questLogIndex)
	if not itemLink then
		itemLink = GetBestFallbackItemLink(questID)
	end
	-- Quest item links can be Secret inside instances; bail before string use.
	if not itemLink or not NotSecret(itemLink) then
		return
	end

	local count = C_Item.GetItemCount(itemLink)
	if not NotSecret(count) or count == 0 then
		return
	end

	local itemID = GetItemInfoFromHyperlink(itemLink)
	if not itemID or blacklist[itemID] then
		return
	end

	if C_QuestLog_IsComplete(questID) then
		local completeItemZone = completeShownItems[itemID]
		if not showWhenComplete and not completeItemZone then
			return -- show item even when quest completed
		end
		if type(completeItemZone) == "number" and completeItemZone ~= C_Map_GetBestMapForUnit("player") then
			return
		end

		local noCompleteItem = noCompleteItems[itemID]
		if type(noCompleteItem) == "number" then
			-- Swap in the replacement item to show instead (only the link is used downstream).
			itemLink = GetItemLinkFromID(noCompleteItem)
		elseif noCompleteItem then
			return
		end
	end

	local distanceSq = C_QuestLog_GetDistanceSqToQuest(questID)
	local distanceYd = distanceSq and NotSecret(distanceSq) and sqrt(distanceSq)
	if distanceYd and distanceYd <= maxDistanceYd then
		return distanceYd, itemLink
	end

	local accurateQuestArea = accurateQuestAreas[questID]
	if accurateQuestArea then
		local distanceSqToPoint = GetDistanceSqToPoint(accurateQuestArea[1], accurateQuestArea[2], accurateQuestArea[3])
		if distanceSqToPoint then
			return sqrt(distanceSqToPoint) * maxDistanceYd, itemLink
		end
	end

	local questMapID = inaccurateQuestAreas[questID]
	if questMapID then
		local currentMapID = C_Map_GetBestMapForUnit("player")
		if type(questMapID) == "boolean" then
			return maxDistanceYd - 1, itemLink
		elseif type(questMapID) == "number" then
			if questMapID == currentMapID then
				return maxDistanceYd - 2, itemLink
			end
		elseif type(questMapID) == "table" then
			for _, mapID in next, questMapID do
				if mapID == currentMapID then
					return maxDistanceYd - 2, itemLink
				end
			end
		end
	end
end

local function GetClosestQuestItem()
	local db = ns.db.extraQuestButton
	local maxDistanceYd = db.distanceYd or MAX_DISTANCE_YARDS
	local zoneOnly = db.zoneOnly
	local trackingOnly = db.trackingOnly
	local closestQuestItemLink
	local closestDistance = maxDistanceYd
	local closestPriority = 0

	local function AddQuestCandidate(questID)
		local distance, itemLink = GetQuestDistanceWithItem(questID, maxDistanceYd)
		if not itemLink then
			return
		end

		local itemID = GetItemInfoFromHyperlink(itemLink)
		local priority = (itemID and priorityItems[itemID]) or 0
		distance = distance or maxDistanceYd
		if not closestQuestItemLink or priority < closestPriority or (priority == closestPriority and distance <= closestDistance) then
			closestPriority = priority
			closestDistance = distance
			closestQuestItemLink = itemLink
		end
	end

	-- Supertracked world quests (shift-clicked on the map).
	for index = 1, C_QuestLog_GetNumWorldQuestWatches() do
		local questID = C_QuestLog_GetQuestIDForWorldQuestWatchIndex(index)
		if questID and (not zoneOnly or IsQuestOnMapCurrentMap(questID)) then
			AddQuestCandidate(questID)
		end
	end

	for index = 1, C_QuestLog_GetNumQuestWatches() do
		local questID = C_QuestLog_GetQuestIDForQuestWatchIndex(index)
		if questID and QuestHasPOIInfo(questID) and (not zoneOnly or IsQuestOnMapCurrentMap(questID)) then
			AddQuestCandidate(questID)
		end
	end

	for index = 1, C_QuestLog_GetNumQuestLogEntries() do
		local info = C_QuestLog_GetInfo(index)
		local questID = info and info.questID
		if info and questID and not info.isHeader and info.hasLocalPOI then
			if C_QuestLog_IsWorldQuest(questID) or info.questClassification == Enum.QuestClassification.BonusObjective or (trackingOnly and not info.isHidden) then
				if not zoneOnly or IsQuestOnMapCurrentMap(questID) then
					AddQuestCandidate(questID)
				end
			end
		end
	end

	-- Bonus objective tasks (e.g. world tasks that drop usable items).
	local tasksTable = GetTasksTable and GetTasksTable()
	if tasksTable then
		for i = 1, #tasksTable do
			local questID = tasksTable[i]
			if questID and not C_QuestLog_IsWorldQuest(questID) and not QuestUtils_IsQuestWatched(questID) and GetTaskInfo(questID) then
				if not zoneOnly or IsQuestOnMapCurrentMap(questID) then
					AddQuestCandidate(questID)
				end
			end
		end
	end

	return closestQuestItemLink
end

-- ---------------------------------------------------------------------------
-- Button behaviour (methods live on the button so the secure handler's
-- CallMethod("Update") can reach them)
-- ---------------------------------------------------------------------------
local button -- the secure button, built lazily in Setup
local anchor -- plain frame carrying the Edit Mode mover

local function Button_BagUpdateCooldown(self)
	if not (self:IsShown() and self.itemID) then
		return
	end
	local cd = self.Cooldown
	if not cd then
		return
	end
	if C_DurationUtil_CreateDuration then
		local start, duration = C_Item.GetItemCooldown(self.itemID)
		if NotSecret(duration) and duration and duration > 0 and NotSecret(start) then
			local durObj = C_DurationUtil_CreateDuration()
			durObj:SetTimeFromStart(start, duration)
			cd:SetCooldownFromDurationObject(durObj)
			F.MaskCooldownSwipeFromDurationObject(cd, durObj)
			cd:Show()
			return
		end
	else
		local start, duration = C_Item.GetItemCooldown(self.itemID)
		if duration and NotSecret(duration) and duration > 0 then
			cd:SetCooldown(start, duration)
			cd:Show()
			return
		end
	end
	cd:Hide()
end

local function Button_UpdateCount(self)
	if self:IsShown() and self.itemLink then
		local count = C_Item.GetItemCount(self.itemLink)
		if NotSecret(count) and count and count > 1 then
			self.Count:SetFormattedText("%d", count)
		else
			self.Count:SetText("")
		end
	end
end

-- SetAttribute is protected in combat; defer to PLAYER_REGEN_ENABLED (the
-- module owns that event and re-runs this once combat ends).
local function Button_UpdateAttributes(self)
	if InCombatLockdown() then
		if not self.itemID and self:IsShown() then
			self:SetAlpha(0)
		end
		EQB.pendingAttributes = true
		return
	end

	self:SetAlpha(1)

	if self.itemID then
		self:SetAttribute("item", "item:" .. self.itemID)
		Button_BagUpdateCooldown(self)
	else
		self:SetAttribute("item", nil)
	end
end

local function Button_SetItem(self, itemLink)
	if HasExtraActionBar() then
		return
	end

	if itemLink then
		local itemID = GetItemInfoFromHyperlink(itemLink)
		self.Icon:SetTexture(C_Item.GetItemIconByID(itemLink))
		self.itemID = itemID
		self.itemLink = itemLink

		if itemID and blacklist[itemID] then
			return
		end
	end

	if self.itemID then
		local hotKey = self.HotKey
		local key = GetBindingKey("EXTRAACTIONBUTTON1")
		local hasRange = C_Item.ItemHasRange(self.itemID)
		if key then
			hotKey:SetText(GetBindingText(key, 1))
			hotKey:Show()
		elseif hasRange then
			hotKey:SetText(RANGE_INDICATOR)
			hotKey:Show()
		else
			hotKey:Hide()
		end

		Button_UpdateAttributes(self)
		Button_UpdateCount(self)
		self.updateRange = hasRange
	end
end

local function Button_RemoveItem(self)
	self.itemID = nil
	self.itemLink = nil
	Button_UpdateAttributes(self)
end

local function GetTargetCreatureID()
	if UnitCreatureID then
		local npcID = UnitCreatureID("target")
		if npcID ~= nil and NotSecret(npcID) then
			return npcID
		end
	end

	local guid = UnitGUID("target")
	if guid and NotSecret(guid) then
		return tonumber(match(guid, "Creature%-.-%-.-%-.-%-.-%-(%d+)%-"))
	end
end

local function Button_UpdateTarget(self)
	local npcID = GetTargetCreatureID()
	local targetItemID = npcID and targetItems[npcID]
	if targetItemID then
		local count = C_Item.GetItemCount(targetItemID)
		if NotSecret(count) and count > 0 then
			self.targetItemLink = GetItemLinkFromID(targetItemID)
			return
		end
	end

	self.targetItemLink = nil
end

local function Button_Update(self)
	if HasExtraActionBar() or self.locked then
		return
	end

	local itemLink = self.targetItemLink or GetClosestQuestItem()
	if itemLink then
		if itemLink ~= self.itemLink then
			Button_SetItem(self, itemLink)
		end
	elseif self:IsShown() then
		Button_RemoveItem(self)
	end
end

-- Throttled per-frame work: only the range tint needs OnUpdate, plus a slow
-- safety rescan. Both early-out cheaply when nothing is due.
local function Button_OnUpdate(self, elapsed)
	if self.updateRange then
		self.rangeTimer = (self.rangeTimer or 0) + elapsed
		if not InCombatLockdown() and self.rangeTimer > TOOLTIP_UPDATE_TIME then
			self.rangeTimer = 0
			local hotKey, icon = self.HotKey, self.Icon
			-- IsItemInRange can misreport vs. friendly NPCs (Blizzard bug).
			local inRange = IsItemInRange(self.itemLink, "target")
			if hotKey:GetText() == RANGE_INDICATOR then
				if inRange == false then
					hotKey:SetTextColor(1, 0.1, 0.1)
					hotKey:Show()
					icon:SetVertexColor(1, 0.1, 0.1)
				elseif inRange then
					hotKey:SetTextColor(0.6, 0.6, 0.6)
					hotKey:Show()
					icon:SetVertexColor(1, 1, 1)
				else
					hotKey:Hide()
				end
			elseif inRange == false then
				hotKey:SetTextColor(1, 0.1, 0.1)
				icon:SetVertexColor(1, 0.1, 0.1)
			else
				hotKey:SetTextColor(0.6, 0.6, 0.6)
				icon:SetVertexColor(1, 1, 1)
			end
		end
	end

	self.updateTimer = (self.updateTimer or 0) + elapsed
	if self.updateTimer > 5 then
		self.updateTimer = 0
		Button_Update(self)
	end
end

-- Secure environment handler: shows/hides and rebinds the EXTRAACTIONBUTTON1
-- key. Runs in the restricted environment, so it can act during combat.
local onAttributeChanged = [[
	if name == "item" then
		if value and not self:IsShown() and not HasExtraActionBar() then
			self:Show()
		elseif not value then
			self:Hide()
			self:ClearBindings()
		end
	elseif name == "state-visible" then
		if value == "show" then
			self:Show()
			self:CallMethod("Update")
		else
			self:Hide()
			self:ClearBindings()
			self:SetAttribute("item", nil)
		end
	end

	if self:IsShown() then
		self:ClearBindings()

		local key1, key2 = GetBindingKey("EXTRAACTIONBUTTON1")
		if key1 then
			self:SetBindingClick(1, key1, self, "LeftButton")
		end
		if key2 then
			self:SetBindingClick(2, key2, self, "LeftButton")
		end
	end
]]

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------
local function ApplySize(size)
	if not anchor then
		return
	end
	anchor:SetSize(size, size)
	if InCombatLockdown() then
		EQB.pendingSize = true
		return
	end
	button:SetSize(size, size)
	ResizeButtonArt(button)
end

local function BuildButton()
	if button then
		return
	end

	local size = ns.db.extraQuestButton.size or 44

	-- Plain anchor frame owns the Edit Mode mover so the secure button is never
	-- re-pointed (button:SetPoint stays a one-time, out-of-combat call).
	anchor = CreateFrame("Frame", nil, UIParent)
	anchor:SetSize(size, size)
	F.CreateMover(anchor, "extraQuestButton", L["Extra Quest Button"], "BOTTOM", 0, 240)

	button = CreateFrame("Button", "NexExtraQuestButton", UIParent, "SecureActionButtonTemplate, SecureHandlerStateTemplate, SecureHandlerAttributeTemplate")
	button:SetSize(size, size)
	button:SetPoint("CENTER", anchor)
	button:SetClampedToScreen(true)
	button:SetToplevel(true)
	button:Hide()
	button:RegisterForClicks("AnyUp", "AnyDown")

	-- Empty-slot background, icon, then the gold IconFrame chrome on top.
	local slot = button:CreateTexture(nil, "BACKGROUND")
	slot:SetAtlas(HUD_ICON_FRAME_SLOT)
	slot:SetAllPoints(button)
	button.nexSlotArt = slot

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(button)
	button.Icon = icon

	-- Round the icon to the gold frame opening with Blizzard's HUD icon mask
	-- (same as ActionButtonTemplate) instead of a square texcoord crop. Sized and
	-- centered by ResizeButtonArt so the icon fills the frame.
	local iconMask = button:CreateMaskTexture(nil, "ARTWORK")
	iconMask:SetAtlas(HUD_ICON_MASK)
	icon:AddMaskTexture(iconMask)
	button.nexIconMask = iconMask

	button:SetNormalAtlas(HUD_ICON_FRAME)
	button:SetPushedAtlas(HUD_ICON_FRAME_DOWN)
	ResizeButtonArt(button)

	-- Mouseover highlight matching the regular action bars. ExtraActionButton uses
	-- ADD/0.7, but the default action buttons use this atlas at full strength
	-- without additive blending.
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAtlas(HUD_ICON_FRAME_MOUSEOVER)
	button:SetHighlightTexture(highlight)
	button.nexHighlight = highlight
	ResizeButtonArt(button)

	local cooldown = CreateFrame("Cooldown", "$parentCooldown", button, "CooldownFrameTemplate")
	cooldown:SetReverse(false)
	-- The leading-edge highlight rides the swipe's outer radius, so it crosses the
	-- gold border even when the swipe is inset; turn it off and let SizeCooldown
	-- keep the dark swipe inside the frame opening.
	cooldown:SetDrawEdge(false)
	cooldown:Hide()
	button.Cooldown = cooldown
	SizeCooldown(button)

	local hotKey = F.CreateFS(button, 12, nil, "OVERLAY")
	hotKey:ClearAllPoints()
	hotKey:SetPoint("TOPRIGHT", -2, -3)
	button.HotKey = hotKey

	local count = F.CreateFS(button, 14, nil, "OVERLAY")
	count:ClearAllPoints()
	count:SetPoint("BOTTOMRIGHT", -2, 2)
	button.Count = count

	-- Small quest "!" marker so the button reads as a quest tool at a glance.
	local marker = button:CreateTexture(nil, "OVERLAY")
	marker:SetAtlas("QuestNormal")
	marker:SetSize(32, 32)
	marker:SetPoint("TOPLEFT", -4, -4)
	button.Marker = marker

	-- Expose Button_Update so the secure handler's CallMethod("Update") works.
	button.Update = Button_Update

	button:SetScript("OnEnter", function(self)
		if not self.itemLink then
			return
		end
		_G.GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		_G.GameTooltip:SetHyperlink(self.itemLink)
	end)
	button:SetScript("OnLeave", function()
		_G.GameTooltip:Hide()
	end)
	button:SetScript("OnUpdate", Button_OnUpdate)
end

-- Configure the secure attributes/state driver. Must run out of combat.
local function ActivateSecure()
	if InCombatLockdown() then
		EQB.pendingActivate = true
		return
	end
	RegisterStateDriver(button, "visible", "[extrabar][petbattle] hide; show")
	button:SetAttribute("_onattributechanged", onAttributeChanged)
	button:SetAttribute("type", "item")
	Button_UpdateTarget(button)
	Button_Update(button)
	Button_SetItem(button)
end

-- ---------------------------------------------------------------------------
-- Event handling (routed through the shared module dispatcher)
-- ---------------------------------------------------------------------------
function EQB:RefreshHotKey()
	if button and button:IsShown() then
		if InCombatLockdown() then
			self.pendingHotKey = true
			return
		end
		Button_SetItem(button)
		button:SetAttribute("binding", GetTime())
	end
end

-- Quest/zone/aura events arrive in bursts (UNIT_AURA on the player alone can
-- fire many times a second), and each Button_Update runs the full
-- GetClosestQuestItem scan over watched quests, world quests and the quest log.
-- Coalesce that storm into a single scan a tick later. Target changes and bag
-- updates keep their own immediate handlers so the button still feels instant.
local QueueQuestUpdate = F.Debounce(0.1, function()
	if button then
		Button_Update(button)
	end
end)

function EQB:OnQuestEvent()
	QueueQuestUpdate()
end

function EQB:OnTargetChanged()
	if button then
		Button_UpdateTarget(button)
		Button_Update(button)
	end
end

function EQB:OnBagDelayed()
	if button then
		Button_UpdateTarget(button)
		Button_Update(button)
		Button_UpdateCount(button)
	end
end

function EQB:OnBagCooldown()
	if button then
		Button_BagUpdateCooldown(button)
	end
end

-- Build + activate the button. Creating and sizing a protected frame is itself
-- blocked in combat, so when the feature is switched on mid-combat we defer the
-- whole thing to PLAYER_REGEN_ENABLED (only the event hookup is safe meanwhile).
local function EnsureActive()
	EQB:RegisterModuleEvents()
	if InCombatLockdown() then
		EQB.pendingEnable = true
		return
	end
	BuildButton()
	ActivateSecure()
end

function EQB:PLAYER_REGEN_ENABLED()
	if self.pendingEnable then
		self.pendingEnable = nil
		BuildButton()
		ActivateSecure()
	end
	if self.pendingActivate then
		self.pendingActivate = nil
		ActivateSecure()
	end
	if self.pendingSize then
		self.pendingSize = nil
		ApplySize(ns.db.extraQuestButton.size or 44)
	end
	if self.pendingAttributes and button then
		self.pendingAttributes = nil
		Button_UpdateAttributes(button)
	end
	if self.pendingHotKey then
		self.pendingHotKey = nil
		self:RefreshHotKey()
	end
end

function EQB:RegisterModuleEvents()
	if self.eventsRegistered then
		return
	end
	self.eventsRegistered = true

	self:TrackEvent(eventHandles, "PLAYER_REGEN_ENABLED")
	self:TrackEvent(eventHandles, "UPDATE_BINDINGS", "RefreshHotKey")
	bagCooldownDispatchId = ns:RegisterCooldownDispatchCallback(function()
		EQB:OnBagCooldown()
	end, "BAG_UPDATE_COOLDOWN")
	self:TrackEvent(eventHandles, "BAG_UPDATE_DELAYED", "OnBagDelayed")
	self:TrackEvent(eventHandles, "QUEST_LOG_UPDATE", "OnQuestEvent")
	self:TrackEvent(eventHandles, "QUEST_POI_UPDATE", "OnQuestEvent")
	self:TrackEvent(eventHandles, "QUEST_WATCH_LIST_CHANGED", "OnQuestEvent")
	self:TrackEvent(eventHandles, "QUEST_ACCEPTED", "OnQuestEvent")
	self:TrackEvent(eventHandles, "PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED", "OnQuestEvent")
	self:TrackEvent(eventHandles, "WAYPOINT_UPDATE", "OnQuestEvent")
	self:TrackEvent(eventHandles, "PLAYER_TARGET_CHANGED", "OnTargetChanged")
	self:TrackEvent(eventHandles, "ZONE_CHANGED", "OnQuestEvent")
	self:TrackEvent(eventHandles, "ZONE_CHANGED_NEW_AREA", "OnQuestEvent")
	self:TrackUnitEvent(eventHandles, "UNIT_AURA", "OnQuestEvent", "player")
end

function EQB:UnregisterModuleEvents()
	if not self.eventsRegistered then
		return
	end
	self.eventsRegistered = false
	if bagCooldownDispatchId then
		ns:UnregisterCooldownDispatchCallback(bagCooldownDispatchId)
		bagCooldownDispatchId = nil
	end
	ns:UnregisterModuleEventHandles(eventHandles)
end

function EQB:OnDisable()
	self:UnregisterModuleEvents()
	self.pendingEnable = nil
	if button then
		button:Hide()
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function EQB:OnEnable()
	if not ns.db.extraQuestButton.enable then
		return
	end

	EnsureActive()
end

function EQB:OnSettingChanged(key, value)
	if key == "enable" then
		if value then
			-- Build/activate now; nothing to tear down (a state-driven secure
			-- button cannot be safely destroyed, so a reload is cleanest to
			-- fully remove it - matches our other secure modules).
			EnsureActive()
		else
			self:OnDisable()
		end
		return
	end

	if not button then
		return
	end

	if key == "size" then
		ApplySize(value or 44)
	elseif key == "trackingOnly" or key == "zoneOnly" or key == "distanceYd" then
		Button_Update(button)
	end
end

function EQB:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Extra Quest Button"], L["Show a keybindable button for the closest usable quest item (reload to fully hide)."])
	builder:Slider(category, self, "size", L["Button Size"], L["Size of the Extra Quest Button, in pixels (applied out of combat)."], 32, 64, 1)
	builder:Checkbox(category, self, "trackingOnly", L["Only Tracked Quests"], L["Only consider watched quests, world quests, and bonus objectives."])
	builder:Checkbox(category, self, "zoneOnly", L["Only Current Zone"], L["Only show quest items for quests in your current zone."])
	builder:Slider(category, self, "distanceYd", L["Tracking Distance"], L["Maximum quest distance, in yards."], 5, 10000, 1)
end

ns.Debug.RegisterScope("extraQuestButton", {
	title = L["Extra Quest Button"],
	module = EQB,
	dump = function()
		F.Print(format("  eventsRegistered=%s pendingEnable=%s", tostring(EQB.eventsRegistered), tostring(EQB.pendingEnable)))
		if button then
			F.Print(format("  button shown=%s item=%s", tostring(button:IsShown()), tostring(button.itemID)))
		end
	end,
})
