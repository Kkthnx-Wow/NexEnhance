--[[
	NexEnhance - Async data loaders
	-------------------------------------------------------------------------
	Coalesced QUEST/ITEM/SPELL_DATA_LOAD_RESULT handling — one shared listener
	per event; multiple waiters per ID share one request.

	Callbacks receive one boolean: `true` when Blizzard reports success, `false`
	when the load failed. Legacy handlers that ignore the arg still work on
	success; gate retries with `if success == false then return end`.
--]]

local _, ns = ...

local C_QuestLog = C_QuestLog
local C_Item = C_Item
local C_Spell = C_Spell

local function CreateDataLoader(eventName, requestLoad)
	local waiters = {}
	local registered = false

	local function OnLoadResult(_, id, success)
		local list = waiters[id]
		if not list then
			return
		end
		waiters[id] = nil
		local ok = success ~= false
		for i = 1, #list do
			local callback = list[i]
			if callback then
				callback(ok)
			end
		end
	end

	local function Ensure()
		if registered then
			return
		end
		registered = true
		ns:RegisterEvent(eventName, OnLoadResult)
	end

	return function(id, callback)
		if not (id and callback and requestLoad) then
			return false
		end
		Ensure()
		local list = waiters[id]
		if not list then
			list = {}
			waiters[id] = list
		end
		list[#list + 1] = callback
		requestLoad(id)
		return true
	end
end

--- Queue `callback(success)` after Blizzard loads `questID`.
function ns:RequestQuestData(questID, callback)
	if not (questID and callback and C_QuestLog and C_QuestLog.RequestLoadQuestByID) then
		return false
	end
	if not ns._requestQuestData then
		ns._requestQuestData = CreateDataLoader("QUEST_DATA_LOAD_RESULT", C_QuestLog.RequestLoadQuestByID)
	end
	return ns._requestQuestData(questID, callback)
end

--- Queue `callback(success)` after Blizzard loads `itemID`.
function ns:RequestItemData(itemID, callback)
	if not (itemID and callback and C_Item and C_Item.RequestLoadItemDataByID) then
		return false
	end
	if not ns._requestItemData then
		ns._requestItemData = CreateDataLoader("ITEM_DATA_LOAD_RESULT", C_Item.RequestLoadItemDataByID)
	end
	return ns._requestItemData(itemID, callback)
end

--- Queue `callback(success)` after Blizzard loads `spellID`.
function ns:RequestSpellData(spellID, callback)
	if not (spellID and callback and C_Spell and C_Spell.RequestLoadSpellData) then
		return false
	end
	if not ns._requestSpellData then
		ns._requestSpellData = CreateDataLoader("SPELL_DATA_LOAD_RESULT", C_Spell.RequestLoadSpellData)
	end
	return ns._requestSpellData(spellID, callback)
end
