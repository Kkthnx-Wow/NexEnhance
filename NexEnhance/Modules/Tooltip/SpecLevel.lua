local NexEnhance, NE_SpecLevel = ...

-- Credit: Cloudy Unit Info, by Cloudyfa
local select, max, strfind, format, strsplit = select, math.max, string.find, string.format, string.split
local GetTime, CanInspect, NotifyInspect, ClearInspectPlayer, IsShiftKeyDown = GetTime, CanInspect, NotifyInspect, ClearInspectPlayer, IsShiftKeyDown
local UnitGUID, UnitClass, UnitIsUnit, UnitIsPlayer, UnitIsVisible, UnitIsDeadOrGhost, UnitOnTaxi = UnitGUID, UnitClass, UnitIsUnit, UnitIsPlayer, UnitIsVisible, UnitIsDeadOrGhost, UnitOnTaxi
local GetInventoryItemTexture, GetInventoryItemLink, GetItemGem, GetAverageItemLevel = GetInventoryItemTexture, GetInventoryItemLink, GetItemGem, GetAverageItemLevel
local HEIRLOOMS = _G.HEIRLOOMS

local levelPrefix = STAT_AVERAGE_ITEM_LEVEL .. ": " .. NE_SpecLevel.InfoColor
local isPending = LFG_LIST_LOADING
local resetTime, frequency = 900, 0.5
local cache, weapon, currentUNIT, currentGUID = {}, {}

NE_SpecLevel.TierSets = {
	-- WARRIOR
	[217220] = true,
	[217219] = true,
	[217218] = true,
	[217217] = true,
	[217216] = true,
	-- PALADIN
	[217200] = true,
	[217199] = true,
	[217198] = true,
	[217197] = true,
	[217196] = true,
	-- HUNTER
	[217185] = true,
	[217184] = true,
	[217183] = true,
	[217182] = true,
	[217181] = true,
	-- ROGUE
	[217210] = true,
	[217209] = true,
	[217208] = true,
	[217207] = true,
	[217206] = true,
	-- PRIEST
	[217204] = true,
	[217205] = true,
	[217203] = true,
	[217202] = true,
	[217201] = true,
	-- DEATHKNIGHT
	[217225] = true,
	[217224] = true,
	[217223] = true,
	[217222] = true,
	[217221] = true,
	-- SHAMAN
	[217240] = true,
	[217239] = true,
	[217238] = true,
	[217237] = true,
	[217236] = true,
	-- MAGE
	[217234] = true,
	[217233] = true,
	[217232] = true,
	[217231] = true,
	[217235] = true,
	-- WARLOCK
	[217214] = true,
	[217215] = true,
	[217213] = true,
	[217212] = true,
	[217211] = true,
	-- MONK
	[217190] = true,
	[217189] = true,
	[217188] = true,
	[217187] = true,
	[217186] = true,
	-- DRUID
	[217195] = true,
	[217194] = true,
	[217193] = true,
	[217192] = true,
	[217191] = true,
	-- DEMONHUNTER
	[217230] = true,
	[217229] = true,
	[217228] = true,
	[217227] = true,
	[217226] = true,
	-- EVOKER
	[217180] = true,
	[217179] = true,
	[217178] = true,
	[217177] = true,
	[217176] = true,
}

local formatSets = {
	[1] = " |cff14b200(1/4)", -- green
	[2] = " |cff0091f2(2/4)", -- blue
	[3] = " |cff0091f2(3/4)", -- blue
	[4] = " |cffc745f9(4/4)", -- purple
	[5] = " |cffc745f9(5/5)", -- purple
}

function NE_SpecLevel:InspectOnUpdate(elapsed)
	self.elapsed = (self.elapsed or frequency) + elapsed
	if self.elapsed > frequency then
		self.elapsed = 0
		self:Hide()
		ClearInspectPlayer()

		if currentUNIT and UnitGUID(currentUNIT) == currentGUID then
			NE_SpecLevel:RegisterEvent("INSPECT_READY", NE_SpecLevel.GetInspectReady)
			NotifyInspect(currentUNIT)
		end
	end
end

local updater = CreateFrame("Frame")
updater:SetScript("OnUpdate", NE_SpecLevel.InspectOnUpdate)
updater:Hide()

local lastTime = 0
function NE_SpecLevel:GetUnitInventoryChanged(unit)
	local thisTime = GetTime()
	if thisTime - lastTime > 0.1 then
		lastTime = thisTime

		if UnitGUID(unit) == currentGUID then
			NE_SpecLevel:InspectUnit(unit, true)
		end
	end

	NE_SpecLevel:UnregisterEvent("UNIT_INVENTORY_CHANGED", NE_SpecLevel.GetUnitInventoryChanged)
end
NE_SpecLevel:RegisterEvent("UNIT_INVENTORY_CHANGED", NE_SpecLevel.GetUnitInventoryChanged)

function NE_SpecLevel:GetInspectReady(guid)
	if guid == currentGUID then
		local level = NE_SpecLevel:GetUnitItemLevel(currentUNIT)
		cache[guid].level = level
		cache[guid].getTime = GetTime()

		if level then
			NE_SpecLevel:SetupItemLevel(level)
		else
			NE_SpecLevel:InspectUnit(currentUNIT, true)
		end
	end

	NE_SpecLevel:UnregisterEvent("INSPECT_READY", NE_SpecLevel.GetInspectReady)
end

function NE_SpecLevel:SetupItemLevel(level)
	local _, unit = GameTooltip:GetUnit()
	if not unit or UnitGUID(unit) ~= currentGUID then
		return
	end

	local levelLine
	for i = 2, GameTooltip:NumLines() do
		local line = _G["GameTooltipTextLeft" .. i]
		local text = line:GetText()
		if text and strfind(text, levelPrefix) then
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

function NE_SpecLevel:GetUnitItemLevel(unit)
	if not unit or UnitGUID(unit) ~= currentGUID then
		return
	end

	local class = select(2, UnitClass(unit))
	local ilvl, boa, total, haveWeapon, twohand, sets = 0, 0, 0, 0, 0, 0
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
					else
						if quality == Enum.ItemQuality.Heirloom then
							boa = boa + 1
						end

						local itemID = GetItemInfoFromHyperlink(itemLink)
						if NE_SpecLevel.TierSets[itemID] then
							sets = sets + 1
						end

						if unit ~= "player" then
							level = NE_SpecLevel.GetItemLevel(itemLink) or level
							if i < 16 then
								total = total + level
							elseif i > 15 and quality == Enum.ItemQuality.Artifact then
								local relics = { select(4, strsplit(":", itemLink)) }
								for i = 1, 3 do
									local relicID = relics[i] ~= "" and relics[i]
									local relicLink = select(2, GetItemGem(itemLink, i))
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

	if not delay then
		if unit == "player" then
			ilvl = select(2, GetAverageItemLevel())
		else
			if hasArtifact or twohand == 2 then
				local higher = max(weapon[1], weapon[2])
				total = total + higher * 2
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
			ilvl = ilvl .. " |cff00ccff(" .. boa .. HEIRLOOMS .. ")"
		end
		if sets > 0 then
			ilvl = ilvl .. formatSets[sets]
		end
	else
		ilvl = nil
	end

	return ilvl
end

function NE_SpecLevel:InspectUnit(unit, forced)
	local level

	if UnitIsUnit(unit, "player") then
		level = NE_SpecLevel:GetUnitItemLevel("player")
		NE_SpecLevel:SetupItemLevel(level)
	else
		if not unit or UnitGUID(unit) ~= currentGUID then
			return
		end
		if not UnitIsPlayer(unit) then
			return
		end

		local currentDB = cache[currentGUID]
		level = currentDB.level
		NE_SpecLevel:SetupItemLevel(level)

		if not NE_SpecLevel.db.profile.tooltip.SpecLevelByShift and IsShiftKeyDown() then
			forced = true
		end
		if level and not forced and (GetTime() - currentDB.getTime < resetTime) then
			updater.elapsed = frequency
			return
		end
		if not UnitIsVisible(unit) or UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then
			return
		end
		if InspectFrame and InspectFrame:IsShown() then
			return
		end

		NE_SpecLevel:SetupItemLevel()
		updater:Show()
	end
end

function NE_SpecLevel:InspectUnitItemLevel(unit)
	if NE_SpecLevel.db.profile.tooltip.SpecLevelByShift and not IsShiftKeyDown() then
		return
	end

	if not unit or not CanInspect(unit) then
		return
	end
	currentUNIT, currentGUID = unit, UnitGUID(unit)
	if not cache[currentGUID] then
		cache[currentGUID] = {}
	end

	NE_SpecLevel:InspectUnit(unit)
end
