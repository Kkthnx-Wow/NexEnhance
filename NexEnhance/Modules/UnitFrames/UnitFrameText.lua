--[[
	NexEnhance - Unit Frame Text
	-------------------------------------------------------------------------
	Optional white name + level on Blizzard Player / Target / Focus / Boss
	frames — the gold GameFontNormalSmall default many UIs replace.

	Blizzard paths (12.0.7):
	  * Player level: PlayerFrame_UpdateLevel() tints PlayerLevelText gold or
	    green when effective ≠ real level.
	  * Target level: TargetFrameMixin:CheckLevel() on LevelText (gold for
	    friendlies, difficulty tint for attackable).
	  * Names: GameFontNormalSmall yellow from the font; UnitFrame_Update only
	    sets text, not vertex colour.

	We post-hook those update paths and SetVertexColor(1,1,1) on name FontStrings.
	Player level goes white too. Target / Focus / Boss level stays on Level Colours;
	that module swaps the default yellow difficulty band to white when this option
	is on (red / orange / green / grey unchanged).

	Standard 5-man party portraits (PartyMemberFrame, not compact raid-style
	party) also get white names — same GameFontNormalSmall gold default. Pet and
	target-of-target names too. Compact raid/party frames are left alone.

	Default OFF. Lives under Unit Frames.
--]]

local _, ns = ...
local F, L = ns.F, ns.L

local _G = _G
local hooksecurefunc = hooksecurefunc
local ipairs = ipairs
local format = string.format
local C_Timer = C_Timer

local WHITE_R, WHITE_G, WHITE_B = 1, 1, 1
local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0

ns:RegisterDefaults({
	unitFrameText = {
		enable = true,
		whiteNameLevel = false,
	},
})

local UnitFrameText = ns:NewModule("UnitFrameText", "unitFrameText", {
	group = "unitframes",
	title = L["Unit Frame Text"],
	order = 16,
})

local eventHandles = {}
local eventsRegistered = false
local hookedPartyFrame = false

-- ---------------------------------------------------------------------------
-- Frame set (HUD + standard party portraits; not compact raid/party).
-- ---------------------------------------------------------------------------
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

local function ForEachFrame(callback)
	local player = _G["PlayerFrame"]
	if player then
		callback(player)
	end
	local target = _G["TargetFrame"]
	if target then
		callback(target)
		if target.totFrame then
			callback(target.totFrame)
		end
	end
	local focus = _G["FocusFrame"]
	if focus then
		callback(focus)
		if focus.totFrame then
			callback(focus.totFrame)
		end
	end
	local pet = _G["PetFrame"]
	if pet then
		callback(pet)
	end
	ForEachBossFrame(callback)
end

local function IsTrackedUnitFrame(frame)
	if not frame or not frame.unit then
		return false
	end
	local unit = frame.unit
	if unit == "player" or unit == "vehicle" or unit == "target" or unit == "focus" then
		return true
	end
	if unit == "pet" or unit == "targettarget" or unit == "focustarget" then
		return true
	end
	return unit:match("^boss%d+$") ~= nil
end

local function ShouldApply()
	local db = ns.db.unitFrameText
	return db.enable and db.whiteNameLevel
end

local function RefreshLevelColors()
	if not ns.db.levelColors or not ns.db.levelColors.enable then
		return
	end
	local levelColors = ns:GetModule("LevelColors")
	if levelColors and levelColors.RefreshEvent then
		levelColors:RefreshEvent()
	end
end

-- ---------------------------------------------------------------------------
-- Apply / restore
-- ---------------------------------------------------------------------------
local function WhitenNameFontString(fontString)
	if fontString then
		fontString:SetVertexColor(WHITE_R, WHITE_G, WHITE_B)
	end
end

local function RestoreNameFontString(fontString)
	if fontString then
		fontString:SetVertexColor(GOLD_R, GOLD_G, GOLD_B)
	end
end

local function ApplyWhiteName(frame)
	if not frame or not frame.name then
		return
	end
	WhitenNameFontString(frame.name)
end

-- PartyMemberFrameTemplate only — compact frames carry groupType.
local function IsPartyMemberHudFrame(frame)
	if not frame or frame.groupType then
		return false
	end
	if frame.unitToken and frame.unitToken:match("^party%d+$") then
		return true
	end
	return frame.layoutIndex ~= nil and frame.Name ~= nil and frame:GetParent() == _G.PartyFrame
end

local function ForEachPartyMember(callback)
	local partyFrame = _G.PartyFrame
	if not partyFrame or not partyFrame.PartyMemberFramePool then
		return
	end
	for member in partyFrame.PartyMemberFramePool:EnumerateActive() do
		callback(member)
	end
end

local function EnsurePartyMemberHooked(frame)
	if not frame or frame.nexUnitFrameTextHooked then
		return
	end
	frame.nexUnitFrameTextHooked = true
	if type(frame.UpdateMember) == "function" then
		hooksecurefunc(frame, "UpdateMember", function(self)
			if ShouldApply() then
				ApplyWhiteName(self)
			end
		end)
	end
	if type(frame.UpdateArt) == "function" then
		hooksecurefunc(frame, "UpdateArt", function(self)
			if ShouldApply() then
				ApplyWhiteName(self)
			end
		end)
	end
end

local function RefreshPartyMembers()
	ForEachPartyMember(function(member)
		EnsurePartyMemberHooked(member)
		if ShouldApply() then
			ApplyWhiteName(member)
		else
			RestoreNameFontString(member.name)
		end
	end)
end

local function InstallPartyFrameHooks()
	if hookedPartyFrame then
		return
	end
	local partyFrame = _G.PartyFrame
	if not partyFrame then
		return
	end

	local function AfterPartyRefresh()
		RefreshPartyMembers()
	end

	if type(partyFrame.InitializePartyMemberFrames) == "function" then
		hooksecurefunc(partyFrame, "InitializePartyMemberFrames", function()
			C_Timer.After(0, AfterPartyRefresh)
		end)
	end
	if type(partyFrame.UpdatePartyFrames) == "function" then
		hooksecurefunc(partyFrame, "UpdatePartyFrames", AfterPartyRefresh)
	end
	if type(partyFrame.UpdateMemberFrames) == "function" then
		hooksecurefunc(partyFrame, "UpdateMemberFrames", AfterPartyRefresh)
	end

	hookedPartyFrame = true
end

local function ApplyWhitePlayerLevel()
	local levelText = _G["PlayerLevelText"]
	if not levelText or not levelText:IsShown() then
		return
	end
	levelText:SetVertexColor(WHITE_R, WHITE_G, WHITE_B)
end

local function ApplyWhiteText(frame)
	if frame == _G["PlayerFrame"] then
		ApplyWhiteName(frame)
		ApplyWhitePlayerLevel()
		return
	end

	if frame.TargetFrameContent then
		ApplyWhiteName(frame)
		return
	end

	-- Pet, ToT, party portraits — name only (no level on these frames).
	ApplyWhiteName(frame)
end

local function Refresh()
	if not ShouldApply() then
		return
	end
	ForEachFrame(ApplyWhiteText)
	RefreshPartyMembers()
	RefreshLevelColors()
end

local function RestoreBlizzardText()
	if _G.PlayerFrame_UpdateLevel then
		_G.PlayerFrame_UpdateLevel()
	end
	ForEachFrame(function(frame)
		if type(frame.CheckLevel) == "function" then
			frame:CheckLevel()
		end
		if frame.unit and _G.UnitFrame_Update then
			_G.UnitFrame_Update(frame)
		end
		RestoreNameFontString(frame.name)
	end)
	RefreshPartyMembers()
	if ns.db.levelColors and ns.db.levelColors.enable then
		local levelColors = ns:GetModule("LevelColors")
		if levelColors and levelColors.RefreshEvent then
			levelColors:RefreshEvent()
		end
	end
end

-- ---------------------------------------------------------------------------
-- Hooks (once). Party pool frames store nexUnitFrameTextHooked — same pattern as HideDpsRole.
-- ---------------------------------------------------------------------------
function UnitFrameText:InstallHooks()
	if self.hooksInstalled then
		return
	end
	self.hooksInstalled = true

	if _G.PlayerFrame_UpdateLevel then
		hooksecurefunc("PlayerFrame_UpdateLevel", function()
			if ShouldApply() then
				ApplyWhitePlayerLevel()
			end
		end)
	end

	hooksecurefunc("UnitFrame_Update", function(self)
		if not ShouldApply() then
			return
		end
		if IsTrackedUnitFrame(self) or IsPartyMemberHudFrame(self) then
			ApplyWhiteName(self)
		end
	end)

	InstallPartyFrameHooks()

	ForEachFrame(function(frame)
		if type(frame.CheckLevel) ~= "function" then
			return
		end
		hooksecurefunc(frame, "CheckLevel", function(f)
			if not ShouldApply() then
				return
			end
			ApplyWhiteName(f)
		end)
	end)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function UnitFrameText:RefreshEvent()
	Refresh()
end

function UnitFrameText:GROUP_ROSTER_UPDATE()
	self:RefreshEvent()
end

function UnitFrameText:RegisterModuleEvents()
	if eventsRegistered then
		return
	end
	eventsRegistered = true
	self:TrackEvent(eventHandles, "PLAYER_ENTERING_WORLD", "RefreshEvent")
	self:TrackEvent(eventHandles, "PLAYER_TARGET_CHANGED", "RefreshEvent")
	self:TrackEvent(eventHandles, "PLAYER_FOCUS_CHANGED", "RefreshEvent")
	self:TrackEvent(eventHandles, "GROUP_ROSTER_UPDATE", "GROUP_ROSTER_UPDATE")
end

function UnitFrameText:UnregisterModuleEvents()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
end

function UnitFrameText:OnEnable()
	self:InstallHooks()
	self:RegisterModuleEvents()
	Refresh()

	ns.Debug.BindModule(self, "unitFrameText", {
		title = L["Unit Frame Text"],
		expectations = {
			{
				name = "hooks when enabled",
				test = function()
					return UnitFrameText.hooksInstalled
				end,
			},
		},
		dump = function()
			local cfg = ns.db.unitFrameText
			F.Print(format("  enable=%s whiteNameLevel=%s hooks=%s", tostring(cfg.enable), tostring(cfg.whiteNameLevel), tostring(UnitFrameText.hooksInstalled)))
		end,
	})
end

function UnitFrameText:OnDisable()
	self:UnregisterModuleEvents()
	RestoreBlizzardText()
end

function UnitFrameText:OnSettingChanged(key)
	if key == "enable" then
		-- ApplyModuleSetting owns enable lifecycle.
		return
	end
	self:InstallHooks()
	if ShouldApply() then
		Refresh()
	else
		RestoreBlizzardText()
	end
end

function UnitFrameText:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Unit Frame Text"], L["Cosmetic tweaks for Blizzard unit frame name and level text."])
	local _, whiteInit = builder:Checkbox(category, self, "whiteNameLevel", L["White Name and Level"], L["Show unit names in white instead of the default gold on player, target, focus, boss, pet, target-of-target, and standard party portraits. Player level goes white too. Target level keeps Level Colours difficulty tints, but the default yellow band becomes white instead. Compact raid/party frames are unchanged."])

	builder:DependsOn(whiteInit, enableInit)
end
