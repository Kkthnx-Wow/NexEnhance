--[[
	NexEnhance - Auction Search History
	-------------------------------------------------------------------------
	Browser-style recent browse searches on the Auction House search box.
	Shows the last few text queries when the box is focused; click one to
	re-run. Text only (filters/level range are not stored).

	Blizzard refs (Resources 12.0.7): C_AuctionHouse.SendBrowseQuery,
	AuctionHouseFrame.SearchBar.SearchBox.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local F, L = ns.F, ns.L

local _G = _G
local format = string.format
local ipairs = ipairs
local tinsert, tremove = table.insert, table.remove
local strtrim = strtrim
local hooksecurefunc = hooksecurefunc
local CreateFrame = CreateFrame
local C_Timer_After = C_Timer.After
local EditBox_ClearFocus = EditBox_ClearFocus

local ROW_HEIGHT = 22
local ROW_PAD = 4
local DROPDOWN_PAD = 6

ns:RegisterDefaults({
	auctionSearchHistory = {
		enable = true,
		maxEntries = 5,
	},
})

ns:RegisterDefaults({ auctionSearchHistory = { recent = {} } }, "global")

local AuctionSearchHistory = ns:NewModule("AuctionSearchHistory", "auctionSearchHistory", {
	group = "automation",
	title = L["Auction Search History"],
	order = 37,
})

local apiHooked
local frameHooked
local dropdown
local rowPool
local hideScheduled

local function db()
	return ns.db.auctionSearchHistory
end

local function HistoryList()
	local g = ns.global and ns.global.auctionSearchHistory
	if not g then
		AuctionSearchHistory:DebugLog("warn", "global.auctionSearchHistory missing")
		return {}
	end
	g.recent = g.recent or {}
	return g.recent
end

local function MaxEntries()
	local n = db().maxEntries or 5
	if n < 1 then
		return 1
	end
	if n > 10 then
		return 10
	end
	return n
end

function AuctionSearchHistory:PushSearch(text)
	if not db().enable then
		self:DebugLog("info", "PushSearch skipped (disabled)")
		return
	end

	text = strtrim(text or "")
	if text == "" then
		self:DebugLog("info", "PushSearch skipped (empty)")
		return
	end
	if F.IsSecret(text) then
		self:DebugLog("warn", "PushSearch skipped (secret text)")
		return
	end

	local recent = HistoryList()
	for i = #recent, 1, -1 do
		if recent[i] == text then
			tremove(recent, i)
		end
	end
	tinsert(recent, 1, text)

	local max = MaxEntries()
	while #recent > max do
		tremove(recent)
	end

	self:DebugLog("info", "saved %q (#recent=%d)", text, #recent)
end

local function EnsureDropdown()
	if dropdown then
		return dropdown
	end

	local frame = CreateFrame("Frame", "NexEnhanceAHSearchHistory", UIParent)
	frame:SetFrameStrata("TOOLTIP")
	frame:SetClampedToScreen(true)
	frame:Hide()
	frame:EnableMouse(true)
	-- F.CreateTooltipBackdrop(frame, { edgeSize = 10 })

	local background = frame:CreateTexture(nil, "BACKGROUND")
	background:SetAtlas("common-dropdown-bg")
	background:SetAlpha(0.9)
	background:SetPoint("TOPLEFT", -10, 6)
	background:SetPoint("BOTTOMRIGHT", 2, -12)

	frame:SetScript("OnHide", function()
		if rowPool then
			rowPool:ReleaseAll()
		end
	end)

	frame:SetScript("OnEnter", function()
		hideScheduled = false
	end)

	frame:SetScript("OnLeave", function()
		AuctionSearchHistory:ScheduleHideDropdown()
	end)

	dropdown = frame
	return frame
end

local function CreateRow(parent)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetHeight(ROW_HEIGHT)
	btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	btn:GetHighlightTexture():SetAlpha(0.35)

	local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", ROW_PAD, 0)
	label:SetPoint("RIGHT", -ROW_PAD, 0)
	label:SetJustifyH("LEFT")
	btn.label = label

	btn:SetScript("OnClick", function(self)
		local searchBar = self.searchBar
		local searchBox = self.searchBox
		if not (searchBar and searchBox) then
			return
		end
		if not db().enable then
			return
		end

		AuctionSearchHistory:DebugLog("info", "history click %q", self.queryText or "")
		searchBar:SetSearchText(self.queryText or "")
		searchBar:StartSearch()
		AuctionSearchHistory:HideDropdown()
		EditBox_ClearFocus(searchBox)
	end)

	btn:SetScript("OnEnter", function(self)
		if self.label then
			self.label:SetTextColor(1, 0.82, 0)
		end
	end)

	btn:SetScript("OnLeave", function(self)
		if self.label then
			self.label:SetTextColor(1, 1, 1)
		end
	end)

	return btn
end

function AuctionSearchHistory:HideDropdown()
	hideScheduled = false
	if dropdown then
		dropdown:Hide()
	end
end

function AuctionSearchHistory:ScheduleHideDropdown()
	if hideScheduled then
		return
	end
	hideScheduled = true
	C_Timer_After(0.12, function()
		hideScheduled = false
		if not dropdown or not dropdown:IsShown() then
			return
		end
		local searchBox = dropdown.searchBox
		if searchBox and searchBox.HasFocus and searchBox:HasFocus() then
			return
		end
		if dropdown:IsMouseOver() then
			return
		end
		self:HideDropdown()
	end)
end

function AuctionSearchHistory:ShowDropdown(searchBar, searchBox)
	if not db().enable then
		self:DebugLog("info", "ShowDropdown skipped (disabled)")
		return
	end

	local recent = HistoryList()
	if #recent == 0 then
		self:DebugLog("info", "ShowDropdown skipped (no history)")
		return
	end

	local panel = EnsureDropdown()
	rowPool = rowPool or F.CreatePool(CreateRow, function(row)
		row.queryText = nil
		row.searchBar = nil
		row.searchBox = nil
		if row.label then
			row.label:SetText("")
			row.label:SetTextColor(1, 1, 1)
		end
	end)

	rowPool:ReleaseAll()

	local width = searchBox:GetWidth()
	if not width or width < 80 then
		width = 200
	end
	panel:SetWidth(width + DROPDOWN_PAD * 2)

	for i = 1, #recent do
		local row = rowPool:Acquire()
		row:SetParent(panel)
		row:SetWidth(width)
		row.queryText = recent[i]
		row.searchBar = searchBar
		row.searchBox = searchBox
		row.label:SetText(recent[i])
		row:SetPoint("TOPLEFT", panel, "TOPLEFT", DROPDOWN_PAD, -(DROPDOWN_PAD + (i - 1) * ROW_HEIGHT))
	end

	panel:SetHeight(DROPDOWN_PAD * 2 + #recent * ROW_HEIGHT)
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -DROPDOWN_PAD, -2)
	panel.searchBox = searchBox

	local ah = _G.AuctionHouseFrame
	local level = (ah and ah:IsShown() and ah:GetFrameLevel() or 0) + 100
	panel:SetFrameLevel(level)

	panel:Show()
	self:DebugLog("info", "ShowDropdown rows=%d level=%d", #recent, level)
end

function AuctionSearchHistory:TryShowDropdown(searchBar, searchBox)
	if not (searchBar and searchBox) then
		self:DebugLog("warn", "TryShowDropdown missing searchBar/searchBox")
		return
	end
	if not searchBox:IsVisible() then
		self:DebugLog("info", "TryShowDropdown skipped (search box not visible)")
		return
	end
	self:ShowDropdown(searchBar, searchBox)
end

local function HookSearchBox(searchBar)
	local searchBox = searchBar and searchBar.SearchBox
	if not searchBox then
		AuctionSearchHistory:DebugLog("warn", "HookSearchBox: no SearchBox on SearchBar")
		return false
	end
	if searchBox.__nexAHHistoryHooked then
		return true
	end
	searchBox.__nexAHHistoryHooked = true

	searchBox:HookScript("OnEditFocusGained", function()
		AuctionSearchHistory:DebugLog("info", "SearchBox focus gained")
		AuctionSearchHistory:TryShowDropdown(searchBar, searchBox)
	end)

	searchBox:HookScript("OnEditFocusLost", function()
		AuctionSearchHistory:ScheduleHideDropdown()
	end)

	AuctionSearchHistory:DebugLog("info", "SearchBox hooked (%s)", searchBox:GetName() or "?")
	return true
end

local function HookSearchBar(searchBar)
	if not searchBar then
		return
	end
	HookSearchBox(searchBar)
	if searchBar.__nexAHHistoryBarHooked then
		return
	end
	searchBar.__nexAHHistoryBarHooked = true
	searchBar:HookScript("OnShow", function(self)
		HookSearchBox(self)
	end)
end

local function InstallApiHooks()
	if apiHooked then
		return true
	end
	if not (C_AuctionHouse and C_AuctionHouse.SendBrowseQuery) then
		AuctionSearchHistory:DebugLog("warn", "InstallApiHooks: C_AuctionHouse.SendBrowseQuery nil")
		return false
	end

	apiHooked = true
	hooksecurefunc(C_AuctionHouse, "SendBrowseQuery", function(query)
		if type(query) ~= "table" then
			AuctionSearchHistory:DebugLog("warn", "SendBrowseQuery: non-table query")
			return
		end
		local text = query.searchString
		AuctionSearchHistory:DebugLog("info", "SendBrowseQuery searchString=%s", type(text))
		if type(text) == "string" then
			AuctionSearchHistory:PushSearch(text)
		end
	end)

	AuctionSearchHistory:DebugLog("info", "API hook installed (C_AuctionHouse.SendBrowseQuery)")
	return true
end

local function TryInstallFrameHooks()
	local ah = _G.AuctionHouseFrame
	if not ah then
		AuctionSearchHistory:DebugLog("info", "frame hooks deferred (AuctionHouseFrame nil)")
		return false
	end

	local searchBar = ah.SearchBar
	if searchBar then
		HookSearchBar(searchBar)
	end

	if not frameHooked then
		frameHooked = true
		ah:HookScript("OnShow", function()
			if not db().enable then
				return
			end
			C_Timer_After(0, function()
				local bar = ah.SearchBar
				if bar then
					HookSearchBar(bar)
				end
				local box = bar and bar.SearchBox
				if box and box.HasFocus and box:HasFocus() then
					AuctionSearchHistory:TryShowDropdown(bar, box)
				end
			end)
		end)
		AuctionSearchHistory:DebugLog("info", "AuctionHouseFrame OnShow hook installed")
	end

	return true
end

local function InstallHooks()
	InstallApiHooks()
	TryInstallFrameHooks()
end

function AuctionSearchHistory:OnInitialize()
	ns.Debug.BindModule(self, "auctionSearchHistory", {
		title = L["Auction Search History"],
		expectations = {
			{
				name = "API hook installed when module enabled",
				test = function()
					return apiHooked == true
				end,
				detail = function()
					return format("apiHooked=%s", tostring(apiHooked))
				end,
			},
		},
		dump = function()
			local cfg = ns.db and ns.db.auctionSearchHistory
			local recent = HistoryList()
			F.Print(format("  enable=%s maxEntries=%s", tostring(cfg and cfg.enable), tostring(cfg and cfg.maxEntries)))
			F.Print(format("  apiHooked=%s frameHooked=%s ahLoaded=%s", tostring(apiHooked), tostring(frameHooked), tostring(C_AddOns.IsAddOnLoaded("Blizzard_AuctionHouseUI"))))
			F.Print(format("  AuctionHouseFrame=%s SearchBar=%s", tostring(_G.AuctionHouseFrame ~= nil), tostring(_G.AuctionHouseFrame and _G.AuctionHouseFrame.SearchBar ~= nil)))
			if _G.AuctionHouseFrame and _G.AuctionHouseFrame.SearchBar then
				local box = _G.AuctionHouseFrame.SearchBar.SearchBox
				F.Print(format("  SearchBox=%s hooked=%s visible=%s", tostring(box ~= nil), tostring(box and box.__nexAHHistoryHooked), tostring(box and box:IsVisible())))
			end
			F.Print(format("  recent count=%d", #recent))
			for i = 1, math.min(#recent, 10) do
				F.Print(format("    [%d] %s", i, recent[i]))
			end
			F.Print("  Tip: /nex debug on auctionSearchHistory then run AH searches and focus the box.")
		end,
	})
end

function AuctionSearchHistory:OnEnable()
	if not db().enable then
		return
	end
	self:DebugLog("info", "OnEnable")
	ns:RegisterAddOnLoadedCallback("Blizzard_AuctionHouseUI", InstallHooks)
	InstallHooks()
end

function AuctionSearchHistory:OnDisable()
	self:HideDropdown()
end

function AuctionSearchHistory:OnSettingChanged(key, value)
	if key == "enable" then
		if value then
			self:OnEnable()
		else
			self:OnDisable()
		end
	elseif key == "maxEntries" then
		local recent = HistoryList()
		local max = MaxEntries()
		while #recent > max do
			tremove(recent)
		end
		self:HideDropdown()
	end
end

function AuctionSearchHistory:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Auction Search History"], L["Show recent Auction House browse searches when you focus the search box."])
	local _, maxInit = builder:Slider(category, self, "maxEntries", L["Recent Search Count"], L["How many previous browse searches to remember (account-wide)."], 3, 10, 1)

	builder:DependsOn(maxInit, enableInit)
end
