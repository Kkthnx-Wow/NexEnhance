--[[
	NexEnhance - Player Cast Bar
	-------------------------------------------------------------------------
	Cosmetic overlay on Blizzard's player cast bar: icon above the bar, cast
	time below. We never touch cast state — only mirror Icon texture and
	CastTimeText into our own frame anchored to the bar.

	PlayerCastingBarFrame is Edit Mode managed; we treat it read-only and back
	off while OverlayPlayerCastingBarFrame replaces it (talents, crafting, etc.).

	Secret-safe: pass icon/time straight to SetTexture/SetText after issecretvalue.
	Event-driven driver frame; zero cost between casts. Optional latency SafeZone
	(red fill = lag / cast duration).

	Default OFF. Unit Frames group.
--]]

-- luacheck: globals UnitCastingInfo UnitChannelInfo GetNetStats
local _, ns = ...
local F, L = ns.F, ns.L

local _G = _G
local format = string.format
local max = math.max
local min = math.min
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local GetNetStats = GetNetStats

local ICON_GAP = 6 -- space between the icon and the top of the bar
local TIME_GAP = 20 -- space between the bar and the cast time text
local LATENCY_TEXT_GAP = 2 -- ms readout sits just above the bar's top-right corner
local UPDATE_INTERVAL = 0.05 -- mirror refresh cadence (only while casting)
local MIN_SAFEZONE_WIDTH = 8 -- floor so low-latency casts stay visible on ~208px bars
-- Inset matches ui-castingbar-background inner fill (CastingBarFrame.xml).
local SAFEZONE_INSET_X = 2
local SAFEZONE_INSET_Y = 1
local SAFEZONE_ALPHA = 0.45

ns:RegisterDefaults({
	playerCastBar = {
		enable = false,
		showIcon = true,
		showLatency = true,
		showLatencyText = true,
		castTimeBelow = true,
		iconSize = 26,
	},
})

local PlayerCastBar = ns:NewModule("PlayerCastBar", "playerCastBar", { group = "unitframes", title = L["Player Cast Bar"], order = 20 })

local active = false
local overlay -- visual mirror (icon + time); hidden when idle
local driver -- invisible OnUpdate host; shown only while a cast is on screen
local eventHandles = {}
local eventsRegistered = false
local suppressionHooked = false
local overlayReplacing = false
local elapsed = 0
-- Weak keys: one latency holder per cast bar (Player + Overlay); child frame only.
local safeZoneByBar = setmetatable({}, { __mode = "k" })

local function GetBar()
	return _G["PlayerCastingBarFrame"]
end

local function GetOverlayBar()
	return _G["OverlayPlayerCastingBarFrame"]
end

-- Frame:IsShown() / ShouldShowCastBar can return Secret booleans in combat —
-- never branch on the raw return; F.BooleanIsTrue yields nil when unreadable.
-- Defined above IsCastActive — local function helpers are nil if called before
-- their declaration (same footgun as UIScale's DumpState).
local function FrameIsShown(frame)
	if not frame then
		return false
	end
	local shown = F.BooleanIsTrue(frame:IsShown())
	return shown == true
end

local function CastBarShouldShow(bar)
	if not (bar and bar.ShouldShowCastBar) then
		return true
	end
	local should = F.BooleanIsTrue(bar:ShouldShowCastBar())
	-- Unreadable → treat as "don't mirror" (fail closed) rather than crash.
	return should == true
end

local function IsCastActive(bar)
	if not bar then
		return false
	end
	-- casting/channeling can be Secret in combat; truthiness tests would error.
	if F.IsSecret(bar.casting) or F.IsSecret(bar.channeling) or F.IsSecret(bar.reverseChanneling) then
		return FrameIsShown(bar)
	end
	return not not (bar.casting or bar.channeling or bar.reverseChanneling)
end

-- nil when channel direction is unreadable (Secret flags).
local function IsChannelCast(bar)
	if F.IsSecret(bar.channeling) or F.IsSecret(bar.reverseChanneling) then
		return nil
	end
	return bar.channeling and not bar.reverseChanneling
end

local function IsEditModeActive(bar)
	return bar and bar.isInEditMode
end

-- Whichever Blizzard player cast bar is currently showing a cast (Edit Mode excluded).
local function GetActiveCastBar()
	local overlayBar = GetOverlayBar()
	if overlayBar and FrameIsShown(overlayBar) and IsCastActive(overlayBar) then
		if not CastBarShouldShow(overlayBar) then
			return nil
		end
		return overlayBar
	end

	local bar = GetBar()
	if bar and FrameIsShown(bar) and IsCastActive(bar) and not IsEditModeActive(bar) then
		if not CastBarShouldShow(bar) then
			return nil
		end
		return bar
	end

	return nil
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

-- Clip region inside the cast bar border (Background atlas inset).
local function LayoutSafeZoneHolder(holder, bar)
	holder:ClearAllPoints()
	holder:SetPoint("TOPLEFT", bar, "TOPLEFT", SAFEZONE_INSET_X, -SAFEZONE_INSET_Y)
	holder:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -SAFEZONE_INSET_X, SAFEZONE_INSET_Y)
end

-- Child frame on the cast bar for latency (SafeZone) — display only, no cast state.
local function EnsureSafeZoneHolder(bar)
	local holder = safeZoneByBar[bar]
	if holder then
		return holder
	end

	holder = CreateFrame("Frame", nil, bar)
	holder:EnableMouse(false)
	holder:SetClipsChildren(true)
	holder:SetFrameLevel(bar:GetFrameLevel() + 12)
	LayoutSafeZoneHolder(holder, bar)

	local tex = holder:CreateTexture(nil, "ARTWORK", nil, 3)
	tex:SetAtlas("UI-Frame-Bar-Fill-Red")
	tex:SetHorizTile(true)
	tex:SetBlendMode("BLEND")
	tex:SetVertexColor(1, 1, 1, SAFEZONE_ALPHA)
	holder.texture = tex

	-- Wrapper keeps label draw order off the StatusBar's own font regions.
	local labelAnchor = CreateFrame("Frame", nil, bar)
	labelAnchor:EnableMouse(false)
	labelAnchor:SetSize(1, 1)
	labelAnchor:SetFrameLevel(bar:GetFrameLevel() + 14)
	holder.labelAnchor = labelAnchor

	local label = F.CreatePlainFS(labelAnchor, 10)
	label:SetJustifyH("RIGHT")
	label:SetTextColor(1, 1, 1)
	F.HidePlainFS(label)
	holder.label = label

	safeZoneByBar[bar] = holder
	return holder
end

local function ReleaseSafeZoneHolders()
	for trackedBar, holder in pairs(safeZoneByBar) do
		if holder then
			if holder.label then
				F.ReleasePlainFS(holder.label)
			end
			if holder.labelAnchor then
				holder.labelAnchor:Hide()
				holder.labelAnchor:SetParent(nil)
				holder.labelAnchor = nil
			end
			holder:Hide()
			holder:SetParent(nil)
		end
		safeZoneByBar[trackedBar] = nil
	end
end

local function HideMirrorDecor()
	if not overlay then
		return
	end
	overlay.icon:Hide()
	overlay.time:Hide()
end

local function HideSafeZone(bar)
	if bar then
		local holder = safeZoneByBar[bar]
		if holder then
			if holder.label then
				F.HidePlainFS(holder.label)
			end
			holder:Hide()
		end
		return
	end
	for trackedBar, holder in pairs(safeZoneByBar) do
		if holder then
			if holder.label then
				F.HidePlainFS(holder.label)
			end
			holder:Hide()
		end
	end
end

local function HideOverlay()
	HideMirrorDecor()
	HideSafeZone()
	if overlay then
		overlay:Hide()
	end
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
	if not CastBarShouldShow(bar) then
		return false
	end
	return FrameIsShown(bar)
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
			HideMirrorDecor()
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

-- Cast duration in ms for latency ratio. Prefer Blizzard's cached maxValue
-- (written in secure OnEvent); fall back to UnitCastingInfo when readable.
local function GetCastDurationMs(bar)
	local maxValue = bar.maxValue
	if F.NotSecret(maxValue) and maxValue and maxValue > 0 then
		return maxValue * 1000
	end

	if bar.GetMinMaxValues then
		local _, maxVal = bar:GetMinMaxValues()
		if F.NotSecret(maxVal) and maxVal and maxVal > 0 then
			return maxVal * 1000
		end
	end

	local unit = bar.unit or "player"
	local name, _, _, startTime, endTime = UnitCastingInfo(unit)
	if not name then
		name, _, _, startTime, endTime = UnitChannelInfo(unit)
	end
	if not name or not startTime or not endTime then
		return nil
	end
	if F.IsSecret(startTime) or F.IsSecret(endTime) then
		return nil
	end
	return endTime - startTime
end

-- Latency band: red fill at the trailing edge (cast/empower) or leading edge
-- (channel). Texture lives on a child frame of the cast bar for draw order.
local function UpdateSafeZone(bar)
	if not ns.db.playerCastBar.showLatency or not bar then
		HideSafeZone(bar)
		return
	end

	local durationMs = GetCastDurationMs(bar)
	if not durationMs or durationMs <= 0 then
		HideSafeZone(bar)
		return
	end

	local _, _, homeMs, worldMs = GetNetStats()
	local lagMs = max(homeMs or 0, worldMs or 0)
	if lagMs <= 0 then
		HideSafeZone(bar)
		return
	end

	local ratio = min(lagMs / durationMs, 1)
	if ratio <= 0 then
		HideSafeZone(bar)
		return
	end

	local holder = EnsureSafeZoneHolder(bar)
	LayoutSafeZoneHolder(holder, bar)

	local fillWidth = holder:GetWidth()
	if fillWidth <= 0 then
		HideSafeZone(bar)
		return
	end

	local zoneWidth = min(fillWidth, max(MIN_SAFEZONE_WIDTH, fillWidth * ratio))
	local isChannel = IsChannelCast(bar)
	if isChannel == nil then
		isChannel = false
	end

	local tex = holder.texture

	tex:SetBlendMode("BLEND")
	tex:SetVertexColor(1, 1, 1, SAFEZONE_ALPHA)
	tex:ClearAllPoints()
	tex:SetHeight(holder:GetHeight())
	tex:SetWidth(zoneWidth)

	if isChannel then
		tex:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
		tex:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
	else
		tex:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
		tex:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
	end

	holder:SetFrameLevel(bar:GetFrameLevel() + 12)
	holder:Show()
	tex:Show()

	local label = holder.label
	local labelAnchor = holder.labelAnchor
	if ns.db.playerCastBar.showLatencyText and label and labelAnchor then
		F.SetPlainText(label, format("%d ms", lagMs))
		labelAnchor:ClearAllPoints()
		labelAnchor:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
		labelAnchor:SetFrameLevel(bar:GetFrameLevel() + 14)
		label:ClearAllPoints()
		label:SetPoint("BOTTOMRIGHT", labelAnchor, "TOPRIGHT", -SAFEZONE_INSET_X, LATENCY_TEXT_GAP)
		labelAnchor:Show()
		F.ShowPlainFS(label)
	elseif label then
		F.HidePlainFS(label)
		if labelAnchor then
			labelAnchor:Hide()
		end
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

	local castBar = GetActiveCastBar()
	local mirrorBar = GetBar()
	local mirroring = ShouldMirrorPlayerBar(mirrorBar)

	if not castBar and not mirroring then
		HideOverlay()
		return false
	end

	local db = ns.db.playerCastBar
	local frame = EnsureOverlay()

	if castBar then
		UpdateSafeZone(castBar)
	else
		HideSafeZone()
	end

	if not mirroring then
		HideMirrorDecor()
		if castBar then
			frame:Show()
			return true
		end
		HideOverlay()
		return false
	end

	frame:ClearAllPoints()
	frame:SetPoint("CENTER", mirrorBar, "CENTER", 0, 0)
	frame:SetFrameStrata(mirrorBar:GetFrameStrata())
	frame:SetFrameLevel(mirrorBar:GetFrameLevel() + 5)
	frame:Show()

	-- Icon. `texture` is false/nil when disabled or absent, a fileID/atlas when
	-- present, or a Secret in instances. The `and` chain returns GetTexture()'s
	-- result without testing its truthiness, so we never branch on a Secret here.
	local nativeIcon = mirrorBar.Icon
	local texture = db.showIcon and nativeIcon and nativeIcon:GetTexture()
	if IsPresent(texture) then
		local size = db.iconSize or 26
		frame.icon:SetTexture(texture)
		frame.icon:SetSize(size, size)
		frame.icon:ClearAllPoints()
		frame.icon:SetPoint("BOTTOM", mirrorBar, "TOP", 0, ICON_GAP)
		frame.icon:Show()
	else
		frame.icon:Hide()
	end

	-- Cast time. Mirror the native string verbatim (it may be Secret). Note: if
	-- Blizzard's own "Show Cast Time" is off, the string is empty and nothing
	-- shows - we can't force it on without writing to the managed frame.
	local nativeTime = mirrorBar.CastTimeText
	local text = db.castTimeBelow and nativeTime and nativeTime:GetText()
	if IsPresent(text) then
		local fontObject = nativeTime:GetFontObject()
		if fontObject then
			frame.time:SetFontObject(fontObject)
		end
		frame.time:SetText(text)
		frame.time:ClearAllPoints()
		frame.time:SetPoint("TOP", mirrorBar, "BOTTOM", 0, -TIME_GAP)
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

	EnsureOverlay()
	if not driver then
		driver = CreateFrame("Frame", nil, _G["UIParent"])
		driver:Hide()
	end
	-- Reattach after Deactivate clears the script; Hide() alone already stops ticks.
	driver:SetScript("OnUpdate", OnUpdate)
	elapsed = UPDATE_INTERVAL -- evaluate on the very next frame
	if not FrameIsShown(driver) then
		driver:Show()
	end
	UpdateMirror()
end

local function RegisterDriverEvents()
	if eventsRegistered then
		return
	end
	eventsRegistered = true
	PlayerCastBar:TrackUnitEvent(eventHandles, "UNIT_SPELLCAST_START", WakeDriver, "player", "vehicle")
	PlayerCastBar:TrackUnitEvent(eventHandles, "UNIT_SPELLCAST_CHANNEL_START", WakeDriver, "player", "vehicle")
	PlayerCastBar:TrackUnitEvent(eventHandles, "UNIT_SPELLCAST_EMPOWER_START", WakeDriver, "player", "vehicle")
	PlayerCastBar:TrackEvent(eventHandles, "PLAYER_ENTERING_WORLD", "PLAYER_ENTERING_WORLD")
end

local function UnregisterDriverEvents()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
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
	WakeDriver()
	return true
end

local function Deactivate()
	active = false
	UnregisterDriverEvents()
	if driver then
		driver:Hide()
		driver:SetScript("OnUpdate", nil)
	end
	HideOverlay()
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function PlayerCastBar:PLAYER_ENTERING_WORLD()
	if not ns.db.playerCastBar.enable then
		return
	end
	if not active then
		Activate()
	elseif active then
		WakeDriver()
	end
end

function PlayerCastBar:OnEnable()
	if not ns.db.playerCastBar.enable then
		return
	end
	RegisterDriverEvents()
	Activate()
end

function PlayerCastBar:OnDisable()
	ReleaseSafeZoneHolders()
	Deactivate()
end

function PlayerCastBar:OnSettingChanged(key)
	if key == "enable" then
		-- ApplyModuleSetting owns enable lifecycle.
		return
	end

	-- Live-apply icon size / icon visibility / cast-time toggle if mid-cast.
	if active then
		WakeDriver()
	end
end

function PlayerCastBar:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Player Cast Bar"], L["Enhance Blizzard's player cast bar with optional icon/time layout and a latency indicator. Cosmetic only - Blizzard keeps ownership of cast state and timing."])
	local _, latencyInit = builder:Checkbox(category, self, "showLatency", L["Show Cast Latency"], L["Red band on the cast bar showing your network latency relative to cast time (standard SafeZone indicator)."])
	local _, latencyTextInit = builder:Checkbox(category, self, "showLatencyText", L["Show Latency Text"], L["Show home/world latency in ms beside the red SafeZone band."])
	local _, iconInit = builder:Checkbox(category, self, "showIcon", L["Show Cast Icon"], L["Show the spell icon above the cast bar."])
	local _, timeInit = builder:Checkbox(category, self, "castTimeBelow", L["Cast Time Below Bar"], L["Mirror the cast time text beneath the cast bar."])
	local _, sizeInit = builder:Slider(category, self, "iconSize", L["Cast Icon Size"], L["Size of the spell icon shown above the cast bar."], 14, 48, 1)

	builder:DependsOn(latencyInit, enableInit)
	builder:DependsOn(latencyTextInit, latencyInit)
	builder:DependsOn(iconInit, enableInit)
	builder:DependsOn(timeInit, enableInit)
	builder:DependsOn(sizeInit, enableInit)
end
