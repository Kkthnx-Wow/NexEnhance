--[[
	NexEnhance - Nameplate Quest Indicator
	-------------------------------------------------------------------------
	Puts a quest icon on the nameplate of any NPC tied to one of your active
	quests, with optional objective progress ("3/7" or remaining).

	  * Outside instances we read the unit tooltip (C_TooltipInfo.GetUnit) and
	    walk its quest lines to find an INCOMPLETE objective; the icon greys for
	    a party member's quest when "Show Party Quests" is on.
	  * Inside instances the tooltip is unreliable, so we fall back to the cheap
	    C_QuestLog.UnitIsRelatedToActiveQuest check (icon only, no progress).
	  * Progress text can show always, only on your target, only while a chosen
	    modifier key is held, or on mouseover.

	12.0 "Secret Values": tooltip line fields (completed/leftText/id) can be
	secret in restricted content. Every read is gated by F.CanAccessValue BEFORE
	it is compared, so a secret value cleanly aborts the parse instead of erroring.

	One widget is cached per nameplate UnitFrame and reused as the engine recycles
	nameplates - no per-update frame churn. Event-driven; no polling OnUpdate.
--]]

local _, ns = ...
local F, L = ns.F, ns.L

-- Localised hot globals / APIs.
local C_NamePlate = C_NamePlate
local GetNamePlates = C_NamePlate.GetNamePlates
local UnitIsRelatedToActiveQuest = C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest
local GetUnitTooltipInfo = C_TooltipInfo and C_TooltipInfo.GetUnit
local UnitIsPlayer = UnitIsPlayer
local IsInInstance = IsInInstance
local CanAccess = F.CanAccessValue
local IsSecret = F.IsSecret
local match, format, tonumber = string.match, string.format, tonumber
local ipairs, pairs = ipairs, pairs

local PLAYER_NAME = UnitName("player")

local LINE_TITLE = Enum.TooltipDataLineType.QuestTitle -- 17
local LINE_PLAYER = Enum.TooltipDataLineType.QuestPlayer -- 18
local LINE_OBJECTIVE = Enum.TooltipDataLineType.QuestObjective -- 8

-- Progress display modes / modifier keys (dropdown values).
local MODE_OFF, MODE_TARGET, MODE_HOVER, MODE_KEY = 1, 2, 3, 4
local MOD_KEYS = { [1] = IsAltKeyDown, [2] = IsControlKeyDown, [3] = IsShiftKeyDown }

-- The progress text uses the nameplate outline font's FILE at a user-chosen
-- size (captured once; the size is applied per-widget in the layout pass).
local PROGRESS_FONT_FILE = select(1, SystemFont_Outline_Small:GetFont())

ns:RegisterDefaults({
	questIndicator = {
		enable = true,
		iconSize = 18,
		progressTextSize = 12,
		showPartyQuest = false,
		progressMode = MODE_TARGET,
		modifierKey = 1, -- 1=ALT 2=CTRL 3=SHIFT
		progressFormat = 1, -- 1=completed (3/7), 2=remaining
		side = 2, -- 1=LEFT 2=RIGHT
		offsetX = 0,
		offsetY = 0,
	},
})

local Module = ns:NewModule("QuestIndicator", "questIndicator", {
	group = "nameplates",
	title = L["Nameplate Quest Icons"],
	order = 10,
	since = "1.5.0",
})

-- Live config snapshot, refreshed from the DB in Apply(); the hot paths read
-- these locals rather than indexing ns.db every nameplate update.
local cfg = {}
local active = {} -- widget -> true (currently shown), for batch refreshes
local inInstance = false
local modifierDown = false
local lastHoverWidget
local running = false -- module active (toggled live via OnSettingChanged)
local eventHandles = {}
local refreshRunner
local REFRESH_BATCH_THRESHOLD = 6

-- ---------------------------------------------------------------------------
-- Progress text extraction (secret-guarded before any string work).
-- ---------------------------------------------------------------------------
local function GetProgressText(str)
	if not CanAccess(str) then
		return nil
	end
	if cfg.progressFormat == 2 then -- remaining
		local done, req = match(str, "(%d+)/(%d+)")
		done, req = tonumber(done), tonumber(req)
		if done and req then
			if done < req then
				return format("%d", req - done)
			end
			return nil
		end
		local pct = tonumber(match(str, "(%d+)%%"))
		if pct and pct < 100 then
			return format("%d%%", 100 - pct)
		end
		return nil
	end
	return match(str, "%d+/%d+") or match(str, "%d+%%")
end

-- ---------------------------------------------------------------------------
-- Widget
-- ---------------------------------------------------------------------------
local function Widget_ShowIcon(self, party)
	self.Icon:Show()
	if party then
		self.Icon:SetDesaturated(true)
		self.Icon:SetVertexColor(0.7, 0.7, 0.7)
		self.ProgressText:SetTextColor(0.67, 0.67, 0.67)
	else
		self.Icon:SetDesaturated(false)
		self.Icon:SetVertexColor(1, 1, 1)
		self.ProgressText:SetTextColor(1, 0.95, 0.6)
	end
end

local function Widget_NoQuest(self)
	self.hasProgress = false
	self.Icon:Hide()
	self.ProgressText:Hide()
	self.ProgressText:SetText(nil)
end

-- Decide whether the progress text should currently be visible for this widget.
local function Widget_UpdateProgressShown(self)
	if not self.hasProgress or cfg.progressMode == MODE_OFF then
		self.ProgressText:Hide()
		return
	end
	local show
	if cfg.progressMode == MODE_TARGET then
		show = self.isTarget
	elseif cfg.progressMode == MODE_HOVER then
		show = self.isHover
	elseif cfg.progressMode == MODE_KEY then
		show = modifierDown
	end
	self.ProgressText:SetShown(show and true or false)
end

-- Walk the unit tooltip for quest lines; gate secret fields with CanAccess first.
local function Widget_UpdateQuest(self)
	local unit = self.unit
	if not unit then
		Widget_NoQuest(self)
		return
	end

	-- Instances: tooltip parsing isn't reliable, use the cheap relation check.
	if inInstance then
		if UnitIsRelatedToActiveQuest and UnitIsRelatedToActiveQuest(unit) then
			Widget_ShowIcon(self, false)
			self.hasProgress = false
			self.ProgressText:Hide()
		else
			Widget_NoQuest(self)
		end
		return
	end

	local info = GetUnitTooltipInfo and GetUnitTooltipInfo(unit)
	local lines = info and info.lines
	if not lines then
		Widget_NoQuest(self)
		return
	end

	local allCompleted = true
	local objectiveText, fromAnotherPlayer
	local i, n = 3, #lines

	while i <= n do
		local l = lines[i]
		local t = l.type
		if t == LINE_TITLE then
			allCompleted = true
			i = i + 1
		elseif t == LINE_PLAYER then
			if not CanAccess(l.leftText) then
				break
			end
			local isPlayer = l.leftText == PLAYER_NAME
			i = i + 1
			l = lines[i]
			while l and l.type == LINE_OBJECTIVE and CanAccess(l.completed) do
				if (not l.completed) and (isPlayer or cfg.showPartyQuest) then
					allCompleted = false
					objectiveText = l.leftText
					fromAnotherPlayer = not isPlayer
					break
				end
				i = i + 1
				l = lines[i]
			end
			if not allCompleted then
				break
			end
		elseif t == LINE_OBJECTIVE then
			if not CanAccess(l.completed) then
				break
			end
			if not l.completed then
				allCompleted = false
				objectiveText = l.leftText
				break
			end
			i = i + 1
		else
			i = i + 1
		end
	end

	if allCompleted then
		Widget_NoQuest(self)
		return
	end

	Widget_ShowIcon(self, fromAnotherPlayer)

	local text = GetProgressText(objectiveText)
	self.hasProgress = text ~= nil
	self.ProgressText:SetText(text)
	Widget_UpdateProgressShown(self)
end

local function Widget_Layout(self)
	local size = cfg.iconSize
	self.Icon:SetSize(size, size)
	if PROGRESS_FONT_FILE then
		self.ProgressText:SetFont(PROGRESS_FONT_FILE, cfg.progressTextSize, "OUTLINE")
	end
	self.ProgressText:ClearAllPoints()
	if cfg.side == 1 then -- LEFT: text to the left of the icon
		self.ProgressText:SetPoint("RIGHT", self.Icon, "LEFT", 2, 0)
	else
		self.ProgressText:SetPoint("LEFT", self.Icon, "RIGHT", -2, 0)
	end
end

-- Hover detection is driven entirely by the unit-tooltip postcall (below), not
-- a mouse frame over the icon — a mouse-enabled child would swallow clicks meant
-- for targeting the nameplate. Mousing a nameplate (or the world unit) shows the
-- unit tooltip, which is exactly the signal we hook.
local function CreateWidget(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(1, 1)
	f:SetFrameLevel((parent:GetFrameLevel() or 0) + 4)

	f.Icon = f:CreateTexture(nil, "OVERLAY")
	f.Icon:SetPoint("CENTER")
	f.Icon:SetAtlas("QuestNormal")
	f.Icon:Hide()

	f.ProgressText = f:CreateFontString(nil, "OVERLAY", "SystemFont_Outline_Small")
	f.ProgressText:Hide()

	return f
end

-- ---------------------------------------------------------------------------
-- Attaching to nameplates
-- ---------------------------------------------------------------------------
local function HealthBarOf(unitFrame)
	local hbc = unitFrame.HealthBarsContainer
	return (hbc and hbc.healthBar) or unitFrame.healthBar or unitFrame
end

local function AttachToNameplate(nameplate, unit)
	local unitFrame = nameplate.UnitFrame
	if not unitFrame then
		return
	end

	local widget = unitFrame.NexQuestIndicator
	if not widget then
		widget = CreateWidget(unitFrame)
		unitFrame.NexQuestIndicator = widget
	end

	widget.unit = unit
	widget.isHover = false
	-- Target check is identity-restricted in instances; SafeUnitIsUnit handles it.
	local isTarget = false
	if cfg.progressMode == MODE_TARGET then
		isTarget = F.SafeUnitIsUnit("target", unit)
	end
	widget.isTarget = isTarget

	widget:SetParent(nameplate)
	widget:ClearAllPoints()
	local anchor = HealthBarOf(unitFrame)
	if cfg.side == 1 then
		widget:SetPoint("RIGHT", anchor, "LEFT", -2 + cfg.offsetX, cfg.offsetY)
	else
		widget:SetPoint("LEFT", anchor, "RIGHT", 2 + cfg.offsetX, cfg.offsetY)
	end

	Widget_Layout(widget)
	Widget_UpdateQuest(widget)
	widget:Show()
	active[widget] = true
end

function Module:UpdateNameplateForUnit(unit)
	if not unit then
		return
	end
	-- UnitIsPlayer hands back a secret value when identity is restricted; bail
	-- safely rather than boolean-testing a secret. Short-circuit avoids reading
	-- isPlayer when it is secret.
	local isPlayer = UnitIsPlayer(unit)
	if IsSecret(isPlayer) or isPlayer then
		return
	end
	local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
	if nameplate and not nameplate:IsForbidden() then
		AttachToNameplate(nameplate, unit)
	end
end

function Module:ForEachActive(method)
	for widget in pairs(active) do
		if widget:IsShown() then
			method(widget)
		end
	end
end

function Module:RefreshAllQuests()
	local list = {}
	for widget in pairs(active) do
		if widget:IsShown() then
			list[#list + 1] = widget
		end
	end
	if #list == 0 then
		return
	end
	if #list <= REFRESH_BATCH_THRESHOLD then
		for i = 1, #list do
			Widget_UpdateQuest(list[i])
		end
		return
	end
	if not refreshRunner then
		refreshRunner = ns:CreateRunner("QuestIndicator", 6)
	end
	refreshRunner:Run(list, Widget_UpdateQuest)
end

function Module:RefreshAllProgress()
	self:ForEachActive(Widget_UpdateProgressShown)
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
function Module:NAME_PLATE_UNIT_ADDED(unit)
	if not running then
		return
	end
	self:UpdateNameplateForUnit(unit)
end

function Module:NAME_PLATE_UNIT_REMOVED(unit)
	for widget in pairs(active) do
		if widget.unit == unit then
			active[widget] = nil
			widget.unit = nil
			widget:Hide()
			break
		end
	end
end

-- All events are registered once (the module metatable has no UnregisterEvent),
-- so the handlers below early-return when their mode isn't active. The work is
-- trivial when gated, and it avoids any register/unregister churn.
function Module:PLAYER_TARGET_CHANGED()
	if not running or cfg.progressMode ~= MODE_TARGET then
		return
	end
	for widget in pairs(active) do
		if widget:IsShown() and widget.unit then
			widget.isTarget = F.SafeUnitIsUnit("target", widget.unit)
			Widget_UpdateProgressShown(widget)
		end
	end
end

function Module:MODIFIER_STATE_CHANGED()
	if not running or cfg.progressMode ~= MODE_KEY then
		return
	end
	local isDown = MOD_KEYS[cfg.modifierKey or 1]
	modifierDown = isDown and isDown() or false
	self:RefreshAllProgress()
end

function Module:PLAYER_ENTERING_WORLD()
	if not running then
		return
	end
	self:UpdateZone()
end

function Module:UpdateZone()
	inInstance = IsInInstance()
	if cfg.progressMode ~= MODE_KEY then
		modifierDown = false
	end
	self:RefreshAllQuests()
end

-- ---------------------------------------------------------------------------
-- Tooltip hover hook (only wired once, only used in MODE_HOVER).
-- ---------------------------------------------------------------------------
local hoverHooked = false
local function InstallHoverHook()
	if hoverHooked or not TooltipDataProcessor then
		return
	end
	hoverHooked = true
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
		if not running or cfg.progressMode ~= MODE_HOVER or inInstance then
			return
		end
		if lastHoverWidget then
			lastHoverWidget.isHover = false
			Widget_UpdateProgressShown(lastHoverWidget)
			lastHoverWidget = nil
		end
		local data = tooltip.infoList and tooltip.infoList[1] and tooltip.infoList[1].tooltipData
		local guid = data and data.guid
		if not (guid and CanAccess(guid) and UnitTokenFromGUID) then
			return
		end
		local unit = UnitTokenFromGUID(guid)
		for widget in pairs(active) do
			if widget:IsShown() and widget.unit == unit then
				widget.isHover = true
				lastHoverWidget = widget
				Widget_UpdateProgressShown(widget)
				break
			end
		end
	end)

	-- When the tooltip hides (mouse left the unit), drop the lingering hover.
	GameTooltip:HookScript("OnHide", function()
		if lastHoverWidget then
			lastHoverWidget.isHover = false
			Widget_UpdateProgressShown(lastHoverWidget)
			lastHoverWidget = nil
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
local function ReadConfig()
	local db = ns.db.questIndicator
	cfg.iconSize = db.iconSize or 18
	cfg.progressTextSize = db.progressTextSize or 12
	cfg.showPartyQuest = db.showPartyQuest
	cfg.progressMode = db.progressMode or MODE_TARGET
	cfg.modifierKey = db.modifierKey or 1
	cfg.progressFormat = db.progressFormat or 1
	cfg.side = db.side or 2
	cfg.offsetX = db.offsetX or 0
	cfg.offsetY = db.offsetY or 0
end

function Module:Apply()
	ReadConfig()
	InstallHoverHook()
	self:UpdateZone()
	-- Re-attach every currently-shown nameplate with the new settings.
	local plates = GetNamePlates(false)
	if plates then
		for _, nameplate in ipairs(plates) do
			local uf = nameplate.UnitFrame
			if uf and uf.unit then
				self:UpdateNameplateForUnit(uf.unit)
			end
		end
	end
end

-- Register events exactly once (idempotent); handlers gate on `running`.
function Module:EnsureEvents()
	if self.eventsRegistered then
		return
	end
	self.eventsRegistered = true

	-- Coalesce quest-log bursts into one refresh.
	self.RefreshQuestsDebounced = F.Debounce(0.2, function()
		Module:RefreshAllQuests()
	end)

	self:TrackEvent(eventHandles, "NAME_PLATE_UNIT_ADDED")
	self:TrackEvent(eventHandles, "NAME_PLATE_UNIT_REMOVED")
	self:TrackEvent(eventHandles, "PLAYER_ENTERING_WORLD")
	self:TrackEvent(eventHandles, "PLAYER_TARGET_CHANGED")
	self:TrackEvent(eventHandles, "MODIFIER_STATE_CHANGED")
	self:TrackEvent(eventHandles, "UNIT_QUEST_LOG_CHANGED", "OnQuestLogChanged")
	self:TrackEvent(eventHandles, "QUEST_LOG_UPDATE", "OnQuestLogChanged")
end

function Module:UnregisterModuleEvents()
	if not self.eventsRegistered then
		return
	end
	self.eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
	self.RefreshQuestsDebounced = nil
end

function Module:OnDisable()
	running = false
	if refreshRunner then
		refreshRunner:Cancel()
	end
	self:HideAll()
	self:UnregisterModuleEvents()
end

function Module:HideAll()
	for widget in pairs(active) do
		active[widget] = nil
		widget:Hide()
	end
end

function Module:OnEnable()
	running = true
	self:EnsureEvents()
	self:Apply()
end

function Module:OnQuestLogChanged()
	if running and self.RefreshQuestsDebounced then
		self.RefreshQuestsDebounced()
	end
end

function Module:OnSettingChanged(key, value)
	if key == "enable" then
		if value then
			running = true
			self:EnsureEvents()
			self:Apply()
		else
			self:OnDisable()
		end
		return
	end
	if running then
		self:Apply()
	end
end

-- ---------------------------------------------------------------------------
-- Options
-- ---------------------------------------------------------------------------
function Module:RegisterOptions(category, builder)
	local _, master = builder:Checkbox(category, self, "enable", L["Enable Nameplate Quest Icons"], L["Show a quest icon (and optional objective progress) on the nameplates of NPCs tied to your active quests."])

	local _, party = builder:Checkbox(category, self, "showPartyQuest", L["Show Party Quests"], L["Also mark NPCs that are only on a party member's quest (the icon is greyed)."])
	builder:DependsOn(party, master)

	local _, size = builder:Slider(category, self, "iconSize", L["Icon Size"], L["Size of the quest icon, in pixels."], 12, 32, 1)
	builder:DependsOn(size, master)

	local _, textSize = builder:Slider(category, self, "progressTextSize", L["Progress Text Size"], L["Font size of the objective progress text next to the icon."], 8, 24, 1)
	builder:DependsOn(textSize, master)

	local sideChoices = {
		{ value = 2, label = L["Right of Healthbar"] },
		{ value = 1, label = L["Left of Healthbar"] },
	}
	local _, side = builder:Dropdown(category, self, "side", L["Icon Side"], L["Which side of the nameplate healthbar the icon sits on."], sideChoices)
	builder:DependsOn(side, master)

	local _, ox = builder:Slider(category, self, "offsetX", L["Offset X"], L["Horizontal nudge for the icon."], -50, 50, 1)
	builder:DependsOn(ox, master)
	local _, oy = builder:Slider(category, self, "offsetY", L["Offset Y"], L["Vertical nudge for the icon."], -50, 50, 1)
	builder:DependsOn(oy, master)

	local modeChoices = {
		{ value = MODE_OFF, label = L["Never"] },
		{ value = MODE_TARGET, label = L["On Your Target"] },
		{ value = MODE_HOVER, label = L["On Mouseover"] },
		{ value = MODE_KEY, label = L["While Holding a Key"] },
	}
	local _, mode = builder:Dropdown(category, self, "progressMode", L["Show Objective Progress"], L["When to show the objective count next to the icon."], modeChoices)
	builder:DependsOn(mode, master)

	local keyChoices = {
		{ value = 1, label = L["Alt"] },
		{ value = 2, label = L["Ctrl"] },
		{ value = 3, label = L["Shift"] },
	}
	local _, key = builder:Dropdown(category, self, "modifierKey", L["Progress Modifier Key"], L["Which key shows progress when 'While Holding a Key' is selected."], keyChoices)
	builder:DependsOn(key, master)

	local fmtChoices = {
		{ value = 1, label = L["Completed (3/7)"] },
		{ value = 2, label = L["Remaining (4)"] },
	}
	local _, fmt = builder:Dropdown(category, self, "progressFormat", L["Progress Format"], L["Show how many objectives are completed, or how many remain."], fmtChoices)
	builder:DependsOn(fmt, master)
end
