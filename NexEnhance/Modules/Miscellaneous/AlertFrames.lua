--[[
	NexEnhance - Alert Frames
	-------------------------------------------------------------------------
	Re-anchors Blizzard's alert popups (achievements, loot rolls, world quest
	rewards, etc.) to a single fixed point near the top of the screen and makes
	the group-loot roll bars stack cleanly with them. Optionally suppresses the
	Talking Head frame.

	The anchor registers with Edit Mode (LibEditMode) so you can drag it.
	Re-anchoring uses hooksecurefunc only — no taint.
--]]

-- luacheck: globals GroupLootContainer AchievementAlertSystem AchievementShield_SetPoints AchievementFrame_LoadUI AlertFrame_PauseOutAnimation AlertFrame_ShowNewAlert LootAlertSystem MoneyWonAlertSystem LOOT_SOURCE_TRADING_POST
---@diagnostic disable: undefined-field
local _, ns = ...
local F, L = ns.F, ns.L

local _G = _G
local format = string.format
local select = select
local ipairs = ipairs
local tremove = table.remove
local wipe = wipe
local hooksecurefunc = hooksecurefunc
local CreateFrame = CreateFrame
local UIParent = UIParent
local AlertFrame = AlertFrame
local GroupLootContainer = GroupLootContainer
local C_Item = C_Item
local C_CurrencyInfo = C_CurrencyInfo
local Constants = Constants

ns:RegisterDefaults({
	alertFrames = {
		enable = true,
		hideTalkingHead = false,
		stackSpacing = 0,
	},
})

local AlertFrames = ns:NewModule("AlertFrames", "alertFrames", { group = "alerts", title = L["Alert Frames"], order = 10 })

local eventHandles = {}
local eventsRegistered = false
local hooksInstalled = false
local testFrames = {}
local testAlertSession = false
local alertShowSequence = 0

-- Transparent padding in toast templates (achievement/loot art) reads as extra gap
-- when anchoring frame TOP/BOTTOM edges; trim pulls stacks visually tighter.
local STACK_ART_TRIM = 6

-- /nex alerttest samples — mirrors real AlertFrame event paths (AlertFrames.lua).
-- Achievement IDs: Level 10 / 20; item 6948 = Hearthstone.
local TEST_ALERTS = {
	{ kind = "achievement", id = 6 },
	{ kind = "achievement", id = 7 },
	{ kind = "loot", itemID = 6948, quantity = 1 },
	{ kind = "money", amount = 12500 },
	{ kind = "tradingPost", amount = 50 },
}

-- Current stacking direction; synced before each anchor pass from the mover position.
local POSITION, ANCHOR_POINT = "TOP", "BOTTOM"
local parentFrame

local function db()
	return ns.db.alertFrames
end

local function IsActive()
	return db().enable and parentFrame ~= nil
end

local function GetStackSpacing()
	return db().stackSpacing or 0
end

local function GetStackYOffset()
	-- Add trim so spacing 0 pulls frames slightly together (toast art has dead padding).
	local spacing = GetStackSpacing() + STACK_ART_TRIM
	if POSITION == "TOP" then
		return -spacing
	end
	return spacing
end

local scratchAlerts = {}
local scratchSeen = {}
local scratchCollectOrder = {}

local function GetQueuedAlertsInStackOrder(pool)
	wipe(scratchAlerts)
	wipe(scratchSeen)
	wipe(scratchCollectOrder)
	local collectIdx = 0
	for alertFrame in pool:EnumerateActive() do
		-- During pool release a frame can still be "active" while anchors are cleared;
		-- skip hidden frames so we never sort or reposition stale entries.
		if alertFrame:IsShown() and not scratchSeen[alertFrame] then
			scratchSeen[alertFrame] = true
			collectIdx = collectIdx + 1
			scratchCollectOrder[alertFrame] = collectIdx
			scratchAlerts[#scratchAlerts + 1] = alertFrame
		end
	end
	table.sort(scratchAlerts, function(a, b)
		local orderA = a.nexShowSequence or 0
		local orderB = b.nexShowSequence or 0
		if orderA ~= orderB then
			return orderA < orderB
		end
		-- Never compare frame objects or call GetTop() here (tables/userdata can't use
		-- <, and cleared anchors make GetTop() nil or secret during pool release).
		return (scratchCollectOrder[a] or 0) < (scratchCollectOrder[b] or 0)
	end)
	return scratchAlerts
end

local function RefreshAlertLayout()
	if not IsActive() then
		return
	end
	if AlertFrame and AlertFrame.UpdateAnchors then
		AlertFrame:UpdateAnchors()
	end
	if GroupLootContainer and GroupLootContainer_Update then
		GroupLootContainer_Update(GroupLootContainer)
	end
end

-- ---------------------------------------------------------------------------
-- Stack spacing between alert popups (configurable in settings)
-- ---------------------------------------------------------------------------
local function AlertFrame_SetPoint(self, relativeAlert)
	self:ClearAllPoints()
	self:SetPoint(POSITION, relativeAlert, ANCHOR_POINT, 0, GetStackYOffset())
end

local function AlertFrame_AdjustQueuedAnchors(self, relativeAlert)
	local alerts = GetQueuedAlertsInStackOrder(self.alertFramePool)
	for i = 1, #alerts do
		AlertFrame_SetPoint(alerts[i], relativeAlert)
		relativeAlert = alerts[i]
	end
	return relativeAlert
end

local function AlertFrame_AdjustAnchors(self, relativeAlert)
	if self.alertFrame:IsShown() then
		AlertFrame_SetPoint(self.alertFrame, relativeAlert)
		return self.alertFrame
	end
	return relativeAlert
end

local function AlertFrame_AdjustAnchorsNonAlert(self, relativeAlert)
	if self.anchorFrame:IsShown() then
		AlertFrame_SetPoint(self.anchorFrame, relativeAlert)
		return self.anchorFrame
	end
	return relativeAlert
end

local function AlertFrame_AdjustPosition(subSystem)
	if not IsActive() then
		return
	end
	if subSystem.alertFramePool then
		subSystem.AdjustAnchors = AlertFrame_AdjustQueuedAnchors
	elseif not subSystem.anchorFrame then
		subSystem.AdjustAnchors = AlertFrame_AdjustAnchors
	elseif subSystem.anchorFrame then
		subSystem.AdjustAnchors = AlertFrame_AdjustAnchorsNonAlert
	end
end

local function SyncAnchorDirection(alertContainer)
	local y = select(2, parentFrame:GetCenter())
	local screenHeight = UIParent:GetTop()
	if y and screenHeight and y > screenHeight / 2 then
		POSITION, ANCHOR_POINT = "TOP", "BOTTOM"
	else
		POSITION, ANCHOR_POINT = "BOTTOM", "TOP"
	end

	-- Stack from the mover anchor (Blizzard AlertContainerMixin.baseAnchorFrame).
	if alertContainer.SetBaseAnchorFrame then
		alertContainer:SetBaseAnchorFrame(parentFrame)
	end
	if GroupLootContainer then
		GroupLootContainer:ClearAllPoints()
		GroupLootContainer:SetPoint(POSITION, parentFrame)
	end
end

-- Re-run the anchor chain with current POSITION/spacing. Blizzard's post-hook
-- UpdateAnchors pass can run before direction is synced; this fixes spacing.
local function RepositionAllAlerts(alertContainer)
	alertContainer:CleanAnchorPriorities()
	local relativeFrame = alertContainer.baseAnchorFrame or alertContainer
	for _, subSystem in ipairs(alertContainer.alertFrameSubSystems) do
		AlertFrame_AdjustPosition(subSystem)
		local resultFrame = subSystem:AdjustAnchors(relativeFrame)
		if not resultFrame or not resultFrame.IsInDefaultPosition or resultFrame:IsInDefaultPosition() then
			relativeFrame = resultFrame
		end
	end
end

local function OnAlertFrameUpdateAnchors(alertContainer)
	if not IsActive() then
		return
	end
	SyncAnchorDirection(alertContainer)
	RepositionAllAlerts(alertContainer)
	if GroupLootContainer and GroupLootContainer_Update then
		GroupLootContainer_Update(GroupLootContainer)
	end
end

local function UpdateGroupLootContainer(self)
	if not IsActive() then
		return
	end
	local yOffset = GetStackYOffset()
	local lastIdx
	for i = 1, self.maxIndex do
		local frame = self.rollFrames[i]
		if frame then
			frame:ClearAllPoints()
			frame:SetPoint("CENTER", self, POSITION, 0, self.reservedSize * (i - 1 + 0.5) * yOffset / 10)
			lastIdx = i
		end
	end

	if lastIdx then
		self:SetHeight(self.reservedSize * lastIdx)
		self:Show()
	else
		self:Hide()
	end
end

-- ---------------------------------------------------------------------------
-- Test preview (/nex alerttest) — Blizzard AchievementAlertSystem + frozen anims
-- ---------------------------------------------------------------------------
local function StopTestAlertAnimations(frame)
	if AlertFrame_PauseOutAnimation then
		AlertFrame_PauseOutAnimation(frame)
	end
	if frame.animIn then
		frame.animIn:Stop()
	end
	if frame.waitAndAnimOut then
		frame.waitAndAnimOut:Stop()
	end
	if frame.glow then
		if frame.glow.animIn then
			frame.glow.animIn:Stop()
		end
		frame.glow:Hide()
	end
	if frame.shine then
		if frame.shine.animIn then
			frame.shine.animIn:Stop()
		end
		frame.shine:Hide()
	end
	frame:SetAlpha(1)
end

local function CaptureTestAlert(frame)
	StopTestAlertAnimations(frame)
	frame.nexTestAlert = true
	testFrames[#testFrames + 1] = frame
end

local TEST_ALERT_SYSTEMS = {
	"AchievementAlertSystem",
	"LootAlertSystem",
	"MoneyWonAlertSystem",
}

local function ClearTestQueues()
	for i = 1, #TEST_ALERT_SYSTEMS do
		local system = _G[TEST_ALERT_SYSTEMS[i]]
		if system and system.queuedAlerts then
			wipe(system.queuedAlerts)
		end
	end
end

local function ClearTestFrames()
	for i = 1, #testFrames do
		local frame = testFrames[i]
		if frame then
			frame.nexTestAlert = nil
			StopTestAlertAnimations(frame)
			frame:Hide()
		end
	end
	wipe(testFrames)
	ClearTestQueues()
	RefreshAlertLayout()
end

-- AchievementAlertSystem:SetUp needs AchievementShield_SetPoints (Blizzard_AchievementUI).
local function EnsureAchievementUI()
	if AchievementShield_SetPoints then
		return true
	end
	if AchievementFrame_LoadUI then
		AchievementFrame_LoadUI()
	end
	return AchievementShield_SetPoints ~= nil
end

local function QueueTestAlert(spec)
	if spec.kind == "achievement" then
		if AchievementAlertSystem then
			AchievementAlertSystem:AddAlert(spec.id, true)
		end
	elseif spec.kind == "loot" then
		if not LootAlertSystem or not C_Item or not C_Item.GetItemLinkByID then
			return
		end
		local link = C_Item.GetItemLinkByID(spec.itemID)
		if link then
			LootAlertSystem:AddAlert(link, spec.quantity or 1)
		end
	elseif spec.kind == "money" then
		if MoneyWonAlertSystem then
			MoneyWonAlertSystem:AddAlert(spec.amount or 10000)
		end
	elseif spec.kind == "tradingPost" then
		-- PERKS_PROGRAM_CURRENCY_AWARDED path (AlertFrames.lua).
		if not LootAlertSystem or not C_CurrencyInfo or not Constants then
			return
		end
		local amount = spec.amount or 50
		local currencyID = Constants.CurrencyConsts.CURRENCY_ID_PERKS_PROGRAM_DISPLAY_INFO
		local link = C_CurrencyInfo.GetCurrencyLink(currencyID, amount)
		if link then
			LootAlertSystem:AddAlert(link, amount, nil, nil, nil, true, false, LOOT_SOURCE_TRADING_POST)
		end
	end
end

function AlertFrames:ToggleTest()
	if not IsActive() then
		F.Print(F.Colorize(L["Alert Frames"] .. ": ", "brand") .. L["Module unavailable."])
		return
	end

	if #testFrames > 0 then
		ClearTestFrames()
		F.Print(F.Colorize(L["Alert Frames"] .. ": ", "brand") .. L["Test alerts hidden."])
		return
	end

	if not EnsureAchievementUI() then
		F.Print(F.Colorize(L["Alert Frames"] .. ": ", "brand") .. L["Test alerts unavailable - achievement UI not loaded."])
		return
	end

	if not LootAlertSystem or not MoneyWonAlertSystem then
		F.Print(F.Colorize(L["Alert Frames"] .. ": ", "brand") .. L["Test alerts unavailable - alert UI not loaded."])
		return
	end

	-- Same AddAlert paths as live events; hook freezes glow/intro before it paints white.
	testAlertSession = true
	for i = 1, #TEST_ALERTS do
		QueueTestAlert(TEST_ALERTS[i])
	end
	testAlertSession = false

	if #testFrames == 0 then
		F.Print(F.Colorize(L["Alert Frames"] .. ": ", "brand") .. L["Test alerts unavailable - alert UI not loaded."])
		return
	end

	RefreshAlertLayout()
	F.Print(F.Colorize(L["Alert Frames"] .. ": ", "brand") .. L["Test alerts shown - /nex alerttest to hide."])
end

-- ---------------------------------------------------------------------------
-- Talking Head
-- ---------------------------------------------------------------------------
local talkingHeadHidden
local function NoTalkingHeads()
	if not db().hideTalkingHead then
		return
	end
	local frame = _G.TalkingHeadFrame
	if not frame or talkingHeadHidden then
		return
	end

	talkingHeadHidden = true
	frame:UnregisterAllEvents()
	hooksecurefunc(frame, "Show", function(self)
		self:Hide()
	end)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function AlertFrames:ADDON_LOADED(addon)
	if addon == "Blizzard_TalkingHeadUI" then
		NoTalkingHeads()
	end
end

function AlertFrames:InstallHooks()
	if hooksInstalled then
		return
	end
	hooksInstalled = true

	GroupLootContainer:EnableMouse(false)
	GroupLootContainer.ignoreFramePositionManager = true

	for index = #AlertFrame.alertFrameSubSystems, 1, -1 do
		local subSystem = AlertFrame.alertFrameSubSystems[index]
		if subSystem.anchorFrame and subSystem.anchorFrame == _G.TalkingHeadFrame then
			tremove(AlertFrame.alertFrameSubSystems, index)
		else
			AlertFrame_AdjustPosition(subSystem)
		end
	end

	hooksecurefunc(AlertFrame, "AddAlertFrameSubSystem", function(_, subSystem)
		AlertFrame_AdjustPosition(subSystem)
	end)

	hooksecurefunc(AlertFrame, "UpdateAnchors", OnAlertFrameUpdateAnchors)
	hooksecurefunc("GroupLootContainer_Update", UpdateGroupLootContainer)

	if AlertFrame_ShowNewAlert then
		hooksecurefunc("AlertFrame_ShowNewAlert", function(frame)
			alertShowSequence = alertShowSequence + 1
			frame.nexShowSequence = alertShowSequence
			if testAlertSession then
				CaptureTestAlert(frame)
			end
		end)
	end
end

function AlertFrames:OnEnable()
	if not db().enable then
		return
	end

	if not parentFrame then
		parentFrame = CreateFrame("Frame", nil, UIParent)
		parentFrame:SetSize(200, 30)
		F.CreateMover(parentFrame, "alertFrames", L["Alert Frames"], "TOP", 0, -40)
	end

	self:InstallHooks()
	RefreshAlertLayout()
	NoTalkingHeads()
	self:RegisterModuleEvents()
end

function AlertFrames:RegisterModuleEvents()
	if eventsRegistered then
		return
	end
	eventsRegistered = true
	self:TrackEvent(eventHandles, "ADDON_LOADED", "ADDON_LOADED")
end

function AlertFrames:UnregisterModuleEvents()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
end

function AlertFrames:OnDisable()
	ClearTestFrames()
	self:UnregisterModuleEvents()
end

function AlertFrames:OnSettingChanged(key, value)
	-- ApplyModuleSetting owns enable lifecycle.
	if key == "enable" then
		return
	end
	NoTalkingHeads()
	if key == "stackSpacing" then
		RefreshAlertLayout()
	end
end

function AlertFrames:OnInitialize()
	local cfg = db()
	-- One-time: old builds defaulted stack spacing to 10 — huge gaps in-game.
	if not cfg._stackSpacingMigrated then
		cfg._stackSpacingMigrated = true
		if cfg.stackSpacing == nil or cfg.stackSpacing >= 8 then
			cfg.stackSpacing = 0
		end
	end

	ns.Debug.BindModule(self, "alertFrames", {
		title = L["Alert Frames"],
		dump = function()
			F.Print(format("  enable=%s hideTalkingHead=%s stackSpacing=%d", tostring(db().enable), tostring(db().hideTalkingHead), GetStackSpacing()))
			F.Print(format("  parentFrame=%s hooksInstalled=%s testFrames=%d position=%s", parentFrame and "yes" or "no", tostring(hooksInstalled), #testFrames, POSITION))
		end,
	})
end

function AlertFrames:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Alert Frames"], L["Move achievement/loot/reward alert popups to the top of the screen (reload to disable)."])
	local _, headInit = builder:Checkbox(category, self, "hideTalkingHead", L["Hide Talking Head"], L["Suppress the Talking Head dialog frame (reload to re-enable it)."])
	local _, spacingInit = builder:Slider(category, self, "stackSpacing", L["Stack Spacing"], L["Gap between stacked alerts. 0 = tight; negative overlaps art padding. Old default was 10."], -15, 10, 1)

	builder:DependsOn(headInit, enableInit)
	builder:DependsOn(spacingInit, enableInit)
end
