--[[
	NexEnhance - System Chat Filter
	-------------------------------------------------------------------------
	Filters learn/unlearn spell spam when changing talents (Inomena-inspired).
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local L = ns.L

local ChatFrame_AddMessageEventFilter = ChatFrame_AddMessageEventFilter

ns:RegisterDefaults({
	systemChatFilter = {
		enable = true,
	},
})

local SystemChatFilter = ns:NewModule("SystemChatFilter", "systemChatFilter", { group = "filters", title = L["System Chat Filter"], order = 20 })

local installed

-- Prefixes from ERR_LEARN_* / ERR_SPELL_UNLEARNED (locale-stable leading text).
local ERR_LEARN_ABILITY = string.split("%s", ERR_LEARN_ABILITY_S)
local ERR_LEARN_PASSIVE = string.split("%s", ERR_LEARN_PASSIVE_S)
local ERR_LEARN_SPELL = string.split("%s", ERR_LEARN_SPELL_S)
local ERR_SPELL_UNLEARNED = string.split("%s", ERR_SPELL_UNLEARNED_S)

local function ShouldHideSystemMessage(msg)
	if not msg or ns.F.IsSecret(msg) then
		return false
	end
	local lenAbility = #ERR_LEARN_ABILITY
	local lenPassive = #ERR_LEARN_PASSIVE
	local lenSpell = #ERR_LEARN_SPELL
	local lenUnlearned = #ERR_SPELL_UNLEARNED
	if lenAbility > 0 and msg:sub(1, lenAbility) == ERR_LEARN_ABILITY then
		return true
	end
	if lenPassive > 0 and msg:sub(1, lenPassive) == ERR_LEARN_PASSIVE then
		return true
	end
	if lenSpell > 0 and msg:sub(1, lenSpell) == ERR_LEARN_SPELL then
		return true
	end
	if lenUnlearned > 0 and msg:sub(1, lenUnlearned) == ERR_SPELL_UNLEARNED then
		return true
	end
	return false
end

local function OnSystemMessage(_, _, msg, ...)
	if not ns.db.systemChatFilter.enable then
		return false, msg, ...
	end
	if ShouldHideSystemMessage(msg) then
		return true
	end
	return false, msg, ...
end

function SystemChatFilter:OnEnable()
	if not ns.db.systemChatFilter.enable or installed then
		return
	end
	ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", OnSystemMessage)
	installed = true
end

function SystemChatFilter:OnDisable()
	if not installed then
		return
	end
	-- Blizzard provides no remove API; filter stays registered but no-ops when disabled.
end

function SystemChatFilter:OnSettingChanged()
	-- Filter callback reads ns.db live; nothing to reinstall.
end

function SystemChatFilter:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable System Chat Filter"], L["Hide learn and unlearn spell system messages when changing talents."])
end
