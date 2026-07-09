--[[
	NexEnhance - Tooltip Item Level
	-------------------------------------------------------------------------
	Shows the average item level of an inspected player on their unit tooltip,
	using a throttled inspect + cache so it never spams the server. Secret-safe
	on 12.0 (guarded GUID/inspect reads).
--]]

local _, ns = ...
local F, C = ns.F, ns.C
local Tooltip = ns:GetModule("Tooltip")
if not Tooltip then
	return
end

local _G = _G
local wipe = wipe
local select, max, strfind, format, strsplit = select, math.max, string.find, string.format, string.split
local GetTime, CanInspect, NotifyInspect, ClearInspectPlayer, IsShiftKeyDown = GetTime, CanInspect, NotifyInspect, ClearInspectPlayer, IsShiftKeyDown
local UnitGUID, UnitClass, UnitIsUnit, UnitIsPlayer = UnitGUID, UnitClass, UnitIsUnit, UnitIsPlayer
local UnitIsVisible, UnitIsDeadOrGhost, UnitOnTaxi = UnitIsVisible, UnitIsDeadOrGhost, UnitOnTaxi
local GetInventoryItemTexture, GetInventoryItemLink, GetAverageItemLevel = GetInventoryItemTexture, GetInventoryItemLink, GetAverageItemLevel
local InCombatLockdown = InCombatLockdown
local GetItemInfo, GetItemGem = C_Item.GetItemInfo, C_Item.GetItemGem
local HEIRLOOMS = _G["HEIRLOOMS"]

local levelPrefix = STAT_AVERAGE_ITEM_LEVEL .. ": " .. C.InfoColor
local isPending = LFG_LIST_LOADING
local resetTime, frequency = 900, 0.5
local cache, weapon = {}, {}
-- Reused across artifact-relic scans so we don't allocate a split table per
-- weapon. Multiple-assignment from select() nils the unused slots for us.
local relicScratch = {}
-- The inspect cache is keyed by GUID; cap it so a long session of mousing over
-- many players (cities, raids) can't grow it without bound.
local cacheCount, CACHE_MAX = 0, 200
local currentUNIT, currentGUID, tipShownGUID
local lastTime = 0
local userInspectUntil = 0

hooksecurefunc("InspectUnit", function()
	userInspectUntil = GetTime() + 2
end)

local function checkUnitGUID(unit)
	local guid = UnitGUID(unit)
	return F.NotSecret(guid) and guid
end

local function ItemIDFromLink(link)
	return link and tonumber(link:match("item:(%d+)"))
end

-- Scan equipped slots and compute an effective item level for `unit`.
local function GetUnitItemLevel(unit)
	if not unit or checkUnitGUID(unit) ~= currentGUID then
		return
	end

	local class = select(2, UnitClass(unit))
	if F.IsSecret(class) then
		class = nil
	end

	local boa, total, haveWeapon, twohand = 0, 0, 0, 0
	local ilvl
	local delay, mainhand, offhand, hasArtifact
	weapon[1], weapon[2] = 0, 0

	for i = 1, 17 do
		if i ~= 4 then
			local itemTexture = GetInventoryItemTexture(unit, i)
			if itemTexture then
				local itemLink = GetInventoryItemLink(unit, i)
				if not itemLink then
					delay = true
				else
					local _, _, quality, level, _, _, _, _, slot = GetItemInfo(itemLink)
					if (not quality) or not level then
						delay = true
						local itemID = ItemIDFromLink(itemLink)
						if itemID and ns.RequestItemData then
							ns:RequestItemData(itemID, function()
								if currentGUID == checkUnitGUID(unit) then
									InspectUnit(unit, true)
								end
							end)
						end
					else
						if quality == Enum.ItemQuality.Heirloom then
							boa = boa + 1
						end

						if unit ~= "player" then
							level = F.GetItemLevel(itemLink) or level
							if i < 16 then
								total = total + level
							elseif i > 15 and quality == Enum.ItemQuality.Artifact then
								relicScratch[1], relicScratch[2], relicScratch[3] = select(4, strsplit(":", itemLink))
								for r = 1, 3 do
									local relicID = relicScratch[r] and relicScratch[r] ~= "" and relicScratch[r]
									local relicLink = select(2, GetItemGem(itemLink, r))
									if relicID and not relicLink then
										delay = true
										break
									end
								end
							end

							if i == 16 then
								if quality == Enum.ItemQuality.Artifact then
									hasArtifact = true
								end
								weapon[1] = level
								haveWeapon = haveWeapon + 1
								if slot == "INVTYPE_2HWEAPON" or slot == "INVTYPE_RANGED" or (slot == "INVTYPE_RANGEDRIGHT" and class == "HUNTER") then
									mainhand = true
									twohand = twohand + 1
								end
							elseif i == 17 then
								weapon[2] = level
								haveWeapon = haveWeapon + 1
								if slot == "INVTYPE_2HWEAPON" then
									offhand = true
									twohand = twohand + 1
								end
							end
						end
					end
				end
			end
		end
	end

	if delay then
		return
	end

	if unit == "player" then
		ilvl = select(2, GetAverageItemLevel())
	else
		if hasArtifact or twohand == 2 then
			total = total + max(weapon[1], weapon[2]) * 2
		elseif twohand == 1 and haveWeapon == 1 then
			total = total + weapon[1] * 2 + weapon[2] * 2
		elseif twohand == 1 and haveWeapon == 2 then
			if mainhand and weapon[1] >= weapon[2] then
				total = total + weapon[1] * 2
			elseif offhand and weapon[2] >= weapon[1] then
				total = total + weapon[2] * 2
			else
				total = total + weapon[1] + weapon[2]
			end
		else
			total = total + weapon[1] + weapon[2]
		end
		ilvl = total / 16
	end

	if ilvl > 0 then
		ilvl = format("%.1f", ilvl)
	end
	if boa > 0 then
		ilvl = ilvl .. " |cff00ccff(" .. boa .. (HEIRLOOMS or "") .. ")"
	end
	return ilvl
end

-- Write (or refresh) the item-level line on the mouseover tooltip.
local function SetupItemLevelLine(level)
	if not GameTooltip:IsShown() then
		return
	end
	if not tipShownGUID or F.IsSecret(tipShownGUID) or tipShownGUID ~= currentGUID then
		return
	end
	if Tooltip._tipShownGUID ~= tipShownGUID then
		return
	end

	local levelLine
	for i = 2, GameTooltip:NumLines() do
		local line = _G["GameTooltipTextLeft" .. i]
		local text = line and line:GetText()
		if text and F.NotSecret(text) and strfind(text, levelPrefix) then
			levelLine = line
		end
	end

	level = levelPrefix .. (level or isPending)
	if levelLine then
		levelLine:SetText(level)
	else
		GameTooltip:AddLine(level)
	end
end

local updater = CreateFrame("Frame")
updater:Hide()
updater:SetScript("OnUpdate", function(self, elapsed)
	self.elapsed = (self.elapsed or frequency) + elapsed
	if self.elapsed > frequency then
		self.elapsed = 0
		self:Hide()
		ClearInspectPlayer()
		-- Incident (TooltipItemLevel, Jul 2026): after tooltip hide, stale currentUNIT
		-- kept NotifyInspect firing. Only inspect while this tip is still the shown one.
		if not currentUNIT or not currentGUID or Tooltip._tipShownGUID ~= tipShownGUID then
			return
		end
		if checkUnitGUID(currentUNIT) == currentGUID then
			NotifyInspect(currentUNIT)
		end
	end
end)

-- Called from Tooltip.lua OnGameTooltipHide — stop inspect work when the tip closes.
function Tooltip:ClearItemLevelInspectState()
	currentUNIT, currentGUID, tipShownGUID = nil, nil, nil
	updater.elapsed = frequency
	updater:Hide()
end

local function InspectUnit(unit, forced)
	local level
	local isPlayerUnit = F.SafeUnitIsUnit(unit, "player")
	if isPlayerUnit then
		level = GetUnitItemLevel("player")
		SetupItemLevelLine(level)
		return
	end

	if not unit or checkUnitGUID(unit) ~= currentGUID then
		return
	end
	local isPlayer = UnitIsPlayer(unit)
	if F.IsSecret(isPlayer) or not isPlayer then
		return
	end

	local currentDB = cache[currentGUID]
	if not currentDB then
		return
	end

	level = currentDB.level
	SetupItemLevelLine(level)

	if not ns.db.tooltip.itemLevelByShift and IsShiftKeyDown() then
		forced = true
	end
	if level and not forced and (GetTime() - (currentDB.getTime or 0) < resetTime) then
		updater.elapsed = frequency
		return
	end
	local isVisible = UnitIsVisible(unit)
	local playerDead = UnitIsDeadOrGhost("player")
	local playerOnTaxi = UnitOnTaxi("player")
	if F.IsSecret(isVisible) or not isVisible or F.IsSecret(playerDead) or playerDead or F.IsSecret(playerOnTaxi) or playerOnTaxi then
		return
	end
	if InspectFrame and InspectFrame:IsShown() then
		return
	end
	if GetTime() < userInspectUntil then
		return
	end

	SetupItemLevelLine()
	updater:Show()
end

function Tooltip:INSPECT_READY(guid)
	if F.NotSecret(guid) and guid == currentGUID and guid == tipShownGUID
		and Tooltip._tipShownGUID == tipShownGUID then
		local db = cache[currentGUID]
		if not db then
			return
		end
		local level = GetUnitItemLevel(currentUNIT)
		db.level = level
		db.getTime = GetTime()
		if level then
			SetupItemLevelLine(level)
		else
			InspectUnit(currentUNIT, true)
		end
	end
end

function Tooltip:UNIT_INVENTORY_CHANGED(unit)
	if InCombatLockdown() then
		return
	end
	if not currentGUID or Tooltip._tipShownGUID ~= tipShownGUID then
		return
	end
	local thisTime = GetTime()
	if thisTime - lastTime > 0.1 then
		lastTime = thisTime
		if checkUnitGUID(unit) == currentGUID then
			InspectUnit(unit, true)
		end
	end
end

-- Entry point called from the unit tooltip rewrite.
function Tooltip:InspectUnitItemLevel(unit, guid)
	if not Tooltip:IsEnabled() or not ns.db.tooltip.showItemLevel then
		return
	end
	if ns.db.tooltip.itemLevelByShift and not IsShiftKeyDown() then
		return
	end

	if not unit or not CanInspect(unit) then
		return
	end
	currentUNIT = unit
	currentGUID = (guid and F.NotSecret(guid) and guid) or checkUnitGUID(unit)
	tipShownGUID = currentGUID
	if not currentGUID then
		return
	end
	if not cache[currentGUID] then
		if cacheCount >= CACHE_MAX then
			wipe(cache)
			cacheCount = 0
		end
		cache[currentGUID] = {}
		cacheCount = cacheCount + 1
	end
	InspectUnit(unit)
end

-- Registered from OnEnable.
function Tooltip:SetupItemLevel()
	if self._itemLevelEventsRegistered then
		return
	end
	self._itemLevelEventsRegistered = true
	local handles = self.eventHandles
	if not handles then
		return
	end
	self:TrackEvent(handles, "UNIT_INVENTORY_CHANGED")
	self:TrackEvent(handles, "INSPECT_READY")
end
