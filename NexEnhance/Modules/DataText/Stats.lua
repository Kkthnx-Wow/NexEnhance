--[[
	NexEnhance - DataText: Stats
	-------------------------------------------------------------------------
	A single movable readout under the minimap showing framerate and latency
	("60 fps / 45 ms"). Hovering it opens a tooltip with the latency detail at
	the top (home/world latency, IP protocol, streaming bandwidth) followed by
	a per-addon memory list. Left-click runs the garbage collector.

	Combines the functional parts of NDui's Infobar Latency.lua and System.lua
	(by siweia) into one element, adapted to the NexEnhance framework:
	  https://github.com/siweia/NDui/blob/master/Interface/AddOns/NDui/Modules/Infobar/Latency.lua
	  https://github.com/siweia/NDui/blob/master/Interface/AddOns/NDui/Modules/Infobar/System.lua
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local _G = _G
local max, floor = math.max, math.floor
local format = string.format
local ipairs, next, wipe = ipairs, next, wipe
local sort = table.sort
local collectgarbage = collectgarbage

local CreateFrame = CreateFrame
local GetTime = GetTime
local GetFramerate = GetFramerate
local GetNetStats = GetNetStats
local GetNetIpTypes = GetNetIpTypes
local GetCVarBool = GetCVarBool
local IsShiftKeyDown = IsShiftKeyDown
local UpdateAddOnMemoryUsage = UpdateAddOnMemoryUsage
local GetAddOnMemoryUsage = GetAddOnMemoryUsage
local GetAvailableBandwidth = GetAvailableBandwidth
local GetDownloadedPercentage = GetDownloadedPercentage
local GetFileStreamingStatus = GetFileStreamingStatus
local GetBackgroundLoadingStatus = GetBackgroundLoadingStatus
local C_AddOns = C_AddOns
local UNKNOWN = _G.UNKNOWN

-- Shared tooltip palette (single source of truth in Constants.lua): gold section
-- headers, light-blue labels/hints, white values.
local HDR = C.Colors.header
local LBL = C.Colors.label

local DEFAULTS = {
	enable = true,
	maxAddOns = 12,
	classColor = false,
	flip = false,
	display = "both", -- "both" | "fps" | "ms"
}

ns:RegisterDefaults({ datatext = DEFAULTS })

local DataText = ns:NewModule("DataText", "datatext", { group = "datatext", title = L["Stats"], order = 10 })

local cfg
local stat
local entered
local tooltipElapsed = 0
local infoTable = {}
local ipTypes = { "IPv4", "IPv6" }
local memoryTotal = 0
local memoryUpdatedAt = 0
local MEMORY_REFRESH_INTERVAL = 5

-- ---------------------------------------------------------------------------
-- Formatting helpers
-- ---------------------------------------------------------------------------
-- The player's class colour as a "|cffRRGGBB" prefix, refreshed each call so it
-- survives a late class read.
local function ClassPrefix()
	return "|c" .. F.RGBToHex(F.UnitColor("player"))
end

local function ColorFPS(fps)
	if cfg and cfg.classColor then
		return format("%s%d|r", ClassPrefix(), fps)
	end
	local hex
	if fps < 15 then
		hex = "ffd80909"
	elseif fps < 30 then
		hex = "ffe8da0f"
	else
		hex = "ff0cd809"
	end
	return format("|c%s%d|r", hex, fps)
end

local function ColorLatency(ms)
	if cfg and cfg.classColor then
		return format("%s%d|r", ClassPrefix(), ms)
	end
	local hex
	if ms < 250 then
		hex = "ff0cd809"
	elseif ms < 500 then
		hex = "ffe8da0f"
	else
		hex = "ffd80909"
	end
	return format("|c%s%d|r", hex, ms)
end

local function FormatMemory(kb)
	if kb > 1024 then
		return format("%.1f mb", kb / 1024)
	end
	return format("%.0f kb", kb)
end

-- Memory share gradient: green (low) -> yellow -> red (hogging the total).
local function MemoryColor(cur, total)
	local p = total > 0 and (cur / total) or 0
	if p >= 1 then
		return 1, 0, 0
	end
	if p <= 0 then
		return 0, 1, 0
	end
	if p <= 0.5 then
		return p / 0.5, 1, 0
	end
	return 1, 1 - (p - 0.5) / 0.5, 0
end

local function SortByMemory(a, b)
	if a and b then
		return (a[3] == b[3] and a[2] < b[2]) or (a[3] > b[3])
	end
end

-- ---------------------------------------------------------------------------
-- Data
-- ---------------------------------------------------------------------------
local function BuildAddonList()
	local num = C_AddOns.GetNumAddOns()
	if num == #infoTable then
		return
	end

	wipe(infoTable)
	for i = 1, num do
		local _, title, _, loadable = C_AddOns.GetAddOnInfo(i)
		if loadable then
			infoTable[#infoTable + 1] = { i, title, 0 }
		end
	end
end

local function UpdateMemory()
	UpdateAddOnMemoryUsage()

	local total = 0
	for _, data in ipairs(infoTable) do
		if C_AddOns.IsAddOnLoaded(data[1]) then
			local mem = GetAddOnMemoryUsage(data[1])
			data[3] = mem
			total = total + mem
		end
	end
	sort(infoTable, SortByMemory)

	return total
end

-- ---------------------------------------------------------------------------
-- Display
-- ---------------------------------------------------------------------------
local function UpdateStat(self)
	local fps = floor(GetFramerate())
	local _, _, home, world = GetNetStats()
	local latency = max(home, world)

	local fpsText = format("%s|cffffffff fps|r", ColorFPS(fps))
	local msText = format("%s|cffffffff ms|r", ColorLatency(latency))

	local display = cfg and cfg.display or "both"
	if display == "fps" then
		self.text:SetText(fpsText)
	elseif display == "ms" then
		self.text:SetText(msText)
	else
		local a, b = fpsText, msText
		if cfg and cfg.flip then
			a, b = msText, fpsText
		end
		self.text:SetFormattedText("%s |cff808080/|r %s", a, b)
	end

	self:SetWidth(max(60, self.text:GetStringWidth() + 8))
end

-- ---------------------------------------------------------------------------
-- Tooltip: latency detail first, then per-addon memory
-- ---------------------------------------------------------------------------
local function OnEnter(self, forceMemory)
	entered = true
	tooltipElapsed = 0
	self:RegisterEvent("MODIFIER_STATE_CHANGED")

	GameTooltip:SetOwner(self, "ANCHOR_NONE")
	GameTooltip:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -6)
	GameTooltip:ClearLines()

	-- Latency
	GameTooltip:AddLine(L["Latency"], HDR[1], HDR[2], HDR[3])
	GameTooltip:AddLine(" ")

	local _, _, home, world = GetNetStats()
	GameTooltip:AddDoubleLine(L["Home Latency"], ColorLatency(home) .. "|r ms", LBL[1], LBL[2], LBL[3], 1, 1, 1)
	GameTooltip:AddDoubleLine(L["World Latency"], ColorLatency(world) .. "|r ms", LBL[1], LBL[2], LBL[3], 1, 1, 1)

	if GetCVarBool("useIPv6") then
		local homeType, worldType = GetNetIpTypes()
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine(L["Home Protocol"], ipTypes[homeType or 0] or UNKNOWN, LBL[1], LBL[2], LBL[3], 1, 1, 1)
		GameTooltip:AddDoubleLine(L["World Protocol"], ipTypes[worldType or 0] or UNKNOWN, LBL[1], LBL[2], LBL[3], 1, 1, 1)
	end

	if GetFileStreamingStatus() ~= 0 or GetBackgroundLoadingStatus() ~= 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine(L["Bandwidth"], format("%.2f Mbps", GetAvailableBandwidth()), LBL[1], LBL[2], LBL[3], 1, 1, 1)
		GameTooltip:AddDoubleLine(L["Download"], format("%.2f%%", GetDownloadedPercentage() * 100), LBL[1], LBL[2], LBL[3], 1, 1, 1)
	end

	-- System / addon memory
	if not next(infoTable) then
		BuildAddonList()
	end
	local now = GetTime()
	if forceMemory or memoryTotal == 0 or (now - memoryUpdatedAt) >= MEMORY_REFRESH_INTERVAL then
		memoryTotal = UpdateMemory()
		memoryUpdatedAt = now
	end
	local total = memoryTotal

	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine(L["System"], FormatMemory(total), HDR[1], HDR[2], HDR[3], 1, 1, 1)
	GameTooltip:AddLine(" ")

	local maxAddOns = ns.db.datatext.maxAddOns
	local isShift = IsShiftKeyDown()
	local numEnabled = 0
	for _, data in ipairs(infoTable) do
		if C_AddOns.IsAddOnLoaded(data[1]) then
			numEnabled = numEnabled + 1
			if isShift or numEnabled <= maxAddOns then
				local r, g, b = MemoryColor(data[3], total)
				GameTooltip:AddDoubleLine(data[2], FormatMemory(data[3]), 1, 1, 1, r, g, b)
			end
		end
	end

	if not isShift and numEnabled > maxAddOns then
		local hidden = 0
		for i = maxAddOns + 1, numEnabled do
			hidden = hidden + (infoTable[i] and infoTable[i][3] or 0)
		end
		GameTooltip:AddDoubleLine(format("%d %s (%s)", numEnabled - maxAddOns, L["Hidden"], L["Hold Shift"]), FormatMemory(hidden), LBL[1], LBL[2], LBL[3], 1, 1, 1)
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L["Left-Click to collect memory"], LBL[1], LBL[2], LBL[3])
	GameTooltip:Show()
end

local function OnLeave()
	entered = false
	if stat then
		stat:UnregisterEvent("MODIFIER_STATE_CHANGED")
	end
	GameTooltip:Hide()
end

local function OnMouseUp(self, button)
	if button ~= "LeftButton" then
		return
	end
	local before = collectgarbage("count")
	collectgarbage("collect")
	F.Print(format("%s: %s", L["Collect Memory"], FormatMemory(before - collectgarbage("count"))))
	if entered then
		OnEnter(self, true)
	end
end

-- ---------------------------------------------------------------------------
-- Edit Mode dialog settings
--   Mirror the appearance options (everything except the master enable toggle)
--   onto the LibEditMode dialog so the readout can be tuned while it is being
--   moved. Both paths read/write the same profile keys.
-- ---------------------------------------------------------------------------
local editMode

local function ApplySetting(key, value)
	ns.db.datatext[key] = value
	cfg = ns.db.datatext
	if stat then
		UpdateStat(stat)
	end
end

local function MakeCheckbox(key, name, desc)
	return {
		kind = editMode.SettingType.Checkbox,
		name = name,
		desc = desc,
		default = DEFAULTS[key],
		get = function()
			return ns.db.datatext[key]
		end,
		set = function(_, value)
			ApplySetting(key, value)
		end,
	}
end

local function SetupEditModeSettings()
	editMode = _G.LibStub and _G.LibStub("LibEditMode", true)
	if not editMode or not editMode.AddFrameSettings then
		return
	end

	editMode:AddFrameSettings(stat, {
		{
			kind = editMode.SettingType.Dropdown,
			name = L["Display"],
			desc = L["Choose whether to show framerate, latency, or both."],
			default = DEFAULTS.display,
			get = function()
				return ns.db.datatext.display
			end,
			set = function(_, value)
				ApplySetting("display", value)
			end,
			values = {
				{ text = L["FPS & Latency"], value = "both" },
				{ text = L["FPS Only"], value = "fps" },
				{ text = L["Latency Only"], value = "ms" },
			},
		},
		MakeCheckbox("flip", L["Flip Order"], L["Show latency before framerate."]),
		MakeCheckbox("classColor", L["Class-Coloured Numbers"], L["Colour the numbers with your class colour instead of value-based colours."]),
		{
			kind = editMode.SettingType.Slider,
			name = L["Addons Shown"],
			desc = L['How many addons to list in the memory tooltip before collapsing the rest under "Hold Shift".'],
			default = DEFAULTS.maxAddOns,
			minValue = 5,
			maxValue = 30,
			valueStep = 1,
			get = function()
				return ns.db.datatext.maxAddOns
			end,
			set = function(_, value)
				ApplySetting("maxAddOns", value)
			end,
		},
	})
end

-- The mover key was bumped (stats -> statsAnchor -> statsAnchor2) so any stale
-- saved coordinate from the older schemes - including the bad "CENTER, 0, -240"
-- screen-centre fallback that stranded the readout below the minimap - is
-- discarded and the readout starts fresh, centred under the minimap.
local MOVER_KEY = "statsAnchor2"
local moverRegistered

-- Returns the minimap only when it is a real, anchorable, laid-out region. On a
-- /reload Blizzard frames can be transiently *forbidden*, and anchoring to a
-- forbidden frame throws "SetPoint(): Wrong object type for function", so we
-- never hand such a frame to SetPoint.
local function MinimapAnchor()
	local minimap = _G["Minimap"]
	if minimap and minimap.IsForbidden and not minimap:IsForbidden() and minimap.GetBottom and minimap:GetBottom() then
		return minimap
	end
end

-- Place the readout with a LIVE relative anchor to the minimap. Because this is
-- a real frame-to-frame anchor it can never be stranded by a bad/stale absolute
-- coordinate and it tracks the minimap wherever Edit Mode puts it. We also sync
-- LibEditMode's stored default (absolute UIParent coords, which is all its
-- "Reset Position" button understands) to the live spot so a reset lands here.
local function GlueUnderMinimap()
	local minimap = MinimapAnchor()
	if not (stat and minimap) then
		return
	end

	stat:ClearAllPoints()
	stat:SetPoint("TOP", minimap, "BOTTOM", 0, -4) -- -4 clears the 3px border

	local lib = _G.LibStub and _G.LibStub("LibEditMode", true)
	local default = lib and lib.frameDefaults and lib.frameDefaults[stat]
	if default then
		local cx, cy = stat:GetCenter()
		local ux, uy = UIParent:GetCenter()
		if cx and ux then
			default.point, default.x, default.y = "CENTER", cx - ux, cy - uy
		end
	end
end

-- Register once the minimap has a resolved position, then keep it glued via the
-- mover's onPlace hook so the Edit Mode layout callback re-applies the relative
-- anchor (instead of clobbering it with a stale absolute default).
local function SetupPosition()
	if not stat then
		return
	end

	local ready = MinimapAnchor()

	if not moverRegistered then
		if not ready then
			return
		end
		moverRegistered = true

		F.CreateMover(stat, MOVER_KEY, L["Stats"], "CENTER", 0, -240, GlueUnderMinimap)
		SetupEditModeSettings()
	end

	if ready and not (ns.db.movers and ns.db.movers[MOVER_KEY]) then
		GlueUnderMinimap()
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function DataText:Create()
	if stat then
		stat:Show()
		return
	end

	stat = CreateFrame("Button", nil, UIParent)
	stat:SetSize(120, 20)
	stat:RegisterForClicks("AnyUp")

	-- Plain text with a soft drop shadow (no outline).
	stat.text = stat:CreateFontString(nil, "OVERLAY")
	stat.text:SetFont(C.Media.Fonts.normal, 14, "")
	stat.text:SetShadowColor(0, 0, 0, 1)
	stat.text:SetShadowOffset(1, -1)
	stat.text:SetPoint("CENTER")

	stat:SetScript("OnEnter", OnEnter)
	stat:SetScript("OnLeave", OnLeave)
	stat:SetScript("OnMouseUp", OnMouseUp)
	stat:SetScript("OnEvent", function(self, event)
		if event == "MODIFIER_STATE_CHANGED" and entered then
			OnEnter(self)
		end
	end)

	local elapsed = 0
	stat:SetScript("OnUpdate", function(self, e)
		elapsed = elapsed + (e or 0)
		if elapsed < 1 then
			return
		end
		elapsed = 0
		UpdateStat(self)
		if entered then
			tooltipElapsed = tooltipElapsed + 1
			if tooltipElapsed >= MEMORY_REFRESH_INTERVAL then
				OnEnter(self)
			end
		end
	end)

	-- Size the frame to its text, then resolve its position. Registration is
	-- deferred to the next frame (off the synchronous module-enable / reload path,
	-- where the minimap can still be transiently forbidden) and re-run on every
	-- world enter so a late minimap layout can't leave it stranded.
	UpdateStat(stat)

	_G.C_Timer.After(0, SetupPosition)
	ns:RegisterEvent("PLAYER_ENTERING_WORLD", SetupPosition)
end

function DataText:OnEnable()
	cfg = ns.db.datatext
	if not cfg.enable then
		return
	end
	self:Create()
end

function DataText:OnSettingChanged(key, value)
	cfg = ns.db.datatext
	if key == "enable" then
		if value then
			self:Create()
		elseif stat then
			stat:Hide()
		end
	elseif stat then
		-- display / flip / class-colour changes apply live.
		UpdateStat(stat)
	end

	-- Reflect Settings-panel changes in the Edit Mode dialog if it is open.
	if editMode and editMode.RefreshFrameSettings and stat then
		editMode:RefreshFrameSettings(stat)
	end
end

function DataText:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable DataText"], L["Show a movable FPS / latency readout under the minimap, with a memory/addon tooltip (reload to disable)."])
	local _, displayInit = builder:Dropdown(category, self, "display", L["Display"], L["Choose whether to show framerate, latency, or both."], {
		{ value = "both", label = L["FPS & Latency"] },
		{ value = "fps", label = L["FPS Only"] },
		{ value = "ms", label = L["Latency Only"] },
	})
	local _, flipInit = builder:Checkbox(category, self, "flip", L["Flip Order"], L["Show latency before framerate."])
	local _, classColorInit = builder:Checkbox(category, self, "classColor", L["Class-Coloured Numbers"], L["Colour the numbers with your class colour instead of value-based colours."])
	local _, maxAddOnsInit = builder:Slider(category, self, "maxAddOns", L["Addons Shown"], L['How many addons to list in the memory tooltip before collapsing the rest under "Hold Shift".'], 5, 30, 1)

	builder:DependsOn(displayInit, enableInit)
	builder:DependsOn(flipInit, enableInit)
	builder:DependsOn(classColorInit, enableInit)
	builder:DependsOn(maxAddOnsInit, enableInit)
end
