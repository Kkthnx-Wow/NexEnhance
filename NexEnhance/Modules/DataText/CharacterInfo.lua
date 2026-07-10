--[[
	NexEnhance - DataText: Currency & Gold
	-------------------------------------------------------------------------
	A wealth tooltip on Blizzard's CharacterMicroButton: session gold gain/loss,
	per-character / per-realm gold (stored account-wide), faction & server
	totals, Warband bank gold, and backpack-tracked currencies. The button keeps
	its native click (opens the character pane); we only add the hover tooltip.

	GetMoney() and currency quantities have no SecretReturns in Resources 12.0.7
	— store and compare as plain numbers.
--]]

---@diagnostic disable: undefined-field, undefined-global
local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local _G = _G
local format = string.format
local ipairs, pairs, sort, wipe, type = ipairs, pairs, sort, wipe, type
local pcall = pcall

local GameTooltip = GameTooltip
local GameTooltip_SetTitle = GameTooltip_SetTitle
local MicroButtonTooltipText = MicroButtonTooltipText
local GetMoney = GetMoney
local MouseIsOver = MouseIsOver
local BreakUpLargeNumbers = BreakUpLargeNumbers

local C_CurrencyInfo = C_CurrencyInfo
local C_Bank = C_Bank
local C_Timer = C_Timer
local C_WowTokenPublic = C_WowTokenPublic
local FetchDepositedMoney = C_Bank and C_Bank.FetchDepositedMoney
local WARBAND_BANK_TYPE = (Enum and Enum.BankType and Enum.BankType.Account) or 2

local CHARACTER_BUTTON = _G.CHARACTER_BUTTON
local CURRENCY = _G.CURRENCY

local HDR = C.Colors.header
local LBL = C.Colors.label

local CLASS_COLORS = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS

ns:RegisterDefaults({
	characterInfo = {
		enable = true,
		maxCharacters = 12,
	},
})

-- Account-wide gold ledger: gold[realm][name] = copper, plus class/faction for
-- colouring and totals. Lives on ns.global so it persists across characters.
ns:RegisterDefaults({
	goldTracker = {
		gold = {},
		class = {},
		faction = {},
	},
}, "global")

local CharacterInfo = ns:NewModule("CharacterInfo", "characterInfo", { group = "datatext", title = L["Currency & Gold"], order = 70 })

local cfg
local hooksInstalled
local eventHandles = {}
local eventsRegistered = false
local started
local tokenTicker

local sessionEarned, sessionSpent = 0, 0
local warbandGold = 0

-- Reused scratch list for the sorted character rollup (no per-hover garbage).
local rollup = {}

local function ClassColor(token)
	local color = token and CLASS_COLORS and CLASS_COLORS[token]
	if color then
		return color.r, color.g, color.b
	end
	return 1, 1, 1
end

local function GetLedger()
	local db = ns.global and ns.global.goldTracker
	if not db then
		return nil
	end
	db.gold = db.gold or {}
	db.class = db.class or {}
	db.faction = db.faction or {}
	return db
end

-- Token prices arrive asynchronously: requesting an update fires
-- TOKEN_MARKET_PRICE_UPDATED, after which GetCurrentMarketPrice() is valid.
local function RequestTokenPrice()
	if C_WowTokenPublic and C_WowTokenPublic.UpdateMarketPrice then
		C_WowTokenPublic.UpdateMarketPrice()
	end
end

local function UpdateWarband()
	if not FetchDepositedMoney then
		warbandGold = 0
		return
	end
	local ok, money = pcall(FetchDepositedMoney, WARBAND_BANK_TYPE)
	if ok and money then
		warbandGold = money or 0
	end
end

-- Record the player's current money in the ledger and fold the delta into the
-- session counters. GetMoney has no SecretReturns (Resources 12.0.7).
function CharacterInfo:RecordMoney(countSession)
	local money = GetMoney()
	if not money then
		return
	end

	local db = GetLedger()
	if not db then
		return
	end

	local realm, name = C.Player.realm, C.Player.name
	db.gold[realm] = db.gold[realm] or {}
	db.class[realm] = db.class[realm] or {}
	db.faction[realm] = db.faction[realm] or {}

	local prev = db.gold[realm][name]
	if type(prev) ~= "number" then
		prev = nil
	end

	if countSession and started and prev then
		local change = money - prev
		if change > 0 then
			sessionEarned = sessionEarned + change
		elseif change < 0 then
			sessionSpent = sessionSpent - change
		end
	end

	db.gold[realm][name] = money
	db.class[realm][name] = C.Player.class
	db.faction[realm][name] = C.Player.faction
	started = true
end

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------

local function AddCurrencies()
	if not (C_CurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo) then
		return
	end

	local index = 1
	local info = C_CurrencyInfo.GetBackpackCurrencyInfo(index)
	while info do
		local quantity = info.quantity
		if info.name and quantity then
			if index == 1 then
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine(CURRENCY or "Currency", HDR.r, HDR.g, HDR.b)
			end
			local icon = info.iconFileID and format("|T%s:14:14:0:0:64:64:4:60:4:60|t ", info.iconFileID) or ""
			GameTooltip:AddDoubleLine(icon .. info.name, BreakUpLargeNumbers(quantity), 1, 1, 1, 1, 1, 1)
		end
		index = index + 1
		info = C_CurrencyInfo.GetBackpackCurrencyInfo(index)
	end
end

function CharacterInfo:BuildTooltip(button)
	if not cfg.enable then
		return
	end

	local db = GetLedger()
	if not db then
		return
	end

	-- Refresh live values.
	self:RecordMoney(false)
	UpdateWarband()

	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:ClearLines()
	GameTooltip_SetTitle(GameTooltip, MicroButtonTooltipText(CHARACTER_BUTTON, "TOGGLECHARACTER0"))

	-- Session gain / loss.
	GameTooltip:AddLine(L["Session"], HDR.r, HDR.g, HDR.b)
	GameTooltip:AddDoubleLine(L["Earned"], F.FormatMoney(sessionEarned), LBL.r, LBL.g, LBL.b, 1, 1, 1)
	GameTooltip:AddDoubleLine(L["Spent"], F.FormatMoney(sessionSpent), LBL.r, LBL.g, LBL.b, 1, 1, 1)
	if sessionEarned ~= sessionSpent then
		local gained = sessionEarned > sessionSpent
		local net = gained and (sessionEarned - sessionSpent) or (sessionSpent - sessionEarned)
		GameTooltip:AddDoubleLine(gained and L["Profit"] or L["Deficit"], F.FormatMoney(net), gained and 0 or 1, gained and 1 or 0, 0, 1, 1, 1)
	end

	-- Per-character rollup (sorted by amount), plus faction / server totals.
	wipe(rollup)
	local totalGold, totalAlliance, totalHorde = 0, 0, 0
	for realm, names in pairs(db.gold) do
		local classRealm = db.class[realm]
		local factionRealm = db.faction[realm]
		for name, amount in pairs(names) do
			if type(amount) == "number" then
				local faction = factionRealm and factionRealm[name] or ""
				rollup[#rollup + 1] = {
					name = name,
					realm = realm,
					amount = amount,
					class = classRealm and classRealm[name] or nil,
					faction = faction,
					isPlayer = (name == C.Player.name and realm == C.Player.realm),
				}
				totalGold = totalGold + amount
				if faction == "Alliance" then
					totalAlliance = totalAlliance + amount
				elseif faction == "Horde" then
					totalHorde = totalHorde + amount
				end
			end
		end
	end
	sort(rollup, function(a, b)
		return a.amount > b.amount
	end)

	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L["Characters"], HDR.r, HDR.g, HDR.b)

	local limit = cfg.maxCharacters or 12
	local useLimit = limit > 0
	local total = #rollup
	for i, g in ipairs(rollup) do
		if useLimit and i > limit then
			local hidden = total - limit
			if hidden > 0 then
				GameTooltip:AddLine(format("+%d %s", hidden, L["More"]), 0.75, 0.9, 1)
			end
			break
		end
		local r, gr, b = ClassColor(g.class)
		local label = g.name
		if g.realm ~= C.Player.realm then
			label = label .. " - " .. g.realm
		end
		if g.isPlayer then
			label = label .. " |TInterface\\COMMON\\Indicator-Green:14|t"
		end
		GameTooltip:AddDoubleLine(label, F.FormatMoney(g.amount), r, gr, b, 1, 1, 1)
	end

	GameTooltip:AddLine(" ")
	if totalAlliance > 0 and totalHorde > 0 then
		GameTooltip:AddDoubleLine(L["Alliance"], F.FormatMoney(totalAlliance), 0, 0.376, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine(L["Horde"], F.FormatMoney(totalHorde), 1, 0.2, 0.2, 1, 1, 1)
	end
	GameTooltip:AddDoubleLine(L["Total"], F.FormatMoney(totalGold), LBL.r, LBL.g, LBL.b, 1, 1, 1)
	if FetchDepositedMoney then
		GameTooltip:AddDoubleLine(L["Warband"], F.FormatMoney(warbandGold), LBL.r, LBL.g, LBL.b, 1, 1, 1)
	end

	-- WoW Token current market price (requested on a ticker; cached value here).
	-- Kept in its own section so it reads as a market rate, not part of totals.
	if C_WowTokenPublic and C_WowTokenPublic.GetCurrentMarketPrice then
		RequestTokenPrice()
		local price = C_WowTokenPublic.GetCurrentMarketPrice()
		if price then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(L["WoW Token"], HDR.r, HDR.g, HDR.b)
			GameTooltip:AddDoubleLine(L["Price"], F.FormatMoney(price), LBL.r, LBL.g, LBL.b, 1, 1, 1)
		end
	end

	-- Backpack-tracked currencies.
	AddCurrencies()

	GameTooltip:Show()
end

local function OnEnterHook(button)
	CharacterInfo:BuildTooltip(button)
end

function CharacterInfo:RefreshIfHovering()
	local button = _G.CharacterMicroButton
	if button and MouseIsOver(button) then
		self:BuildTooltip(button)
	end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

function CharacterInfo:PLAYER_ENTERING_WORLD()
	self:RecordMoney(false)
	UpdateWarband()
end

function CharacterInfo:PLAYER_MONEY()
	self:RecordMoney(true)
	self:RefreshIfHovering()
end

function CharacterInfo:ACCOUNT_MONEY()
	UpdateWarband()
	self:RefreshIfHovering()
end

function CharacterInfo:CURRENCY_DISPLAY_UPDATE()
	self:RefreshIfHovering()
end

function CharacterInfo:TOKEN_MARKET_PRICE_UPDATED()
	self:RefreshIfHovering()
end

function CharacterInfo:InstallHooks()
	if hooksInstalled then
		return
	end
	local button = _G.CharacterMicroButton
	if not button then
		return
	end
	button:HookScript("OnEnter", OnEnterHook)
	hooksInstalled = true
end

function CharacterInfo:Create()
	local button = _G.CharacterMicroButton
	if not button then
		return
	end

	self:InstallHooks()

	self:RegisterModuleEvents()

	-- Keep the token price warm: request once now, then refresh every 60s.
	if not tokenTicker and C_Timer and C_Timer.NewTicker then
		RequestTokenPrice()
		tokenTicker = C_Timer.NewTicker(60, RequestTokenPrice)
	end

	self:RecordMoney(false)
	UpdateWarband()
end

function CharacterInfo:RegisterModuleEvents()
	if eventsRegistered then
		return
	end
	eventsRegistered = true
	self:TrackEvent(eventHandles, "PLAYER_ENTERING_WORLD", "PLAYER_ENTERING_WORLD")
	self:TrackEvent(eventHandles, "PLAYER_MONEY", "PLAYER_MONEY")
	self:TrackEvent(eventHandles, "ACCOUNT_MONEY", "ACCOUNT_MONEY")
	self:TrackEvent(eventHandles, "CURRENCY_DISPLAY_UPDATE", "CURRENCY_DISPLAY_UPDATE")
	self:TrackEvent(eventHandles, "TOKEN_MARKET_PRICE_UPDATED", "TOKEN_MARKET_PRICE_UPDATED")
end

function CharacterInfo:UnregisterModuleEvents()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
end

function CharacterInfo:Stop()
	self:UnregisterModuleEvents()
	if tokenTicker then
		tokenTicker:Cancel()
		tokenTicker = nil
	end
end

function CharacterInfo:OnEnable()
	cfg = ns.db.characterInfo
	if not cfg.enable then
		return
	end
	self:Create()
end

function CharacterInfo:OnDisable()
	self:Stop()
end

function CharacterInfo:OnSettingChanged(key)
	cfg = ns.db.characterInfo
	if key == "enable" then
		-- ApplyModuleSetting owns enable lifecycle.
		return
	end
	if key == "maxCharacters" then
		self:RefreshIfHovering()
	end
end

function CharacterInfo:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Currency & Gold"], L["Show a wealth tooltip (gold, Warband, currencies) when hovering the character micro button (reload to disable)."])
	local _, maxInit = builder:Slider(category, self, "maxCharacters", L["Max Characters"], L["Maximum characters listed in the gold tooltip before collapsing the rest."], 5, 30, 1)

	builder:DependsOn(maxInit, enableInit)
end
