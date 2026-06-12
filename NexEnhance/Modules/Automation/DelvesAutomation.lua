--[[
	NexEnhance - Delves Automation
	-------------------------------------------------------------------------
	While you are inside a Delve, automatically confirms the single-choice
	"borrowed power" popup (the curio/power offered during the run) so you
	don't have to click through it, and optionally announces what was taken.

	Concept ported from Plumber's DelvesAutomation module (Plumber by
	Peterodox). This is an independent NexEnhance implementation - rewritten
	against the project optimisation guide rather than copied:
	  * Purely event-driven. PLAYER_CHOICE_UPDATE is registered only while we
	    are actually inside a Delve (gated by PLAYER_ENTERING_WORLD /
	    PLAYER_MAP_CHANGED), so player choices outside Delves are never touched.
	  * No OnUpdate polling - delve state is recomputed from cheap events.
	  * Every API used in the handler is localised; the handler runs
	    cheapest-filter-first and bails on anything that isn't a lone,
	    single-button, spell-backed option.
	  * Toggles live without a reload.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local F, L = ns.F, ns.L

local format = string.format
local C_Timer_After = C_Timer and C_Timer.After
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
-- Subscription gating
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

-- Listen for the borrowed-power popup only when standing inside a Delve.
local function RefreshDelveState()
	if db().enable and IsInDelve() then
		SubscribeChoice()
	else
		UnsubscribeChoice()
	end
end

-- IsPartyWalkIn() is stale at the exact moment you cross a Delve boundary (it
-- still reports the old state on PLAYER_ENTERING_WORLD), so the gate events
-- only schedule a re-check a beat later rather than reading it immediately. A
-- single pending flag coalesces a burst of boundary events into one timer.
local refreshPending = false

local function RunScheduledRefresh()
	refreshPending = false
	RefreshDelveState()
end

local function ScheduleRefresh()
	if refreshPending then
		return
	end
	refreshPending = true
	if C_Timer_After then
		C_Timer_After(0.5, RunScheduledRefresh)
	else
		RunScheduledRefresh()
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
local gateRegistered = false

local function Setup()
	if not gateRegistered then
		gateRegistered = true
		ns:RegisterEvent("PLAYER_ENTERING_WORLD", ScheduleRefresh)
		ns:RegisterEvent("PLAYER_MAP_CHANGED", ScheduleRefresh)
		if HAS_WALK_IN_EVENT then
			ns:RegisterEvent("WALK_IN_DATA_UPDATE", ScheduleRefresh)
		end
	end
	-- Catch the case where the module is enabled while already inside a Delve.
	ScheduleRefresh()
end

local function Teardown()
	if gateRegistered then
		gateRegistered = false
		ns:UnregisterEvent("PLAYER_ENTERING_WORLD", ScheduleRefresh)
		ns:UnregisterEvent("PLAYER_MAP_CHANGED", ScheduleRefresh)
		if HAS_WALK_IN_EVENT then
			ns:UnregisterEvent("WALK_IN_DATA_UPDATE", ScheduleRefresh)
		end
	end
	UnsubscribeChoice()
end

function DelvesAutomation:OnEnable()
	if db().enable then
		Setup()
	end
end

function DelvesAutomation:OnSettingChanged()
	if db().enable then
		Setup()
	else
		Teardown()
	end
end

function DelvesAutomation:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Delves Automation"], L["While inside a Delve, automatically confirm the single-choice borrowed power popup."])
	local _, printInit = builder:Checkbox(category, self, "printToChat", L["Announce Auto-Selection"], L["Print the borrowed power you auto-selected to chat."])

	builder:DependsOn(printInit, enableInit)
end
