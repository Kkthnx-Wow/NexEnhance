--[[
	NexEnhance - Quick Item Delete
	-------------------------------------------------------------------------
	Blizzard makes you type "DELETE" to destroy high-quality or quest items.
	This swaps those confirmation dialogs (DELETE_GOOD_ITEM /
	DELETE_GOOD_QUEST_ITEM) for the simple Yes/No prompt used by ordinary
	items, with a short timeout so it auto-cancels if you walk away.

	Refactor of an old snippet that just overwrote the dialog tables outright.
	Doing it properly: we clone the simple dialog with Blizzard's own
	CopyTable() (SharedXML/TableUtil.lua) so we never mutate Blizzard's shared
	table, stash the originals, and restore them when the option is turned off -
	so it toggles live without a reload. Off by default since it removes a
	safety prompt.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local L = ns.L

local ipairs = ipairs
local CopyTable = CopyTable
local StaticPopupDialogs = StaticPopupDialogs

-- target dialog (the one that forces you to type DELETE)  <-  simple source.
local OVERRIDES = {
	{ target = "DELETE_GOOD_ITEM", source = "DELETE_ITEM" },
	{ target = "DELETE_GOOD_QUEST_ITEM", source = "DELETE_QUEST_ITEM" },
}

local TIMEOUT = 5

ns:RegisterDefaults({
	quickDelete = {
		enable = false,
	},
})

local QuickDelete = ns:NewModule("QuickDelete", "quickDelete", { group = "inventory", title = L["Quick Item Delete"], order = 50 })

local originals = {}
local applied = false

local function Apply()
	if applied or not StaticPopupDialogs then
		return
	end

	for _, entry in ipairs(OVERRIDES) do
		local source = StaticPopupDialogs[entry.source]
		if source then
			-- Remember Blizzard's original so we can put it back on disable.
			originals[entry.target] = StaticPopupDialogs[entry.target]

			-- Clone the simple Yes/No dialog (DeleteCursorItem OnAccept and all)
			-- via Blizzard's CopyTable so the typed confirmation is no longer
			-- required and we never touch Blizzard's original table.
			local copy = CopyTable(source)
			copy.timeout = TIMEOUT
			StaticPopupDialogs[entry.target] = copy
		end
	end

	applied = true
end

local function Restore()
	if not applied or not StaticPopupDialogs then
		return
	end

	for _, entry in ipairs(OVERRIDES) do
		if originals[entry.target] ~= nil then
			StaticPopupDialogs[entry.target] = originals[entry.target]
		end
	end

	applied = false
end

function QuickDelete:OnEnable()
	if ns.db.quickDelete.enable then
		Apply()
	end
end

function QuickDelete:OnSettingChanged(key, value)
	if key ~= "enable" then
		return
	end
	if value then
		Apply()
	else
		Restore()
	end
end

function QuickDelete:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Quick Item Delete"], L["Skip the type-DELETE confirmation for high-quality and quest items, showing a simple Yes/No prompt instead. Reduces accidental-deletion protection."])
end
