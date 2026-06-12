--[[
	NexEnhance - Level Colours
	-------------------------------------------------------------------------
	Improves the Target / Focus / Boss frame LEVEL display:
	  * Colours the level number by classic creature difficulty (red -> orange
	    -> yellow -> green -> grey relative to YOUR level) via
	    GetCreatureDifficultyColor(UnitEffectiveLevel(unit)).
	  * Optional "Always Show Level": replaces Blizzard's skull (HighLevelTexture,
	    shown when the level is "too high to tell") with the actual number, or a
	    red "??" when the game genuinely hides it - so you always get info instead
	    of a bare skull icon (the KkthnxUI fulllevel approach). Also appends
	    classification markers - "Boss" for world bosses, "R+" rare-elite,
	    "+" elite, "R" rare.

	Why: modern Blizzard colours the level via the *new* content-difficulty
	system (C_PlayerInfo.GetContentDifficultyCreatureForPlayer + GetDifficultyColor)
	which only buckets trivial/easy/etc, and falls back to a skull. Many players
	prefer the classic level-vs-level colour and a readable number. We improve,
	not replace.

	Design (researched from BlizzardInterfaceCode,
	Blizzard_UIPanels_Game/Mainline/TargetFrame.lua - TargetFrameMixin):
	  * TargetFrameMixin:CheckLevel() sets the text/colour of
	    frame.TargetFrameContent.TargetFrameContentMain.LevelText and toggles
	    frame.TargetFrameContent.TargetFrameContentContextual.HighLevelTexture
	    (the skull). It runs on target change, UNIT_LEVEL and UNIT_FACTION.
	    FocusFrame and the Boss frames (BossTargetFrameMixin) share the SAME
	    mixin/method.
	  * We post-hook CheckLevel (hooksecurefunc) and adjust the LevelText /
	    skull AFTER Blizzard. We never replace CheckLevel and never touch
	    cast/health logic. We only call cosmetic FontString/Texture methods
	    (SetText / SetVertexColor / Show / Hide) - never protected APIs.
	  * These frames are Edit Mode-managed, so - like the cast bar - we do NOT
	    write any fields onto them. Hooks are installed exactly once via a
	    module-level flag over the known frames (all exist, hidden, from login).
	  * Secret-safe (Patch 12.0): UnitEffectiveLevel / UnitIs*BattlePet* can
	    return Secret values in instances/combat. We gate every read with
	    NexEnhance's shared F.IsSecret helper before any boolean test or
	    comparison, and simply leave Blizzard's display when a value is Secret.

	Default ON. Lives under Unit Frames.
--]]

local _, ns = ...
local F, L = ns.F, ns.L

local _G = _G
local hooksecurefunc = hooksecurefunc
local ipairs = ipairs

local UnitEffectiveLevel = UnitEffectiveLevel
local UnitClassification = UnitClassification
local UnitIsWildBattlePet = UnitIsWildBattlePet
local UnitIsBattlePetCompanion = UnitIsBattlePetCompanion
local UnitBattlePetLevel = UnitBattlePetLevel

-- Follow Blizzard's own palette/idiom for the text we add: gold NORMAL_FONT_COLOR
-- for the rare/elite/boss markers and RED_FONT_COLOR for an unknown level. These
-- are ColorMixin globals; WrapTextInColorCode() is Blizzard's standard helper.
local BOSS_STRING = _G["BOSS"] or "Boss"
local MARKER_COLOR = NORMAL_FONT_COLOR or CreateColor(1, 0.82, 0)
local UNKNOWN_COLOR = RED_FONT_COLOR or CreateColor(1, 0.1, 0.1)
-- Prefer the classic creature scale; fall back to the quest difficulty scale
-- (same red->grey-vs-player palette, confirmed present) so a missing global can
-- never hard-error on the call.
local GetCreatureDifficultyColor = GetCreatureDifficultyColor or GetQuestDifficultyColor
local IsSecret = F.IsSecret

ns:RegisterDefaults({
	levelColors = {
		enable = true,
		alwaysShowLevel = true,
	},
})

local LevelColors = ns:NewModule("LevelColors", "levelColors", { group = "unitframes", title = L["Level Colours"], order = 15 })

-- ---------------------------------------------------------------------------
-- Region resolution
-- ---------------------------------------------------------------------------
local function GetLevelRegions(frame)
	local content = frame and frame.TargetFrameContent
	if not content then
		return nil
	end
	local main = content.TargetFrameContentMain
	local contextual = content.TargetFrameContentContextual
	local levelText = main and main.LevelText
	local highLevel = contextual and contextual.HighLevelTexture
	return levelText, highLevel
end

-- Returns a non-secret numeric level (may be <= 0 for "too high to tell"), or
-- nil when a read is Secret / unavailable (so the caller leaves Blizzard alone).
local function GetUnitLevel(unit)
	local isWild = UnitIsWildBattlePet(unit)
	if IsSecret(isWild) then
		return nil
	end

	local isCompanion = false
	if not isWild then
		isCompanion = UnitIsBattlePetCompanion(unit)
		if IsSecret(isCompanion) then
			return nil
		end
	end

	local level
	if isWild or isCompanion then
		level = UnitBattlePetLevel(unit)
	else
		level = UnitEffectiveLevel(unit)
	end

	if IsSecret(level) or not level then
		return nil
	end
	return level
end

local function ColorLevelText(levelText, level)
	if not GetCreatureDifficultyColor then
		return
	end
	local color = GetCreatureDifficultyColor(level)
	if color then
		levelText:SetVertexColor(color.r, color.g, color.b)
	end
end

-- Difficulty colour as an inline |cffRRGGBB escape, so it composes with the
-- classification markers in a single SetText (white vertex colour underneath).
-- Uses the shared F.RGBToHex helper rather than rebuilding the escape by hand.
local function GetDifficultyHex(level)
	local color = GetCreatureDifficultyColor and GetCreatureDifficultyColor(level)
	if color then
		return "|c" .. F.RGBToHex(color.r, color.g, color.b)
	end
	return "|cffffffff"
end

-- Returns the suffix to append for the unit's classification ("R", "+", "R+"),
-- or nil. Secret-safe: leaves it off when the read is restricted.
local function GetClassificationSuffix(unit)
	local class = UnitClassification(unit)
	if IsSecret(class) then
		return nil
	end
	if class == "rareelite" then
		return MARKER_COLOR:WrapTextInColorCode("R+")
	elseif class == "elite" then
		return MARKER_COLOR:WrapTextInColorCode("+")
	elseif class == "rare" then
		return MARKER_COLOR:WrapTextInColorCode("R")
	end
	return nil
end

-- Is this unit a world boss? Secret-safe (returns false when restricted).
local function IsWorldBoss(unit)
	local class = UnitClassification(unit)
	if IsSecret(class) then
		return false
	end
	return class == "worldboss"
end

-- ---------------------------------------------------------------------------
-- Core: re-colour the level and (optionally) replace the skull with a number.
-- ---------------------------------------------------------------------------
local function ApplyLevel(frame)
	local levelText, highLevel = GetLevelRegions(frame)
	if not levelText then
		return
	end

	local unit = frame.unit
	if not unit then
		return
	end

	local db = ns.db.levelColors
	local level = GetUnitLevel(unit)

	if not db.alwaysShowLevel then
		-- Colour-only mode: just re-tint whatever Blizzard already shows and
		-- leave the skull behaviour untouched.
		if levelText:IsShown() and level and level > 0 then
			ColorLevelText(levelText, level)
		end
		return
	end

	-- Always-show mode: never display the skull.
	if not level then
		-- Secret read (instance/combat): don't fight it, keep Blizzard's display.
		return
	end

	if highLevel then
		highLevel:Hide()
	end

	-- World bosses replace the number entirely with a gold "Boss".
	if IsWorldBoss(unit) then
		levelText:SetVertexColor(1, 1, 1)
		levelText:SetText(MARKER_COLOR:WrapTextInColorCode(BOSS_STRING))
		levelText:Show()
		return
	end

	-- Build the level segment, then append the rare/elite marker. We embed the
	-- colours inline and keep the vertex colour white so both compose cleanly.
	local str
	if level > 0 then
		str = GetDifficultyHex(level) .. level .. "|r"
	else
		-- The game genuinely hides this unit's level (-1). Show "??" (red),
		-- which carries the same "much higher than you" cue as the skull.
		str = UNKNOWN_COLOR:WrapTextInColorCode("??")
	end

	local suffix = GetClassificationSuffix(unit)
	if suffix then
		str = str .. suffix
	end

	levelText:SetVertexColor(1, 1, 1)
	levelText:SetText(str)
	levelText:Show()
end

-- ---------------------------------------------------------------------------
-- Frame set: Target, Focus, and the five Boss frames.
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
	local target = _G["TargetFrame"]
	if target then
		callback(target)
	end
	local focus = _G["FocusFrame"]
	if focus then
		callback(focus)
	end
	ForEachBossFrame(callback)
end

local function Refresh()
	if not ns.db.levelColors.enable then
		return
	end
	ForEachFrame(ApplyLevel)
end

-- ---------------------------------------------------------------------------
-- Hooks (installed once over the known frames; no fields written onto them).
-- ---------------------------------------------------------------------------
local function HookFrame(frame)
	if type(frame.CheckLevel) ~= "function" then
		return
	end
	hooksecurefunc(frame, "CheckLevel", function(f)
		if ns.db.levelColors.enable then
			ApplyLevel(f)
		end
	end)
end

function LevelColors:InstallHooks()
	if self.hooksInstalled then
		return
	end
	self.hooksInstalled = true
	ForEachFrame(HookFrame)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function LevelColors:RefreshEvent()
	Refresh()
end

function LevelColors:OnEnable()
	self:InstallHooks()

	-- CheckLevel covers target/focus changes; these catch combat-exit (when
	-- secret reads clear) and initial state where CheckLevel may not re-fire.
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "RefreshEvent")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "RefreshEvent")
	self:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT", "RefreshEvent")

	Refresh()
end

function LevelColors:OnSettingChanged()
	self:InstallHooks()
	Refresh()
end

function LevelColors:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Level Colours"], L["Colour the Target / Focus / Boss level number by classic difficulty (red to grey vs your level) instead of Blizzard's trivial/easy buckets."])
	local _, alwaysInit = builder:Checkbox(category, self, "alwaysShowLevel", L["Always Show Level"], L["Replace the skull shown on high-level targets with the actual level number (or a red ?? when the game hides it), so you always get info."])

	builder:DependsOn(alwaysInit, enableInit)
end
