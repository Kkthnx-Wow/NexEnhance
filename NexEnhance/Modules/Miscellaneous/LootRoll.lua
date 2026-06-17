--[[
	NexEnhance - Loot Roll
	-------------------------------------------------------------------------
	Replaces Blizzard's group-loot roll frames with NexEnhance's own compact,
	skinned bars: an item icon (with item tooltip + Shift-compare), a quality
	coloured timer bar, and Need / Greed / Disenchant / Transmog / Pass buttons.
	Bars stack from a draggable Edit Mode anchor and recycle through a pool.

	Re-implemented from ElvUI's Misc/LootRoll.lua (tukui-org), adapted to the
	NexEnhance framework:
	  https://github.com/tukui-org/ElvUI/blob/main/ElvUI/Game/Shared/Modules/Misc/LootRoll.lua

	Suppression mirrors ElvUI: Blizzard drives group loot from UIParent's
	START_LOOT_ROLL handler (see Resources/Blizzard_UIParent/Mainline/UIParent.lua
	-> GroupLootContainer_AddRoll). Unregistering that event on UIParent stops the
	default bars from ever showing, and our module handles display instead. The
	existing AlertFrames module only repositions the now-empty GroupLootContainer,
	so the two do not fight.

	Midnight: GetLootRollItemInfo's quality can be a secret value inside
	instances, so all colouring/ilvl text is taken behind F.NotSecret - if we
	cannot read it we fall back to plain white rather than doing arithmetic on a
	secret. The roll buttons and timer never inspect secret data.
--]]

---@diagnostic disable: undefined-field, undefined-global
local _, ns = ...
local F, L, C = ns.F, ns.L, ns.C

local _G = _G
local next, wipe = next, wipe
local tinsert, tremove = table.insert, table.remove
local floor = math.floor

local CreateFrame = CreateFrame
local GameTooltip = GameTooltip
local UIParent = UIParent
local GetTime = GetTime
local IsModifiedClick = IsModifiedClick
local IsShiftKeyDown = IsShiftKeyDown
local HandleModifiedItemClick = HandleModifiedItemClick

local GetLootRollItemInfo = GetLootRollItemInfo
local GetLootRollItemLink = GetLootRollItemLink
local GetLootRollTimeLeft = GetLootRollTimeLeft
local RollOnLoot = RollOnLoot
local GetItemInfo = C_Item.GetItemInfo
local GetItemIconByID = C_Item.GetItemIconByID

-- Roll types (rollID-side constants). Fall back to literals if the globals are
-- absent on a given flavor.
local TYPE_PASS = _G.LOOT_ROLL_TYPE_PASS or 0
local TYPE_NEED = _G.LOOT_ROLL_TYPE_NEED or 1
local TYPE_GREED = _G.LOOT_ROLL_TYPE_GREED or 2
local TYPE_DISENCHANT = _G.LOOT_ROLL_TYPE_DISENCHANT or 3
local TYPE_TRANSMOG = _G.LOOT_ROLL_TYPE_TRANSMOG or 4

-- Localised button labels (Blizzard globals).
local NEED, GREED, PASS = _G.NEED, _G.GREED, _G.PASS
local ROLL_DISENCHANT, TRANSMOGRIFY = _G.ROLL_DISENCHANT, _G.TRANSMOGRIFY

ns:RegisterDefaults({
	lootRoll = {
		enable = false,
		width = 352,
		height = 36,
		maxBars = 4,
	},
})

local LootRoll = ns:NewModule("LootRoll", "lootRoll", { group = "misc", title = L["Loot Roll"], order = 41 })

-- Bars currently showing a roll, in stack order; rollID -> bar lookup; and a
-- queue of rolls waiting for a free bar when we hit maxBars. `testBars` tracks
-- the fake bars spawned by /nex lootroll so we can clear just those.
local activeBars = {}
local barByRollID = {}
local waitingRolls = {}
local testBars = {}
local barPool
local anchor

-- Per-rolltype icon tex-coords lifted from ElvUI so the stock group-loot art
-- crops the same way it does there.
local iconCoords = {
	[TYPE_PASS] = { 1.05, -0.1, 1.05, -0.1 },
	[TYPE_NEED] = { 0.05, 1.05, -0.05, 0.95 },
	[TYPE_GREED] = { 0.05, 1.05, -0.025, 0.85 },
	[TYPE_DISENCHANT] = { 0.05, 1.05, -0.05, 0.95 },
	[TYPE_TRANSMOG] = { 0, 1, 0, 1 },
}

-- ---------------------------------------------------------------------------
-- Roll buttons
-- ---------------------------------------------------------------------------
local function ApplyRollTexture(button, icon, rolltype)
	if not icon then
		return
	end
	local minX, maxX, minY, maxY = unpack(iconCoords[rolltype])
	icon:SetTexCoord(minX, maxX, minY, maxY)
	if icon == button:GetDisabledTexture() then
		icon:SetDesaturated(true)
		icon:SetAlpha(0.25)
	end
end

local function StyleRollButton(button, texture, rolltype)
	button:SetNormalTexture(texture)
	button:SetPushedTexture(texture)
	button:SetDisabledTexture(texture)
	button:SetHighlightTexture(texture)

	ApplyRollTexture(button, button:GetNormalTexture(), rolltype)
	ApplyRollTexture(button, button:GetPushedTexture(), rolltype)
	ApplyRollTexture(button, button:GetDisabledTexture(), rolltype)
	ApplyRollTexture(button, button:GetHighlightTexture(), rolltype)
end

local function ClickRoll(button)
	local bar = button.bar
	if not bar then
		return
	end
	-- Test bars have no real roll; clicking any button just dismisses them.
	if bar.isTest then
		LootRoll:ClearTestBar(bar)
	elseif bar.rollID then
		RollOnLoot(bar.rollID, button.rolltype)
	end
end

local function RollButton_OnEnter(button)
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:AddLine(button.tiptext)
	if button:IsEnabled() == false or button:IsEnabled() == 0 then
		GameTooltip:AddLine("|cffff3333" .. L["Can't Roll"])
	end
	GameTooltip:Show()
end

local function CreateRollButton(bar, texture, rolltype, tiptext)
	local button = CreateFrame("Button", nil, bar.overlay)
	button:SetScript("OnClick", ClickRoll)
	button:SetScript("OnEnter", RollButton_OnEnter)
	button:SetScript("OnLeave", _G.GameTooltip_Hide)
	button:SetMotionScriptsWhileDisabled(true)
	button:SetHitRectInsets(3, 3, 3, 3)

	StyleRollButton(button, texture, rolltype)

	button.bar = bar
	button.rolltype = rolltype
	button.tiptext = tiptext

	button.count = button:CreateFontString(nil, "OVERLAY")
	button.count:SetFontObject(_G.NumberFontNormalSmall)
	button.count:SetPoint("BOTTOMRIGHT", 2, -2)

	return button
end

-- ---------------------------------------------------------------------------
-- Item button (icon + tooltip)
-- ---------------------------------------------------------------------------
local function ItemButton_ShowTip(button, event)
	local bar = button.bar
	if not (button.rollID or (bar and bar.isTest and button.link)) then
		return
	end
	if event == "MODIFIER_STATE_CHANGED" and not button:IsMouseOver() then
		return
	end

	GameTooltip:SetOwner(button, "ANCHOR_TOPLEFT")
	if bar and bar.isTest then
		GameTooltip:SetHyperlink(button.link)
	else
		GameTooltip:SetLootRollItem(button.rollID)
	end
	if IsShiftKeyDown() then
		_G.GameTooltip_ShowCompareItem()
	end
end

local function ItemButton_OnClick(button)
	if IsModifiedClick() and button.link then
		HandleModifiedItemClick(button.link)
	end
end

-- ---------------------------------------------------------------------------
-- Timer bar
-- ---------------------------------------------------------------------------
local function StatusBar_OnUpdate(status, elapsed)
	local bar = status.bar

	status.elapsed = (status.elapsed or 0) + elapsed
	if status.elapsed < 0.1 then
		return
	end
	status.elapsed = 0

	-- Test bars run a self-driven countdown since there's no real roll behind
	-- them; real bars read the remaining time from the loot API.
	if bar.isTest then
		local timeLeft = (bar.testEnd or 0) - GetTime()
		if timeLeft <= 0 then
			LootRoll:ClearTestBar(bar)
		else
			status:SetValue(timeLeft)
		end
		return
	end

	if not bar.rollID then
		return
	end

	local timeLeft = GetLootRollTimeLeft(bar.rollID)
	if timeLeft <= 0 then
		LootRoll:ClearBar(bar)
	else
		status:SetValue(timeLeft)
	end
end

-- ---------------------------------------------------------------------------
-- Bar construction / pooling
-- ---------------------------------------------------------------------------
-- How far the tooltip border art reaches inward from the frame edge. Content
-- (status fill, icon) is inset by this so it sits inside the visible border line
-- rather than bleeding out underneath it.
local BORDER_INSET = 4
local BACKGROUND_INSET = 2

-- Tooltip-art border drawn ON TOP of a frame's content (modelled on the
-- Minimap module): a dedicated child frame at a high frame level with no
-- background, so the border line is never hidden behind a status-bar fill,
-- icon, or overlay the way a backdrop sitting behind the frame would be.
local function AddTopBorder(frame)
	local border = CreateFrame("Frame", nil, frame)
	border:SetAllPoints()
	F.CreateTooltipBackdrop(border, {
		edgeSize = 12,
		noBackground = true,
		frameLevel = frame:GetFrameLevel() + 20,
	})
	return border
end

local function LayoutRollButtons(bar, showTransmog)
	bar.pass:ClearAllPoints()
	bar.disenchant:ClearAllPoints()
	bar.transmog:ClearAllPoints()
	bar.greed:ClearAllPoints()
	bar.need:ClearAllPoints()

	bar.transmog:SetShown(showTransmog)

	bar.pass:SetPoint("RIGHT", bar.overlay, "RIGHT", -BORDER_INSET - 2, 0)
	bar.disenchant:SetPoint("RIGHT", bar.pass, "LEFT", -2, 0)
	if showTransmog then
		bar.transmog:SetPoint("RIGHT", bar.disenchant, "LEFT", -2, 0)
		bar.greed:SetPoint("RIGHT", bar.transmog, "LEFT", -2, 0)
	else
		bar.greed:SetPoint("RIGHT", bar.disenchant, "LEFT", -2, 0)
	end
	bar.need:SetPoint("RIGHT", bar.greed, "LEFT", -2, 0)
end

local function CreateBar()
	local db = ns.db.lootRoll
	local bar = CreateFrame("Frame", nil, UIParent)
	bar:SetSize(db.width, db.height)
	bar:Hide()

	-- Dark fill spanning the whole frame, behind everything. This is what shows
	-- through under the border edge and in the depleted part of the timer, so
	-- the coloured fill can be inset inside the border without leaving a gap.
	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", BACKGROUND_INSET, -BACKGROUND_INSET)
	bg:SetPoint("BOTTOMRIGHT", -BACKGROUND_INSET, BACKGROUND_INSET)
	bg:SetColorTexture(0.06, 0.06, 0.06, 0.9)
	bar.bg = bg

	-- Status fill is inset inside the border line so the coloured timer texture
	-- never bleeds out past (or hides) the border.
	local status = CreateFrame("StatusBar", nil, bar)
	status:SetPoint("TOPLEFT", BORDER_INSET, -BORDER_INSET)
	status:SetPoint("BOTTOMRIGHT", -BORDER_INSET, BORDER_INSET)
	status:SetFrameLevel(bar:GetFrameLevel() + 1)
	status:SetStatusBarTexture(C.Media.Textures.statusbar)
	status:SetMinMaxValues(0, 1)
	status.bar = bar
	status:SetScript("OnUpdate", StatusBar_OnUpdate)
	bar.status = status

	local spark = status:CreateTexture(nil, "ARTWORK")
	spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
	spark:SetBlendMode("ADD")
	spark:SetWidth(16)
	spark:SetPoint("TOP", status:GetStatusBarTexture(), "TOPRIGHT")
	spark:SetPoint("BOTTOM", status:GetStatusBarTexture(), "BOTTOMRIGHT")
	status.spark = spark

	-- Overlay holds everything that must draw above the timer fill (a child
	-- frame renders over its parent's regions, so fontstrings on `bar` would be
	-- hidden behind the status bar).
	local overlay = CreateFrame("Frame", nil, bar)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(status:GetFrameLevel() + 5)
	bar.overlay = overlay

	-- Item icon button, anchored just outside the left edge.
	local button = CreateFrame("Button", nil, bar)
	button:SetPoint("RIGHT", bar, "LEFT", -2, 0)
	button:SetSize(db.height, db.height)
	button:SetFrameLevel(overlay:GetFrameLevel())
	button:RegisterEvent("MODIFIER_STATE_CHANGED")
	button:SetScript("OnEvent", ItemButton_ShowTip)
	button:SetScript("OnEnter", ItemButton_ShowTip)
	button:SetScript("OnLeave", _G.GameTooltip_Hide)
	button:SetScript("OnClick", ItemButton_OnClick)
	button.bar = bar
	bar.button = button

	local buttonBG = button:CreateTexture(nil, "BACKGROUND")
	buttonBG:SetPoint("TOPLEFT", BACKGROUND_INSET, -BACKGROUND_INSET)
	buttonBG:SetPoint("BOTTOMRIGHT", -BACKGROUND_INSET, BACKGROUND_INSET)
	buttonBG:SetColorTexture(0.06, 0.06, 0.06, 0.9)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", BORDER_INSET, -BORDER_INSET)
	icon:SetPoint("BOTTOMRIGHT", -BORDER_INSET, BORDER_INSET)
	icon:SetTexCoord(unpack(C.TexCoord))
	button.icon = icon

	-- Border on top, after the icon, so it frames the icon the same way the bar
	-- border frames the fill.
	AddTopBorder(button)

	local stack = button:CreateFontString(nil, "OVERLAY")
	stack:SetFontObject(_G.NumberFontNormal)
	stack:SetPoint("BOTTOMRIGHT", -3, 4)
	button.stack = stack

	local ilvl = button:CreateFontString(nil, "OVERLAY")
	ilvl:SetFontObject(_G.NumberFontNormal)
	ilvl:SetPoint("TOPLEFT", 3, -4)
	button.ilvl = ilvl

	-- Roll buttons (right -> left): Pass, Disenchant, Transmog, Greed, Need.
	bar.pass = CreateRollButton(bar, [[Interface\Buttons\UI-GroupLoot-Pass-Up]], TYPE_PASS, PASS)
	bar.disenchant = CreateRollButton(bar, [[Interface\Buttons\UI-GroupLoot-DE-Up]], TYPE_DISENCHANT, ROLL_DISENCHANT)
	bar.transmog = CreateRollButton(bar, [[Interface\MINIMAP\TRACKING\Transmogrifier]], TYPE_TRANSMOG, TRANSMOGRIFY)
	bar.greed = CreateRollButton(bar, [[Interface\Buttons\UI-GroupLoot-Coin-Up]], TYPE_GREED, GREED)
	bar.need = CreateRollButton(bar, [[Interface\Buttons\UI-GroupLoot-Dice-Up]], TYPE_NEED, NEED)

	-- Square buttons at ~55% of the inner height so they stay compact and
	-- vertically centred rather than filling the whole bar.
	local btnSize = floor((db.height - (BORDER_INSET * 2)) * 0.94)
	bar.pass:SetSize(btnSize, btnSize)
	bar.disenchant:SetSize(btnSize, btnSize)
	bar.transmog:SetSize(btnSize, btnSize)
	bar.greed:SetSize(btnSize, btnSize)
	bar.need:SetSize(btnSize, btnSize)

	LayoutRollButtons(bar, true)

	-- Bind tag + item name, filling the space to the left of the roll buttons.
	local bind = overlay:CreateFontString(nil, "OVERLAY")
	bind:SetFontObject(_G.GameFontNormal)
	bind:SetPoint("RIGHT", bar.need, "LEFT", -4, 0)
	bar.bind = bind

	local name = overlay:CreateFontString(nil, "OVERLAY")
	name:SetFontObject(_G.GameFontNormalOutline)
	name:SetShadowColor(0, 0, 0, 0)
	name:SetShadowOffset(0, 0)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	name:SetPoint("LEFT", overlay, "LEFT", 4, 0)
	name:SetPoint("RIGHT", bind, "LEFT", -2, 0)
	bar.name = name

	-- Border last so it draws on top of the fill, icon and overlay content.
	AddTopBorder(bar)

	return bar
end

local function ResetBar(bar)
	bar.rollID = nil
	bar.isTest = nil
	bar.testEnd = nil
	if bar.button then
		bar.button.rollID = nil
		bar.button.link = nil
	end
end

-- ---------------------------------------------------------------------------
-- Anchoring
-- ---------------------------------------------------------------------------
function LootRoll:UpdateAnchors()
	if not anchor then
		return
	end
	local spacing = 2
	for i, bar in next, activeBars do
		bar:ClearAllPoints()
		if i == 1 then
			bar:SetPoint("TOP", anchor, "BOTTOM", 0, -spacing)
		else
			bar:SetPoint("TOP", activeBars[i - 1], "BOTTOM", 0, -spacing)
		end
	end
end

function LootRoll:ClearBar(bar)
	if bar.rollID then
		barByRollID[bar.rollID] = nil
	end

	for i = #activeBars, 1, -1 do
		if activeBars[i] == bar then
			tremove(activeBars, i)
		end
	end

	bar:Release()
	self:UpdateAnchors()

	-- Promote queued rolls into any freed slots. We loop (rather than pulling a
	-- single entry) so a roll that expired while waiting - START_LOOT_ROLL bails
	-- on it without taking a slot - is skipped and the next one fills the gap.
	while waitingRolls[1] and #activeBars < ns.db.lootRoll.maxBars do
		local pending = tremove(waitingRolls, 1)
		self:START_LOOT_ROLL(pending.rollID, pending.rollTime)
	end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
function LootRoll:START_LOOT_ROLL(rollID, rollTime)
	if not rollID or barByRollID[rollID] then
		return
	end

	local texture, name, count, quality, _, canNeed, canGreed, canDisenchant, _, _, _, _, canTransmog = GetLootRollItemInfo(rollID)
	if not name then
		return
	end

	local db = ns.db.lootRoll
	if #activeBars >= db.maxBars then
		tinsert(waitingRolls, { rollID = rollID, rollTime = rollTime })
		return
	end

	local bar = barPool:Acquire()
	bar:SetSize(db.width, db.height)
	bar.rollID = rollID

	tinsert(activeBars, bar)
	barByRollID[rollID] = bar

	-- Item details
	local link = GetLootRollItemLink(rollID)
	local itemLevel, itemEquipLoc
	if link then
		_, _, _, itemLevel, _, _, _, _, itemEquipLoc = GetItemInfo(link)
	end

	bar.button.rollID = rollID
	bar.button.link = link
	bar.button.icon:SetTexture(texture)
	bar.button.stack:SetShown(count and count > 1)
	bar.button.stack:SetText(count or "")

	-- Quality colour (secret-safe). Default to white when we can't read quality.
	local r, g, b = 1, 1, 1
	if F.NotSecret(quality) and quality then
		local qc = C.QualityColors[quality]
		if qc then
			r, g, b = qc.r, qc.g, qc.b
		end
	end

	bar.name:SetText(name)
	bar.name:SetTextColor(r, g, b)

	-- Item level for equippable items only.
	local showIlvl = itemEquipLoc and itemEquipLoc ~= "" and F.NotSecret(itemLevel) and itemLevel and itemLevel > 1
	bar.button.ilvl:SetShown(showIlvl)
	if showIlvl then
		bar.button.ilvl:SetText(itemLevel)
		bar.button.ilvl:SetTextColor(r, g, b)
	end

	-- Roll button availability + counts reset.
	bar.need.count:SetText("")
	bar.greed.count:SetText("")
	bar.pass.count:SetText("")
	bar.disenchant.count:SetText("")
	bar.transmog.count:SetText("")

	bar.need:SetEnabled(canNeed)
	bar.greed:SetEnabled(canGreed and not canTransmog)
	bar.disenchant:SetEnabled(canDisenchant)
	bar.transmog:SetEnabled(canTransmog)
	LayoutRollButtons(bar, canTransmog)

	-- Timer
	bar.status:SetStatusBarColor(r, g, b, 0.7)
	bar.status.spark:SetVertexColor(r, g, b, 0.9)
	bar.status.elapsed = 0
	bar.status:SetMinMaxValues(0, rollTime or 1)
	bar.status:SetValue(rollTime or 1)

	bar:Show()
	self:UpdateAnchors()
end

function LootRoll:CANCEL_LOOT_ROLL(rollID)
	local bar = barByRollID[rollID]
	if bar then
		self:ClearBar(bar)
		return
	end

	-- Not shown yet: drop it from the queue so it can't be promoted later.
	for i = #waitingRolls, 1, -1 do
		if waitingRolls[i].rollID == rollID then
			tremove(waitingRolls, i)
		end
	end
end

function LootRoll:CANCEL_ALL_LOOT_ROLLS()
	wipe(waitingRolls)
	for i = #activeBars, 1, -1 do
		local bar = activeBars[i]
		if bar.rollID then
			barByRollID[bar.rollID] = nil
		end
		bar:Release()
		activeBars[i] = nil
	end
	wipe(barByRollID)
	wipe(testBars)
end

-- ---------------------------------------------------------------------------
-- Test bars (/nex lootroll)
-- ---------------------------------------------------------------------------
-- A spread of item IDs so the preview shows different qualities, an equippable
-- item (item level shown) and a non-equip stack.
local TEST_ITEMS = {
	19019, -- Thunderfury (legendary weapon)
	18832, -- Brutality Blade (epic weapon)
	14156, -- Big Bag of Enchantment (rare)
	6948, -- Hearthstone (common, non-equip)
}

function LootRoll:ClearTestBar(bar)
	for i = #testBars, 1, -1 do
		if testBars[i] == bar then
			tremove(testBars, i)
		end
	end
	for i = #activeBars, 1, -1 do
		if activeBars[i] == bar then
			tremove(activeBars, i)
		end
	end
	bar:Release()
	self:UpdateAnchors()
end

local function SpawnTestBar(index, itemID, seconds)
	local db = ns.db.lootRoll
	local bar = barPool:Acquire()
	bar:SetSize(db.width, db.height)
	bar.isTest = true
	bar.rollID = nil

	tinsert(activeBars, bar)
	tinsert(testBars, bar)

	local name, link, quality, itemLevel, _, _, _, _, itemEquipLoc = GetItemInfo(itemID)
	name = name or ("Test Item " .. index)
	local texture = GetItemIconByID(itemID) or 134400 -- ? mark fallback

	bar.button.rollID = nil
	bar.button.link = link
	bar.button.icon:SetTexture(texture)
	bar.button.stack:Hide()

	local r, g, b = 1, 1, 1
	if quality then
		local qc = C.QualityColors[quality]
		if qc then
			r, g, b = qc.r, qc.g, qc.b
		end
	end

	bar.name:SetText(name)
	bar.name:SetTextColor(r, g, b)

	local showIlvl = itemEquipLoc and itemEquipLoc ~= "" and itemLevel and itemLevel > 1
	bar.button.ilvl:SetShown(showIlvl)
	if showIlvl then
		bar.button.ilvl:SetText(itemLevel)
		bar.button.ilvl:SetTextColor(r, g, b)
	end

	bar.need.count:SetText("")
	bar.greed.count:SetText("")
	bar.pass.count:SetText("")
	bar.disenchant.count:SetText("")
	bar.transmog.count:SetText("")
	bar.need:SetEnabled(true)
	bar.greed:SetEnabled(true)
	bar.disenchant:SetEnabled(true)
	bar.transmog:SetEnabled(false)
	LayoutRollButtons(bar, false)

	bar.status:SetStatusBarColor(r, g, b, 0.7)
	bar.status.spark:SetVertexColor(r, g, b, 0.9)
	bar.status.elapsed = 0
	bar.testEnd = GetTime() + seconds
	bar.status:SetMinMaxValues(0, seconds)
	bar.status:SetValue(seconds)

	bar:Show()
end

-- Toggle a set of fake roll bars for previewing layout/position. Click any roll
-- button (or wait for the timer) to dismiss a bar. Runs without a real loot
-- roll, so it also works solo and out of combat.
function LootRoll:ToggleTest()
	self:EnsureInit()

	if #testBars > 0 then
		for i = #testBars, 1, -1 do
			self:ClearTestBar(testBars[i])
		end
		F.Print(F.Colorize(L["Loot Roll"] .. ": ", "brand") .. L["Test bars hidden."])
		return
	end

	for i = 1, #TEST_ITEMS do
		SpawnTestBar(i, TEST_ITEMS[i], 25 + i * 10)
	end
	self:UpdateAnchors()
	F.Print(F.Colorize(L["Loot Roll"] .. ": ", "brand") .. L["Test bars shown - click a button or wait to dismiss."])
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
-- Build the pool + draggable anchor. Kept separate from Setup so the test
-- command can preview bars without suppressing Blizzard's real loot frames.
function LootRoll:EnsureInit()
	if self.initDone then
		return
	end
	self.initDone = true

	barPool = F.CreatePool(CreateBar, ResetBar)

	anchor = CreateFrame("Frame", nil, UIParent)
	anchor:SetSize(ns.db.lootRoll.width, ns.db.lootRoll.height)
	F.CreateMover(anchor, "lootRoll", L["Loot Roll"], "CENTER", 0, 500)
end

function LootRoll:Setup()
	if self.setupDone then
		return
	end
	self.setupDone = true

	self:EnsureInit()

	-- Stop Blizzard's default group-loot bars: UIParent drives them from
	-- START_LOOT_ROLL (see Resources/.../UIParent.lua), so removing those events
	-- there hands display entirely to us.
	UIParent:UnregisterEvent("START_LOOT_ROLL")
	UIParent:UnregisterEvent("CANCEL_LOOT_ROLL")

	self:RegisterEvent("START_LOOT_ROLL")
	self:RegisterEvent("CANCEL_LOOT_ROLL")
	self:RegisterEvent("CANCEL_ALL_LOOT_ROLLS")
end

function LootRoll:OnEnable()
	if not ns.db.lootRoll.enable then
		return
	end
	self:Setup()
end

function LootRoll:OnSettingChanged(key, value)
	if key == "enable" and value then
		self:Setup()
	end
end

function LootRoll:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Loot Roll"], L["Replace the default group loot roll bars with NexEnhance's own (reload to disable)."])
	builder:Slider(category, self, "maxBars", L["Max Bars"], L["How many roll bars can show at once; extra rolls queue for a free slot."], 1, 10, 1)
	builder:Slider(category, self, "width", L["Width"], L["Width of each loot roll bar."], 200, 500, 4)
	builder:Slider(category, self, "height", L["Height"], L["Height of each loot roll bar."], 24, 64, 2)
end
