--[[
	NexEnhance - Quick Quest
	-------------------------------------------------------------------------
	Automates the boring parts of questing: accepts quests (by frequency), turns
	them in (skipping costly ones), picks the most valuable reward, and walks
	single-option gossip. Hold the override key (default SHIFT) to suppress
	automation for that interaction, or flip it to require the key instead.

	Alt-click an NPC's name (quest or gossip) to toggle a per-character ignore
	for that NPC, so chatty/utility NPCs are left alone.

	Ported from NDui's Plugins/QuickQuest.lua (QuickQuest by p3lim, NDui MOD by
	siweia), adapted to the NexEnhance framework. All actions mirror what a
	player click would do, so this stays taint-safe.
--]]

-- luacheck: globals QuestInfoRewardsFrame QuestInfoItem_OnClick QuestFrame QuestNpcNameFrame GossipFrame GossipFrameCloseButton InteractiveWormholes
-- The Lua Language Server ships outdated quest API signatures (e.g. SelectActiveQuest
-- as 0-arg, non-optional questIDs); silence those false positives here.
---@diagnostic disable: param-type-mismatch, redundant-parameter
local _, ns = ...
local F, L = ns.F, ns.L

local next, ipairs, pairs, select = next, ipairs, pairs, select
local wipe, strfind, strupper = wipe, string.find, string.upper
local IsAltKeyDown, IsShiftKeyDown, IsControlKeyDown = IsAltKeyDown, IsShiftKeyDown, IsControlKeyDown
local UnitGUID, UnitIsDeadOrGhost = UnitGUID, UnitIsDeadOrGhost
local InCombatLockdown = InCombatLockdown
local QuestIsDaily, QuestIsWeekly = QuestIsDaily, QuestIsWeekly
local GetQuestMoneyToGet = GetQuestMoneyToGet
local GetItemInfoFromHyperlink, GetInstanceInfo, GetQuestID = GetItemInfoFromHyperlink, GetInstanceInfo, GetQuestID
local GetNumActiveQuests, GetActiveTitle, GetActiveQuestID, SelectActiveQuest = GetNumActiveQuests, GetActiveTitle, GetActiveQuestID, SelectActiveQuest
local IsQuestCompletable, GetNumQuestItems, GetQuestItemLink, QuestIsFromAreaTrigger = IsQuestCompletable, GetNumQuestItems, GetQuestItemLink, QuestIsFromAreaTrigger
local QuestGetAutoAccept, AcceptQuest, ConfirmAcceptQuest, CloseQuest, CompleteQuest, AcknowledgeAutoAcceptQuest = QuestGetAutoAccept, AcceptQuest, ConfirmAcceptQuest, CloseQuest, CompleteQuest, AcknowledgeAutoAcceptQuest
local GetNumQuestChoices, GetQuestReward, GetQuestItemInfo = GetNumQuestChoices, GetQuestReward, GetQuestItemInfo
local GetNumAvailableQuests, GetAvailableQuestInfo, GetAvailableLevel, SelectAvailableQuest = GetNumAvailableQuests, GetAvailableQuestInfo, GetAvailableLevel, SelectAvailableQuest
local GetNumAutoQuestPopUps, GetAutoQuestPopUp, ShowQuestOffer, ShowQuestComplete = GetNumAutoQuestPopUps, GetAutoQuestPopUp, ShowQuestOffer, ShowQuestComplete
local CreateFrame, StaticPopup_Hide, RemoveAutoQuestPopUp = CreateFrame, StaticPopup_Hide, RemoveAutoQuestPopUp
local C_QuestLog_IsWorldQuest = C_QuestLog.IsWorldQuest
local C_QuestLog_IsQuestTrivial = C_QuestLog.IsQuestTrivial
local C_QuestLog_GetQuestDifficultyLevel = C_QuestLog.GetQuestDifficultyLevel
local C_QuestLog_RequestLoadQuestByID = C_QuestLog.RequestLoadQuestByID
local C_QuestLog_GetQuestTagInfo = C_QuestLog.GetQuestTagInfo
local C_QuestLog_IsQuestFlaggedCompletedOnAccount = C_QuestLog.IsQuestFlaggedCompletedOnAccount
local C_GossipInfo_GetOptions = C_GossipInfo.GetOptions
local C_GossipInfo_SelectOption = C_GossipInfo.SelectOption
local C_GossipInfo_GetActiveQuests = C_GossipInfo.GetActiveQuests
local C_GossipInfo_SelectActiveQuest = C_GossipInfo.SelectActiveQuest
local C_GossipInfo_GetAvailableQuests = C_GossipInfo.GetAvailableQuests
local C_GossipInfo_GetNumActiveQuests = C_GossipInfo.GetNumActiveQuests
local C_GossipInfo_SelectAvailableQuest = C_GossipInfo.SelectAvailableQuest
local C_GossipInfo_GetNumAvailableQuests = C_GossipInfo.GetNumAvailableQuests
local C_Item_GetItemInfo = C_Item.GetItemInfo
local C_Minimap_IsFilteredOut = C_Minimap.IsFilteredOut
local C_Minimap_IsTrackingHiddenQuests = C_Minimap.IsTrackingHiddenQuests
local C_TooltipInfo_GetItemByID = C_TooltipInfo and C_TooltipInfo.GetItemByID
local C_PlayerInteractionManager_IsInteractingWithNpcOfType = C_PlayerInteractionManager.IsInteractingWithNpcOfType
local QuestLabelPrepend = Enum.GossipOptionRecFlags.QuestLabelPrepend
local FlagsUtil_IsSet = _G["FlagsUtil"] and _G["FlagsUtil"].IsSet
local AccountCompletedFilter = Enum.MinimapTrackingFilter.AccountCompletedQuests
local TaxiNodeInteraction = Enum.PlayerInteractionType.TaxiNode
local QF_Daily, QF_Weekly = Enum.QuestFrequency.Daily, Enum.QuestFrequency.Weekly
local MAX_REQUIRED_ITEMS = _G["MAX_REQUIRED_ITEMS"] or 8

-- Override-key choices for the options dropdown.
local OVERRIDE_SHIFT, OVERRIDE_ALT, OVERRIDE_CONTROL = 1, 2, 3

ns:RegisterDefaults({
	quickQuest = {
		enable = false,
		acceptRegular = true, -- auto-accept regular quests
		acceptDaily = true, -- auto-accept daily quests
		acceptWeekly = true, -- auto-accept weekly quests
		protectTurnIns = true, -- skip turn-ins that consume gold/currency/reagents/account-bound items
		overrideKey = OVERRIDE_SHIFT, -- which modifier pauses (or, with requireOverride, enables) automation
		requireOverride = false, -- false: holding the key pauses; true: holding the key is required to run
		blockInInstances = false, -- skip single-option gossip in raids/blacklisted instances
		autoSkipGossip = false, -- auto-click lone red "<Skip ...>" gossip (skip ahead / skip conversation)
		ignoreNPC = {}, -- [npcID] = true (ignore) / false (force-allow a built-in)
	},
})

local QuickQuest = ns:NewModule("QuickQuest", "quickQuest", { group = "automation", title = L["Quick Quest"], order = 20 })

local function db()
	return ns.db.quickQuest
end

-- ---------------------------------------------------------------------------
-- Override key: by default holding the chosen modifier PAUSES automation; with
-- requireOverride set, automation only runs WHILE the modifier is held.
-- ---------------------------------------------------------------------------
local function IsOverrideKeyDown()
	local key = db().overrideKey
	if key == OVERRIDE_ALT then return IsAltKeyDown() end
	if key == OVERRIDE_CONTROL then return IsControlKeyDown() end
	return IsShiftKeyDown()
end

local function Automating()
	if not db().enable then return false end
	local keyDown = IsOverrideKeyDown()
	if db().requireOverride then
		return keyDown
	end
	return not keyDown
end

-- ---------------------------------------------------------------------------
-- Event plumbing: each registered handler only runs when automation is active
-- (enabled + override-key state). Events are still feature-scoped, but they use
-- the addon-wide dispatcher instead of a private frame.
-- ---------------------------------------------------------------------------
local handlers = {}
local choiceQueue
local regenRetryRegistered = false
local regenRetryCallback

local function CancelRegenRetry()
	if not regenRetryRegistered then return end
	regenRetryRegistered = false
	ns:UnregisterEvent("PLAYER_REGEN_ENABLED", regenRetryCallback)
end

-- Events are collected here at load but only registered in the shared dispatcher
-- while the module is enabled (see SetEventsActive). Quick Quest defaults to OFF, so
-- without this gate it would keep waking on QUEST_LOG_UPDATE etc. for users who
-- never turn it on. (Plumber idiom: feature-scoped event registration.)
local registeredEvents = {}

local function Register(event, func)
	handlers[event] = func
	local callback = function(_, ...)
		if Automating() then
			func(...)
		end
	end
	registeredEvents[#registeredEvents + 1] = { event, callback }
end

local eventsActive = false
local function SetEventsActive(state)
	if state then
		if eventsActive then return end
		eventsActive = true
		for i = 1, #registeredEvents do
			local entry = registeredEvents[i]
			ns:RegisterEvent(entry[1], entry[2])
		end
	elseif eventsActive then
		eventsActive = false
		-- Clears the gated events plus any transient PLAYER_REGEN_ENABLED retry.
		for i = 1, #registeredEvents do
			local entry = registeredEvents[i]
			ns:UnregisterEvent(entry[1], entry[2])
		end
		CancelRegenRetry()
	end
end

local function GetNPCID()
	return F.GetNPCID(UnitGUID("npc"))
end

local function IsAccountCompleted(questID)
	return C_Minimap_IsFilteredOut(AccountCompletedFilter) and C_QuestLog_IsQuestFlaggedCompletedOnAccount(questID)
end

-- Blizzard can surface gossip/quest-list entries before the quest record is
-- cached. If we decide from uncached data, the trivial/repeatable flags can be
-- wrong, so retry the same handler once QUEST_DATA_LOAD_RESULT arrives.
local questDataQueue = {}

local function WaitForQuestData(questID, callback)
	if not (questID and C_QuestLog_RequestLoadQuestByID) then return false end
	questDataQueue[questID] = callback
	C_QuestLog_RequestLoadQuestByID(questID)
	return true
end

Register("QUEST_DATA_LOAD_RESULT", function(questID, success)
	local callback = questDataQueue[questID]
	if not callback then return end
	questDataQueue[questID] = nil
	if success ~= false then
		callback()
	end
end)

-- ---------------------------------------------------------------------------
-- Ignore list (built-in NPCs + per-character overrides)
-- ---------------------------------------------------------------------------
local ignoreQuestNPC = {
	[88570] = true,   -- Fate-Twister Tiklal
	[87391] = true,   -- Fate-Twister Seress
	[111243] = true,  -- Archmage Lan'dalock
	[108868] = true,  -- Hunter's order hall
	[101462] = true,  -- Reaves
	[43929] = true,   -- 4000
	[14847] = true,   -- DarkMoon
	[119388] = true,  -- Chieftain Hatuun
	[114719] = true,  -- Merchant Selina
	[121263] = true,  -- Grand Artificer Romuul
	[126954] = true,  -- Turalyon
	[124312] = true,  -- Turalyon
	[103792] = true,  -- Griftah
	[101880] = true,  -- Tech-Tock
	[141584] = true,  -- Zul'wen
	[142063] = true,  -- Tzane
	[143388] = true,  -- Druza
	[98489] = true,   -- Shipwreck Captive
	[135690] = true,  -- Undead Captain
	[105387] = true,  -- Andus
	[93538] = true,   -- Darethy
	[154534] = true,  -- Chang the Camp Cook
	[150987] = true,  -- Sean Wilkers, Stratholme
	[150563] = true,  -- Sparkit, Mechagon daily
	[143555] = true,  -- Shandai Silverman, Zuldazar PvP QM
	[168430] = true,  -- Disciplinarian Fane, Bastion challenge
	[160248] = true,  -- Archivist Fane, Sinstone shards
	[127037] = true,  -- Nabiru
	[326027] = true,  -- Reclamation Rig DX-82
	[162804] = true,  -- Vinaly
	[195935] = true,  -- Taveouo, walrus fishing item
}

local ignoreList = {}

local function UpdateIgnoreList()
	wipe(ignoreList)

	for npcID in pairs(ignoreQuestNPC) do
		ignoreList[npcID] = true
	end

	for npcID, value in pairs(db().ignoreNPC) do
		if value and ignoreQuestNPC[npcID] then
			db().ignoreNPC[npcID] = nil -- redundant override; drop it
		else
			ignoreList[npcID] = value
		end
	end
end

-- ---------------------------------------------------------------------------
-- Action-specific blocklists
--   blockQuestID         - quests never auto-selected/accepted (consequences,
--                          or quests that gather items the moment you accept).
--   selectOnlyIgnoreNPC  - NPCs whose available quests we leave for the player
--                          to pick up manually, while still auto-turning-in.
-- ---------------------------------------------------------------------------
local blockQuestID = {
	[43923] = true, -- Get Your Own! (Starlight Rose)
	[43924] = true, -- Get Your Own! (Leyblood)
	[43925] = true, -- Get Your Own! (Runescale Koi)
	[71162] = true, -- Dragon Isles waygate
	[71165] = true, -- Dragon Isles waygate
}

local selectOnlyIgnoreNPC = {
	[87706] = true, -- Gazmolf Futzwangler (Ashran)
	[70022] = true, -- Ku'ma (Timeless Isle)
	[12944] = true, -- Lokhtos Darkbargainer (Thorium Brotherhood)
	[87393] = true, -- Sallee Silverclamp (Stormshield)
	[10307] = true, -- Witch Doctor Mau'ari (Hatecrest)
}

-- ---------------------------------------------------------------------------
-- Quest frequency gating (regular / daily / weekly accept toggles)
-- ---------------------------------------------------------------------------
local function FrequencyAllowed(frequency)
	local cfg = db()
	if frequency == QF_Daily then return cfg.acceptDaily end
	if frequency == QF_Weekly then return cfg.acceptWeekly end
	return cfg.acceptRegular
end

-- QUEST_DETAIL has no frequency field, so fall back to the quest-frame globals.
local function DetailFrequencyAllowed()
	local cfg = db()
	if QuestIsDaily and QuestIsDaily() then return cfg.acceptDaily end
	if QuestIsWeekly and QuestIsWeekly() then return cfg.acceptWeekly end
	return cfg.acceptRegular
end

-- ---------------------------------------------------------------------------
-- Costly turn-in protection: never auto-complete a quest that consumes gold,
-- currency, crafting reagents, or account-bound items (Leatrix Plus parity).
-- ---------------------------------------------------------------------------
local accountBoundLines = {}
do
	local labels = { ITEM_BNETACCOUNTBOUND, ITEM_BIND_TO_BNETACCOUNT, ITEM_BIND_TO_ACCOUNT, ITEM_ACCOUNTBOUND }
	for i = 1, 4 do
		if labels[i] then accountBoundLines[labels[i]] = true end
	end
end

local function IsCraftingReagent(itemID)
	return select(17, C_Item_GetItemInfo(itemID)) and true or false
end

local function IsItemAccountBound(itemID)
	if not C_TooltipInfo_GetItemByID then return false end
	local data = C_TooltipInfo_GetItemByID(itemID)
	local lines = data and data.lines
	if not lines then return false end
	for i = 1, #lines do
		local line = lines[i]
		if line and line.leftText and accountBoundLines[line.leftText] then
			return true
		end
	end
	return false
end

-- Reads the QUEST_PROGRESS frame; only meaningful while that stage is shown.
local function TurnInHasCost()
	if not db().protectTurnIns then return false end

	if GetQuestMoneyToGet and (GetQuestMoneyToGet() or 0) > 0 then return true end

	for i = 1, MAX_REQUIRED_ITEMS do
		local item = _G["QuestProgressItem" .. i]
		if item and item:IsShown() and item.type == "required" then
			if item.objectType == "currency" then
				return true
			elseif item.objectType == "item" then
				local itemID = select(6, GetQuestItemInfo("required", i))
				if itemID and (IsCraftingReagent(itemID) or IsItemAccountBound(itemID)) then
					return true
				end
			end
		end
	end

	return false
end

-- ---------------------------------------------------------------------------
-- Quest / gossip automation
-- ---------------------------------------------------------------------------
Register("QUEST_GREETING", function()
	local npcID = GetNPCID()
	if ignoreList[npcID] then return end

	local active = GetNumActiveQuests()
	if active > 0 then
		for index = 1, active do
			local _, isComplete = GetActiveTitle(index)
			local questID = GetActiveQuestID(index)
			if isComplete and not C_QuestLog_IsWorldQuest(questID) then
				SelectActiveQuest(index)
			end
		end
	end

	local available = GetNumAvailableQuests()
	if available > 0 and not selectOnlyIgnoreNPC[npcID] then
		for index = 1, available do
			local isTrivial, frequency, _, _, questID = GetAvailableQuestInfo(index)
			local questLevel = GetAvailableLevel and GetAvailableLevel(index)
			if questID and (not questLevel or questLevel == 0) then
				WaitForQuestData(questID, handlers.QUEST_GREETING)
			elseif not blockQuestID[questID] and not IsAccountCompleted(questID) and FrequencyAllowed(frequency) and (not isTrivial or C_Minimap_IsTrackingHiddenQuests()) then
				SelectAvailableQuest(index)
			end
		end
	end
end)

local ignoreGossipNPC = {
	-- Bodyguards
	[86945] = true, -- Aeda Brightdawn (Horde)
	[86933] = true, -- Vivianne (Horde)
	[86927] = true, -- Delvar Ironfist (Alliance)
	[86934] = true, -- Defender Illona (Alliance)
	[86682] = true, -- Tormmok
	[86964] = true, -- Leorajh
	[86946] = true, -- Talonpriest Ishaal
	-- Sassy Imps
	[95139] = true, [95141] = true, [95142] = true, [95143] = true, [95144] = true,
	[95145] = true, [95146] = true, [95200] = true, [95201] = true,
	-- Misc NPCs
	[79740] = true,  -- Warmaster Zog (Horde)
	[79953] = true,  -- Lieutenant Thorn (Alliance)
	[84268] = true,  -- Lieutenant Thorn (Alliance)
	[84511] = true,  -- Lieutenant Thorn (Alliance)
	[84684] = true,  -- Lieutenant Thorn (Alliance)
	[117871] = true, -- War Councilor Victoria (Class Challenges @ Broken Shore)
	[155101] = true, -- Elemental Essence Fuser
	[155261] = true, -- Sean Wilkers, Stratholme
	[150122] = true, -- Honor Hold Mage
	[150131] = true, -- Thrallmar Mage
	[173021] = true, -- Rune-Etched Tauren
	[171589] = true, -- General Draven
	[171787] = true, -- Adjutant Adrestes
	[171795] = true, -- Lady Moonberry
	[171821] = true, -- Baroness Draka
	[172558] = true, -- Mentor Ella
	[172572] = true, -- Mentor Celestine of the Harvest
	[175513] = true, -- Nathria Inquisitor (Pride)
	[165196] = true, -- Ember Court, Sika
	[180458] = true, -- Ember Court, Court vision
	[182681] = true, -- Zereth Mortis, Empowered console
	[183262] = true, -- Zereth Mortis, Echo of Genesis
	[184587] = true, -- Bazaar, Ta'phix
}

local autoSelectFirstOptionList = {
	[97004] = true,  -- "Red" Jack Findle, Rogue ClassHall
	[96782] = true,  -- Lucian Trias, Rogue ClassHall
	[93188] = true,  -- Mongar, Rogue ClassHall
	[107486] = true, -- Stellagosa
	[167839] = true, -- Soul Remnant, Torghast
}

-- Newer retail quest/task gossip options that are not always flagged like normal
-- quests. Sourced from p3lim's QuickQuest data and kept option-ID based so we
-- don't accidentally match unrelated NPC text.
local questGossipOptions = {
	[109275] = true, -- Soridormi - begin time rift
	[120619] = true, -- Big Dig task
	[120620] = true, -- Big Dig task
	[120555] = true, -- Awakening The Machine
	[120733] = true, -- Theater Troupe

	-- Darkmoon Faire games / returns
	[40563] = true, -- Whack-a-Gnoll
	[28701] = true, -- Cannon
	[31202] = true, -- Shooting gallery
	[39245] = true, -- Tonk
	[40224] = true, -- Ring toss
	[43060] = true, -- Firebird
	[52651] = true, -- Dance
	[41759] = true, -- Pet battle 1
	[42668] = true, -- Pet battle 2
	[40872] = true, -- Cannon return
}

local ignoreGossipOptions = {
	[122442] = true, -- Leave the dungeon in Remix
	[44733] = true,  -- Teleport
	[125350] = true, -- Siren Isle teleport
	[125351] = true, -- Siren Isle teleport
	[131324] = true, -- Winter Veil Hillsbrad teleport
	[131325] = true, -- Winter Veil Hillsbrad teleport
}

local ignoreInstances = {
	[1571] = true, -- Court of Stars
	[1626] = true, -- Suramar withered training
}

local QUEST_STRING = "cFF0000FF.-" .. TRANSMOG_SOURCE_2
local SKIP_GOSSIP_PREFIX, SKIP_GOSSIP_PREFIX_UPPER = "|cFFFF0000<", "|CFFFF0000<"

local function IsQuestLabelPrepend(flags)
	if not flags then return false end
	if FlagsUtil_IsSet then
		return FlagsUtil_IsSet(flags, QuestLabelPrepend)
	end
	return flags == QuestLabelPrepend
end

-- Gossip options that carry their own colour code or angle-bracket markup are
-- usually "special" (teleports, skip-ahead, choices with consequences). When a
-- lone option looks special, leave the single-option walk to the player. The
-- purple quest colour (FF0008E8) is whitelisted because it marks normal quests.
local function HasUnsafeGossipOption(options)
	for i = 1, #options do
		local name = options[i] and options[i].name
		if name then
			local upper = strupper(name)
			if (strfind(upper, "|C") or strfind(upper, "<")) and not strfind(upper, "FF0008E8") then
				return true
			end
		end
	end
	return false
end

Register("GOSSIP_SHOW", function()
	local npcID = GetNPCID()
	if ignoreList[npcID] then return end
	if C_PlayerInteractionManager_IsInteractingWithNpcOfType and C_PlayerInteractionManager_IsInteractingWithNpcOfType(TaxiNodeInteraction) then return end
	local wormholes = _G["InteractiveWormholes"]
	if wormholes and wormholes.IsActive and wormholes:IsActive() then return end

	local active = C_GossipInfo_GetNumActiveQuests()
	if active > 0 then
		for _, questInfo in ipairs(C_GossipInfo_GetActiveQuests()) do
			local questID = questInfo.questID
			local isWorldQuest = questID and C_QuestLog_IsWorldQuest(questID)
			local questLevel = questID and C_QuestLog_GetQuestDifficultyLevel and C_QuestLog_GetQuestDifficultyLevel(questID)
			if questID and (not questLevel or questLevel == 0) then
				WaitForQuestData(questID, handlers.GOSSIP_SHOW)
			elseif questInfo.isComplete and not isWorldQuest then
				C_GossipInfo_SelectActiveQuest(questID)
			end
		end
	end

	local available = C_GossipInfo_GetNumAvailableQuests()
	if available > 0 and not selectOnlyIgnoreNPC[npcID] then
		for _, questInfo in ipairs(C_GossipInfo_GetAvailableQuests()) do
			local trivial = questInfo.isTrivial
			local questID = questInfo.questID
			local questLevel = questID and C_QuestLog_GetQuestDifficultyLevel and C_QuestLog_GetQuestDifficultyLevel(questID)
			if questID == 82449 then
				-- "The Call of the Worldsoul" behaves like a repeatable selector
				-- quest, but the quest APIs don't reliably classify it that way.
				C_GossipInfo_SelectAvailableQuest(questID)
			elseif questID and (not questLevel or questLevel == 0) then
				WaitForQuestData(questID, handlers.GOSSIP_SHOW)
			elseif not blockQuestID[questID] and not IsAccountCompleted(questID) and FrequencyAllowed(questInfo.frequency) and (not trivial or C_Minimap_IsTrackingHiddenQuests() or (trivial and npcID == 64337)) then
				C_GossipInfo_SelectAvailableQuest(questInfo.questID)
			end
		end
	end

	local gossipInfoTable = C_GossipInfo_GetOptions()
	if not gossipInfoTable then return end

	local numOptions = #gossipInfoTable
	local firstOptionID = gossipInfoTable[1] and gossipInfoTable[1].gossipOptionID

	if firstOptionID then
		if autoSelectFirstOptionList[npcID] then
			return C_GossipInfo_SelectOption(firstOptionID)
		end

		if available == 0 and active == 0 and numOptions == 1 and not ignoreGossipNPC[npcID] and not HasUnsafeGossipOption(gossipInfoTable) then
			if ignoreGossipOptions[firstOptionID] then return end
			local allow = true
			-- Optional safety: skip the single-option walk inside raids and the
			-- blacklisted instances. Off by default, so it auto-walks everywhere.
			if db().blockInInstances then
				local _, instance, _, _, _, _, _, mapID = GetInstanceInfo()
				if instance == "raid" or ignoreInstances[mapID] then
					allow = false
				end
			end
			if allow then
				return C_GossipInfo_SelectOption(firstOptionID)
			end
		end
	end

	-- One pass to find quest-flagged gossip options and red "<Skip ...>" options.
	-- Blizzard colours skip choices red with an angle-bracket prefix
	-- (|cFFFF0000<...>): both the campaign "skip ahead" walks and the per-NPC
	-- "<Skip conversation>" branches. These usually ALSO carry the quest prepend
	-- flag (so they show the (Quest) icon next to a normal "listen/continue"
	-- option), so the skip is tracked separately rather than in the quest bucket.
	local numQuestGossips, numSkipGossips = 0, 0
	local questGossipID, skipGossipID
	for i = 1, numOptions do
		local option = gossipInfoTable[i]
		local name = option.name
		if name then
			if strfind(name, SKIP_GOSSIP_PREFIX, 1, true) == 1 or strfind(name, SKIP_GOSSIP_PREFIX_UPPER, 1, true) == 1 then
				numSkipGossips = numSkipGossips + 1
				skipGossipID = option.gossipOptionID
			end
			if questGossipOptions[option.gossipOptionID] or strfind(name, QUEST_STRING) or IsQuestLabelPrepend(option.flags) then
				numQuestGossips = numQuestGossips + 1
				questGossipID = option.gossipOptionID
			end
		end
	end

	-- Opt-in: when there is exactly one red "<Skip ...>" option, prefer it over the
	-- listen/continue branch so alts can blow past story/campaign dialogue. Off by
	-- default so it never silently bypasses dialogue you wanted to read. Checked
	-- before the quest-gossip auto-select so it wins when both are present.
	if db().autoSkipGossip and numSkipGossips == 1 and not ignoreGossipOptions[skipGossipID] then
		return C_GossipInfo_SelectOption(skipGossipID)
	end

	-- Auto-select when there is exactly one quest-flagged gossip option.
	if numQuestGossips == 1 then
		return C_GossipInfo_SelectOption(questGossipID)
	end
end)

local skipConfirmNPCs = {
	[57850] = true, -- Teleportologist Fozlebub
	[55382] = true, -- Darkmoon Faire Mystic Mage (Horde)
	[54334] = true, -- Darkmoon Faire Mystic Mage (Alliance)
}

Register("GOSSIP_CONFIRM", function(index)
	if skipConfirmNPCs[GetNPCID()] then
		C_GossipInfo_SelectOption(index, "", true)
		StaticPopup_Hide("GOSSIP_CONFIRM")
	end
end)

Register("QUEST_DETAIL", function()
	local questID = GetQuestID()
	if not questID or questID == 0 then return end

	local questLevel = C_QuestLog_GetQuestDifficultyLevel and C_QuestLog_GetQuestDifficultyLevel(questID)
	if not questLevel or questLevel == 0 then
		WaitForQuestData(questID, handlers.QUEST_DETAIL)
		return
	end

	if QuestIsFromAreaTrigger() then
		AcceptQuest()
	elseif QuestGetAutoAccept() then
		AcknowledgeAutoAcceptQuest()
		RemoveAutoQuestPopUp(questID)
	elseif not C_QuestLog_IsQuestTrivial(questID) or C_Minimap_IsTrackingHiddenQuests() then
		if ignoreList[GetNPCID()] then return end
		if blockQuestID[questID] then return end
		if not DetailFrequencyAllowed() then return end
		AcceptQuest()
	end
end)

Register("QUEST_ACCEPT_CONFIRM", function()
	if ConfirmAcceptQuest then
		ConfirmAcceptQuest()
	else
		AcceptQuest()
	end
end)

Register("QUEST_ACCEPTED", function()
	if QuestFrame:IsShown() and QuestGetAutoAccept() then
		CloseQuest()
	end
end)

Register("QUEST_ITEM_UPDATE", function()
	if choiceQueue and handlers[choiceQueue] then
		handlers[choiceQueue]()
	end
end)

local itemBlacklist = {
	-- Inscription weapons
	[31690] = 79343, [31691] = 79340, [31692] = 79341,
	-- Darkmoon Faire artifacts
	[29443] = 71635, [29444] = 71636, [29445] = 71637, [29446] = 71638,
	[29451] = 71715, [29456] = 71951, [29457] = 71952, [29458] = 71953, [29464] = 71716,
	-- Tiller gifts
	["progress_79264"] = 79264, ["progress_79265"] = 79265, ["progress_79266"] = 79266,
	["progress_79267"] = 79267, ["progress_79268"] = 79268,
	-- Garrison scouting missives
	["38180"] = 122424, ["38193"] = 122423, ["38182"] = 122418, ["38196"] = 122417,
	["38179"] = 122400, ["38192"] = 122404, ["38194"] = 122420, ["38202"] = 122419,
	["38178"] = 122402, ["38191"] = 122406, ["38184"] = 122413, ["38198"] = 122414,
	["38177"] = 122403, ["38190"] = 122399, ["38181"] = 122421, ["38195"] = 122422,
	["38185"] = 122411, ["38199"] = 122409, ["38187"] = 122412, ["38201"] = 122410,
	["38186"] = 122408, ["38200"] = 122407, ["38183"] = 122416, ["38197"] = 122415,
	["38176"] = 122405, ["38189"] = 122401,
	-- Misc
	[31664] = 88604, -- Nat's Fishing Journal
}

Register("QUEST_PROGRESS", function()
	if IsQuestCompletable() then
		local info = C_QuestLog_GetQuestTagInfo(GetQuestID())
		if info and (info.tagID == 153 or info.worldQuestType) then return end

		local npcID = GetNPCID()
		if ignoreList[npcID] then return end

		local requiredItems = GetNumQuestItems()
		if requiredItems > 0 then
			for index = 1, requiredItems do
				local link = GetQuestItemLink("required", index)
				if link then
					local id = GetItemInfoFromHyperlink(link)
					for _, itemID in next, itemBlacklist do
						if itemID == id then
							CloseQuest()
							return
						end
					end
				else
					choiceQueue = "QUEST_PROGRESS"
					GetQuestItemInfo("required", index)
					return
				end
			end
		end

		if TurnInHasCost() then return end

		CompleteQuest()
	end
end)

local cashRewards = {
	[45724] = 1e5, -- Champion's Purse
	[64491] = 2e6, -- Royal Reward
	-- Sixtrigger brothers chain (Stormheim)
	[138127] = 15, [138129] = 11, [138131] = 24, [138123] = 15, [138125] = 16, [138133] = 27,
}

Register("QUEST_COMPLETE", function()
	-- Blingtron 6000 only!
	local npcID = GetNPCID()
	if npcID == 43929 or npcID == 77789 then return end

	-- Guard against any quest that still wants gold to hand in at this stage.
	if db().protectTurnIns and GetQuestMoneyToGet and (GetQuestMoneyToGet() or 0) > 0 then return end

	local choices = GetNumQuestChoices()
	if choices <= 1 then
		GetQuestReward(1)
	elseif choices > 1 then
		local bestValue, bestIndex = 0, nil

		for index = 1, choices do
			local link = GetQuestItemLink("choice", index)
			if link then
				local value = select(11, C_Item_GetItemInfo(link))
				local itemID = GetItemInfoFromHyperlink(link)
				value = cashRewards[itemID] or value

				if value and value > bestValue then
					bestValue, bestIndex = value, index
				end
			else
				choiceQueue = "QUEST_COMPLETE"
				return GetQuestItemInfo("choice", index)
			end
		end

		local button = bestIndex and QuestInfoRewardsFrame.RewardButtons[bestIndex]
		if button then
			QuestInfoItem_OnClick(button)
		end
	end
end)

local function RegisterRegenRetry()
	if regenRetryRegistered then return end
	regenRetryRegistered = true
	ns:RegisterEvent("PLAYER_REGEN_ENABLED", regenRetryCallback)
end

local function AttemptAutoComplete()
	local numPopUps = GetNumAutoQuestPopUps()
	if numPopUps == 0 then return end

	-- Avoid stomping the map/quest UI while the player is already interacting
	-- with it (p3lim/QuickQuest#45).
	local WorldMapFrame = _G["WorldMapFrame"]
	if (WorldMapFrame and WorldMapFrame:IsShown()) or (QuestFrame and QuestFrame:IsShown()) then
		return
	end

	-- Auto-quest popups taint while dead/in combat; retry once it lifts.
	if UnitIsDeadOrGhost("player") or InCombatLockdown() then
		RegisterRegenRetry()
		return
	end

	for index = 1, numPopUps do
		local questID, popUpType = GetAutoQuestPopUp(index)
		if questID then
			local questLevel = C_QuestLog_GetQuestDifficultyLevel and C_QuestLog_GetQuestDifficultyLevel(questID)
			if not questLevel or questLevel == 0 then
				WaitForQuestData(questID, AttemptAutoComplete)
			elseif not C_QuestLog_IsWorldQuest(questID) then
				if popUpType == "OFFER" then
					ShowQuestOffer(questID)
				elseif popUpType == "COMPLETE" then
					ShowQuestComplete(questID)
				end
				RemoveAutoQuestPopUp(questID)
			end
		end
	end
end
Register("QUEST_LOG_UPDATE", AttemptAutoComplete)

-- Dedicated, self-unregistering combat retry for auto-quest popups.
regenRetryCallback = function()
	CancelRegenRetry()
	if Automating() then
		AttemptAutoComplete()
	end
end

-- ---------------------------------------------------------------------------
-- Per-NPC ignore toggle (Alt-click the NPC name marker)
-- ---------------------------------------------------------------------------
local function AddHint(frame, text)
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

local function UnitQuickQuestStatus(self)
	if not self.__ignore then
		local frame = CreateFrame("Frame", nil, self)
		frame:SetSize(100, 14)
		frame:SetPoint("TOP", self, "BOTTOM", 0, -2)
		AddHint(frame, L["Alt-click to toggle Quick Quest for this NPC."])
		F.CreateFS(frame, 14, IGNORED):SetTextColor(1, 0, 0)
		self.__ignore = frame
		UpdateIgnoreList()
	end

	local npcID = GetNPCID()
	local isIgnored = db().enable and npcID and ignoreList[npcID]
	self.__ignore:SetShown(isIgnored and true or false)
end

local function ToggleQuickQuestStatus(self)
	if not self.__ignore then return end
	if not db().enable then return end
	if not IsAltKeyDown() then return end

	self.__ignore:SetShown(not self.__ignore:IsShown())
	local npcID = GetNPCID()
	if not npcID then return end

	if self.__ignore:IsShown() then
		if ignoreQuestNPC[npcID] then
			db().ignoreNPC[npcID] = nil
		else
			db().ignoreNPC[npcID] = true
		end
	else
		if ignoreQuestNPC[npcID] then
			db().ignoreNPC[npcID] = false
		else
			db().ignoreNPC[npcID] = nil
		end
	end

	UpdateIgnoreList()
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function QuickQuest:OnInitialize()
	UpdateIgnoreList()

	if QuestNpcNameFrame then
		QuestNpcNameFrame:HookScript("OnShow", UnitQuickQuestStatus)
		QuestNpcNameFrame:HookScript("OnMouseDown", ToggleQuickQuestStatus)
	end

	local titleContainer = GossipFrame and GossipFrame.TitleContainer
	if titleContainer then
		if GossipFrameCloseButton then
			-- Keep the close button clickable above the (mouse-enabled) title.
			GossipFrameCloseButton:SetFrameLevel(titleContainer:GetFrameLevel() + 1)
		end
		titleContainer:HookScript("OnShow", UnitQuickQuestStatus)
		titleContainer:HookScript("OnMouseDown", ToggleQuickQuestStatus)
	end
end

-- OnEnable only fires for modules enabled at login; combined with the live
-- toggle below this keeps the quest events bound exactly while the feature is on.
function QuickQuest:OnEnable()
	SetEventsActive(db().enable)
end

function QuickQuest:OnSettingChanged(key, value)
	if key == "enable" then
		SetEventsActive(value)
	end
end

function QuickQuest:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Quick Quest"], L["Automatically accept and turn in quests; hold the override key to pause. Alt-click an NPC name to ignore it."])
	local _, regularInit = builder:Checkbox(category, self, "acceptRegular", L["Accept Regular Quests"], L["Automatically accept regular (one-time) quests."])
	local _, dailyInit = builder:Checkbox(category, self, "acceptDaily", L["Accept Daily Quests"], L["Automatically accept daily quests."])
	local _, weeklyInit = builder:Checkbox(category, self, "acceptWeekly", L["Accept Weekly Quests"], L["Automatically accept weekly quests."])
	local _, protectInit = builder:Checkbox(category, self, "protectTurnIns", L["Protect Costly Turn-Ins"], L["Skip turn-ins that would consume gold, currency, crafting reagents, or account-bound items."])
	local _, requireInit = builder:Checkbox(category, self, "requireOverride", L["Require Override Key"], L["Only automate while the override key is held, instead of using it to pause."])
	local _, blockInit = builder:Checkbox(category, self, "blockInInstances", L["Block in Raids & Instances"], L["Skip single-option gossip auto-selection while in raids and certain instances."])
	local _, skipInit = builder:Checkbox(category, self, "autoSkipGossip", L["Auto-Skip Story Gossip"], L["Automatically click red \"<Skip ...>\" gossip options (skip ahead in a campaign, skip a conversation) when exactly one is offered. Handy on alts; off by default so you never miss dialogue you want to read."])

	local _, keyInit = builder:Dropdown(category, self, "overrideKey", L["Override Key"], L["The modifier that pauses (or, with Require Override Key, enables) automation."], {
		{ value = OVERRIDE_SHIFT, label = L["SHIFT"] },
		{ value = OVERRIDE_ALT, label = L["ALT"] },
		{ value = OVERRIDE_CONTROL, label = L["CONTROL"] },
	})

	-- Grey out every dependent option while Quick Quest is disabled.
	builder:DependsOn(regularInit, enableInit)
	builder:DependsOn(dailyInit, enableInit)
	builder:DependsOn(weeklyInit, enableInit)
	builder:DependsOn(protectInit, enableInit)
	builder:DependsOn(requireInit, enableInit)
	builder:DependsOn(blockInit, enableInit)
	builder:DependsOn(skipInit, enableInit)
	if keyInit then
		builder:DependsOn(keyInit, enableInit)
	end
end
