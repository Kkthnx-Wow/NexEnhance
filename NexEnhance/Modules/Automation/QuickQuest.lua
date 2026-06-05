--[[
	NexEnhance - Quick Quest
	-------------------------------------------------------------------------
	Automates the boring parts of questing: accepts quests, turns them in,
	picks the most valuable reward, and walks single-option gossip. Hold SHIFT
	at any time to suppress automation for that interaction.

	Alt-click an NPC's name (quest or gossip) to toggle a per-character ignore
	for that NPC, so chatty/utility NPCs are left alone.

	Ported from NDui's Plugins/QuickQuest.lua (QuickQuest by p3lim, NDui MOD by
	siweia), adapted to the NexEnhance framework. All actions mirror what a
	player click would do, so this stays taint-safe.
--]]

-- luacheck: globals QuestInfoRewardsFrame QuestInfoItem_OnClick QuestFrame QuestNpcNameFrame GossipFrame GossipFrameCloseButton
-- The Lua Language Server ships outdated quest API signatures (e.g. SelectActiveQuest
-- as 0-arg, non-optional questIDs); silence those false positives here.
---@diagnostic disable: param-type-mismatch, redundant-parameter
local _, ns = ...
local F, L = ns.F, ns.L

local next, ipairs, pairs, select = next, ipairs, pairs, select
local wipe, strfind = wipe, string.find
local IsAltKeyDown, IsShiftKeyDown = IsAltKeyDown, IsShiftKeyDown
local UnitGUID, UnitIsDeadOrGhost = UnitGUID, UnitIsDeadOrGhost
local InCombatLockdown = InCombatLockdown
local GetItemInfoFromHyperlink, GetInstanceInfo, GetQuestID = GetItemInfoFromHyperlink, GetInstanceInfo, GetQuestID
local GetNumActiveQuests, GetActiveTitle, GetActiveQuestID, SelectActiveQuest = GetNumActiveQuests, GetActiveTitle, GetActiveQuestID, SelectActiveQuest
local IsQuestCompletable, GetNumQuestItems, GetQuestItemLink, QuestIsFromAreaTrigger = IsQuestCompletable, GetNumQuestItems, GetQuestItemLink, QuestIsFromAreaTrigger
local QuestGetAutoAccept, AcceptQuest, CloseQuest, CompleteQuest, AcknowledgeAutoAcceptQuest = QuestGetAutoAccept, AcceptQuest, CloseQuest, CompleteQuest, AcknowledgeAutoAcceptQuest
local GetNumQuestChoices, GetQuestReward, GetQuestItemInfo = GetNumQuestChoices, GetQuestReward, GetQuestItemInfo
local GetNumAvailableQuests, GetAvailableQuestInfo, SelectAvailableQuest = GetNumAvailableQuests, GetAvailableQuestInfo, SelectAvailableQuest
local GetNumAutoQuestPopUps, GetAutoQuestPopUp, ShowQuestOffer, ShowQuestComplete = GetNumAutoQuestPopUps, GetAutoQuestPopUp, ShowQuestOffer, ShowQuestComplete
local CreateFrame, StaticPopup_Hide, RemoveAutoQuestPopUp = CreateFrame, StaticPopup_Hide, RemoveAutoQuestPopUp
local C_QuestLog_IsWorldQuest = C_QuestLog.IsWorldQuest
local C_QuestLog_IsQuestTrivial = C_QuestLog.IsQuestTrivial
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
local QuestLabelPrepend = Enum.GossipOptionRecFlags.QuestLabelPrepend
local AccountCompletedFilter = Enum.MinimapTrackingFilter.AccountCompletedQuests

ns:RegisterDefaults({
	quickQuest = {
		enable = false,
		ignoreNPC = {}, -- [npcID] = true (ignore) / false (force-allow a built-in)
	},
})

local QuickQuest = ns:NewModule("QuickQuest", "quickQuest", { group = "automation", title = L["Quick Quest"], order = 20 })

local function db()
	return ns.db.quickQuest
end

-- ---------------------------------------------------------------------------
-- Event plumbing: each registered handler only runs when enabled and SHIFT is
-- not held. A private frame keeps the choiceQueue / combat re-queue self-contained.
-- ---------------------------------------------------------------------------
local qqFrame = CreateFrame("Frame")
qqFrame:SetScript("OnEvent", function(self, event, ...)
	local fn = self[event]
	if fn then fn(...) end
end)

local handlers = {}
local choiceQueue

local function Register(event, func)
	handlers[event] = func
	qqFrame[event] = function(...)
		if db().enable and not IsShiftKeyDown() then
			func(...)
		end
	end
	qqFrame:RegisterEvent(event)
end

local function GetNPCID()
	return F.GetNPCID(UnitGUID("npc"))
end

local function IsAccountCompleted(questID)
	return C_Minimap_IsFilteredOut(AccountCompletedFilter) and C_QuestLog_IsQuestFlaggedCompletedOnAccount(questID)
end

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
	if available > 0 then
		for index = 1, available do
			local isTrivial, _, _, _, questID = GetAvailableQuestInfo(index)
			if not IsAccountCompleted(questID) and (not isTrivial or C_Minimap_IsTrackingHiddenQuests()) then
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

local ignoreInstances = {
	[1571] = true, -- Court of Stars
	[1626] = true, -- Suramar withered training
}

local QUEST_STRING = "cFF0000FF.-" .. TRANSMOG_SOURCE_2

Register("GOSSIP_SHOW", function()
	local npcID = GetNPCID()
	if ignoreList[npcID] then return end

	local active = C_GossipInfo_GetNumActiveQuests()
	if active > 0 then
		for _, questInfo in ipairs(C_GossipInfo_GetActiveQuests()) do
			local questID = questInfo.questID
			local isWorldQuest = questID and C_QuestLog_IsWorldQuest(questID)
			if questInfo.isComplete and not isWorldQuest then
				C_GossipInfo_SelectActiveQuest(questID)
			end
		end
	end

	local available = C_GossipInfo_GetNumAvailableQuests()
	if available > 0 then
		for _, questInfo in ipairs(C_GossipInfo_GetAvailableQuests()) do
			local trivial = questInfo.isTrivial
			local questID = questInfo.questID
			if not IsAccountCompleted(questID) and (not trivial or C_Minimap_IsTrackingHiddenQuests() or (trivial and npcID == 64337)) then
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

		if available == 0 and active == 0 and numOptions == 1 then
			local _, instance, _, _, _, _, _, mapID = GetInstanceInfo()
			if instance ~= "raid" and not ignoreGossipNPC[npcID] and not ignoreInstances[mapID] then
				return C_GossipInfo_SelectOption(firstOptionID)
			end
		end
	end

	-- Auto-select when there is exactly one quest-flagged gossip option.
	local numQuestGossips = 0
	local questGossipID
	for i = 1, numOptions do
		local option = gossipInfoTable[i]
		if option.name and (strfind(option.name, QUEST_STRING) or option.flags == QuestLabelPrepend) then
			numQuestGossips = numQuestGossips + 1
			questGossipID = option.gossipOptionID
		end
	end
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
	if QuestIsFromAreaTrigger() then
		AcceptQuest()
	elseif QuestGetAutoAccept() then
		AcknowledgeAutoAcceptQuest()
	elseif not C_QuestLog_IsQuestTrivial(GetQuestID()) or C_Minimap_IsTrackingHiddenQuests() then
		if not ignoreList[GetNPCID()] then
			AcceptQuest()
		end
	end
end)

Register("QUEST_ACCEPT_CONFIRM", AcceptQuest)

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

local function AttemptAutoComplete()
	if GetNumAutoQuestPopUps() > 0 then
		-- Auto-quest popups taint while dead/in combat; retry once it lifts.
		if UnitIsDeadOrGhost("player") or InCombatLockdown() then
			qqFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
			return
		end

		local questID, popUpType = GetAutoQuestPopUp(1)
		if not C_QuestLog_IsWorldQuest(questID) then
			if popUpType == "OFFER" then
				ShowQuestOffer(questID)
			elseif popUpType == "COMPLETE" then
				ShowQuestComplete(questID)
			end
			RemoveAutoQuestPopUp(questID)
		end
	end
end
Register("QUEST_LOG_UPDATE", AttemptAutoComplete)

-- Dedicated, self-unregistering combat handler (the dispatcher passes event
-- payloads, not the event name, so we cannot detect it inside the shared path).
qqFrame.PLAYER_REGEN_ENABLED = function()
	qqFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
	if db().enable and not IsShiftKeyDown() then
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

function QuickQuest:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Quick Quest"], L["Automatically accept and turn in quests; hold SHIFT to pause. Alt-click an NPC name to ignore it."])
end
