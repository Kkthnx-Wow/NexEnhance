--[[
	NexEnhance - Auction Search Fallback
	-------------------------------------------------------------------------
	On the Auction House browse tab: prefer Current Expansion Only, but when a
	search returns zero results with that filter on, widen once and retry. Re-
	enables the filter when still empty.

	Blizzard refs (Resources 12.0.7): Enum.AuctionHouseFilter.CurrentExpansionOnly,
	AuctionHouseFilterButtonMixin, AUCTION_HOUSE_BROWSE_RESULTS_UPDATED.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local L = ns.L

local C_Timer_After = C_Timer.After

local FILTER = Enum.AuctionHouseFilter.CurrentExpansionOnly

ns:RegisterDefaults({
	auctionSearch = {
		enable = true,
	},
})

local AuctionSearch = ns:NewModule("AuctionSearch", "auctionSearch", { group = "automation", title = L["Auction Search Fallback"], order = 36 })

local hooked
local browseWrapper

function AuctionSearch:AUCTION_HOUSE_BROWSE_RESULTS_UPDATED()
	if not ns.db.auctionSearch.enable then
		return
	end
	if not (C_AuctionHouse and C_AuctionHouse.GetBrowseResults) then
		return
	end

	local results = C_AuctionHouse.GetBrowseResults()
	if #results ~= 0 then
		return
	end

	local searchBar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
	local filterButton = searchBar and searchBar.FilterButton
	if not filterButton or not filterButton.filters then
		return
	end

	if filterButton.filters[FILTER] then
		filterButton:ToggleFilter(FILTER)
		searchBar:StartSearch()
	elseif not filterButton.filters[FILTER] then
		filterButton:ToggleFilter(FILTER)
	end
end

local function InstallHooks()
	if hooked or not AuctionHouseFrame then
		return
	end

	AuctionHouseFrame:HookScript("OnShow", function()
		if not ns.db.auctionSearch.enable then
			return
		end
		C_Timer_After(0.1, function()
			local filterButton = AuctionHouseFrame.SearchBar and AuctionHouseFrame.SearchBar.FilterButton
			if filterButton and not filterButton.filters[FILTER] then
				filterButton:Reset()
				filterButton:ToggleFilter(FILTER)
			end
		end)
	end)

	browseWrapper = AuctionSearch:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	hooked = true
end

function AuctionSearch:OnEnable()
	if not ns.db.auctionSearch.enable then
		return
	end
	ns:RegisterAddOnLoadedCallback("Blizzard_AuctionHouseUI", InstallHooks)
	if _G.AuctionHouseFrame then
		InstallHooks()
	end
end

function AuctionSearch:OnDisable()
	if hooked then
		ns:UnregisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", browseWrapper)
		browseWrapper = nil
		hooked = nil
	end
end

function AuctionSearch:OnSettingChanged(key, value)
	-- ApplyModuleSetting owns enable lifecycle.
	if key == "enable" then
		return
	end
end

function AuctionSearch:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Auction Search Fallback"], L["When a browse search returns no results with Current Expansion Only enabled, automatically widen the search and retry once."])
end
