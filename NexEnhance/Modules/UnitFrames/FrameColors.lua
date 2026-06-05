--[[
	NexEnhance - FrameColors
	-------------------------------------------------------------------------
	Tints the artwork of the default Blizzard unit frames and HUD resources
	with a colour of the player's choosing - black, a dark grey, or anything
	else - so the frames stop looking like polished gold and blend into a
	darker UI.

	Covered (everything SpartanUI tints on the *default* Blizzard frames):
	  * Unit-frame borders: player (+ alternate-power, vehicle), pet, target,
	    target-of-target, focus, focus-of-target, and the raid boss frames.
	  * Player portrait corner status icon and the legacy alternate-mana borders.
	  * Class resource bars: combo points (rogue/feral), runes (DK), chi (monk),
	    arcane charges (mage), soul shards (warlock), holy power (paladin) and
	    essence (evoker) - both the player-frame bars and the personal-resource
	    nameplate copies.
	  * The default cast bars (player/target/focus), totem bar and minimap compass.

	Inspired by SpartanUI's frame "theme" colour, but driven by events/hooks
	instead of a per-frame OnUpdate (SUI re-applies every frame every tick,
	which is wasteful). Each border/resource only re-skins at well-known points,
	so we re-tint exactly there:
	  * Player border       -> PlayerFrame_UpdateArt re-atlases it.
	  * Target/Focus/Boss   -> TargetFrameMixin:CheckClassification re-atlases it.
	  * Class resources      -> the per-class UpdatePower / UpdateRunes repaint.
	  * Everything else (pet, ToT, totems, minimap, first appearance) -> a light
	    event refresh.

	Mechanism: borders use SetDesaturated(true) + SetVertexColor (so the gold
	greyscales then multiplies our colour); flat textures (resources, portrait
	corner, compass) just take SetVertexColor. Disabling restores white.

	Taint-safe: only hooksecurefunc + SetVertexColor / SetDesaturated on
	(unprotected) textures, and forbidden frames are skipped.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local L = ns.L
local F = ns.F

local _G = _G
local ipairs = ipairs
local select = select
local UnitClass = UnitClass
local hooksecurefunc = hooksecurefunc

ns:RegisterDefaults({
	frameColors = {
		enable = false,
		-- "AARRGGBB" hex (Blizzard colour-swatch format). Default = solid black.
		color = "ff000000",
	},
})

local FrameColors = ns:NewModule("FrameColors", "frameColors", { group = "general", title = L["Frame Colour"], order = 10 })

-- Cached 0-1 colour, refreshed only when the swatch changes (no per-call parse).
local cr, cg, cb = 0, 0, 0
local playerClass
local applyClassPower -- function(enabled) set up for the player's class, or nil

local function UpdateColor()
	cr, cg, cb = F.HexToRGBA(ns.db.frameColors.color or "ff000000")
end

-- Walk a chain of nested fields, bailing out the moment one is missing.
local function Field(obj, ...)
	for i = 1, select("#", ...) do
		if not obj then return nil end
		obj = obj[select(i, ...)]
	end
	return obj
end

-- Metal border art: desaturate so the gold greyscales, then multiply our colour.
local function PaintBorder(tex, enabled)
	if not tex then return end
	if tex.SetDesaturated then tex:SetDesaturated(enabled) end
	if enabled then
		tex:SetVertexColor(cr, cg, cb)
	else
		tex:SetVertexColor(1, 1, 1)
	end
end

-- Flat textures (resources, portrait corner, compass): straight vertex colour.
local function PaintTint(tex, enabled)
	if not tex then return end
	if enabled then
		tex:SetVertexColor(cr, cg, cb)
	else
		tex:SetVertexColor(1, 1, 1)
	end
end

-- ---------------------------------------------------------------------------
-- Class resource bars (pooled BG textures, per-class shapes)
-- ---------------------------------------------------------------------------
-- Combo-style bars expose a classResourceButtonPool of buttons; each button
-- carries differently-named background textures depending on the class.
local RESOURCE_KEYS = {
	ROGUE = { "BGActive", "BGInactive", "BGShadow" },
	DRUID = { "BG_Active", "BG_Inactive", "BG_Shadow" },
	MAGE = { "ArcaneBG", "ArcaneBGShadow" },
	WARLOCK = { "Background" },
	MONK = { "Chi_BG", "Chi_BG_Active" },
}

local function TintPool(frameName, keys, enabled)
	local frame = _G[frameName]
	if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
	local pool = frame.classResourceButtonPool
	if not (pool and pool.EnumerateActive) then return end
	for bar in pool:EnumerateActive() do
		for i = 1, #keys do
			PaintTint(bar[keys[i]], enabled)
		end
		if bar.isCharged then
			PaintTint(bar.ChargedFrameActive, enabled)
		end
	end
end

local function TintPaladin(frameName, enabled)
	local frame = _G[frameName]
	if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
	PaintTint(frame.Background, enabled)
end

local function TintRunes(frameName, enabled)
	local frame = _G[frameName]
	if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
	for i = 1, 6 do
		local rune = frame["Rune" .. i]
		if rune then
			PaintTint(rune.BG_Active, enabled)
			PaintTint(rune.BG_Inactive, enabled)
			PaintTint(rune.BG_Shadow, enabled)
		end
	end
end

local function TintEssence(frameName, enabled)
	local frame = _G[frameName]
	if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
	local pool = frame.classResourceButtonPool
	if not (pool and pool.EnumerateActive) then return end
	for bar in pool:EnumerateActive() do
		local done = bar.EssenceFillDone
		if done then
			PaintTint(done.CircBG, enabled)
			PaintTint(done.CircBGActive, enabled)
		end
	end
end

local function TintTotems(enabled)
	local frame = _G["TotemFrame"]
	if not frame or not frame.totemPool or not frame.totemPool.EnumerateActive then return end
	for totem in frame.totemPool:EnumerateActive() do
		PaintTint(totem.Border, enabled)
	end
end

-- ---------------------------------------------------------------------------
-- Border helpers
-- ---------------------------------------------------------------------------
local function PaintTargetStyle(frame, enabled)
	if not frame then return end
	PaintBorder(Field(frame, "TargetFrameContainer", "FrameTexture"), enabled)
end

local function ForEachBossFrame(callback)
	local container = _G["BossTargetFrameContainer"]
	local frames = container and container.BossTargetFrames
	if not frames then return end
	for _, frame in ipairs(frames) do
		if frame then callback(frame) end
	end
end

-- Default cast bars (player / target / focus): metal Border + flat Background.
local function PaintCastBar(bar, enabled)
	if not bar then return end
	PaintBorder(bar.Border, enabled)
	PaintTint(bar.Background, enabled)
end

local function PaintPlayer(enabled)
	local PlayerFrame = _G["PlayerFrame"]
	PaintBorder(Field(PlayerFrame, "PlayerFrameContainer", "FrameTexture"), enabled)
	PaintBorder(Field(PlayerFrame, "PlayerFrameContainer", "AlternatePowerFrameTexture"), enabled)
	PaintBorder(Field(PlayerFrame, "PlayerFrameContainer", "VehicleFrameTexture"), enabled)
	PaintTint(Field(PlayerFrame, "PlayerFrameContent", "PlayerFrameContentContextual", "PlayerPortraitCornerIcon"), enabled)
	-- Legacy alternate-mana bar borders (still present on some specs/vehicles).
	PaintBorder(_G["PlayerFrameAlternateManaBarBorder"], enabled)
	PaintBorder(_G["PlayerFrameAlternateManaBarLeftBorder"], enabled)
	PaintBorder(_G["PlayerFrameAlternateManaBarRightBorder"], enabled)
end

-- Re-tint (or restore) every covered element in one pass.
local function ApplyAll(enabled)
	PaintPlayer(enabled)

	PaintBorder(_G["PetFrameTexture"], enabled)

	PaintTargetStyle(_G["TargetFrame"], enabled)
	PaintBorder(Field(_G["TargetFrameToT"], "FrameTexture"), enabled)

	PaintTargetStyle(_G["FocusFrame"], enabled)
	PaintBorder(Field(_G["FocusFrameToT"], "FrameTexture"), enabled)

	ForEachBossFrame(function(frame)
		PaintTargetStyle(frame, enabled)
	end)

	PaintCastBar(_G["PlayerCastingBarFrame"], enabled)
	PaintCastBar(_G["TargetFrameSpellBar"], enabled)
	PaintCastBar(_G["FocusFrameSpellBar"], enabled)

	PaintTint(_G["MinimapCompassTexture"], enabled)

	if applyClassPower then applyClassPower(enabled) end
	TintTotems(enabled)
end

function FrameColors:Refresh()
	ApplyAll(ns.db.frameColors.enable)
end

-- ---------------------------------------------------------------------------
-- Hooks: re-apply our tint right after Blizzard re-skins something.
-- ---------------------------------------------------------------------------
local function HookClassification(frame)
	if not frame or frame.nexFrameColorHooked then return end
	if type(frame.CheckClassification) ~= "function" then return end
	frame.nexFrameColorHooked = true
	hooksecurefunc(frame, "CheckClassification", function(f)
		if ns.db.frameColors.enable then
			PaintTargetStyle(f, true)
		end
	end)
end

-- Cast bars are shown fresh on each cast; re-tint on show so they keep our colour.
local function HookCastBar(frameName)
	local bar = _G[frameName]
	if not bar or bar.nexFrameColorHooked then return end
	bar.nexFrameColorHooked = true
	bar:HookScript("OnShow", function(self)
		if ns.db.frameColors.enable then PaintCastBar(self, true) end
	end)
end

-- Post-hook a frame method by global name, if both exist.
local function HookMethod(frameName, method, fn)
	local frame = _G[frameName]
	if frame and type(frame[method]) == "function" then
		hooksecurefunc(frame, method, fn)
	end
end

-- Wire up the player's class-resource bars: pick the right frames/keys, build
-- the apply closure (used by ApplyAll), and hook the repaint so changing
-- resources re-tints immediately.
local function SetupClassPower()
	local class = playerClass
	if not class then return end

	local function OnRepaint()
		if ns.db.frameColors.enable and applyClassPower then applyClassPower(true) end
	end

	local keys = RESOURCE_KEYS[class]
	if keys then
		local hud, nameplate
		if class == "ROGUE" then
			hud, nameplate = "RogueComboPointBarFrame", "ClassNameplateBarRogueFrame"
		elseif class == "DRUID" then
			hud, nameplate = "DruidComboPointBarFrame", "ClassNameplateBarFeralDruidFrame"
		elseif class == "MAGE" then
			hud, nameplate = "MageArcaneChargesFrame", "ClassNameplateBarMageFrame"
		elseif class == "WARLOCK" then
			hud, nameplate = "WarlockPowerFrame", "ClassNameplateBarWarlockFrame"
		elseif class == "MONK" then
			hud, nameplate = "MonkHarmonyBarFrame", "ClassNameplateBarWindwalkerMonkFrame"
		end
		applyClassPower = function(enabled)
			TintPool(hud, keys, enabled)
			TintPool(nameplate, keys, enabled)
		end
		-- Mage repaints through MagePowerBar; the rest repaint on their own frame.
		HookMethod(class == "MAGE" and "MagePowerBar" or hud, "UpdatePower", OnRepaint)
		HookMethod(nameplate, "UpdatePower", OnRepaint)
	elseif class == "PALADIN" then
		applyClassPower = function(enabled)
			TintPaladin("PaladinPowerBarFrame", enabled)
			TintPaladin("ClassNameplateBarPaladinFrame", enabled)
		end
		HookMethod("PaladinPowerBarFrame", "UpdatePower", OnRepaint)
		HookMethod("ClassNameplateBarPaladinFrame", "UpdatePower", OnRepaint)
	elseif class == "DEATHKNIGHT" then
		applyClassPower = function(enabled)
			TintRunes("RuneFrame", enabled)
			TintRunes("DeathKnightResourceOverlayFrame", enabled)
		end
		HookMethod("RuneFrame", "UpdateRunes", OnRepaint)
	elseif class == "EVOKER" then
		applyClassPower = function(enabled)
			TintEssence("EssencePlayerFrame", enabled)
			TintEssence("ClassNameplateBarDracthyrFrame", enabled)
		end
		HookMethod("EssencePlayerFrame", "UpdatePower", OnRepaint)
	end
end

function FrameColors:InstallHooks()
	if self.hooksInstalled then return end
	self.hooksInstalled = true

	-- Player border is re-atlased here on every player <-> vehicle / alt-power swap.
	if _G["PlayerFrame_UpdateArt"] then
		hooksecurefunc("PlayerFrame_UpdateArt", function()
			if ns.db.frameColors.enable then PaintPlayer(true) end
		end)
	end

	-- Target / Focus / Boss re-atlas their border in CheckClassification.
	HookClassification(_G["TargetFrame"])
	HookClassification(_G["FocusFrame"])
	ForEachBossFrame(HookClassification)

	-- Default cast bars re-show on each cast.
	HookCastBar("PlayerCastingBarFrame")
	HookCastBar("TargetFrameSpellBar")
	HookCastBar("FocusFrameSpellBar")

	SetupClassPower()
end

function FrameColors:OnEnable()
	UpdateColor()
	playerClass = select(2, UnitClass("player"))
	self:InstallHooks()

	-- Catch first appearance of pet / ToT / totems and reloads.
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "Refresh")
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "Refresh")
	self:RegisterEvent("PLAYER_FOCUS_CHANGED", "Refresh")
	self:RegisterEvent("UNIT_PET", "Refresh")
	self:RegisterEvent("PLAYER_TOTEM_UPDATE", "Refresh")
	self:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT", "Refresh")

	self:Refresh()
end

function FrameColors:OnSettingChanged()
	UpdateColor()
	if ns.db.frameColors.enable then
		self:InstallHooks()
	end
	-- Apply the new colour, or restore the default art when toggled off.
	self:Refresh()
end

function FrameColors:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Frame Colour"], L["Tint the default unit frames and HUD elements (player, pet, target, focus, boss, class resources, cast bars, totems and the minimap) with a colour of your choice."])
	local _, colorInit = builder:Color(category, self, "color", L["Border Colour"], L["The colour applied to the unit-frame borders. Pick black for a clean dark look, or any colour you like."])

	builder:DependsOn(colorInit, enableInit)
end
