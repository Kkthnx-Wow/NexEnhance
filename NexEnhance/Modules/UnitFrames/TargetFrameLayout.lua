--[[
	NexEnhance - Target Frame Layout
	-------------------------------------------------------------------------
	Player-style tweaks for the default Target frame (and the shared Target/
	Focus/Boss reaction strip):

	  * Neutral reaction strip — hide the coloured status strip under the name
	    on Target, Focus, and Boss frames so the dark chrome shows through,
	    matching the player frame (which has no strip).
	  * Name beside portrait — on Target only, re-anchor the name next to the
	    portrait (mirroring the player-frame gap). Blizzard normally pins the
	    name to the reaction strip (TargetFrame.xml).

	Researched from Blizzard_UnitFrame/Mainline/TargetFrame.xml and
	PlayerFrame.xml (12.0.7). hooksecurefunc on CheckFaction only; cosmetic
	SetAlpha / SetPoint — no secure APIs, no health-bar reads.

	Default OFF. Lives under Unit Frames.
--]]

local _, ns = ...
local F, L = ns.F, ns.L

local _G = _G
local UnitSelectionColor = UnitSelectionColor
local hooksecurefunc = hooksecurefunc
local ipairs = ipairs

ns:RegisterDefaults({
	targetFrameLayout = {
		enable = false,
	},
})

ns:RegisterDefaults({ targetFrameLayoutMigrated = false }, "global")

local TargetFrameLayout = ns:NewModule("TargetFrameLayout", "targetFrameLayout", {
	group = "unitframes",
	title = L["Target Frame Layout"],
	order = 12,
})

local eventHandles = {}
local eventsRegistered = false

local TARGET_LAYOUT_UNITS = {
	target = true,
	focus = true,
}
for i = 1, 5 do
	TARGET_LAYOUT_UNITS["boss" .. i] = true
end

local function IsTargetLayoutUnit(unit)
	return not unit or TARGET_LAYOUT_UNITS[unit] == true
end

local scheduleRefreshAll = F.Debounce(0, function()
	if ns.db.targetFrameLayout.enable then
		TargetFrameLayout:RefreshAll()
	end
end)

-- Player: name TOPLEFT 88,-27 vs portrait TOPLEFT 24,-19 (60 wide) -> 4px gap, -8px Y.
-- Target mirror: name TOPRIGHT to portrait TOPLEFT.
local NAME_PORTRAIT_X = -4
local NAME_PORTRAIT_Y = -7

local function GetReputationColor(frame)
	local content = frame and frame.TargetFrameContent
	local main = content and content.TargetFrameContentMain
	return main and main.ReputationColor
end

local function GetTargetName(frame)
	local content = frame and frame.TargetFrameContent
	local main = content and content.TargetFrameContentMain
	return main and main.Name
end

local function CaptureDefaultNameAnchor(name)
	if name.nexDefaultAnchor then
		return
	end
	local point, relativeTo, relativePoint, x, y = name:GetPoint(1)
	if not point then
		return
	end
	name.nexDefaultAnchor = { point, relativeTo, relativePoint, x, y }
	name.nexDefaultJustifyH = name:GetJustifyH()
	name.nexDefaultJustifyV = name:GetJustifyV()
end

local function RestoreDefaultNameAnchor(name)
	if not name or not name.nexDefaultAnchor then
		return
	end
	local anchor = name.nexDefaultAnchor
	name:ClearAllPoints()
	name:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4], anchor[5])
	if name.nexDefaultJustifyH then
		name:SetJustifyH(name.nexDefaultJustifyH)
	end
	if name.nexDefaultJustifyV then
		name:SetJustifyV(name.nexDefaultJustifyV)
	end
end

local function NeutralizeReputationStrip(frame)
	if not frame or not ns.db.targetFrameLayout.enable then
		return
	end
	local strip = GetReputationColor(frame)
	if strip then
		strip:SetAlpha(0)
	end
end

local function RestoreReputationStrip(frame)
	local unit = frame and frame.unit
	local strip = GetReputationColor(frame)
	if not strip then
		return
	end
	strip:SetAlpha(1)
	if not unit then
		return
	end
	-- UnitSelectionColor: SecretArguments only in 12.0.7 — returns are plain.
	local r, g, b = UnitSelectionColor(unit)
	if r then
		strip:SetVertexColor(r, g, b)
	end
end

local function RefreshTargetNameLayout(frame)
	if frame ~= _G["TargetFrame"] then
		return
	end

	local name = GetTargetName(frame)
	if not name then
		return
	end

	CaptureDefaultNameAnchor(name)

	if not ns.db.targetFrameLayout.enable then
		RestoreDefaultNameAnchor(name)
		return
	end

	local portrait = frame.TargetFrameContainer and frame.TargetFrameContainer.Portrait
	if not portrait or not portrait:IsShown() then
		RestoreDefaultNameAnchor(name)
		return
	end

	name:ClearAllPoints()
	name:SetJustifyH("RIGHT")
	name:SetJustifyV("MIDDLE")
	name:SetPoint("TOPRIGHT", portrait, "TOPLEFT", NAME_PORTRAIT_X, NAME_PORTRAIT_Y)
end

local function RefreshFrame(frame)
	if not frame then
		return
	end
	if ns.db.targetFrameLayout.enable then
		NeutralizeReputationStrip(frame)
	else
		RestoreReputationStrip(frame)
	end
	RefreshTargetNameLayout(frame)
end

local standardFrames = { "TargetFrame", "FocusFrame" }

local function ForEachBossFrame(callback)
	local container = _G["BossTargetFrameContainer"]
	local frames = container and container.BossTargetFrames
	if not frames then
		return
	end
	for _, frame in ipairs(frames) do
		if frame then
			callback(frame)
		end
	end
end

function TargetFrameLayout:RefreshAll()
	for i = 1, #standardFrames do
		local frame = _G[standardFrames[i]]
		if frame then
			RefreshFrame(frame)
			if frame.totFrame then
				RefreshFrame(frame.totFrame)
			end
		end
	end
	ForEachBossFrame(RefreshFrame)
end

local function HookFaction(frame)
	if not frame or frame.nexLayoutFactionHooked then
		return
	end
	if type(frame.CheckFaction) ~= "function" then
		return
	end
	frame.nexLayoutFactionHooked = true
	hooksecurefunc(frame, "CheckFaction", function(f)
		RefreshFrame(f)
	end)
end

function TargetFrameLayout:InstallHooks()
	if self.hooksInstalled then
		return
	end
	self.hooksInstalled = true

	HookFaction(_G["TargetFrame"])
	HookFaction(_G["FocusFrame"])
	ForEachBossFrame(HookFaction)
end

function TargetFrameLayout:MigrateLegacySetting()
	if ns.global.targetFrameLayoutMigrated then
		return
	end
	ns.global.targetFrameLayoutMigrated = true
	local legacy = ns.db.classColors and ns.db.classColors.colorReputation
	if legacy then
		ns.db.targetFrameLayout.enable = true
	end
end

function TargetFrameLayout:OnInitialize()
	self:MigrateLegacySetting()
end

function TargetFrameLayout:RegisterModuleEvents()
	if eventsRegistered then
		return
	end
	eventsRegistered = true
	self:TrackEvent(eventHandles, "PLAYER_ENTERING_WORLD", "ScheduleRefreshAll")
	self:TrackEvent(eventHandles, "PLAYER_TARGET_CHANGED", "ScheduleRefreshAll")
	self:TrackEvent(eventHandles, "PLAYER_FOCUS_CHANGED", "ScheduleRefreshAll")
	self:TrackEvent(eventHandles, "UNIT_FACTION", "ScheduleRefreshAllUnit")
	self:TrackEvent(eventHandles, "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "ScheduleRefreshAll")
end

function TargetFrameLayout:ScheduleRefreshAll()
	scheduleRefreshAll()
end

function TargetFrameLayout:ScheduleRefreshAllUnit(unit)
	if unit and not IsTargetLayoutUnit(unit) then
		return
	end
	scheduleRefreshAll()
end

function TargetFrameLayout:UnregisterModuleEvents()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
end

function TargetFrameLayout:OnEnable()
	self:InstallHooks()
	self:RegisterModuleEvents()
	self:RefreshAll()
end

function TargetFrameLayout:OnDisable()
	self:UnregisterModuleEvents()
	self:RefreshAll()
end

function TargetFrameLayout:OnSettingChanged(key)
	if key == "enable" then
		-- ApplyModuleSetting owns enable lifecycle.
		return
	end
	self:RefreshAll()
end

function TargetFrameLayout:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Player-Style Target Frame"], L["Hide the reaction-coloured strip on Target, Focus, and Boss frames and move the Target name beside the portrait to match the player frame."])
end
