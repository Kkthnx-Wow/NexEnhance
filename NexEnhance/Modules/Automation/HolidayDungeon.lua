--[[
	NexEnhance - Holiday Dungeon
	-------------------------------------------------------------------------
	When you open the Dungeon Finder for the first time each login, nudge you
	toward the active holiday or Timewalking random queue if it is not already
	selected. We never call LFDQueueFrame_SetType from addon code — that taints
	LFG session globals and can block protected queue actions (AcceptProposal).

	LFDQueueFrame_SetType from addon code — that taints LFG session globals.

	Blizzard_GroupFinder is load-on-demand; hook installs once and reads the
	live enable toggle.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local L, F = ns.L, ns.F

local format = string.format
local wipe = wipe
local sort = table.sort
local C_Timer_After = C_Timer and C_Timer.After
local C_AddOns_IsAddOnLoaded = C_AddOns.IsAddOnLoaded
local GetNumRandomDungeons = GetNumRandomDungeons
local GetLFGRandomDungeonInfo = GetLFGRandomDungeonInfo
local IsLFGDungeonJoinable = IsLFGDungeonJoinable

local LFG_TYPE_RANDOM_TIMEWALKER_DUNGEON = _G.LFG_TYPE_RANDOM_TIMEWALKER_DUNGEON

-- Random LFG dungeon IDs for events where GetLFGRandomDungeonInfo's isTimeWalker
-- can be false (e.g. Turbulent Timeways). Verify new IDs in-game when an expansion
-- joins the rotation: /run for i=1,GetNumRandomDungeons() do local id=GetLFGRandomDungeonInfo(i); print(i,id,GetLFGRandomDungeonInfo(i)) end
local SPECIAL_RANDOM_DUNGEONS = {
	[288] = true, -- Love is in the Air: The Crown Chemical Co.
	[286] = true, -- Midsummer: The Frost Lord Ahune
	[287] = true, -- Brewfest: Coren Direbrew
	[285] = true, -- Hallow's End: The Headless Horseman

	[744] = true, -- Random Timewalking (Burning Crusade)
	[995] = true, -- Random Timewalking (Wrath of the Lich King)
	[1146] = true, -- Random Timewalking (Cataclysm)
	[1453] = true, -- Random Timewalking (Mists of Pandaria)
	[1971] = true, -- Random Timewalking (Warlords of Draenor)
	[2274] = true, -- Random Timewalking (Legion)
	[2634] = true, -- Random Timewalking (Classic)
	[2874] = true, -- Random Timewalking (Battle for Azeroth)
	[3076] = true, -- Random Timewalking (Shadowlands)
}

ns:RegisterDefaults({
	holidayDungeon = {
		enable = false,
	},
})

local HolidayDungeon = ns:NewModule("HolidayDungeon", "holidayDungeon", { group = "automation", title = L["Holiday Dungeon"], order = 92 })

local candidates = {}
local eventHandles = {}
local eventsRegistered = false

local function db()
	return ns.db.holidayDungeon
end

local function IsEventRandomDungeon(id, isHoliday, isTimeWalker, name)
	if isHoliday or isTimeWalker or SPECIAL_RANDOM_DUNGEONS[id] then
		return true
	end
	-- Turbulent Timeways can clear isTimeWalker; match the localized queue label.
	local label = LFG_TYPE_RANDOM_TIMEWALKER_DUNGEON
	return label and name and name:find(label, 1, true) ~= nil
end

local function GetRandomDungeonName(dungeonID)
	for i = 1, GetNumRandomDungeons() do
		local id, name = GetLFGRandomDungeonInfo(i)
		if id == dungeonID then
			return name
		end
	end
end

local function GetBestDungeon()
	wipe(candidates)
	local n = 0

	for i = 1, GetNumRandomDungeons() do
		local id, name, _, _, _, _, _, _, _, _, _, _, _, _, _, isHoliday, _, _, isTimeWalker = GetLFGRandomDungeonInfo(i)
		local isAvailableForAll = IsLFGDungeonJoinable(id)
		if isAvailableForAll and IsEventRandomDungeon(id, isHoliday, isTimeWalker, name) then
			n = n + 1
			candidates[n] = id
		end
	end

	if n == 0 then
		return
	end

	sort(candidates)
	return candidates[1]
end

function HolidayDungeon:MaybeNudge()
	if self.doneThisSession or not db().enable then
		return
	end

	local queueFrame = _G.LFDQueueFrame
	local dropdown = queueFrame and queueFrame.TypeDropdown
	if not (queueFrame and queueFrame:IsShown() and dropdown) then
		return
	end

	local bestID = GetBestDungeon()
	if not bestID then
		self.doneThisSession = true
		return
	end

	if queueFrame.type == bestID then
		self.doneThisSession = true
		return
	end

	self.doneThisSession = true
	self.nudgePending = nil

	local name = GetRandomDungeonName(bestID)
	if not name then
		return
	end

	local HelpTip = _G.HelpTip
	local point = HelpTip and HelpTip.Point and HelpTip.Point.BottomEdgeCenter
	F.ShowHelpTip(dropdown, "HolidayDungeon", format(L["HolidayDungeonHelpTip"], name), { targetPoint = point })
end

function HolidayDungeon:ScheduleNudge()
	if self.doneThisSession or not db().enable then
		return
	end
	if not _G.LFDParentFrame or not LFDParentFrame:IsShown() then
		return
	end

	self.nudgePending = true

	-- LFG_UPDATE_RANDOM_INFO usually follows LFD OnShow; fall back if it already fired.
	if C_Timer_After then
		C_Timer_After(0.5, function()
			if HolidayDungeon.nudgePending then
				HolidayDungeon:MaybeNudge()
			end
		end)
	end
end

function HolidayDungeon:LFG_UPDATE_RANDOM_INFO()
	if not self.nudgePending then
		return
	end
	self:MaybeNudge()
end

function HolidayDungeon:HookLFDFrame()
	if self.hooked then
		return
	end

	local frame = _G.LFDParentFrame
	if not frame then
		return
	end

	self.hooked = true
	frame:HookScript("OnShow", function()
		HolidayDungeon:ScheduleNudge()
	end)
end

function HolidayDungeon:TrySetup()
	if self.hooked or self.waiting then
		return
	end

	if _G.LFDParentFrame then
		self:HookLFDFrame()
		return
	end

	if C_AddOns_IsAddOnLoaded("Blizzard_GroupFinder") then
		self:HookLFDFrame()
		return
	end

	self.waiting = true
	ns:RegisterAddOnLoadedCallback("Blizzard_GroupFinder", function()
		self.waiting = nil
		self:HookLFDFrame()
	end)
end

function HolidayDungeon:PLAYER_LOGIN()
	self.doneThisSession = nil
	self.nudgePending = nil
end

function HolidayDungeon:RegisterModuleEvents()
	if eventsRegistered then
		return
	end
	eventsRegistered = true
	self:TrackEvent(eventHandles, "PLAYER_LOGIN")
	self:TrackEvent(eventHandles, "LFG_UPDATE_RANDOM_INFO")
end

function HolidayDungeon:UnregisterModuleEvents()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
end

function HolidayDungeon:OnSettingChanged(key, value)
	-- ApplyModuleSetting owns enable lifecycle.
	if key == "enable" then
		return
	end
end

function HolidayDungeon:OnEnable()
	if not db().enable then
		return
	end
	self:RegisterModuleEvents()
	self:TrySetup()
end

function HolidayDungeon:OnDisable()
	self:UnregisterModuleEvents()
end

function HolidayDungeon:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Holiday Dungeon"], L["Holiday Dungeon setting tip"])
end
