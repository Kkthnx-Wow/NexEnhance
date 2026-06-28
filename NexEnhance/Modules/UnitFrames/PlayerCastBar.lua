--[[
	NexEnhance - Player Cast Bar
	-------------------------------------------------------------------------
	Re-lays-out Blizzard's player cast bar (PlayerCastingBarFrame) so the spell
	icon sits on TOP of the bar and the cast time text sits BENEATH it - a
	cleaner, more readable arrangement than the default side-by-side layout.

	Design (researched from BlizzardInterfaceCode,
	Blizzard_UIPanels_Game/Mainline/CastingBarFrame.lua - CastingBarMixin):
	  * PURELY COSMETIC. We never touch cast state, timing, spell data,
	    UnitCastingInfo/UnitChannelInfo, or compute anything from cast data -
	    Blizzard keeps full ownership of all of that.
	  * PlayerCastingBarFrame is an Edit Mode-managed frame. Touching it (moving
	    its regions, writing fields onto it, or hooking its methods) taints
	    Blizzard's protected Edit Mode refresh path. So we treat it as READ-ONLY:
	    we only read `Icon:GetTexture()` and `CastTimeText:GetText()` and mirror
	    them into our own overlay anchored to the bar. We never write to it.
	  * Talent/spec commits, crafting, and other UI hijack the player bar via
	    OverlayPlayerCastingBarFrame:StartReplacingPlayerBarAt(), which calls
	    PlayerCastingBarFrame:SetAndUpdateShowCastbar(false). We must back off
	    entirely while that replacement is active or the native bar is suppressed.
	  * Secret-safe: the icon texture / time string can be Secret values inside
	    instances. We never compare or inspect them - issecretvalue() (always
	    safe) decides presence, then the raw value is passed straight into
	    SetTexture/SetText (both accept Secrets). No arithmetic, no comparison.
	  * Event-driven: an invisible driver frame hosts the OnUpdate (OnUpdate does
	    not fire on hidden frames, and our visual overlay hides when idle). The
	    driver is woken by UNIT_SPELLCAST_*_START (player/vehicle) and puts
	    itself back to sleep once the native bar has finished hiding - so there
	    is zero per-frame cost between casts.

	Default OFF. Lives under Unit Frames.
--]]

local _, ns = ...
local F, L = ns.F, ns.L

local _G = _G
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc

local ICON_GAP = 6 -- space between the icon and the top of the bar
local TIME_GAP = 20 -- space between the bar and the cast time text
local UPDATE_INTERVAL = 0.05 -- mirror refresh cadence (only while casting)

ns:RegisterDefaults({
	playerCastBar = {
		enable = false,
		showIcon = true,
		castTimeBelow = true,
		iconSize = 26,
	},
})

local PlayerCastBar = ns:NewModule("PlayerCastBar", "playerCastBar", { group = "unitframes", title = L["Player Cast Bar"], order = 20 })

local active = false
local overlay -- visual mirror (icon + time); hidden when idle
local driver -- invisible OnUpdate host; shown only while a cast is on screen
local eventsRegistered = false
local suppressionHooked = false
local overlayReplacing = false
local elapsed = 0

local function GetBar()
	return _G["PlayerCastingBarFrame"]
end

local function IsEditModeActive(bar)
	return bar and bar.isInEditMode
end

-- True when a (possibly Secret) value is present, WITHOUT inspecting it.
-- issecretvalue() never errors; plain truthiness is only tested once we know
-- the value is not Secret (branching on a Secret boolean would error).
local function IsPresent(value)
	if F.IsSecret(value) then
		return true
	end
	return value and true or false
end

local function EnsureOverlay()
	if overlay then
		return overlay
	end

	overlay = CreateFrame("Frame", nil, _G["UIParent"])
	overlay:SetSize(1, 1)
	overlay:Hide()

	overlay.icon = overlay:CreateTexture(nil, "OVERLAY")
	overlay.icon:Hide()

	overlay.time = overlay:CreateFontString(nil, "OVERLAY")
	overlay.time:SetJustifyH("CENTER")
	overlay.time:Hide()

	return overlay
end

local function HideOverlay()
	if not overlay then
		return
	end
	overlay.icon:Hide()
	overlay.time:Hide()
	overlay:Hide()
end

local function SleepDriver()
	if driver then
		driver:Hide()
	end
	HideOverlay()
end

-- Blizzard routes player casts through OverlayPlayerCastingBarFrame while talents,
-- specs, crafting, and similar UI are open. PlayerCastingBarFrame is suppressed
-- (showCastbar = false) for that window — mirroring it would fight secure UI.
local function ShouldMirrorPlayerBar(bar)
	if not bar then
		return false
	end
	if overlayReplacing then
		return false
	end
	if IsEditModeActive(bar) then
		return false
	end
	if bar.ShouldShowCastBar and not bar:ShouldShowCastBar() then
		return false
	end
	return bar:IsShown()
end

local function HookCastBarSuppression()
	if suppressionHooked then
		return
	end

	local bar = GetBar()
	local overlayBar = _G["OverlayPlayerCastingBarFrame"]
	if not bar and not overlayBar then
		return
	end

	suppressionHooked = true

	if overlayBar and overlayBar.StartReplacingPlayerBarAt then
		hooksecurefunc(overlayBar, "StartReplacingPlayerBarAt", function()
			overlayReplacing = true
			SleepDriver()
		end)
		hooksecurefunc(overlayBar, "EndReplacingPlayerBar", function()
			overlayReplacing = false
		end)
	end

	if bar and bar.SetAndUpdateShowCastbar then
		hooksecurefunc(bar, "SetAndUpdateShowCastbar", function(_, showCastbar)
			if not showCastbar then
				SleepDriver()
			end
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Mirror Blizzard's icon/time into our overlay. READ-ONLY on the cast bar.
-- Returns true while the bar is on screen (so the driver keeps polling), false
-- once it has hidden (so the driver can go back to sleep).
-- ---------------------------------------------------------------------------
local function UpdateMirror()
	if not active then
		HideOverlay()
		return false
	end

	local bar = GetBar()
	if not ShouldMirrorPlayerBar(bar) then
		HideOverlay()
		return false
	end

	local db = ns.db.playerCastBar
	local frame = EnsureOverlay()
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", bar, "CENTER", 0, 0)
	frame:SetFrameStrata(bar:GetFrameStrata())
	frame:SetFrameLevel(bar:GetFrameLevel() + 5)
	frame:Show()

	-- Icon. `texture` is false/nil when disabled or absent, a fileID/atlas when
	-- present, or a Secret in instances. The `and` chain returns GetTexture()'s
	-- result without testing its truthiness, so we never branch on a Secret here.
	local nativeIcon = bar.Icon
	local texture = db.showIcon and nativeIcon and nativeIcon:GetTexture()
	if IsPresent(texture) then
		local size = db.iconSize or 26
		frame.icon:SetTexture(texture)
		frame.icon:SetSize(size, size)
		frame.icon:ClearAllPoints()
		frame.icon:SetPoint("BOTTOM", bar, "TOP", 0, ICON_GAP)
		frame.icon:Show()
	else
		frame.icon:Hide()
	end

	-- Cast time. Mirror the native string verbatim (it may be Secret). Note: if
	-- Blizzard's own "Show Cast Time" is off, the string is empty and nothing
	-- shows - we can't force it on without writing to the managed frame.
	local nativeTime = bar.CastTimeText
	local text = db.castTimeBelow and nativeTime and nativeTime:GetText()
	if IsPresent(text) then
		local fontObject = nativeTime:GetFontObject()
		if fontObject then
			frame.time:SetFontObject(fontObject)
		end
		frame.time:SetText(text)
		frame.time:ClearAllPoints()
		frame.time:SetPoint("TOP", bar, "BOTTOM", 0, -TIME_GAP)
		frame.time:Show()
	else
		frame.time:Hide()
	end

	return true
end

local function OnUpdate(_, dt)
	elapsed = elapsed + dt
	if elapsed < UPDATE_INTERVAL then
		return
	end
	elapsed = 0

	-- Once the native bar has fully hidden (after its fade-out), stop polling
	-- and sleep until the next cast-start event wakes us.
	if not UpdateMirror() and driver then
		driver:Hide()
	end
end

-- ---------------------------------------------------------------------------
-- Driver wake/sleep
-- ---------------------------------------------------------------------------
local function WakeDriver()
	if not active then
		return
	end

	local bar = GetBar()
	if overlayReplacing or (bar and bar.ShouldShowCastBar and not bar:ShouldShowCastBar()) then
		return
	end

	EnsureOverlay()
	if not driver then
		driver = CreateFrame("Frame", nil, _G["UIParent"])
		driver:Hide()
		driver:SetScript("OnUpdate", OnUpdate)
	end
	elapsed = UPDATE_INTERVAL -- evaluate on the very next frame
	if not driver:IsShown() then
		driver:Show()
	end
	UpdateMirror()
end

-- ---------------------------------------------------------------------------
-- Activation
-- ---------------------------------------------------------------------------
local function Activate()
	HookCastBarSuppression()

	local bar = GetBar()
	if not bar then
		return false
	end

	active = true

	-- Register cast-start signals once. We only use them to wake the driver -
	-- we never read the spell/cast payload, so there are no Secret concerns.
	if not eventsRegistered then
		eventsRegistered = true
		PlayerCastBar:RegisterUnitEvent("UNIT_SPELLCAST_START", WakeDriver, "player", "vehicle")
		PlayerCastBar:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", WakeDriver, "player", "vehicle")
		PlayerCastBar:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", WakeDriver, "player", "vehicle")
	end

	-- Catch a cast that is already in progress (e.g. enabled mid-cast / login).
	WakeDriver()
	return true
end

local function Deactivate()
	active = false
	if driver then
		driver:Hide()
	end
	HideOverlay()
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function PlayerCastBar:PLAYER_ENTERING_WORLD()
	if active then
		WakeDriver()
	end
end

function PlayerCastBar:OnEnable()
	-- PlayerCastingBarFrame ships with Blizzard_UIPanels_Game (not load-on-
	-- demand), so it exists by PLAYER_LOGIN; retry on entering world just in
	-- case it is built late.
	if not Activate() then
		self:RegisterEvent("PLAYER_ENTERING_WORLD", "PLAYER_ENTERING_WORLD")
		active = true
	end
end

function PlayerCastBar:OnSettingChanged(key, value)
	if key == "enable" then
		if value then
			Activate()
		else
			Deactivate()
		end
		return
	end

	-- Live-apply icon size / icon visibility / cast-time toggle if mid-cast.
	if active then
		WakeDriver()
	end
end

function PlayerCastBar:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Player Cast Bar"], L["Mirror the player cast bar icon and time above/below the bar. Cosmetic only - Blizzard keeps ownership of the cast bar itself."])
	local _, iconInit = builder:Checkbox(category, self, "showIcon", L["Show Cast Icon"], L["Show the spell icon above the cast bar."])
	local _, timeInit = builder:Checkbox(category, self, "castTimeBelow", L["Cast Time Below Bar"], L["Mirror the cast time text beneath the cast bar."])
	local _, sizeInit = builder:Slider(category, self, "iconSize", L["Cast Icon Size"], L["Size of the spell icon shown above the cast bar."], 14, 48, 1)

	builder:DependsOn(iconInit, enableInit)
	builder:DependsOn(timeInit, enableInit)
	builder:DependsOn(sizeInit, enableInit)
end
