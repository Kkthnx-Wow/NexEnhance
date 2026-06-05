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

ns:RegisterDefaults({
	datatext = {
		enable = true,
		maxAddOns = 12,
		classColor = false,
		flip = false,
		display = "both", -- "both" | "fps" | "ms"
	},
})

local DataText = ns:NewModule("DataText", "datatext", { group = "datatext", title = L["Stats"], order = 10 })

local cfg
local stat
local entered
local infoTable = {}
local ipTypes = { "IPv4", "IPv6" }

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
	if fps < 15 then hex = "ffd80909"
	elseif fps < 30 then hex = "ffe8da0f"
	else hex = "ff0cd809" end
	return format("|c%s%d|r", hex, fps)
end

local function ColorLatency(ms)
	if cfg and cfg.classColor then
		return format("%s%d|r", ClassPrefix(), ms)
	end
	local hex
	if ms < 250 then hex = "ff0cd809"
	elseif ms < 500 then hex = "ffe8da0f"
	else hex = "ffd80909" end
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
	if p >= 1 then return 1, 0, 0 end
	if p <= 0 then return 0, 1, 0 end
	if p <= 0.5 then return p / 0.5, 1, 0 end
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
	if num == #infoTable then return end

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
local function OnEnter(self)
	entered = true

	GameTooltip:SetOwner(self, "ANCHOR_NONE")
	GameTooltip:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -6)
	GameTooltip:ClearLines()

	-- Latency
	GameTooltip:AddLine(L["Latency"], 0, 0.6, 1)
	GameTooltip:AddLine(" ")

	local _, _, home, world = GetNetStats()
	GameTooltip:AddDoubleLine(L["Home Latency"], ColorLatency(home) .. "|r ms", 0.6, 0.8, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine(L["World Latency"], ColorLatency(world) .. "|r ms", 0.6, 0.8, 1, 1, 1, 1)

	if GetCVarBool("useIPv6") then
		local homeType, worldType = GetNetIpTypes()
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine(L["Home Protocol"], ipTypes[homeType or 0] or UNKNOWN, 0.6, 0.8, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine(L["World Protocol"], ipTypes[worldType or 0] or UNKNOWN, 0.6, 0.8, 1, 1, 1, 1)
	end

	if GetFileStreamingStatus() ~= 0 or GetBackgroundLoadingStatus() ~= 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine(L["Bandwidth"], format("%.2f Mbps", GetAvailableBandwidth()), 0.6, 0.8, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine(L["Download"], format("%.2f%%", GetDownloadedPercentage() * 100), 0.6, 0.8, 1, 1, 1, 1)
	end

	-- System / addon memory
	if not next(infoTable) then BuildAddonList() end
	local total = UpdateMemory()

	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine(L["System"], FormatMemory(total), 0, 0.6, 1, 0.6, 0.8, 1)
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
		GameTooltip:AddDoubleLine(format("%d %s (%s)", numEnabled - maxAddOns, L["Hidden"], L["Hold Shift"]), FormatMemory(hidden), 0.6, 0.8, 1, 0.6, 0.8, 1)
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L["Left-Click to collect memory"], 0.6, 0.8, 1)
	GameTooltip:Show()
end

local function OnLeave()
	entered = false
	GameTooltip:Hide()
end

local function OnMouseUp(self, button)
	if button ~= "LeftButton" then return end
	local before = collectgarbage("count")
	collectgarbage("collect")
	F.Print(format("%s: %s", L["Collect Memory"], FormatMemory(before - collectgarbage("count"))))
	if entered then OnEnter(self) end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function DataText:Create()
	if stat then
		stat:Show()
		return
	end

	stat = CreateFrame("Button", "NexEnhanceStats", UIParent)
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

	local elapsed = 0
	stat:SetScript("OnUpdate", function(self, e)
		elapsed = elapsed + (e or 0)
		if elapsed < 1 then return end
		elapsed = 0
		UpdateStat(self)
		if entered then OnEnter(self) end
	end)

	-- Size the frame to its text first, then resolve a concrete screen position
	-- under the minimap so Edit Mode (and its "reset to default") have a real
	-- absolute anchor instead of snapping to the top of the screen.
	UpdateStat(stat)

	local point, x, y = "TOP", 0, -220
	local minimap = _G["Minimap"]
	if minimap then
		stat:ClearAllPoints()
		stat:SetPoint("TOP", minimap, "BOTTOM", 0, -6)
		local left, bottom = stat:GetLeft(), stat:GetBottom()
		if left and bottom then
			point, x, y = "BOTTOMLEFT", left, bottom
		end
		stat:ClearAllPoints()
	end

	F.CreateMover(stat, "stats", L["Stats"], point, x, y)
end

function DataText:OnEnable()
	cfg = ns.db.datatext
	if not cfg.enable then return end
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
	local _, maxAddOnsInit = builder:Slider(category, self, "maxAddOns", L["Addons Shown"], L["How many addons to list in the memory tooltip before collapsing the rest under \"Hold Shift\"."], 5, 30, 1)

	builder:DependsOn(displayInit, enableInit)
	builder:DependsOn(flipInit, enableInit)
	builder:DependsOn(classColorInit, enableInit)
	builder:DependsOn(maxAddOnsInit, enableInit)
end
