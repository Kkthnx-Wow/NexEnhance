--[[
	NexEnhance - UI Scale
	-------------------------------------------------------------------------
	Pixel-perfect auto-scaling for UIParent. Picks the scale that maps 1 UI
	pixel onto 1 physical pixel for the current resolution, and exposes the
	matching pixel multiplier (C.Mult) that the backdrop/border system uses
	to draw crisp 1px borders at any resolution.

	Ideal scale = clamp(768 / physicalScreenHeight, 0.4, 1.15) - full float,
	no 2-decimal Round. Mult = perfect / scale.

	Computed in OnInitialize so C.Mult is correct before any module builds a
	backdrop, and re-applied on UI_SCALE_CHANGED / DISPLAY_SIZE_CHANGED /
	PLAYER_ENTERING_WORLD.

	Important: apply only via UIParent:SetScale during ADDON_LOADED / out of combat.
	Do not write the uiScale CVar or defer apply to C_Timer.After(0) on login -
	both run after Blizzard_CombatLog initializes and break the chat dock tabs.
	(Blizzard, fix the load order on your end. We tried.)

	While enabled we force useUiScale=0 so Blizzard's Graphics slider does not
	stack on top - two scale systems = UI the size of a postage stamp. We do not
	hide or remove their menu row, we just turn theirs off while we're driving.

	Settings live in the active profile:
	  * enable    - apply our scale to UIParent (off = only compute C.Mult)
	  * autoScale - lock to the pixel-perfect best scale for this resolution
	  * scale     - manual scale used when autoScale is off
--]]

local _, ns = ...
local C, L, F = ns.C, ns.L, ns.F

local min, max, abs, floor = math.min, math.max, math.abs, math.floor
local format = string.format
local pcall = pcall
local GetCVar = GetCVar
local SetCVar = SetCVar
local InCombatLockdown = InCombatLockdown
local UnitAffectingCombat = UnitAffectingCombat
local GetPhysicalScreenSize = GetPhysicalScreenSize
local UIParent = UIParent

ns:RegisterDefaults({
	uiScale = {
		enable = true,
		autoScale = true,
		scale = 0.71,
	},
})

local UIScale = ns:NewModule("UIScale", "uiScale", { group = "general", title = L["UI Scale"], order = 10 })

local MIN_SCALE, MAX_SCALE = 0.40, 1.15

-- Physical screen height (refreshed on resolution / scale events), 768 is the
-- pixel baseline Blizzard's UI is authored against.
local screenHeight = select(2, GetPhysicalScreenSize())

-- Re-entrancy guard: SetScale can fire UI_SCALE_CHANGED mid-apply.
local isScaling = false

local function SetCVarSafe(name, value)
	pcall(SetCVar, name, value)
end

-- NexEnhance scales via UIParent:SetScale. Blizzard's "Use UI Scale" uses the
-- useUiScale + uiScale CVars - if both run, scale stacks or fights. We only
-- flip useUiScale off (never uiScale) and restore the user's choice when disabled.
-- Incident (UIScale, Jun 2026): writing uiScale + next-frame apply broke chat dock.
function UIScale:SyncBlizzardUiScale(cfg)
	if not cfg.enable then
		if self.savedUseUiScale ~= nil then
			SetCVarSafe("useUiScale", self.savedUseUiScale)
			self.savedUseUiScale = nil
		end
		return
	end

	if GetCVar("useUiScale") == "1" then
		if self.savedUseUiScale == nil then
			self.savedUseUiScale = "1"
		end
		SetCVarSafe("useUiScale", "0")
	end
end

-- Exact perfect - no Round(..., 2). Incident (UIScale, Jul 2026): 768/1440~0.5333
-- became 0.53 and soft 1px borders (a bug we have hit before).
local function GetPerfectScale()
	return max(MIN_SCALE, min(MAX_SCALE, 768 / screenHeight))
end

local function GetBestScale()
	return GetPerfectScale()
end

-- Old AutoScale wrote Round(perfect, 2). Swap leftovers back when Auto is on.
local function MigrateTruncatedAutoScale(cfg)
	if not cfg.autoScale then
		return
	end
	local perfect = GetPerfectScale()
	local stored = cfg.scale
	if type(stored) ~= "number" then
		return
	end
	local truncated = floor(perfect * 100 + 0.5) / 100
	if abs(stored - truncated) < 0.0001 and abs(stored - perfect) > 0.0001 then
		cfg.scale = perfect
	end
end

local function GetDisplayScale(cfg)
	if not cfg.enable then
		-- Slider display only, Mult uses the full UIParent float below.
		return F.Round(UIParent:GetScale(), 2)
	end
	if cfg.autoScale then
		return GetBestScale()
	end
	return cfg.scale
end

function UIScale:SyncScaleSetting()
	local setting = self.scaleSetting
	local cfg = ns.db and ns.db.uiScale
	if not setting or not cfg then
		return
	end

	local display = GetDisplayScale(cfg)

	self.syncingScale = true
	setting:SetValue(display)
	self.syncingScale = false

	if cfg.enable and cfg.autoScale then
		cfg.scale = display
	elseif not cfg.enable and self.manualScale then
		cfg.scale = self.manualScale
	end
end

function UIScale:Refresh(pixelOnly)
	local cfg = ns.db.uiScale
	MigrateTruncatedAutoScale(cfg)

	local scale
	if cfg.enable then
		scale = cfg.autoScale and GetBestScale() or cfg.scale
		if cfg.autoScale then
			cfg.scale = scale
		end
	else
		scale = UIParent:GetScale()
	end

	-- Mult always uses live screen height + chosen scale (exact floats).
	C.Mult = (768 / screenHeight) / (scale ~= 0 and scale or 1)

	if cfg.enable and not pixelOnly and not InCombatLockdown() then
		self:SyncBlizzardUiScale(cfg)
		isScaling = true
		UIParent:SetScale(scale)
		isScaling = false
		-- Chat (and anything else) can re-anchor without a /reload.
		ns:TriggerCallback("UIScaleApplied", scale)
	end

	self:SyncScaleSetting()
end

local function ApplyScale()
	-- Always refresh Mult immediately (even in combat). Only SetScale waits.
	UIScale:Refresh(true)
	UIScale:Refresh()

	-- Combat lockdown blocks SetScale, we'll catch up on regen.
	if ns.db.uiScale.enable and InCombatLockdown() then
		UIScale.pending = true
	end
end

local function RefreshScreenSizeAndApply()
	if isScaling then
		return
	end
	screenHeight = select(2, GetPhysicalScreenSize())
	local cfg = ns.db and ns.db.uiScale
	if cfg and cfg.enable and GetCVar("useUiScale") == "1" then
		UIScale:SyncBlizzardUiScale(cfg)
	end
	ApplyScale()
end

function UIScale:UI_SCALE_CHANGED()
	RefreshScreenSizeAndApply()
end

function UIScale:DISPLAY_SIZE_CHANGED()
	RefreshScreenSizeAndApply()
end

function UIScale:PLAYER_ENTERING_WORLD()
	RefreshScreenSizeAndApply()
end

function UIScale:PLAYER_REGEN_ENABLED()
	if self.pending then
		self.pending = nil
		ApplyScale()
	end
end

function UIScale:ForceApply()
	ApplyScale()
end

function UIScale:OnInitialize()
	local cfg = ns.db.uiScale
	MigrateTruncatedAutoScale(cfg)
	self.manualScale = cfg.scale
	ApplyScale()
	-- Scale must stay live before PLAYER_LOGIN, register resolution/combat defer
	-- listeners here even when uiScale.enable is off (C.Mult still tracks UIParent).
	self:RegisterEvent("UI_SCALE_CHANGED")
	self:RegisterEvent("DISPLAY_SIZE_CHANGED")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")

	ns.Debug.BindModule(self, "uiscale", {
		title = L["UI Scale"],
		expectations = {
			{
				name = "C.Mult is positive",
				test = function()
					return C.Mult and C.Mult > 0
				end,
			},
			{
				name = "useUiScale off when NexEnhance scale enabled",
				test = function()
					local db = ns.db and ns.db.uiScale
					if not db or not db.enable then
						return true
					end
					return GetCVar("useUiScale") == "0"
				end,
				detail = function()
					return format("useUiScale=%s", GetCVar("useUiScale") or "?")
				end,
			},
			{
				name = "AutoScale stores exact perfect (not 2dp trunc)",
				test = function()
					local db = ns.db and ns.db.uiScale
					if not db or not db.enable or not db.autoScale then
						return true
					end
					local perfect = GetPerfectScale()
					return abs((db.scale or 0) - perfect) < 0.0001
				end,
				detail = function()
					return format("scale=%.6f perfect=%.6f", ns.db.uiScale.scale or 0, GetPerfectScale())
				end,
			},
		},
		dump = function()
			local db = ns.db.uiScale
			local sh = select(2, GetPhysicalScreenSize())
			F.Print(format("  cfg.enable=%s autoScale=%s scale=%.6f manualScale=%s", tostring(db.enable), tostring(db.autoScale), db.scale or 0, tostring(UIScale.manualScale)))
			F.Print(format("  screenH=%s bestScale=%.6f UIParent=%.6f C.Mult=%.6f pending=%s", tostring(sh), GetBestScale(), UIParent:GetScale(), C.Mult or 0, tostring(UIScale.pending)))
			F.Print(format("  combat=%s lockdown=%s savedUseUiScale=%s", tostring(UnitAffectingCombat("player")), tostring(InCombatLockdown()), tostring(UIScale.savedUseUiScale)))

			local cf1 = _G.ChatFrame1
			if cf1 then
				local dock = cf1.isDocked and "docked" or "undocked"
				local eb = cf1.editBox
				local ebAnchor = eb and eb:GetPoint() or "no editBox"
				F.Print(format("  ChatFrame1: %s | editBoxTop=%s | editBox anchor=%s", dock, tostring(ns.db.chat and ns.db.chat.editBoxTop), tostring(ebAnchor)))
			end
			local combatLog = _G.COMBAT_LOG
			if combatLog then
				F.Print(format("  COMBAT_LOG quickButton visible=%s", tostring(combatLog.quickButton and combatLog.quickButton:IsShown())))
			end
		end,
	})
end

function UIScale:OnSettingChanged(key)
	if self.syncingScale then
		return
	end
	if key == "scale" and ns.db.uiScale.autoScale then
		return
	end
	if key == "scale" and not ns.db.uiScale.autoScale then
		self.manualScale = ns.db.uiScale.scale
	end
	if key == "autoScale" and not ns.db.uiScale.autoScale and self.manualScale then
		ns.db.uiScale.scale = self.manualScale
	end
	ApplyScale()
end

function UIScale:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable UI Scale"], L["Let NexEnhance set the UIParent scale (reload-safe, ignores changes made in combat). While enabled, Blizzard's Graphics > Use UI Scale is turned off so the two systems do not stack."])
	local _, autoScaleInit = builder:Checkbox(category, self, "autoScale", L["Auto (Pixel-Perfect)"], L["Automatically pick the scale that maps 1 UI pixel to 1 screen pixel for your resolution."])
	local scaleSetting, scaleInit = builder:Slider(category, self, "scale", L["Scale"], L["Current UI scale. Auto (Pixel-Perfect) updates this to the calculated value for your resolution."], MIN_SCALE, MAX_SCALE, 0.01)

	self.scaleSetting = scaleSetting

	builder:DependsOn(autoScaleInit, enableInit)
	builder:DependsOn(scaleInit, enableInit)

	scaleInit.nexBumpFont = true
	scaleInit:SetParentInitializer(autoScaleInit, function()
		local cfg = ns.db.uiScale
		return cfg.enable and not cfg.autoScale
	end)

	self:SyncScaleSetting()
end
