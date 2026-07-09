--[[
	NexEnhance - Delves Automation
	-------------------------------------------------------------------------
	While you are inside a Delve, automatically confirms the single-choice
	"borrowed power" popup (the curio/power offered during the run) so you
	don't have to click through it, and optionally announces what was taken.

	Event-driven: PLAYER_CHOICE_UPDATE registers only while inside a Delve
	(gated via ns:CreateStateTrigger). No OnUpdate polling. Handler is
	cheapest-filter-first and only auto-confirms a lone spell-backed option.
	Toggles live without reload.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local F, L = ns.F, ns.L

local format = string.format
local C_PartyInfo_IsPartyWalkIn = C_PartyInfo and C_PartyInfo.IsPartyWalkIn
local C_PlayerChoice_GetCurrentPlayerChoiceInfo = C_PlayerChoice and C_PlayerChoice.GetCurrentPlayerChoiceInfo
local C_PlayerChoice_SendPlayerChoiceResponse = C_PlayerChoice and C_PlayerChoice.SendPlayerChoiceResponse
local C_PlayerChoice_OnUIClosed = C_PlayerChoice and C_PlayerChoice.OnUIClosed
local ITEM_QUALITY_COLORS = ITEM_QUALITY_COLORS

-- WALK_IN_DATA_UPDATE is the event that tells us walk-in (Delve) status is ready;
-- it isn't valid on every client flavour, so probe it once.
local HAS_WALK_IN_EVENT = C_EventUtils and C_EventUtils.IsEventValid and C_EventUtils.IsEventValid("WALK_IN_DATA_UPDATE")

ns:RegisterDefaults({
	delvesAutomation = {
		enable = false,
		printToChat = true,
	},
})

local DelvesAutomation = ns:NewModule("DelvesAutomation", "delvesAutomation", { group = "automation", title = L["Delves Automation"], order = 95 })

local delveGate

local function db()
	return ns.db.delvesAutomation
end

-- Delves are "walk-in" instances; IsPartyWalkIn is the signal Blizzard's own
-- InstanceDifficulty UI uses and it survives relogging inside the delve.
local function IsInDelve()
	return C_PartyInfo_IsPartyWalkIn and C_PartyInfo_IsPartyWalkIn() or false
end

-- ---------------------------------------------------------------------------
-- PLAYER_CHOICE_UPDATE handler (only live while inside a Delve)
-- ---------------------------------------------------------------------------
local function OnPlayerChoice()
	local info = C_PlayerChoice_GetCurrentPlayerChoiceInfo and C_PlayerChoice_GetCurrentPlayerChoiceInfo()
	local options = info and info.options
	-- Only auto-confirm a genuinely single, unambiguous choice.
	if not options or #options ~= 1 then
		return
	end

	local option = options[1]
	local buttons = option and option.buttons
	if not (option.spellID and buttons and #buttons == 1) then
		return
	end

	local responseID = buttons[1].id
	if not responseID then
		return
	end

	C_PlayerChoice_SendPlayerChoiceResponse(responseID)
	if C_PlayerChoice_OnUIClosed then
		C_PlayerChoice_OnUIClosed()
	end

	if db().printToChat then
		local link = format("|Hspell:%d:0|h[%s]|h", option.spellID, option.header or "")
		-- Enum.PlayerChoiceRarity is item-quality minus one; shift it back.
		local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[(option.rarity or 0) + 1]
		if color and color.hex then
			link = color.hex .. link .. "|r"
		end
		F.Print(L["Auto-selected:"], link)
	end
end

-- ---------------------------------------------------------------------------
-- Subscription gating (via CreateStateTrigger)
-- ---------------------------------------------------------------------------
local choiceSubscribed = false

local function SubscribeChoice()
	if choiceSubscribed then
		return
	end
	choiceSubscribed = true
	ns:RegisterEvent("PLAYER_CHOICE_UPDATE", OnPlayerChoice)
end

local function UnsubscribeChoice()
	if not choiceSubscribed then
		return
	end
	choiceSubscribed = false
	ns:UnregisterEvent("PLAYER_CHOICE_UPDATE", OnPlayerChoice)
end

local function EnsureDelveGate()
	if delveGate then
		return delveGate
	end
	local extraEvents = HAS_WALK_IN_EVENT and { "WALK_IN_DATA_UPDATE" } or {}
	delveGate = ns:CreateStateTrigger(
		function()
			return db().enable and IsInDelve()
		end,
		SubscribeChoice,
		UnsubscribeChoice,
		{ debounce = 0.5, events = extraEvents }
	)
	return delveGate
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function DelvesAutomation:OnEnable()
	if db().enable then
		EnsureDelveGate():Enable()
	end
end

function DelvesAutomation:OnDisable()
	if delveGate then
		delveGate:Disable()
	end
	UnsubscribeChoice()
end

function DelvesAutomation:OnSettingChanged(key)
	if key == "enable" then
		-- ApplyModuleSetting owns enable lifecycle.
		return
	end
end

function DelvesAutomation:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Delves Automation"], L["While inside a Delve, automatically confirm the single-choice borrowed power popup."])
	local _, printInit = builder:Checkbox(category, self, "printToChat", L["Announce Auto-Selection"], L["Print the borrowed power you auto-selected to chat."])

	builder:DependsOn(printInit, enableInit)
end
